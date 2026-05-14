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
import '../pub_license_checker.dart';
import '../pub_repository_docs.dart';
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
      ..addMultiOption(
        'path',
        help:
            'Package path inside a monorepo upstream repository. Can be repeated.',
      )
      ..addOption(
        'output',
        help: 'Destination path for the FlutterOH pub repository.',
      )
      ..addOption('sdk', help: 'Flutter OHOS SDK version or version series.')
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
  String get invocation => 'fluoh pub create <upstream>';

  @override
  String get usage => '$description\n\n$_usageWithoutDescription';

  @override
  void printUsage() {
    _output.write(usage);
  }

  @override
  Never usageException(String message) {
    throw UsageException(message, _usageWithoutDescription);
  }

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) {
      usageException('Expected <upstream>: Git URL or local Git repo path.');
    }

    final upstream = rest.single;
    _output.step('Resolving Flutter OHOS SDK.');
    final release = await _resolveSdkRelease();
    final packagePaths = argResults!.multiOption('path');
    final destination = Directory(
      argResults!.option('output') ??
          '${environment.workingDirectory.path}/${repositoryNameFromUpstream(upstream)}',
    );

    if (await destination.exists()) {
      usageException('Destination already exists: ${destination.path}');
    }

    _output.step(
      'Cloning upstream repository into ${_output.style.path(destination.path)}...',
    );
    await runGit(['clone', '--quiet', upstream, destination.path]);

    final selectedPackages = await _selectPackages(
      repository: destination,
      packagePaths: packagePaths,
    );
    for (final selected in selectedPackages) {
      if (selected.path != '.') {
        _output.info(
          'Selected package ${selected.package.name} at ${selected.path}.',
        );
      }
    }
    final docPackages = [
      for (final selected in selectedPackages)
        _docPackageForSelection(
          selectedPackages: selectedPackages,
          selectedPackage: selected,
        ),
    ];

    final repositoryUrl =
        argResults!.option('repo') ??
        defaultPubRepositoryUrl(
          _defaultImplementationRepositoryName(upstream, selectedPackages),
        );
    await configurePubRemotes(destination, repositoryUrl);

    final upstreamBranch = await upstreamDefaultBranch(destination);
    final branch = flutterOhosBranchForSdk(release.tag);
    await runGit(['checkout', '-b', branch], workingDirectory: destination);
    final pubEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: destination,
      processEnvironment: environment.processEnvironment,
    );
    _output.blank();
    final sdkDirectory = SdkManager(pubEnvironment).sdkDirectory(release.tag);
    final sdkInstalled = await sdkDirectory.exists();
    if (sdkInstalled) {
      _output.info('Using installed Flutter OHOS SDK ${release.tag}.');
    }
    final projectEnvironment = SdkProjectEnvironment(pubEnvironment);
    final configuredSdkDirectory = await _output.withProgress(
      sdkInstalled
          ? 'Configuring Flutter OHOS SDK ${release.tag}.'
          : 'Installing Flutter OHOS SDK ${release.tag}; this may take a while.',
      () => projectEnvironment.configure(release, writeFluohConfig: false),
      showWhenPlain: !sdkInstalled,
    );
    _output.info(
      'Flutter OHOS SDK path: ${_output.style.path(configuredSdkDirectory.path)}.',
    );
    final ideLink = await projectEnvironment.linkIdeSdk(configuredSdkDirectory);
    _output.info('IDE Flutter SDK link: ${_output.style.path(ideLink.path)}.');
    _output.next('Use this link as your IDE Flutter SDK path.');
    _output.blank();
    await writePubManifestFile(
      destination,
      PubManifest(
        name: _defaultImplementationRepositoryName(upstream, selectedPackages),
        sdkVersion: release.tag,
        repositoryBranch: branch,
        upstreamUrl: upstream,
        upstreamBranch: upstreamBranch,
        repositoryUrl: repositoryUrl,
        packages: [
          for (final selected in selectedPackages)
            PubManifestPackage(
              name: selected.package.name,
              upstreamVersion: selected.package.version,
              version: initialPubReleaseVersion,
              repositoryPath: selected.path,
              upstreamPath: selected.path,
              status: 'experimental',
            ),
        ],
      ),
    );
    await File('${destination.path}/FLUOH.md').writeAsString(
      pubImplementationGuideContent(
        packages: docPackages,
        upstreamBranch: upstreamBranch,
        sdkVersion: release.tag,
        branch: branch,
        includeTitle: true,
      ),
    );
    await File('${destination.path}/FLUOH_CHANGELOG.md').writeAsString(
      pubFluohChangelogContent(
        packages: docPackages,
        sdkVersion: release.tag,
        releaseVersion: initialPubReleaseVersion,
      ),
    );
    await writeOrAppendPubAgentsInstructions(
      destination: destination,
      packages: docPackages,
      upstreamBranch: upstreamBranch,
      sdkVersion: release.tag,
      branch: branch,
    );
    await _writeClaudeInstructions(destination);
    final testInitResults = <FluohTestInitResult>[];
    for (final selected in selectedPackages) {
      testInitResults.add(
        await initializeFluohTestWorkspace(
          environment: pubEnvironment,
          stdout: _stdout,
          stderr: _stderr,
          output: _output,
          packageName: selected.package.name,
        ),
      );
    }
    final createdTestWorkspaces = testInitResults.any(
      (result) => result.created,
    );
    await runGit([
      'add',
      '-f',
      'AGENTS.md',
      'CLAUDE.md',
      'FLUOH.md',
      'FLUOH_CHANGELOG.md',
      '.gitignore',
      'fluoh.yaml',
    ], workingDirectory: destination);
    if (createdTestWorkspaces) {
      await runGit(['add', 'fluoh_test'], workingDirectory: destination);
    }

    final licenseWarnings = <String>[];
    for (final selected in selectedPackages) {
      licenseWarnings.addAll(
        await pubLicenseWarnings(
          repository: destination,
          packagePath: selected.path,
          packageName: selected.package.name,
        ),
      );
    }
    _output.blank();
    for (final warning in licenseWarnings) {
      _output.warningError(warning);
    }
    if (licenseWarnings.isNotEmpty) {
      _output.blank();
    }

    _output.success(
      'Created pub repository at ${_output.style.path(destination.path)}.',
    );
    _output.info('Pub branch: $branch.');
    _output.info('Origin: ${_output.style.url(repositoryUrl)}.');
    _output.success('Configured Flutter OHOS SDK ${release.tag}.');
    if (createdTestWorkspaces) {
      _output.next(
        'See FLUOH.md, AGENTS.md, and fluoh_test/ for implementation steps.',
      );
    } else {
      _output.next('See FLUOH.md and AGENTS.md for implementation steps.');
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
      usageException('No SDK versions found in configured sources.');
    }
    return SdkManager.latestRelease(releases, preferStable: true);
  }

  String get _usageWithoutDescription {
    return [
      'Usage: $invocation',
      'Upstream: Git URL or local Git repo path.',
      '',
      argParser.usage,
      '',
      'Run "${runner!.executableName} help" to see global options.',
    ].join('\n');
  }
}

