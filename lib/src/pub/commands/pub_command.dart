import 'package:args/command_runner.dart';

import '../../cli/command_usage.dart';
import '../../cli/fluoh_command_runner.dart';
import '../../context/fluoh_environment.dart';
import 'pub_adapt_command.dart';
import 'pub_create_command.dart';
import 'pub_dependency_commands.dart';
import 'pub_release_command.dart';
import 'pub_sync_command.dart';
import 'pub_upgrade_command.dart';

class PubCommand extends Command<int> {
  PubCommand({
    required FluohEnvironment environment,
    required OutputWriter stdout,
    required OutputWriter stderr,
  }) : _stdout = stdout {
    addSubcommand(PubCheckCommand(environment: environment, stdout: stdout));
    addSubcommand(PubFixCommand(environment: environment, stdout: stdout));
    addSubcommand(PubUpgradeCommand(environment: environment, stdout: stdout));
    addSubcommand(
      PubCreateCommand(
        environment: environment,
        stdout: stdout,
        stderr: stderr,
      ),
    );
    addSubcommand(PubSyncCommand(environment: environment, stdout: stdout));
    addSubcommand(PubAdaptCommand(environment: environment, stdout: stdout));
    addSubcommand(
      PubReleaseCommand(
        environment: environment,
        stdout: stdout,
        stderr: stderr,
      ),
    );
  }

  final OutputWriter _stdout;

  @override
  String get name => 'pub';

  @override
  String get description =>
      'Manage FlutterOH pub dependencies and repositories.';

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
        sections: _pubCommandSections,
        isSubcommand: true,
        lineLength: argParser.usageLineLength,
      ),
      '',
      'Run "${runner!.executableName} help" to see global options.',
    ].join('\n');
  }
}

const _pubCommandSections = [
  CommandUsageSection('Project dependencies:', ['check', 'fix', 'upgrade']),
  CommandUsageSection('Adapter repositories:', [
    'create',
    'sync',
    'adapt',
    'release',
  ]),
];
