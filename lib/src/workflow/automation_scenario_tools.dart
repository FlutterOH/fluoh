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
      await _terminateToolProcess(process);
      try {
        return await process.exitCode.timeout(const Duration(seconds: 5));
      } on TimeoutException {
        if (!Platform.isWindows) {
          await _terminateToolProcess(process, ProcessSignal.sigkill);
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
    stderr: timedOut
        ? _toolTimeoutStderr(stderrBuffer.toString())
        : stderrBuffer.toString(),
  );
}

Future<_ToolRun> _runToolToFile(
  String executable,
  List<String> arguments, {
  required Map<String, String> environment,
  required Directory workingDirectory,
  required File outputFile,
  Duration timeout = const Duration(seconds: 30),
}) async {
  await outputFile.parent.create(recursive: true);
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory.path,
    environment: environment,
  );
  final stderrBuffer = StringBuffer();
  final outputSink = outputFile.openWrite();
  final stdoutDone = process.stdout.pipe(outputSink);
  final stderrDone = _collectToolOutput(process.stderr, stderrBuffer);
  var timedOut = false;
  final exitCode = await process.exitCode.timeout(
    timeout,
    onTimeout: () async {
      timedOut = true;
      await _terminateToolProcess(process);
      try {
        return await process.exitCode.timeout(const Duration(seconds: 5));
      } on TimeoutException {
        if (!Platform.isWindows) {
          await _terminateToolProcess(process, ProcessSignal.sigkill);
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
    // The process has been signalled; return a timeout diagnostic instead of
    // blocking the automation loop on unclosed pipes.
  }
  return _ToolRun(
    command: '$executable ${arguments.join(' ')}',
    exitCode: timedOut ? 124 : exitCode,
    stdout: '',
    stderr: timedOut
        ? _toolTimeoutStderr(stderrBuffer.toString())
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

String _toolTimeoutStderr(String stderr) {
  if (stderr.trim().isEmpty) {
    return 'Command timed out.';
  }
  if (stderr.contains('Command timed out.')) {
    return stderr;
  }
  final separator = stderr.endsWith('\n') ? '' : '\n';
  return '$stderr${separator}Command timed out.';
}

Future<void> _terminateToolProcess(
  Process process, [
  ProcessSignal signal = ProcessSignal.sigterm,
]) async {
  process.kill(signal);
  if (Platform.isWindows) {
    return;
  }

  for (final pid in await _toolProcessDescendantPids(process.pid)) {
    Process.killPid(pid, signal);
  }
}

Future<List<int>> _toolProcessDescendantPids(int rootPid) async {
  try {
    final result = await Process.run('ps', const ['-axo', 'pid=,ppid=']);
    if (result.exitCode != 0) {
      return const [];
    }
    final childrenByParent = <int, List<int>>{};
    for (final line in result.stdout.toString().split('\n')) {
      final fields = line.trim().split(RegExp(r'\s+'));
      if (fields.length != 2) {
        continue;
      }
      final pid = int.tryParse(fields[0]);
      final parentPid = int.tryParse(fields[1]);
      if (pid == null || parentPid == null || pid <= 0) {
        continue;
      }
      childrenByParent.putIfAbsent(parentPid, () => <int>[]).add(pid);
    }

    final descendants = <int>[];
    final queue = <int>[rootPid];
    while (queue.isNotEmpty) {
      final parentPid = queue.removeAt(0);
      final children = childrenByParent[parentPid] ?? const <int>[];
      descendants.addAll(children);
      queue.addAll(children);
    }
    return descendants.reversed.toList(growable: false);
  } on Object {
    return const [];
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
