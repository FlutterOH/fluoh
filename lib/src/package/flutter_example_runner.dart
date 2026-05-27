import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import '../cli/fluoh_command_runner.dart';
import '../cli/terminal_output.dart';
import '../context/fluoh_environment.dart';
import '../platform/platform_environment.dart';
import '../sdk/flutter_runner.dart';

class FlutterDeviceTarget {
  const FlutterDeviceTarget({
    required this.id,
    required this.name,
    required this.targetPlatform,
    required this.isSupported,
  });

  final String id;
  final String name;
  final String targetPlatform;
  final bool isSupported;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'targetPlatform': targetPlatform,
      'isSupported': isSupported,
    };
  }
}

class FlutterEmulatorTarget {
  const FlutterEmulatorTarget({
    required this.id,
    required this.name,
    required this.platformType,
  });

  final String id;
  final String name;
  final String platformType;

  Map<String, Object?> toJson() {
    return {'id': id, 'name': name, 'platformType': platformType};
  }
}

class FlutterExampleRunResult {
  const FlutterExampleRunResult({
    required this.exitCode,
    required this.platform,
    required this.command,
    required this.diagnostics,
    this.target,
    this.emulator,
    this.outputLog,
    this.reason,
    this.details = const {},
  });

  final int exitCode;
  final String platform;
  final String command;
  final FlutterDeviceTarget? target;
  final FlutterEmulatorTarget? emulator;
  final File? outputLog;
  final String? reason;
  final Map<String, Object?> details;
  final List<FlutterExampleDiagnostic> diagnostics;

  bool get passed => exitCode == 0;
}

class FlutterExampleDiagnostic {
  const FlutterExampleDiagnostic({
    required this.code,
    required this.message,
    this.severity = 'error',
    this.details = const {},
  });

  final String code;
  final String message;
  final String severity;
  final Map<String, Object?> details;
}

