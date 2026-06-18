import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import '../../cli/argument_validation.dart';
import '../../cli/fluoh_command_runner.dart';
import '../../cli/machine_output.dart';
import '../../cli/terminal_output.dart';
import '../../context/fluoh_environment.dart';
import '../../sdk/sdk_manager.dart';
import '../../sdk/sdk_project_environment.dart';
import '../git/package_git.dart';
import '../manifest/package_manifest.dart';
import '../manifest/pubspec_package.dart';
import '../package_examples.dart';
import '../package_repository_docs.dart';
import '../package_sdk_compatibility.dart';
import '../package_spec.dart';
import '../upstream_package_ref.dart';

/// Creates another package support branch in an existing repository.
class PackageAddCommand extends FluohCommand<int> {
  /// Creates the package add command.
  PackageAddCommand({
    required this.environment,
    required OutputWriter stdout,
    required OutputWriter stderr,
    TerminalOutput? output,
  }) : _stdout = stdout,
       _stderr = stderr,
       _output = output ?? TerminalOutput(stdout: stdout, stderr: stderr) {
    argParser.addOption(
      'expected-package',
      valueHelp: 'name',
      help: 'Expected package name at <package-path>.',
    );
    argParser.addOption(
      'upstream-version',
      valueHelp: 'version',
      help:
          'Upstream package version to target. Defaults to the latest valid '
          'package release tag.',
    );
    argParser.addOption(
      'upstream-ref',
      valueHelp: 'ref',
      help:
          'Upstream Git ref to target. Use only when release tags cannot '
          'identify the target package version.',
    );
    argParser.addOption(
      'org',
      valueHelp: 'organization',
      help:
          'Organization passed to flutter create when adding OHOS to the '
          'example. Omit it to infer from existing example platforms.',
    );
    argParser.addFlag(
      'plan',
      negatable: false,
      help:
          'Resolve the package branch plan without checking out or writing '
          'project files.',
    );
    argParser.addFlag(
      'json',
      negatable: false,
      help: 'Print the package add plan as JSON. Requires --plan.',
    );
  }

  /// Runtime environment for repository and Flutter SDK operations.
  final FluohEnvironment environment;
  final OutputWriter _stdout;
  final OutputWriter _stderr;
  final TerminalOutput _output;

  @override
  String get name => 'add';

  @override
  String get description =>
      'Create another package support branch in a FlutterOH repository.';

  @override
  String get invocation => 'fluoh package add <package-path>';

