import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import '../cli/fluoh_command_runner.dart';
import '../cli/machine_output.dart';
import '../cli/terminal_output.dart';
import '../context/fluoh_environment.dart';
import '../sdk/flutter_runner.dart';
import '../sdk/sdk_manager.dart';
import '../sdk/sdk_project_environment.dart';
import '../sdk/sdk_release.dart';

/// Creates a Flutter project with a FlutterOH SDK.
class CreateCommand extends Command<int> {
  /// Creates the project creation subcommand.
  CreateCommand({
    required this.environment,
    required OutputWriter stdout,
    required OutputWriter stderr,
    TerminalOutput? output,
    bool inheritStdio = false,
  }) : _stdout = stdout,
       _stderr = stderr,
       _output = output ?? TerminalOutput(stdout: stdout, stderr: stderr),
       _inheritStdio = inheritStdio;

  /// Runtime environment used to resolve SDKs and create the project.
  final FluohEnvironment environment;
  final OutputWriter _stdout;
  final OutputWriter _stderr;
  final TerminalOutput _output;
  final bool _inheritStdio;

  @override
  /// Parser that accepts all arguments after `fluoh create`.
  final ArgParser argParser = ArgParser.allowAnything();

  @override
  String get name => 'create';

  @override
  String get description => 'Create a Flutter project with a Flutter OHOS SDK.';

  @override
  String get invocation => 'fluoh create [--sdk <version-or-series>] <args>';

  @override
  void printUsage() {
    final resolvedRunner = runner;
    if (resolvedRunner is FluohCommandRunner) {
      resolvedRunner.writeCommandUsage(usage);
      return;
    }
    _stdout(usage);
  }

  @override
  String get usage {
    return [
      description,
      '',
      'Usage: $invocation',
      '-h, --help                 Print this usage information.',
      '--sdk <version-or-series>  Flutter OHOS SDK to use. Defaults to the latest stable SDK.',
      '--json                     Print a machine-readable create report.',
      '',
      'All other arguments are passed to `flutter create`.',
      'Use `--` before a Flutter argument that should not be parsed by fluoh.',
      '',
      'Examples:',
      '  fluoh create demo_app --platforms=android,ios,ohos',
      '  fluoh create --sdk 3.35 -- --org com.example demo_app',
      '',
      'Run "${runner!.executableName} help" to see global options.',
    ].join('\n');
  }

  @override
  Future<int> run() async {
    final rawArguments = argResults!.arguments;
    late final _CreateArguments parsed;
    try {
      parsed = _parseCreateArguments(rawArguments);
    } on UsageException catch (error) {
      if (_rawRequestsJson(rawArguments)) {
        writeMachineErrorOutput(
          _stdout,
          command: 'create',
          exitCode: 64,
          type: 'usage',
          message: error.message,
        );
        return 64;
      }
      rethrow;
    }
    if (parsed.help) {
      _output.write(usage);
      return 0;
    }
    if (parsed.flutterArguments.isEmpty) {
      if (parsed.json) {
        writeMachineErrorOutput(
          _stdout,
          command: 'create',
          exitCode: 64,
          type: 'usage',
          message: 'Expected arguments for flutter create.',
        );
        return 64;
      }
      throw UsageException('Expected arguments for flutter create.', usage);
    }

    try {
      return await _runCreate(parsed);
    } on UsageException catch (error) {
      if (parsed.json) {
        writeMachineErrorOutput(
          _stdout,
          command: 'create',
          exitCode: 64,
          type: 'usage',
          message: error.message,
        );
        return 64;
      }
      rethrow;
    } on ProcessException catch (error) {
      if (parsed.json) {
        writeMachineErrorOutput(
          _stdout,
          command: 'create',
          exitCode: 1,
          type: 'process',
          message: 'Failed to run ${error.executable}: ${error.message}',
        );
        return 1;
      }
      rethrow;
    }
  }