Future<FlutterExampleRunResult> runFlutterExampleOnDevice({
  required FluohEnvironment environment,
  required Directory exampleDirectory,
  required String buildExampleTarget,
  required TerminalOutput output,
  required OutputWriter stdout,
  required OutputWriter stderr,
  String? deviceId,
  bool startEmulator = false,
  String? emulatorName,
  Duration deviceTimeout = const Duration(seconds: 90),
  Duration runDuration = const Duration(seconds: 8),
  String usage = '',
}) async {
  final platform = _platformForBuildTarget(buildExampleTarget);
  final commandEnvironment = FluohEnvironment(
    homeDirectory: environment.homeDirectory,
    workingDirectory: exampleDirectory,
    processEnvironment: environment.processEnvironment,
  );
  final devicesResult = await _runFlutterTool(
    environment: commandEnvironment,
    workingDirectory: exampleDirectory,
    output: output,
    arguments: const ['devices', '--machine'],
    usage: usage,
  );
  if (devicesResult.exitCode != 0) {
    return _failedRunResult(
      platform: platform,
      command: 'flutter devices --machine',
      code: '$platform.devices_failed',
      message: 'Could not list Flutter devices.',
      reason: 'flutter devices --machine failed.',
      details: _commandDetails(devicesResult),
    );
  }

  late List<FlutterDeviceTarget> parsedDevices;
  try {
    parsedDevices = parseFlutterDevices(devicesResult.stdout);
  } on Object catch (error) {
    return _failedRunResult(
      platform: platform,
      command: 'flutter devices --machine',
      code: '$platform.devices_failed',
      message: 'Could not parse Flutter devices.',
      reason: error.toString(),
      details: _commandDetails(devicesResult),
    );
  }
  var devices = _devicesForPlatform(parsedDevices, platform);
  var target = emulatorName == null ? _selectDevice(devices, deviceId) : null;
  FlutterEmulatorTarget? emulator;

  if (target == null && startEmulator && deviceId == null) {
    final previousDeviceIds = devices.map((device) => device.id).toSet();
    final emulatorResult = await _startFlutterEmulator(
      environment: commandEnvironment,
      workingDirectory: exampleDirectory,
      output: output,
      platform: platform,
      emulatorName: emulatorName,
      usage: usage,
    );
    if (!emulatorResult.passed) {
      return emulatorResult;
    }
    emulator = emulatorResult.emulator;
    final waitResult = await _waitForFlutterDevice(
      environment: commandEnvironment,
      workingDirectory: exampleDirectory,
      output: output,
      platform: platform,
      deviceTimeout: deviceTimeout,
      usage: usage,
    );
    if (!waitResult.passed) {
      return FlutterExampleRunResult(
        exitCode: waitResult.exitCode,
        platform: platform,
        command: waitResult.command,
        emulator: emulator,
        diagnostics: waitResult.diagnostics,
        reason: waitResult.reason,
        details: waitResult.details,
      );
    }
    devices = _devicesForPlatform(
      parseFlutterDevices(waitResult.details['devicesJson'] as String? ?? '[]'),
      platform,
    );
    target = emulatorName == null
        ? _selectDevice(devices, null)
        : _selectStartedEmulatorDevice(
            devices: devices,
            emulator: emulator,
            previousDeviceIds: previousDeviceIds,
          );
  }

  if (target == null) {
    final details = <String, Object?>{
      'platform': platform,
      'devices': devices.map((device) => device.toJson()).toList(),
      if (deviceId != null && deviceId.trim().isNotEmpty)
        'requestedDevice': deviceId.trim(),
      if (emulatorName != null && emulatorName.trim().isNotEmpty)
        'requestedEmulator': emulatorName.trim(),
      if (emulator != null) 'startedEmulator': emulator.toJson(),
    };
    if (emulatorName != null && emulatorName.trim().isNotEmpty) {
      return _failedRunResult(
        platform: platform,
        command: 'flutter devices --machine',
        code: '$platform.device_missing',
        message: 'The requested emulator did not appear as a Flutter device.',
        reason:
            'Started $platform emulator ${emulatorName.trim()}, but no new matching Flutter device appeared.',
        emulator: emulator,
        details: details,
      );
    }
    if (deviceId != null && deviceId.trim().isNotEmpty) {
      return _failedRunResult(
        platform: platform,
        command: 'flutter devices --machine',
        code: '$platform.device_not_found',
        message: 'The requested Flutter device was not found.',
        reason: 'No $platform device matched ${deviceId.trim()}.',
        details: details,
      );
    }
    if (devices.isEmpty) {
      return _failedRunResult(
        platform: platform,
        command: 'flutter devices --machine',
        code: '$platform.device_missing',
        message: 'No Flutter device was available for the platform.',
        reason:
            'No $platform device was available. Connect a device or rerun with --start-emulator.',
        details: details,
      );
    }
    return _failedRunResult(
      platform: platform,
      command: 'flutter devices --machine',
      code: '$platform.device_ambiguous',
      message: 'Multiple Flutter devices matched the platform.',
      reason: 'Multiple $platform devices are connected; rerun with --device.',
      details: details,
    );
  }

  final runArguments = ['run', '-d', target.id, '--debug', '--no-pub'];
  final runCommand = 'flutter ${runArguments.join(' ')}';
  output.step('Running $runCommand in ${exampleDirectory.path}');
  final runResult = await _runFlutterSmoke(
    environment: commandEnvironment,
    workingDirectory: exampleDirectory,
    arguments: runArguments,
    platform: platform,
    target: target,
    emulator: emulator,
    stdout: stdout,
    stderr: stderr,
    output: output,
    runDuration: runDuration,
    launchTimeout: deviceTimeout,
    usage: usage,
  );
  return runResult;
}

List<FlutterDeviceTarget> parseFlutterDevices(String content) {
  if (content.trim().isEmpty) {
    return const [];
  }
  final decoded = jsonDecode(content);
  if (decoded is! List<Object?>) {
    throw const FormatException('Expected a Flutter device list.');
  }
  return [
    for (final item in decoded)
      if (item is Map<String, Object?>)
        FlutterDeviceTarget(
          id: (item['id'] ?? '').toString(),
          name: (item['name'] ?? '').toString(),
          targetPlatform: (item['targetPlatform'] ?? '').toString(),
          isSupported: item['isSupported'] != false,
        ),
  ].where((device) => device.id.trim().isNotEmpty).toList();
}

String _platformForBuildTarget(String target) {
  return switch (target) {
    'apk' => 'android',
    'ios' => 'ios',
    _ => throw ArgumentError.value(target, 'target', 'Unsupported target.'),
  };
}

List<FlutterDeviceTarget> _devicesForPlatform(
  List<FlutterDeviceTarget> devices,
  String platform,
) {
  return [
    for (final device in devices)
      if (device.isSupported &&
          _matchesPlatform(device.targetPlatform, platform))
        device,
  ];
}

