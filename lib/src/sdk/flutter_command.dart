import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import '../cli/fluoh_command_runner.dart';
import '../cli/terminal_output.dart';
import '../context/fluoh_environment.dart';
import 'flutter_runner.dart';

class FlutterCommand extends Command<int> {
  FlutterCommand({
    required this.environment,
    required OutputWriter stdout,
    required OutputWriter stderr,
    TerminalOutput? output,
    bool inheritStdio = false,
  }) : _stdout = stdout,
       _stderr = stderr,
       _output = output ?? TerminalOutput(stdout: stdout, stderr: stderr),
       _inheritStdio = inheritStdio;

  final FluohEnvironment environment;
  final OutputWriter _stdout;
  final OutputWriter _stderr;
  final TerminalOutput _output;
  final bool _inheritStdio;

  @override
  final ArgParser argParser = ArgParser.allowAnything();

  @override
  String get name => 'flutter';

  @override
  String get description => 'Run flutter from the selected Flutter OHOS SDK.';

  @override
  String get invocation => 'fluoh flutter <args>';

  @override
  Future<int> run() async {
    return runSelectedFlutter(
      environment: environment,
      arguments: argResults!.rest,
      workingDirectory: environment.workingDirectory,
      stdout: _stdout,
      stderr: _stderr,
      output: _output,
      inheritStdio: _inheritStdio,
      usage: usage,
    );
  }
}
