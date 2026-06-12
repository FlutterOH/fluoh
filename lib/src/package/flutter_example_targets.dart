part of 'flutter_example_runner.dart';

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
    'hap' => 'ohos',
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
  _RunTargetPolicy policy,
) {
  return [
    for (final device in devices)
      if (policy.matchesDevice(device)) device,
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

_RunTargetPolicy _runTargetPolicyFor(String platform) {
  return platform == 'web'
      ? const _WebRunTargetPolicy()
      : _DefaultRunTargetPolicy(platform);
}

abstract class _RunTargetPolicy {
  const _RunTargetPolicy(this.platform);

  final String platform;

  bool matchesDevice(FlutterDeviceTarget device) {
    return device.isSupported &&
        _matchesPlatform(device.targetPlatform, platform);
  }

  FlutterDeviceTarget? selectDefaultDevice(List<FlutterDeviceTarget> devices) {
    return devices.length == 1 ? devices.single : null;
  }

  String missingDeviceReason() {
    if (_isDesktopRunPlatform(platform)) {
      return 'No $platform host target was available. Run on a matching host and '
          'ensure flutter devices lists the desktop target.';
    }
    return 'No $platform device was available. Rerun with --auto-emulator so '
        'fluoh can start a local emulator or simulator, or pass --device-id <id> '
        'for a connected target.';
  }
}

class _DefaultRunTargetPolicy extends _RunTargetPolicy {
  const _DefaultRunTargetPolicy(super.platform);
}

class _WebRunTargetPolicy extends _RunTargetPolicy {
  const _WebRunTargetPolicy() : super('web');

  @override
  bool matchesDevice(FlutterDeviceTarget device) {
    return super.matchesDevice(device) && device.id != 'web-server';
  }

  @override
  FlutterDeviceTarget? selectDefaultDevice(List<FlutterDeviceTarget> devices) {
    for (final device in devices) {
      if (device.id == 'chrome') {
        return device;
      }
    }
    return super.selectDefaultDevice(devices);
  }

  @override
  String missingDeviceReason() {
    return 'No browser target was available. Ensure flutter devices lists '
        'Chrome or another supported browser device.';
  }
}

FlutterDeviceTarget? _selectDevice(
  List<FlutterDeviceTarget> devices,
  String? deviceId, {
  required _RunTargetPolicy policy,
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
  return policy.selectDefaultDevice(devices);
}

Future<FlutterDeviceTarget?> _selectIosDeviceAlias({
  required FluohEnvironment environment,
  required List<FlutterDeviceTarget> devices,
  required String deviceId,
}) async {
  final requested = deviceId.trim();
  if (requested.isEmpty) {
    return null;
  }
  final reports = await listPlatformDeviceReports(
    environment: environment,
    platforms: const [FluohPlatform.ios],
  ).catchError((_) => const <PlatformTargetReport>[]);
  final nativeTargets = [
    for (final report in reports)
      if (report.ok)
        for (final target in report.targets)
          if (target.kind == 'device') target,
  ];
  final requestedTargets = [
    for (final target in nativeTargets)
      if (_iosNativeTargetMatches(target, requested)) target,
  ];
  if (requestedTargets.isEmpty) {
    return null;
  }

  final candidates = <String, FlutterDeviceTarget>{};
  for (final nativeTarget in requestedTargets) {
    final aliases = _iosNativeTargetAliases(nativeTarget);
    for (final device in devices) {
      if (aliases.contains(device.id)) {
        candidates[device.id] = device;
      }
    }
    final nameMatches = [
      for (final device in devices)
        if (_normalizedDeviceName(device.name) ==
            _normalizedDeviceName(nativeTarget.name))
          device,
    ];
    if (nameMatches.length == 1) {
      candidates[nameMatches.single.id] = nameMatches.single;
    }
  }
  return candidates.length == 1 ? candidates.values.single : null;
}

bool _iosNativeTargetMatches(PlatformTarget target, String requested) {
  return _iosNativeTargetAliases(target).contains(requested) ||
      _normalizedDeviceName(target.name) == _normalizedDeviceName(requested);
}

Set<String> _iosNativeTargetAliases(PlatformTarget target) {
  final values = <String>{target.id};
  for (final key in const ['identifier', 'devicectlIdentifier', 'udid']) {
    final value = target.details[key]?.toString().trim();
    if (value != null && value.isNotEmpty) {
      values.add(value);
    }
  }
  final aliases = target.details['aliases'];
  if (aliases is Iterable) {
    for (final alias in aliases) {
      final value = alias?.toString().trim();
      if (value != null && value.isNotEmpty) {
        values.add(value);
      }
    }
  }
  return values;
}

String _normalizedDeviceName(String value) {
  return value.trim().toLowerCase();
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
      id.startsWith('127.0.0.1:') ||
      id.startsWith('localhost:') ||
      id.contains('simulator') ||
      name.contains('emulator') ||
      name.contains('simulator');
}

bool _isDesktopRunPlatform(String platform) {
  return platformWorkflowPolicy(platform).isDesktopRunPlatform;
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
    'ohos' => FluohPlatform.ohos,
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
  if (newDevices.length == 1) {
    return newDevices.single;
  }
  final runningEmulators = [
    for (final device in devices)
      if (_isRunningEmulatorDevice(device)) device,
  ];
  return runningEmulators.length == 1 ? runningEmulators.single : null;
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
  bool allowExistingEmulatorFallback = false,
  required Duration deviceTimeout,
  required String usage,
}) async {
  final deadline = DateTime.now().add(deviceTimeout);
  late SelectedToolResult lastResult;
  while (true) {
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
    final devices = _devicesForPlatform(
      parsedDevices,
      _runTargetPolicyFor(platform),
    );
    final readyDevices = waitForNewDevice
        ? [
            for (final device in devices)
              if (!previousDeviceIds.contains(device.id)) device,
          ]
        : devices;
    final runningEmulators = allowExistingEmulatorFallback
        ? [
            for (final device in devices)
              if (_isRunningEmulatorDevice(device)) device,
          ]
        : const <FlutterDeviceTarget>[];
    if (readyDevices.isNotEmpty || runningEmulators.length == 1) {
      return FlutterExampleRunResult(
        exitCode: 0,
        platform: platform,
        command: 'flutter devices --machine',
        diagnostics: const [],
        details: {'devicesJson': result.stdout},
      );
    }
    if (DateTime.now().isAfter(deadline) || deviceTimeout == Duration.zero) {
      break;
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
      ..._commandDetails(lastResult),
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
