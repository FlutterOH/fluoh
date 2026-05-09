import 'dart:io';

import 'package:args/command_runner.dart';

import '../cli/terminal_output.dart';
import '../config/fluoh_config.dart';
import 'source_index.dart';

Future<void> ensureSourceSnapshots(
  FluohConfig config, {
  TerminalOutput? output,
}) async {
  for (final entry in config.sources.entries) {
    final source = entry.value;
    final state = await _snapshotState(entry.key, source);
    if (state == _SnapshotState.valid) {
      continue;
    }

    if (source.url == null) {
      if (state == _SnapshotState.missing) {
        throw UsageException(
          'Source ${entry.key} cache is missing. Re-add the local source with '
              '"fluoh source add ${entry.key} <path>".',
          '',
        );
      }
      await validateSource(entry.key, source);
    }

    await syncGitSource(entry.key, source, output: output);
  }
}

Future<_SnapshotState> _snapshotState(
  String name,
  SourceConfig sourceConfig,
) async {
  final source = SourceIndex.directory(sourceConfig.directory);
  if (!source.hasSdkIndex && !source.hasPackageIndex) {
    return _SnapshotState.missing;
  }

  try {
    await validateSource(name, sourceConfig);
    return _SnapshotState.valid;
  } on UsageException {
    return _SnapshotState.invalid;
  }
}

enum _SnapshotState { missing, valid, invalid }

Future<void> validateSource(String name, SourceConfig sourceConfig) async {
  final source = SourceIndex.directory(sourceConfig.directory);
  final validators =
      <({String label, bool present, Future<void> Function() validate})>[
        (
          label: 'sdk/releases.yaml',
          present: source.hasSdkIndex,
          validate: () async => source.loadSdkIndex(),
        ),
        (
          label: 'packages/repositories.yaml',
          present: source.hasPackageIndex,
          validate: () async {
            await source.loadPackageIndex();
            await source.loadCompatibilityMatrix();
          },
        ),
      ];
  final present = validators
      .where((entry) => entry.present)
      .toList(growable: false);
  if (present.isEmpty) {
    throw UsageException(
      'Source $name does not contain sdk/releases.yaml or '
          'packages/repositories.yaml.',
      '',
    );
  }

  try {
    for (final entry in present) {
      await entry.validate();
    }
  } on FormatException catch (error) {
    throw UsageException('Source $name is not valid: ${error.message}', '');
  } on FileSystemException catch (error) {
    throw UsageException(
      'Source $name could not be read: ${fileSystemMessage(error)}',
      '',
    );
  }
}

String fileSystemMessage(FileSystemException error) {
  final path = error.path;
  if (path == null || path.isEmpty) {
    return error.message;
  }
  return '${error.message}: $path';
}

Future<void> syncLocalSource(
  String name,
  Directory source,
  Directory destination,
) async {
  final temp = await Directory.systemTemp.createTemp('fluoh_source_');
  try {
    await _copySourceSnapshot(source, temp);
    await validateSource(name, SourceConfig(path: temp.path));
    await replaceSourceSnapshot(source: temp, destination: destination);
  } finally {
    await deleteIfExists(temp);
  }
}

Future<void> syncGitSource(
  String name,
  SourceConfig source, {
  TerminalOutput? output,
}) async {
  final temp = await Directory.systemTemp.createTemp('fluoh_source_');
  try {
    await _withOptionalProgress(
      output,
      'Syncing source $name.',
      () => git([
        'clone',
        '--depth=1',
        '--single-branch',
        '--quiet',
        source.url!,
        temp.path,
      ]),
    );
    await deleteIfExists(Directory('${temp.path}/.git'));
    await validateSource(name, SourceConfig(path: temp.path));
    await replaceSourceSnapshot(source: temp, destination: source.directory);
  } finally {
    await deleteIfExists(temp);
  }
}

Future<T> _withOptionalProgress<T>(
  TerminalOutput? output,
  String message,
  Future<T> Function() task,
) {
  return output == null ? task() : output.withProgress(message, task);
}

Future<void> replaceSourceSnapshot({
  required Directory source,
  required Directory destination,
}) async {
  final parent = destination.parent;
  await parent.create(recursive: true);
  var staging = await parent.createTemp('.${basename(destination.path)}-next-');
  Directory? backup;
  try {
    await _copySourceSnapshot(source, staging);
    if (await destination.exists()) {
      backup = await destination.rename(
        '${parent.path}/.${basename(destination.path)}-previous-'
        '${DateTime.now().microsecondsSinceEpoch}',
      );
    }
    try {
      await staging.rename(destination.path);
      staging = Directory('');
    } catch (_) {
      if (backup != null && !await destination.exists()) {
        await backup.rename(destination.path);
        backup = null;
      }
      rethrow;
    }
  } finally {
    if (staging.path.isNotEmpty) {
      await deleteIfExists(staging);
    }
    if (backup != null) {
      await deleteIfExists(backup);
    }
  }
}

Future<void> _copySourceSnapshot(
  Directory source,
  Directory destination,
) async {
  await destination.create(recursive: true);
  await _copyFileIfExists(
    File('${source.path}/fluoh.yaml'),
    File('${destination.path}/fluoh.yaml'),
  );
  await _copyFileIfExists(
    File('${source.path}/sdk/releases.yaml'),
    File('${destination.path}/sdk/releases.yaml'),
  );
  await _copyFileIfExists(
    File('${source.path}/packages/repositories.yaml'),
    File('${destination.path}/packages/repositories.yaml'),
  );
  await _copyYamlFilesIfExists(
    Directory('${source.path}/packages/manifests'),
    Directory('${destination.path}/packages/manifests'),
  );
}

Future<void> _copyFileIfExists(File source, File destination) async {
  if (!await source.exists()) {
    return;
  }
  await destination.parent.create(recursive: true);
  await source.copy(destination.path);
}

Future<void> _copyYamlFilesIfExists(
  Directory source,
  Directory destination,
) async {
  if (!await source.exists()) {
    return;
  }
  await for (final entity in source.list(recursive: false)) {
    if (entity is! File || !entity.path.endsWith('.yaml')) {
      continue;
    }
    await _copyFileIfExists(
      entity,
      File('${destination.path}/${basename(entity.path)}'),
    );
  }
}

Future<void> deleteIfExists(FileSystemEntity entity) async {
  if (await entity.exists()) {
    await entity.delete(recursive: true);
  }
}

String basename(String path) {
  final normalized = path.endsWith(Platform.pathSeparator)
      ? path.substring(0, path.length - 1)
      : path;
  return normalized.split(Platform.pathSeparator).last;
}

Future<void> git(List<String> arguments, {Directory? workingDirectory}) async {
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: workingDirectory?.path,
  );
  if (result.exitCode != 0) {
    throw UsageException(
      'git ${arguments.join(' ')} failed:\n${result.stderr}',
      '',
    );
  }
}
