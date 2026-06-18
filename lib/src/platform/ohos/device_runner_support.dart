part of 'device_runner.dart';

/// Returns fatal runtime findings from an OHOS hilog capture.
List<String> classifyOhosRuntimeLog(String log) {
  final findings = <String>[];
  final seen = <String>{};
  final fatalPattern = RegExp(
    r'(FATAL EXCEPTION|Fatal signal|SIGSEGV|SIGABRT|Process crashed|'
    r'app ?crash|CppCrash|MissingPluginException|No implementation found '
    r'for method|MethodChannel#\s*-->\s*method not implemented)',
    caseSensitive: false,
  );
  String? previousLine;
  for (final rawLine in const LineSplitter().convert(log)) {
    final line = rawLine.trim();
    if (line.isEmpty) {
      continue;
    }
    if (_isBenignOhosMethodNotImplemented(line, previousLine)) {
      previousLine = line;
      continue;
    }
    if (!fatalPattern.hasMatch(line)) {
      previousLine = line;
      continue;
    }
    final finding = line.length <= 500 ? line : line.substring(0, 500);
    if (seen.add(finding)) {
      findings.add(finding);
    }
    if (findings.length >= 20) {
      break;
    }
    previousLine = line;
  }
  return findings;
}

bool _isBenignOhosMethodNotImplemented(String line, String? previousLine) {
  return line.contains('MethodChannel# --> method not implemented') &&
      (previousLine?.contains(
            "PlatformMethodCallback --> Received 'System.initializationComplete' message.",
          ) ??
          false);
}

/// Exception thrown for OHOS device and emulator failures.
class OhosDeviceException implements Exception {
  /// Creates an OHOS device exception.
  const OhosDeviceException(this.message, {this.code, this.details = const {}});

  /// User-facing failure message.
  final String message;

  /// Stable diagnostic code when the failure has a known machine meaning.
  final String? code;

  /// Additional machine-readable diagnostic details.
  final Map<String, Object?> details;

  @override
  String toString() => message;
}

Future<List<io.File>> _moduleJsonFiles(io.Directory ohosDirectory) async {
  final mainFiles = <io.File>[];
  final fallbackFiles = <io.File>[];
  await for (final entity in ohosDirectory.list(recursive: true)) {
    if (entity is! io.File || !entity.path.endsWith('/module.json5')) {
      continue;
    }
    final normalized = entity.path.replaceAll('\\', '/');
    if (normalized.contains('/ohosTest/')) {
      continue;
    }
    if (normalized.endsWith('/src/main/module.json5')) {
      mainFiles.add(entity);
    } else {
      fallbackFiles.add(entity);
    }
  }
  mainFiles.sort((left, right) => left.path.compareTo(right.path));
  fallbackFiles.sort((left, right) => left.path.compareTo(right.path));
  return [...mainFiles, ...fallbackFiles];
}

String? _firstStringValue(String content, String key) {
  return RegExp(
    '"${RegExp.escape(key)}"\\s*:\\s*"([^"]+)"',
  ).firstMatch(content)?.group(1);
}

String? _firstAbilityName(String content) {
  final key = RegExp(r'"abilities"\s*:').firstMatch(content);
  if (key == null) {
    return null;
  }
  final start = content.indexOf('[', key.end);
  if (start < 0) {
    return null;
  }
  final end = _matchingBracket(content, start, '[', ']');
  if (end < 0) {
    return null;
  }
  return _firstStringValue(content.substring(start, end + 1), 'name');
}

int _matchingBracket(String text, int start, String open, String close) {
  var depth = 0;
  var inString = false;
  var escaped = false;
  for (var index = start; index < text.length; index += 1) {
    final char = text[index];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (char == '\\') {
        escaped = true;
      } else if (char == '"') {
        inString = false;
      }
      continue;
    }
    if (char == '"') {
      inString = true;
    } else if (char == open) {
      depth += 1;
    } else if (char == close) {
      depth -= 1;
      if (depth == 0) {
        return index;
      }
    }
  }
  return -1;
}

OhosDeviceTarget? _selectTarget(
  List<OhosDeviceTarget> targets,
  String? requestedId,
) {
  if (requestedId != null && requestedId.trim().isNotEmpty) {
    for (final target in targets) {
      if (target.id == requestedId) {
        return target;
      }
    }
    return null;
  }
  return targets.length == 1 ? targets.single : null;
}

