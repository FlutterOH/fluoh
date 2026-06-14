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
    final cache = environment.projectCacheDirectory;

    late final _CleanStats stats;
    try {
      stats = await _cacheStats(cache);
    } on FileSystemException catch (error) {
      return _writeFailure(
        cache: Directory(error.path ?? cache.path),
        dryRun: dryRun,
        json: json,
        message: _fileSystemMessage(error),
      );
    }

    var deleted = false;
    try {
      if (!dryRun) {
        if (stats.exists) {
          await Directory(stats.path).delete(recursive: true);
          deleted = true;
        }
      }
    } on FileSystemException catch (error) {
      return _writeFailure(
        cache: Directory(error.path ?? cache.path),
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
        fields: {'dryRun': dryRun, 'deleted': deleted, 'cache': stats.toJson()},
      );
      return 0;
    }

    _writeHumanReport(stats: stats, dryRun: dryRun, deleted: deleted);
    return 0;
  }

  int _writeFailure({
    required Directory cache,
    required bool dryRun,
    required bool json,
    required String message,
    _CleanStats? stats,
  }) {
    final cleanStats =
        stats ??
        _CleanStats(
          path: cache.path,
          exists: false,
          files: 0,
          directories: 0,
          bytes: 0,
        );
    if (json) {
      writeMachineOutput(
        _stdout,
        command: name,
        ok: false,
        exitCode: 1,
        fields: {
          'dryRun': dryRun,
          'deleted': false,
          'cache': cleanStats.toJson(),
          'error': {'type': 'filesystem', 'message': message},
        },
      );
    } else {
      _output.error('Failed to clean fluoh cache: $message');
      _output.writeError('Cache path: ${cache.path}');
    }
    return 1;
  }

  void _writeHumanReport({
    required _CleanStats stats,
    required bool dryRun,
    required bool deleted,
  }) {
    if (!stats.exists) {
      _output.info('No cleanable cache found');
      _output.write('Cache path: ${stats.path}');
      return;
    }
    if (dryRun) {
      _output.info('Would remove fluoh cache');
    } else if (deleted) {
      _output.success('Removed fluoh cache');
    }
    _output.write('Cache path: ${stats.path}');
    _output.write('Files: ${stats.files}');
    _output.write('Directories: ${stats.directories}');
    _output.write('Bytes: ${stats.bytes}');
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
