import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:pub_semver/pub_semver.dart';

import '../../cli/argument_validation.dart';
import '../../cli/fluoh_command_runner.dart';
import '../../cli/machine_output.dart';
import '../../cli/terminal_output.dart';
import '../../context/fluoh_environment.dart';
import '../../sdk/sdk_manager.dart';
import '../../sdk/sdk_project_environment.dart';
import '../../sdk/sdk_release.dart';
import '../git/package_git.dart';
import '../manifest/package_manifest.dart';
import '../manifest/pubspec_package.dart';
import '../license_checker.dart';
import '../package_discovery.dart';
import '../package_examples.dart';
import '../package_repository_docs.dart';
import '../package_sdk_compatibility.dart';
import '../repository_url.dart';
import '../upstream_package_ref.dart';

/// Initializes a FlutterOH package repository from an upstream package repo.
class PackageCreateCommand extends FluohCommand<int> {
  /// Creates the package repository initialization command.
  PackageCreateCommand({
    required this.environment,
    required OutputWriter stdout,
    required OutputWriter stderr,
    TerminalOutput? output,
  }) : _stdout = stdout,
       _stderr = stderr {
    _output = output ?? TerminalOutput(stdout: stdout, stderr: stderr);
    argParser
      ..addOption(
        'package-path',
        valueHelp: 'path',
        help:
            'Package path inside the upstream repository. Pass one path; '
            'omitting it selects only the root package.',
      )
      ..addOption(
        'upstream-version',
        valueHelp: 'version',
        help:
            'Upstream package version to adapt. Defaults to the latest valid '
            'package release tag.',
      )
      ..addOption(
        'upstream-ref',
        valueHelp: 'ref',
        help:
            'Upstream Git ref to adapt. Use only when release tags cannot '
            'identify the target package version.',
      )
      ..addOption(
        'output',
        valueHelp: 'path',
        help: 'Destination path for the FlutterOH package repository.',
      )
      ..addOption(
        'repository-name',
        valueHelp: 'repository-name',
        help:
            'Required FlutterOH package repository name for the default '
            'output path and repository URL.',
      )
      ..addOption(
        'sdk',
        valueHelp: 'version-or-series',
        help: 'FlutterOH SDK version or version series.',
      )
      ..addOption(
        'org',
        valueHelp: 'organization',
        help:
            'Organization passed to flutter create when adding OHOS to the '
            'example. Omit it to infer from existing example platforms.',
      )
      ..addOption(
        'repository',
        abbr: 'r',
        valueHelp: 'url',
        help: 'Final FlutterOH package repository URL for origin and manifest.',
      )
      ..addOption(
        'git-author-name',
        valueHelp: 'name',
        help: 'Configure local Git user.name for adaptation commits.',
      )
      ..addOption(
        'git-author-email',
        valueHelp: 'email',
        help: 'Configure local Git user.email for adaptation commits.',
      )
      ..addFlag(
        'plan',
        negatable: false,
        help:
            'Inspect the upstream repository and print the creation plan '
            'without creating the destination repository.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help: 'Print the creation plan as JSON. Requires --plan.',
      );
  }

  /// Runtime environment for SDK, Git, and filesystem operations.
  final FluohEnvironment environment;
  final OutputWriter _stdout;
  final OutputWriter _stderr;
  late final TerminalOutput _output;

  @override
  String get name => 'create';

  @override
  String get description => 'Initialize a FlutterOH package repository.';

  @override
  String get invocation => 'fluoh package create <upstream>';

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
    final planOnly = argResults!.flag('plan');
    final json = argResults!.flag('json');
    if (json && !planOnly) {
      usageException(
        '--json is supported only with --plan for package create.',
      );
    }
    final rest = expectArgumentCount(
      argResults!,
      1,
      'Expected <upstream>: Git URL or local Git repo path.',
      usageException,
    );

    final upstream = rest.single;
    _ensureSinglePackagePathOption();
    final packagePath = _packagePathFromOptions();
    final packagePaths = packagePath == null ? const <String>[] : [packagePath];
    final upstreamTarget = _upstreamTargetFromOptions();
    final packageRepositoryName = _packageRepositoryNameFromOptions();
    final gitAuthor = _gitAuthorConfigFromOptions();
    final flutterCreateOrg = _flutterCreateOrgFromOptions();
    final repositoryOption = argResults!.option('repository');
    if (!json) {
      _output.step('Resolving FlutterOH SDK');
    }
    final release = await _resolveSdkRelease();
    final destination = _packageCreateDestination(
      environment: environment,
      output: argResults!.option('output'),
      repositoryName: packageRepositoryName,
    );

    if (await destination.exists()) {
      usageException('Destination already exists: ${destination.path}');
    }

    if (planOnly) {
      return _runPlan(
        upstream: upstream,
        packagePaths: packagePaths,
        repositoryName: packageRepositoryName,
        repositoryOption: repositoryOption,
        upstreamTarget: upstreamTarget,
        gitAuthor: gitAuthor,
        flutterCreateOrg: flutterCreateOrg,
        release: release,
        destination: destination,
        json: json,
      );
    }