  @override
  Future<int> run() async {
    final planOnly = argResults!.flag('plan');
    final json = argResults!.flag('json');
    if (json && !planOnly) {
      usageException('--json is supported only with --plan for package add.');
    }
    final rest = expectArgumentCount(
      argResults!,
      1,
      'Expected <package-path>.',
      usageException,
    );

    final repository = environment.workingDirectory;
    final manifest = await readPackageManifest(repository);
    if (!manifest.isPorted) {
      usageException('package add is only available for ported packages.');
    }
    final startBranch = await currentBranch(repository);
    if (startBranch != manifest.branch) {
      usageException(
        'Current branch $startBranch does not match package branch '
        '${manifest.branch}.',
      );
    }
    final packagePath = rest.single;
    final upstreamTarget = _upstreamTargetFromOptions(argResults!);
    final expectedPackage = argResults!.option('expected-package');
    final flutterCreateOrg = _flutterCreateOrgFromOptions(argResults!);
    if (planOnly) {
      return _runPlan(
        repository: repository,
        manifest: manifest,
        currentBranch: startBranch,
        packagePath: packagePath,
        upstreamTarget: upstreamTarget,
        expectedPackage: expectedPackage,
        flutterCreateOrg: flutterCreateOrg,
        json: json,
      );
    }

    await ensureCleanWorkingTree(repository, 'Add package');

    var switchedBranches = false;
    String? createdBranch;
    try {
      await ensureUpstreamRemote(repository, manifest.requiredUpstreamUrl);
      await fetchUpstreamRefs(repository);
      final selected = await _resolvePackageRef(
        repository: repository,
        packagePath: packagePath,
        upstreamBranch: 'upstream/${manifest.upstreamBranch}',
        target: upstreamTarget,
        expectedPackageName: expectedPackage,
      );
      if (expectedPackage != null && selected.package.name != expectedPackage) {
        usageException(
          'Package at $packagePath is ${selected.package.name}, expected '
          '$expectedPackage.',
        );
      }

      final branch = flutterOhosPackageBranchForSdk(
        sdkVersion: manifest.sdkVersion,
        packageName: selected.package.name,
      );
      if (await _branchExists(repository, branch)) {
        usageException(
          'Package branch $branch already exists. Check it out and run '
          '"fluoh package status --package ${selected.package.name}" to inspect '
          'the existing support branch, or run '
          '"${_syncCommandFor(upstreamTarget)}" from that branch to update it.',
        );
      }

      switchedBranches = true;
      await synchronizeUpstreamBranch(
        repository,
        branch: manifest.upstreamBranch,
      );

      await _warnForPackageAddSdkCompatibility(
        repository: repository,
        environment: environment,
        selected: selected,
        packagePath: packagePath,
        sdkVersion: manifest.sdkVersion,
        output: _output,
      );

      await runGit([
        'checkout',
        '--detach',
        selected.commit,
      ], workingDirectory: repository);
      await runGit(['checkout', '-b', branch], workingDirectory: repository);
      createdBranch = branch;

      final packageManifest = PackageManifest(
        sdkVersion: manifest.sdkVersion,
        repositoryBranch: branch,
        repositoryUrl: manifest.repositoryUrl,
        upstreamUrl: manifest.requiredUpstreamUrl,
        upstreamBranch: manifest.upstreamBranch,
        package: PackageManifestPackage(
          name: selected.package.name,
          path: packagePath,
          upstreamVersion: selected.package.version,
          upstreamRef: selected.ref,
          upstreamCommit: selected.commit,
          version: initialPackageReleaseVersion,
          status: 'experimental',
        ),
      );
      await writePackageManifestFile(repository, packageManifest);
      await writeInitialPackageSpec(
        repository: repository,
        manifest: packageManifest,
      );
      final docPackage = _docPackageForManifest(
        packageManifest.package,
        repositoryUrl: packageManifest.repositoryUrl,
        sdkVersion: packageManifest.sdkVersion,
      );
      await writeOrReplacePackageContext(
        destination: repository,
        packages: [docPackage],
      );
      await ensureFluohLocalStateIgnored(repository);

      final exampleSetupResult = await preparePackageExample(
        environment: environment,
        repository: repository,
        package: packageManifest.package,
        sdkVersion: manifest.sdkVersion,
        stdout: _stdout,
        stderr: _stderr,
        output: _output,
        flutterCreateOrg: flutterCreateOrg,
      );
      if (!exampleSetupResult.prepared && exampleSetupResult.reason != null) {
        _output.skipped(
          'Skipping example OHOS setup for ${exampleSetupResult.packageName}: '
          '${exampleSetupResult.reason}',
        );
      }

      await runGit([
        'add',
        '-f',
        '.gitignore',
        'fluoh.yaml',
        'FLUOH.md',
        packageSpecRelativePath(selected.package.name),
      ], workingDirectory: repository);
      if (exampleSetupResult.prepared) {
        await runGit([
          'add',
          '-A',
          packageRelativePath(repository, exampleSetupResult.example),
        ], workingDirectory: repository);
      }

      _output.success(
        'Created package branch $branch for ${selected.package.name}',
      );
      _output.next(
        'Implement FlutterOH support for ${selected.package.name}, then check '
        'it with "fluoh package check" and release it with '
        '"fluoh package release"',
      );
      return 0;
    } catch (_) {
      if (switchedBranches) {
        await _rollbackFailedPackageAdd(
          repository: repository,
          startBranch: startBranch,
          createdBranch: createdBranch,
        );
      }
      rethrow;
    }
  }
}

