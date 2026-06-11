import 'package:args/command_runner.dart';

import '../../cli/command_usage.dart';
import '../../cli/fluoh_command_runner.dart';
import '../../cli/terminal_output.dart';
import '../../context/fluoh_environment.dart';
import 'deps_get_command.dart';
import 'dependency_plan_commands.dart';
import 'deps_upgrade_command.dart';

/// `fluoh deps` command group.
class DepsCommand extends FluohCommand<int> {
  /// Creates the dependency command group and its subcommands.
  DepsCommand({
    required FluohEnvironment environment,
    required OutputWriter stdout,
    required OutputWriter stderr,
    TerminalOutput? output,
  }) : _output = output ?? TerminalOutput(stdout: stdout, stderr: stderr) {
    addSubcommand(
      DepsGetCommand(
        environment: environment,
        stdout: stdout,
        stderr: stderr,
        output: _output,
      ),
    );
    addSubcommand(
      DepsCheckCommand(
        environment: environment,
        stdout: stdout,
        output: _output,
      ),
    );
    addSubcommand(
      DepsFixCommand(environment: environment, stdout: stdout, output: _output),
    );
    addSubcommand(
      DepsUpgradeCommand(
        environment: environment,
        stdout: stdout,
        output: _output,
      ),
    );
  }

  final TerminalOutput _output;

  @override
  String get name => 'deps';

  @override
  String get description => 'Manage FlutterOH project dependencies.';

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
        sections: _depsCommandSections,
        isSubcommand: true,
        lineLength: argParser.usageLineLength,
        style: _output.style,
      ),
      '',
      'Run "${runner!.executableName} help" to see global options.',
    ].join('\n');
  }
}

const _depsCommandSections = [
  CommandUsageSection('Project dependencies:', [
    'get',
    'check',
    'fix',
    'upgrade',
  ]),
];
