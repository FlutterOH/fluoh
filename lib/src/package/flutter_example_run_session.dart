part of 'flutter_example_runner.dart';

Future<FlutterExampleRunResult> _runFlutterSmoke({
  required FluohEnvironment environment,
  required FluohEnvironment cacheEnvironment,
  required Directory workingDirectory,
  required List<String> arguments,
  required String platform,
  required FlutterDeviceTarget target,
  required FlutterEmulatorTarget? emulator,
  required OutputWriter stdout,
  required OutputWriter stderr,
  required TerminalOutput output,
  required Duration runDuration,
  required Duration launchTimeout,
  required File? sessionFile,
  required String usage,
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
    environment: selectedToolProcessEnvironment(
      environment: environment,
      tool: flutter,
    ),
  );
  final command = 'flutter ${arguments.join(' ')}';
  final stdoutBuffer = _LineBuffer();
  final stderrBuffer = _LineBuffer();
  final launchCompleter = Completer<void>();
  final failureCompleter = Completer<String>();
  String? vmServiceUri;
  var launchDetected = false;

  Future<void> writeSession(
    String status, {
    File? outputLog,
    int? exitCode,
    bool detached = false,
  }) {
    return _writeDebugSession(
      sessionFile: sessionFile,
      status: status,
      platform: platform,
      command: command,
      processId: process.pid,
      target: target,
      emulator: emulator,
      launchDetected: launchDetected,
      vmServiceUri: vmServiceUri,
      outputLog: outputLog,
      exitCode: exitCode,
      detached: detached,
    );
  }

  void inspect(String line) {
    final extractedVmServiceUri = _extractVmServiceUri(line);
    if (vmServiceUri == null && extractedVmServiceUri != null) {
      vmServiceUri = extractedVmServiceUri;
      unawaited(writeSession('running'));
    }
    final lower = line.toLowerCase();
    if (!launchCompleter.isCompleted && _looksLaunched(lower)) {
      launchDetected = true;
      launchCompleter.complete();
      unawaited(writeSession('running'));
    }
    if (!failureCompleter.isCompleted && _looksLikeRuntimeFailure(lower)) {
      failureCompleter.complete(line);
    }
  }

  final stdoutDone = _captureLines(
    process.stdout,
    stdout,
    capture: (line) {
      stdoutBuffer.add(line);
      inspect(line);
    },
  );
  final stderrDone = _captureLines(
    process.stderr,
    stderr,
    capture: (line) {
      stderrBuffer.add(line);
      inspect(line);
    },
  );
  final exitFuture = process.exitCode;
  unawaited(writeSession('starting'));
  final firstState = await Future.any<Object>([
    launchCompleter.future.then((_) => const _RunLaunched()),
    failureCompleter.future.then((line) => _RunFailure(line)),
    exitFuture.then((exitCode) => _RunExited(exitCode)),
    Future<void>.delayed(launchTimeout).then((_) => const _RunLaunchTimeout()),
  ]);

  if (firstState is _RunLaunchTimeout) {
    final exitCode = await _terminateProcess(process, exitFuture);
    await _waitForCapturedOutput([stdoutDone, stderrDone]);
    final outputLog = await _writeRunLog(
      cacheEnvironment,
      platform,
      stdoutBuffer.text,
      stderrBuffer.text,
    );
    await writeSession('failed', outputLog: outputLog, exitCode: exitCode);
    return _failedRunResult(
      platform: platform,
      command: command,
      target: target,
      emulator: emulator,
      outputLog: outputLog,
      code: '$platform.launch_timeout',
      message: 'Flutter example launch did not complete before the timeout',
      reason:
          'No Flutter launch signal was detected within ${launchTimeout.inSeconds}s.',
      details: {
        'exitCodeAfterKill': exitCode,
        'target': target.toJson(),
        if (emulator != null) 'emulator': emulator.toJson(),
        ..._sessionFileDetails(sessionFile),
        ..._vmServiceDetails(vmServiceUri),
        ..._bufferDetails(stdoutBuffer.text, stderrBuffer.text),
      },
    );
  }

  if (firstState is _RunFailure) {
    final exitCode = await _terminateProcess(process, exitFuture);
    await _waitForCapturedOutput([stdoutDone, stderrDone]);
    final outputLog = await _writeRunLog(
      cacheEnvironment,
      platform,
      stdoutBuffer.text,
      stderrBuffer.text,
    );
    await writeSession('failed', outputLog: outputLog, exitCode: exitCode);
    return _failedRunResult(
      platform: platform,
      command: command,
      target: target,
      emulator: emulator,
      outputLog: outputLog,
      code: '$platform.runtime_crash',
      message: 'Flutter example output indicates a runtime failure',
      reason: firstState.line,
      details: {
        'exitCodeAfterKill': exitCode,
        'target': target.toJson(),
        if (emulator != null) 'emulator': emulator.toJson(),
        ..._sessionFileDetails(sessionFile),
        ..._vmServiceDetails(vmServiceUri),
        ..._bufferDetails(stdoutBuffer.text, stderrBuffer.text),
      },
    );
  }

  if (firstState is _RunExited) {
    await _waitForCapturedOutput([stdoutDone, stderrDone]);
    final outputLog = await _writeRunLog(
      cacheEnvironment,
      platform,
      stdoutBuffer.text,
      stderrBuffer.text,
    );
    if (firstState.exitCode != 0) {
      await writeSession(
        'failed',
        outputLog: outputLog,
        exitCode: firstState.exitCode,
      );
      return _failedRunResult(
        platform: platform,
        command: command,
        target: target,
        emulator: emulator,
        outputLog: outputLog,
        code: '$platform.run_failed',
        message: 'Flutter example run failed',
        reason: 'flutter run exited with code ${firstState.exitCode}',
        details: {
          'exitCode': firstState.exitCode,
          'target': target.toJson(),
          if (emulator != null) 'emulator': emulator.toJson(),
          ..._sessionFileDetails(sessionFile),
          ..._vmServiceDetails(vmServiceUri),
          ..._bufferDetails(stdoutBuffer.text, stderrBuffer.text),
        },
      );
    }
    if (launchDetected) {
      await writeSession(
        'passed',
        outputLog: outputLog,
        exitCode: firstState.exitCode,
      );
      return FlutterExampleRunResult(
        exitCode: 0,
        platform: platform,
        command: command,
        target: target,
        emulator: emulator,
        outputLog: outputLog,
        diagnostics: const [],
        details: {
          'target': target.toJson(),
          if (emulator != null) 'emulator': emulator.toJson(),
          if (outputLog != null) 'outputLog': outputLog.path,
          ..._sessionFileDetails(sessionFile),
          ..._vmServiceDetails(vmServiceUri),
          'processExited': true,
          ..._bufferDetails(stdoutBuffer.text, stderrBuffer.text),
        },
      );
    }
    await writeSession(
      'failed',
      outputLog: outputLog,
      exitCode: firstState.exitCode,
    );
    return _failedRunResult(
      platform: platform,
      command: command,
      target: target,
      emulator: emulator,
      outputLog: outputLog,
      code: '$platform.launch_missing',
      message: 'Flutter example run exited before launch was detected',
      reason:
          'flutter run exited with code 0 before fluoh detected a launch signal',
      details: {
        'exitCode': firstState.exitCode,
        'target': target.toJson(),
        if (emulator != null) 'emulator': emulator.toJson(),
        ..._sessionFileDetails(sessionFile),
        ..._vmServiceDetails(vmServiceUri),
        ..._bufferDetails(stdoutBuffer.text, stderrBuffer.text),
      },
    );
  }

  final secondState = await Future.any<Object>([
    failureCompleter.future.then((line) => _RunFailure(line)),
    exitFuture.then((exitCode) => _RunExited(exitCode)),
    Future<void>.delayed(runDuration).then((_) => const _RunDurationElapsed()),
  ]);

  if (secondState is _RunFailure) {
    final exitCode = await _terminateProcess(process, exitFuture);
    await _waitForCapturedOutput([stdoutDone, stderrDone]);
    final outputLog = await _writeRunLog(
      cacheEnvironment,
      platform,
      stdoutBuffer.text,
      stderrBuffer.text,
    );
    await writeSession('failed', outputLog: outputLog, exitCode: exitCode);
    return _failedRunResult(
      platform: platform,
      command: command,
      target: target,
      emulator: emulator,
      outputLog: outputLog,
      code: '$platform.runtime_crash',
      message: 'Flutter example output indicates a runtime failure',
      reason: secondState.line,
      details: {
        'exitCodeAfterKill': exitCode,
        'target': target.toJson(),
        if (emulator != null) 'emulator': emulator.toJson(),
        ..._sessionFileDetails(sessionFile),
        ..._vmServiceDetails(vmServiceUri),
        ..._bufferDetails(stdoutBuffer.text, stderrBuffer.text),
      },
    );
  }

  var detachRequested = false;
  if (secondState is _RunExited) {
    await _waitForCapturedOutput([stdoutDone, stderrDone]);
    final outputLog = await _writeRunLog(
      cacheEnvironment,
      platform,
      stdoutBuffer.text,
      stderrBuffer.text,
    );
    if (secondState.exitCode != 0) {
      await writeSession(
        'failed',
        outputLog: outputLog,
        exitCode: secondState.exitCode,
      );
      return _failedRunResult(
        platform: platform,
        command: command,
        target: target,
        emulator: emulator,
        outputLog: outputLog,
        code: '$platform.run_failed',
        message: 'Flutter example run failed',
        reason: 'flutter run exited with code ${secondState.exitCode}',
        details: {
          'exitCode': secondState.exitCode,
          'target': target.toJson(),
          if (emulator != null) 'emulator': emulator.toJson(),
          ..._sessionFileDetails(sessionFile),
          ..._vmServiceDetails(vmServiceUri),
          ..._bufferDetails(stdoutBuffer.text, stderrBuffer.text),
        },
      );
    }
    await writeSession(
      'passed',
      outputLog: outputLog,
      exitCode: secondState.exitCode,
    );
  } else {
    try {
      detachRequested = true;
      process.stdin.writeln('d');
      await process.stdin.flush();
    } on Object {
      // The process may have exited between the duration timer and detach signal.
    }
  }

  var exitCode = await _waitForExit(exitFuture);
  exitCode ??= await _terminateProcess(process, exitFuture);
  await _waitForCapturedOutput([stdoutDone, stderrDone]);
  final outputLog = await _writeRunLog(
    cacheEnvironment,
    platform,
    stdoutBuffer.text,
    stderrBuffer.text,
  );
  final processDetails = {
    if (detachRequested) 'detachedAfterDuration': true,
    if (exitCode == null)
      'terminatedAfterDuration': true
    else
      'processExitCode': exitCode,
  };
  await writeSession(
    'passed',
    outputLog: outputLog,
    exitCode: exitCode,
    detached: detachRequested,
  );
  return FlutterExampleRunResult(
    exitCode: 0,
    platform: platform,
    command: command,
    target: target,
    emulator: emulator,
    outputLog: outputLog,
    diagnostics: const [],
    details: {
      'target': target.toJson(),
      if (emulator != null) 'emulator': emulator.toJson(),
      if (outputLog != null) 'outputLog': outputLog.path,
      ..._sessionFileDetails(sessionFile),
      ..._vmServiceDetails(vmServiceUri),
      'launchDetected': true,
      'runDurationSeconds': runDuration.inSeconds,
      ...processDetails,
      ..._bufferDetails(stdoutBuffer.text, stderrBuffer.text),
    },
  );
}

