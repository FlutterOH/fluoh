import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../context/fluoh_environment.dart';
import '../platform/ohos/ohos_toolchain.dart';
import '../sdk/sdk_project_environment.dart';

const _postLaunchScreenshotDirectory = '.fluoh/evidence/screenshots';

/// Result from best-effort mobile post-launch evidence collection.
class MobileRunEvidenceResult {
  /// Creates a mobile run evidence result.
  const MobileRunEvidenceResult({
    required this.kind,
    required this.status,
    required this.platform,
    required this.targetId,
    this.path,
    this.bytes,
    this.method,
    this.command,
    this.remotePath,
    this.reason,
    this.details = const {},
  });

  /// Evidence kind, such as `postLaunchScreenshot`.
  final String kind;

  /// Evidence status: `passed`, `failed`, or `skipped`.
  final String status;

  /// Target platform.
  final String platform;

  /// Device or simulator id used for collection.
  final String targetId;

  /// Local evidence file path, when one was selected.
  final String? path;

  /// Local evidence file size, when a non-empty file was produced.
  final int? bytes;

  /// Platform capture method.
  final String? method;

  /// Tool command used for the capture or transfer.
  final String? command;

  /// Remote temporary evidence path, when the platform uses one.
  final String? remotePath;

  /// Human-readable reason for skipped or failed evidence.
  final String? reason;

  /// Additional machine-readable details.
  final Map<String, Object?> details;

  /// Whether this result produced usable evidence.
  bool get passed => status == 'passed';

  /// Converts this evidence result to JSON.
  Map<String, Object?> toJson() {
    return {
      'schema': 1,
      'kind': kind,
      'status': status,
      'platform': platform,
      'targetId': targetId,
      if (path != null) 'path': path,
      if (bytes != null) 'bytes': bytes,
      if (method != null) 'method': method,
      if (command != null) 'command': command,
      if (remotePath != null) 'remotePath': remotePath,
      if (reason != null) 'reason': reason,
      ...details,
    };
  }
}

/// Captures a best-effort post-launch screenshot for a mobile run.
Future<MobileRunEvidenceResult> captureMobilePostLaunchScreenshot({
  required FluohEnvironment environment,
  required String platform,
  required String targetId,
  required String scopeName,
  Duration timeout = const Duration(seconds: 20),
}) async {
  final normalizedPlatform = platform.trim().toLowerCase();
  return switch (normalizedPlatform) {
    'ohos' => _captureOhosPostLaunchScreenshot(
      environment: environment,
      platform: normalizedPlatform,
      targetId: targetId,
      scopeName: scopeName,
      timeout: timeout,
    ),
    'android' => _captureAndroidPostLaunchScreenshot(
      environment: environment,
      platform: normalizedPlatform,
      targetId: targetId,
      scopeName: scopeName,
      timeout: timeout,
    ),
    'ios' => _captureIosPostLaunchScreenshot(
      environment: environment,
      platform: normalizedPlatform,
      targetId: targetId,
      scopeName: scopeName,
      timeout: timeout,
    ),
    _ => MobileRunEvidenceResult(
      kind: 'postLaunchScreenshot',
      status: 'skipped',
      platform: normalizedPlatform,
      targetId: targetId,
      reason: 'post-launch screenshot is supported only for mobile platforms',
    ),
  };
}