  Future<int> _runCreate(_CreateArguments parsed) async {
    final sdk = await _resolveSdk(parsed.sdk, json: parsed.json);
    final flutter = File('${sdk.directory.path}/bin/flutter');
    if (!await flutter.exists()) {
      throw UsageException(
        'SDK ${sdk.version} does not contain bin/flutter.',
        usage,
      );
    }

    final targetDirectory = _targetDirectory(parsed.flutterArguments);
    late final _FlutterCreateResult createResult;
    try {
      if (parsed.json) {
        createResult = await _runFlutterCreate(
          flutter,
          parsed.flutterArguments,
          streamOutput: false,
        );
      } else {
        createResult = await _output.withProgress(
          'Running flutter create with Flutter OHOS SDK ${sdk.version}',
          () => _runFlutterCreate(
            flutter,
            parsed.flutterArguments,
            streamOutput: true,
          ),
          showWhenPlain: true,
        );
      }
    } on _FlutterCreateException catch (error) {
      if (parsed.json) {
        writeMachineOutput(
          _stdout,
          command: 'create',
          ok: false,
          exitCode: 1,
          fields: {
            'sdk': _sdkJson(sdk),
            'flutter': error.result.toJson(),
            'error': {
              'type': 'process',
              'message':
                  'flutter create failed with exit code ${error.result.exitCode}.',
            },
          },
        );
        return 1;
      }
      throw UsageException(
        'flutter create failed with exit code ${error.result.exitCode}.\n'
        '${_failureOutput(error.result.stdout, error.result.stderr)}',
        usage,
      );
    }

    if (targetDirectory == null || !await targetDirectory.exists()) {
      if (parsed.json) {
        writeMachineOutput(
          _stdout,
          command: 'create',
          ok: true,
          exitCode: 0,
          fields: {
            'sdk': _sdkJson(sdk),
            'project': null,
            'metadataWritten': false,
            'flutter': createResult.toJson(),
            'warnings': [
              'Created project could not be inferred; SDK metadata was not written.',
            ],
          },
        );
        return 0;
      }
      _output.warning(
        'Created project could not be inferred; SDK metadata was not written.',
      );
      return 0;
    }

    final targetEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: targetDirectory,
      processEnvironment: environment.processEnvironment,
    );
    final projectEnvironment = SdkProjectEnvironment(targetEnvironment);
    await projectEnvironment.writeSdkVersion(sdk.version);
    final ideLink = await projectEnvironment.linkIdeSdk(sdk.directory);
    if (parsed.json) {
      writeMachineOutput(
        _stdout,
        command: 'create',
        ok: true,
        exitCode: 0,
        fields: {
          'sdk': _sdkJson(sdk),
          'project': {'path': targetDirectory.path},
          'metadataWritten': true,
          'ideFlutterSdkLink': ideLink.path,
          'flutter': createResult.toJson(),
        },
      );
      return 0;
    }
    _output.info('Flutter OHOS SDK: ${_output.style.path(sdk.directory.path)}');
    _output.info('Project: ${_output.style.path(targetDirectory.path)}');
    _output.info('IDE Flutter SDK link: ${_output.style.path(ideLink.path)}');
    _output.success('Created FlutterOH project with SDK ${sdk.version}');
    return 0;
  }

  Future<_ResolvedCreateSdk> _resolveSdk(
    String? requested, {
    required bool json,
  }) async {
    final manager = SdkManager(environment);
    final query = requested?.trim();
    if (query != null && query.isNotEmpty) {
      try {
        final release = await manager.resolveRelease(query);
        final directory = await _installRelease(manager, release, json: json);
        return _ResolvedCreateSdk(version: release.tag, directory: directory);
      } on UsageException catch (error) {
        final installed = await manager.installedSdkTags();
        if (installed.contains(query)) {
          return _ResolvedCreateSdk(
            version: query,
            directory: manager.sdkDirectory(query),
          );
        }
        throw UsageException(error.message, usage);
      }
    }

    try {
      final releases = await manager.listReleases();
      if (releases.isNotEmpty) {
        final release = SdkManager.latestRelease(releases, preferStable: true);
        final directory = await _installRelease(manager, release, json: json);
        return _ResolvedCreateSdk(version: release.tag, directory: directory);
      }
    } on UsageException {
      // Fall back to locally installed SDKs below.
    }

    final installed = await manager.installedSdkTags();
    if (installed.isNotEmpty) {
      final version = installed.first;
      return _ResolvedCreateSdk(
        version: version,
        directory: manager.sdkDirectory(version),
      );
    }
    throw UsageException(
      'No Flutter OHOS SDK was found. Run "fluoh source update" or pass --sdk after installing an SDK.',
      usage,
    );
  }

  Future<Directory> _installRelease(
    SdkManager manager,
    SdkRelease release, {
    required bool json,
  }) async {
    final installed = await manager.sdkDirectory(release.tag).exists();
    if (json) {
      return manager.install(release);
    }
    return _output.withProgress(
      installed
          ? 'Using Flutter OHOS SDK ${release.tag}'
          : 'Installing Flutter OHOS SDK ${release.tag}; this may take a while.',
      () => manager.install(release),
      showWhenPlain: true,
    );
  }

  Future<_FlutterCreateResult> _runFlutterCreate(
    File flutter,
    List<String> flutterArguments, {
    required bool streamOutput,
  }) async {
    final arguments = ['create', ...flutterArguments];
    final process = await Process.start(
      flutter.path,
      arguments,
      workingDirectory: environment.workingDirectory.path,
      environment: selectedToolProcessEnvironment(
        environment: environment,
        tool: flutter,
      ),
      mode: _inheritStdio && streamOutput
          ? ProcessStartMode.inheritStdio
          : ProcessStartMode.normal,
    );
    if (_inheritStdio && streamOutput) {
      final exitCode = await process.exitCode;
      if (exitCode != 0) {
        throw _FlutterCreateException(
          _FlutterCreateResult(
            arguments: arguments,
            exitCode: exitCode,
            stdout: '',
            stderr: '',
          ),
        );
      }
      return _FlutterCreateResult(
        arguments: arguments,
        exitCode: exitCode,
        stdout: '',
        stderr: '',
      );
    }

    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();
    final stdoutDone = _collectProcessStream(
      process.stdout,
      stdoutBuffer,
      streamOutput ? _stdout : null,
    );
    final stderrDone = _collectProcessStream(
      process.stderr,
      stderrBuffer,
      streamOutput ? _stderr : null,
    );
    final exitCode = await process.exitCode;
    await Future.wait([stdoutDone, stderrDone]);
    final result = _FlutterCreateResult(
      arguments: arguments,
      exitCode: exitCode,
      stdout: stdoutBuffer.toString(),
      stderr: stderrBuffer.toString(),
    );
    if (exitCode != 0) {
      throw _FlutterCreateException(result);
    }
    return result;
  }

  Directory? _targetDirectory(List<String> flutterArguments) {
    final target = _lastPositionalArgument(flutterArguments);
    if (target == null || target.trim().isEmpty) {
      return null;
    }
    final directory = Directory(
      target.startsWith('/')
          ? target
          : '${environment.workingDirectory.path}/$target',
    );
    return directory.absolute;
  }
}

