import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import '../context/fluoh_environment.dart';
import '../ohos/device_runner.dart';
import '../ohos/ohos_toolchain.dart';

enum FluohPlatform { android, ios, ohos }

extension FluohPlatformName on FluohPlatform {
  String get cliName {
    return switch (this) {
      FluohPlatform.android => 'android',
      FluohPlatform.ios => 'ios',
      FluohPlatform.ohos => 'ohos',
    };
  }
}

class PlatformDoctorReport {
  const PlatformDoctorReport({required this.platform, required this.checks});

  final FluohPlatform platform;
  final List<PlatformToolCheck> checks;

  bool get ok => checks.every((check) => check.ok);

  Map<String, Object?> toJson() {
    return {
      'platform': platform.cliName,
      'ok': ok,
      'checks': checks.map((check) => check.toJson()).toList(),
    };
  }
}

class PlatformToolCheck {
  const PlatformToolCheck({
    required this.id,
    required this.label,
    required this.ok,
    required this.message,
    this.path,
    this.command,
  });

  final String id;
  final String label;
  final bool ok;
  final String message;
  final String? path;
  final List<String>? command;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'label': label,
      'status': ok ? 'ok' : 'warning',
      'message': message,
      if (path != null) 'path': path,
      if (command != null) 'command': command,
    };
  }
}

class PlatformTargetReport {
  const PlatformTargetReport({
    required this.platform,
    required this.kind,
    required this.ok,
    required this.targets,
    this.message,
  });

  final FluohPlatform platform;
  final String kind;
  final bool ok;
  final List<PlatformTarget> targets;
  final String? message;

  Map<String, Object?> toJson() {
    return {
      'platform': platform.cliName,
      'kind': kind,
      'ok': ok,
      'targets': targets.map((target) => target.toJson()).toList(),
      if (message != null) 'message': message,
    };
  }
}

class PlatformTarget {
  const PlatformTarget({
    required this.platform,
    required this.id,
    required this.name,
    required this.kind,
    this.state,
    this.details = const {},
  });

  final FluohPlatform platform;
  final String id;
  final String name;
  final String kind;
  final String? state;
  final Map<String, Object?> details;

  Map<String, Object?> toJson() {
    return {
      'platform': platform.cliName,
      'id': id,
      'name': name,
      'kind': kind,
      if (state != null) 'state': state,
      if (details.isNotEmpty) 'details': details,
    };
  }
}

class PlatformStartResult {
  const PlatformStartResult({
    required this.platform,
    required this.ok,
    required this.emulator,
    required this.command,
    required this.message,
    this.pid,
  });

  final FluohPlatform platform;
  final bool ok;
  final String emulator;
  final List<String> command;
  final String message;
  final int? pid;

  Map<String, Object?> toJson() {
    return {
      'platform': platform.cliName,
      'ok': ok,
      'emulator': emulator,
      'command': command,
      'message': message,
      if (pid != null) 'pid': pid,
    };
  }
}

Future<List<PlatformDoctorReport>> inspectPlatformEnvironment({
  required FluohEnvironment environment,
  required List<FluohPlatform> platforms,
}) async {
  return [
    for (final platform in platforms)
      switch (platform) {
        FluohPlatform.android => await _inspectAndroid(environment),
        FluohPlatform.ios => await _inspectIos(environment),
        FluohPlatform.ohos => await _inspectOhos(environment),
      },
  ];
}

Future<List<PlatformTargetReport>> listPlatformDeviceReports({
  required FluohEnvironment environment,
  required List<FluohPlatform> platforms,
}) async {
  return [
    for (final platform in platforms)
      switch (platform) {
        FluohPlatform.android => await _listAndroidDevices(environment),
        FluohPlatform.ios => await _listIosDevices(environment),
        FluohPlatform.ohos => await _listOhosDevices(environment),
      },
  ];
}

