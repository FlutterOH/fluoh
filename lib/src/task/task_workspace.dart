import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

import '../context/fluoh_environment.dart';

/// Schema version for project-local fluoh task metadata.
const fluohTaskSchema = 1;

/// Project-local task workspace rooted under `.fluoh/tasks`.
class TaskWorkspace {
  /// Creates a task workspace helper for [environment].
  const TaskWorkspace(this.environment);

  /// Creates a task workspace helper for [workingDirectory].
  factory TaskWorkspace.project(Directory workingDirectory) {
    return TaskWorkspace(
      FluohEnvironment(
        homeDirectory: Directory('${workingDirectory.path}/.fluoh'),
        workingDirectory: workingDirectory,
      ),
    );
  }

  /// Runtime environment.
  final FluohEnvironment environment;

  /// Directory containing all local tasks.
  Directory get tasksDirectory =>
      Directory('${environment.projectFluohDirectory.path}/tasks');

  /// Current task pointer.
  File get currentTaskFile =>
      File('${environment.projectFluohDirectory.path}/current-task.json');

  /// Returns the current task if it exists.
  Future<FluohTask?> current({String? taskId}) async {
    final explicit =
        _nonEmpty(taskId) ??
        _nonEmpty(environment.processEnvironment['FLUOH_TASK']);
    if (explicit != null) {
      final task = taskById(explicit);
      return await task.directory.exists() ? task : null;
    }
    if (!await currentTaskFile.exists()) {
      return null;
    }
    try {
      final decoded = jsonDecode(await currentTaskFile.readAsString());
      if (decoded is! Map) {
        return null;
      }
      final id = _nonEmpty(decoded['id']);
      if (id == null) {
        return null;
      }
      final task = taskById(id);
      return await task.directory.exists() ? task : null;
    } on Object {
      return null;
    }
  }

  /// Returns the current task, creating one when none exists.
  Future<FluohTask> resolveOrCreate({
    String? taskId,
    String type = 'workflow',
    String? scopeName,
    String? packageName,
  }) async {
    final existing = await current(taskId: taskId);
    if (existing != null) {
      return existing;
    }
    return start(type: type, scopeName: scopeName, packageName: packageName);
  }

  /// Starts a new task and makes it current.
  Future<FluohTask> start({
    String type = 'workflow',
    String? scopeName,
    String? packageName,
  }) async {
    final now = DateTime.now();
    final scope = _taskScope(scopeName: scopeName, packageName: packageName);
    final id = await _uniqueTaskId(now, type: type, scopeName: scope);
    final task = taskById(id);
    await task.directory.create(recursive: true);
    await task.manifestFile.writeAsString(
      _taskManifest(
        id: id,
        type: type,
        scopeName: scope,
        packageName: packageName,
        createdAt: now,
      ),
    );
    await task.stateFile.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert({'schema': fluohTaskSchema, 'kind': 'fluoh.taskState', 'taskId': id, 'status': 'running', 'createdAt': now.toIso8601String(), 'updatedAt': now.toIso8601String()})}\n',
    );
    await _writeCurrent(task, now);
    return task;
  }

  /// Clears the current task pointer.
  ///
  /// When [taskId] is provided, the pointer is removed only if it references
  /// that task. This lets cleanup commands delete non-current tasks without
  /// losing the active task selection.
  Future<void> clearCurrent({String? taskId}) async {
    if (!await currentTaskFile.exists()) {
      return;
    }
    if (taskId != null) {
      final currentId = await _currentTaskId();
      if (currentId != taskId) {
        return;
      }
    }
    await currentTaskFile.delete();
  }

  /// Returns the task with [id] without checking filesystem existence.
  FluohTask taskById(String id) {
    final safeId = _safeTaskId(id);
    return FluohTask(
      id: safeId,
      directory: Directory('${tasksDirectory.path}/$safeId'),
    );
  }

  /// Lists task directories in newest-first order.
  Future<List<FluohTask>> list() async {
    if (!await tasksDirectory.exists()) {
      return const [];
    }
    final tasks = <FluohTask>[];
    await for (final entity in tasksDirectory.list(followLinks: false)) {
      if (entity is Directory) {
        tasks.add(FluohTask(id: _basename(entity.path), directory: entity));
      }
    }
    tasks.sort(
      (a, b) => b.directory.statSync().modified.compareTo(
        a.directory.statSync().modified,
      ),
    );
    return tasks;
  }

  Future<void> _writeCurrent(FluohTask task, DateTime now) async {
    await currentTaskFile.parent.create(recursive: true);
    await currentTaskFile.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert({'schema': fluohTaskSchema, 'kind': 'fluoh.currentTask', 'id': task.id, 'path': task.relativePath(environment.workingDirectory), 'updatedAt': now.toIso8601String()})}\n',
    );
  }

  Future<String?> _currentTaskId() async {
    try {
      final decoded = jsonDecode(await currentTaskFile.readAsString());
      if (decoded is! Map) {
        return null;
      }
      return _nonEmpty(decoded['id']);
    } on Object {
      return null;
    }
  }

  Future<String> _uniqueTaskId(
    DateTime now, {
    required String type,
    required String scopeName,
  }) async {
    final base = _taskId(now, type: type, scopeName: scopeName);
    var id = base;
    var suffix = 2;
    while (await taskById(id).directory.exists()) {
      id = '$base-$suffix';
      suffix += 1;
    }
    return id;
  }
}