    var shouldRollbackDestination = true;
    try {
      _output.step(
        'Cloning upstream repository into ${_output.style.path(destination.path)}...',
      );
      await runGit(['clone', '--quiet', upstream, destination.path]);

      final implementationRepositoryName = packageRepositoryName;
      final repositoryUrl =
          repositoryOption ??
          defaultPackageRepositoryUrl(implementationRepositoryName);
      await configurePackageRemotes(destination, repositoryUrl);
      await fetchUpstreamRefs(destination);
      final upstreamBranch = await upstreamDefaultBranch(destination);
      await synchronizeUpstreamBranch(destination, branch: upstreamBranch);

      final selectedPackages = await _selectPackagesForTarget(
        repository: destination,
        packagePaths: packagePaths,
        fallbackRef: upstreamBranch,
        target: upstreamTarget,
      );
      final selected = selectedPackages.single;
      if (selected.path != '.') {
        _output.info(
          'Selected package ${selected.package.name} at ${selected.path}',
        );
      }
      if (gitAuthor != null) {
        await configurePackageGitAuthor(destination, gitAuthor);
        _output.info(
          'Configured local Git author: ${gitAuthor.name} <${gitAuthor.email}>',
        );
      }

      await runGit([
        'checkout',
        '--detach',
        selected.upstreamCommit!,
      ], workingDirectory: destination);
      final branch = flutterOhosPackageBranchForSdk(
        sdkVersion: release.tag,
        packageName: selected.package.name,
      );
      await runGit(['checkout', '-b', branch], workingDirectory: destination);
      final implementationRecommendation =
          await _implementationRecommendationForSelectedPackage(
            repository: destination,
            selected: selected,
            missingPlatform: 'ohos',
          );
      final docPackages = [
        _docPackageForSelection(
          selectedPackage: selected,
          repositoryUrl: repositoryUrl,
          implementationRecommendation: implementationRecommendation,
        ),
      ];
      final packageEnvironment = FluohEnvironment(
        homeDirectory: environment.homeDirectory,
        workingDirectory: destination,
        processEnvironment: environment.processEnvironment,
      );
      _output.blank();
      final sdkDirectory = SdkManager(
        packageEnvironment,
      ).sdkDirectory(release.tag);
      final sdkInstalled = await sdkDirectory.exists();
      if (sdkInstalled) {
        _output.info('Using installed FlutterOH SDK ${release.tag}');
      }
      final projectEnvironment = SdkProjectEnvironment(packageEnvironment);
      final configuredSdkDirectory = await _output.withProgress(
        sdkInstalled
            ? 'Configuring FlutterOH SDK ${release.tag}'
            : 'Installing FlutterOH SDK ${release.tag}; this may take a while.',
        () => projectEnvironment.configure(release, writeFluohConfig: false),
        showWhenPlain: !sdkInstalled,
      );
      _output.info(
        'FlutterOH SDK path: ${_output.style.path(configuredSdkDirectory.path)}',
      );
      await _warnForSelectedPackageSdkCompatibility(
        repository: destination,
        selectedPackages: selectedPackages,
        sdkDirectory: configuredSdkDirectory,
        output: _output,
      );
      final ideLink = await projectEnvironment.linkIdeSdk(
        configuredSdkDirectory,
      );
      _output.info('IDE Flutter SDK link: ${_output.style.path(ideLink.path)}');
      _output.next('Use this link as your IDE Flutter SDK path');
      _output.blank();
      await writePackageManifestFile(
        destination,
        PackageManifest(
          sdkVersion: release.tag,
          repositoryBranch: branch,
          upstreamUrl: upstream,
          upstreamBranch: upstreamBranch,
          repositoryUrl: repositoryUrl,
          package: PackageManifestPackage(
            name: selected.package.name,
            path: selected.path,
            upstreamVersion: selected.package.version,
            upstreamRef: selected.upstreamRef,
            upstreamCommit: selected.upstreamCommit!,
            version: initialPackageReleaseVersion,
            status: 'experimental',
          ),
        ),
      );
      await writeOrReplacePackageReadmeAdaptation(
        destination: destination,
        packages: docPackages,
      );
      await writeOrReplacePackageImplementationGuide(
        destination: destination,
        packages: docPackages,
      );
      await File('${destination.path}/FLUOH_CHANGELOG.md').writeAsString(
        packageFluohChangelogContent(
          packages: docPackages,
          sdkVersion: release.tag,
          releaseVersion: initialPackageReleaseVersion,
        ),
      );
      await writeOrReplacePackageAgentsInstructions(
        destination: destination,
        packages: docPackages,
      );
      await _writeClaudeInstructions(destination);
      final preparedExample = await preparePackageExample(
        environment: packageEnvironment,
        repository: destination,
        package: PackageManifestPackage(
          name: selected.package.name,
          path: selected.path,
          upstreamVersion: selected.package.version,
          upstreamRef: selected.upstreamRef,
          upstreamCommit: selected.upstreamCommit!,
          version: initialPackageReleaseVersion,
          status: 'experimental',
        ),
        sdkVersion: release.tag,
        sdkDirectory: configuredSdkDirectory,
        stdout: _stdout,
        stderr: _stderr,
        output: _output,
        flutterCreateOrg: flutterCreateOrg,
      );
      if (!preparedExample.prepared && preparedExample.reason != null) {
        _output.skipped(
          'Skipping example OHOS setup for ${preparedExample.packageName}: '
          '${preparedExample.reason}',
        );
      }
      await runGit([
        'add',
        '-f',
        'AGENTS.md',
        'CLAUDE.md',
        'FLUOH.md',
        'FLUOH_CHANGELOG.md',
        'README.md',
        '.gitignore',
        'fluoh.yaml',
      ], workingDirectory: destination);
      if (preparedExample.prepared) {
        await runGit([
          'add',
          '-A',
          packageRelativePath(destination, preparedExample.example),
        ], workingDirectory: destination);
      }

      final licenseWarnings = <String>[];
      licenseWarnings.addAll(
        await packageLicenseWarnings(
          repository: destination,
          packagePath: selected.path,
          packageName: selected.package.name,
        ),
      );
      _output.blank();
      for (final warning in licenseWarnings) {
        _output.warningError(warning);
      }
      if (licenseWarnings.isNotEmpty) {
        _output.blank();
      }

      _output.success(
        'Created package repository at ${_output.style.path(destination.path)}',
      );
      _output.info('Package branch: $branch');
      _output.info('Origin: ${_output.style.url(repositoryUrl)}');
      _output.success('Configured FlutterOH SDK ${release.tag}');
      if (implementationRecommendation != null) {
        _output.next(
          'Create ${implementationRecommendation.implementationPackageName} at '
          '${implementationRecommendation.implementationPackagePath} and add '
          '${implementationRecommendation.platform}.default_package to '
          '${implementationRecommendation.appFacingPackage}',
        );
      }
      _output.next('See FLUOH.md and AGENTS.md for implementation steps');
      shouldRollbackDestination = false;
      return 0;
    } catch (_) {
      if (shouldRollbackDestination && await destination.exists()) {
        await destination.delete(recursive: true);
      }
      rethrow;
    }
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