Future<List<PlatformTargetReport>> listPlatformEmulatorReports({
  required FluohEnvironment environment,
  required List<FluohPlatform> platforms,
}) async {
  return [
    for (final platform in platforms)
      switch (platform) {
        FluohPlatform.android => await _listAndroidEmulators(environment),
        FluohPlatform.ios => await _listIosDevices(
          environment,
          kind: 'emulator',
        ),
        FluohPlatform.ohos => await _listOhosEmulators(environment),
      },
  ];
}

Future<PlatformStartResult> startPlatformEmulator({
  required FluohEnvironment environment,
  required FluohPlatform platform,
  required String? emulator,
}) async {
  return switch (platform) {
    FluohPlatform.android => _startAndroidEmulator(environment, emulator),
    FluohPlatform.ios => _startIosSimulator(environment, emulator),
    FluohPlatform.ohos => _startOhosEmulator(environment, emulator),
  };
}

Future<PlatformDoctorReport> _inspectAndroid(
  FluohEnvironment environment,
) async {
  final env = environment.processEnvironment;
  final sdkRoot = _androidSdkRoot(env);
  final adb = await _findExecutable(
    environment: env,
    environmentKey: 'FLUOH_ANDROID_ADB',
    candidates: [if (sdkRoot != null) '${sdkRoot.path}/platform-tools/adb'],
    fallbackName: 'adb',
  );
  final emulator = await _findExecutable(
    environment: env,
    environmentKey: 'FLUOH_ANDROID_EMULATOR',
    candidates: [if (sdkRoot != null) '${sdkRoot.path}/emulator/emulator'],
    fallbackName: 'emulator',
  );
  final avdManager = await _findExecutable(
    environment: env,
    environmentKey: 'FLUOH_ANDROID_AVDMANAGER',
    candidates: [
      if (sdkRoot != null)
        '${sdkRoot.path}/cmdline-tools/latest/bin/avdmanager',
      if (sdkRoot != null) '${sdkRoot.path}/tools/bin/avdmanager',
    ],
    fallbackName: 'avdmanager',
  );
  final java = await _findExecutable(
    environment: env,
    environmentKey: 'FLUOH_JAVA',
    candidates: [
      if (_nonEmpty(env['JAVA_HOME'])) '${env['JAVA_HOME']!.trim()}/bin/java',
    ],
    fallbackName: 'java',
  );

  return PlatformDoctorReport(
    platform: FluohPlatform.android,
    checks: [
      PlatformToolCheck(
        id: 'android.sdk',
        label: 'Android SDK',
        ok: sdkRoot != null && await sdkRoot.exists(),
        message: sdkRoot == null
            ? 'ANDROID_SDK_ROOT or ANDROID_HOME is not set.'
            : await sdkRoot.exists()
            ? 'Android SDK root exists.'
            : 'Android SDK root does not exist.',
        path: sdkRoot?.path,
      ),
      _toolCheck(
        id: 'android.adb',
        label: 'adb',
        executable: adb,
        missingMessage: 'adb was not found in the Android SDK or PATH.',
      ),
      _toolCheck(
        id: 'android.emulator',
        label: 'Android emulator',
        executable: emulator,
        missingMessage:
            'Android emulator was not found in the Android SDK or PATH.',
      ),
      _toolCheck(
        id: 'android.avdmanager',
        label: 'avdmanager',
        executable: avdManager,
        missingMessage:
            'avdmanager was not found; emulator creation may require Android Studio.',
      ),
      _toolCheck(
        id: 'android.java',
        label: 'Java',
        executable: java,
        missingMessage: 'Java was not found through JAVA_HOME or PATH.',
      ),
    ],
  );
}

