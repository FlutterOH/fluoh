import 'package:args/command_runner.dart';

import '../../cli/command_usage.dart';
import '../../cli/fluoh_command_runner.dart';
import '../../cli/terminal_output.dart';
import '../../context/fluoh_environment.dart';
import 'package_add_command.dart';
import 'package_check_command.dart';
import 'package_create_command.dart';
import 'package_release_command.dart';
import 'package_sync_command.dart';

class PackageCommand extends Command<int> {
  PackageCommand({
    required FluohEnvironment environment,
    required OutputWriter stdout,
    required OutputWriter stderr,
    TerminalOutput? output,
  }) : _output = output ?? TerminalOutput(stdout: stdout, stderr: stderr) {
    addSubcommand(
      PackageCreateCommand(
        environment: environment,
        stdout: stdout,
        stderr: stderr,
        output: _output,
      ),
    );
    addSubcommand(
      PackageAddCommand(
        environment: environment,
        stdout: stdout,
        stderr: stderr,
        output: _output,
      ),
    );
    addSubcommand(
      PackageSyncCommand(
        environment: environment,
        stdout: stdout,
        output: _output,
      ),
    );
    addSubcommand(
      PackageCheckCommand(
        environment: environment,
        stdout: stdout,
        stderr: stderr,
        output: _output,
      ),
    );
    addSubcommand(
      PackageReleaseCommand(
        environment: environment,
        stdout: stdout,
        stderr: stderr,
        output: _output,
      ),
    );
  }

  final TerminalOutput _output;

  @override
  String get name => 'package';

  @override
  String get description => 'Maintain FlutterOH package repositories.';

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
        sections: _packageCommandSections,
        isSubcommand: true,
        lineLength: argParser.usageLineLength,
        style: _output.style,
      ),
      '',
      'Run "${runner!.executableName} help" to see global options.',
    ].join('\n');
  }
}

const _packageCommandSections = [
  CommandUsageSection('Package repositories:', [
    'create',
    'add',
    'sync',
    'check',
    'release',
  ]),
];
