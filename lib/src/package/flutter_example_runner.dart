import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import '../cli/fluoh_command_runner.dart';
import '../cli/terminal_output.dart';
import '../context/fluoh_environment.dart';
import '../platform/platform_environment.dart';
import '../sdk/flutter_runner.dart';

/// Flutter device entry parsed from `flutter devices --machine`.
class FlutterDeviceTarget {
  /// Creates a Flutter device target.
  const FlutterDeviceTarget({
    required this.id,
    required this.name,
    required this.targetPlatform,
    required this.isSupported,
    this.isEmulator = false,
  });

  /// Flutter device id.
  final String id;

  /// User-facing device name.
  final String name;

  /// Flutter target platform string.
  final String targetPlatform;

  /// Whether Flutter reports the device as supported.
  final bool isSupported;

  /// Whether Flutter reports this target as an emulator or simulator.
  final bool isEmulator;

  /// Converts the device target to JSON.
  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'targetPlatform': targetPlatform,
      'isSupported': isSupported,
      if (isEmulator) 'isEmulator': true,
    };
  }
}

/// Flutter emulator entry parsed from `flutter emulators --machine`.
class FlutterEmulatorTarget {
  /// Creates a Flutter emulator target.
  const FlutterEmulatorTarget({
    required this.id,
    required this.name,
    required this.platformType,
  });

  /// Flutter emulator id.
  final String id;

  /// User-facing emulator name.
  final String name;

  /// Flutter platform type.
  final String platformType;

  /// Converts the emulator target to JSON.
  Map<String, Object?> toJson() {
    return {'id': id, 'name': name, 'platformType': platformType};
  }
}

/// Result of a Flutter example run or integration-test flow.
class FlutterExampleRunResult {
  /// Creates a Flutter example run result.
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

  /// Exit code for the run flow.
  final int exitCode;

  /// Platform requested by the run flow.
  final String platform;

  /// Command line used for the run flow.
  final String command;

  /// Selected Flutter device target.
  final FlutterDeviceTarget? target;

  /// Emulator that was launched before the run, if any.
  final FlutterEmulatorTarget? emulator;

  /// Captured output log file.
  final File? outputLog;

  /// Optional high-level failure reason.
  final String? reason;

  /// Additional machine-readable result details.
  final Map<String, Object?> details;

  /// Structured diagnostics from device selection or runtime output.
  final List<FlutterExampleDiagnostic> diagnostics;

  /// Whether the run flow passed.
  bool get passed => exitCode == 0;
}

/// Structured diagnostic for Flutter example runs.
class FlutterExampleDiagnostic {
  /// Creates a Flutter example diagnostic.
  const FlutterExampleDiagnostic({
    required this.code,
    required this.message,
    this.severity = 'error',
    this.details = const {},
  });

  /// Stable diagnostic code.
  final String code;

  /// Human-readable diagnostic message.
  final String message;

  /// Diagnostic severity.
  final String severity;

  /// Additional machine-readable diagnostic details.
  final Map<String, Object?> details;
}