class _CreateArguments {
  const _CreateArguments({
    required this.sdk,
    required this.flutterArguments,
    required this.help,
    required this.json,
  });

  final String? sdk;
  final List<String> flutterArguments;
  final bool help;
  final bool json;
}

class _ResolvedCreateSdk {
  const _ResolvedCreateSdk({required this.version, required this.directory});

  final String version;
  final Directory directory;
}

class _FlutterCreateResult {
  const _FlutterCreateResult({
    required this.arguments,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final List<String> arguments;
  final int exitCode;
  final String stdout;
  final String stderr;

  Map<String, Object?> toJson() {
    return {
      'arguments': arguments,
      'exitCode': exitCode,
      'stdoutTail': _tail(stdout),
      'stderrTail': _tail(stderr),
    };
  }
}

class _FlutterCreateException implements Exception {
  const _FlutterCreateException(this.result);

  final _FlutterCreateResult result;
}

_CreateArguments _parseCreateArguments(List<String> raw) {
  String? sdk;
  var help = false;
  var json = false;
  final flutterArguments = <String>[];
  for (var index = 0; index < raw.length; index += 1) {
    final argument = raw[index];
    if (argument == '--') {
      flutterArguments.addAll(raw.sublist(index + 1));
      break;
    }
    if (argument == '-h' || argument == '--help' || argument == 'help') {
      help = true;
      continue;
    }
    if (argument == '--json') {
      json = true;
      continue;
    }
    if (argument == '--sdk') {
      if (index + 1 >= raw.length) {
        throw UsageException('Expected a value after --sdk.', '');
      }
      sdk = raw[index + 1];
      index += 1;
      continue;
    }
    if (argument.startsWith('--sdk=')) {
      sdk = argument.substring('--sdk='.length);
      continue;
    }
    flutterArguments.add(argument);
  }
  return _CreateArguments(
    sdk: sdk,
    flutterArguments: flutterArguments,
    help: help,
    json: json,
  );
}

bool _rawRequestsJson(List<String> raw) {
  for (final argument in raw) {
    if (argument == '--') {
      return false;
    }
    if (argument == '--json') {
      return true;
    }
  }
  return false;
}

const _flutterCreateValueOptions = {
  '--android-language',
  '--description',
  '--ios-language',
  '--org',
  '--platforms',
  '--project-name',
  '--sample',
  '--template',
  '-a',
  '-i',
  '-t',
};

String? _lastPositionalArgument(List<String> arguments) {
  String? positional;
  for (var index = 0; index < arguments.length; index += 1) {
    final argument = arguments[index];
    if (argument == '--') {
      for (final trailing in arguments.skip(index + 1)) {
        if (trailing.trim().isNotEmpty) {
          positional = trailing;
        }
      }
      break;
    }
    if (_optionConsumesFollowingValue(argument)) {
      index += 1;
      continue;
    }
    if (argument.startsWith('-')) {
      continue;
    }
    positional = argument;
  }
  return positional;
}

bool _optionConsumesFollowingValue(String argument) {
  if (argument.contains('=')) {
    return false;
  }
  return _flutterCreateValueOptions.contains(argument);
}

Future<void> _collectProcessStream(
  Stream<List<int>> stream,
  StringBuffer buffer,
  OutputWriter? writer,
) async {
  await for (final chunk in stream.transform(utf8.decoder)) {
    buffer.write(chunk);
    for (final line in const LineSplitter().convert(chunk)) {
      writer?.call(line);
    }
  }
}

Map<String, Object?> _sdkJson(_ResolvedCreateSdk sdk) {
  return {'version': sdk.version, 'path': sdk.directory.path};
}

String _failureOutput(String stdout, String stderr) {
  final output = [
    if (stdout.trim().isNotEmpty) stdout.trim(),
    if (stderr.trim().isNotEmpty) stderr.trim(),
  ].join('\n');
  return output.isEmpty ? 'No flutter output was captured.' : output;
}

String _tail(String value, {int maxCharacters = 12000}) {
  if (value.length <= maxCharacters) {
    return value;
  }
  return value.substring(value.length - maxCharacters);
}
