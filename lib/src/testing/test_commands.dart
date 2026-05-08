import 'package:args/command_runner.dart';

import '../cli/command_usage.dart';
import '../cli/fluoh_command_runner.dart';
import '../context/fluoh_environment.dart';
import 'test_workspace.dart';

class TestCommand extends Command<int> {
  TestCommand({
    required FluohEnvironment environment,
    required OutputWriter stdout,
    required OutputWriter stderr,
  }) : _stdout = stdout {
    addSubcommand(
      TestInitCommand(environment: environment, stdout: stdout, stderr: stderr),
    );
    addSubcommand(
      TestRunCommand(environment: environment, stdout: stdout, stderr: stderr),
    );
  }

  final OutputWriter _stdout;

  @override
  String get name => 'test';

  @override
  String get description => 'Manage FlutterOH adapter verification tests.';

  @override
  String get usage => '$description\n\n$_usageWithoutDescription';

  @override
  void printUsage() {
    _stdout(usage);
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
        sections: _testCommandSections,
        isSubcommand: true,
        lineLength: argParser.usageLineLength,
      ),
      '',
      'Run "${runner!.executableName} help" to see global options.',
    ].join('\n');
  }
}

class TestInitCommand extends Command<int> {
  TestInitCommand({
    required this.environment,
    required OutputWriter stdout,
    required OutputWriter stderr,
  }) : _stdout = stdout,
       _stderr = stderr {
    argParser.addFlag(
      'force',
      negatable: false,
      help: 'Replace an existing fluoh_test directory.',
    );
  }

  final FluohEnvironment environment;
  final OutputWriter _stdout;
  final OutputWriter _stderr;

  @override
  String get name => 'init';

  @override
  String get description => 'Create the fluoh_test verification workspace.';

  @override
  Future<int> run() async {
    await initializeFluohTestWorkspace(
      environment: environment,
      stdout: _stdout,
      stderr: _stderr,
      force: argResults!.flag('force'),
    );
    return 0;
  }
}

class TestRunCommand extends Command<int> {
  TestRunCommand({
    required this.environment,
    required OutputWriter stdout,
    required OutputWriter stderr,
  }) : _stdout = stdout,
       _stderr = stderr;

  final FluohEnvironment environment;
  final OutputWriter _stdout;
  final OutputWriter _stderr;

  @override
  String get name => 'run';

  @override
  String get description =>
      'Run adapter package tests and fluoh_test automated tests.';

  @override
  Future<int> run() {
    return runFluohTestWorkspace(
      environment: environment,
      stdout: _stdout,
      stderr: _stderr,
    );
  }
}

const _testCommandSections = [
  CommandUsageSection('', ['init', 'run']),
];
