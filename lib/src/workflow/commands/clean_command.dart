part of 'workflow_commands.dart';

/// Removes cleanable project-local workflow artifacts.
class CleanCommand extends FluohCommand<int> {
  /// Creates the clean command.
  CleanCommand({
    required this.environment,
    required OutputWriter stdout,
    TerminalOutput? output,
  }) : _stdout = stdout,
       _output = output ?? TerminalOutput(stdout: stdout) {
    argParser
      ..addOption('task', valueHelp: 'id', help: 'Task id. Defaults current.')
      ..addFlag(
        'tasks',
        negatable: false,
        help: 'Remove whole task workspaces instead of only scratch output.',
      )
      ..addFlag('all', negatable: false, help: 'Remove all task workspaces.')
      ..addFlag(
        'dry-run',
        negatable: false,
        help: 'Report cleanable artifacts without deleting them.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help: 'Print a machine-readable clean report.',
      );
  }

  /// Runtime environment used to locate the project cache directory.
  final FluohEnvironment environment;
  final OutputWriter _stdout;
  final TerminalOutput _output;

  @override
  String get name => 'clean';

  @override
  String get description => 'Remove cleanable project workflow artifacts.';

  @override
  Future<int> run() async {
    expectNoArguments(argResults!, usageException);
    final dryRun = argResults!.flag('dry-run');
    final json = argResults!.flag('json');
    final cleanAll = argResults!.flag('all');
    final cleanTasks = cleanAll || argResults!.flag('tasks');
    final workspace = TaskWorkspace(environment);
    final selectedTask = await workspace.current(
      taskId: _trimmedOption(argResults!, 'task'),
    );
    final targets = cleanAll
        ? [for (final task in await workspace.list()) task.directory]
        : cleanTasks
        ? [if (selectedTask != null) selectedTask.directory]
        : [if (selectedTask != null) selectedTask.scratchDirectory];
    if (targets.isEmpty && cleanAll) {
      if (!dryRun) {
        await workspace.clearCurrent();
      }
      if (json) {
        writeMachineOutput(
          _stdout,
          command: name,
          ok: true,
          exitCode: 0,
          fields: {'dryRun': dryRun, 'deleted': false, 'targets': const []},
        );
      } else {
        _output.info('No task workspaces found');
      }
      return 0;
    }
    if (targets.isEmpty) {
      if (json) {
        writeMachineOutput(
          _stdout,
          command: name,
          ok: false,
          exitCode: 1,
          fields: {
            'dryRun': dryRun,
            'deleted': false,
            'error': {'type': 'missingTask', 'message': 'No task selected.'},
          },
        );
      } else {
        _output.error('No task selected');
      }
      return 1;
    }

    late final List<_CleanStats> stats;
    try {
      stats = [for (final target in targets) await _cacheStats(target)];
    } on FileSystemException catch (error) {
      return _writeFailure(
        path: error.path,
        dryRun: dryRun,
        json: json,
        message: _fileSystemMessage(error),
      );
    }

    var deleted = false;
    try {
      if (!dryRun) {
        for (final stat in stats) {
          if (stat.exists) {
            await Directory(stat.path).delete(recursive: true);
            deleted = true;
          }
        }
        if (cleanAll) {
          await workspace.clearCurrent();
        } else if (cleanTasks && selectedTask != null) {
          await workspace.clearCurrent(taskId: selectedTask.id);
        }
      }
    } on FileSystemException catch (error) {
      return _writeFailure(
        path: error.path,
        dryRun: dryRun,
        json: json,
        message: _fileSystemMessage(error),
        stats: stats,
      );
    }

    if (json) {
      writeMachineOutput(
        _stdout,
        command: name,
        ok: true,
        exitCode: 0,
        fields: {
          'dryRun': dryRun,
          'deleted': deleted,
          'targets': [for (final stat in stats) stat.toJson()],
        },
      );
      return 0;
    }

    _writeHumanReport(stats: stats, dryRun: dryRun, deleted: deleted);
    return 0;
  }

  int _writeFailure({
    required String? path,
    required bool dryRun,
    required bool json,
    required String message,
    List<_CleanStats> stats = const [],
  }) {
    if (json) {
      writeMachineOutput(
        _stdout,
        command: name,
        ok: false,
        exitCode: 1,
        fields: {
          'dryRun': dryRun,
          'deleted': false,
          'targets': [for (final stat in stats) stat.toJson()],
          'error': {'type': 'filesystem', 'message': message},
        },
      );
    } else {
      _output.error('Failed to clean fluoh task output: $message');
      if (path != null && path.isNotEmpty) {
        _output.writeError('Path: $path');
      }
    }
    return 1;
  }

  void _writeHumanReport({
    required List<_CleanStats> stats,
    required bool dryRun,
    required bool deleted,
  }) {
    if (!stats.any((stat) => stat.exists)) {
      _output.info('No cleanable task output found');
      for (final stat in stats) {
        _output.write('Path: ${stat.path}');
      }
      return;
    }
    if (dryRun) {
      _output.info('Would remove fluoh task output');
    } else if (deleted) {
      _output.success('Removed fluoh task output');
    }
    for (final stat in stats) {
      _output.write('Path: ${stat.path}');
      _output.write('Files: ${stat.files}');
      _output.write('Directories: ${stat.directories}');
      _output.write('Bytes: ${stat.bytes}');
    }
  }
}

String _fileSystemMessage(FileSystemException error) {
  final path = error.path;
  if (path == null || path.isEmpty) {
    return error.message;
  }
  return '${error.message}: $path';
}

Future<_CleanStats> _cacheStats(Directory cache) async {
  if (!await cache.exists()) {
    return _CleanStats(
      path: cache.path,
      exists: false,
      files: 0,
      directories: 0,
      bytes: 0,
    );
  }

  var files = 0;
  var directories = 1;
  var bytes = 0;
  await for (final entity in cache.list(recursive: true, followLinks: false)) {
    final stat = await entity.stat();
    if (stat.type == FileSystemEntityType.directory) {
      directories += 1;
    } else if (stat.type == FileSystemEntityType.file) {
      files += 1;
      bytes += stat.size;
    }
  }

  return _CleanStats(
    path: cache.path,
    exists: true,
    files: files,
    directories: directories,
    bytes: bytes,
  );
}

class _CleanStats {
  const _CleanStats({
    required this.path,
    required this.exists,
    required this.files,
    required this.directories,
    required this.bytes,
  });

  final String path;
  final bool exists;
  final int files;
  final int directories;
  final int bytes;

  Map<String, Object?> toJson() {
    return {
      'path': path,
      'exists': exists,
      'files': files,
      'directories': directories,
      'bytes': bytes,
    };
  }
}
