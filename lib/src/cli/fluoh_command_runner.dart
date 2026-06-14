import 'dart:io' as io;

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import '../context/fluoh_environment.dart';
import '../doctor/doctor_command.dart';
import '../deps/commands/deps_command.dart';
import '../package/commands/package_command.dart';
import '../platform/platform_target_commands.dart';
import '../project/create_command.dart';
import '../sdk/flutter_command.dart';
import '../sdk/sdk_commands.dart';
import '../source/source_commands.dart';
import '../source/source_runtime.dart';
import '../upgrade/upgrade_command.dart';
import '../version.dart';
import '../workflow/commands/plan_command.dart';
import '../workflow/commands/report_command.dart';
import '../workflow/commands/workflow_commands.dart';
import 'command_suggestions.dart';
import 'command_usage.dart';
import 'machine_output.dart';
import 'skill_command.dart';
import 'terminal_output.dart';

/// Callback used by commands to emit one complete output line.
typedef OutputWriter = void Function(String message);

/// Returns the line length used for help text in the current terminal.
int fluohUsageLineLength() {
  try {
    if (io.stdout.hasTerminal) {
      final columns = io.stdout.terminalColumns;
      return columns.clamp(40, defaultTerminalLineLength).toInt();
    }
  } on Object {
    // Fall through to a deterministic default for tests and non-TTY output.
  }
  return defaultTerminalLineLength;
}

/// Base class for `fluoh` commands.
///
/// It centralizes argument parser construction and routes usage text through
/// [FluohCommandRunner] so tests and embedded callers can capture output
/// without relying on global stdout.
abstract class FluohCommand<T> extends Command<T> {
  /// Creates a command with a parser configured for `fluoh` help wrapping.
  FluohCommand({int? usageLineLength})
    : _argParser = ArgParser(
        usageLineLength: usageLineLength ?? fluohUsageLineLength(),
      );

  final ArgParser _argParser;

  @override
  ArgParser get argParser => _argParser;

  @override
  void printUsage() {
    final resolvedRunner = runner;
    if (resolvedRunner is FluohCommandRunner) {
      (resolvedRunner as FluohCommandRunner).writeCommandUsage(usage);
      return;
    }
    io.stdout.writeln(usage);
  }
}

