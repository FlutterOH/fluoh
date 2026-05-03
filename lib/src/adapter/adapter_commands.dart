import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:yaml/yaml.dart';

import '../cli/fluoh_command_runner.dart';
import '../context/fluoh_environment.dart';
import '../sdk/sdk_manager.dart';
import '../sdk/sdk_release.dart';

const _defaultFlutterOhRepositoryUrl = 'git@github.com:FlutterOH/fluoh.git';

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
      ..addOption('sdk-series', help: 'Flutter OHOS SDK series to target.')
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
  String get invocation => 'fluoh create <upstream-url>';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) {
      usageException('Expected an upstream Git URL or path.');
    }

    final upstream = rest.single;
    final repositoryUrl =
        argResults!.option('repository') ?? _defaultFlutterOhRepositoryUrl;
    final release = await _resolveSdkRelease();
    final destination = Directory(
      argResults!.option('output') ??
          '${environment.workingDirectory.path}/${_defaultRepositoryName(upstream)}',
    );
    var packagePath = argResults!.option('path') ?? '.';
    final packageName = argResults!.option('package');

    if (await destination.exists()) {
      usageException('Destination already exists: ${destination.path}');
    }

    await _git(['clone', '--quiet', upstream, destination.path]);
    await _git([
      'checkout',
      '-b',
      'ohos-${release.line}',
    ], workingDirectory: destination);

    if (argResults!.option('path') == null && packageName != null) {
      packagePath = await _findPackagePath(destination, packageName);
    }
    final package = await _readPackageInfo(
      _packageDirectory(destination, packagePath),
    );
    if (packageName != null && package.name != packageName) {
      usageException(
        'Package at $packagePath is ${package.name}, expected $packageName.',
      );
    }
    await _configureAdapterRemotes(destination, repositoryUrl);
    final upstreamRef = (await _git([
      'rev-parse',
      'HEAD',
    ], workingDirectory: destination)).stdout.toString().trim();
    await _writeAdapterManifest(
      destination: destination,
      package: package,
      upstream: upstream,
      upstreamRef: upstreamRef,
      packagePath: packagePath,
      release: release,
      flutterOhUrl: repositoryUrl,
    );
    await File('${destination.path}/FLUOH_ADAPT.md').writeAsString(
      [
        '# FlutterOH Adapter Checklist',
        '',
        '- [ ] Review upstream package metadata.',
        '- [ ] Implement OHOS platform changes.',
        '- [ ] Run package tests.',
        '- [ ] Run `fluoh release` when ready.',
        '',
      ].join('\n'),
    );

    await _ensureGitIdentity(destination);
    await _git([
      'add',
      'fluoh.yaml',
      'FLUOH_ADAPT.md',
    ], workingDirectory: destination);
    await _git([
      'commit',
      '--quiet',
      '-m',
      'Initialize FlutterOH adapter',
    ], workingDirectory: destination);

    _stdout('Created adapter repository at ${destination.path}.');
    return 0;
  }

  Future<SdkRelease> _resolveSdkRelease() async {
    final manager = SdkManager(environment);
    final sdk = argResults!.option('sdk');
    if (sdk != null) {
      return manager.resolveRelease(sdk);
    }
    final sdkSeries = argResults!.option('sdk-series');
    if (sdkSeries != null) {
      return manager.resolveRelease(sdkSeries);
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
    final branch = (await _git(
      ['branch', '--show-current'],
      workingDirectory: environment.workingDirectory,
    )).stdout.toString().trim();
    if (!branch.startsWith('ohos-')) {
      usageException('Release must run from an ohos-* branch.');
    }

    final manifest = await _readAdapterManifest(environment.workingDirectory);
    final expectedBranch = 'ohos-${manifest.sdkLine}';
    if (branch != expectedBranch) {
      usageException(
        'Current branch $branch does not match sdkLine ${manifest.sdkLine}.',
      );
    }
    await _ensureCleanWorkingTree(environment.workingDirectory);
    await _ensureSdkTagExists(manifest.sdkTag);

    final sdkBase = manifest.sdkTag.split('-ohos-').first;
    final expectedTag =
        '${manifest.packageName}-v${manifest.upstreamVersion}-ohos-$sdkBase-${manifest.adapterVersion}';
    final tag = manifest.releaseTag ?? expectedTag;
    if (tag != expectedTag) {
      usageException(
        'Release tag $tag does not match manifest values. Expected $expectedTag.',
      );
    }

    final existing = (await _git(
      ['tag', '--list', tag],
      workingDirectory: environment.workingDirectory,
    )).stdout.toString().trim();
    if (existing == tag) {
      final tagCommit = (await _git(
        ['rev-parse', '$tag^{}'],
        workingDirectory: environment.workingDirectory,
      )).stdout.toString().trim();
      final headCommit = (await _git(
        ['rev-parse', 'HEAD'],
        workingDirectory: environment.workingDirectory,
      )).stdout.toString().trim();
      if (tagCommit != headCommit) {
        usageException(
          'Release tag $tag already exists on a different commit.',
        );
      }
      _stdout('Release tag already exists: $tag.');
      if (argResults!.flag('push')) {
        await _git([
          'push',
          'origin',
          tag,
        ], workingDirectory: environment.workingDirectory);
        _stdout('Pushed release tag $tag.');
      }
      await _writeSourceUpdateIfRequested(manifest, tag);
      return 0;
    }

    await _git(['tag', tag], workingDirectory: environment.workingDirectory);
    if (argResults!.flag('push')) {
      await _git([
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

Future<PackageInfo> _readPackageInfo(Directory repository) async {
  final pubspec = File('${repository.path}/pubspec.yaml');
  if (!await pubspec.exists()) {
    throw UsageException('Missing pubspec.yaml in upstream repository.', '');
  }
  final yaml = loadYaml(await pubspec.readAsString());
  if (yaml is! YamlMap) {
    throw UsageException('pubspec.yaml must contain a YAML map.', '');
  }
  final name = yaml['name'];
  final version = yaml['version'];
  if (name is! String || version is! String) {
    throw UsageException('pubspec.yaml must contain name and version.', '');
  }
  return PackageInfo(name: name, version: version);
}

Future<void> _writeAdapterManifest({
  required Directory destination,
  required PackageInfo package,
  required String upstream,
  required String upstreamRef,
  required String packagePath,
  required SdkRelease release,
  required String? flutterOhUrl,
}) async {
  const adapterVersion = '0.1.0';
  final tag = _releaseTag(
    packageName: package.name,
    upstreamVersion: package.version,
    sdkTag: release.tag,
    adapterVersion: adapterVersion,
  );
  final path = packagePath == '.' || packagePath.isEmpty ? null : packagePath;
  final quotedLine = '"${release.line}"';
  await File('${destination.path}/fluoh.yaml').writeAsString(
    [
      'schema: 1',
      '',
      'package:',
      '  name: ${package.name}',
      '  upstream:',
      '    type: git',
      '    url: $upstream',
      if (path != null) '    path: $path',
      '    ref: $upstreamRef',
      '    version: ${package.version}',
      '',
      'flutteroh:',
      '  url: ${flutterOhUrl ?? 'null'}',
      '  branch: ohos-${release.line}',
      '  release:',
      '    version: $adapterVersion',
      '    tag: $tag',
      '',
      'sdk:',
      '  line: $quotedLine',
      '  versions:',
      '    - ${release.tag}',
      '',
      'status: experimental',
      '',
      'replacement:',
      '  source: git',
      '  url: ${flutterOhUrl ?? 'null'}',
      '  ref: $tag',
      if (path != null) '  path: $path',
      '',
      'notes:',
      '  summary: Adds OpenHarmony platform implementation.',
      '',
    ].join('\n'),
  );
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

  final repository = manifest.flutterOhUrl ?? manifest.replacementUrl;
  final packagePath = manifest.upstreamPath ?? manifest.replacementPath;
  final manifestFile = File(
    '${packagesDirectory.path}/manifests/${manifest.packageName}.yaml',
  );
  await manifestFile.writeAsString(
    [
      'schema: 1',
      'package:',
      '  name: ${manifest.packageName}',
      if (repository != null) '  repositoryUrl: $repository',
      if (manifest.upstreamUrl != null)
        '  upstreamUrl: ${manifest.upstreamUrl}',
      if (packagePath != null) '  packagePath: $packagePath',
      'releases:',
      '  - version: ${manifest.upstreamVersion}',
      if (manifest.upstreamRef != null)
        '    upstreamRef: ${manifest.upstreamRef}',
      '    sdk:',
      '      versionSeries: "${manifest.sdkLine}"',
      '      versions:',
      '        - ${manifest.sdkTag}',
      '    status: ${manifest.status ?? 'experimental'}',
      '    sourceBranch: ohos-${manifest.sdkLine}',
      '    release:',
      '      version: ${manifest.adapterVersion}',
      '      tag: $releaseTag',
      '    replacement:',
      '      type: git',
      '      url: ${repository ?? 'null'}',
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
        if (repository != null) '    repositoryUrl: $repository',
        if (manifest.upstreamUrl != null)
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
      if (repository != null) '    repositoryUrl: $repository',
      if (manifest.upstreamUrl != null)
        '    upstreamUrl: ${manifest.upstreamUrl}',
      if (packagePath != null) '    packagePath: $packagePath',
      '    status: ${manifest.status ?? 'experimental'}',
      '',
    ].join('\n'),
  );
}

String _releaseTag({
  required String packageName,
  required String upstreamVersion,
  required String sdkTag,
  required String adapterVersion,
}) {
  final sdkBase = sdkTag.split('-ohos-').first;
  return '$packageName-v$upstreamVersion-ohos-$sdkBase-$adapterVersion';
}

Directory _packageDirectory(Directory repository, String packagePath) {
  if (packagePath == '.' || packagePath.isEmpty) {
    return repository;
  }
  return Directory('${repository.path}/$packagePath');
}

Future<String> _findPackagePath(
  Directory repository,
  String packageName,
) async {
  await for (final entity in repository.list(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('/pubspec.yaml')) {
      continue;
    }
    if (entity.path.contains('/.git/')) {
      continue;
    }
    final package = await _readPackageInfo(entity.parent);
    if (package.name == packageName) {
      final relative = entity.parent.path.substring(repository.path.length);
      final normalized = relative.startsWith('/')
          ? relative.substring(1)
          : relative;
      return normalized.isEmpty ? '.' : normalized;
    }
  }
  throw UsageException(
    'Package $packageName was not found in upstream repository.',
    '',
  );
}

Future<AdapterManifest> _readAdapterManifest(Directory repository) async {
  final manifest = File('${repository.path}/fluoh.yaml');
  if (!await manifest.exists()) {
    throw UsageException('Missing fluoh.yaml.', '');
  }
  final yaml = loadYaml(await manifest.readAsString());
  if (yaml is! YamlMap) {
    throw UsageException('fluoh.yaml must contain a YAML map.', '');
  }

  String requiredString(YamlMap map, String key) {
    final value = map[key];
    if (value == null || '$value'.isEmpty) {
      throw UsageException('fluoh.yaml missing "$key".', '');
    }
    return '$value';
  }

  String? optionalString(YamlMap map, String key) {
    final value = map[key];
    if (value == null || '$value'.isEmpty) {
      return null;
    }
    return '$value';
  }

  if (yaml['schema'] != null && yaml['package'] is YamlMap) {
    final package = yaml['package'] as YamlMap;
    final upstream = package['upstream'];
    final sdk = yaml['sdk'];
    final flutteroh = yaml['flutteroh'];
    if (upstream is! YamlMap || sdk is! YamlMap || flutteroh is! YamlMap) {
      throw UsageException('fluoh.yaml has an incomplete adapter schema.', '');
    }
    final release = flutteroh['release'];
    final replacement = yaml['replacement'];
    if (release is! YamlMap) {
      throw UsageException('fluoh.yaml missing flutteroh.release.', '');
    }
    if (replacement is! YamlMap) {
      throw UsageException('fluoh.yaml missing replacement.', '');
    }
    final versions = sdk['versions'];
    if (versions is! YamlList || versions.isEmpty) {
      throw UsageException('fluoh.yaml sdk.versions must not be empty.', '');
    }

    return AdapterManifest(
      packageName: requiredString(package, 'name'),
      upstreamVersion: requiredString(upstream, 'version'),
      sdkLine: requiredString(sdk, 'line'),
      sdkTag: '${versions.first}',
      adapterVersion: requiredString(release, 'version'),
      releaseTag: requiredString(release, 'tag'),
      upstreamUrl: optionalString(upstream, 'url'),
      upstreamPath: optionalString(upstream, 'path'),
      upstreamRef: optionalString(upstream, 'ref'),
      flutterOhUrl: optionalString(flutteroh, 'url'),
      replacementUrl: optionalString(replacement, 'url'),
      replacementPath: optionalString(replacement, 'path'),
      status: optionalString(yaml, 'status'),
    );
  }

  return AdapterManifest(
    packageName: requiredString(yaml, 'package'),
    upstreamVersion: requiredString(yaml, 'upstreamVersion'),
    sdkLine: requiredString(yaml, 'sdkLine'),
    sdkTag: requiredString(yaml, 'sdkTag'),
    adapterVersion: '${yaml['adapterVersion'] ?? 1}',
  );
}

Future<void> _ensureCleanWorkingTree(Directory repository) async {
  final status = (await _git([
    'status',
    '--porcelain',
  ], workingDirectory: repository)).stdout.toString().trim();
  if (status.isNotEmpty) {
    throw UsageException(
      'Release requires the adapter working tree must be clean.',
      '',
    );
  }
}

Future<void> _configureAdapterRemotes(
  Directory destination,
  String repositoryUrl,
) async {
  final existingOrigin = await _git(
    ['remote', 'get-url', 'origin'],
    workingDirectory: destination,
    allowFailure: true,
  );
  if (existingOrigin.exitCode == 0 &&
      existingOrigin.stdout.toString().trim().isNotEmpty) {
    await _git([
      'remote',
      'rename',
      'origin',
      'upstream',
    ], workingDirectory: destination);
  }
  await _git([
    'remote',
    'add',
    'origin',
    repositoryUrl,
  ], workingDirectory: destination);
}

Future<void> _ensureGitIdentity(Directory repository) async {
  final email = await _git(
    ['config', '--get', 'user.email'],
    workingDirectory: repository,
    allowFailure: true,
  );
  if (email.exitCode != 0 || email.stdout.toString().trim().isEmpty) {
    await _git([
      'config',
      'user.email',
      'fluoh@example.invalid',
    ], workingDirectory: repository);
  }

  final name = await _git(
    ['config', '--get', 'user.name'],
    workingDirectory: repository,
    allowFailure: true,
  );
  if (name.exitCode != 0 || name.stdout.toString().trim().isEmpty) {
    await _git(['config', 'user.name', 'fluoh'], workingDirectory: repository);
  }
}

Future<ProcessResult> _git(
  List<String> arguments, {
  Directory? workingDirectory,
  bool allowFailure = false,
}) async {
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: workingDirectory?.path,
  );
  if (!allowFailure && result.exitCode != 0) {
    throw UsageException(
      'git ${arguments.join(' ')} failed:\n${result.stderr}',
      '',
    );
  }
  return result;
}

String _defaultRepositoryName(String upstream) {
  final trimmed = upstream.endsWith('/')
      ? upstream.substring(0, upstream.length - 1)
      : upstream;
  final name = trimmed.split('/').last;
  return name.endsWith('.git') ? name.substring(0, name.length - 4) : name;
}

class PackageInfo {
  const PackageInfo({required this.name, required this.version});

  final String name;
  final String version;
}

class AdapterManifest {
  const AdapterManifest({
    required this.packageName,
    required this.upstreamVersion,
    required this.sdkLine,
    required this.sdkTag,
    required this.adapterVersion,
    this.releaseTag,
    this.upstreamUrl,
    this.upstreamPath,
    this.upstreamRef,
    this.flutterOhUrl,
    this.replacementUrl,
    this.replacementPath,
    this.status,
  });

  final String packageName;
  final String upstreamVersion;
  final String sdkLine;
  final String sdkTag;
  final String adapterVersion;
  final String? releaseTag;
  final String? upstreamUrl;
  final String? upstreamPath;
  final String? upstreamRef;
  final String? flutterOhUrl;
  final String? replacementUrl;
  final String? replacementPath;
  final String? status;
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