Future<MobileRunEvidenceResult> _captureOhosPostLaunchScreenshot({
  required FluohEnvironment environment,
  required String platform,
  required String targetId,
  required String scopeName,
  required Duration timeout,
}) async {
  final file = await _postLaunchScreenshotFile(
    environment,
    scopeName: scopeName,
    platform: platform,
    extension: 'jpeg',
  );
  final remotePath =
      '/data/local/tmp/fluoh-${_artifactSlug(scopeName)}-$platform-post-launch.jpeg';
  late final OhosToolchain toolchain;
  try {
    toolchain = await locateOhosToolchain(
      environment: environment.processEnvironment,
    );
  } on Object catch (error) {
    return _skipped(
      platform: platform,
      targetId: targetId,
      path: file.path,
      reason: 'OHOS hdc toolchain was not available',
      details: {'error': error.toString()},
    );
  }
  final capture = await _runTool(
    toolchain.hdc.path,
    ['-t', targetId, 'shell', 'snapshot_display', '-f', remotePath],
    environment: environment.processEnvironment,
    workingDirectory: environment.workingDirectory,
    timeout: timeout,
  );
  if (capture.exitCode != 0) {
    return _failed(
      platform: platform,
      targetId: targetId,
      path: file.path,
      command: capture.command,
      method: 'hdc shell snapshot_display',
      remotePath: remotePath,
      reason: 'Could not capture OHOS post-launch screenshot',
      details: capture.toDetails(),
    );
  }
  final recv = await _runTool(
    toolchain.hdc.path,
    ['-t', targetId, 'file', 'recv', remotePath, file.path],
    environment: environment.processEnvironment,
    workingDirectory: environment.workingDirectory,
    timeout: timeout,
  );
  if (recv.exitCode != 0) {
    return _failed(
      platform: platform,
      targetId: targetId,
      path: file.path,
      command: recv.command,
      method: 'hdc file recv',
      remotePath: remotePath,
      reason: 'Could not receive OHOS post-launch screenshot',
      details: {'capture': capture.toDetails(), ...recv.toDetails()},
    );
  }
  return _fileResult(
    file,
    platform: platform,
    targetId: targetId,
    command: recv.command,
    method: 'hdc shell snapshot_display',
    remotePath: remotePath,
    details: {'capture': capture.toDetails()},
  );
}

Future<MobileRunEvidenceResult> _captureAndroidPostLaunchScreenshot({
  required FluohEnvironment environment,
  required String platform,
  required String targetId,
  required String scopeName,
  required Duration timeout,
}) async {
  final file = await _postLaunchScreenshotFile(
    environment,
    scopeName: scopeName,
    platform: platform,
    extension: 'png',
  );
  final adb = await _androidAdb(environment.processEnvironment);
  if (adb == null) {
    return _skipped(
      platform: platform,
      targetId: targetId,
      path: file.path,
      reason: 'adb was not found in the Android SDK or PATH',
    );
  }
  final result = await _runToolToFile(
    adb.path,
    ['-s', targetId, 'exec-out', 'screencap', '-p'],
    environment: environment.processEnvironment,
    workingDirectory: environment.workingDirectory,
    outputFile: file,
    timeout: timeout,
  );
  if (result.exitCode != 0) {
    return _failed(
      platform: platform,
      targetId: targetId,
      path: file.path,
      command: result.command,
      method: 'adb exec-out screencap -p',
      reason: 'Could not capture Android post-launch screenshot',
      details: result.toDetails(),
    );
  }
  return _fileResult(
    file,
    platform: platform,
    targetId: targetId,
    command: result.command,
    method: 'adb exec-out screencap -p',
  );
}

Future<MobileRunEvidenceResult> _captureIosPostLaunchScreenshot({
  required FluohEnvironment environment,
  required String platform,
  required String targetId,
  required String scopeName,
  required Duration timeout,
}) async {
  final file = await _postLaunchScreenshotFile(
    environment,
    scopeName: scopeName,
    platform: platform,
    extension: 'png',
  );
  final xcrun = await _xcrun(environment.processEnvironment);
  if (xcrun == null) {
    return _skipped(
      platform: platform,
      targetId: targetId,
      path: file.path,
      reason: 'xcrun was not found for iOS screenshot capture',
    );
  }
  final result = await _runTool(
    xcrun.path,
    ['simctl', 'io', targetId, 'screenshot', file.path],
    environment: environment.processEnvironment,
    workingDirectory: environment.workingDirectory,
    timeout: timeout,
  );
  if (result.exitCode != 0) {
    return _failed(
      platform: platform,
      targetId: targetId,
      path: file.path,
      command: result.command,
      method: 'xcrun simctl io screenshot',
      reason: 'Could not capture iOS post-launch screenshot',
      details: result.toDetails(),
    );
  }
  return _fileResult(
    file,
    platform: platform,
    targetId: targetId,
    command: result.command,
    method: 'xcrun simctl io screenshot',
  );
}

Future<File> _postLaunchScreenshotFile(
  FluohEnvironment environment, {
  required String scopeName,
  required String platform,
  required String extension,
}) async {
  await ensureFluohLocalStateIgnored(environment.workingDirectory);
  final directory = Directory(
    '${environment.workingDirectory.path}${Platform.pathSeparator}'
    '${_postLaunchScreenshotDirectory.replaceAll('/', Platform.pathSeparator)}',
  );
  await directory.create(recursive: true);
  return File(
    '${directory.path}${Platform.pathSeparator}'
    '${_artifactSlug(scopeName)}-$platform-post-launch.$extension',
  );
}

