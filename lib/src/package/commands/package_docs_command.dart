import 'dart:io';

import 'package:args/command_runner.dart';

import '../../cli/argument_validation.dart';
import '../../cli/command_usage.dart';
import '../../cli/fluoh_command_runner.dart';
import '../../cli/terminal_output.dart';
import '../../context/fluoh_environment.dart';
import '../git/package_git.dart';
import '../manifest/package_manifest.dart';
import '../package_repository_docs.dart';

/// Maintains generated package repository documentation.
class PackageDocsCommand extends FluohCommand<int> {
  /// Creates the package docs command group.
  PackageDocsCommand({
    required FluohEnvironment environment,
    required OutputWriter stdout,
    required OutputWriter stderr,
    TerminalOutput? output,
  }) : _output = output ?? TerminalOutput(stdout: stdout, stderr: stderr) {
    addSubcommand(
      PackageDocsRefreshCommand(environment: environment, output: _output),
    );
  }

  final TerminalOutput _output;

  @override
  String get name => 'docs';

  @override
  String get description => 'Maintain generated package documentation.';

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

  String get _usageWithoutDescription {
    return [
      'Usage: $invocation',
      argParser.usage,
      '',
      formatCommandUsage(
        subcommands,
        sections: const [
          CommandUsageSection('Package documentation:', ['refresh']),
        ],
        isSubcommand: true,
        lineLength: argParser.usageLineLength,
        style: _output.style,
      ),
      '',
      'Run "${runner!.executableName} help" to see global options.',
    ].join('\n');
  }
}

/// Refreshes generated package repository documentation from `fluoh.yaml`.
class PackageDocsRefreshCommand extends FluohCommand<int> {
  /// Creates the package docs refresh command.
  PackageDocsRefreshCommand({
    required FluohEnvironment environment,
    required TerminalOutput output,
  }) : _environment = environment,
       _output = output {
    argParser.addFlag(
      'dry-run',
      abbr: 'n',
      negatable: false,
      help: 'Show documentation changes without writing files.',
    );
  }

  final FluohEnvironment _environment;
  final TerminalOutput _output;

  @override
  String get name => 'refresh';

  @override
  String get description => 'Refresh generated package documentation.';

  @override
  Future<int> run() async {
    expectNoArguments(argResults!, usageException);

    final repository = _environment.workingDirectory;
    final manifest = await readPackageManifest(repository);
    final packages = packageRepositoryDocPackagesForManifest(manifest);
    final updates = await _plannedUpdates(
      repository: repository,
      manifest: manifest,
      packages: packages,
    );

    final dryRun = argResults!.flag('dry-run');
    if (updates.isEmpty) {
      _output.success('Package docs are current');
      return 0;
    }

    if (dryRun) {
      _output.info('Package docs would be refreshed');
      for (final update in updates) {
        _output.detail(update.path);
      }
      return 0;
    }

    final branch = await currentBranch(repository);
    if (branch != manifest.branch) {
      usageException(
        'Current branch $branch does not match package branch '
        '${manifest.branch}.',
      );
    }
    await ensureCleanWorkingTree(repository, 'Package docs refresh');

    final snapshot = <String, String?>{};
    for (final update in updates) {
      final file = File('${repository.path}/${update.path}');
      snapshot[update.path] = await file.exists()
          ? await file.readAsString()
          : null;
    }

    try {
      for (final update in updates) {
        await File(
          '${repository.path}/${update.path}',
        ).writeAsString(update.content);
      }
    } on FileSystemException catch (error) {
      await _restoreFiles(repository, snapshot);
      throw UsageException(
        'Failed to refresh package documentation: ${error.message}',
        '',
      );
    } catch (_) {
      await _restoreFiles(repository, snapshot);
      rethrow;
    }

    _output.success('Refreshed package docs');
    for (final update in updates) {
      _output.detail(update.path);
    }
    return 0;
  }

  Future<List<_DocUpdate>> _plannedUpdates({
    required Directory repository,
    required PackageManifest manifest,
    required List<PackageRepositoryDocPackage> packages,
  }) async {
    final updates = <_DocUpdate>[];
    await _addUpdate(
      updates,
      repository: repository,
      path: 'FLUOH.md',
      contentBuilder: (existing) => updatedPackageImplementationGuideContent(
        packages: packages,
        existing: existing,
      ),
    );
    await _addUpdate(
      updates,
      repository: repository,
      path: 'AGENTS.md',
      contentBuilder: (existing) => updatedPackageAgentsInstructionsContent(
        packages: packages,
        existing: existing,
      ),
    );
    await _addUpdate(
      updates,
      repository: repository,
      path: 'FLUOH_CHANGELOG.md',
      contentBuilder: (existing) => _updatedChangelogContent(
        existing: existing,
        manifest: manifest,
        packages: packages,
      ),
    );
    return updates;
  }

  Future<void> _addUpdate(
    List<_DocUpdate> updates, {
    required Directory repository,
    required String path,
    required String? Function(String? existing) contentBuilder,
  }) async {
    final file = File('${repository.path}/$path');
    final existing = await file.exists() ? await file.readAsString() : null;
    final next = contentBuilder(existing);
    if (next == null || next == existing) {
      return;
    }
    updates.add(_DocUpdate(path: path, content: next));
  }

  String? _updatedChangelogContent({
    required String? existing,
    required PackageManifest manifest,
    required List<PackageRepositoryDocPackage> packages,
  }) {
    if (existing != null && existing.trim().isNotEmpty) {
      return null;
    }
    final packageDocs = {for (final package in packages) package.name: package};
    return [
      '# FlutterOH Changelog',
      '',
      for (final package in manifest.packages)
        ...packageFluohChangelogEntryLines(
          package: packageDocs[package.name]!,
          sdkVersion: manifest.sdkVersion,
          releaseVersion: package.releaseVersion,
        ),
    ].join('\n');
  }

  Future<void> _restoreFiles(
    Directory repository,
    Map<String, String?> snapshot,
  ) async {
    for (final entry in snapshot.entries) {
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
}

class _DocUpdate {
  const _DocUpdate({required this.path, required this.content});

  final String path;
  final String content;
}