  PackageGitAuthor? _gitAuthorConfigFromOptions() {
    final name = argResults!.option('git-author-name')?.trim();
    final email = argResults!.option('git-author-email')?.trim();
    final hasName = name != null && name.isNotEmpty;
    final hasEmail = email != null && email.isNotEmpty;
    if (!hasName && !hasEmail) {
      return null;
    }
    if (!hasName || !hasEmail) {
      usageException(
        'Pass both --git-author-name and --git-author-email, or omit both.',
      );
    }
    return PackageGitAuthor(name: name, email: email);
  }

  String? _packagePathFromOptions() {
    final packagePath = argResults!.option('package-path')?.trim();
    if (packagePath == null) {
      return null;
    }
    if (packagePath.isEmpty) {
      usageException('--package-path must not be empty.');
    }
    return packagePath;
  }

  PackageUpstreamTarget _upstreamTargetFromOptions() {
    final version = argResults!.option('upstream-version')?.trim();
    final ref = argResults!.option('upstream-ref')?.trim();
    final hasVersion = version != null && version.isNotEmpty;
    final hasRef = ref != null && ref.isNotEmpty;
    if (hasVersion && hasRef) {
      usageException('Use only one of --upstream-version or --upstream-ref.');
    }
    return PackageUpstreamTarget(
      version: hasVersion ? version : null,
      ref: hasRef ? ref : null,
    );
  }

  String? _flutterCreateOrgFromOptions() {
    final org = argResults!.option('org')?.trim();
    if (org == null) {
      return null;
    }
    if (org.isEmpty) {
      usageException('--org must not be empty.');
    }
    return org;
  }

  void _ensureSinglePackagePathOption() {
    final occurrences = argResults!.arguments.where((argument) {
      return argument == '--package-path' ||
          argument.startsWith('--package-path=');
    }).length;
    if (occurrences > 1) {
      usageException(
        'package create creates one package branch. Pass one --package-path '
        'and use "fluoh package add <package-path>" for additional packages.',
      );
    }
  }

