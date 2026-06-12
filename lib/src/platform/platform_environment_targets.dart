part of 'platform_environment.dart';

Future<PlatformTargetReport> _listAndroidDevices(
  FluohEnvironment environment,
) async {
  final adb = await _androidAdb(environment.processEnvironment);
  if (adb == null) {
    return const PlatformTargetReport(
      platform: FluohPlatform.android,
      kind: 'device',
      ok: false,
      targets: [],
      message: 'adb was not found in the Android SDK or PATH',
    );
  }
  final result = await _runTool(adb.path, const [
    'devices',
    '-l',
  ], environment: environment.processEnvironment);
  if (result.exitCode != 0) {
    return PlatformTargetReport(
      platform: FluohPlatform.android,
      kind: 'device',
      ok: false,
      targets: const [],
      message: _commandFailureMessage('adb devices -l', result),
    );
  }
  return PlatformTargetReport(
    platform: FluohPlatform.android,
    kind: 'device',
    ok: true,
    targets: parseAdbDevices(result.stdout),
  );
}

Future<PlatformTargetReport> _listAndroidEmulators(
  FluohEnvironment environment,
) async {
  final emulator = await _androidEmulator(environment.processEnvironment);
  if (emulator == null) {
    return const PlatformTargetReport(
      platform: FluohPlatform.android,
      kind: 'emulator',
      ok: false,
      targets: [],
      message: 'Android emulator was not found in the Android SDK or PATH',
    );
  }
  final result = await _runTool(emulator.path, const [
    '-list-avds',
  ], environment: environment.processEnvironment);
  if (result.exitCode != 0) {
    return PlatformTargetReport(
      platform: FluohPlatform.android,
      kind: 'emulator',
      ok: false,
      targets: const [],
      message: _commandFailureMessage('emulator -list-avds', result),
    );
  }
  return PlatformTargetReport(
    platform: FluohPlatform.android,
    kind: 'emulator',
    ok: true,
    targets: [
      for (final name in const LineSplitter().convert(result.stdout))
        if (name.trim().isNotEmpty)
          PlatformTarget(
            platform: FluohPlatform.android,
            id: name.trim(),
            name: name.trim(),
            kind: 'emulator',
          ),
    ],
  );
}

Future<PlatformTargetReport> _listIosDevices(
  FluohEnvironment environment, {
  String kind = 'device',
}) async {
  final xcrun = await _xcrun(environment.processEnvironment);
  if (xcrun == null) {
    return PlatformTargetReport(
      platform: FluohPlatform.ios,
      kind: kind,
      ok: false,
      targets: const [],
      message: 'xcrun was not found; install Xcode command line tools',
    );
  }
  final result = await _runTool(xcrun.path, const [
    'simctl',
    'list',
    'devices',
    'available',
    '--json',
  ], environment: environment.processEnvironment);
  if (result.exitCode != 0 && kind != 'device') {
    return PlatformTargetReport(
      platform: FluohPlatform.ios,
      kind: kind,
      ok: false,
      targets: const [],
      message: _commandFailureMessage('xcrun simctl list devices', result),
    );
  }
  final simulators = result.exitCode == 0
      ? parseSimctlDevices(result.stdout, onlyBooted: kind == 'device')
      : const <PlatformTarget>[];
  final physicalDevices = kind == 'device'
      ? await _listIosPhysicalDevices(
          xcrun.path,
          environment.processEnvironment,
        )
      : const <PlatformTarget>[];
  if (result.exitCode != 0 && physicalDevices.isEmpty) {
    return PlatformTargetReport(
      platform: FluohPlatform.ios,
      kind: kind,
      ok: false,
      targets: const [],
      message: _commandFailureMessage('xcrun simctl list devices', result),
    );
  }
  return PlatformTargetReport(
    platform: FluohPlatform.ios,
    kind: kind,
    ok: true,
    targets: [...physicalDevices, ...simulators],
  );
}

Future<PlatformTargetReport> _listMacosDevices(
  FluohEnvironment environment,
) async {
  if (!io.Platform.isMacOS) {
    return const PlatformTargetReport(
      platform: FluohPlatform.macos,
      kind: 'device',
      ok: false,
      targets: [],
      message: 'macOS desktop targets require a macOS host',
    );
  }
  return PlatformTargetReport(
    platform: FluohPlatform.macos,
    kind: 'device',
    ok: true,
    targets: [
      PlatformTarget(
        platform: FluohPlatform.macos,
        id: 'macos',
        name: 'macOS',
        kind: 'device',
        state: 'available',
        details: {
          'runtime': ?_hostRuntimeIdentifier(),
          if (io.Platform.operatingSystemVersion.trim() case final version
              when version.isNotEmpty)
            'osVersion': normalizeAppleOperatingSystemVersion(version),
          'host': ?environment.processEnvironment['HOSTNAME'],
        },
      ),
    ],
  );
}