Future<PlatformDoctorReport> _inspectIos(FluohEnvironment environment) async {
  final env = environment.processEnvironment;
  final xcrun = await _xcrun(env);
  final developerDir = await _xcodeDeveloperDirectory(env);
  final simctl = xcrun == null
      ? _CommandRun(exitCode: 1, stdout: '', stderr: 'xcrun not found')
      : await _runTool(xcrun.path, const [
          'simctl',
          'list',
          'devices',
          'available',
          '--json',
        ], environment: env);

  return PlatformDoctorReport(
    platform: FluohPlatform.ios,
    checks: [
      _toolCheck(
        id: 'ios.xcrun',
        label: 'xcrun',
        executable: xcrun,
        missingMessage:
            'xcrun was not found; install Xcode command line tools.',
      ),
      PlatformToolCheck(
        id: 'ios.xcode',
        label: 'Xcode',
        ok: developerDir != null,
        message: developerDir == null
            ? 'Xcode developer directory was not found.'
            : 'Xcode developer directory exists.',
        path: developerDir,
      ),
      PlatformToolCheck(
        id: 'ios.simctl',
        label: 'simctl',
        ok: simctl.exitCode == 0,
        message: simctl.exitCode == 0
            ? 'simctl can list available simulators.'
            : 'simctl could not list available simulators.',
        command: xcrun == null
            ? null
            : [xcrun.path, 'simctl', 'list', 'devices', 'available', '--json'],
      ),
    ],
  );
}

Future<PlatformDoctorReport> _inspectOhos(FluohEnvironment environment) async {
  final checks = <PlatformToolCheck>[];
  try {
    final toolchain = await locateOhosToolchain(
      environment: environment.processEnvironment,
    );
    checks.addAll([
      PlatformToolCheck(
        id: 'ohos.deveco',
        label: 'DevEco Studio',
        ok: true,
        message: 'DevEco Studio was found.',
        path: toolchain.devEcoStudio.path,
      ),
      PlatformToolCheck(
        id: 'ohos.sdk',
        label: 'OpenHarmony SDK',
        ok: true,
        message: 'OpenHarmony SDK was found.',
        path: toolchain.openHarmonySdk.path,
      ),
      _fileCheck(
        id: 'ohos.hdc',
        label: 'hdc',
        file: toolchain.hdc,
        missingMessage: 'hdc was not found in the OpenHarmony toolchain.',
      ),
      _fileCheck(
        id: 'ohos.sign',
        label: 'hap-sign-tool',
        file: toolchain.hapSignTool,
        missingMessage: 'hap-sign-tool was not found.',
      ),
      _fileCheck(
        id: 'ohos.emulator',
        label: 'DevEco emulator',
        file: toolchain.emulator,
        missingMessage: 'DevEco emulator binary was not found.',
      ),
    ]);
  } on Object catch (error) {
    checks.add(
      PlatformToolCheck(
        id: 'ohos.toolchain',
        label: 'OHOS toolchain',
        ok: false,
        message: error.toString(),
      ),
    );
  }

  final emulators = await _safeOhosEmulators(environment);
  checks.add(
    PlatformToolCheck(
      id: 'ohos.local_emulators',
      label: 'Local DevEco emulators',
      ok: emulators.isNotEmpty,
      message: emulators.isEmpty
          ? 'No local DevEco emulator HVD was found.'
          : 'Local emulators: ${emulators.map((item) => item.name).join(', ')}.',
    ),
  );
  return PlatformDoctorReport(platform: FluohPlatform.ohos, checks: checks);
}

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
      message: 'adb was not found in the Android SDK or PATH.',
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
      message: 'Android emulator was not found in the Android SDK or PATH.',
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
      message: 'xcrun was not found; install Xcode command line tools.',
    );
  }
  final result = await _runTool(xcrun.path, const [
    'simctl',
    'list',
    'devices',
    'available',
    '--json',
  ], environment: environment.processEnvironment);
  if (result.exitCode != 0) {
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
    targets: parseSimctlDevices(result.stdout),
  );
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
      message: report.message ?? 'Could not list Android emulators.',
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
      message: 'Android emulator executable was not found.',
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
    message: 'Started Android emulator ${emulator.id}.',
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
      message: report.message ?? 'Could not list iOS simulators.',
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
      message: 'xcrun was not found.',
    );
  }
  final command = [xcrun.path, 'simctl', 'boot', simulator.id];
  final result = await _runTool(xcrun.path, [
    'simctl',
    'boot',
    simulator.id,
  ], environment: environment.processEnvironment);
  final alreadyBooted =
      result.stderr.toLowerCase().contains('booted') ||
      result.stdout.toLowerCase().contains('booted');
  final ok = result.exitCode == 0 || alreadyBooted;
  return PlatformStartResult(
    platform: FluohPlatform.ios,
    ok: ok,
    emulator: simulator.id,
    command: command,
    message: ok
        ? 'Started iOS simulator ${simulator.name}.'
        : _commandFailureMessage(command.join(' '), result),
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
      message: 'Started OHOS emulator ${result.emulator.name}.',
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

List<PlatformTarget> parseAdbDevices(String output) {
  final targets = <PlatformTarget>[];
  for (final rawLine in const LineSplitter().convert(output)) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('List of devices')) {
      continue;
    }
    final parts = line.split(RegExp(r'\s+'));
    if (parts.length < 2) {
      continue;
    }
    final id = parts.first;
    final state = parts[1];
    targets.add(
      PlatformTarget(
        platform: FluohPlatform.android,
        id: id,
        name: _androidDeviceName(parts.skip(2).toList(), id),
        kind: id.startsWith('emulator-') ? 'emulator' : 'device',
        state: state,
        details: {'raw': line},
      ),
    );
  }
  return targets;
}

