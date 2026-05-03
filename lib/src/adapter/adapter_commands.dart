import 'dart:io';

import 'package:args/command_runner.dart';

import '../cli/fluoh_command_runner.dart';
import '../context/fluoh_environment.dart';
import '../sdk/sdk_manager.dart';
import '../sdk/sdk_release.dart';
import 'adapter_git.dart';
import 'adapter_manifest.dart';
import 'repository_url.dart';

class CreateCommand extends Command<int> {
  CreateCommand({required this.environment, required OutputWriter stdout})
    : _stdout = stdout {
    argParser
      ..addOption('package', help: 'Package name to adapt in a monorepo.')
      ..addOption('path', help: 'Package path inside the upstream repository.')
      ..addOption(
        'output',
        help: 'Destination path for the adapter repository.',
      )
      ..addOption('sdk', help: 'Exact Flutter OHOS SDK tag to target.')
      ..addOption(
        'repository',
        help: 'Final FlutterOH adapter repository URL for origin and manifest.',
      );
  }

  final FluohEnvironment environment;
  final OutputWriter _stdout;

  @override
  String get name => 'create';

  @override
  String get description => 'Initialize a FlutterOH adapter repository.';

  @override
  String get invocation => 'fluoh pub create <upstream-url>';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) {
      usageException('Expected an upstream Git URL or path.');
    }

    final upstream = rest.single;
    final release = await _resolveSdkRelease();
    final destination = Directory(
      argResults!.option('output') ??
          '${environment.workingDirectory.path}/${repositoryNameFromUpstream(upstream)}',
    );
    var packagePath = argResults!.option('path') ?? '.';
    final packageName = argResults!.option('package');

    if (await destination.exists()) {
      usageException('Destination already exists: ${destination.path}');
    }

    await runGit(['clone', '--quiet', upstream, destination.path]);

    if (argResults!.option('path') == null && packageName != null) {
      packagePath = await findPackagePath(destination, packageName);
    }
    final package = await readPackageInfo(
      packageDirectory(destination, packagePath),
    );
    if (packageName != null && package.name != packageName) {
      usageException(
        'Package at $packagePath is ${package.name}, expected $packageName.',
      );
    }

    final repositoryUrl =
        argResults!.option('repository') ??
        defaultAdapterRepositoryUrl(package.name);
    await configureAdapterRemotes(destination, repositoryUrl);

    final upstreamRef = await currentHead(destination);
    final branch = adapterBranchForSdk(release.tag);
    await runGit(['checkout', '-b', branch], workingDirectory: destination);
    await writeAdapterManifest(
      destination: destination,
      package: package,
      upstream: upstream,
      upstreamRef: upstreamRef,
      packagePath: packagePath,
      sdkVersion: release.tag,
      branch: branch,
      flutterOhUrl: repositoryUrl,
    );
    await File('${destination.path}/FLUOH_ADAPT.md').writeAsString(
      [
        '# FlutterOH Adapter Checklist',
        '',
        '- [ ] Review upstream package metadata.',
        '- [ ] Implement OHOS platform changes.',
        '- [ ] Run package tests.',
        '- [ ] Run `fluoh pub release` when ready.',
        '',
      ].join('\n'),
    );

    await ensureGitIdentity(destination);
    await runGit([
      'add',
      'fluoh.yaml',
      'FLUOH_ADAPT.md',
    ], workingDirectory: destination);
    await runGit([
      'commit',
      '--quiet',
      '-m',
      'Initialize FlutterOH adapter',
    ], workingDirectory: destination);

    _stdout('Created adapter repository at ${destination.path}.');
    _stdout('Adapter branch: $branch.');
    _stdout('Origin: $repositoryUrl.');
    return 0;
  }

  Future<SdkRelease> _resolveSdkRelease() async {
    final manager = SdkManager(environment);
    final sdk = argResults!.option('sdk');
    if (sdk != null) {
      return manager.resolveRelease(sdk);
    }

    final releases = await manager.listReleases();
    final stable =
        releases
            .where((release) => release.channel == 'stable')
            .toList(growable: false)
          ..sort(_compareSdkReleasesDescending);
    if (stable.isNotEmpty) {
      return stable.first;
    }
    if (releases.isEmpty) {
      usageException('No SDK releases found in configured sources.');
    }
    return releases.first;
  }
}