  String _packageRepositoryNameFromOptions() {
    final name = argResults!.option('repository-name')?.trim();
    if (name == null) {
      usageException(_missingPackageRepositoryNameMessage());
    }
    if (name.isEmpty) {
      usageException('--repository-name must not be empty.');
    }
    if (name == '.' ||
        name == '..' ||
        name.contains('/') ||
        name.contains('\\')) {
      usageException(
        '--repository-name must be a repository name, not a path.',
      );
    }
    if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(name)) {
      usageException(
        '--repository-name may contain only letters, numbers, ".", "_", and "-".',
      );
    }
    return name;
  }

  String _missingPackageRepositoryNameMessage() {
    final suggestion = _packageRepositoryNameSuggestion(
      argResults!.option('package-path'),
    );
    return [
      'Pass --repository-name <repository-name> for the FlutterOH package repository.',
      if (suggestion != null) 'Suggested name: $suggestion',
    ].join(' ');
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

extension on PackageCreateCommand {
  Future<int> _runPlan({
    required String upstream,
    required List<String> packagePaths,
    required String repositoryName,
    required String? repositoryOption,
    required PackageUpstreamTarget upstreamTarget,
    required PackageGitAuthor? gitAuthor,
    required String? flutterCreateOrg,
    required SdkRelease release,
    required Directory destination,
    required bool json,
  }) async {
    Directory? tempRoot;
    try {
      tempRoot = await Directory.systemTemp.createTemp('fluoh-create-plan-');
      final scratchRepository = Directory('${tempRoot.path}/upstream');
      if (!json) {
        _output.step('Inspecting upstream repository');
      }
      final cloneMode = await _cloneUpstreamForPackageCreatePlan(
        upstream: upstream,
        scratchRepository: scratchRepository,
        packagePaths: packagePaths,
        upstreamTarget: upstreamTarget,
      );
      final repositoryUrl =
          repositoryOption ?? defaultPackageRepositoryUrl(repositoryName);
      await configurePackageRemotes(scratchRepository, repositoryUrl);
      final upstreamBranch = await upstreamDefaultBranch(scratchRepository);
      await synchronizeUpstreamBranch(
        scratchRepository,
        branch: upstreamBranch,
      );
      await _prepareUpstreamRefsForPackageCreatePlan(
        repository: scratchRepository,
        cloneMode: cloneMode,
        packagePaths: packagePaths,
        upstreamBranch: upstreamBranch,
        upstreamTarget: upstreamTarget,
      );
      final selectedPackages = await _selectPackagesForTarget(
        repository: scratchRepository,
        packagePaths: packagePaths,
        fallbackRef: upstreamBranch,
        target: upstreamTarget,
      );
      final selected = selectedPackages.single;
      final defaultBranchVersionWarning =
          await _defaultBranchPackageVersionWarning(
            repository: scratchRepository,
            selected: selected,
            upstreamBranch: upstreamBranch,
            upstreamTarget: upstreamTarget,
          );
      final branch = flutterOhosPackageBranchForSdk(
        sdkVersion: release.tag,
        packageName: selected.package.name,
      );
      await runGit([
        'checkout',
        '--detach',
        selected.upstreamCommit!,
      ], workingDirectory: scratchRepository);
      final implementationRecommendation =
          await _implementationRecommendationForSelectedPackage(
            repository: scratchRepository,
            selected: selected,
            missingPlatform: 'ohos',
          );
      final compatibilityWarnings = await packageSdkCompatibilityWarnings(
        repository: scratchRepository,
        selectedPackages: selectedPackages
            .map(
              (selected) => SelectedPackageForSdkCompatibility(
                package: selected.package,
                path: selected.path,
                upstreamRef: selected.upstreamRef,
              ),
            )
            .toList(),
        sdkDirectory: SdkManager(environment).sdkDirectory(release.tag),
      );
      final warnings = <_PackageCreateWarning>[
        ?defaultBranchVersionWarning,
        ...compatibilityWarnings.map(_SdkCompatibilityPlanWarning.new),
      ];
      final plan = _PackageCreatePlan(
        upstream: upstream,
        upstreamBranch: upstreamBranch,
        repositoryName: repositoryName,
        repositoryUrl: repositoryUrl,
        outputPath: destination.path,
        sdkVersion: release.tag,
        sdkLine: sdkLineFromSdkVersion(release.tag),
        packageName: selected.package.name,
        packagePath: selected.path,
        upstreamVersion: selected.package.version,
        upstreamRef: selected.upstreamRef,
        upstreamCommit: selected.upstreamCommit!,
        branch: branch,
        gitAuthor: gitAuthor,
        flutterCreateOrg: flutterCreateOrg,
        implementationRecommendation: implementationRecommendation,
        warnings: warnings,
      );
      if (json) {
        writeMachineOutput(
          _stdout,
          command: 'package create',
          ok: true,
          exitCode: 0,
          fields: {'changed': false, 'applied': false, 'plan': plan.toJson()},
        );
      } else {
        _printPlan(plan);
      }
      return 0;
    } finally {
      if (tempRoot != null && await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    }
  }

  void _printPlan(_PackageCreatePlan plan) {
    _output.success('Package creation plan');
    _output.info('Repository name: ${plan.repositoryName}');
    _output.info('Output path: ${_output.style.path(plan.outputPath)}');
    _output.info('Origin: ${_output.style.url(plan.repositoryUrl)}');
    _output.info('Package: ${plan.packageName} at ${plan.packagePath}');
    _output.info('SDK: ${plan.sdkVersion} (${plan.sdkLine})');
    _output.info('Branch: ${plan.branch}');
    if (plan.gitAuthor != null) {
      _output.info(
        'Git author: ${plan.gitAuthor!.name} <${plan.gitAuthor!.email}>',
      );
    } else {
      _output.info('Git author: not configured by this command');
    }
    _output.info(
      plan.flutterCreateOrg == null
          ? 'Flutter create org: infer from example platforms'
          : 'Flutter create org: ${plan.flutterCreateOrg}',
    );
    final implementationRecommendation = plan.implementationRecommendation;
    if (implementationRecommendation != null) {
      _output.next(
        'Create ${implementationRecommendation.implementationPackageName} at '
        '${implementationRecommendation.implementationPackagePath} and add '
        '${implementationRecommendation.platform}.default_package to '
        '${implementationRecommendation.appFacingPackage}',
      );
    }
    for (final warning in plan.warnings) {
      _output.warning(warning.message);
      _output.next(warning.nextStep);
    }
    _output.next('Run without --plan after confirming these values');
  }
}

class _PackageCreatePlan {
  const _PackageCreatePlan({
    required this.upstream,
    required this.upstreamBranch,
    required this.repositoryName,
    required this.repositoryUrl,
    required this.outputPath,
    required this.sdkVersion,
    required this.sdkLine,
    required this.packageName,
    required this.packagePath,
    required this.upstreamVersion,
    required this.upstreamRef,
    required this.upstreamCommit,
    required this.branch,
    required this.gitAuthor,
    required this.flutterCreateOrg,
    required this.implementationRecommendation,
    required this.warnings,
  });

  final String upstream;
  final String upstreamBranch;
  final String repositoryName;
  final String repositoryUrl;
  final String outputPath;
  final String sdkVersion;
  final String sdkLine;
  final String packageName;
  final String packagePath;
  final String upstreamVersion;
  final String? upstreamRef;
  final String upstreamCommit;
  final String branch;
  final PackageGitAuthor? gitAuthor;
  final String? flutterCreateOrg;
  final PackageImplementationRecommendation? implementationRecommendation;
  final List<_PackageCreateWarning> warnings;

  Map<String, Object?> toJson() {
    return {
      'adaptationKind': 'package',
      'upstream': {
        'urlOrPath': upstream,
        'branch': upstreamBranch,
        'selectedRef': upstreamRef,
        'selectedCommit': upstreamCommit,
      },
      'repository': {
        'name': repositoryName,
        'url': repositoryUrl,
        'outputPath': outputPath,
        'branch': branch,
      },
      'sdk': {'version': sdkVersion, 'line': sdkLine},
      'package': {
        'name': packageName,
        'path': packagePath,
        'upstreamVersion': upstreamVersion,
        'releaseVersion': initialPackageReleaseVersion,
        'status': 'experimental',
      },
      'gitAuthor': gitAuthor == null
          ? null
          : {'name': gitAuthor!.name, 'email': gitAuthor!.email},
      'flutterCreateOrg': flutterCreateOrg,
      'implementationRecommendation': ?implementationRecommendation?.toJson(),
      'warnings': warnings.map((warning) => warning.toJson()).toList(),
      'willRun': [
        'git clone <upstream> <outputPath>',
        'configure origin remote',
        if (gitAuthor != null) 'configure local Git author',
        'checkout $branch',
        'configure FlutterOH SDK $sdkVersion',
        'write README.md, fluoh.yaml, FLUOH.md, FLUOH_CHANGELOG.md, AGENTS.md, and CLAUDE.md',
        'prepare example OHOS platform when an example exists',
        'stage generated files',
      ],
      'willNotRunWithoutSeparateApproval': [
        'fluoh package release',
        'git push',
        'git push --force',
        'destructive Git commands',
      ],
    };
  }
}

abstract class _PackageCreateWarning {
  String get message;
  String get nextStep;
  Map<String, Object?> toJson();
}

class _SdkCompatibilityPlanWarning implements _PackageCreateWarning {
  const _SdkCompatibilityPlanWarning(this.warning);

  final PackageSdkCompatibilityWarning warning;

  @override
  String get message => warning.message;

  @override
  String get nextStep => warning.nextStep;

  @override
  Map<String, Object?> toJson() => warning.toJson();
}

class _DefaultBranchPackageVersionWarning implements _PackageCreateWarning {
  const _DefaultBranchPackageVersionWarning({
    required this.packageName,
    required this.packagePath,
    required this.selectedRef,
    required this.selectedVersion,
    required this.defaultBranch,
    required this.defaultBranchVersion,
  });

  final String packageName;
  final String packagePath;
  final String selectedRef;
  final String selectedVersion;
  final String defaultBranch;
  final String defaultBranchVersion;

  @override
  String get message =>
      'Default branch $defaultBranch declares $packageName '
      '$defaultBranchVersion, but package create selected latest release tag '
      '$selectedRef ($selectedVersion).';

  @override
  String get nextStep =>
      'Keep adapting the selected release tag by default. Use --upstream-ref '
      '$defaultBranch only if maintainers explicitly approve adapting the '
      'unreleased default-branch snapshot.';

  @override
  Map<String, Object?> toJson() {
    return {
      'code': 'package.default_branch_version_unreleased',
      'severity': 'warning',
      'message': message,
      'nextStep': nextStep,
      'package': {'name': packageName, 'path': packagePath},
      'selected': {'ref': selectedRef, 'version': selectedVersion},
      'defaultBranch': {
        'branch': defaultBranch,
        'version': defaultBranchVersion,
      },
      'policy': {
        'defaultAction': 'adapt-selected-release-tag',
        'defaultBranchSnapshotRequiresApproval': true,
      },
    };
  }
}

Future<PackageImplementationRecommendation?>
_implementationRecommendationForSelectedPackage({
  required Directory repository,
  required _SelectedPackage selected,
  required String missingPlatform,
}) async {
  final discovery = await discoverPackageAdaptationCandidates(
    repository: repository,
    missingPlatform: missingPlatform,
  );
  for (final candidate in discovery.candidates) {
    if (candidate.name == selected.package.name &&
        candidate.path == selected.path) {
      return candidate.implementationRecommendation(missingPlatform);
    }
  }
  return null;
}

Future<_DefaultBranchPackageVersionWarning?>
_defaultBranchPackageVersionWarning({
  required Directory repository,
  required _SelectedPackage selected,
  required String upstreamBranch,
  required PackageUpstreamTarget upstreamTarget,
}) async {
  final selectedRef = selected.upstreamRef;
  if (upstreamTarget.isExplicit || selectedRef == null) {
    return null;
  }
  final defaultBranchPackage = await packageAtUpstreamRef(
    repository: repository,
    ref: upstreamBranch,
    packagePath: selected.path,
  );
  if (defaultBranchPackage == null ||
      defaultBranchPackage.name != selected.package.name ||
      !_isPackageVersionAheadOrDifferent(
        defaultBranchPackage.version,
        selected.package.version,
      )) {
    return null;
  }
  return _DefaultBranchPackageVersionWarning(
    packageName: selected.package.name,
    packagePath: selected.path,
    selectedRef: selectedRef,
    selectedVersion: selected.package.version,
    defaultBranch: upstreamBranch,
    defaultBranchVersion: defaultBranchPackage.version,
  );
}

bool _isPackageVersionAheadOrDifferent(
  String defaultBranchVersion,
  String selectedVersion,
) {
  if (defaultBranchVersion == selectedVersion) {
    return false;
  }
  try {
    return Version.parse(
          defaultBranchVersion,
        ).compareTo(Version.parse(selectedVersion)) >=
        0;
  } on FormatException {
    return true;
  }
}

Directory _packageCreateDestination({
  required FluohEnvironment environment,
  required String? output,
  required String repositoryName,
}) {
  final trimmedOutput = output?.trim();
  if (trimmedOutput != null && trimmedOutput.isNotEmpty) {
    final outputDirectory = Directory(trimmedOutput);
    final path = outputDirectory.isAbsolute
        ? trimmedOutput
        : '${environment.workingDirectory.path}/$trimmedOutput';
    return Directory(_normalizeDirectoryPath(path));
  }
  return Directory(
    _normalizeDirectoryPath(
      '${environment.workingDirectory.path}/$repositoryName',
    ),
  );
}

enum _PackageCreatePlanCloneMode { shallow, partial, full }

Future<_PackageCreatePlanCloneMode> _cloneUpstreamForPackageCreatePlan({
  required String upstream,
  required Directory scratchRepository,
  required List<String> packagePaths,
  required PackageUpstreamTarget upstreamTarget,
}) async {
  if (upstreamTarget.ref == null) {
    final sparsePaths = _packageCreatePlanSparsePaths(packagePaths);
    if (sparsePaths.isNotEmpty) {
      final sparse = await runGit([
        'clone',
        '--quiet',
        '--depth',
        '1',
        '--single-branch',
        '--filter=blob:none',
        '--sparse',
        upstream,
        scratchRepository.path,
      ], allowFailure: true);
      if (sparse.exitCode == 0 &&
          await _setPackageCreatePlanSparsePaths(
            scratchRepository,
            sparsePaths,
          )) {
        return _PackageCreatePlanCloneMode.shallow;
      }
      if (await scratchRepository.exists()) {
        await scratchRepository.delete(recursive: true);
      }
    }

    final shallow = await runGit([
      'clone',
      '--quiet',
      '--depth',
      '1',
      '--single-branch',
      upstream,
      scratchRepository.path,
    ], allowFailure: true);
    if (shallow.exitCode == 0) {
      return _PackageCreatePlanCloneMode.shallow;
    }
    if (await scratchRepository.exists()) {
      await scratchRepository.delete(recursive: true);
    }
  }

  final partial = await runGit([
    'clone',
    '--quiet',
    '--filter=blob:none',
    '--no-checkout',
    upstream,
    scratchRepository.path,
  ], allowFailure: true);
  if (partial.exitCode == 0) {
    return _PackageCreatePlanCloneMode.partial;
  }
  if (await scratchRepository.exists()) {
    await scratchRepository.delete(recursive: true);
  }
  await runGit(['clone', '--quiet', upstream, scratchRepository.path]);
  return _PackageCreatePlanCloneMode.full;
}

List<String> _packageCreatePlanSparsePaths(List<String> packagePaths) {
  final paths = packagePaths
      .map(_normalizePackagePath)
      .where((path) => path != '.')
      .toList(growable: false);
  return paths;
}

Future<bool> _setPackageCreatePlanSparsePaths(
  Directory repository,
  List<String> sparsePaths,
) async {
  final result = await runGit(
    ['sparse-checkout', 'set', ...sparsePaths],
    workingDirectory: repository,
    allowFailure: true,
  );
  return result.exitCode == 0;
}

Future<void> _prepareUpstreamRefsForPackageCreatePlan({
  required Directory repository,
  required _PackageCreatePlanCloneMode cloneMode,
  required List<String> packagePaths,
  required String upstreamBranch,
  required PackageUpstreamTarget upstreamTarget,
}) async {
  if (cloneMode == _PackageCreatePlanCloneMode.shallow) {
    final selectedTagsPrepared = await _prepareSelectedPackageReleaseTags(
      repository: repository,
      packagePaths: packagePaths,
      upstreamBranch: upstreamBranch,
      upstreamTarget: upstreamTarget,
    );
    if (selectedTagsPrepared) {
      return;
    }
  }
  await fetchUpstreamRefs(repository);
}

Future<bool> _prepareSelectedPackageReleaseTags({
  required Directory repository,
  required List<String> packagePaths,
  required String upstreamBranch,
  required PackageUpstreamTarget upstreamTarget,
}) async {
  final paths = packagePaths.isEmpty ? const ['.'] : packagePaths;
  for (final path in paths) {
    final package = await packageAtUpstreamRef(
      repository: repository,
      ref: upstreamBranch,
      packagePath: path,
    );
    if (package == null) {
      return false;
    }
    final fetched = await _fetchLatestValidPackageReleaseTag(
      repository: repository,
      package: package,
      packagePath: path,
      upstreamTarget: upstreamTarget,
    );
    if (!fetched) {
      return false;
    }
  }
  return true;
}

Future<bool> _fetchLatestValidPackageReleaseTag({
  required Directory repository,
  required PubspecPackage package,
  required String packagePath,
  required PackageUpstreamTarget upstreamTarget,
}) async {
  final requestedVersion = upstreamTarget.version == null
      ? null
      : _tryParsePackageVersion(upstreamTarget.version!);
  if (upstreamTarget.version != null && requestedVersion == null) {
    return true;
  }
  final tags = await _remotePackageReleaseTags(
    repository: repository,
    packageName: package.name,
    rootPackage: _normalizePackagePath(packagePath) == '.',
    requestedVersion: requestedVersion,
  );
  if (tags == null) {
    return false;
  }
  for (final tag in tags.reversed) {
    final fetched = await _fetchUpstreamTag(repository, tag.ref);
    if (!fetched) {
      return false;
    }
    final tagPackage = await packageAtUpstreamRef(
      repository: repository,
      ref: tag.ref,
      packagePath: packagePath,
    );
    if (tagPackage == null || tagPackage.name != package.name) {
      continue;
    }
    if (tagPackage.version != tag.version.toString()) {
      continue;
    }
    return true;
  }
  return true;
}

Future<List<_RemotePackageReleaseTag>?> _remotePackageReleaseTags({
  required Directory repository,
  required String packageName,
  required bool rootPackage,
  required Version? requestedVersion,
}) async {
  final result = await runGit(
    ['ls-remote', '--tags', 'upstream'],
    workingDirectory: repository,
    allowFailure: true,
  );
  if (result.exitCode != 0) {
    return null;
  }
  final tags = <_RemotePackageReleaseTag>[];
  for (final line in result.stdout.toString().split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length < 2) {
      continue;
    }
    final ref = parts[1];
    if (!ref.startsWith('refs/tags/') || ref.endsWith('^{}')) {
      continue;
    }
    final tag = ref.substring('refs/tags/'.length);
    final version = packageVersionFromReleaseTag(
      tag: tag,
      packageName: packageName,
      rootPackage: rootPackage,
    );
    if (version == null) {
      continue;
    }
    final parsedVersion = _tryParsePackageVersion(version);
    if (parsedVersion == null) {
      continue;
    }
    if (requestedVersion != null && parsedVersion != requestedVersion) {
      continue;
    }
    tags.add(_RemotePackageReleaseTag(ref: tag, version: parsedVersion));
  }
  tags.sort((a, b) {
    final version = a.version.compareTo(b.version);
    if (version != 0) {
      return version;
    }
    return a.ref.compareTo(b.ref);
  });
  return tags;
}

Future<bool> _fetchUpstreamTag(Directory repository, String tag) async {
  final result = await runGit(
    ['fetch', '--depth', '1', 'upstream', 'refs/tags/$tag:refs/tags/$tag'],
    workingDirectory: repository,
    allowFailure: true,
  );
  return result.exitCode == 0;
}

Version? _tryParsePackageVersion(String value) {
  try {
    return Version.parse(value);
  } on FormatException {
    return null;
  }
}

class _RemotePackageReleaseTag {
  const _RemotePackageReleaseTag({required this.ref, required this.version});

  final String ref;
  final Version version;
}

String? _packageRepositoryNameSuggestion(String? packagePath) {
  if (packagePath == null) {
    return null;
  }
  final normalized = _normalizePackagePath(packagePath);
  if (normalized == '.') {
    return null;
  }
  return _pathName(normalized);
}

String _normalizeDirectoryPath(String path) {
  final normalizedSeparators = path.replaceAll('\\', '/');
  final absolutePrefix = normalizedSeparators.startsWith('/') ? '/' : '';
  final segments = <String>[];
  for (final segment in normalizedSeparators.split('/')) {
    if (segment.isEmpty || segment == '.') {
      continue;
    }
    if (segment == '..') {
      if (segments.isNotEmpty && segments.last != '..') {
        segments.removeLast();
      } else if (absolutePrefix.isEmpty) {
        segments.add(segment);
      }
      continue;
    }
    segments.add(segment);
  }

  final normalized = '$absolutePrefix${segments.join('/')}';
  final nativePath = Platform.pathSeparator == '/'
      ? normalized
      : normalized.replaceAll('/', Platform.pathSeparator);
  if (nativePath.isNotEmpty) {
    return nativePath;
  }
  return absolutePrefix.isEmpty ? '.' : Platform.pathSeparator;
}

class _SelectedPackage {
  const _SelectedPackage({
    required this.package,
    required this.path,
    this.upstreamCommit,
    this.upstreamRef,
  });

  final PubspecPackage package;
  final String path;
  final String? upstreamCommit;
  final String? upstreamRef;
}

Future<List<_SelectedPackage>> _selectPackagesForTarget({
  required Directory repository,
  required List<String> packagePaths,
  required String fallbackRef,
  required PackageUpstreamTarget target,
}) async {
  final paths = packagePaths.isEmpty ? const ['.'] : packagePaths;
  final selected = <_SelectedPackage>[];
  final seenPackages = <String>{};
  for (final path in paths) {
    final upstreamRef = await _resolveSelectedPackageUpstreamRef(
      repository: repository,
      packagePath: path,
      fallbackRef: fallbackRef,
      target: target,
    );
    final package = upstreamRef.package;
    if (!seenPackages.add(package.name)) {
      throw UsageException(
        'Package ${package.name} was selected more than once.',
        '',
      );
    }
    selected.add(
      _SelectedPackage(
        package: upstreamRef.package,
        path: path,
        upstreamCommit: upstreamRef.commit,
        upstreamRef: upstreamRef.ref,
      ),
    );
  }
  return selected;
}

Future<ResolvedPackageUpstreamRef> _resolveSelectedPackageUpstreamRef({
  required Directory repository,
  required String packagePath,
  required String fallbackRef,
  required PackageUpstreamTarget target,
}) async {
  try {
    return await resolvePackageUpstreamRefAtPath(
      repository: repository,
      packagePath: packagePath,
      fallbackRef: fallbackRef,
      target: target,
    );
  } on UsageException {
    if (target.isExplicit) {
      rethrow;
    }
    final package = await _readSelectedPackage(
      repository: repository,
      packagePath: packagePath,
    );
    return resolvePackageUpstreamRef(
      repository: repository,
      packageName: package.name,
      packagePath: packagePath,
      fallbackRef: fallbackRef,
      target: target,
    );
  }
}

Future<void> _warnForSelectedPackageSdkCompatibility({
  required Directory repository,
  required List<_SelectedPackage> selectedPackages,
  required Directory sdkDirectory,
  required TerminalOutput output,
}) async {
  final warnings = await packageSdkCompatibilityWarnings(
    repository: repository,
    selectedPackages: selectedPackages
        .map(
          (selected) => SelectedPackageForSdkCompatibility(
            package: selected.package,
            path: selected.path,
            upstreamRef: selected.upstreamRef,
          ),
        )
        .toList(),
    sdkDirectory: sdkDirectory,
  );
  for (final warning in warnings) {
    output.warning(warning.message);
    output.next(warning.nextStep);
  }
}

PackageRepositoryDocPackage _docPackageForSelection({
  required _SelectedPackage selectedPackage,
  required String repositoryUrl,
  PackageImplementationRecommendation? implementationRecommendation,
}) {
  return PackageRepositoryDocPackage(
    name: selectedPackage.package.name,
    version: selectedPackage.package.version,
    packagePath: selectedPackage.path,
    repositoryUrl: repositoryUrl,
    implementationRecommendation: implementationRecommendation,
  );
}

String _normalizePackagePath(String path) {
  final segments = _pathSegments(path);
  if (segments.isEmpty) {
    return '.';
  }
  return segments.join('/');
}

List<String> _pathSegments(String path) {
  return path
      .replaceAll('\\', '/')
      .split('/')
      .where((segment) => segment.isNotEmpty && segment != '.')
      .toList(growable: false);
}

String _pathName(String path) {
  final segments = _pathSegments(path);
  return segments.isEmpty ? path : segments.last;
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
    final candidates = await _packageSelectionCandidates(repository);
    final candidateHelp = _packageSelectionCandidateHelp(candidates);
    throw UsageException(
      'Missing pubspec.yaml at the upstream repository root. '
          'For packages below the root, select package paths with '
          '"--package-path <package-path>".'
          '$candidateHelp',
      '',
    );
  }
  throw UsageException(
    'Missing pubspec.yaml at package path $packagePath.',
    '',
  );
}

