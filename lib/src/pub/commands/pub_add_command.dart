import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:yaml/yaml.dart';

import '../../cli/fluoh_command_runner.dart';
import '../../cli/terminal_output.dart';
import '../../context/fluoh_environment.dart';
import '../../testing/test_workspace.dart';
import '../git/pub_git.dart';
import '../manifest/pub_manifest.dart';
import '../manifest/pubspec_package.dart';
import '../pub_repository_docs.dart';

class PubAddCommand extends Command<int> {
  PubAddCommand({
    required this.environment,
    required OutputWriter stdout,
    required OutputWriter stderr,
    TerminalOutput? output,
  }) : _stdout = stdout,
       _stderr = stderr,
       _output = output ?? TerminalOutput(stdout: stdout, stderr: stderr) {
    argParser
      ..addOption(
        'path',
        mandatory: true,
        help: 'Package path inside the existing adapter monorepo.',
      )
      ..addOption('package', help: 'Expected package name at --path.');
  }

  final FluohEnvironment environment;
  final OutputWriter _stdout;
  final OutputWriter _stderr;
  final TerminalOutput _output;

  @override
  String get name => 'add';

  @override
  String get description =>
      'Register another package in an existing FlutterOH pub monorepo.';

  @override
  Future<int> run() async {
    final repository = environment.workingDirectory;
    await ensureCleanWorkingTree(repository, 'Add package');
    final manifest = await readPubManifest(repository);
    final branch = await currentBranch(repository);
    if (branch != manifest.branch) {
      usageException(
        'Current branch $branch does not match pub branch ${manifest.branch}.',
      );
    }

    final packagePath = argResults!.option('path')!;
    final package = await readPubspecPackage(
      packageDirectory(repository, packagePath),
    );
    final expectedPackage = argResults!.option('package');
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
    final existingPackage = manifest.packages.length == 1
        ? manifest.packages.single.name
        : null;
    final packageTestWorkspace = Directory(
      '${repository.path}/fluoh_test/${package.name}',
    );
    final packageTestWorkspaceExisted = await packageTestWorkspace.exists();
    var migratedTestWorkspace = false;
    try {
      migratedTestWorkspace = await _migrateRootTestWorkspaceForMultiPackage(
        repository,
        manifest,
      );
      await addPubManifestPackage(
        destination: repository,
        package: package,
        packagePath: packagePath,
      );
      final testInitResult = await initializeFluohTestWorkspace(
        environment: environment,
        stdout: _stdout,
        stderr: _stderr,
        output: _output,
        packageName: package.name,
      );
      await _appendPackageDocs(
        repository: repository,
        manifest: manifest,
        package: PubRepositoryDocPackage(
          name: package.name,
          version: package.version,
          packagePath: packagePath,
          testWorkspacePath: 'fluoh_test/${package.name}',
        ),
      );
      await runGit([
        'add',
        '-f',
        'fluoh.yaml',
        'FLUOH.md',
        'FLUOH_CHANGELOG.md',
        'AGENTS.md',
      ], workingDirectory: repository);
      if (migratedTestWorkspace || testInitResult.created) {
        await runGit(['add', '-A', 'fluoh_test'], workingDirectory: repository);
      }
    } catch (_) {
      await _restoreFiles(repository, originalFiles);
      await _rollbackTestWorkspaceChanges(
        repository: repository,
        migrated: migratedTestWorkspace,
        existingPackage: existingPackage,
        addedPackage: package.name,
        addedWorkspaceExisted: packageTestWorkspaceExisted,
      );
      rethrow;
    }
    _output.success('Registered package ${package.name} at $packagePath.');
    _output.next(
      'Adapt ${package.name}, then release it with '
      '"fluoh pub release --package ${package.name}".',
    );
    return 0;
  }