List<String> _targeted(String targetId, List<String> arguments) {
  return ['-t', targetId, ...arguments];
}

Future<OhosHdcResult> _runHdc(
  OhosToolchain toolchain,
  List<String> arguments, {
  required Duration timeout,
}) async {
  io.Process? process;
  final stdoutBuffer = StringBuffer();
  final stderrBuffer = StringBuffer();
  final drains = <Future<void>>[];
  try {
    process = await io.Process.start(toolchain.hdc.path, arguments);
    drains
      ..add(
        process.stdout
            .transform(const Utf8Decoder(allowMalformed: true))
            .listen(stdoutBuffer.write)
            .asFuture<void>(),
      )
      ..add(
        process.stderr
            .transform(const Utf8Decoder(allowMalformed: true))
            .listen(stderrBuffer.write)
            .asFuture<void>(),
      );
    final exitCode = await process.exitCode.timeout(timeout);
    await _drainHdcStreams(drains);
    return OhosHdcResult(
      exitCode: exitCode,
      stdout: stdoutBuffer.toString(),
      stderr: stderrBuffer.toString(),
    );
  } on TimeoutException {
    process?.kill();
    try {
      await process?.exitCode.timeout(const Duration(seconds: 1));
    } on Object {
      process?.kill(io.ProcessSignal.sigkill);
    }
    await _drainHdcStreams(drains);
    final stderr = stderrBuffer.toString();
    return OhosHdcResult(
      exitCode: 124,
      stdout: stdoutBuffer.toString(),
      stderr:
          '${stderr.trimRight()}${stderr.trim().isEmpty ? '' : '\n'}'
          'Timed out after ${timeout.inSeconds}s running hdc ${arguments.join(' ')}',
    );
  }
}

Duration _ohosHdcCommandTimeout(Map<String, String> environment) {
  final raw = environment['FLUOH_OHOS_HDC_TIMEOUT_SECONDS']?.trim();
  if (raw == null || raw.isEmpty) {
    return const Duration(seconds: 10);
  }
  final seconds = int.tryParse(raw);
  if (seconds == null || seconds <= 0) {
    return const Duration(seconds: 10);
  }
  return Duration(seconds: seconds);
}

Future<void> _drainHdcStreams(List<Future<void>> drains) async {
  try {
    await Future.wait(drains).timeout(const Duration(seconds: 1));
  } on Object {
    // hdc output is diagnostic only after exit or timeout.
  }
}

Future<void> _runHdcBestEffort(
  OhosToolchain toolchain,
  List<String> arguments, {
  required Duration timeout,
  String? workingDirectory,
}) async {
  io.Process? process;
  final drains = <Future<void>>[];
  try {
    process = await io.Process.start(
      toolchain.hdc.path,
      arguments,
      workingDirectory: workingDirectory,
    );
    drains
      ..add(process.stdout.drain<void>())
      ..add(process.stderr.drain<void>());
    await process.exitCode.timeout(timeout);
  } on TimeoutException {
    process?.kill();
  } on Object {
    process?.kill();
  } finally {
    try {
      await Future.wait(drains).timeout(const Duration(seconds: 1));
    } on Object {
      process?.kill();
    }
  }
}

bool _isHdcCommandFailure(OhosHdcResult result) {
  return result.exitCode != 0 ||
      _isHdcConnectionFailure(result) ||
      _isHdcTargetUnavailable(result);
}

int _effectiveHdcExitCode(OhosHdcResult result) {
  return result.exitCode == 0 && _isHdcCommandFailure(result)
      ? 1
      : result.exitCode;
}

bool _isHdcConnectionFailure(OhosHdcResult result) {
  return _containsHdcOutputFragment(result, const [
    'connect server failed',
    'failed to connect hdc server',
    'failed to connect to hdc server',
    'connect hdc server failed',
  ]);
}

bool _isHdcTargetUnavailable(OhosHdcResult result) {
  return _containsHdcOutputFragment(result, const [
    'not match target founded',
    'not match target found',
    'target offline',
    'device offline',
  ]);
}