Future<MobileRunEvidenceResult> _fileResult(
  File file, {
  required String platform,
  required String targetId,
  required String command,
  required String method,
  String? remotePath,
  Map<String, Object?> details = const {},
}) async {
  final exists = await file.exists();
  final bytes = exists ? await file.length() : 0;
  if (!exists || bytes <= 0) {
    return _failed(
      platform: platform,
      targetId: targetId,
      path: file.path,
      command: command,
      method: method,
      remotePath: remotePath,
      reason: exists
          ? 'Post-launch screenshot file is empty'
          : 'Post-launch screenshot file was not created',
      details: {'bytes': bytes, ...details},
    );
  }
  return MobileRunEvidenceResult(
    kind: 'postLaunchScreenshot',
    status: 'passed',
    platform: platform,
    targetId: targetId,
    path: file.path,
    bytes: bytes,
    command: command,
    method: method,
    remotePath: remotePath,
    details: details,
  );
}

MobileRunEvidenceResult _skipped({
  required String platform,
  required String targetId,
  required String path,
  required String reason,
  Map<String, Object?> details = const {},
}) {
  return MobileRunEvidenceResult(
    kind: 'postLaunchScreenshot',
    status: 'skipped',
    platform: platform,
    targetId: targetId,
    path: path,
    reason: reason,
    details: details,
  );
}

MobileRunEvidenceResult _failed({
  required String platform,
  required String targetId,
  required String path,
  required String command,
  required String method,
  required String reason,
  String? remotePath,
  Map<String, Object?> details = const {},
}) {
  return MobileRunEvidenceResult(
    kind: 'postLaunchScreenshot',
    status: 'failed',
    platform: platform,
    targetId: targetId,
    path: path,
    command: command,
    method: method,
    remotePath: remotePath,
    reason: reason,
    details: details,
  );
}

Future<File?> _androidAdb(Map<String, String> environment) async {
  final configured = environment['FLUOH_ANDROID_ADB']?.trim();
  if (configured != null && configured.isNotEmpty) {
    final file = File(configured);
    return await file.exists() ? file : null;
  }
  final sdkRoot = _androidSdkRootPath(environment);
  if (sdkRoot != null && sdkRoot.isNotEmpty) {
    final name = Platform.isWindows ? 'adb.exe' : 'adb';
    final file = File('$sdkRoot/platform-tools/$name');
    if (await file.exists()) {
      return file;
    }
  }
  return _findExecutableOnPath('adb', environment);
}

String? _androidSdkRootPath(Map<String, String> environment) {
  for (final key in const ['ANDROID_SDK_ROOT', 'ANDROID_HOME']) {
    final value = environment[key]?.trim();
    if (value != null && value.isNotEmpty) {
      return value;
    }
  }
  final home = environment['HOME']?.trim();
  if (home != null && home.isNotEmpty && Platform.isMacOS) {
    return '$home/Library/Android/sdk';
  }
  return null;
}

Future<File?> _xcrun(Map<String, String> environment) async {
  final configured = environment['FLUOH_XCRUN']?.trim();
  if (configured != null && configured.isNotEmpty) {
    final file = File(configured);
    return await file.exists() ? file : null;
  }
  if (Platform.isMacOS) {
    final systemXcrun = File('/usr/bin/xcrun');
    if (await systemXcrun.exists()) {
      return systemXcrun;
    }
  }
  return _findExecutableOnPath('xcrun', environment);
}

Future<File?> _findExecutableOnPath(
  String executable,
  Map<String, String> environment,
) async {
  final path = environment['PATH'] ?? Platform.environment['PATH'];
  if (path == null || path.trim().isEmpty) {
    return null;
  }
  final separator = Platform.isWindows ? ';' : ':';
  final candidates = Platform.isWindows
      ? [executable, '$executable.exe', '$executable.bat', '$executable.cmd']
      : [executable];
  for (final directory in path.split(separator)) {
    if (directory.trim().isEmpty) {
      continue;
    }
    for (final candidate in candidates) {
      final file = File(
        '${directory.trim()}${Platform.pathSeparator}$candidate',
      );
      if (await file.exists()) {
        return file;
      }
    }
  }
  return null;
}

