import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io' as io;

import 'package:args/command_runner.dart';

import '../cli/fluoh_command_runner.dart';
import '../cli/terminal_output.dart';
import '../context/fluoh_environment.dart';
import 'sdk_manager.dart';

class SelectedToolResult {
  const SelectedToolResult({
    required this.exitCode,
    this.stdout = '',
    this.stderr = '',
  });

  final int exitCode;
  final String stdout;
  final String stderr;

  String get combinedOutput => [
    if (stdout.trim().isNotEmpty) stdout.trim(),
    if (stderr.trim().isNotEmpty) stderr.trim(),
  ].join('\n');
}

Future<io.File> resolveFlutterExecutable({
  required FluohEnvironment environment,
  required TerminalOutput output,
  String usage = '',
}) async {
  final manager = SdkManager(environment);
  final sdkVersion = await manager.currentSdkVersion();
  if (sdkVersion == null || sdkVersion.isEmpty) {
    throw UsageException(
      'No SDK selected. Run "fluoh sdk use <version-or-series>".',
      usage,
    );
  }

  var sdkDirectory = manager.sdkDirectory(sdkVersion);
  if (!await sdkDirectory.exists()) {
    final release = await manager.resolveRelease(sdkVersion);
    sdkDirectory = await output.withProgress(
      'Installing Flutter OHOS SDK ${release.tag}; this may take a while.',
      () => manager.install(release),
      showWhenPlain: true,
    );
  }
  final flutter = io.File('${sdkDirectory.path}/bin/flutter');
  if (!await flutter.exists()) {
    throw UsageException(
      'Selected SDK $sdkVersion does not contain bin/flutter.',
      '',
    );
  }
  return flutter;
}

Future<io.File> resolveDartExecutable({
  required FluohEnvironment environment,
  required TerminalOutput output,
  String usage = '',
}) async {
  final flutter = await resolveFlutterExecutable(
    environment: environment,
    output: output,
    usage: usage,
  );
  final dart = io.File('${flutter.parent.path}/dart');
  if (!await dart.exists()) {
    throw UsageException('Selected SDK does not contain bin/dart.', usage);
  }
  return dart;
}

Future<int> runSelectedFlutter({
  required FluohEnvironment environment,
  required List<String> arguments,
  required io.Directory workingDirectory,
  required OutputWriter stdout,
  required OutputWriter stderr,
  required TerminalOutput output,
  bool inheritStdio = false,
  String usage = '',
}) async {
  final result = await runSelectedFlutterResult(
    environment: environment,
    arguments: arguments,
    workingDirectory: workingDirectory,
    stdout: stdout,
    stderr: stderr,
    output: output,
    inheritStdio: inheritStdio,
    usage: usage,
  );
  return result.exitCode;
}

