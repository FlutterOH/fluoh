import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

import '../cli/argument_validation.dart';
import '../cli/fluoh_command_runner.dart';
import '../cli/machine_output.dart';
import '../cli/terminal_output.dart';
import '../context/fluoh_environment.dart';
import '../schema/schema.dart';
import 'source_index.dart';
import 'source_sync.dart';

part 'source_check_helpers.dart';
part 'source_check_models.dart';
part 'source_check_flow.dart';
part 'source_check_setup.dart';
part 'source_check_release_plan.dart';
part 'source_check_release_verify.dart';
part 'source_check_support.dart';

/// Validates Source files and verifies declared Package releases.
class SourceCheckCommand extends FluohCommand<int> {
  /// Creates the Source check command.
  SourceCheckCommand({
    required this.environment,
    required this.stdout,
    TerminalOutput? output,
  }) : _output = output ?? TerminalOutput(stdout: stdout) {
    argParser
      ..addFlag('json', negatable: false, help: 'Print the result as JSON.')
      ..addFlag(
        'schema-only',
        negatable: false,
        help:
            'Only validate local Source YAML and indexes. Does not read Git '
            'diffs, check SDK tags, or verify declared Package releases.',
      )
      ..addOption(
        'base-ref',
        valueHelp: 'ref',
        help:
            'Git base ref used to detect changed manifests. Defaults to '
            'origin/HEAD, main, master, then HEAD~1. Cannot be used with '
            '--all.',
      )
      ..addFlag(
        'all',
        negatable: false,
        help:
            'Check all manifest routes instead of only changed manifests. '
            'Cannot be used with --base-ref.',
      )
      ..addMultiOption(
        'manifest',
        valueHelp: 'name',
        help:
            'Limit checks to a Source manifest route. May be passed more than '
            'once.',
      )
      ..addMultiOption(
        'package',
        valueHelp: 'name',
        help:
            'Limit declared Package release verification to a package name. '
            'May be passed more than once.',
      )
      ..addOption(
        'shard',
        valueHelp: 'index/total',
        help:
            'Run only one shard of the selected release check plan, for '
            'example 1/10.',
      )
      ..addOption(
        'concurrency',
        valueHelp: 'count',
        defaultsTo: '1',
        help: 'Maximum manifest repositories to verify in parallel.',
      )
      ..addOption(
        'fluoh-command',
        valueHelp: 'command',
        defaultsTo: 'fluoh',
        help:
            'fluoh command used for nested package checks during release '
            'verification. Use a quoted command when running from a local '
            'checkout.',
      )
      ..addOption(
        'work-root',
        valueHelp: 'path',
        help:
            'Temporary work parent directory for cloned Source and Package '
            'repositories.',
      )
      ..addFlag(
        'keep-work-root',
        negatable: false,
        help: 'Keep the per-run work directory after check.',
      )
      ..addFlag(
        'skip-release-checks',
        negatable: false,
        help: 'Skip declared Package release verification.',
      )
      ..addOption(
        'release-check-timeout',
        valueHelp: 'seconds',
        defaultsTo: '600',
        help: 'Timeout for each declared Package release check.',
      )
      ..addOption(
        'max-release-checks',
        valueHelp: 'count',
        defaultsTo: '20',
        help: 'Maximum release records to check across selected manifests.',
      );
  }

  /// Runtime environment used to resolve local paths.
  final FluohEnvironment environment;

  /// Writer for machine output.
  final OutputWriter stdout;
  final TerminalOutput _output;

  @override
  String get name => 'check';

  @override
  String get description =>
      'Validate Source files and verify declared Package releases.';

  @override
  String get invocation => 'fluoh source check [source]';

  @override
  Future<int> run() async {
    final json = argResults!.flag('json');
    try {
      final report = await _runCheck();
      if (json) {
        writeMachineOutput(
          stdout,
          command: 'source check',
          ok: report.ok,
          exitCode: report.exitCode,
          fields: report.toJson(),
        );
      } else {
        _printHumanReport(report);
      }
      return report.exitCode;
    } on UsageException catch (error) {
      if (!json) {
        rethrow;
      }
      writeMachineOutput(
        stdout,
        command: 'source check',
        ok: false,
        exitCode: 64,
        fields: {
          'recommendation': 'blocked',
          'errors': [error.message],
          'warnings': <String>[],
        },
      );
      return 64;
    } on FormatException catch (error) {
      if (!json) {
        rethrow;
      }
      writeMachineOutput(
        stdout,
        command: 'source check',
        ok: false,
        exitCode: 64,
        fields: {
          'recommendation': 'blocked',
          'errors': [error.message],
          'warnings': <String>[],
        },
      );
      return 64;
    }
  }
}
