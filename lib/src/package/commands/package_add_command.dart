import 'dart:io';

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

/// Registers an additional package in an existing package repository.
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
      'Register another package in an existing FlutterOH package repository.';

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
    final branch = await currentBranch(repository);
    if (branch != manifest.branch) {
      usageException(
        'Current branch $branch does not match package branch ${manifest.branch}.',
      );
    }

    final packagePath = rest.single;
    final package = await readPubspecPackage(
      packageDirectory(repository, packagePath),
    );
    final expectedPackage = argResults!.option('expected-package');
    if (expectedPackage != null && package.name != expectedPackage) {
      usageException(
        'Package at $packagePath is ${package.name}, expected $expectedPackage.',
      );
    }
    if (manifest.packages.any((existing) => existing.name == package.name)) {
      usageException(
        'Package ${package.name} is already registered in fluoh.yaml.',
      );
    }

    final originalFiles = await _snapshotFiles(repository, const [
      'fluoh.yaml',
      'FLUOH.md',
      'FLUOH_CHANGELOG.md',
      'AGENTS.md',
    ]);
    PackageExampleSetupResult? exampleSetupResult;
    Future<void> rollbackPackageAdd() async {
      await exampleSetupResult?.rollbackSnapshot?.restore();
      await _restoreFiles(repository, originalFiles);
      await _restoreStagedPaths(repository, [
        ...originalFiles.keys,
        if (exampleSetupResult?.prepared ?? false)
          packageRelativePath(repository, exampleSetupResult!.example),
      ]);
    }

    try {
      await addPackageManifestPackage(
        destination: repository,
        package: package,
        packagePath: packagePath,
      );
      final updatedManifest = await readPackageManifest(repository);
      final addedManifestPackage = updatedManifest.packageForName(package.name);
      exampleSetupResult = await preparePackageExample(
        environment: environment,
        repository: repository,
        package: addedManifestPackage,
        sdkVersion: updatedManifest.sdkVersion,
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
      await _writePackageDocs(
        repository: repository,
        manifest: updatedManifest,
        addedPackageName: package.name,
      );
      await runGit([
        'add',
        '-f',
        'fluoh.yaml',
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
    } on FileSystemException catch (error) {
      await rollbackPackageAdd();
      throw UsageException(
        'Failed to update package repository files: ${error.message}',
        '',
      );
    } catch (_) {
      await rollbackPackageAdd();
      rethrow;
    }
    _output.success('Registered package ${package.name} at $packagePath');
    _output.next(
      'Implement OHOS support for ${package.name}, then check it with '
      '"fluoh package check --package ${package.name}" and release it with '
      '"fluoh package release --package ${package.name}"',
    );
    return 0;
  }

  Future<void> _writePackageDocs({
    required Directory repository,
    required PackageManifest manifest,
    required String addedPackageName,
  }) async {
    final packages = packageRepositoryDocPackagesForManifest(manifest);
    await writeOrReplacePackageImplementationGuide(
      destination: repository,
      packages: packages,
    );

    final addedManifestPackage = manifest.packages.firstWhere(
      (package) => package.name == addedPackageName,
    );
    final addedDocPackage = packages.firstWhere(
      (package) => package.name == addedPackageName,
    );
    final changelog = File('${repository.path}/FLUOH_CHANGELOG.md');
    final changelogContent = await changelog.exists()
        ? await changelog.readAsString()
        : null;
    if (changelogContent == null || changelogContent.trim().isEmpty) {
      await changelog.writeAsString(
        packageFluohChangelogContent(
          packages: [addedDocPackage],
          sdkVersion: manifest.sdkVersion,
          releaseVersion: addedManifestPackage.version,
        ),
      );
    } else {
      final entry = packageFluohChangelogEntryLines(
        package: addedDocPackage,
        sdkVersion: manifest.sdkVersion,
        releaseVersion: addedManifestPackage.version,
      ).join('\n');
      await changelog.writeAsString(
        '$changelogContent${markdownAppendSeparator(changelogContent)}$entry',
      );
    }

    await writeOrReplacePackageAgentsInstructions(
      destination: repository,
      packages: packages,
    );
  }

  Future<Map<String, String?>> _snapshotFiles(
    Directory repository,
    List<String> paths,
  ) async {
    final snapshot = <String, String?>{};
    for (final path in paths) {
      final file = File('${repository.path}/$path');
      snapshot[path] = await file.exists() ? await file.readAsString() : null;
    }
    return snapshot;
  }

  Future<void> _restoreFiles(
    Directory repository,
    Map<String, String?> files,
  ) async {
    for (final entry in files.entries) {
      final file = File('${repository.path}/${entry.key}');
      final content = entry.value;
      if (content == null) {
        if (await file.exists()) {
          await file.delete();
        }
      } else {
        await file.writeAsString(content);
      }
    }
  }

  Future<void> _restoreStagedPaths(
    Directory repository,
    List<String> paths,
  ) async {
    await runGit(
      ['reset', '--', ...paths],
      workingDirectory: repository,
      allowFailure: true,
    );
  }
}