/// Runs a Flutter example on a selected device or emulator.
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
  File? sessionFile,
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
      message: 'Could not list Flutter devices',
      reason: 'flutter devices --machine failed',
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
      message: 'Could not parse Flutter devices',
      reason: error.toString(),
      details: _commandDetails(devicesResult),
    );
  }
  var devices = _devicesForPlatform(parsedDevices, platform);
  var target = deviceId != null
      ? _selectDevice(devices, deviceId, platform: platform)
      : startEmulator && emulatorName == null
      ? _isDesktopRunPlatform(platform)
            ? _selectDevice(devices, null, platform: platform)
            : _selectRunningEmulatorDevice(devices)
      : startEmulator
      ? null
      : _selectDevice(devices, null, platform: platform);
  FlutterEmulatorTarget? emulator;
  FlutterExampleRunResult? autoEmulatorFailure;

  if (target == null &&
      startEmulator &&
      deviceId == null &&
      (!_isDesktopRunPlatform(platform) || emulatorName != null)) {
    final previousDeviceIds = devices.map((device) => device.id).toSet();
    final emulatorResult = await _startFlutterEmulator(
      environment: commandEnvironment,
      workingDirectory: exampleDirectory,
      output: output,
      platform: platform,
      emulatorName: emulatorName,
      preferDefault: emulatorName == null,
      usage: usage,
    );
    if (!emulatorResult.passed) {
      if (_shouldFallbackToConnectedDevice(
            emulatorResult,
            emulatorName: emulatorName,
          ) &&
          devices.isNotEmpty) {
        autoEmulatorFailure = emulatorResult;
        target = _selectDevice(devices, null, platform: platform);
      } else {
        return emulatorResult;
      }
    } else {
      emulator = emulatorResult.emulator;
      final waitResult = await _waitForFlutterDevice(
        environment: commandEnvironment,
        workingDirectory: exampleDirectory,
        output: output,
        platform: platform,
        previousDeviceIds: previousDeviceIds,
        waitForNewDevice: true,
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
        parseFlutterDevices(
          waitResult.details['devicesJson'] as String? ?? '[]',
        ),
        platform,
      );
      target = _selectStartedEmulatorDevice(
        devices: devices,
        emulator: emulator,
        previousDeviceIds: previousDeviceIds,
      );
    }
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
      if (autoEmulatorFailure != null)
        'autoEmulatorFallback': _autoEmulatorFallbackDetails(
          autoEmulatorFailure,
        ),
    };
    if (emulatorName != null && emulatorName.trim().isNotEmpty) {
      return _failedRunResult(
        platform: platform,
        command: 'flutter devices --machine',
        code: '$platform.device_missing',
        message: 'The requested emulator did not appear as a Flutter device',
        reason:
            'Started $platform emulator ${emulatorName.trim()}, but no new matching Flutter device appeared',
        emulator: emulator,
        details: details,
      );
    }
    if (deviceId != null && deviceId.trim().isNotEmpty) {
      return _failedRunResult(
        platform: platform,
        command: 'flutter devices --machine',
        code: '$platform.device_not_found',
        message: 'The requested Flutter device was not found',
        reason: 'No $platform device matched ${deviceId.trim()}',
        details: details,
      );
    }
    if (devices.isEmpty) {
      return _failedRunResult(
        platform: platform,
        command: 'flutter devices --machine',
        code: '$platform.device_missing',
        message: 'No Flutter device was available for the platform',
        reason: _missingFlutterDeviceReason(platform),
        details: details,
      );
    }
    return _failedRunResult(
      platform: platform,
      command: 'flutter devices --machine',
      code: '$platform.device_ambiguous',
      message: 'Multiple Flutter devices matched the platform',
      reason: 'Multiple $platform devices are connected; rerun with --device',
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
    sessionFile: sessionFile,
    usage: usage,
  );
  if (autoEmulatorFailure == null) {
    return runResult;
  }
  return FlutterExampleRunResult(
    exitCode: runResult.exitCode,
    platform: runResult.platform,
    command: runResult.command,
    target: runResult.target,
    emulator: runResult.emulator,
    outputLog: runResult.outputLog,
    reason: runResult.reason,
    details: {
      ...runResult.details,
      'autoEmulatorFallback': _autoEmulatorFallbackDetails(autoEmulatorFailure),
    },
    diagnostics: runResult.diagnostics,
  );
}

/// Parses `flutter devices --machine` JSON output.
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
          isEmulator: item['emulator'] == true,
        ),
  ].where((device) => device.id.trim().isNotEmpty).toList();
}

