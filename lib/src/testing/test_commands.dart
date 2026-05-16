import 'package:args/command_runner.dart';

import '../cli/argument_validation.dart';
import '../cli/command_usage.dart';
import '../cli/fluoh_command_runner.dart';
import '../cli/terminal_output.dart';
import '../context/fluoh_environment.dart';
import 'test_workspace.dart';

class TestCommand extends Command<int> {
  TestCommand({
    required FluohEnvironment environment,
    required OutputWriter stdout,
    required OutputWriter stderr,
    TerminalOutput? output,
  }) : _output = output ?? TerminalOutput(stdout: stdout, stderr: stderr) {
    addSubcommand(
      TestInitCommand(
        environment: environment,
        stdout: stdout,
        stderr: stderr,
        output: _output,
      ),
    );
    addSubcommand(
      TestRunCommand(
        environment: environment,
        stdout: stdout,
        stderr: stderr,
        output: _output,
      ),
    );
  }

  final TerminalOutput _output;

  @override
  String get name => 'test';

  @override
  String get description => 'Manage FlutterOH package verification tests.';

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
        sections: _testCommandSections,
        isSubcommand: true,
        lineLength: argParser.usageLineLength,
        style: _output.style,
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
    TerminalOutput? output,
  }) : _stdout = stdout,
       _stderr = stderr {
    _output = output ?? TerminalOutput(stdout: stdout, stderr: stderr);
    argParser
      ..addOption(
        'package',
        valueHelp: 'name',
        help: 'Package to initialize tests for in a multi-package repository.',
      )
      ..addFlag(
        'force',
        negatable: false,
        help: 'Replace an existing fluoh_test directory.',
      );
  }

  final FluohEnvironment environment;
  final OutputWriter _stdout;
  final OutputWriter _stderr;
  late final TerminalOutput _output;

  @override
  String get name => 'init';

  @override
  String get description => 'Create the fluoh_test verification workspace.';

  @override
  Future<int> run() async {
    expectNoArguments(argResults!, usageException);
    await initializeFluohTestWorkspace(
      environment: environment,
      stdout: _stdout,
      stderr: _stderr,
      output: _output,
      force: argResults!.flag('force'),
      packageName: argResults!.option('package'),
    );
    return 0;
  }
}

class TestRunCommand extends Command<int> {
  TestRunCommand({
    required this.environment,
    required OutputWriter stdout,
    required OutputWriter stderr,
    TerminalOutput? output,
  }) : _stdout = stdout,
       _stderr = stderr {
    _output = output ?? TerminalOutput(stdout: stdout, stderr: stderr);
    argParser.addOption(
      'package',
      valueHelp: 'name',
      help: 'Package to test in a multi-package repository.',
    );
  }

  final FluohEnvironment environment;
  final OutputWriter _stdout;
  final OutputWriter _stderr;
  late final TerminalOutput _output;

  @override
  String get name => 'run';

  @override
  String get description => 'Run package tests and fluoh_test automated tests.';

  @override
  Future<int> run() {
    expectNoArguments(argResults!, usageException);
    return runFluohTestWorkspace(
      environment: environment,
      stdout: _stdout,
      stderr: _stderr,
      output: _output,
      packageName: argResults!.option('package'),
    );
  }
}

const _testCommandSections = [
  CommandUsageSection('', ['init', 'run']),
];