List<PlatformTarget> parseSimctlDevices(String output) {
  final decoded = jsonDecode(output);
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('Expected simctl JSON object.');
  }
  final devices = decoded['devices'];
  if (devices is! Map) {
    return const [];
  }
  final targets = <PlatformTarget>[];
  for (final entry in devices.entries) {
    final runtime = entry.key.toString();
    final list = entry.value;
    if (list is! List) {
      continue;
    }
    for (final item in list) {
      if (item is! Map) {
        continue;
      }
      final id = item['udid']?.toString() ?? '';
      final name = item['name']?.toString() ?? id;
      if (id.isEmpty) {
        continue;
      }
      targets.add(
        PlatformTarget(
          platform: FluohPlatform.ios,
          id: id,
          name: name,
          kind: 'emulator',
          state: item['state']?.toString(),
          details: {
            'runtime': runtime,
            if (item.containsKey('isAvailable'))
              'isAvailable': item['isAvailable'],
          },
        ),
      );
    }
  }
  targets.sort((left, right) => left.name.compareTo(right.name));
  return targets;
}

Future<io.File?> _androidAdb(Map<String, String> env) async {
  final sdkRoot = _androidSdkRoot(env);
  return _findExecutable(
    environment: env,
    environmentKey: 'FLUOH_ANDROID_ADB',
    candidates: [if (sdkRoot != null) '${sdkRoot.path}/platform-tools/adb'],
    fallbackName: 'adb',
  );
}

Future<io.File?> _androidEmulator(Map<String, String> env) async {
  final sdkRoot = _androidSdkRoot(env);
  return _findExecutable(
    environment: env,
    environmentKey: 'FLUOH_ANDROID_EMULATOR',
    candidates: [if (sdkRoot != null) '${sdkRoot.path}/emulator/emulator'],
    fallbackName: 'emulator',
  );
}

io.Directory? _androidSdkRoot(Map<String, String> env) {
  for (final key in const ['ANDROID_SDK_ROOT', 'ANDROID_HOME']) {
    final value = env[key];
    if (_nonEmpty(value)) {
      return io.Directory(value!.trim());
    }
  }
  final home = env['HOME'];
  if (_nonEmpty(home)) {
    return io.Directory('${home!.trim()}/Library/Android/sdk');
  }
  return null;
}

Future<io.File?> _xcrun(Map<String, String> env) {
  return _findExecutable(
    environment: env,
    environmentKey: 'FLUOH_XCRUN',
    candidates: const [],
    fallbackName: 'xcrun',
  );
}

Future<String?> _xcodeDeveloperDirectory(Map<String, String> env) async {
  final developerDir = env['DEVELOPER_DIR'];
  if (_nonEmpty(developerDir) &&
      await io.Directory(developerDir!.trim()).exists()) {
    return developerDir.trim();
  }
  final result = await _runTool('xcode-select', const ['-p'], environment: env);
  if (result.exitCode != 0) {
    return null;
  }
  final path = result.stdout.trim();
  return path.isEmpty ? null : path;
}