class ReleaseCommand extends Command<int> {
  ReleaseCommand({required this.environment, required OutputWriter stdout})
    : _stdout = stdout {
    argParser
      ..addFlag(
        'push',
        negatable: false,
        help: 'Push the release tag to origin after creating or validating it.',
      )
      ..addOption(
        'source-update',
        help: 'Write a FlutterOH/pub package update into this source path.',
      );
  }

  final FluohEnvironment environment;
  final OutputWriter _stdout;

  @override
  String get name => 'release';

  @override
  String get description => 'Create a FlutterOH adapter release tag.';

  @override
  Future<int> run() async {
    final branch = await currentBranch(environment.workingDirectory);
    if (!branch.startsWith('ohos/')) {
      usageException('Release must run from an ohos/* adapter branch.');
    }

    final manifest = await readAdapterManifest(environment.workingDirectory);
    if (branch != manifest.branch) {
      usageException(
        'Current branch $branch does not match adapter branch '
        '${manifest.branch}.',
      );
    }
    await ensureCleanWorkingTree(environment.workingDirectory, 'Release');
    await _ensureSdkTagExists(manifest.sdkVersion);

    final expectedTag = releaseTagForAdapter(
      packageName: manifest.packageName,
      upstreamVersion: manifest.upstreamVersion,
      sdkVersion: manifest.sdkVersion,
      adapterVersion: manifest.adapterVersion,
    );
    final tag = manifest.releaseTag;
    if (tag != expectedTag) {
      usageException(
        'Release tag $tag does not match manifest values. Expected $expectedTag.',
      );
    }

    final existing = (await runGit(
      ['tag', '--list', tag],
      workingDirectory: environment.workingDirectory,
    )).stdout.toString().trim();
    if (existing == tag) {
      final tagCommit = (await runGit(
        ['rev-parse', '$tag^{}'],
        workingDirectory: environment.workingDirectory,
      )).stdout.toString().trim();
      final headCommit = await currentHead(environment.workingDirectory);
      if (tagCommit != headCommit) {
        usageException(
          'Release tag $tag already exists on a different commit.',
        );
      }
      _stdout('Release tag already exists: $tag.');
      if (argResults!.flag('push')) {
        await runGit([
          'push',
          'origin',
          tag,
        ], workingDirectory: environment.workingDirectory);
        _stdout('Pushed release tag $tag.');
      }
      await _writeSourceUpdateIfRequested(manifest, tag);
      return 0;
    }

    await runGit(['tag', tag], workingDirectory: environment.workingDirectory);
    if (argResults!.flag('push')) {
      await runGit([
        'push',
        'origin',
        tag,
      ], workingDirectory: environment.workingDirectory);
      _stdout('Pushed release tag $tag.');
    }
    await _writeSourceUpdateIfRequested(manifest, tag);
    _stdout('Created release tag $tag.');
    return 0;
  }

  Future<void> _ensureSdkTagExists(String sdkTag) async {
    final releases = await SdkManager(environment).listReleases();
    if (!releases.any((release) => release.tag == sdkTag)) {
      usageException('SDK tag $sdkTag was not found in configured sources.');
    }
  }

  Future<void> _writeSourceUpdateIfRequested(
    AdapterManifest manifest,
    String releaseTag,
  ) async {
    final sourcePath = argResults!.option('source-update');
    if (sourcePath == null || sourcePath.isEmpty) {
      return;
    }
    await _writePubSourceUpdate(
      Directory(sourcePath),
      manifest: manifest,
      releaseTag: releaseTag,
    );
    _stdout('Wrote pub source update for ${manifest.packageName}.');
  }
}

