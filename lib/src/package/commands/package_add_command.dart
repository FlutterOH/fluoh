import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import '../../cli/argument_validation.dart';
import '../../cli/fluoh_command_runner.dart';
import '../../cli/terminal_output.dart';
import '../../context/fluoh_environment.dart';
import '../git/package_git.dart';
import '../manifest/package_manifest.dart';
import '../manifest/pubspec_package.dart';
import '../package_examples.dart';
import '../package_repository_docs.dart';
import '../upstream_package_ref.dart';

/// Creates another package adaptation branch in an existing repository.
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
          'Upstream package version to adapt. Defaults to the latest valid '
          'package release tag.',
    );
    argParser.addOption(
      'upstream-ref',
      valueHelp: 'ref',
      help:
          'Upstream Git ref to adapt. Use only when release tags cannot '
          'identify the target package version.',
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
      'Create another package adaptation branch in a FlutterOH repository.';

  @override
  String get invocation => 'fluoh package add <package-path>';

  @override
  Future<int> run() async {
    final rest = expectArgumentCount(
      argResults!,
      1,
      'Expected <package-path>.',
      usageException,
    );

    final repository = environment.workingDirectory;
    await ensureCleanWorkingTree(repository, 'Add package');
    final manifest = await readPackageManifest(repository);
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

    var switchedBranches = false;
    String? createdBranch;
    try {
      await fetchUpstreamRefs(repository);
      switchedBranches = true;
      await synchronizeUpstreamBranch(
        repository,
        branch: manifest.upstreamBranch,
      );

      final selected = await _resolvePackageRef(
        repository: repository,
        packagePath: packagePath,
        upstreamBranch: manifest.upstreamBranch,
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
      final existingBranch = await runGit(
        ['rev-parse', '--verify', branch],
        workingDirectory: repository,
        allowFailure: true,
      );
      if (existingBranch.exitCode == 0) {
        final syncCommand = upstreamTarget.version != null
            ? 'fluoh package sync --upstream-version ${upstreamTarget.version}'
            : upstreamTarget.ref != null
            ? 'fluoh package sync --upstream-ref ${upstreamTarget.ref}'
            : 'fluoh package sync';
        usageException(
          'Package branch $branch already exists. Check it out and run '
          '"fluoh package status --package ${selected.package.name}" to inspect '
          'the existing adaptation, or run "$syncCommand" from that branch to '
          'update it.',
        );
      }

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
        upstreamUrl: manifest.upstreamUrl,
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
      final docPackage = _docPackageForManifest(
        packageManifest.package,
        repositoryUrl: packageManifest.repositoryUrl,
      );
      await writeOrReplacePackageReadmeAdaptation(
        destination: repository,
        packages: [docPackage],
      );
      await writeOrReplacePackageImplementationGuide(
        destination: repository,
        packages: [docPackage],
      );
      await File('${repository.path}/FLUOH_CHANGELOG.md').writeAsString(
        packageFluohChangelogContent(
          packages: [docPackage],
          sdkVersion: manifest.sdkVersion,
          releaseVersion: initialPackageReleaseVersion,
        ),
      );
      await writeOrReplacePackageAgentsInstructions(
        destination: repository,
        packages: [docPackage],
      );

      final exampleSetupResult = await preparePackageExample(
        environment: environment,
        repository: repository,
        package: packageManifest.package,
        sdkVersion: manifest.sdkVersion,
        stdout: _stdout,
        stderr: _stderr,
        output: _output,
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
        'fluoh.yaml',
        'README.md',
        'FLUOH.md',
        'FLUOH_CHANGELOG.md',
        'AGENTS.md',
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
        'Implement OHOS support for ${selected.package.name}, then check it with '
        '"fluoh package check" and release it with "fluoh package release"',
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
}) {
  return PackageRepositoryDocPackage(
    name: package.name,
    version: package.upstreamVersion,
    packagePath: package.path,
    repositoryUrl: repositoryUrl,
  );
}
