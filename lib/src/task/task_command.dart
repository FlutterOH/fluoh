import 'dart:io';

import 'package:args/command_runner.dart';

import '../cli/argument_validation.dart';
import '../cli/command_usage.dart';
import '../cli/fluoh_command_runner.dart';
import '../cli/machine_output.dart';
import '../cli/terminal_output.dart';
import '../context/fluoh_environment.dart';
import 'task_workspace.dart';

/// Top-level `fluoh task` command group.
class TaskCommand extends FluohCommand<int> {
  /// Creates the task command group.
  TaskCommand({
    required FluohEnvironment environment,
    required OutputWriter stdout,
    TerminalOutput? output,
  }) : _output = output ?? TerminalOutput(stdout: stdout) {
    addSubcommand(
      TaskStartCommand(
        environment: environment,
        stdout: stdout,
        output: _output,
      ),
    );
    addSubcommand(
      TaskCurrentCommand(
        environment: environment,
        stdout: stdout,
        output: _output,
      ),
    );
    addSubcommand(
      TaskListCommand(
        environment: environment,
        stdout: stdout,
        output: _output,
      ),
    );
    addSubcommand(
      TaskStatusCommand(
        environment: environment,
        stdout: stdout,
        output: _output,
      ),
    );
    addSubcommand(
      TaskCleanCommand(
        environment: environment,
        stdout: stdout,
        output: _output,
      ),
    );
  }

  final TerminalOutput _output;

  @override
  String get name => 'task';

  @override
  String get description => 'Manage project-local fluoh task workspaces.';

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
          CommandUsageSection('Task workspaces:', [
            'start',
            'current',
            'list',
            'status',
            'clean',
          ]),
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

/// Starts a new task workspace.
class TaskStartCommand extends FluohCommand<int> {
  /// Creates the command.
  TaskStartCommand({
    required FluohEnvironment environment,
    required OutputWriter stdout,
    required TerminalOutput output,
  }) : _environment = environment,
       _stdout = stdout,
       _output = output {
    argParser
      ..addOption(
        'type',
        defaultsTo: 'workflow',
        valueHelp: 'name',
        help: 'Task type, such as packageSupport or appSupport.',
      )
      ..addOption('scope', valueHelp: 'name', help: 'Task scope name.')
      ..addOption('package', valueHelp: 'name', help: 'Package scope name.')
      ..addFlag('json', negatable: false, help: 'Print the task as JSON.');
  }

  final FluohEnvironment _environment;
  final OutputWriter _stdout;
  final TerminalOutput _output;

  @override
  String get name => 'start';

  @override
  String get description => 'Start a new project-local task workspace.';

  @override
  Future<int> run() async {
    expectNoArguments(argResults!, usageException);
    final task = await TaskWorkspace(_environment).start(
      type: _trimmedOption('type') ?? 'workflow',
      scopeName: _trimmedOption('scope'),
      packageName: _trimmedOption('package'),
    );
    final fields = {'task': task.toJson(_environment.workingDirectory)};
    if (argResults!.flag('json')) {
      writeMachineOutput(
        _stdout,
        command: 'task start',
        ok: true,
        exitCode: 0,
        fields: fields,
      );
    } else {
      _output.success('Task started');
      _output.info('Task: ${task.id}');
      _output.info('Path: ${task.relativePath(_environment.workingDirectory)}');
    }
    return 0;
  }

  String? _trimmedOption(String name) {
    final value = argResults!.option(name)?.trim();
    return value == null || value.isEmpty ? null : value;
  }
}

/// Prints the current task.
class TaskCurrentCommand extends FluohCommand<int> {
  /// Creates the command.
  TaskCurrentCommand({
    required FluohEnvironment environment,
    required OutputWriter stdout,
    required TerminalOutput output,
  }) : _environment = environment,
       _stdout = stdout,
       _output = output {
    argParser.addFlag(
      'json',
      negatable: false,
      help: 'Print the current task as JSON.',
    );
  }

  final FluohEnvironment _environment;
  final OutputWriter _stdout;
  final TerminalOutput _output;

  @override
  String get name => 'current';

  @override
  String get description => 'Print the current task workspace.';

