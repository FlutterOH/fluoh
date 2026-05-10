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
      ..addOption('package', help: 'Package name to adapt in a monorepo.')
      ..addMultiOption(
        'path',
        help:
            'Package path inside a monorepo upstream repository. Can be repeated.',
      )
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
    final packagePaths = argResults!.multiOption('path');
    final packageName = argResults!.option('package');
    if (packageName != null && packagePaths.length > 1) {
      usageException('Use --package with at most one --path.');
    }
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
      packageName: packageName,
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

    final adapterUrl =
        argResults!.option('repo') ??
        defaultPubRepositoryUrl(
          _defaultAdapterRepositoryName(upstream, selectedPackages),
        );
    await configurePubRemotes(destination, adapterUrl);

    final upstreamRef = await currentHead(destination);
    final branch = ohosBranchForSdk(release.tag);
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
        sdkVersion: release.tag,
        branch: branch,
        upstreamUrl: upstream,
        upstreamRef: upstreamRef,
        upstreamDefaultBranch: await upstreamDefaultBranch(destination),
        adapterUrl: adapterUrl,
        packages: [
          for (final selected in selectedPackages)
            PubManifestPackage(
              name: selected.package.name,
              upstreamVersion: selected.package.version,
              releaseVersion: initialPubReleaseVersion,
              dependencyPath: selected.path == '.' ? null : selected.path,
              upstreamPath: selected.path == '.' ? null : selected.path,
              status: 'experimental',
            ),
        ],
      ),
    );
    await File('${destination.path}/FLUOH.md').writeAsString(
      pubAdaptationGuideContent(
        packages: docPackages,
        upstreamRef: upstreamRef,
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
      upstreamRef: upstreamRef,
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
    _output.info('Origin: ${_output.style.url(adapterUrl)}.');
    _output.success('Configured Flutter OHOS SDK ${release.tag}.');
    if (createdTestWorkspaces) {
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

class _SelectedPackage {
  const _SelectedPackage({required this.package, required this.path});

  final PubspecPackage package;
  final String path;
}

Future<List<_SelectedPackage>> _selectPackages({
  required Directory repository,
  required List<String> packagePaths,
  required String? packageName,
}) async {
  if (packagePaths.isEmpty && packageName != null) {
    final path = await findPackagePath(repository, packageName);
    final package = await _readSelectedPackage(
      repository: repository,
      packagePath: path,
      selectedByPackageName: true,
    );
    return [_SelectedPackage(package: package, path: path)];
  }

  final paths = packagePaths.isEmpty ? const ['.'] : packagePaths;
  final selected = <_SelectedPackage>[];
  final seenPackages = <String>{};
  for (final path in paths) {
    final package = await _readSelectedPackage(
      repository: repository,
      packagePath: path,
      selectedByPackageName: false,
    );
    if (packageName != null && package.name != packageName) {
      throw UsageException(
        'Package at $path is ${package.name}, expected $packageName.',
        '',
      );
    }
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

String _defaultAdapterRepositoryName(
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
  required bool selectedByPackageName,
}) async {
  final directory = packageDirectory(repository, packagePath);
  final pubspec = File('${directory.path}/pubspec.yaml');
  if (await pubspec.exists()) {
    return readPubspecPackage(directory);
  }

  if (packagePath == '.' || packagePath.isEmpty) {
    throw UsageException(
      'Missing pubspec.yaml at the upstream repository root. '
          'For a monorepo, select one package with '
          '"--path <package-path>" or "--package <package-name>".',
      '',
    );
  }
  if (selectedByPackageName) {
    throw UsageException(
      'Package path $packagePath does not contain pubspec.yaml.',
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
