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
      ..addOption('sdk', help: 'Flutter OHOS SDK tag or version series.')
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
    final configuredSdkDirectory = await SdkProjectEnvironment(
      pubEnvironment,
    ).configure(release, writeFluohConfig: false);
    _stdout('Flutter OHOS SDK path: ${configuredSdkDirectory.path}.');
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
    await _writeAgentsInstructions(
      destination: destination,
      package: package,
      packagePath: packagePath,
      upstreamRef: upstreamRef,
      sdkVersion: release.tag,
      branch: branch,
    );
    await runGit([
      'add',
      '-f',
      'AGENTS.md',
      'FLUOH.md',
      'fluoh.yaml',
    ], workingDirectory: destination);

    _stdout('Created pub repository at ${destination.path}.');
    _stdout('Pub branch: $branch.');
    _stdout('Origin: $adapterUrl.');
    _stdout('Configured Flutter OHOS SDK ${release.tag}.');
    _stdout('See FLUOH.md and AGENTS.md for adaptation steps.');
    return 0;
  }

  Future<SdkRelease> _resolveSdkRelease() async {
    final manager = SdkManager(environment);
    final sdk = argResults!.option('sdk');
    if (sdk != null) {
      return manager.resolveRelease(sdk);
    }

    final releases = await manager.listReleases();
    if (releases.isEmpty) {
      usageException('No SDK releases found in configured sources.');
    }
    return SdkManager.latestRelease(releases, preferStable: true);
  }
}

Future<void> _writeAgentsInstructions({
  required Directory destination,
  required PubspecPackage package,
  required String packagePath,
  required String upstreamRef,
  required String sdkVersion,
  required String branch,
}) async {
  final file = File('${destination.path}/AGENTS.md');
  final existing = await file.exists() ? await file.readAsString() : null;
  final generated = _agentsInstructionsContent(
    package: package,
    packagePath: packagePath,
    upstreamRef: upstreamRef,
    sdkVersion: sdkVersion,
    branch: branch,
    includeTitle: existing == null || existing.trim().isEmpty,
  );

  if (existing == null || existing.trim().isEmpty) {
    await file.writeAsString(generated);
    return;
  }

  await file.writeAsString(
    '$existing${_markdownAppendSeparator(existing)}$generated',
  );
}

String _markdownAppendSeparator(String content) {
  if (content.endsWith('\n\n')) {
    return '';
  }
  if (content.endsWith('\n')) {
    return '\n';
  }
  return '\n\n';
}

String _agentsInstructionsContent({
  required PubspecPackage package,
  required String packagePath,
  required String upstreamRef,
  required String sdkVersion,
  required String branch,
  required bool includeTitle,
}) {
  return [
    if (includeTitle) '# AGENTS.md',
    if (includeTitle) '',
    '## FlutterOH Agent Instructions',
    '',
    'This repository adapts `${package.name}` ${package.version} for Flutter OHOS SDK `$sdkVersion`.',
    'Use this file as the AI working contract. Use `FLUOH.md` for the full maintainer workflow and `fluoh.yaml` as the metadata source of truth.',
    '',
    '## Fast Context',
    '',
    '- Package path: `$packagePath`',
    '- Upstream ref at creation: `$upstreamRef`',
    '- FlutterOH branch: `$branch`',
    '- FlutterOH metadata: `fluoh.yaml`',
    '- Full adaptation guide: `FLUOH.md`',
    '',
    '## Use fluoh',
    '',
    '- Prefer `fluoh flutter <args>` for Flutter commands so the SDK selected in `fluoh.yaml` is used.',
    '- Start with `fluoh flutter pub get` when dependencies may be stale.',
    '- Use `fluoh flutter analyze`, `fluoh flutter test`, and package-specific build or smoke commands when they apply.',
    '- Use `fluoh sdk list` to inspect available SDKs.',
    '- Do not run `fluoh sdk use` in this pub adapter repository; it is for Flutter apps and refuses to replace pub repository metadata.',
    '- When intentionally retargeting the adapter SDK, update `fluoh.yaml` and keep the branch and release metadata consistent.',
    '- `fluoh pub sync` updates the clean upstream branch from `upstream` and requires a clean worktree.',
    '- `fluoh pub adapt` merges the synchronized upstream branch into the current FlutterOH branch and refreshes `fluoh.yaml`; it also requires a clean worktree.',
    '- `fluoh pub release` is for final release validation and tagging after the adapter is ready.',
    '',
    '## Working Rules',
    '',
    '- Read `FLUOH.md`, `fluoh.yaml`, and the package `pubspec.yaml` before making code changes.',
    '- If the package path is not `.`, inspect that directory first and adapt verification commands to the upstream layout.',
    '- Keep upstream APIs and non-OHOS platform behavior compatible unless the adaptation requires a targeted change.',
    '- Prefer focused OHOS platform changes near the package implementation; avoid broad rewrites outside the package path.',
    '- Preserve local work, generated metadata, and upstream history. Do not delete `fluoh.yaml` or `FLUOH.md`.',
    '- Update `fluoh.yaml` when SDK, upstream ref, package path, status, release version, or adapter URL changes.',
    '- Commit local changes before running `fluoh pub sync`, `fluoh pub adapt`, or `fluoh pub release`.',
    '',
  ].join('\n');
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