PlatformTargetReport _listLinuxDevices(FluohEnvironment environment) {
  if (!io.Platform.isLinux) {
    return const PlatformTargetReport(
      platform: FluohPlatform.linux,
      kind: 'device',
      ok: false,
      targets: [],
      message: 'Linux desktop targets require a Linux host',
    );
  }
  return PlatformTargetReport(
    platform: FluohPlatform.linux,
    kind: 'device',
    ok: true,
    targets: [_hostDesktopTarget(environment, FluohPlatform.linux, 'Linux')],
  );
}

PlatformTargetReport _listWindowsDevices(FluohEnvironment environment) {
  if (!io.Platform.isWindows) {
    return const PlatformTargetReport(
      platform: FluohPlatform.windows,
      kind: 'device',
      ok: false,
      targets: [],
      message: 'Windows desktop targets require a Windows host',
    );
  }
  return PlatformTargetReport(
    platform: FluohPlatform.windows,
    kind: 'device',
    ok: true,
    targets: [
      _hostDesktopTarget(environment, FluohPlatform.windows, 'Windows'),
    ],
  );
}

Future<PlatformTargetReport> _listWebDevices(
  FluohEnvironment environment,
) async {
  final env = environment.processEnvironment;
  final chrome = await _findWebChromeExecutable(env);
  final chromeVersion = await _toolVersion(chrome, const [
    '--version',
  ], environment: env);
  return PlatformTargetReport(
    platform: FluohPlatform.web,
    kind: 'device',
    ok: true,
    targets: [
      if (chrome != null)
        PlatformTarget(
          platform: FluohPlatform.web,
          id: 'chrome',
          name: 'Chrome',
          kind: 'device',
          state: 'available',
          details: {
            'runtime': 'chrome',
            'path': chrome.path,
            'version': ?chromeVersion,
          },
        ),
    ],
    message: chrome == null ? 'Chrome was not found' : null,
  );
}

PlatformTarget _hostDesktopTarget(
  FluohEnvironment environment,
  FluohPlatform platform,
  String name,
) {
  return PlatformTarget(
    platform: platform,
    id: platform.cliName,
    name: name,
    kind: 'device',
    state: 'available',
    details: {
      'runtime': ?_hostRuntimeIdentifier(),
      if (io.Platform.operatingSystemVersion.trim() case final version
          when version.isNotEmpty)
        'osVersion': version,
      'host': ?environment.processEnvironment['HOSTNAME'],
    },
  );
}

String? _hostRuntimeIdentifier() {
  final match = RegExp(r'on "([^"]+)"').firstMatch(io.Platform.version);
  final value = match?.group(1)?.trim();
  if (value == null || value.isEmpty) {
    return null;
  }
  final normalized = value.replaceAll('_', '-');
  if (io.Platform.operatingSystem == 'macos' &&
      normalized.startsWith('macos-')) {
    return 'darwin-${normalized.substring('macos-'.length)}';
  }
  return normalized;
}

PlatformTargetReport _listMacosEmulators() {
  return const PlatformTargetReport(
    platform: FluohPlatform.macos,
    kind: 'emulator',
    ok: true,
    targets: [],
  );
}

PlatformTargetReport _listDesktopEmulators(FluohPlatform platform) {
  return PlatformTargetReport(
    platform: platform,
    kind: 'emulator',
    ok: true,
    targets: const [],
  );
}

PlatformTargetReport _listNoEmulators(FluohPlatform platform) {
  return PlatformTargetReport(
    platform: platform,
    kind: 'emulator',
    ok: true,
    targets: const [],
  );
}

Future<List<PlatformTarget>> _listIosPhysicalDevices(
  String xcrun,
  Map<String, String> environment,
) async {
  final targets = <PlatformTarget>[];
  final devicectlOutput = await _devicectlListDevicesJson(xcrun, environment);
  if (devicectlOutput != null) {
    try {
      _addUniqueTargets(targets, parseDevicectlDevices(devicectlOutput));
    } on Object {
      // Fall through to xcdevice; devicectl JSON has changed across Xcode
      // versions, while xcdevice covers paired wireless devices in practice.
    }
  }

  final xcdevice = await _runTool(
    xcrun,
    const ['xcdevice', 'list', '--timeout', '2'],
    environment: environment,
    timeout: const Duration(seconds: 5),
  );
  if (xcdevice.exitCode == 0) {
    try {
      _addUniqueTargets(targets, parseXcdeviceDevices(xcdevice.stdout));
    } on Object {
      // Keep the older xctrace fallback below for Xcode variants that do not
      // emit parseable xcdevice JSON.
    }
  }

  if (targets.isEmpty) {
    final xctrace = await _runTool(xcrun, const [
      'xctrace',
      'list',
      'devices',
    ], environment: environment);
    if (xctrace.exitCode == 0) {
      _addUniqueTargets(targets, parseXctraceDevices(xctrace.stdout));
    }
  }

  targets.sort((left, right) => left.name.compareTo(right.name));
  return targets;
}

