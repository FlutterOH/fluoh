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
    String invocation = 'fluoh flutter <args>',
    String? globalHelpInvocation,
  }) : _stdout = stdout,
       _stderr = stderr,
       _output = output ?? TerminalOutput(stdout: stdout, stderr: stderr),
       _inheritStdio = inheritStdio,
       _invocation = invocation,
       _globalHelpInvocation = globalHelpInvocation;

  final FluohEnvironment environment;
  final OutputWriter _stdout;
  final OutputWriter _stderr;
  final TerminalOutput _output;
  final bool _inheritStdio;
  final String _invocation;
  final String? _globalHelpInvocation;

  @override
  final ArgParser argParser = ArgParser.allowAnything();

  @override
  String get name => 'flutter';

  @override
  String get description =>
      "Run the selected Flutter OHOS SDK's flutter command.";

  @override
  String get invocation => _invocation;

  @override
  String get usage {
    final helpInvocation =
        _globalHelpInvocation ?? '${runner!.executableName} help';
    return [
      description,
      '',
      'Usage: $invocation',
      '-h, --help    Print this usage information.',
      '',
      'All other arguments are passed to flutter.',
      '',
      'Run "$helpInvocation" to see global options.',
    ].join('\n');
  }

  @override
  Future<int> run() async {
    if (_isHelpRequest(argResults!.rest)) {
      _output.write(usage);
      return 0;
    }
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

bool _isHelpRequest(List<String> arguments) {
  return arguments.length == 1 &&
      const {'help', '--help', '-h'}.contains(arguments.single);
}