Future<List<_PackageSelectionCandidate>> _packageSelectionCandidates(
  Directory repository,
) async {
  final candidates = <_PackageSelectionCandidate>[];
  if (!await repository.exists()) {
    return candidates;
  }
  final pending = <Directory>[repository];
  while (pending.isNotEmpty) {
    final directory = pending.removeLast();
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is Directory) {
        final path = _relativeCandidatePath(repository, entity);
        if (!_shouldSkipCandidatePath(path)) {
          pending.add(entity);
        }
        continue;
      }
      if (entity is! File || !_isPubspecFile(entity)) {
        continue;
      }
      final path = _relativeCandidatePath(repository, entity.parent);
      if (_shouldSkipCandidatePath(path)) {
        continue;
      }
      try {
        final package = await readPubspecPackage(entity.parent);
        final refs = await packageReleaseRefs(
          repository: repository,
          packageName: package.name,
          packagePath: path,
        );
        candidates.add(
          _PackageSelectionCandidate(
            package: package,
            path: path,
            latestRef: refs.isEmpty ? null : refs.last,
          ),
        );
      } on Object {
        // Ignore malformed nested pubspec files while building selection help.
      }
    }
  }
  candidates.sort((a, b) => a.path.compareTo(b.path));
  return candidates;
}

String _relativeCandidatePath(Directory repository, Directory directory) {
  final root = repository.absolute.path;
  final path = directory.absolute.path;
  if (path == root) {
    return '.';
  }
  if (path.startsWith('$root${Platform.pathSeparator}')) {
    return _normalizePackagePath(path.substring(root.length + 1));
  }
  return _normalizePackagePath(path);
}

