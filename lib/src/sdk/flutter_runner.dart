import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

import '../cli/fluoh_command_runner.dart';
import '../cli/terminal_output.dart';
import '../context/fluoh_environment.dart';
import 'sdk_manager.dart';

Future<File> resolveFlutterExecutable({
  required FluohEnvironment environment,
  required TerminalOutput output,
  String usage = '',
}) async {
  final manager = SdkManager(environment);
  final sdkTag = await manager.currentSdkTag();
  if (sdkTag == null || sdkTag.isEmpty) {
    throw UsageException(
      'No SDK selected. Run "fluoh sdk use <version-or-series>".',
      usage,
    );
  }

  var sdkDirectory = manager.sdkDirectory(sdkTag);
  if (!await sdkDirectory.exists()) {
    final release = await manager.resolveRelease(sdkTag);
    sdkDirectory = await output.withProgress(
      'Installing Flutter OHOS SDK ${release.tag}; this may take a while.',
      () => manager.install(release),
      showWhenPlain: true,
    );
  }
  final flutter = File('${sdkDirectory.path}/bin/flutter');
  if (!await flutter.exists()) {
    throw UsageException(
      'Selected SDK $sdkTag does not contain bin/flutter.',
      '',
    );
  }
  return flutter;
}

Future<int> runSelectedFlutter({
  required FluohEnvironment environment,
  required List<String> arguments,
  required Directory workingDirectory,
  required OutputWriter stdout,
  required OutputWriter stderr,
  required TerminalOutput output,
  bool inheritStdio = false,
  String usage = '',
}) async {
  final flutter = await resolveFlutterExecutable(
    environment: environment,
    output: output,
    usage: usage,
  );
  final process = await Process.start(
    flutter.path,
    arguments,
    workingDirectory: workingDirectory.path,
    environment: environment.processEnvironment,
    mode: inheritStdio
        ? ProcessStartMode.inheritStdio
        : ProcessStartMode.normal,
  );
  if (inheritStdio) {
    return process.exitCode;
  }

  final stdoutDone = _writeLines(process.stdout, stdout);
  final stderrDone = _writeLines(process.stderr, stderr);
  final exitCode = await process.exitCode;
  await Future.wait([stdoutDone, stderrDone]);
  return exitCode;
}

Future<void> _writeLines(Stream<List<int>> stream, OutputWriter write) async {
  await for (final line
      in stream.transform(utf8.decoder).transform(const LineSplitter())) {
    write(line);
  }
}
