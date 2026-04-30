import 'dart:io';

import 'package:args/command_runner.dart';

import '../cli/fluoh_command_runner.dart';

class UpgradeCommand extends Command<int> {
  UpgradeCommand({required OutputWriter stdout, OutputWriter? stderr})
    : _stdout = stdout,
      _stderr = stderr ?? stdout {
    argParser.addFlag(
      'yes',
      negatable: false,
      help: 'Execute the fluoh self-upgrade command.',
    );
  }

  final OutputWriter _stdout;
  final OutputWriter _stderr;

  @override
  String get name => 'upgrade';

  @override
  String get description => 'Upgrade the fluoh CLI tool itself.';

  @override
  Future<int> run() async {
    const executable = 'dart';
    const arguments = ['pub', 'global', 'activate', 'fluoh'];
    const displayCommand = 'dart pub global activate fluoh';

    if (!argResults!.flag('yes')) {
      _stdout('Upgrade command: $displayCommand');
      _stdout('Run with --yes to execute.');
      return 0;
    }

    final result = await Process.run(executable, arguments);
    if (result.stdout.toString().trim().isNotEmpty) {
      _stdout(result.stdout.toString().trimRight());
    }
    if (result.stderr.toString().trim().isNotEmpty) {
      _stderr(result.stderr.toString().trimRight());
    }

    return result.exitCode;
  }
}