String _platformForBuildTarget(String target) {
  return switch (target) {
    'apk' => 'android',
    'ios' => 'ios',
    'macos' => 'macos',
    'linux' => 'linux',
    'web' => 'web',
    'windows' => 'windows',
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
  if (platform == 'macos') {
    return normalized == 'macos' ||
        normalized.startsWith('darwin-') ||
        normalized.contains('macos');
  }
  if (platform == 'web') {
    return normalized == 'web' || normalized.contains('web');
  }
  return normalized == platform || normalized.contains(platform);
}

FlutterDeviceTarget? _selectDevice(
  List<FlutterDeviceTarget> devices,
  String? deviceId, {
  required String platform,
}) {
  final requested = deviceId?.trim();
  if (requested != null && requested.isNotEmpty) {
    for (final device in devices) {
      if (device.id == requested) {
        return device;
      }
    }
    return null;
  }
  if (platform == 'web') {
    for (final device in devices) {
      if (device.id == 'web-server') {
        return device;
      }
    }
  }
  return devices.length == 1 ? devices.single : null;
}

FlutterDeviceTarget? _selectRunningEmulatorDevice(
  List<FlutterDeviceTarget> devices,
) {
  final candidates = [
    for (final device in devices)
      if (_isRunningEmulatorDevice(device)) device,
  ]..sort(_compareFlutterEmulatorPreference);
  return candidates.isEmpty ? null : candidates.first;
}

bool _isRunningEmulatorDevice(FlutterDeviceTarget device) {
  if (device.isEmulator) {
    return true;
  }
  final id = device.id.toLowerCase();
  final name = device.name.toLowerCase();
  return id.startsWith('emulator-') ||
      id.contains('simulator') ||
      name.contains('emulator') ||
      name.contains('simulator');
}

bool _isDesktopRunPlatform(String platform) {
  return platform == 'macos' ||
      platform == 'linux' ||
      platform == 'web' ||
      platform == 'windows';
}

String _missingFlutterDeviceReason(String platform) {
  if (platform == 'web') {
    return 'No web target was available. Ensure flutter devices lists Chrome, '
        'web-server, or another supported Flutter web device.';
  }
  if (_isDesktopRunPlatform(platform)) {
    return 'No $platform host target was available. Run on a matching host and '
        'ensure flutter devices lists the desktop target.';
  }
  return 'No $platform device was available. Rerun with --auto-emulator so '
      'fluoh can start a local emulator or simulator, or pass --device <id> '
      'for a connected target.';
}

Future<FlutterExampleRunResult> _startFlutterEmulator({
  required FluohEnvironment environment,
  required Directory workingDirectory,
  required TerminalOutput output,
  required String platform,
  required String? emulatorName,
  required bool preferDefault,
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
      message: 'Could not list native emulators',
      reason: report.message ?? 'Native emulator listing failed',
      details: report.toJson(),
    );
  }
  final emulator = _selectNativeEmulator(
    report.targets,
    emulatorName,
    preferDefault: preferDefault,
  );
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
        message: 'The requested native emulator was not found',
        reason: 'No $platform emulator matched ${emulatorName.trim()}',
        details: details,
      );
    }
    if (report.targets.isEmpty) {
      return _failedRunResult(
        platform: platform,
        command: '$platform native emulator list',
        code: '$platform.emulator_missing',
        message: 'No native emulator was available for the platform',
        reason: 'No $platform emulator was available',
        details: details,
      );
    }
    return _failedRunResult(
      platform: platform,
      command: '$platform native emulator list',
      code: '$platform.emulator_ambiguous',
      message: 'Multiple native emulators matched the platform',
      reason:
          'Multiple $platform emulators are available; rerun with --emulator',
      details: details,
    );
  }

  output.step('Starting $platform emulator ${emulator.id}');
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
      message: 'Could not start the native emulator',
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
    'linux' => FluohPlatform.linux,
    'macos' => FluohPlatform.macos,
    'web' => FluohPlatform.web,
    'windows' => FluohPlatform.windows,
    _ => throw ArgumentError.value(platform, 'platform', 'Unsupported target.'),
  };
}

PlatformTarget? _selectNativeEmulator(
  List<PlatformTarget> emulators,
  String? emulatorName, {
  required bool preferDefault,
}) {
  final requested = emulatorName?.trim();
  if (requested != null && requested.isNotEmpty) {
    for (final emulator in emulators) {
      if (emulator.id == requested || emulator.name == requested) {
        return emulator;
      }
    }
    return null;
  }
  if (preferDefault && emulators.isNotEmpty) {
    final sorted = [...emulators]..sort(_compareNativeEmulatorPreference);
    return sorted.first;
  }
  return emulators.length == 1 ? emulators.single : null;
}

int _compareFlutterEmulatorPreference(
  FlutterDeviceTarget left,
  FlutterDeviceTarget right,
) {
  final platformCompare = _runTargetPreferenceScore(
    left.targetPlatform,
    left.name,
  ).compareTo(_runTargetPreferenceScore(right.targetPlatform, right.name));
  if (platformCompare != 0) {
    return platformCompare;
  }
  final nameCompare = left.name.compareTo(right.name);
  return nameCompare != 0 ? nameCompare : left.id.compareTo(right.id);
}

int _compareNativeEmulatorPreference(
  PlatformTarget left,
  PlatformTarget right,
) {
  final platformCompare = _nativeTargetPreferenceScore(
    left,
  ).compareTo(_nativeTargetPreferenceScore(right));
  if (platformCompare != 0) {
    return platformCompare;
  }
  final nameCompare = left.name.compareTo(right.name);
  return nameCompare != 0 ? nameCompare : left.id.compareTo(right.id);
}

int _runTargetPreferenceScore(String targetPlatform, String name) {
  if (!targetPlatform.toLowerCase().contains('ios')) {
    return 0;
  }
  return _iosSimulatorDeviceClassScore(name);
}

