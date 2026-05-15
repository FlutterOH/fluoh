import 'dart:io' as io;

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import '../clean/clean_command.dart';
import '../context/fluoh_environment.dart';
import '../doctor/doctor_command.dart';
import '../pub/commands/pub_command.dart';
import '../sdk/flutter_command.dart';
import '../sdk/sdk_commands.dart';
import '../source/source_commands.dart';
import '../source/source_runtime.dart';
import '../testing/test_commands.dart';
import '../upgrade/upgrade_command.dart';
import '../version.dart';
import 'command_suggestions.dart';
import 'command_usage.dart';
import 'terminal_output.dart';

typedef OutputWriter = void Function(String message);

class FluohCommandRunner extends CommandRunner<int> {
  FluohCommandRunner({
    String executableName = 'fluoh',
    OutputWriter? stdout,
    OutputWriter? stderr,
    FluohEnvironment? environment,
    Iterable<Command<int>> commands = const <Command<int>>[],
    String? flutterInvocation,
    String? flutterGlobalHelpInvocation,
  }) : _stdout = stdout ?? print,
       _stderr = stderr ?? print,
       _environment = environment ?? FluohEnvironment.current(),
       _output = TerminalOutput(
         stdout: stdout ?? print,
         stderr: stderr ?? print,
         transient: stdout == null ? io.stdout.write : null,
         style: TerminalStyle(
           capabilities: TerminalCapabilities.detect(
             enableFormatting: stdout == null,
             environment:
                 (environment ?? FluohEnvironment.current()).processEnvironment,
           ),
         ),
       ),
       super(
         executableName,
         'CLI for Flutter OHOS SDKs and package workflows.',
         suggestionDistanceLimit: 0,
       ) {
    final env = _environment;
    addCommand(
      FlutterCommand(
        environment: env,
        stdout: _stdout,
        stderr: _stderr,
        output: _output,
        inheritStdio: stdout == null && stderr == null,
        invocation: flutterInvocation ?? '$executableName flutter <args>',
        globalHelpInvocation: flutterGlobalHelpInvocation,
      ),
    );
    addCommand(
      CleanCommand(
        environment: env,
        stdout: _stdout,
        stderr: _stderr,
        output: _output,
        inheritStdio: stdout == null && stderr == null,
      ),
    );
    addCommand(SdkCommand(environment: env, stdout: _stdout, output: _output));
    addCommand(
      PubCommand(
        environment: env,
        stdout: _stdout,
        stderr: _stderr,
        output: _output,
      ),
    );
    addCommand(
      TestCommand(
        environment: env,
        stdout: _stdout,
        stderr: _stderr,
        output: _output,
      ),
    );
    addCommand(
      SourceCommand(environment: env, stdout: _stdout, output: _output),
    );
    addCommand(
      DoctorCommand(environment: env, stdout: _stdout, output: _output),
    );
    addCommand(
      UpgradeCommand(stdout: _stdout, stderr: _stderr, output: _output),
    );

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
  final TerminalOutput _output;

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

  @override
  Future<int> run(Iterable<String> args) async {
    try {
      final results = parse(args);
      if (results.flag('version')) {
        _printVersionInformation();
        return 0;
      }
      _throwUnknownCommandUsage(results);

      if (_usesSourceConfiguration(results) &&
          _repairsSourceSnapshots(results)) {
        await SourceRuntime(_environment).rebuildLock(
          output: _output.style.capabilities.decorated ? _output : null,
        );
      }

      return await runCommand(results) ?? 0;
    } on UsageException catch (error) {
      _output.error(error.message);
      _output.writeError('');
      _output.writeError(error.usage);
      return 64;
    } on FormatException catch (error) {
      _output.error(error.message);
      return 64;
    }
  }

  void _printVersionInformation() {
    final dartVersion = io.Platform.version.split(' ').first;
    final style = _output.style;
    _output.write(
      '${style.header('fluoh')} ${style.value(packageVersion)} - '
      'CLI for Flutter OHOS SDKs and package workflows',
    );
    _output.write('${style.label('Dart')} $dartVersion');
    _output.write(
      '${style.label('Platform')} ${io.Platform.operatingSystem} '
      '${io.Platform.operatingSystemVersion}',
    );
    _output.write(
      '${style.label('Repository')} '
      '${style.url('https://github.com/FlutterOH/fluoh')}',
    );
  }

  void _throwUnknownCommandUsage(ArgResults results) {
    var currentResults = results;
    var availableCommands = commands;
    Command<int>? command;
    var commandString = executableName;

    while (availableCommands.isNotEmpty) {
      final parsedCommand = currentResults.command;
      if (parsedCommand == null) {
        if (currentResults.rest.isEmpty) {
          return;
        }

        final requested = currentResults.rest.first;
        final suggestions = commandSuggestionsText(
          requested,
          availableCommands.values,
          commandPrefix: commandString,
        );
        if (command == null) {
          usageException(
            'Could not find a command named "$requested".$suggestions',
          );
        }
        command.usageException(
          'Could not find a subcommand named "$requested" for '
          '"$commandString".$suggestions',
        );
      }

      command = availableCommands[parsedCommand.name];
      if (command == null) {
        return;
      }
      commandString = '$commandString ${parsedCommand.name}';
      currentResults = parsedCommand;
      if (_hasHelpFlag(currentResults)) {
        return;
      }
      availableCommands = command.subcommands;
    }
  }

  String get _usageWithoutDescription {
    final usagePrefix = 'Usage:';
    return [
      '$usagePrefix $invocation',
      '',
      'Global options:',
      argParser.usage,
      '',
      formatCommandUsage(
        commands,
        sections: _topLevelCommandSections,
        isSubcommand: false,
        lineLength: argParser.usageLineLength,
        style: _output.style,
      ),
      '',
      'Shortcut: use "fluohf <flutter-args>" for '
          '"fluoh flutter <flutter-args>".',
      '',
      'Run "$executableName help <command>" for more information about a command.',
    ].join('\n');
  }
}

const _topLevelCommandSections = [
  CommandUsageSection('', [
    'flutter',
    'source',
    'sdk',
    'pub',
    'test',
    'clean',
    'doctor',
    'upgrade',
  ]),
];

bool _usesSourceConfiguration(ArgResults results) {
  if (_hasHelpFlag(results)) {
    return false;
  }
  if (results.command?.name == 'pub' &&
      results.command?.command?.name == 'get') {
    return false;
  }
  final commandName = results.command?.name;
  return commandName != null &&
      const {'source', 'sdk', 'doctor', 'pub', 'test'}.contains(commandName);
}

bool _hasHelpFlag(ArgResults results) {
  if (results.options.contains('help') && results.flag('help')) {
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

Future<int> runFluohFlutter(
  List<String> arguments, {
  OutputWriter? stdout,
  OutputWriter? stderr,
  FluohEnvironment? environment,
}) {
  return FluohCommandRunner(
    executableName: 'fluohf',
    stdout: stdout,
    stderr: stderr,
    environment: environment,
    flutterInvocation: 'fluohf <args>',
    flutterGlobalHelpInvocation: 'fluoh help',
  ).run(['flutter', ...arguments]);
}