bool _matchesPlatform(String value, String platform) {
  final normalized = value.toLowerCase();
  return normalized == platform || normalized.contains(platform);
}

FlutterDeviceTarget? _selectDevice(
  List<FlutterDeviceTarget> devices,
  String? deviceId,
) {
  final requested = deviceId?.trim();
  if (requested != null && requested.isNotEmpty) {
    for (final device in devices) {
      if (device.id == requested) {
        return device;
      }
    }
    return null;
  }
  return devices.length == 1 ? devices.single : null;
}

Future<FlutterExampleRunResult> _startFlutterEmulator({
  required FluohEnvironment environment,
  required Directory workingDirectory,
  required TerminalOutput output,
  required String platform,
  required String? emulatorName,
  required String usage,
}) async {
  final fluohPlatform = _fluohPlatformForRunPlatform(platform);
  final report = (await listPlatformEmulatorReports(
    environment: environment,
    platforms: [fluohPlatform],
  )).single;
  if (!report.ok) {
    return _failedRunResult(
      platform: platform,
      command: '$platform native emulator list',
      code: '$platform.emulators_failed',
      message: 'Could not list native emulators.',
      reason: report.message ?? 'Native emulator listing failed.',
      details: report.toJson(),
    );
  }
  final emulator = _selectNativeEmulator(report.targets, emulatorName);
  if (emulator == null) {
    final details = {
      'platform': platform,
      'emulators': report.targets.map((item) => item.toJson()).toList(),
      if (emulatorName != null && emulatorName.trim().isNotEmpty)
        'requestedEmulator': emulatorName.trim(),
    };
    if (emulatorName != null && emulatorName.trim().isNotEmpty) {
      return _failedRunResult(
        platform: platform,
        command: '$platform native emulator list',
        code: '$platform.emulator_not_found',
        message: 'The requested native emulator was not found.',
        reason: 'No $platform emulator matched ${emulatorName.trim()}.',
        details: details,
      );
    }
    if (report.targets.isEmpty) {
      return _failedRunResult(
        platform: platform,
        command: '$platform native emulator list',
        code: '$platform.emulator_missing',
        message: 'No native emulator was available for the platform.',
        reason: 'No $platform emulator was available.',
        details: details,
      );
    }
    return _failedRunResult(
      platform: platform,
      command: '$platform native emulator list',
      code: '$platform.emulator_ambiguous',
      message: 'Multiple native emulators matched the platform.',
      reason:
          'Multiple $platform emulators are available; rerun with --emulator.',
      details: details,
    );
  }

  output.step('Starting $platform emulator ${emulator.id}.');
  final startResult = await startPlatformEmulator(
    environment: environment,
    platform: fluohPlatform,
    emulator: emulator.id,
  );
  final command = startResult.command.isEmpty
      ? '$platform native emulator start'
      : startResult.command.join(' ');
  if (!startResult.ok) {
    return _failedRunResult(
      platform: platform,
      command: command,
      code: '$platform.emulator_start_failed',
      message: 'Could not start the native emulator.',
      reason: startResult.message,
      emulator: _flutterEmulatorFromNative(emulator),
      details: startResult.toJson(),
    );
  }
  return FlutterExampleRunResult(
    exitCode: 0,
    platform: platform,
    command: command,
    emulator: _flutterEmulatorFromNative(emulator),
    diagnostics: const [],
    details: {'emulator': emulator.toJson(), 'start': startResult.toJson()},
  );
}

FluohPlatform _fluohPlatformForRunPlatform(String platform) {
  return switch (platform) {
    'android' => FluohPlatform.android,
    'ios' => FluohPlatform.ios,
    _ => throw ArgumentError.value(platform, 'platform', 'Unsupported target.'),
  };
}

PlatformTarget? _selectNativeEmulator(
  List<PlatformTarget> emulators,
  String? emulatorName,
) {
  final requested = emulatorName?.trim();
  if (requested != null && requested.isNotEmpty) {
    for (final emulator in emulators) {
      if (emulator.id == requested || emulator.name == requested) {
        return emulator;
      }
    }
    return null;
  }
  return emulators.length == 1 ? emulators.single : null;
}