bool _containsHdcOutputFragment(OhosHdcResult result, List<String> fragments) {
  final output = '${result.stdout}\n${result.stderr}'.toLowerCase();
  return fragments.any(output.contains);
}

bool _isHdcTimeout(OhosHdcResult result) {
  return result.exitCode == 124 &&
      _containsHdcOutputFragment(result, const ['timed out after']);
}

OhosDeviceDiagnostic _hdcFailureDiagnostic({
  required String defaultCode,
  required String defaultMessage,
  required String command,
  required String targetId,
  required OhosHdcResult result,
  Map<String, Object?> details = const {},
}) {
  final code = _isHdcConnectionFailure(result)
      ? 'ohos.hdc_connection_failed'
      : _isHdcTimeout(result)
      ? 'ohos.hdc_timeout'
      : _isHdcTargetUnavailable(result)
      ? 'ohos.hdc_target_unavailable'
      : defaultCode;
  final message = switch (code) {
    'ohos.hdc_connection_failed' => 'OHOS hdc connection failed',
    'ohos.hdc_timeout' => 'OHOS hdc command timed out',
    'ohos.hdc_target_unavailable' => 'OHOS hdc target became unavailable',
    _ => defaultMessage,
  };
  return OhosDeviceDiagnostic(
    code: code,
    message: message,
    details: {
      ...details,
      ..._hdcFailureDetails(
        command: command,
        result: result,
        targetId: targetId,
      ),
    },
  );
}

Map<String, Object?> _hdcFailureDetails({
  required String command,
  required OhosHdcResult result,
  String? targetId,
}) {
  final effectiveExitCode = _effectiveHdcExitCode(result);
  return {
    'command': command,
    'targetId': ?targetId,
    'exitCode': effectiveExitCode,
    if (effectiveExitCode != result.exitCode) 'rawExitCode': result.exitCode,
    if (result.stdout.trim().isNotEmpty) 'stdout': result.stdout,
    if (result.stderr.trim().isNotEmpty) 'stderr': result.stderr,
  };
}

Future<void> _stopLogProcess(io.Process? process, Future<int>? exitCode) async {
  if (process == null || exitCode == null) {
    return;
  }
  process.kill(io.ProcessSignal.sigint);
  try {
    await exitCode.timeout(const Duration(seconds: 2));
  } on TimeoutException {
    process.kill(io.ProcessSignal.sigkill);
    await exitCode.timeout(const Duration(seconds: 2), onTimeout: () => -1);
  }
}

Future<void> _drainLogStreams(List<Future<void>> streams) async {
  try {
    await Future.wait<void>(
      streams,
    ).timeout(const Duration(seconds: 2), onTimeout: () => const []);
  } on Object {
    // Hilog capture is diagnostic only; keep the device run result authoritative.
  }
}

Future<io.File> _writeHilog({
  required FluohEnvironment environment,
  required OhosLaunchInfo launchInfo,
  required String content,
}) async {
  final task = await TaskWorkspace(
    environment,
  ).resolveOrCreate(type: 'run', scopeName: launchInfo.bundleName);
  final directory = io.Directory(
    '${task.logDirectory.path}/${_safePathSegment(launchInfo.bundleName)}',
  );
  await directory.create(recursive: true);
  final timestamp = DateTime.now()
      .toUtc()
      .toIso8601String()
      .replaceAll(RegExp(r'[^0-9A-Za-z]+'), '-')
      .replaceAll(RegExp(r'-+$'), '');
  final file = io.File('${directory.path}/$timestamp.hilog');
  await file.writeAsString(content);
  return file;
}

String _safePathSegment(String value) {
  final safe = value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9._-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return safe.isEmpty ? 'app' : safe;
}

String _fileName(String path) {
  return path.replaceAll('\\', '/').split('/').last;
}

String _userHome(Map<String, String> environment) {
  final home = environment['HOME'] ?? environment['USERPROFILE'];
  if (home != null && home.trim().isNotEmpty) {
    return home.trim();
  }
  return io.Platform.environment['HOME'] ??
      io.Platform.environment['USERPROFILE'] ??
      '.';
}

String _trimOutput(String value) {
  final text = value.trim();
  if (text.isEmpty) {
    return '';
  }
  const limit = 3000;
  final trimmed = text.length <= limit
      ? text
      : text.substring(text.length - limit);
  return '$trimmed\n';
}