Future<int?> _waitForExit(Future<int> exitFuture) async {
  return Future.any<int?>([
    exitFuture,
    Future<int?>.delayed(const Duration(seconds: 10), () => null),
  ]);
}

Future<int?> _terminateProcess(Process process, Future<int> exitFuture) async {
  process.kill();
  var exitCode = await _waitForExit(exitFuture);
  if (exitCode != null) {
    return exitCode;
  }
  process.kill(ProcessSignal.sigkill);
  exitCode = await Future.any<int?>([
    exitFuture,
    Future<int?>.delayed(const Duration(seconds: 3), () => null),
  ]);
  return exitCode;
}

Future<void> _waitForCapturedOutput(List<Future<void>> futures) async {
  await Future.wait(
    futures,
  ).timeout(const Duration(seconds: 3), onTimeout: () => const <void>[]);
}

String? _extractVmServiceUri(String line) {
  final match = RegExp(
    r'((?:http|https|ws|wss)://[^\s]+)',
    caseSensitive: false,
  ).firstMatch(line);
  if (match == null) {
    return null;
  }
  final uri = match.group(1)!.replaceAll(RegExp(r'[),.;]+$'), '');
  final lower = line.toLowerCase();
  if (lower.contains('vm service') ||
      lower.contains('observatory') ||
      lower.contains('debug service listening')) {
    return uri;
  }
  return null;
}

