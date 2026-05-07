import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import '../cli/fluoh_command_runner.dart';
import '../context/fluoh_environment.dart';
import 'sdk_manager.dart';

class FlutterCommand extends Command<int> {
  FlutterCommand({
    required this.environment,
    required OutputWriter stdout,
    required OutputWriter stderr,
    bool inheritStdio = false,
  }) : _stdout = stdout,
       _stderr = stderr,
       _inheritStdio = inheritStdio;

  final FluohEnvironment environment;
  final OutputWriter _stdout;
  final OutputWriter _stderr;
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
    final manager = SdkManager(environment);
    final sdkTag = await manager.currentSdkTag();
    if (sdkTag == null || sdkTag.isEmpty) {
      usageException(
        'No SDK selected. Run "fluoh sdk use <version-or-series>".',
      );
    }

    var sdkDirectory = manager.sdkDirectory(sdkTag);
    if (!await sdkDirectory.exists()) {
      final release = await manager.resolveRelease(sdkTag);
      _stdout(
        'Installing Flutter OHOS SDK ${release.tag}; this may take a while.',
      );
      sdkDirectory = await manager.install(release);
    }
    final flutter = File('${sdkDirectory.path}/bin/flutter');
    if (!await flutter.exists()) {
      throw UsageException(
        'Selected SDK $sdkTag does not contain bin/flutter.',
        '',
      );
    }

    final process = await Process.start(
      flutter.path,
      argResults!.rest,
      workingDirectory: environment.workingDirectory.path,
      environment: environment.processEnvironment,
      mode: _inheritStdio
          ? ProcessStartMode.inheritStdio
          : ProcessStartMode.normal,
    );
    if (_inheritStdio) {
      return process.exitCode;
    }

    final stdoutDone = _writeLines(process.stdout, _stdout);
    final stderrDone = _writeLines(process.stderr, _stderr);
    final exitCode = await process.exitCode;
    await Future.wait([stdoutDone, stderrDone]);
    return exitCode;
  }
}

Future<void> _writeLines(Stream<List<int>> stream, OutputWriter write) async {
  await for (final line
      in stream.transform(utf8.decoder).transform(const LineSplitter())) {
    write(line);
  }
}
