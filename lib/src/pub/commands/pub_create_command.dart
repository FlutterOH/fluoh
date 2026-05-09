import 'dart:io';

import 'package:args/command_runner.dart';

import '../../cli/fluoh_command_runner.dart';
import '../../cli/terminal_output.dart';
import '../../context/fluoh_environment.dart';
import '../../sdk/sdk_manager.dart';
import '../../sdk/sdk_project_environment.dart';
import '../../sdk/sdk_release.dart';
import '../../testing/test_workspace.dart';
import '../git/pub_git.dart';
import '../manifest/pub_manifest.dart';
import '../manifest/pubspec_package.dart';
import '../repository_url.dart';

class PubCreateCommand extends Command<int> {
  PubCreateCommand({
    required this.environment,
    required OutputWriter stdout,
    required OutputWriter stderr,
    TerminalOutput? output,
  }) : _stdout = stdout,
       _stderr = stderr {
    _output = output ?? TerminalOutput(stdout: stdout, stderr: stderr);
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
  final OutputWriter _stderr;
  late final TerminalOutput _output;

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
    _output.step('Resolving Flutter OHOS SDK.');
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

    await _output.withProgress(
      'Cloning upstream repository into ${_output.style.path(destination.path)}.',
      () => runGit(['clone', '--quiet', upstream, destination.path]),
      showWhenPlain: true,
    );

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
    final sdkInstalled = await sdkDirectory.exists();
    if (sdkInstalled) {
      _output.info('Using installed Flutter OHOS SDK ${release.tag}.');
    }
    final configuredSdkDirectory = await _output.withProgress(
      sdkInstalled
          ? 'Configuring Flutter OHOS SDK ${release.tag}.'
          : 'Installing Flutter OHOS SDK ${release.tag}; this may take a while.',
      () => SdkProjectEnvironment(
        pubEnvironment,
      ).configure(release, writeFluohConfig: false),
      showWhenPlain: !sdkInstalled,
    );
    _output.info(
      'Flutter OHOS SDK path: ${_output.style.path(configuredSdkDirectory.path)}.',
    );
    await writePubManifest(
      destination: destination,
      package: package,
      upstream: upstream,
      upstreamRef: upstreamRef,
      packagePath: packagePath,
      sdkVersion: release.tag,
      branch: branch,
      adapterUrl: adapterUrl,
      releaseVersion: _initialReleaseVersion,
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
    await File('${destination.path}/FLUOH_CHANGELOG.md').writeAsString(
      _fluohChangelogContent(
        package: package,
        sdkVersion: release.tag,
        releaseVersion: _initialReleaseVersion,
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
    await _writeClaudeInstructions(destination);
    final testInitResult = await initializeFluohTestWorkspace(
      environment: pubEnvironment,
      stdout: _stdout,
      stderr: _stderr,
      output: _output,
    );
    await runGit([
      'add',
      '-f',
      'AGENTS.md',
      'CLAUDE.md',
      'FLUOH.md',
      'FLUOH_CHANGELOG.md',
      'fluoh.yaml',
    ], workingDirectory: destination);
    if (testInitResult.created) {
      await runGit(['add', 'fluoh_test'], workingDirectory: destination);
    }

    _output.success(
      'Created pub repository at ${_output.style.path(destination.path)}.',
    );
    _output.info('Pub branch: $branch.');
    _output.info('Origin: ${_output.style.url(adapterUrl)}.');
    _output.success('Configured Flutter OHOS SDK ${release.tag}.');
    if (testInitResult.created) {
      _output.next(
        'See FLUOH.md, AGENTS.md, and fluoh_test/ for adaptation steps.',
      );
    } else {
      _output.next('See FLUOH.md and AGENTS.md for adaptation steps.');
    }
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

const _initialReleaseVersion = '0.1.0';

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

const _claudeAgentsImport = '@AGENTS.md';

Future<void> _writeClaudeInstructions(Directory destination) async {
  final file = File('${destination.path}/CLAUDE.md');
  if (!await file.exists()) {
    await file.writeAsString('$_claudeAgentsImport\n');
    return;
  }

  final existing = await file.readAsString();
  if (existing.trim().isEmpty) {
    await file.writeAsString('$_claudeAgentsImport\n');
    return;
  }
  if (_importsAgentsInstructions(existing)) {
    return;
  }

  final separator = existing.startsWith('\n') ? '' : '\n';
  await file.writeAsString('$_claudeAgentsImport\n$separator$existing');
}

bool _importsAgentsInstructions(String content) {
  return content.split('\n').any((line) => line.trim() == _claudeAgentsImport);
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
    '## FlutterOH Context',
    '',
    'This repository adapts `${package.name}` ${package.version} for Flutter OHOS SDK `$sdkVersion`.',
    '',
    '- Package path: `$packagePath`.',
    '- Upstream ref at creation: `$upstreamRef`',
    '- FlutterOH branch: `$branch`',
    '- Metadata: `fluoh.yaml`.',
    '- Release notes: `FLUOH_CHANGELOG.md`.',
    '',
    '## Working Rules',
    '',
    '- Use `fluoh flutter <args>` so commands use the SDK selected in `fluoh.yaml`; start with `fluoh pub get` when dependencies may be stale.',
    '- Keep OHOS adaptation changes focused near `$packagePath`; preserve upstream APIs and non-OHOS behavior.',
    '- Keep `fluoh_test/test` for automated adapter checks and `fluoh_test/example` for manual platform verification.',
    '- Update `fluoh.yaml` when SDK, upstream ref, package path, status, release version, or adapter URL changes.',
    '- Update `FLUOH_CHANGELOG.md` for FlutterOH release notes.',
    '- Run `fluoh test run` before release. Commit before `fluoh pub sync` or `fluoh pub release` because both require a clean worktree.',
    '',
    '## Before Commit',
    '',
    '- Review `git status --short --ignored=matching` and staged files before committing.',
    '- Do not commit local paths, IDE metadata, generated build outputs, caches, certificates, private keys, passwords, or signing profiles.',
    '- Do not commit team-specific iOS signing state such as `DEVELOPMENT_TEAM`, `PROVISIONING_PROFILE_SPECIFIER`, profile UUIDs, or non-generic `CODE_SIGN_IDENTITY` values.',
    '- OHOS `signingConfigs` may exist for local testing, but tracked files must not contain real certificate paths, passwords, or private signing material. Commit empty or placeholder signing settings only.',
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
    '# FlutterOH Adaptation',
    '',
    'This repository adapts `${package.name}` ${package.version} for Flutter OHOS SDK `$sdkVersion`.',
    '',
    '## Metadata',
    '',
    '- `fluoh.yaml` records the upstream package, FlutterOH repository, SDK target, and release metadata.',
    '- Package path: `$packagePath`',
    '- Upstream ref: `$upstreamRef`',
    '- FlutterOH branch: `$branch`',
    '- Metadata: `fluoh.yaml`',
    '- Release notes: `FLUOH_CHANGELOG.md`',
    '',
    '## Next Steps',
    '',
    '1. Implement the OHOS platform code for `${package.name}`.',
    '2. Keep `fluoh_test/test` for automated checks and `fluoh_test/example` for manual verification.',
    '3. Update `fluoh.yaml` and `FLUOH_CHANGELOG.md` when release metadata changes.',
    '4. Run `fluoh test run` before release.',
    '5. Commit before `fluoh pub sync` or `fluoh pub release`; both require a clean worktree.',
    '',
    '## Before Commit',
    '',
    '- Review `git status --short --ignored=matching`.',
    '- Keep local paths, IDE files, generated outputs, certificates, private keys, passwords, Android keystore config, and iOS team/profile signing values out of committed files.',
    '- OHOS `signingConfigs` can be used locally; commit only empty or placeholder signing settings.',
    '',
  ].join('\n');
}

String _fluohChangelogContent({
  required PubspecPackage package,
  required String sdkVersion,
  required String releaseVersion,
}) {
  return [
    '# FlutterOH Changelog',
    '',
    '## $releaseVersion',
    '',
    '- Initial adapter for `${package.name}` ${package.version} on Flutter OHOS SDK `$sdkVersion`.',
    '',
  ].join('\n');
}