Map<String, Object?> _vmServiceDetails(String? uri) {
  return uri == null ? const {} : {'vmServiceUri': uri};
}

Map<String, Object?> _sessionFileDetails(File? file) {
  return file == null ? const {} : {'sessionFile': file.path};
}

Map<String, Object?> _exitCodeDetails(int? exitCode) {
  return exitCode == null ? const {} : {'exitCode': exitCode};
}

Future<void> _writeDebugSession({
  required File? sessionFile,
  required String status,
  required String platform,
  required String command,
  required int processId,
  required FlutterDeviceTarget target,
  required FlutterEmulatorTarget? emulator,
  required bool launchDetected,
  required String? vmServiceUri,
  required File? outputLog,
  required int? exitCode,
  required bool detached,
}) async {
  if (sessionFile == null) {
    return;
  }
  try {
    await sessionFile.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    final session = {
      'schema': 1,
      'kind': 'flutterRunSession',
      'status': status,
      'platform': platform,
      'command': command,
      'processId': processId,
      'targetId': target.id,
      'target': target.toJson(),
      if (emulator != null) 'emulator': emulator.toJson(),
      'launchDetected': launchDetected,
      ..._vmServiceDetails(vmServiceUri),
      if (outputLog != null) 'outputLog': outputLog.path,
      ..._exitCodeDetails(exitCode),
      if (detached) 'detached': true,
      'updatedAt': DateTime.now().toIso8601String(),
    };
    await sessionFile.writeAsString('${encoder.convert(session)}\n');
  } on Object {
    // Session files are best-effort debug hints and must not fail the run.
  }
}

