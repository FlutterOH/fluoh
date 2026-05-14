import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:pub_semver/pub_semver.dart';

import '../cli/terminal_output.dart';
import '../config/fluoh_config.dart';
import '../version.dart';
import 'source_index.dart';

Future<void> ensureSourceSnapshots(
  FluohConfig config, {
  TerminalOutput? output,
}) async {
  if (config.sources.isEmpty) {
    return;
  }

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

    try {
      await syncGitSource(entry.key, source, output: output);
    } on UsageException {
      // Source consumers can proceed when another configured snapshot is
      // readable. Explicit `source update` still reports sync failures.
    }
  }

  if (!await _hasReadableSource(config)) {
    throw UsageException(
      'No readable data source index found. Run "fluoh source update" or '
          '"fluoh source add <name> <path>".',
      '',
    );
  }
}

Future<bool> _hasReadableSource(FluohConfig config) async {
  for (final entry in config.sources.entries) {
    if (await _snapshotState(entry.key, entry.value) == _SnapshotState.valid) {
      return true;
    }
  }
  return false;
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
          label: 'fluoh.yaml sdk',
          present: source.hasSdkIndex,
          validate: () async => source.loadSdkIndex(),
        ),
        (
          label: 'fluoh.yaml manifests',
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
    throw UsageException('Source $name does not contain fluoh.yaml.', '');
  }

  try {
    await _validateSourceEnvironment(source);
    for (final entry in present) {
      await entry.validate();
    }
  } on UsageException catch (error) {
    throw UsageException('Source $name is not valid: ${error.message}', '');
  } on FormatException catch (error) {
    throw UsageException('Source $name is not valid: ${error.message}', '');
  } on FileSystemException catch (error) {
    throw UsageException(
      'Source $name could not be read: ${fileSystemMessage(error)}',
      '',
    );
  }
}

Future<void> _validateSourceEnvironment(SourceIndex source) async {
  final manifest = await source.loadRootManifest();
  final constraintText = manifest.fluohConstraint;
  if (constraintText == null || constraintText.trim().isEmpty) {
    return;
  }

  final constraint = VersionConstraint.parse(constraintText);
  final current = Version.parse(packageVersion);
  if (!constraint.allows(current)) {
    throw UsageException(
      'Requires fluoh $constraintText, current version is $packageVersion. '
          'Upgrade fluoh and try again.',
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
  final temp = await prepareLocalSourceSnapshot(name, source);
  try {
    await replaceSourceSnapshot(source: temp, destination: destination);
  } finally {
    await deleteIfExists(temp);
  }
}

Future<Directory> prepareLocalSourceSnapshot(
  String name,
  Directory source,
) async {
  final temp = await Directory.systemTemp.createTemp('fluoh_source_');
  try {
    await copySourceSnapshot(source, temp);
    await validateSource(name, SourceConfig(path: temp.path));
    return temp;
  } catch (_) {
    await deleteIfExists(temp);
    rethrow;
  }
}

Future<void> syncGitSource(
  String name,
  SourceConfig source, {
  TerminalOutput? output,
}) async {
  final localSource = localSourceDirectoryFromUrl(source.url);
  final temp = localSource == null
      ? await prepareGitSourceSnapshot(name, source, output: output)
      : await prepareLocalSourceSnapshot(name, localSource);
  try {
    await replaceSourceSnapshot(source: temp, destination: source.directory);
  } finally {
    await deleteIfExists(temp);
  }
}

Directory? localSourceDirectoryFromUrl(String? value) {
  if (value == null || !value.startsWith('file:')) {
    return null;
  }

  try {
    final uri = Uri.parse(value);
    if (uri.scheme != 'file') {
      return null;
    }
    if (uri.path.startsWith('/') || uri.hasAuthority) {
      return Directory(uri.toFilePath());
    }
    return Directory(Uri.decodeComponent(uri.path));
  } on FormatException {
    return Directory(value.substring('file:'.length));
  } on UnsupportedError {
    return Directory(value.substring('file:'.length));
  }
}

Future<Directory> prepareGitSourceSnapshot(
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
    return temp;
  } catch (_) {
    await deleteIfExists(temp);
    rethrow;
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
    await copySourceSnapshot(source, staging);
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

Future<void> copySourceSnapshot(Directory source, Directory destination) async {
  await destination.create(recursive: true);
  await _copyFileIfExists(
    File('${source.path}/fluoh.yaml'),
    File('${destination.path}/fluoh.yaml'),
  );
  await _copyDirectoryIfExists(
    Directory('${source.path}/manifests'),
    Directory('${destination.path}/manifests'),
  );
}

Future<void> _copyFileIfExists(File source, File destination) async {
  if (!await source.exists()) {
    return;
  }
  await destination.parent.create(recursive: true);
  await source.copy(destination.path);
}

Future<void> _copyDirectoryIfExists(
  Directory source,
  Directory destination,
) async {
  if (!await source.exists()) {
    return;
  }
  await for (final entity in source.list(recursive: true)) {
    final relative = _relativeEntityPath(source, entity);
    if (entity is Directory) {
      await Directory('${destination.path}/$relative').create(recursive: true);
    } else if (entity is File) {
      await _copyFileIfExists(entity, File('${destination.path}/$relative'));
    }
  }
}

String _relativeEntityPath(Directory root, FileSystemEntity entity) {
  final rootPath = root.absolute.path;
  final entityPath = entity.absolute.path;
  if (entityPath == rootPath) {
    return '';
  }
  return entityPath.substring(rootPath.length + 1);
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