/// Command runner for the `fluoh` executable.
///
/// The runner wires all top-level commands, handles global options, keeps
/// machine-readable error output consistent, and repairs Source snapshots before
/// commands that consume Source data.
class FluohCommandRunner extends CommandRunner<int> {
  /// Creates the root command runner and registers built-in commands.
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
         lineLength: _outputLineLength(stdout),
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
         'CLI for FlutterOH SDKs, projects, and package adaptation workflows.',
         usageLineLength: fluohUsageLineLength(),
         suggestionDistanceLimit: 0,
       ) {
    final env = _environment;
    addCommand(SdkCommand(environment: env, stdout: _stdout, output: _output));
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
      CreateCommand(
        environment: env,
        stdout: _stdout,
        stderr: _stderr,
        output: _output,
        inheritStdio: stdout == null && stderr == null,
      ),
    );
    addCommand(
      DepsCommand(
        environment: env,
        stdout: _stdout,
        stderr: _stderr,
        output: _output,
      ),
    );
    addCommand(
      VerifyCommand(
        environment: env,
        stdout: _stdout,
        stderr: _stderr,
        output: _output,
      ),
    );
    addCommand(
      BuildCommand(
        environment: env,
        stdout: _stdout,
        stderr: _stderr,
        output: _output,
      ),
    );
    addCommand(
      RunCommand(
        environment: env,
        stdout: _stdout,
        stderr: _stderr,
        output: _output,
      ),
    );
    addCommand(
      AttachCommand(
        environment: env,
        stdout: _stdout,
        stderr: _stderr,
        output: _output,
        inheritStdio: stdout == null && stderr == null,
      ),
    );
    addCommand(PlanCommand(environment: env, stdout: _stdout, output: _output));
    addCommand(
      PackageCommand(
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
      DevicesCommand(environment: env, stdout: _stdout, output: _output),
    );
    addCommand(
      EmulatorsCommand(environment: env, stdout: _stdout, output: _output),
    );
    addCommand(
      DriveCommand(
        environment: env,
        stdout: _stdout,
        stderr: _stderr,
        output: _output,
      ),
    );
    addCommand(
      ReportCommand(environment: env, stdout: _stdout, output: _output),
    );
    addCommand(
      UpgradeCommand(stdout: _stdout, stderr: _stderr, output: _output),
    );
    addCommand(SkillCommand(stdout: _stdout, output: _output));
    addCommand(
      CleanCommand(environment: env, stdout: _stdout, output: _output),
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

  /// Writes command-specific usage text through the configured output writer.
  void writeCommandUsage(String usage) {
    _output.write(usage);
  }

  @override
  Never usageException(String message) {
    throw UsageException(message, _usageWithoutDescription);
  }

  @override
  Future<int> run(Iterable<String> args) async {
    _MachineOutputRequest? machineOutputRequest;
    try {
      final arguments = args.toList(growable: false);
      _throwUnknownLeadingCommandUsage(arguments);
      final results = parse(arguments);
      machineOutputRequest = _machineOutputRequest(results);
      if (results.flag('version')) {
        _printVersionInformation();
        return 0;
      }
      _throwUnknownCommandUsage(results);

      if (_usesSourceConfiguration(results) &&
          _repairsSourceSnapshots(results)) {
        await SourceRuntime(_environment).rebuildLock(
          output:
              machineOutputRequest == null &&
                  _output.style.capabilities.decorated
              ? _output
              : null,
        );
      }

      return await runCommand(results) ?? 0;
    } on UsageException catch (error) {
      if (machineOutputRequest != null) {
        writeMachineErrorOutput(
          _stdout,
          command: machineOutputRequest.command,
          exitCode: 64,
          type: 'usage',
          message: error.message,
        );
        return 64;
      }
      _output.error(error.message);
      _output.writeError('');
      _output.writeError(error.usage);
      return 64;
    } on FormatException catch (error) {
      if (machineOutputRequest != null) {
        writeMachineErrorOutput(
          _stdout,
          command: machineOutputRequest.command,
          exitCode: 64,
          type: 'format',
          message: error.message,
        );
        return 64;
      }
      _output.error(error.message);
      return 64;
    } on io.ProcessException catch (error) {
      if (machineOutputRequest != null) {
        writeMachineErrorOutput(
          _stdout,
          command: machineOutputRequest.command,
          exitCode: 1,
          type: 'process',
          message: 'Failed to run ${error.executable}: ${error.message}',
        );
        return 1;
      }
      if (error.executable == 'git') {
        _output.error(
          'git is not available. Install Git and make sure it is on PATH.',
        );
      } else {
        _output.error('Failed to run ${error.executable}: ${error.message}');
      }
      return 1;
    }
  }

  void _printVersionInformation() {
    final dartVersion = io.Platform.version.split(' ').first;
    final style = _output.style;
    _output.write(
      '${style.header('fluoh')} ${style.value(packageVersion)} - '
      'CLI for FlutterOH SDKs, projects, and package adaptation workflows',
    );
    _output.write('${style.label('Dart')} $dartVersion');
    _output.write(
      '${style.label('Platform')} ${io.Platform.operatingSystem} '
      '${_normalizedOperatingSystemVersion(io.Platform.operatingSystemVersion)}',
    );
    _output.write(
      '${style.label('Repository')} '
      '${style.url('https://github.com/FlutterOH/fluoh')}',
    );
  }

  void _throwUnknownLeadingCommandUsage(List<String> args) {
    if (args.isEmpty) {
      return;
    }
    final requested = args.first;
    if (requested.startsWith('-') ||
        requested == 'help' ||
        commands.containsKey(requested)) {
      return;
    }

    final suggestions = commandSuggestionsText(
      requested,
      commands.values,
      commandPrefix: executableName,
    );
    usageException('Could not find a command named "$requested".$suggestions');
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
      availableCommands = command.subcommands;
      if (_hasHelpFlag(currentResults) &&
          _helpDoesNotHideUnknownSubcommand(
            currentResults,
            availableCommands,
          )) {
        return;
      }
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

/// Normalizes platform version strings to match doctor and device output.
String _normalizedOperatingSystemVersion(String value) {
  return value
      .trim()
      .replaceFirst(RegExp(r'^Version\s+', caseSensitive: false), '')
      .replaceAllMapped(
        RegExp(r'\s*\((?:Build\s+)?([^)]+)\)', caseSensitive: false),
        (match) => ' ${match.group(1)}',
      );
}

class _MachineOutputRequest {
  const _MachineOutputRequest(this.command);

  final String command;
}

_MachineOutputRequest? _machineOutputRequest(ArgResults results) {
  var current = results;
  final commandParts = <String>[];
  while (current.command != null) {
    final command = current.command!;
    commandParts.add(command.name!);
    current = command;
  }
  if (commandParts.isEmpty) {
    return null;
  }
  if (!current.options.contains('json') || !current.flag('json')) {
    if (_pathEquals(commandParts, const ['create']) &&
        _createCommandRequestsJson(current.arguments)) {
      return _MachineOutputRequest(commandParts.join(' '));
    }
    return null;
  }
  return _MachineOutputRequest(commandParts.join(' '));
}

bool _createCommandRequestsJson(List<String> arguments) {
  for (final argument in arguments) {
    if (argument == '--') {
      return false;
    }
    if (argument == '--json') {
      return true;
    }
  }
  return false;
}

const _topLevelCommandSections = [
  CommandUsageSection('Fluoh', ['skill', 'doctor', 'flutter', 'upgrade']),
  CommandUsageSection('SDK & Metadata', ['sdk', 'source']),
  CommandUsageSection('Project', ['create', 'deps']),
  CommandUsageSection('Package', ['package']),
  CommandUsageSection('Workflow', [
    'plan',
    'verify',
    'build',
    'run',
    'attach',
    'drive',
    'report',
    'clean',
  ]),
  CommandUsageSection('Devices', ['devices', 'emulators']),
];

bool _usesSourceConfiguration(ArgResults results) {
  if (_hasHelpFlag(results)) {
    return false;
  }
  final commandPath = _parsedCommandPath(results);
  if (_pathEquals(commandPath, const ['deps', 'get'])) {
    return false;
  }
  if (_pathEquals(commandPath, const ['flutter'])) {
    return false;
  }
  final commandName = commandPath.isEmpty ? null : commandPath.first;
  return commandName != null &&
      const {
        'source',
        'sdk',
        'doctor',
        'create',
        'deps',
        'plan',
        'verify',
        'build',
        'run',
        'attach',
        'drive',
        'report',
        'package',
      }.contains(commandName);
}

List<String> _parsedCommandPath(ArgResults results) {
  final path = <String>[];
  var current = results;
  while (current.command != null) {
    final command = current.command!;
    path.add(command.name!);
    current = command;
  }
  return path;
}

bool _pathEquals(List<String> left, List<String> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

bool _hasHelpFlag(ArgResults results) {
  if (results.options.contains('help') && results.flag('help')) {
    return true;
  }
  final command = results.command;
  return command != null && _hasHelpFlag(command);
}

bool _helpDoesNotHideUnknownSubcommand(
  ArgResults results,
  Map<String, Command<int>> subcommands,
) {
  if (results.command != null || results.rest.isEmpty) {
    return true;
  }
  return subcommands.containsKey(results.rest.first);
}

bool _repairsSourceSnapshots(ArgResults results) {
  if (results.command?.name != 'source') {
    return false;
  }
  final sourceResults = results.command!;
  final sourceSubcommandResults = sourceResults.command;
  if (sourceSubcommandResults != null &&
      sourceSubcommandResults.rest.isNotEmpty) {
    return false;
  }
  final subcommand = sourceSubcommandResults?.name;
  return subcommand == null || subcommand == 'list';
}

int _outputLineLength(OutputWriter? stdout) {
  return stdout == null ? fluohUsageLineLength() : 1 << 30;
}

/// Runs `fluoh` with [arguments].
///
/// This helper is primarily used by tests and small embedding scenarios where
/// callers want to provide an isolated [environment] and capture stdout/stderr.
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

/// Runs the `fluohf` shortcut with [arguments].
///
/// `fluohf` delegates to the selected FlutterOH SDK's `flutter` executable.
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