Future<String?> _devicectlListDevicesJson(
  String xcrun,
  Map<String, String> environment,
) async {
  final stdoutJson = await _runTool(
    xcrun,
    const ['devicectl', 'list', 'devices', '--json'],
    environment: environment,
    timeout: const Duration(seconds: 5),
  );
  if (stdoutJson.exitCode == 0 && stdoutJson.stdout.trim().isNotEmpty) {
    return stdoutJson.stdout;
  }

  io.Directory? temp;
  try {
    temp = await io.Directory.systemTemp.createTemp('fluoh_devicectl_');
    final output = io.File('${temp.path}/devices.json');
    final fileJson = await _runTool(
      xcrun,
      ['devicectl', 'list', 'devices', '--json-output', output.path],
      environment: environment,
      timeout: const Duration(seconds: 5),
    );
    if (fileJson.exitCode != 0 || !await output.exists()) {
      return null;
    }
    final content = await output.readAsString();
    return content.trim().isEmpty ? null : content;
  } on Object {
    return null;
  } finally {
    if (temp != null) {
      try {
        await temp.delete(recursive: true);
      } on Object {
        // Best-effort cleanup for temporary devicectl JSON output.
      }
    }
  }
}

Future<PlatformTargetReport> _listOhosDevices(
  FluohEnvironment environment,
) async {
  try {
    final targets = await listOhosDeviceTargets(environment: environment);
    return PlatformTargetReport(
      platform: FluohPlatform.ohos,
      kind: 'device',
      ok: true,
      targets: [
        for (final target in targets)
          PlatformTarget(
            platform: FluohPlatform.ohos,
            id: target.id,
            name: target.id,
            kind: 'device',
            details: {if (target.details != null) 'details': target.details},
          ),
      ],
    );
  } on Object catch (error) {
    return PlatformTargetReport(
      platform: FluohPlatform.ohos,
      kind: 'device',
      ok: false,
      targets: const [],
      message: error.toString(),
    );
  }
}

Future<PlatformTargetReport> _listOhosEmulators(
  FluohEnvironment environment,
) async {
  try {
    final emulators = await discoverOhosLocalEmulators(
      environment: environment,
    );
    return PlatformTargetReport(
      platform: FluohPlatform.ohos,
      kind: 'emulator',
      ok: true,
      targets: [
        for (final emulator in emulators)
          PlatformTarget(
            platform: FluohPlatform.ohos,
            id: emulator.name,
            name: emulator.name,
            kind: 'emulator',
            details: {
              'deployedRoot': emulator.deployedRoot.path,
              'imageRoot': emulator.imageRoot.path,
              if (emulator.apiVersion != null)
                'apiVersion': emulator.apiVersion,
            },
          ),
      ],
    );
  } on Object catch (error) {
    return PlatformTargetReport(
      platform: FluohPlatform.ohos,
      kind: 'emulator',
      ok: false,
      targets: const [],
      message: error.toString(),
    );
  }
}

Future<PlatformStartResult> _startAndroidEmulator(
  FluohEnvironment environment,
  String? requested,
) async {
  final report = await _listAndroidEmulators(environment);
  if (!report.ok) {
    return PlatformStartResult(
      platform: FluohPlatform.android,
      ok: false,
      emulator: requested ?? '',
      command: const [],
      message: report.message ?? 'Could not list Android emulators',
    );
  }
  final emulator = _selectTarget(report.targets, requested);
  if (emulator == null) {
    return PlatformStartResult(
      platform: FluohPlatform.android,
      ok: false,
      emulator: requested ?? '',
      command: const [],
      message: _targetSelectionMessage(
        'Android emulator',
        report.targets,
        requested,
      ),
    );
  }
  final executable = await _androidEmulator(environment.processEnvironment);
  if (executable == null) {
    return PlatformStartResult(
      platform: FluohPlatform.android,
      ok: false,
      emulator: emulator.id,
      command: const [],
      message: 'Android emulator executable was not found',
    );
  }
  final command = [executable.path, '-avd', emulator.id];
  final process = await io.Process.start(
    executable.path,
    ['-avd', emulator.id],
    environment: environment.processEnvironment,
    mode: io.ProcessStartMode.detached,
  );
  return PlatformStartResult(
    platform: FluohPlatform.android,
    ok: true,
    emulator: emulator.id,
    command: command,
    message: 'Started Android emulator ${emulator.id}',
    pid: process.pid,
  );
}