Future<void> _writePubSourceUpdate(
  Directory source, {
  required AdapterManifest manifest,
  required String releaseTag,
}) async {
  final packagesDirectory = Directory('${source.path}/packages');
  await packagesDirectory.create(recursive: true);
  await Directory(
    '${packagesDirectory.path}/manifests',
  ).create(recursive: true);

  final packagePath = manifest.upstreamPath ?? manifest.replacementPath;
  final manifestFile = File(
    '${packagesDirectory.path}/manifests/${manifest.packageName}.yaml',
  );
  await manifestFile.writeAsString(
    [
      'schema: 1',
      'package:',
      '  name: ${manifest.packageName}',
      '  repositoryUrl: ${manifest.flutterOhUrl}',
      '  upstreamUrl: ${manifest.upstreamUrl}',
      if (packagePath != null) '  packagePath: $packagePath',
      'releases:',
      '  - version: ${manifest.upstreamVersion}',
      if (manifest.upstreamRef != null)
        '    upstreamRef: ${manifest.upstreamRef}',
      '    sdk:',
      '      version: ${manifest.sdkVersion}',
      '      versions:',
      '        - ${manifest.sdkVersion}',
      '    status: ${manifest.status ?? 'experimental'}',
      '    sourceBranch: ${manifest.branch}',
      '    release:',
      '      version: ${manifest.adapterVersion}',
      '      tag: $releaseTag',
      '    replacement:',
      '      type: git',
      '      url: ${manifest.replacementUrl}',
      '      ref: $releaseTag',
      if (manifest.replacementPath != null)
        '      path: ${manifest.replacementPath}',
      '',
    ].join('\n'),
  );

  final registryFile = File('${packagesDirectory.path}/registry.yaml');
  if (!await registryFile.exists()) {
    await registryFile.writeAsString(
      [
        'schema: 1',
        'packages:',
        '  - name: ${manifest.packageName}',
        '    repositoryUrl: ${manifest.flutterOhUrl}',
        '    upstreamUrl: ${manifest.upstreamUrl}',
        if (packagePath != null) '    packagePath: $packagePath',
        '    status: ${manifest.status ?? 'experimental'}',
        '',
      ].join('\n'),
    );
    return;
  }

  final registry = await registryFile.readAsString();
  if (RegExp(
    r'^\s*-\s+name:\s+' + RegExp.escape(manifest.packageName) + r'\s*$',
    multiLine: true,
  ).hasMatch(registry)) {
    return;
  }
  await registryFile.writeAsString(
    [
      registry.trimRight(),
      '  - name: ${manifest.packageName}',
      '    repositoryUrl: ${manifest.flutterOhUrl}',
      '    upstreamUrl: ${manifest.upstreamUrl}',
      if (packagePath != null) '    packagePath: $packagePath',
      '    status: ${manifest.status ?? 'experimental'}',
      '',
    ].join('\n'),
  );
}

int _compareSdkReleasesDescending(SdkRelease a, SdkRelease b) {
  final byPublishedAt = (b.publishedAt ?? '').compareTo(a.publishedAt ?? '');
  if (byPublishedAt != 0) {
    return byPublishedAt;
  }
  return _compareNumericVersion(b.tag, a.tag);
}

int _compareNumericVersion(String a, String b) {
  final aParts = _numericParts(a);
  final bParts = _numericParts(b);
  final length = aParts.length > bParts.length ? aParts.length : bParts.length;
  for (var i = 0; i < length; i += 1) {
    final aPart = i < aParts.length ? aParts[i] : 0;
    final bPart = i < bParts.length ? bParts[i] : 0;
    final compared = aPart.compareTo(bPart);
    if (compared != 0) {
      return compared;
    }
  }
  return 0;
}

List<int> _numericParts(String version) {
  return RegExp(r'\d+')
      .allMatches(version)
      .map((match) => int.parse(match.group(0)!))
      .toList(growable: false);
}