  @override
  Future<int> run() async {
    expectNoArguments(argResults!, usageException);
    final task = await TaskWorkspace(_environment).current();
    final json = argResults!.flag('json');
    if (task == null) {
      if (json) {
        writeMachineOutput(
          _stdout,
          command: 'task current',
          ok: false,
          exitCode: 1,
          fields: {
            'error': {'type': 'missingTask', 'message': 'No current task.'},
          },
        );
      } else {
        _output.error('No current task');
      }
      return 1;
    }
    final fields = {'task': task.toJson(_environment.workingDirectory)};
    if (json) {
      writeMachineOutput(
        _stdout,
        command: 'task current',
        ok: true,
        exitCode: 0,
        fields: fields,
      );
    } else {
      _output.info('Task: ${task.id}');
      _output.info('Path: ${task.relativePath(_environment.workingDirectory)}');
    }
    return 0;
  }
}

/// Lists project-local tasks.
class TaskListCommand extends FluohCommand<int> {
  /// Creates the command.
  TaskListCommand({
    required FluohEnvironment environment,
    required OutputWriter stdout,
    required TerminalOutput output,
  }) : _environment = environment,
       _stdout = stdout,
       _output = output {
    argParser.addFlag('json', negatable: false, help: 'Print tasks as JSON.');
  }

  final FluohEnvironment _environment;
  final OutputWriter _stdout;
  final TerminalOutput _output;

  @override
  String get name => 'list';

  @override
  String get description => 'List project-local task workspaces.';

  @override
  Future<int> run() async {
    expectNoArguments(argResults!, usageException);
    final tasks = await TaskWorkspace(_environment).list();
    final fields = {
      'tasks': [
        for (final task in tasks) task.toJson(_environment.workingDirectory),
      ],
    };
    if (argResults!.flag('json')) {
      writeMachineOutput(
        _stdout,
        command: 'task list',
        ok: true,
        exitCode: 0,
        fields: fields,
      );
    } else if (tasks.isEmpty) {
      _output.info('No tasks found');
    } else {
      for (final task in tasks) {
        _output.write(
          '${task.id}  ${task.relativePath(_environment.workingDirectory)}',
        );
      }
    }
    return 0;
  }
}

/// Prints task status.
class TaskStatusCommand extends FluohCommand<int> {
  /// Creates the command.
  TaskStatusCommand({
    required FluohEnvironment environment,
    required OutputWriter stdout,
    required TerminalOutput output,
  }) : _environment = environment,
       _stdout = stdout,
       _output = output {
    argParser
      ..addOption('task', valueHelp: 'id', help: 'Task id. Defaults current.')
      ..addFlag('json', negatable: false, help: 'Print status as JSON.');
  }

  final FluohEnvironment _environment;
  final OutputWriter _stdout;
  final TerminalOutput _output;

  @override
  String get name => 'status';

  @override
  String get description => 'Summarize a task workspace.';

  @override
  Future<int> run() async {
    expectNoArguments(argResults!, usageException);
    final workspace = TaskWorkspace(_environment);
    final task = await workspace.current(taskId: _trimmedOption('task'));
    final json = argResults!.flag('json');
    if (task == null) {
      if (json) {
        writeMachineOutput(
          _stdout,
          command: 'task status',
          ok: false,
          exitCode: 1,
          fields: {
            'error': {'type': 'missingTask', 'message': 'Task not found.'},
          },
        );
      } else {
        _output.error('Task not found');
      }
      return 1;
    }
    final stats = await _taskStats(task);
    final fields = {
      'task': task.toJson(_environment.workingDirectory),
      'stats': stats,
    };
    if (json) {
      writeMachineOutput(
        _stdout,
        command: 'task status',
        ok: true,
        exitCode: 0,
        fields: fields,
      );
    } else {
      _output.info('Task: ${task.id}');
      _output.info('Path: ${task.relativePath(_environment.workingDirectory)}');
      _output.write('Files: ${stats['files']}');
      _output.write('Directories: ${stats['directories']}');
      _output.write('Bytes: ${stats['bytes']}');
    }
    return 0;
  }