bool _looksLaunched(String lower) {
  return lower.contains('flutter run key commands') ||
      lower.contains('debug service listening') ||
      lower.contains('syncing files to device') ||
      lower.contains('syncing files to ') ||
      lower.contains('application running') ||
      lower.contains('to hot reload changes while running');
}

bool _looksLikeRuntimeFailure(String lower) {
  return lower.contains('══╡ exception caught') ||
      lower.contains('unhandled exception') ||
      lower.contains('fatal exception') ||
      lower.contains('error launching application') ||
      lower.contains('lost connection to device') ||
      lower.contains('application finished') && lower.contains('non-zero') ||
      lower.contains('crash');
}

Future<void> _captureLines(
  Stream<List<int>> stream,
  OutputWriter write, {
  required void Function(String line) capture,
}) async {
  await for (final line
      in stream.transform(utf8.decoder).transform(const LineSplitter())) {
    capture(line);
    write(line);
  }
}

Future<File?> _writeRunLog(
  FluohEnvironment environment,
  String platform,
  String stdout,
  String stderr,
) async {
  try {
    final task = await TaskWorkspace(
      environment,
    ).resolveOrCreate(type: 'run', scopeName: platform);
    final runs = task.logDirectory;
    await runs.create(recursive: true);
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '')
        .replaceAll('.', '');
    final file = File('${runs.path}/flutter-run-$platform-$timestamp.log');
    await file.writeAsString(
      [
        if (stdout.trim().isNotEmpty) 'stdout:\n$stdout',
        if (stderr.trim().isNotEmpty) 'stderr:\n$stderr',
      ].join('\n\n'),
    );
    return file;
  } on Object {
    return null;
  }
}

FlutterExampleRunResult _failedRunResult({
  required String platform,
  required String command,
  required String code,
  required String message,
  required String reason,
  FlutterDeviceTarget? target,
  FlutterEmulatorTarget? emulator,
  File? outputLog,
  Map<String, Object?> details = const {},
}) {
  return FlutterExampleRunResult(
    exitCode: 1,
    platform: platform,
    command: command,
    target: target,
    emulator: emulator,
    outputLog: outputLog,
    reason: reason,
    details: {
      ...details,
      if (target != null) 'targetId': target.id,
      if (outputLog != null) 'outputLog': outputLog.path,
    },
    diagnostics: [
      FlutterExampleDiagnostic(
        code: code,
        message: message,
        details: {
          'command': command,
          ...details,
          if (target != null) 'targetId': target.id,
          if (outputLog != null) 'outputLog': outputLog.path,
        },
      ),
    ],
  );
}

Map<String, Object?> _commandDetails(SelectedToolResult result) {
  return {
    'exitCode': result.exitCode,
    ..._bufferDetails(result.stdout, result.stderr),
  };
}

Map<String, Object?> _bufferDetails(String stdout, String stderr) {
  return {
    if (stdout.trim().isNotEmpty) 'stdoutTail': stdout,
    if (stderr.trim().isNotEmpty) 'stderrTail': stderr,
    if ([
      stdout.trim(),
      stderr.trim(),
    ].where((item) => item.isNotEmpty).isNotEmpty)
      'outputTail': [
        if (stdout.trim().isNotEmpty) stdout.trim(),
        if (stderr.trim().isNotEmpty) stderr.trim(),
      ].join('\n'),
  };
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

class _RunLaunched {
  const _RunLaunched();
}

class _RunDurationElapsed {
  const _RunDurationElapsed();
}

class _RunLaunchTimeout {
  const _RunLaunchTimeout();
}

class _RunFailure {
  const _RunFailure(this.line);

  final String line;
}

class _RunExited {
  const _RunExited(this.exitCode);

  final int exitCode;
}
