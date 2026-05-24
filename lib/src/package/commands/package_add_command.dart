import 'dart:io';

import 'package:args/command_runner.dart';

import '../../cli/argument_validation.dart';
import '../../cli/fluoh_command_runner.dart';
import '../../cli/terminal_output.dart';
import '../../context/fluoh_environment.dart';
import '../../testing/test_workspace.dart';
import '../git/package_git.dart';
import '../manifest/package_manifest.dart';
import '../manifest/pubspec_package.dart';
import '../package_repository_docs.dart';

class PackageAddCommand extends Command<int> {
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
    final packageTestWorkspace = Directory(
      '${repository.path}/fluoh_test/${package.name}',
    );
    final packageTestWorkspaceExisted = await packageTestWorkspace.exists();
    try {
      await addPackageManifestPackage(
        destination: repository,
        package: package,
        packagePath: packagePath,
      );
      final updatedManifest = await readPackageManifest(repository);
      final testInitResult = await initializeFluohTestWorkspace(
        environment: environment,
        stdout: _stdout,
        stderr: _stderr,
        output: _output,
        packageName: package.name,
      );
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
      if (testInitResult.created) {
        await runGit(['add', '-A', 'fluoh_test'], workingDirectory: repository);
      }
    } catch (_) {
      await _restoreFiles(repository, originalFiles);
      await _rollbackTestWorkspaceChanges(
        repository: repository,
        addedPackage: package.name,
        addedWorkspaceExisted: packageTestWorkspaceExisted,
      );
      rethrow;
    }
    _output.success('Registered package ${package.name} at $packagePath.');
    _output.next(
      'Implement OHOS support for ${package.name}, then release it with '
      '"fluoh package release --package ${package.name}".',
    );
    return 0;
  }

  Future<void> _writePackageDocs({
    required Directory repository,
    required PackageManifest manifest,
    required String addedPackageName,
  }) async {
    final packages = _docPackagesForManifest(manifest);
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

  List<PackageRepositoryDocPackage> _docPackagesForManifest(
    PackageManifest manifest,
  ) {
    return [
      for (final package in manifest.packages)
        PackageRepositoryDocPackage(
          name: package.name,
          version: package.upstreamVersion,
          packagePath: package.repositoryPath,
          testWorkspacePath: _testWorkspacePathForPackage(package),
        ),
    ];
  }

  String _testWorkspacePathForPackage(PackageManifestPackage package) {
    return 'fluoh_test/${package.name}';
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

  Future<void> _rollbackTestWorkspaceChanges({
    required Directory repository,
    required String addedPackage,
    required bool addedWorkspaceExisted,
  }) async {
    final root = Directory('${repository.path}/fluoh_test');
    final addedWorkspace = Directory('${root.path}/$addedPackage');
    if (!addedWorkspaceExisted && await addedWorkspace.exists()) {
      await addedWorkspace.delete(recursive: true);
    }
  }
}