FlutterDeviceTarget? _selectStartedEmulatorDevice({
  required List<FlutterDeviceTarget> devices,
  required FlutterEmulatorTarget? emulator,
  required Set<String> previousDeviceIds,
}) {
  if (emulator != null) {
    for (final device in devices) {
      if (device.id == emulator.id || device.name == emulator.name) {
        return device;
      }
    }
  }
  final newDevices = [
    for (final device in devices)
      if (!previousDeviceIds.contains(device.id)) device,
  ];
  return newDevices.length == 1 ? newDevices.single : null;
}

FlutterEmulatorTarget _flutterEmulatorFromNative(PlatformTarget target) {
  return FlutterEmulatorTarget(
    id: target.id,
    name: target.name,
    platformType: target.platform.cliName,
  );
}

Future<FlutterExampleRunResult> _waitForFlutterDevice({
  required FluohEnvironment environment,
  required Directory workingDirectory,
  required TerminalOutput output,
  required String platform,
  required Duration deviceTimeout,
  required String usage,
}) async {
  final deadline = DateTime.now().add(deviceTimeout);
  SelectedToolResult? lastResult;
  while (!DateTime.now().isAfter(deadline)) {
    final result = await _runFlutterTool(
      environment: environment,
      workingDirectory: workingDirectory,
      output: output,
      arguments: const ['devices', '--machine'],
      usage: usage,
    );
    lastResult = result;
    if (result.exitCode != 0) {
      return _failedRunResult(
        platform: platform,
        command: 'flutter devices --machine',
        code: '$platform.devices_failed',
        message: 'Could not list Flutter devices.',
        reason: 'flutter devices --machine failed.',
        details: _commandDetails(result),
      );
    }
    late List<FlutterDeviceTarget> parsedDevices;
    try {
      parsedDevices = parseFlutterDevices(result.stdout);
    } on Object catch (error) {
      return _failedRunResult(
        platform: platform,
        command: 'flutter devices --machine',
        code: '$platform.devices_failed',
        message: 'Could not parse Flutter devices.',
        reason: error.toString(),
        details: _commandDetails(result),
      );
    }
    final devices = _devicesForPlatform(parsedDevices, platform);
    if (devices.isNotEmpty) {
      return FlutterExampleRunResult(
        exitCode: 0,
        platform: platform,
        command: 'flutter devices --machine',
        diagnostics: const [],
        details: {'devicesJson': result.stdout},
      );
    }
    await Future<void>.delayed(const Duration(seconds: 2));
  }
  return _failedRunResult(
    platform: platform,
    command: 'flutter devices --machine',
    code: '$platform.device_missing',
    message: 'No Flutter device appeared before the timeout.',
    reason: 'No $platform device appeared within ${deviceTimeout.inSeconds}s.',
    details: {
      'timeoutSeconds': deviceTimeout.inSeconds,
      if (lastResult != null) ..._commandDetails(lastResult),
    },
  );
}

Future<SelectedToolResult> _runFlutterTool({
  required FluohEnvironment environment,
  required Directory workingDirectory,
  required TerminalOutput output,
  required List<String> arguments,
  required String usage,
}) {
  output.step(
    'Running flutter ${arguments.join(' ')} in ${workingDirectory.path}',
  );
  return runSelectedFlutterResult(
    environment: environment,
    arguments: arguments,
    workingDirectory: workingDirectory,
    stdout: (_) {},
    stderr: (_) {},
    output: output,
    usage: usage,
  );
}

