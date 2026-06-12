import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import '../cli/fluoh_command_runner.dart';
import '../cli/terminal_output.dart';
import '../context/fluoh_environment.dart';
import '../platform/platform_environment.dart';
import '../sdk/flutter_runner.dart';
import '../workflow/platform_workflow_policy.dart';

part 'flutter_example_targets.dart';
part 'flutter_example_run_session.dart';

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
  final targetPolicy = _runTargetPolicyFor(platform);
  var devices = _devicesForPlatform(parsedDevices, targetPolicy);
  var target = deviceId != null
      ? _selectDevice(devices, deviceId, policy: targetPolicy)
      : startEmulator && emulatorName == null
      ? _isDesktopRunPlatform(platform)
            ? _selectDevice(devices, null, policy: targetPolicy)
            : _selectRunningEmulatorDevice(devices)
      : startEmulator
      ? null
      : _selectDevice(devices, null, policy: targetPolicy);
  if (target == null &&
      platform == 'ios' &&
      deviceId != null &&
      deviceId.trim().isNotEmpty) {
    target = await _selectIosDeviceAlias(
      environment: commandEnvironment,
      devices: devices,
      deviceId: deviceId,
    );
  }
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
        target = _selectDevice(devices, null, policy: targetPolicy);
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
        allowExistingEmulatorFallback: emulatorName != null,
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
        targetPolicy,
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
        reason: targetPolicy.missingDeviceReason(),
        details: details,
      );
    }
    return _failedRunResult(
      platform: platform,
      command: 'flutter devices --machine',
      code: '$platform.device_ambiguous',
      message: 'Multiple Flutter devices matched the platform',
      reason:
          'Multiple $platform devices are connected; rerun with --device-id',
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