class _SelectedPackage {
  const _SelectedPackage({required this.package, required this.path});

  final PubspecPackage package;
  final String path;
}

Future<List<_SelectedPackage>> _selectPackages({
  required Directory repository,
  required List<String> packagePaths,
}) async {
  final paths = packagePaths.isEmpty ? const ['.'] : packagePaths;
  final selected = <_SelectedPackage>[];
  final seenPackages = <String>{};
  for (final path in paths) {
    final package = await _readSelectedPackage(
      repository: repository,
      packagePath: path,
    );
    if (!seenPackages.add(package.name)) {
      throw UsageException(
        'Package ${package.name} was selected more than once.',
        '',
      );
    }
    selected.add(_SelectedPackage(package: package, path: path));
  }
  return selected;
}

String _defaultImplementationRepositoryName(
  String upstream,
  List<_SelectedPackage> selectedPackages,
) {
  if (selectedPackages.length == 1 && selectedPackages.single.path == '.') {
    return selectedPackages.single.package.name;
  }
  return repositoryNameFromUpstream(upstream);
}

String _testWorkspacePathForSelection({
  required List<_SelectedPackage> selectedPackages,
  required _SelectedPackage selectedPackage,
}) {
  if (selectedPackages.length > 1 || selectedPackage.path != '.') {
    return 'fluoh_test/${selectedPackage.package.name}';
  }
  return 'fluoh_test';
}

PubRepositoryDocPackage _docPackageForSelection({
  required List<_SelectedPackage> selectedPackages,
  required _SelectedPackage selectedPackage,
}) {
  return PubRepositoryDocPackage(
    name: selectedPackage.package.name,
    version: selectedPackage.package.version,
    packagePath: selectedPackage.path,
    testWorkspacePath: _testWorkspacePathForSelection(
      selectedPackages: selectedPackages,
      selectedPackage: selectedPackage,
    ),
  );
}

Future<PubspecPackage> _readSelectedPackage({
  required Directory repository,
  required String packagePath,
}) async {
  final directory = packageDirectory(repository, packagePath);
  final pubspec = File('${directory.path}/pubspec.yaml');
  if (await pubspec.exists()) {
    return readPubspecPackage(directory);
  }

  if (packagePath == '.' || packagePath.isEmpty) {
    throw UsageException(
      'Missing pubspec.yaml at the upstream repository root. '
          'For a monorepo, select package paths with '
          '"--path <package-path>".',
      '',
    );
  }
  throw UsageException(
    'Missing pubspec.yaml at package path $packagePath.',
    '',
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