Future<SelectedToolResult> runSelectedFlutterResult({
  required FluohEnvironment environment,
  required List<String> arguments,
  required io.Directory workingDirectory,
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
  final captureInheritedStdio = inheritStdio && _isHapBuild(arguments);
  final process = await io.Process.start(
    flutter.path,
    arguments,
    workingDirectory: workingDirectory.path,
    environment: environment.processEnvironment,
    mode: inheritStdio && !captureInheritedStdio
        ? io.ProcessStartMode.inheritStdio
        : io.ProcessStartMode.normal,
  );
  if (inheritStdio && !captureInheritedStdio) {
    final exitCode = await process.exitCode;
    _reportFlutterFailureHint(
      exitCode: exitCode,
      arguments: arguments,
      output: output,
    );
    return SelectedToolResult(exitCode: exitCode);
  }

  final stdoutLines = _LineBuffer();
  final stderrLines = _LineBuffer();
  if (captureInheritedStdio) {
    unawaited(_forwardStdin(process.stdin));
  }
  final stdoutDone = captureInheritedStdio
      ? _teeLines(process.stdout, io.stdout, capture: stdoutLines.add)
      : _writeLines(process.stdout, stdout, capture: stdoutLines.add);
  final stderrDone = captureInheritedStdio
      ? _teeLines(process.stderr, io.stderr, capture: stderrLines.add)
      : _writeLines(process.stderr, stderr, capture: stderrLines.add);
  final exitCode = await process.exitCode;
  await Future.wait([stdoutDone, stderrDone]);
  _reportFlutterFailureHint(
    exitCode: exitCode,
    arguments: arguments,
    output: output,
    outputText: '${stdoutLines.text}\n${stderrLines.text}',
  );
  return SelectedToolResult(
    exitCode: exitCode,
    stdout: stdoutLines.text,
    stderr: stderrLines.text,
  );
}

Future<int> runSelectedDart({
  required FluohEnvironment environment,
  required List<String> arguments,
  required io.Directory workingDirectory,
  required OutputWriter stdout,
  required OutputWriter stderr,
  required TerminalOutput output,
  String usage = '',
}) async {
  final result = await runSelectedDartResult(
    environment: environment,
    arguments: arguments,
    workingDirectory: workingDirectory,
    stdout: stdout,
    stderr: stderr,
    output: output,
    usage: usage,
  );
  return result.exitCode;
}

Future<SelectedToolResult> runSelectedDartResult({
  required FluohEnvironment environment,
  required List<String> arguments,
  required io.Directory workingDirectory,
  required OutputWriter stdout,
  required OutputWriter stderr,
  required TerminalOutput output,
  String usage = '',
}) async {
  final dart = await resolveDartExecutable(
    environment: environment,
    output: output,
    usage: usage,
  );
  final process = await io.Process.start(
    dart.path,
    arguments,
    workingDirectory: workingDirectory.path,
    environment: environment.processEnvironment,
  );
  final stdoutLines = _LineBuffer();
  final stderrLines = _LineBuffer();
  final stdoutDone = _writeLines(
    process.stdout,
    stdout,
    capture: stdoutLines.add,
  );
  final stderrDone = _writeLines(
    process.stderr,
    stderr,
    capture: stderrLines.add,
  );
  final exitCode = await process.exitCode;
  await Future.wait([stdoutDone, stderrDone]);
  return SelectedToolResult(
    exitCode: exitCode,
    stdout: stdoutLines.text,
    stderr: stderrLines.text,
  );
}

Future<void> _forwardStdin(io.IOSink sink) async {
  try {
    await io.stdin.pipe(sink);
  } on Object {
    try {
      await sink.close();
    } on Object {
      // The child may exit before stdin forwarding completes.
    }
  }
}

Future<void> _teeLines(
  Stream<List<int>> stream,
  io.IOSink sink, {
  required void Function(String line) capture,
}) async {
  final lineTextBuffer = _LineTextBuffer(capture);
  await for (final chunk in stream) {
    sink.add(chunk);
    lineTextBuffer.addText(utf8.decode(chunk, allowMalformed: true));
  }
  lineTextBuffer.close();
  await sink.flush();
}

Future<void> _writeLines(
  Stream<List<int>> stream,
  OutputWriter write, {
  void Function(String line)? capture,
}) async {
  await for (final line
      in stream.transform(utf8.decoder).transform(const LineSplitter())) {
    capture?.call(line);
    write(line);
  }
}

void _reportFlutterFailureHint({
  required int exitCode,
  required List<String> arguments,
  required TerminalOutput output,
  String? outputText,
}) {
  if (exitCode == 0 || !_isHapBuild(arguments)) {
    return;
  }

  if (outputText != null && _looksLikeOhosSigningFailure(outputText)) {
    output.warningError(
      'OHOS HAP build reached signing and failed on local signing configuration',
    );
    output.writeError(
      'Configure DevEco Studio debug signing or local OHOS signingConfigs, '
      'then rerun "fluoh flutter build hap --debug".',
    );
    output.writeError(
      'Do not commit certificate paths, private keys, passwords, or signing profiles.',
    );
    return;
  }

  output.warningError('OHOS HAP build failed');
  output.writeError(
    outputText == null
        ? 'If the output above stopped at signing, configure DevEco Studio '
              'debug signing or local OHOS signingConfigs; otherwise fix the '
              'build error above first.'
        : 'No signing-only failure was detected. Fix the build error above '
              'before treating this as local signing setup.',
  );
}

bool _isHapBuild(List<String> arguments) {
  final buildIndex = arguments.indexOf('build');
  return buildIndex >= 0 && arguments.skip(buildIndex + 1).contains('hap');
}

bool _looksLikeOhosSigningFailure(String output) {
  final text = output.toLowerCase();
  return const [
    'signhap',
    'sign hap',
    'signingconfig',
    'signing config',
    'signingconfigs',
    'debug signing',
    'release signing',
    'certificate',
    'private key',
    'keystore',
    'p12',
    'provision',
  ].any(text.contains);
}

class _LineBuffer {
  static const _limit = 200;

  final Queue<String> _lines = Queue<String>();

  void add(String line) {
    if (_lines.length == _limit) {
      _lines.removeFirst();
    }
    _lines.add(line);
  }

  String get text => _lines.join('\n');
}

class _LineTextBuffer {
  _LineTextBuffer(this._capture);

  final void Function(String line) _capture;
  String _pending = '';

  void addText(String text) {
    final parts = '$_pending$text'.split(RegExp(r'\r\n?|\n'));
    for (final line in parts.take(parts.length - 1)) {
      if (line.isNotEmpty) {
        _capture(line);
      }
    }
    _pending = parts.last;
  }

  void close() {
    if (_pending.isNotEmpty) {
      _capture(_pending);
      _pending = '';
    }
  }
}
