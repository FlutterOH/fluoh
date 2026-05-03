import 'dart:io' as io;

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import '../adapter/adapter_commands.dart';
import '../config/fluoh_config.dart';
import '../context/fluoh_environment.dart';
import '../deps/deps_commands.dart';
import '../doctor/doctor_command.dart';
import '../sdk/sdk_commands.dart';
import '../source/source_commands.dart';
import '../source/source_sync.dart';
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
       _environment = environment ?? FluohEnvironment.current(),
       super('fluoh', 'FlutterOH SDK and package adapter CLI.') {
    final env = _environment;
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
  final FluohEnvironment _environment;

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

      if (_usesSourceConfiguration(results)) {
        final config = await FluohConfigStore(_environment).load();
        if (_repairsSourceSnapshots(results)) {
          await ensureSourceSnapshots(config);
        }
      }

      return await runCommand(results) ?? 0;
    } on UsageException catch (error) {
      _stderr(error.message);
      _stderr('');
      _stderr(error.usage);
      return 64;
    } on FormatException catch (error) {
      _stderr(error.message);
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

bool _usesSourceConfiguration(ArgResults results) {
  if (_hasHelpFlag(results)) {
    return false;
  }
  final commandName = results.command?.name;
  return commandName != null &&
      const {
        'source',
        'sdk',
        'use',
        'deps',
        'doctor',
        'create',
        'release',
        'update',
      }.contains(commandName);
}

bool _hasHelpFlag(ArgResults results) {
  if (results.flag('help')) {
    return true;
  }
  final command = results.command;
  return command != null && _hasHelpFlag(command);
}

bool _repairsSourceSnapshots(ArgResults results) {
  if (results.command?.name != 'source') {
    return false;
  }
  final sourceResults = results.command!;
  final subcommand = sourceResults.command?.name;
  return subcommand == null || subcommand == 'list';
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