extension on PackageAddCommand {
  Future<int> _runPlan({
    required Directory repository,
    required PackageManifest manifest,
    required String currentBranch,
    required String packagePath,
    required PackageUpstreamTarget upstreamTarget,
    required String? expectedPackage,
    required String? flutterCreateOrg,
    required bool json,
  }) async {
    if (!json) {
      _output.step('Resolving package add plan');
    }
    await fetchUpstreamRefsFromUrl(
      repository,
      upstreamUrl: manifest.requiredUpstreamUrl,
    );
    final selected = await _resolvePackageRef(
      repository: repository,
      packagePath: packagePath,
      upstreamBranch: 'upstream/${manifest.upstreamBranch}',
      target: upstreamTarget,
      expectedPackageName: expectedPackage,
    );
    if (expectedPackage != null && selected.package.name != expectedPackage) {
      usageException(
        'Package at $packagePath is ${selected.package.name}, expected '
        '$expectedPackage.',
      );
    }
    final branch = flutterOhosPackageBranchForSdk(
      sdkVersion: manifest.sdkVersion,
      packageName: selected.package.name,
    );
    final existingBranch = await _branchExists(repository, branch);
    final status = await runGit(
      ['status', '--porcelain'],
      workingDirectory: repository,
      allowFailure: true,
    );
    final warnings = await _packageAddSdkCompatibilityWarnings(
      repository: repository,
      environment: environment,
      selected: selected,
      packagePath: packagePath,
      sdkVersion: manifest.sdkVersion,
    );
    final plan = _PackageAddPlan(
      repositoryUrl: manifest.repositoryUrl,
      upstreamUrl: manifest.requiredUpstreamUrl,
      upstreamBranch: manifest.upstreamBranch,
      currentBranch: currentBranch,
      sourceBranch: manifest.branch,
      sdkVersion: manifest.sdkVersion,
      packagePath: packagePath,
      packageName: selected.package.name,
      upstreamVersion: selected.package.version,
      upstreamRef: selected.ref,
      upstreamCommit: selected.commit,
      branch: branch,
      branchExists: existingBranch,
      workingTreeClean:
          status.exitCode == 0 && status.stdout.toString().trim().isEmpty,
      flutterCreateOrg: flutterCreateOrg,
      addCommand: _addCommandFor(
        packagePath: packagePath,
        target: upstreamTarget,
        org: flutterCreateOrg,
      ),
      syncCommand: _syncCommandFor(upstreamTarget),
      warnings: warnings,
    );

    if (json) {
      writeMachineOutput(
        _stdout,
        command: 'package add',
        ok: true,
        exitCode: 0,
        fields: {'changed': false, 'applied': false, 'plan': plan.toJson()},
      );
    } else {
      _printPlan(plan);
    }
    return 0;
  }

  void _printPlan(_PackageAddPlan plan) {
    _output.success('Package add plan');
    _output.info('Package: ${plan.packageName} at ${plan.packagePath}');
    _output.info('Repository branch: ${plan.sourceBranch}');
    _output.info('New package branch: ${plan.branch}');
    _output.info('SDK: ${plan.sdkVersion} (${plan.sdkLine})');
    _output.info(
      plan.flutterCreateOrg == null
          ? 'Flutter create org: infer from example platforms'
          : 'Flutter create org: ${plan.flutterCreateOrg}',
    );
    if (!plan.workingTreeClean) {
      _output.warning('Current working tree is not clean.');
      _output.next('Commit or stash local changes before running package add');
    }
    if (plan.branchExists) {
      _output.warning('Package branch already exists: ${plan.branch}');
      _output.next(
        'Check it out and run "fluoh package status --package '
        '${plan.packageName}", or run "${plan.syncCommand}" from that branch',
      );
    }
    for (final warning in plan.warnings) {
      _output.warning(warning.message);
      _output.next(warning.nextStep);
    }
    if (!plan.branchExists) {
      _output.next(plan.addCommand);
    }
  }
}

