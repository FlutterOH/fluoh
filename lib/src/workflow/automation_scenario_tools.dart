part of 'automation_scenario.dart';

Future<File?> _androidAdb(Map<String, String> environment) async {
  final configured = environment['FLUOH_ANDROID_ADB']?.trim();
  if (configured != null && configured.isNotEmpty) {
    final file = File(configured);
    return await file.exists() ? file : null;
  }
  final sdkRoot = _androidSdkRootPath(environment);
  if (sdkRoot != null && sdkRoot.isNotEmpty) {
    final file = File('$sdkRoot/platform-tools/adb');
    if (await file.exists()) {
      return file;
    }
  }
  final result = await Process.run('which', const ['adb']);
  if (result.exitCode == 0) {
    final path = result.stdout.toString().trim();
    if (path.isNotEmpty) {
      return File(path);
    }
  }
  return null;
}

String? _androidSdkRootPath(Map<String, String> environment) {
  for (final key in const ['ANDROID_SDK_ROOT', 'ANDROID_HOME']) {
    final value = environment[key]?.trim();
    if (value != null && value.isNotEmpty) {
      return value;
    }
  }
  final home = environment['HOME']?.trim();
  if (home != null && home.isNotEmpty) {
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
  final result = await Process.run('which', const ['xcrun']);
  if (result.exitCode == 0) {
    final path = result.stdout.toString().trim();
    if (path.isNotEmpty) {
      return File(path);
    }
  }
  return null;
}

Future<File?> _openSimulatorTool(Map<String, String> environment) async {
  final configured = environment['FLUOH_OPEN']?.trim();
  if (configured != null && configured.isNotEmpty) {
    final file = File(configured);
    return await file.exists() ? file : null;
  }
  final configuredXcrun = environment['FLUOH_XCRUN']?.trim();
  if (configuredXcrun != null && configuredXcrun.isNotEmpty) {
    return null;
  }
  if (!Platform.isMacOS) {
    return null;
  }
  final systemOpen = File('/usr/bin/open');
  if (await systemOpen.exists()) {
    return systemOpen;
  }
  final result = await Process.run('which', const ['open']);
  if (result.exitCode == 0) {
    final path = result.stdout.toString().trim();
    if (path.isNotEmpty) {
      return File(path);
    }
  }
  return null;
}

Future<_IosXcodebuildTool?> _iosXcodebuild(
  Map<String, String> environment,
) async {
  final configured = environment['FLUOH_XCODEBUILD']?.trim();
  if (configured != null && configured.isNotEmpty) {
    final file = File(configured);
    return await file.exists()
        ? _IosXcodebuildTool(executable: file, prefixArguments: const [])
        : null;
  }
  final xcrun = await _xcrun(environment);
  if (xcrun != null) {
    return _IosXcodebuildTool(
      executable: xcrun,
      prefixArguments: const ['xcodebuild'],
    );
  }
  final result = await Process.run('which', const ['xcodebuild']);
  if (result.exitCode == 0) {
    final path = result.stdout.toString().trim();
    if (path.isNotEmpty) {
      return _IosXcodebuildTool(
        executable: File(path),
        prefixArguments: const [],
      );
    }
  }
  return null;
}

class _IosXcodebuildTool {
  const _IosXcodebuildTool({
    required this.executable,
    required this.prefixArguments,
  });

  final File executable;
  final List<String> prefixArguments;
}

Future<_ToolRun> _runTool(
  String executable,
  List<String> arguments, {
  required Map<String, String> environment,
  required Directory workingDirectory,
  Duration timeout = const Duration(seconds: 30),
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
  var timedOut = false;
  final exitCode = await process.exitCode.timeout(
    timeout,
    onTimeout: () async {
      timedOut = true;
      process.kill();
      try {
        return await process.exitCode.timeout(const Duration(seconds: 5));
      } on TimeoutException {
        if (!Platform.isWindows) {
          process.kill(ProcessSignal.sigkill);
        }
        return 124;
      }
    },
  );
  try {
    await Future.wait([
      stdoutDone,
      stderrDone,
    ]).timeout(const Duration(seconds: 2));
  } on TimeoutException {
    // The process has been signalled; return the timeout diagnostic instead of
    // blocking the automation loop on unclosed pipes.
  }
  return _ToolRun(
    command: '$executable ${arguments.join(' ')}',
    exitCode: timedOut ? 124 : exitCode,
    stdout: stdoutBuffer.toString(),
    stderr: timedOut && stderrBuffer.toString().trim().isEmpty
        ? 'Command timed out.'
        : stderrBuffer.toString(),
  );
}

Future<void> _collectToolOutput(
  Stream<List<int>> stream,
  StringBuffer buffer,
) async {
  await for (final chunk in stream.transform(utf8.decoder)) {
    buffer.write(chunk);
  }
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
