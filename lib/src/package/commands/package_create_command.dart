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

part 'package_create_plan_flow.dart';
part 'package_create_plan_models.dart';
part 'package_create_upstream_git.dart';
part 'package_create_selection.dart';
part 'package_create_agent_docs.dart';

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