String _packageSelectionCandidateHelp(
  List<_PackageSelectionCandidate> candidates,
) {
  if (candidates.isEmpty) {
    return '';
  }
  final visible = candidates.take(20).map((candidate) {
    final package = candidate.package;
    return [
      '\n- ${package.name} ${package.version} at ${candidate.path}',
      if (package.sdkConstraint != null) ' (Dart ${package.sdkConstraint})',
      if (candidate.latestRef != null)
        ' [latest tag ${candidate.latestRef!.ref}]',
      ': --package-path ${candidate.path} --repository-name ${package.name}',
    ].join();
  }).join();
  final hidden = candidates.length > 20
      ? '\n- ... ${candidates.length - 20} more package candidates'
      : '';
  return '\nCandidate packages:$visible$hidden';
}

bool _isPubspecFile(File file) {
  final normalized = file.path.replaceAll('\\', '/');
  return normalized.endsWith('/pubspec.yaml');
}

bool _shouldSkipCandidatePath(String path) {
  final segments = _pathSegments(path);
  return segments.any(
    (segment) => const {
      '.dart_tool',
      '.git',
      '.idea',
      'build',
      'example',
      'examples',
      'node_modules',
    }.contains(segment),
  );
}

class _PackageSelectionCandidate {
  const _PackageSelectionCandidate({
    required this.package,
    required this.path,
    required this.latestRef,
  });

  final PubspecPackage package;
  final String path;
  final PackageReleaseRef? latestRef;
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