Future<PlatformStartResult> _startIosSimulator(
  FluohEnvironment environment,
  String? requested,
) async {
  final report = await _listIosDevices(environment, kind: 'emulator');
  if (!report.ok) {
    return PlatformStartResult(
      platform: FluohPlatform.ios,
      ok: false,
      emulator: requested ?? '',
      command: const [],
      message: report.message ?? 'Could not list iOS simulators',
    );
  }
  final simulator = _selectTarget(report.targets, requested);
  if (simulator == null) {
    return PlatformStartResult(
      platform: FluohPlatform.ios,
      ok: false,
      emulator: requested ?? '',
      command: const [],
      message: _targetSelectionMessage(
        'iOS simulator',
        report.targets,
        requested,
      ),
    );
  }
  final xcrun = await _xcrun(environment.processEnvironment);
  if (xcrun == null) {
    return PlatformStartResult(
      platform: FluohPlatform.ios,
      ok: false,
      emulator: simulator.id,
      command: const [],
      message: 'xcrun was not found',
    );
  }
  final command = [xcrun.path, 'simctl', 'boot', simulator.id];
  final result = await _runTool(
    xcrun.path,
    ['simctl', 'boot', simulator.id],
    environment: environment.processEnvironment,
    timeout: const Duration(minutes: 3),
  );
  final alreadyBooted =
      result.stderr.toLowerCase().contains('booted') ||
      result.stdout.toLowerCase().contains('booted');
  final ok = result.exitCode == 0 || alreadyBooted;
  if (ok) {
    final bootStatus = await _runTool(
      xcrun.path,
      ['simctl', 'bootstatus', simulator.id, '-b'],
      environment: environment.processEnvironment,
      timeout: const Duration(minutes: 3),
    );
    if (bootStatus.exitCode != 0) {
      return PlatformStartResult(
        platform: FluohPlatform.ios,
        ok: false,
        emulator: simulator.id,
        command: [xcrun.path, 'simctl', 'bootstatus', simulator.id, '-b'],
        message: _commandFailureMessage('xcrun simctl bootstatus', bootStatus),
      );
    }
    await _foregroundIosSimulator(environment, simulator.id);
  }
  return PlatformStartResult(
    platform: FluohPlatform.ios,
    ok: ok,
    emulator: simulator.id,
    command: command,
    message: ok
        ? 'Started iOS simulator ${simulator.name}'
        : _commandFailureMessage(command.join(' '), result),
  );
}

Future<void> _foregroundIosSimulator(
  FluohEnvironment environment,
  String simulatorId,
) async {
  final mode = environment.processEnvironment['FLUOH_IOS_FOREGROUND_SIMULATOR']
      ?.trim()
      .toLowerCase();
  if (mode == '0' || mode == 'false' || mode == 'off' || mode == 'no') {
    return;
  }
  final open = await _openSimulatorTool(environment.processEnvironment);
  if (open == null) {
    return;
  }
  await _runTool(
    open.path,
    ['-a', 'Simulator', '--args', '-CurrentDeviceUDID', simulatorId],
    environment: environment.processEnvironment,
    timeout: const Duration(seconds: 15),
  );
}

PlatformStartResult _startMacosEmulator(String? requested) {
  return PlatformStartResult(
    platform: FluohPlatform.macos,
    ok: false,
    emulator: requested ?? '',
    command: const [],
    message: 'macOS uses the local host and does not provide emulators',
  );
}

PlatformStartResult _startDesktopEmulator(FluohPlatform platform) {
  return PlatformStartResult(
    platform: platform,
    ok: false,
    emulator: '',
    command: const [],
    message:
        '${platform.cliName} uses the matching local host and does not provide emulators',
  );
}

PlatformStartResult _startNoEmulator(
  FluohPlatform platform,
  String? requested,
) {
  return PlatformStartResult(
    platform: platform,
    ok: false,
    emulator: requested ?? '',
    command: const [],
    message:
        '${platform.cliName} uses Flutter web devices and does not provide emulators',
  );
}

Future<PlatformStartResult> _startOhosEmulator(
  FluohEnvironment environment,
  String? requested,
) async {
  try {
    final toolchain = await locateOhosToolchain(
      environment: environment.processEnvironment,
    );
    final result = await startOhosEmulator(
      environment: environment,
      toolchain: toolchain,
      emulatorName: requested,
    );
    return PlatformStartResult(
      platform: FluohPlatform.ohos,
      ok: true,
      emulator: result.emulator.name,
      command: result.command,
      message: 'Started OHOS emulator ${result.emulator.name}',
    );
  } on Object catch (error) {
    return PlatformStartResult(
      platform: FluohPlatform.ohos,
      ok: false,
      emulator: requested ?? '',
      command: const [],
      message: error.toString(),
    );
  }
}