class _PackageAddPlan {
  const _PackageAddPlan({
    required this.repositoryUrl,
    required this.upstreamUrl,
    required this.upstreamBranch,
    required this.currentBranch,
    required this.sourceBranch,
    required this.sdkVersion,
    required this.packagePath,
    required this.packageName,
    required this.upstreamVersion,
    required this.upstreamRef,
    required this.upstreamCommit,
    required this.branch,
    required this.branchExists,
    required this.workingTreeClean,
    required this.flutterCreateOrg,
    required this.addCommand,
    required this.syncCommand,
    required this.warnings,
  });

  final String repositoryUrl;
  final String upstreamUrl;
  final String upstreamBranch;
  final String currentBranch;
  final String sourceBranch;
  final String sdkVersion;
  final String packagePath;
  final String packageName;
  final String upstreamVersion;
  final String? upstreamRef;
  final String upstreamCommit;
  final String branch;
  final bool branchExists;
  final bool workingTreeClean;
  final String? flutterCreateOrg;
  final String addCommand;
  final String syncCommand;
  final List<PackageSdkCompatibilityWarning> warnings;

  String get sdkLine => sdkLineFromSdkVersion(sdkVersion);

  Map<String, Object?> toJson() {
    return {
      'supportKind': 'package',
      'repository': {
        'url': repositoryUrl,
        'currentBranch': currentBranch,
        'sourceBranch': sourceBranch,
        'newBranch': branch,
        'branchExists': branchExists,
        'workingTreeClean': workingTreeClean,
      },
      'upstream': {
        'urlOrPath': upstreamUrl,
        'branch': upstreamBranch,
        'selectedRef': upstreamRef,
        'selectedCommit': upstreamCommit,
      },
      'sdk': {'version': sdkVersion, 'line': sdkLine},
      'package': {
        'name': packageName,
        'path': packagePath,
        'upstreamVersion': upstreamVersion,
        'releaseVersion': initialPackageReleaseVersion,
        'status': 'experimental',
      },
      'flutterCreateOrg': flutterCreateOrg,
      'warnings': warnings.map((warning) => warning.toJson()).toList(),
      'nextCommand': branchExists
          ? 'git checkout $branch && fluoh package status --package $packageName'
          : addCommand,
      'willRun': branchExists
          ? [
              'checkout existing package branch $branch',
              'inspect package status for $packageName',
            ]
          : [
              'fetch upstream refs',
              'synchronize upstream branch $upstreamBranch',
              'checkout $branch from selected upstream commit',
              'write fluoh.yaml, FLUOH.md, and doc/fluoh/$packageName/spec.md',
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

Future<void> _rollbackFailedPackageAdd({
  required Directory repository,
  required String startBranch,
  required String? createdBranch,
}) async {
  final status = await runGit(
    ['status', '--short'],
    workingDirectory: repository,
    allowFailure: true,
  );
  if (status.exitCode == 0 && status.stdout.toString().trim().isNotEmpty) {
    await runGit(['reset', '--hard'], workingDirectory: repository);
    await runGit(['clean', '-fd'], workingDirectory: repository);
  }
  await runGit(['checkout', startBranch], workingDirectory: repository);
  if (createdBranch != null) {
    await runGit(
      ['branch', '-D', createdBranch],
      workingDirectory: repository,
      allowFailure: true,
    );
  }
}

Future<void> _warnForPackageAddSdkCompatibility({
  required Directory repository,
  required FluohEnvironment environment,
  required _ResolvedPackageRef selected,
  required String packagePath,
  required String sdkVersion,
  required TerminalOutput output,
}) async {
  final warnings = await _packageAddSdkCompatibilityWarnings(
    repository: repository,
    environment: environment,
    selected: selected,
    packagePath: packagePath,
    sdkVersion: sdkVersion,
  );
  for (final warning in warnings) {
    output.warning(warning.message);
    output.next(warning.nextStep);
  }
}

Future<List<PackageSdkCompatibilityWarning>>
_packageAddSdkCompatibilityWarnings({
  required Directory repository,
  required FluohEnvironment environment,
  required _ResolvedPackageRef selected,
  required String packagePath,
  required String sdkVersion,
}) {
  return packageSdkCompatibilityWarnings(
    repository: repository,
    selectedPackages: [
      SelectedPackageForSdkCompatibility(
        package: selected.package,
        path: packagePath,
        upstreamRef: selected.ref,
      ),
    ],
    sdkDirectory: SdkManager(environment).sdkDirectory(sdkVersion),
  );
}

Future<bool> _branchExists(Directory repository, String branch) async {
  final local = await runGit(
    ['show-ref', '--verify', '--quiet', 'refs/heads/$branch'],
    workingDirectory: repository,
    allowFailure: true,
  );
  if (local.exitCode == 0) {
    return true;
  }
  final origin = await runGit(
    ['show-ref', '--verify', '--quiet', 'refs/remotes/origin/$branch'],
    workingDirectory: repository,
    allowFailure: true,
  );
  return origin.exitCode == 0;
}

String _syncCommandFor(PackageUpstreamTarget target) {
  if (target.version != null) {
    return 'fluoh package upstream sync --upstream-version ${target.version}';
  }
  if (target.ref != null) {
    return 'fluoh package upstream sync --upstream-ref ${target.ref}';
  }
  return 'fluoh package upstream sync';
}

String _addCommandFor({
  required String packagePath,
  required PackageUpstreamTarget target,
  required String? org,
}) {
  final parts = ['fluoh package add $packagePath'];
  if (target.version != null) {
    parts.add('--upstream-version ${target.version}');
  }
  if (target.ref != null) {
    parts.add('--upstream-ref ${target.ref}');
  }
  if (org != null) {
    parts.add('--org $org');
  }
  return parts.join(' ');
}

class _ResolvedPackageRef {
  const _ResolvedPackageRef({
    required this.package,
    required this.commit,
    this.ref,
  });

  final PubspecPackage package;
  final String commit;
  final String? ref;
}

PackageUpstreamTarget _upstreamTargetFromOptions(ArgResults argResults) {
  final version = argResults.option('upstream-version')?.trim();
  final ref = argResults.option('upstream-ref')?.trim();
  final hasVersion = version != null && version.isNotEmpty;
  final hasRef = ref != null && ref.isNotEmpty;
  if (hasVersion && hasRef) {
    throw UsageException(
      'Use only one of --upstream-version or --upstream-ref.',
      '',
    );
  }
  return PackageUpstreamTarget(
    version: hasVersion ? version : null,
    ref: hasRef ? ref : null,
  );
}

String? _flutterCreateOrgFromOptions(ArgResults argResults) {
  final org = argResults.option('org')?.trim();
  if (org == null) {
    return null;
  }
  if (org.isEmpty) {
    throw UsageException('--org must not be empty.', '');
  }
  return org;
}

Future<_ResolvedPackageRef> _resolvePackageRef({
  required Directory repository,
  required String packagePath,
  required String upstreamBranch,
  required PackageUpstreamTarget target,
  required String? expectedPackageName,
}) async {
  final resolved = await resolvePackageUpstreamRefAtPath(
    repository: repository,
    packagePath: packagePath,
    fallbackRef: upstreamBranch,
    target: target,
    expectedPackageName: expectedPackageName,
  );
  return _ResolvedPackageRef(
    package: resolved.package,
    commit: resolved.commit,
    ref: resolved.ref,
  );
}

PackageRepositoryDocPackage _docPackageForManifest(
  PackageManifestPackage package, {
  required String repositoryUrl,
  required String sdkVersion,
}) {
  return PackageRepositoryDocPackage(
    name: package.name,
    version: package.sourceVersion,
    packagePath: package.path,
    sdkVersion: sdkVersion,
    releaseVersion: package.releaseVersion,
    repositoryUrl: repositoryUrl,
  );
}