int _nativeTargetPreferenceScore(PlatformTarget target) {
  if (target.platform != FluohPlatform.ios) {
    return 0;
  }
  final deviceClassScore = _iosSimulatorDeviceClassScore(target.name);
  final runtimeScore = _iosRuntimeVersionScore(target.details['runtime']);
  return deviceClassScore * 1000000 - runtimeScore;
}

int _iosSimulatorDeviceClassScore(String name) {
  final lower = name.toLowerCase();
  if (lower.contains('iphone')) {
    return 0;
  }
  if (lower.contains('ipad')) {
    return 1;
  }
  return 2;
}

int _iosRuntimeVersionScore(Object? runtime) {
  final match = RegExp(
    r'iOS-(\d+)(?:-(\d+))?(?:-(\d+))?',
    caseSensitive: false,
  ).firstMatch(runtime?.toString() ?? '');
  if (match == null) {
    return 0;
  }
  final major = int.tryParse(match.group(1) ?? '') ?? 0;
  final minor = int.tryParse(match.group(2) ?? '') ?? 0;
  final patch = int.tryParse(match.group(3) ?? '') ?? 0;
  return major * 10000 + minor * 100 + patch;
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
  Set<String> previousDeviceIds = const {},
  bool waitForNewDevice = false,
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
        message: 'Could not list Flutter devices',
        reason: 'flutter devices --machine failed',
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
        message: 'Could not parse Flutter devices',
        reason: error.toString(),
        details: _commandDetails(result),
      );
    }
    final devices = _devicesForPlatform(parsedDevices, platform);
    final readyDevices = waitForNewDevice
        ? [
            for (final device in devices)
              if (!previousDeviceIds.contains(device.id)) device,
          ]
        : devices;
    if (readyDevices.isNotEmpty) {
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
    message: 'No Flutter device appeared before the timeout',
    reason: 'No $platform device appeared within ${deviceTimeout.inSeconds}s',
    details: {
      'timeoutSeconds': deviceTimeout.inSeconds,
      if (lastResult != null) ..._commandDetails(lastResult),
    },
  );
}

bool _shouldFallbackToConnectedDevice(
  FlutterExampleRunResult result, {
  required String? emulatorName,
}) {
  final requested = emulatorName?.trim();
  if (requested != null && requested.isNotEmpty) {
    return false;
  }
  return result.diagnostics.any(
    (diagnostic) =>
        diagnostic.code.endsWith('.emulator_missing') ||
        diagnostic.code.endsWith('.emulators_failed'),
  );
}

Map<String, Object?> _autoEmulatorFallbackDetails(
  FlutterExampleRunResult failure,
) {
  return {
    'reason': failure.reason,
    'diagnostics': failure.diagnostics
        .map(
          (diagnostic) => {
            'code': diagnostic.code,
            'message': diagnostic.message,
            'severity': diagnostic.severity,
            if (diagnostic.details.isNotEmpty) 'details': diagnostic.details,
          },
        )
        .toList(),
  };
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

  Future<void> writeSession(String status, {File? outputLog, int? exitCode}) {
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
      environment,
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
      environment,
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
      environment,
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

  final secondState = await Future.any<Object>([
    failureCompleter.future.then((line) => _RunFailure(line)),
    exitFuture.then((exitCode) => _RunExited(exitCode)),
    Future<void>.delayed(runDuration).then((_) => const _RunDurationElapsed()),
  ]);

  if (secondState is _RunFailure) {
    final exitCode = await _terminateProcess(process, exitFuture);
    await _waitForCapturedOutput([stdoutDone, stderrDone]);
    final outputLog = await _writeRunLog(
      environment,
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

  if (secondState is _RunExited) {
    await _waitForCapturedOutput([stdoutDone, stderrDone]);
    final outputLog = await _writeRunLog(
      environment,
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
    environment,
    platform,
    stdoutBuffer.text,
    stderrBuffer.text,
  );
  final processDetails = exitCode == null
      ? const {'terminatedAfterDuration': true}
      : {'processExitCode': exitCode};
  await writeSession('passed', outputLog: outputLog, exitCode: exitCode);
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
      'target': target.toJson(),
      if (emulator != null) 'emulator': emulator.toJson(),
      'launchDetected': launchDetected,
      ..._vmServiceDetails(vmServiceUri),
      if (outputLog != null) 'outputLog': outputLog.path,
      ..._exitCodeDetails(exitCode),
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
    final runs = environment.packageRunsDirectory;
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
