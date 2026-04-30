import 'dart:io' as io;

import 'package:args/command_runner.dart';

import '../adapter/adapter_commands.dart';
import '../context/fluoh_environment.dart';
import '../deps/deps_commands.dart';
import '../doctor/doctor_command.dart';
import '../sdk/sdk_commands.dart';
import '../source/source_commands.dart';
import '../update/update_command.dart';
import '../upgrade/upgrade_command.dart';
import '../use/use_command.dart';
import '../version.dart';

typedef OutputWriter = void Function(String message);

class FluohCommandRunner extends CommandRunner<int> {
  FluohCommandRunner({
    OutputWriter? stdout,
    OutputWriter? stderr,
    FluohEnvironment? environment,
    Iterable<Command<int>> commands = const <Command<int>>[],
  }) : _stdout = stdout ?? print,
       _stderr = stderr ?? print,
       super('fluoh', 'FlutterOH SDK and package adapter CLI.') {
    final env = environment ?? FluohEnvironment.current();
    addCommand(SourceCommand(environment: env, stdout: _stdout));
    addCommand(SdkCommand(environment: env, stdout: _stdout));
    addCommand(UseCommand(environment: env, stdout: _stdout));
    addCommand(DepsCommand(environment: env, stdout: _stdout));
    addCommand(DoctorCommand(environment: env, stdout: _stdout));
    addCommand(CreateCommand(environment: env, stdout: _stdout));
    addCommand(ReleaseCommand(environment: env, stdout: _stdout));
    addCommand(UpgradeCommand(stdout: _stdout, stderr: _stderr));
    addCommand(UpdateCommand(environment: env, stdout: _stdout));

    argParser.addFlag(
      'version',
      negatable: false,
      help: 'Print the tool version.',
    );

    for (final command in commands) {
      addCommand(command);
    }
  }

  final OutputWriter _stdout;
  final OutputWriter _stderr;

  @override
  void printUsage() {
    _stdout(usage);
  }

  @override
  Future<int> run(Iterable<String> args) async {
    try {
      final results = parse(args);
      if (results.flag('version')) {
        _printVersionInformation();
        return 0;
      }

      return await runCommand(results) ?? 0;
    } on UsageException catch (error) {
      _stderr(error.message);
      _stderr('');
      _stderr(error.usage);
      return 64;
    }
  }

  void _printVersionInformation() {
    final dartVersion = io.Platform.version.split(' ').first;
    _stdout('fluoh $packageVersion - FlutterOH SDK and package adapter CLI');
    _stdout('Dart $dartVersion');
    _stdout(
      'Platform ${io.Platform.operatingSystem} '
      '${io.Platform.operatingSystemVersion}',
    );
    _stdout('Repository https://github.com/FlutterOH/fluoh');
  }
}

Future<int> runFluoh(
  List<String> arguments, {
  OutputWriter? stdout,
  OutputWriter? stderr,
  FluohEnvironment? environment,
}) {
  return FluohCommandRunner(
    stdout: stdout,
    stderr: stderr,
    environment: environment,
  ).run(arguments);
}