  String? _trimmedOption(String name) {
    final value = argResults!.option(name)?.trim();
    return value == null || value.isEmpty ? null : value;
  }
}

/// Cleans task workspaces.
class TaskCleanCommand extends FluohCommand<int> {
  /// Creates the command.
  TaskCleanCommand({
    required FluohEnvironment environment,
    required OutputWriter stdout,
    required TerminalOutput output,
  }) : _environment = environment,
       _stdout = stdout,
       _output = output {
    argParser
      ..addOption('task', valueHelp: 'id', help: 'Task id. Defaults current.')
      ..addFlag('all', negatable: false, help: 'Clean every task workspace.')
      ..addFlag(
        'dry-run',
        negatable: false,
        help: 'Report cleanable task paths without deleting them.',
      )
      ..addFlag('json', negatable: false, help: 'Print clean result as JSON.');
  }

  final FluohEnvironment _environment;
  final OutputWriter _stdout;
  final TerminalOutput _output;

  @override
  String get name => 'clean';

  @override
  String get description => 'Remove task workspaces.';

  @override
  Future<int> run() async {
    expectNoArguments(argResults!, usageException);
    final workspace = TaskWorkspace(_environment);
    final all = argResults!.flag('all');
    final dryRun = argResults!.flag('dry-run');
    final json = argResults!.flag('json');
    final currentTask = all
        ? null
        : await workspace.current(taskId: _trimmedOption('task'));
    final tasks = all ? await workspace.list() : [?currentTask];
    if (tasks.isEmpty && !all) {
      if (json) {
        writeMachineOutput(
          _stdout,
          command: 'task clean',
          ok: false,
          exitCode: 1,
          fields: {
            'dryRun': dryRun,
            'deleted': false,
            'error': {'type': 'missingTask', 'message': 'Task not found.'},
          },
        );
      } else {
        _output.error('Task not found');
      }
      return 1;
    }
    if (tasks.isEmpty) {
      if (!dryRun) {
        await workspace.clearCurrent();
      }
      if (json) {
        writeMachineOutput(
          _stdout,
          command: 'task clean',
          ok: true,
          exitCode: 0,
          fields: {'dryRun': dryRun, 'deleted': false, 'tasks': const []},
        );
      } else {
        _output.info('No task workspaces found');
      }
      return 0;
    }
    final cleaned = <Map<String, Object?>>[];
    for (final task in tasks) {
      final stats = await _taskStats(task);
      cleaned.add({
        'task': task.toJson(_environment.workingDirectory),
        'stats': stats,
      });
      if (!dryRun && await task.directory.exists()) {
        await task.directory.delete(recursive: true);
        await workspace.clearCurrent(taskId: task.id);
      }
    }
    if (all && !dryRun) {
      await workspace.clearCurrent();
    }
    if (json) {
      writeMachineOutput(
        _stdout,
        command: 'task clean',
        ok: true,
        exitCode: 0,
        fields: {
          'dryRun': dryRun,
          'deleted': !dryRun && cleaned.isNotEmpty,
          'tasks': cleaned,
        },
      );
    } else if (dryRun) {
      _output.info('Would remove task workspaces');
      for (final task in tasks) {
        _output.write(task.relativePath(_environment.workingDirectory));
      }
    } else {
      _output.success('Removed task workspaces');
    }
    return 0;
  }

  String? _trimmedOption(String name) {
    final value = argResults!.option(name)?.trim();
    return value == null || value.isEmpty ? null : value;
  }
}

Future<Map<String, Object?>> _taskStats(FluohTask task) async {
  if (!await task.directory.exists()) {
    return {'exists': false, 'files': 0, 'directories': 0, 'bytes': 0};
  }
  var files = 0;
  var directories = 1;
  var bytes = 0;
  await for (final entity in task.directory.list(
    recursive: true,
    followLinks: false,
  )) {
    final stat = await entity.stat();
    if (stat.type == FileSystemEntityType.directory) {
      directories += 1;
    } else if (stat.type == FileSystemEntityType.file) {
      files += 1;
      bytes += stat.size;
    }
  }
  return {
    'exists': true,
    'files': files,
    'directories': directories,
    'bytes': bytes,
  };
}