/// One project-local fluoh task.
class FluohTask {
  /// Creates a task reference.
  const FluohTask({required this.id, required this.directory});

  /// Task id.
  final String id;

  /// Task root directory.
  final Directory directory;

  /// Task metadata file.
  File get manifestFile => File('${directory.path}/task.yaml');

  /// Machine-readable task state file.
  File get stateFile => File('${directory.path}/state.json');

  /// Trace root for the task.
  Directory get tracesDirectory => Directory('${directory.path}/traces');

  /// Report root for the task.
  Directory get reportsDirectory => Directory('${directory.path}/reports');

  /// Evidence root for screenshots, logs, sessions, and UI state.
  Directory get evidenceDirectory => Directory('${directory.path}/evidence');

  /// Scratch root for cleanable intermediates.
  Directory get scratchDirectory => Directory('${directory.path}/scratch');

  /// Command result root.
  Directory get commandsDirectory => Directory('${directory.path}/commands');

  /// Screenshot evidence directory.
  Directory get screenshotDirectory =>
      Directory('${evidenceDirectory.path}/screenshots');

  /// Session evidence directory.
  Directory get sessionDirectory =>
      Directory('${evidenceDirectory.path}/sessions');

  /// Log evidence directory.
  Directory get logDirectory => Directory('${evidenceDirectory.path}/logs');

  /// Relative path from [root] to [directory].
  String relativePath(Directory root) {
    final rootPath = root.absolute.path;
    final path = directory.absolute.path;
    if (path == rootPath) {
      return '.';
    }
    if (path.startsWith('$rootPath/')) {
      return path.substring(rootPath.length + 1);
    }
    return path;
  }

  /// Converts this task reference to JSON.
  Map<String, Object?> toJson(Directory root) {
    return {
      'schema': fluohTaskSchema,
      'id': id,
      'path': directory.path,
      'relativePath': relativePath(root),
    };
  }
}

/// Returns a package or generic scope slug suitable for task paths.
String fluohTaskScopeSlug({String? scopeName, String? packageName}) {
  return _taskScope(scopeName: scopeName, packageName: packageName);
}

String _taskScope({String? scopeName, String? packageName}) {
  return _pathSlug(scopeName) ?? _pathSlug(packageName) ?? 'workspace';
}

String _taskId(
  DateTime now, {
  required String type,
  required String scopeName,
}) {
  final timestamp =
      '${now.year.toString().padLeft(4, '0')}'
      '${now.month.toString().padLeft(2, '0')}'
      '${now.day.toString().padLeft(2, '0')}-'
      '${now.hour.toString().padLeft(2, '0')}'
      '${now.minute.toString().padLeft(2, '0')}'
      '${now.second.toString().padLeft(2, '0')}';
  return '$timestamp-${_pathSlug(type) ?? 'task'}-$scopeName';
}

String _taskManifest({
  required String id,
  required String type,
  required String scopeName,
  required String? packageName,
  required DateTime createdAt,
}) {
  return '''
schema: $fluohTaskSchema
kind: fluoh.task
id: $id
type: ${_yamlScalar(type)}
scope:
  name: ${_yamlScalar(scopeName)}
${packageName == null ? '' : '  package: ${_yamlScalar(packageName)}\n'}createdAt: ${createdAt.toIso8601String()}
updatedAt: ${createdAt.toIso8601String()}
status: running
''';
}

String _yamlScalar(String value) {
  if (RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(value)) {
    return value;
  }
  return jsonEncode(value);
}

String _safeTaskId(String value) {
  final normalized = _pathSlug(value);
  if (normalized == null) {
    throw UsageException('Task id must not be empty.', '');
  }
  if (normalized != value) {
    throw UsageException('Task id contains unsupported path characters.', '');
  }
  return normalized;
}

String? _pathSlug(Object? value) {
  final text = _nonEmpty(value);
  if (text == null) {
    return null;
  }
  final normalized = text
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
      .replaceAll(RegExp(r'^[-._]+|[-._]+$'), '');
  return normalized.isEmpty ? null : normalized;
}

String? _nonEmpty(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

String _basename(String path) {
  final normalized = path.replaceAll('\\', '/');
  final index = normalized.lastIndexOf('/');
  return index == -1 ? normalized : normalized.substring(index + 1);
}
