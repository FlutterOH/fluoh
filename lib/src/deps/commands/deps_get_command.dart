import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import '../../cli/fluoh_command_runner.dart';
import '../../cli/terminal_output.dart';
import '../../context/fluoh_environment.dart';
import '../../package/package_examples.dart';
import '../../sdk/flutter_runner.dart';
import '../../package/manifest/package_manifest.dart';
import '../../package/manifest/pubspec_package.dart';

/// Runs `flutter pub get` for a project and package repository examples.
class DepsGetCommand extends Command<int> {
  /// Creates the project dependency fetch command.
  DepsGetCommand({
    required this.environment,
    required OutputWriter stdout,
    required OutputWriter stderr,
    TerminalOutput? output,
  }) : _stdout = stdout,
       _stderr = stderr,
       _output = output ?? TerminalOutput(stdout: stdout, stderr: stderr);

  /// Runtime environment used to resolve the selected Flutter SDK.
  final FluohEnvironment environment;
  final OutputWriter _stdout;
  final OutputWriter _stderr;
  final TerminalOutput _output;

  @override
  final ArgParser argParser = ArgParser.allowAnything();

  @override
  String get name => 'get';

  @override
  String get description =>
      'Run flutter pub get for the project and package examples.';

  @override
  String get invocation => 'fluoh deps get [arguments]';

  @override
  String get usage {
    return [
      description,
      '',
      'Usage: $invocation',
      '-h, --help    Print this usage information.',
      '',
      'All other arguments are passed to flutter pub get.',
      '',
      'Run "${runner!.executableName} help" to see global options.',
    ].join('\n');
  }

  @override
  void printUsage() {
    _output.write(usage);
  }

  @override
  Future<int> run() async {
    if (_isHelpRequest(argResults!.rest)) {
      printUsage();
      return 0;
    }

    final arguments = ['pub', 'get', ...argResults!.rest];
    for (final directory in await _pubGetDirectories()) {
      _output.step('Running flutter pub get in ${_relativePath(directory)}');
      final result = await runSelectedFlutter(
        environment: environment,
        arguments: arguments,
        workingDirectory: directory,
        stdout: _stdout,
        stderr: _stderr,
        output: _output,
        usage: usage,
      );
      if (result != 0) {
        _output.failure(
          'flutter pub get failed in ${_relativePath(directory)}',
        );
        return result;
      }
    }

    _output.success('Dependencies are up to date');
    return 0;
  }

  Future<List<Directory>> _pubGetDirectories() async {
    final directories = await _candidatePubGetDirectories();
    final existing = <Directory>[];
    final seen = <String>{};
    for (final directory in directories) {
      final pubspec = File('${directory.path}/pubspec.yaml');
      if (!await pubspec.exists()) {
        continue;
      }
      final absolutePath = directory.absolute.path;
      if (seen.add(absolutePath)) {
        existing.add(directory);
      }
    }
    if (existing.isEmpty) {
      throw UsageException('No pubspec.yaml found for pub get.', usage);
    }
    return existing;
  }

  Future<List<Directory>> _candidatePubGetDirectories() async {
    try {
      final manifest = await readPackageManifest(environment.workingDirectory);
      return [
        packageDirectory(environment.workingDirectory, manifest.package.path),
        ...await packageExampleDirectories(
          repository: environment.workingDirectory,
          packages: [manifest.package],
        ),
      ];
    } on UsageException catch (error) {
      if (!_isProjectFluohConfig(error)) {
        rethrow;
      }
    }
    return [
      environment.workingDirectory,
      if (await File(
        '${environment.workingDirectory.path}/example/pubspec.yaml',
      ).exists())
        Directory('${environment.workingDirectory.path}/example'),
    ];
  }

  bool _isProjectFluohConfig(UsageException error) {
    final message = error.message;
    return const {
          'Missing fluoh.yaml.',
          'fluoh.yaml missing "repository".',
          'fluoh.yaml missing "packages".',
          'fluoh.yaml missing "upstream".',
          'Expected "name" to be a non-empty string.',
          'Expected fluoh.yaml repository.git to be a YAML object.',
        }.contains(message) ||
        message.contains('must not contain "dependencyPolicy"');
  }

  String _relativePath(Directory directory) {
    final rawRoot = environment.workingDirectory.path;
    final rawPath = directory.path;
    if (rawPath == rawRoot) {
      return '.';
    }
    if (rawPath.startsWith('$rawRoot${Platform.pathSeparator}')) {
      return rawPath.substring(rawRoot.length + 1);
    }

    final root = environment.workingDirectory.absolute.path;
    final path = directory.absolute.path;
    if (path == root) {
      return '.';
    }
    if (path.startsWith('$root${Platform.pathSeparator}')) {
      return path.substring(root.length + 1);
    }
    return path;
  }

  bool _isHelpRequest(List<String> arguments) {
    return arguments.any(const {'-h', '--help'}.contains) ||
        arguments.length == 1 && arguments.single == 'help';
  }
}
