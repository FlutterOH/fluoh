import 'dart:io';

import 'package:args/command_runner.dart';

import '../../cli/fluoh_command_runner.dart';
import '../../context/fluoh_environment.dart';
import '../../sdk/sdk_manager.dart';
import '../../sdk/sdk_project_environment.dart';
import '../../sdk/sdk_release.dart';
import '../git/pub_git.dart';
import '../manifest/pub_manifest.dart';
import '../manifest/pubspec_package.dart';
import '../repository_url.dart';

class PubCreateCommand extends Command<int> {
  PubCreateCommand({required this.environment, required OutputWriter stdout})
    : _stdout = stdout {
    argParser
      ..addOption('package', help: 'Package name to adapt in a monorepo.')
      ..addOption('path', help: 'Package path inside the upstream repository.')
      ..addOption(
        'output',
        help: 'Destination path for the FlutterOH pub repository.',
      )
      ..addOption('sdk', help: 'Exact Flutter OHOS SDK tag to target.')
      ..addOption(
        'repo',
        abbr: 'r',
        help: 'Final FlutterOH pub repository URL for origin and manifest.',
      );
  }

  final FluohEnvironment environment;
  final OutputWriter _stdout;

  @override
  String get name => 'create';

  @override
  String get description => 'Initialize a FlutterOH pub repository.';

  @override
  String get invocation => 'fluoh pub create <upstream-url>';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) {
      usageException('Expected an upstream Git URL or path.');
    }

    final upstream = rest.single;
    _stdout('Resolving Flutter OHOS SDK.');
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

    _stdout('Cloning upstream repository into ${destination.path}.');
    await runGit(['clone', '--quiet', upstream, destination.path]);

    if (argResults!.option('path') == null && packageName != null) {
      packagePath = await findPackagePath(destination, packageName);
    }
    final package = await readPubspecPackage(
      packageDirectory(destination, packagePath),
    );
    if (packageName != null && package.name != packageName) {
      usageException(
        'Package at $packagePath is ${package.name}, expected $packageName.',
      );
    }

    final adapterUrl =
        argResults!.option('repo') ?? defaultPubRepositoryUrl(package.name);
    await configurePubRemotes(destination, adapterUrl);

    final upstreamRef = await currentHead(destination);
    final branch = ohosBranchForSdk(release.tag);
    await runGit(['checkout', '-b', branch], workingDirectory: destination);
    final pubEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: destination,
      processEnvironment: environment.processEnvironment,
    );
    final sdkDirectory = SdkManager(pubEnvironment).sdkDirectory(release.tag);
    if (await sdkDirectory.exists()) {
      _stdout('Using installed Flutter OHOS SDK ${release.tag}.');
    } else {
      _stdout(
        'Installing Flutter OHOS SDK ${release.tag}; this may take a while.',
      );
    }
    await SdkProjectEnvironment(
      pubEnvironment,
    ).configure(release, writeFluohConfig: false);
    await _ignoreFvmFlutterSdk(destination);
    await writePubManifest(
      destination: destination,
      package: package,
      upstream: upstream,
      upstreamRef: upstreamRef,
      packagePath: packagePath,
      sdkVersion: release.tag,
      branch: branch,
      adapterUrl: adapterUrl,
    );
    await File('${destination.path}/FLUOH.md').writeAsString(
      _adaptationGuideContent(
        package: package,
        packagePath: packagePath,
        upstreamRef: upstreamRef,
        sdkVersion: release.tag,
        branch: branch,
      ),
    );
    await runGit([
      'add',
      '-f',
      'FLUOH.md',
      'fluoh.yaml',
      '.fvmrc',
      '.gitignore',
    ], workingDirectory: destination);

    _stdout('Created pub repository at ${destination.path}.');
    _stdout('Pub branch: $branch.');
    _stdout('Origin: $adapterUrl.');
    _stdout('Configured Flutter OHOS SDK ${release.tag}.');
    _stdout('See FLUOH.md for adaptation steps.');
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

String _adaptationGuideContent({
  required PubspecPackage package,
  required String packagePath,
  required String upstreamRef,
  required String sdkVersion,
  required String branch,
}) {
  return [
    '# FlutterOH Adaptation Guide',
    '',
    'This repository adapts `${package.name}` ${package.version} for Flutter OHOS SDK `$sdkVersion`.',
    '',
    '## Metadata',
    '',
    '- `fluoh.yaml` records the upstream package, FlutterOH repository, SDK target, and release metadata.',
    '- Package path: `$packagePath`',
    '- Upstream ref: `$upstreamRef`',
    '- FlutterOH branch: `$branch`',
    '',
    '## Adaptation Workflow',
    '',
    '1. Review the upstream package metadata and platform implementation.',
    '2. Implement or update the OHOS platform code for `${package.name}`.',
    '3. Keep `fluoh.yaml` in sync when upstream, SDK, status, or release version values change.',
    '4. The generated files are already staged.',
    '5. You can continue adapting and commit everything together.',
    '6. Commit before running `fluoh pub sync`, `fluoh pub adapt`, or `fluoh pub release` because those commands require a clean worktree.',
    '7. Run the package tests and any FlutterOH verification needed by the adapter.',
    '8. Commit adapter changes with the maintainer Git identity.',
    '9. Run `fluoh pub release` when the adapter is ready.',
    '',
  ].join('\n');
}

Future<void> _ignoreFvmFlutterSdk(Directory repository) async {
  const entry = '.fvm/flutter_sdk';
  final gitignore = File('${repository.path}/.gitignore');
  if (!await gitignore.exists()) {
    await gitignore.writeAsString('$entry\n');
    return;
  }

  final content = await gitignore.readAsString();
  final lines = content.split('\n').map((line) => line.trim()).toSet();
  if (lines.contains(entry)) {
    return;
  }

  final prefix = content.isEmpty || content.endsWith('\n')
      ? content
      : '$content\n';
  await gitignore.writeAsString('$prefix$entry\n');
}
