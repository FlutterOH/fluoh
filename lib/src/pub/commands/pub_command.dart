import 'package:args/command_runner.dart';

import '../../cli/command_usage.dart';
import '../../cli/fluoh_command_runner.dart';
import '../../cli/terminal_output.dart';
import '../../context/fluoh_environment.dart';
import 'pub_add_command.dart';
import 'pub_create_command.dart';
import 'pub_dependency_commands.dart';
import 'pub_get_command.dart';
import 'pub_release_command.dart';
import 'pub_sync_command.dart';
import 'pub_upgrade_command.dart';

class PubCommand extends Command<int> {
  PubCommand({
    required FluohEnvironment environment,
    required OutputWriter stdout,
    required OutputWriter stderr,
    TerminalOutput? output,
  }) : _output = output ?? TerminalOutput(stdout: stdout, stderr: stderr) {
    addSubcommand(
      PubGetCommand(
        environment: environment,
        stdout: stdout,
        stderr: stderr,
        output: _output,
      ),
    );
    addSubcommand(
      PubCheckCommand(
        environment: environment,
        stdout: stdout,
        output: _output,
      ),
    );
    addSubcommand(
      PubFixCommand(environment: environment, stdout: stdout, output: _output),
    );
    addSubcommand(
      PubUpgradeCommand(
        environment: environment,
        stdout: stdout,
        output: _output,
      ),
    );
    addSubcommand(
      PubCreateCommand(
        environment: environment,
        stdout: stdout,
        stderr: stderr,
        output: _output,
      ),
    );
    addSubcommand(
      PubAddCommand(
        environment: environment,
        stdout: stdout,
        stderr: stderr,
        output: _output,
      ),
    );
    addSubcommand(
      PubSyncCommand(environment: environment, stdout: stdout, output: _output),
    );
    addSubcommand(
      PubReleaseCommand(
        environment: environment,
        stdout: stdout,
        stderr: stderr,
        output: _output,
      ),
    );
  }

  final TerminalOutput _output;

  @override
  String get name => 'pub';

  @override
  String get description =>
      'Manage FlutterOH package dependencies and pub repositories.';

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
        sections: _pubCommandSections,
        isSubcommand: true,
        lineLength: argParser.usageLineLength,
        style: _output.style,
      ),
      '',
      'Run "${runner!.executableName} help" to see global options.',
    ].join('\n');
  }
}

const _pubCommandSections = [
  CommandUsageSection('Project dependencies:', [
    'get',
    'check',
    'fix',
    'upgrade',
  ]),
  CommandUsageSection('FlutterOH pub repositories:', [
    'create',
    'add',
    'sync',
    'release',
  ]),
];