Future<FlutterExampleRunResult> _runFlutterSmoke({
  required FluohEnvironment environment,
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
    environment: environment.processEnvironment,
  );
  final stdoutBuffer = _LineBuffer();
  final stderrBuffer = _LineBuffer();
  final launchCompleter = Completer<void>();
  final failureCompleter = Completer<String>();

  void inspect(String line) {
    final lower = line.toLowerCase();
    if (!launchCompleter.isCompleted && _looksLaunched(lower)) {
      launchCompleter.complete();
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
  final command = 'flutter ${arguments.join(' ')}';
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
      environment.homeDirectory,
      platform,
      stdoutBuffer.text,
      stderrBuffer.text,
    );
    return _failedRunResult(
      platform: platform,
      command: command,
      target: target,
      emulator: emulator,
      outputLog: outputLog,
      code: '$platform.launch_timeout',
      message: 'Flutter example launch did not complete before the timeout.',
      reason:
          'No Flutter launch signal was detected within ${launchTimeout.inSeconds}s.',
      details: {
        'exitCodeAfterKill': exitCode,
        'target': target.toJson(),
        if (emulator != null) 'emulator': emulator.toJson(),
        ..._bufferDetails(stdoutBuffer.text, stderrBuffer.text),
      },
    );
  }

  if (firstState is _RunFailure) {
    final exitCode = await _terminateProcess(process, exitFuture);
    await _waitForCapturedOutput([stdoutDone, stderrDone]);
    final outputLog = await _writeRunLog(
      environment.homeDirectory,
      platform,
      stdoutBuffer.text,
      stderrBuffer.text,
    );
    return _failedRunResult(
      platform: platform,
      command: command,
      target: target,
      emulator: emulator,
      outputLog: outputLog,
      code: '$platform.runtime_crash',
      message: 'Flutter example output indicates a runtime failure.',
      reason: firstState.line,
      details: {
        'exitCodeAfterKill': exitCode,
        'target': target.toJson(),
        if (emulator != null) 'emulator': emulator.toJson(),
        ..._bufferDetails(stdoutBuffer.text, stderrBuffer.text),
      },
    );
  }

  if (firstState is _RunExited) {
    await _waitForCapturedOutput([stdoutDone, stderrDone]);
    final outputLog = await _writeRunLog(
      environment.homeDirectory,
      platform,
      stdoutBuffer.text,
      stderrBuffer.text,
    );
    if (firstState.exitCode != 0) {
      return _failedRunResult(
        platform: platform,
        command: command,
        target: target,
        emulator: emulator,
        outputLog: outputLog,
        code: '$platform.run_failed',
        message: 'Flutter example run failed.',
        reason: 'flutter run exited with code ${firstState.exitCode}.',
        details: {
          'exitCode': firstState.exitCode,
          'target': target.toJson(),
          if (emulator != null) 'emulator': emulator.toJson(),
          ..._bufferDetails(stdoutBuffer.text, stderrBuffer.text),
        },
      );
    }
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
        'processExited': true,
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
      environment.homeDirectory,
      platform,
      stdoutBuffer.text,
      stderrBuffer.text,
    );
    return _failedRunResult(
      platform: platform,
      command: command,
      target: target,
      emulator: emulator,
      outputLog: outputLog,
      code: '$platform.runtime_crash',
      message: 'Flutter example output indicates a runtime failure.',
      reason: secondState.line,
      details: {
        'exitCodeAfterKill': exitCode,
        'target': target.toJson(),
        if (emulator != null) 'emulator': emulator.toJson(),
        ..._bufferDetails(stdoutBuffer.text, stderrBuffer.text),
      },
    );
  }

  if (secondState is _RunExited) {
    await _waitForCapturedOutput([stdoutDone, stderrDone]);
    final outputLog = await _writeRunLog(
      environment.homeDirectory,
      platform,
      stdoutBuffer.text,
      stderrBuffer.text,
    );
    if (secondState.exitCode != 0) {
      return _failedRunResult(
        platform: platform,
        command: command,
        target: target,
        emulator: emulator,
        outputLog: outputLog,
        code: '$platform.run_failed',
        message: 'Flutter example run failed.',
        reason: 'flutter run exited with code ${secondState.exitCode}.',
        details: {
          'exitCode': secondState.exitCode,
          'target': target.toJson(),
          if (emulator != null) 'emulator': emulator.toJson(),
          ..._bufferDetails(stdoutBuffer.text, stderrBuffer.text),
        },
      );
    }
  } else {
    try {
      process.stdin.writeln('q');
      await process.stdin.flush();
    } on Object {
      // The process may have exited between the duration timer and quit signal.
    }
  }

  var exitCode = await _waitForExit(exitFuture);
  exitCode ??= await _terminateProcess(process, exitFuture);
  await _waitForCapturedOutput([stdoutDone, stderrDone]);
  final outputLog = await _writeRunLog(
    environment.homeDirectory,
    platform,
    stdoutBuffer.text,
    stderrBuffer.text,
  );
  final processDetails = exitCode == null
      ? const {'terminatedAfterDuration': true}
      : {'processExitCode': exitCode};
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
  Directory homeDirectory,
  String platform,
  String stdout,
  String stderr,
) async {
  try {
    final runs = Directory('${homeDirectory.path}/package-runs');
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
    details: {...details, if (outputLog != null) 'outputLog': outputLog.path},
    diagnostics: [
      FlutterExampleDiagnostic(
        code: code,
        message: message,
        details: {
          'command': command,
          ...details,
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