  Future<void> _appendPackageDocs({
    required Directory repository,
    required PubManifest manifest,
    required PubRepositoryDocPackage package,
  }) async {
    final guide = File('${repository.path}/FLUOH.md');
    await _writeOrAppendMarkdown(
      guide,
      (includeTitle) => pubAdaptationGuideContent(
        packages: [package],
        upstreamRef: manifest.upstreamRef,
        sdkVersion: manifest.sdkVersion,
        branch: manifest.branch,
        includeTitle: includeTitle,
      ),
    );

    final changelog = File('${repository.path}/FLUOH_CHANGELOG.md');
    final changelogContent = await changelog.exists()
        ? await changelog.readAsString()
        : null;
    if (changelogContent == null || changelogContent.trim().isEmpty) {
      await changelog.writeAsString(
        pubFluohChangelogContent(
          packages: [package],
          sdkVersion: manifest.sdkVersion,
          releaseVersion: initialPubReleaseVersion,
        ),
      );
    } else {
      final entry = pubFluohChangelogEntryLines(
        package: package,
        sdkVersion: manifest.sdkVersion,
        releaseVersion: initialPubReleaseVersion,
      ).join('\n');
      await changelog.writeAsString(
        '$changelogContent${markdownAppendSeparator(changelogContent)}$entry',
      );
    }

    await writeOrAppendPubAgentsInstructions(
      destination: repository,
      packages: [package],
      upstreamRef: manifest.upstreamRef,
      sdkVersion: manifest.sdkVersion,
      branch: manifest.branch,
    );
  }

  Future<void> _writeOrAppendMarkdown(
    File file,
    String Function(bool includeTitle) content,
  ) async {
    final existing = await file.exists() ? await file.readAsString() : null;
    if (existing == null || existing.trim().isEmpty) {
      await file.writeAsString(content(true));
      return;
    }
    await file.writeAsString(
      '$existing${markdownAppendSeparator(existing)}${content(false)}',
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

  Future<bool> _migrateRootTestWorkspaceForMultiPackage(
    Directory repository,
    PubManifest manifest,
  ) async {
    if (manifest.packages.length != 1) {
      return false;
    }
    final existingPackage = manifest.packages.single;
    final root = Directory('${repository.path}/fluoh_test');
    final rootPubspec = File('${root.path}/pubspec.yaml');
    if (!await rootPubspec.exists()) {
      return false;
    }
    if (!await _testWorkspaceTargetsPackage(
      rootPubspec,
      existingPackage.name,
    )) {
      return false;
    }

    final scoped = Directory('${root.path}/${existingPackage.name}');
    if (await scoped.exists()) {
      throw UsageException(
        'Cannot move fluoh_test to ${existingPackage.name}: '
            '${scoped.path} already exists.',
        '',
      );
    }

    final temporary = Directory(
      '${repository.path}/.fluoh_test_${existingPackage.name}_migration',
    );
    if (await temporary.exists()) {
      throw UsageException(
        'Cannot move fluoh_test because ${temporary.path} already exists.',
        '',
      );
    }

    await root.rename(temporary.path);
    await root.create(recursive: true);
    await temporary.rename(scoped.path);
    _output.info(
      'Moved existing fluoh_test to fluoh_test/${existingPackage.name}.',
    );
    return true;
  }

  Future<void> _rollbackTestWorkspaceChanges({
    required Directory repository,
    required bool migrated,
    required String? existingPackage,
    required String addedPackage,
    required bool addedWorkspaceExisted,
  }) async {
    final root = Directory('${repository.path}/fluoh_test');
    if (migrated && existingPackage != null) {
      final scopedExisting = Directory('${root.path}/$existingPackage');
      final temporary = Directory(
        '${repository.path}/.fluoh_test_${existingPackage}_rollback_'
        '${DateTime.now().microsecondsSinceEpoch}',
      );
      if (await scopedExisting.exists()) {
        await scopedExisting.rename(temporary.path);
      }
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
      if (await temporary.exists()) {
        await temporary.rename(root.path);
      }
      return;
    }

    final addedWorkspace = Directory('${root.path}/$addedPackage');
    if (!addedWorkspaceExisted && await addedWorkspace.exists()) {
      await addedWorkspace.delete(recursive: true);
    }
  }

  Future<bool> _testWorkspaceTargetsPackage(
    File pubspec,
    String packageName,
  ) async {
    final yaml = loadYaml(await pubspec.readAsString());
    if (yaml is! YamlMap) {
      return false;
    }
    final dependencies = yaml['dependencies'];
    return dependencies is YamlMap && dependencies[packageName] != null;
  }
}