Future<_ToolRun> _runTool(
  String executable,
  List<String> arguments, {
  required Map<String, String> environment,
  required Directory workingDirectory,
  required Duration timeout,
}) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory.path,
    environment: environment,
  );
  final stdoutBuffer = StringBuffer();
  final stderrBuffer = StringBuffer();
  final stdoutDone = _collectToolOutput(process.stdout, stdoutBuffer);
  final stderrDone = _collectToolOutput(process.stderr, stderrBuffer);
  final exitCode = await _waitForTool(process, timeout);
  await _waitForOutput([stdoutDone, stderrDone]);
  return _ToolRun(
    command: '$executable ${arguments.join(' ')}',
    exitCode: exitCode.exitCode,
    stdout: stdoutBuffer.toString(),
    stderr: exitCode.timedOut
        ? _timeoutStderr(stderrBuffer.toString())
        : stderrBuffer.toString(),
  );
}

Future<_ToolRun> _runToolToFile(
  String executable,
  List<String> arguments, {
  required Map<String, String> environment,
  required Directory workingDirectory,
  required File outputFile,
  required Duration timeout,
}) async {
  await outputFile.parent.create(recursive: true);
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory.path,
    environment: environment,
  );
  final stderrBuffer = StringBuffer();
  final stdoutDone = process.stdout.pipe(outputFile.openWrite());
  final stderrDone = _collectToolOutput(process.stderr, stderrBuffer);
  final exitCode = await _waitForTool(process, timeout);
  await _waitForOutput([stdoutDone, stderrDone]);
  return _ToolRun(
    command: '$executable ${arguments.join(' ')}',
    exitCode: exitCode.exitCode,
    stdout: '',
    stderr: exitCode.timedOut
        ? _timeoutStderr(stderrBuffer.toString())
        : stderrBuffer.toString(),
  );
}

Future<_ToolExit> _waitForTool(Process process, Duration timeout) async {
  var timedOut = false;
  final exitCode = await process.exitCode.timeout(
    timeout,
    onTimeout: () async {
      timedOut = true;
      process.kill();
      try {
        return await process.exitCode.timeout(const Duration(seconds: 3));
      } on TimeoutException {
        if (!Platform.isWindows) {
          process.kill(ProcessSignal.sigkill);
        }
        return 124;
      }
    },
  );
  return _ToolExit(exitCode: timedOut ? 124 : exitCode, timedOut: timedOut);
}

Future<void> _waitForOutput(List<Future<void>> futures) async {
  try {
    await Future.wait(futures).timeout(const Duration(seconds: 2));
  } on TimeoutException {
    // The tool was already stopped; keep evidence collection best-effort.
  }
}

Future<void> _collectToolOutput(
  Stream<List<int>> stream,
  StringBuffer buffer,
) async {
  await for (final chunk in stream.transform(utf8.decoder)) {
    buffer.write(chunk);
  }
}

String _timeoutStderr(String stderr) {
  if (stderr.trim().isEmpty) {
    return 'Command timed out.';
  }
  if (stderr.contains('Command timed out.')) {
    return stderr;
  }
  final separator = stderr.endsWith('\n') ? '' : '\n';
  return '$stderr${separator}Command timed out.';
}

String _artifactSlug(String value) {
  final normalized = value
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
      .replaceAll(RegExp(r'^[-._]+|[-._]+$'), '');
  return normalized.isEmpty ? 'run' : normalized;
}

String _tail(String text) {
  final lines = const LineSplitter().convert(text.trimRight());
  if (lines.length <= 20) {
    return lines.join('\n');
  }
  return lines.sublist(lines.length - 20).join('\n');
}

class _ToolExit {
  const _ToolExit({required this.exitCode, required this.timedOut});

  final int exitCode;
  final bool timedOut;
}

class _ToolRun {
  const _ToolRun({
    required this.command,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final String command;
  final int exitCode;
  final String stdout;
  final String stderr;

  Map<String, Object?> toDetails() {
    return {
      'exitCode': exitCode,
      if (stdout.trim().isNotEmpty) 'stdoutTail': _tail(stdout),
      if (stderr.trim().isNotEmpty) 'stderrTail': _tail(stderr),
    };
  }
}