Future<io.File?> _findExecutable({
  required Map<String, String> environment,
  required String environmentKey,
  required List<String> candidates,
  required String fallbackName,
}) async {
  final explicit = environment[environmentKey];
  if (_nonEmpty(explicit)) {
    final file = io.File(explicit!.trim());
    return await file.exists() ? file : null;
  }
  for (final candidate in candidates) {
    final file = io.File(candidate);
    if (await file.exists()) {
      return file;
    }
  }
  final which = await _runTool(
    'which',
    [fallbackName],
    environment: environment,
    timeout: const Duration(seconds: 3),
  );
  if (which.exitCode != 0) {
    return null;
  }
  final path = which.stdout.trim().split(RegExp(r'\r\n?|\n')).firstOrNull;
  if (!_nonEmpty(path)) {
    return null;
  }
  final file = io.File(path!.trim());
  return await file.exists() ? file : null;
}

PlatformToolCheck _toolCheck({
  required String id,
  required String label,
  required io.File? executable,
  required String missingMessage,
}) {
  return PlatformToolCheck(
    id: id,
    label: label,
    ok: executable != null,
    message: executable == null ? missingMessage : '$label was found.',
    path: executable?.path,
  );
}

PlatformToolCheck _fileCheck({
  required String id,
  required String label,
  required io.File file,
  required String missingMessage,
}) {
  final exists = file.existsSync();
  return PlatformToolCheck(
    id: id,
    label: label,
    ok: exists,
    message: exists ? '$label was found.' : missingMessage,
    path: file.path,
  );
}

Future<List<OhosLocalEmulator>> _safeOhosEmulators(
  FluohEnvironment environment,
) async {
  try {
    return discoverOhosLocalEmulators(environment: environment);
  } on Object {
    return const [];
  }
}

PlatformTarget? _selectTarget(List<PlatformTarget> targets, String? requested) {
  final query = requested?.trim();
  if (query != null && query.isNotEmpty) {
    for (final target in targets) {
      if (target.id == query || target.name == query) {
        return target;
      }
    }
    return null;
  }
  return targets.length == 1 ? targets.single : null;
}

String _targetSelectionMessage(
  String label,
  List<PlatformTarget> targets,
  String? requested,
) {
  final query = requested?.trim();
  if (query != null && query.isNotEmpty) {
    return '$label $query was not found. Available: ${_targetNames(targets)}.';
  }
  if (targets.isEmpty) {
    return 'No $label is available.';
  }
  return 'Multiple ${label}s are available; pass --emulator with one of: ${_targetNames(targets)}.';
}

String _targetNames(List<PlatformTarget> targets) {
  return targets.isEmpty
      ? 'none'
      : targets.map((target) => target.id).join(', ');
}

String _androidDeviceName(List<String> details, String fallback) {
  for (final detail in details) {
    if (detail.startsWith('model:')) {
      return detail.substring('model:'.length).replaceAll('_', ' ');
    }
  }
  return fallback;
}

Future<_CommandRun> _runTool(
  String executable,
  List<String> arguments, {
  required Map<String, String> environment,
  Duration timeout = const Duration(seconds: 15),
}) async {
  try {
    final result = await io.Process.run(
      executable,
      arguments,
      environment: environment,
    ).timeout(timeout);
    return _CommandRun(
      exitCode: result.exitCode,
      stdout: result.stdout.toString(),
      stderr: result.stderr.toString(),
    );
  } on Object catch (error) {
    return _CommandRun(exitCode: 1, stdout: '', stderr: error.toString());
  }
}

String _commandFailureMessage(String command, _CommandRun result) {
  final output = [
    result.stderr.trim(),
    result.stdout.trim(),
  ].where((item) => item.isNotEmpty).join('\n');
  return output.isEmpty
      ? '$command failed with exit code ${result.exitCode}.'
      : '$command failed with exit code ${result.exitCode}: $output';
}

bool _nonEmpty(String? value) => value != null && value.trim().isNotEmpty;

class _CommandRun {
  const _CommandRun({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}
