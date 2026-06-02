import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import '../context/fluoh_environment.dart';
import 'ohos/device_runner.dart';
import 'ohos/ohos_toolchain.dart';

/// Platforms understood by fluoh project and package workflows.
enum FluohPlatform { android, ios, macos, ohos }

/// Convenience methods for [FluohPlatform].
extension FluohPlatformName on FluohPlatform {
  /// Lowercase command-line name for this platform.
  String get cliName {
    return switch (this) {
      FluohPlatform.android => 'android',
      FluohPlatform.ios => 'ios',
      FluohPlatform.macos => 'macos',
      FluohPlatform.ohos => 'ohos',
    };
  }
}

/// Native toolchain diagnostics for one platform.
class PlatformDoctorReport {
  const PlatformDoctorReport({required this.platform, required this.checks});

  /// Platform this report describes.
  final FluohPlatform platform;

  /// Tool checks collected for the platform.
  final List<PlatformToolCheck> checks;

  /// Whether all checks passed.
  bool get ok => checks.every((check) => check.ok);

  /// Converts this report to the command JSON contract.
  Map<String, Object?> toJson() {
    return {
      'platform': platform.cliName,
      'ok': ok,
      'checks': checks.map((check) => check.toJson()).toList(),
    };
  }
}

/// Result of one native toolchain check.
class PlatformToolCheck {
  const PlatformToolCheck({
    required this.id,
    required this.label,
    required this.ok,
    required this.message,
    this.path,
    this.version,
    this.command,
    this.details = const {},
  });

  /// Stable check identifier.
  final String id;

  /// User-facing tool label.
  final String label;

  /// Whether the check passed.
  final bool ok;

  /// Human-readable check result.
  final String message;

  /// Tool or SDK path, when available.
  final String? path;

  /// Tool or SDK version, when available.
  final String? version;

  /// Command used for this check, when relevant.
  final List<String>? command;

  /// Additional structured check data.
  final Map<String, Object?> details;

  /// Converts this check to the command JSON contract.
  Map<String, Object?> toJson() {
    return {
      'id': id,
      'label': label,
      'status': ok ? 'ok' : 'warning',
      'message': message,
      if (path != null) 'path': path,
      if (version != null) 'version': version,
      if (command != null) 'command': command,
      if (details.isNotEmpty) 'details': details,
    };
  }
}

/// Target listing report for devices or emulators on one platform.
class PlatformTargetReport {
  const PlatformTargetReport({
    required this.platform,
    required this.kind,
    required this.ok,
    required this.targets,
    this.message,
  });

  /// Platform this report describes.
  final FluohPlatform platform;

  /// Listing kind, usually `device` or `emulator`.
  final String kind;

  /// Whether target discovery succeeded.
  final bool ok;

  /// Targets found for this platform.
  final List<PlatformTarget> targets;

  /// Warning or error message when discovery failed.
  final String? message;

  /// Converts this report to the command JSON contract.
  Map<String, Object?> toJson() {
    return {
      'platform': platform.cliName,
      'kind': kind,
      'ok': ok,
      'targets': targets
          .map((target) => target.toJson(listingKind: kind))
          .toList(),
      if (message != null) 'message': message,
    };
  }
}

/// Connected device, simulator, or emulator discovered by platform tooling.
class PlatformTarget {
  const PlatformTarget({
    required this.platform,
    required this.id,
    required this.name,
    required this.kind,
    this.state,
    this.details = const {},
  });

  /// Platform that owns this target.
  final FluohPlatform platform;

  /// Stable target identifier used by platform tools.
  final String id;

  /// User-facing target name.
  final String name;

  /// Target kind, usually `device` or `emulator`.
  final String kind;

  /// Raw target state reported by platform tooling.
  final String? state;

  /// Platform-specific target details.
  final Map<String, Object?> details;

  /// Converts this target to the machine-output shape used by target reports.
  ///
  /// The optional [listingKind] lets display fields match the command context.
  /// For example, Android `emulator-*` targets discovered by `devices` are
  /// rendered as connected mobile devices, while AVDs discovered by
  /// `emulators` are rendered as emulator rows.
  Map<String, Object?> toJson({String? listingKind}) {
    final connection = platformTargetConnection(this);
    final manufacturer = platformTargetManufacturer(this);
    final summary = platformTargetSummary(this);
    return {
      'platform': platform.cliName,
      'id': id,
      'name': name,
      'kind': kind,
      'displayName': platformTargetDisplayName(this, listingKind: listingKind),
      'displayPlatform': platformTargetDisplayPlatform(this),
      'category': platformTargetCategory(this),
      if (summary.isNotEmpty) 'summary': summary,
      'connection': ?connection,
      'manufacturer': ?manufacturer,
      if (state != null) 'state': state,
      if (details.isNotEmpty) 'details': details,
    };
  }
}

/// Result of starting an emulator or simulator.
class PlatformStartResult {
  const PlatformStartResult({
    required this.platform,
    required this.ok,
    required this.emulator,
    required this.command,
    required this.message,
    this.pid,
  });

  /// Platform that handled the start request.
  final FluohPlatform platform;

  /// Whether the start command succeeded.
  final bool ok;

  /// Emulator or simulator id/name requested by the user.
  final String emulator;

  /// Command used to start the target.
  final List<String> command;

  /// User-facing result message.
  final String message;

  /// Started process id, when available.
  final int? pid;

  /// Converts this result to the command JSON contract.
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

/// Inspects native toolchains for the requested [platforms].
Future<List<PlatformDoctorReport>> inspectPlatformEnvironment({
  required FluohEnvironment environment,
  required List<FluohPlatform> platforms,
}) async {
  final appleToolchain =
      platforms.contains(FluohPlatform.ios) &&
          platforms.contains(FluohPlatform.macos)
      ? await _inspectAppleToolchain(environment.processEnvironment)
      : null;
  return [
    for (final platform in platforms)
      switch (platform) {
        FluohPlatform.android => await _inspectAndroid(environment),
        FluohPlatform.ios => await _inspectIos(
          environment,
          appleToolchain: appleToolchain,
        ),
        FluohPlatform.macos => await _inspectMacos(
          environment,
          appleToolchain: appleToolchain,
        ),
        FluohPlatform.ohos => await _inspectOhos(environment),
      },
  ];
}

/// Lists connected device targets for the requested [platforms].
Future<List<PlatformTargetReport>> listPlatformDeviceReports({
  required FluohEnvironment environment,
  required List<FluohPlatform> platforms,
}) async {
  return [
    for (final platform in platforms)
      switch (platform) {
        FluohPlatform.android => await _listAndroidDevices(environment),
        FluohPlatform.ios => await _listIosDevices(environment),
        FluohPlatform.macos => await _listMacosDevices(environment),
        FluohPlatform.ohos => await _listOhosDevices(environment),
      },
  ];
}

/// Lists local emulator or simulator targets for the requested [platforms].
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
        FluohPlatform.macos => _listMacosEmulators(),
        FluohPlatform.ohos => await _listOhosEmulators(environment),
      },
  ];
}

/// Starts an emulator or simulator for one platform.
Future<PlatformStartResult> startPlatformEmulator({
  required FluohEnvironment environment,
  required FluohPlatform platform,
  required String? emulator,
}) async {
  return switch (platform) {
    FluohPlatform.android => _startAndroidEmulator(environment, emulator),
    FluohPlatform.ios => _startIosSimulator(environment, emulator),
    FluohPlatform.macos => _startMacosEmulator(emulator),
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
      ..._androidStudioBundledJavaCandidates(env),
      if (_nonEmpty(env['JAVA_HOME'])) '${env['JAVA_HOME']!.trim()}/bin/java',
    ],
    fallbackName: 'java',
  );
  final adbVersion = await _toolVersion(
    adb,
    const ['version'],
    environment: env,
    parser: _adbVersion,
  );
  final emulatorVersion = await _toolVersion(
    emulator,
    const ['-version'],
    environment: env,
    parser: _androidEmulatorVersion,
  );
  final avdManagerVersion = await _toolVersion(avdManager, const [
    '--version',
  ], environment: env);
  final javaVersion =
      await _toolVersion(
        java,
        const ['-version'],
        environment: env,
        parser: _javaVersion,
      ) ??
      await _javaReleaseFileVersion(java);
  final androidPlatform = await _latestAndroidPlatform(sdkRoot);
  final buildToolsVersion = await _latestBuildToolsVersion(sdkRoot);
  final licensesAccepted = await _androidLicensesAccepted(sdkRoot);

  return PlatformDoctorReport(
    platform: FluohPlatform.android,
    checks: [
      PlatformToolCheck(
        id: 'android.sdk',
        label: 'Android SDK',
        ok: sdkRoot != null && await sdkRoot.exists(),
        message: sdkRoot == null
            ? 'ANDROID_SDK_ROOT or ANDROID_HOME is not set'
            : await sdkRoot.exists()
            ? 'Android SDK root exists'
            : 'Android SDK root does not exist',
        path: sdkRoot?.path,
        version: buildToolsVersion,
      ),
      PlatformToolCheck(
        id: 'android.platform',
        label: 'Android platform',
        ok: androidPlatform != null && buildToolsVersion != null,
        message: androidPlatform == null
            ? 'No Android platform package was found'
            : buildToolsVersion == null
            ? 'No Android build-tools package was found'
            : 'Android platform and build-tools were found',
        version: androidPlatform,
        details: _optionalDetail('buildTools', buildToolsVersion),
      ),
      _toolCheck(
        id: 'android.adb',
        label: 'adb',
        executable: adb,
        version: adbVersion,
        missingMessage: 'adb was not found in the Android SDK or PATH',
      ),
      _toolCheck(
        id: 'android.emulator',
        label: 'Android emulator',
        executable: emulator,
        version: emulatorVersion,
        missingMessage:
            'Android emulator was not found in the Android SDK or PATH',
      ),
      _toolCheck(
        id: 'android.avdmanager',
        label: 'avdmanager',
        executable: avdManager,
        version: avdManagerVersion,
        missingMessage:
            'avdmanager was not found; emulator creation may require Android Studio.',
      ),
      _toolCheck(
        id: 'android.java',
        label: 'Java',
        executable: java,
        version: javaVersion,
        missingMessage:
            'Java was not found in Android Studio, JAVA_HOME, or PATH',
        details: {
          if (java != null)
            'androidStudioBundledJdk': _isAndroidStudioBundledJdk(java.path),
        },
      ),
      PlatformToolCheck(
        id: 'android.licenses',
        label: 'Android licenses',
        ok: licensesAccepted == true,
        message: licensesAccepted == true
            ? 'All Android licenses accepted'
            : 'Android licenses were not found',
      ),
    ],
  );
}

Future<_AppleToolchain> _inspectAppleToolchain(Map<String, String> env) async {
  final xcrun = await _xcrun(env);
  final developerDir = await _xcodeDeveloperDirectory(env);
  final xcrunVersion = await _toolVersion(
    xcrun,
    const ['--version'],
    environment: env,
    parser: _xcrunVersion,
  );
  final xcodeBuild = xcrun == null
      ? null
      : await _runTool(xcrun.path, const [
          'xcodebuild',
          '-version',
        ], environment: env);
  final xcodeOutput = xcodeBuild == null || xcodeBuild.exitCode != 0
      ? ''
      : '${xcodeBuild.stdout}\n${xcodeBuild.stderr}';
  return _AppleToolchain(
    xcrun: xcrun,
    developerDir: developerDir,
    xcrunVersion: xcrunVersion,
    xcodeVersion: xcodeOutput.isEmpty ? null : _xcodeVersion(xcodeOutput),
    xcodeBuildVersion: xcodeOutput.isEmpty
        ? null
        : _xcodeBuildVersion(xcodeOutput),
  );
}

class _AppleToolchain {
  const _AppleToolchain({
    required this.xcrun,
    required this.developerDir,
    required this.xcrunVersion,
    required this.xcodeVersion,
    required this.xcodeBuildVersion,
  });

  final io.File? xcrun;
  final String? developerDir;
  final String? xcrunVersion;
  final String? xcodeVersion;
  final String? xcodeBuildVersion;
}

Future<PlatformDoctorReport> _inspectIos(
  FluohEnvironment environment, {
  _AppleToolchain? appleToolchain,
}) async {
  final env = environment.processEnvironment;
  final apple = appleToolchain ?? await _inspectAppleToolchain(env);
  final xcrun = apple.xcrun;
  final simctl = xcrun == null
      ? _CommandRun(exitCode: 1, stdout: '', stderr: 'xcrun not found')
      : await _runTool(xcrun.path, const [
          'simctl',
          'list',
          'devices',
          'available',
          '--json',
        ], environment: env);
  final cocoaPods = await _findExecutable(
    environment: env,
    environmentKey: 'FLUOH_COCOAPODS',
    candidates: const [],
    fallbackName: 'pod',
  );
  final cocoaPodsVersion = await _toolVersion(cocoaPods, const [
    '--version',
  ], environment: env);

  return PlatformDoctorReport(
    platform: FluohPlatform.ios,
    checks: [
      _toolCheck(
        id: 'ios.xcrun',
        label: 'xcrun',
        executable: xcrun,
        version: apple.xcrunVersion,
        missingMessage:
            'xcrun was not found; install Xcode command line tools.',
      ),
      PlatformToolCheck(
        id: 'ios.xcode',
        label: 'Xcode',
        ok: apple.developerDir != null,
        message: apple.developerDir == null
            ? 'Xcode developer directory was not found'
            : 'Xcode developer directory exists',
        path: apple.developerDir,
        version: apple.xcodeVersion,
        details: _optionalDetail('buildVersion', apple.xcodeBuildVersion),
      ),
      PlatformToolCheck(
        id: 'ios.simctl',
        label: 'simctl',
        ok: simctl.exitCode == 0,
        message: simctl.exitCode == 0
            ? 'simctl can list available simulators'
            : 'simctl could not list available simulators',
        command: xcrun == null
            ? null
            : [xcrun.path, 'simctl', 'list', 'devices', 'available', '--json'],
      ),
      _toolCheck(
        id: 'ios.cocoapods',
        label: 'CocoaPods',
        executable: cocoaPods,
        version: cocoaPodsVersion,
        missingMessage:
            'CocoaPods was not found; iOS plugin builds may require it.',
      ),
    ],
  );
}

Future<PlatformDoctorReport> _inspectMacos(
  FluohEnvironment environment, {
  _AppleToolchain? appleToolchain,
}) async {
  final apple =
      appleToolchain ??
      await _inspectAppleToolchain(environment.processEnvironment);

  return PlatformDoctorReport(
    platform: FluohPlatform.macos,
    checks: [
      PlatformToolCheck(
        id: 'macos.host',
        label: 'macOS host',
        ok: io.Platform.isMacOS,
        message: io.Platform.isMacOS
            ? 'Running on macOS'
            : 'macOS desktop builds require a macOS host',
        version: normalizeAppleOperatingSystemVersion(
          io.Platform.operatingSystemVersion,
        ),
      ),
      _toolCheck(
        id: 'macos.xcrun',
        label: 'xcrun',
        executable: apple.xcrun,
        version: apple.xcrunVersion,
        missingMessage:
            'xcrun was not found; install Xcode command line tools.',
      ),
      PlatformToolCheck(
        id: 'macos.xcode',
        label: 'Xcode',
        ok: apple.developerDir != null,
        message: apple.developerDir == null
            ? 'Xcode developer directory was not found'
            : 'Xcode developer directory exists',
        path: apple.developerDir,
        version: apple.xcodeVersion,
        details: _optionalDetail('buildVersion', apple.xcodeBuildVersion),
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
    final openHarmonyVersion = await _openHarmonySdkVersion(
      toolchain.openHarmonySdk,
    );
    final hdcVersion = await _toolVersion(
      toolchain.hdc,
      const ['-v'],
      environment: environment.processEnvironment,
      parser: _ohosHdcVersion,
      timeout: const Duration(seconds: 5),
    );
    final emulatorVersion = await _toolVersion(
      toolchain.emulator,
      const ['-version'],
      environment: environment.processEnvironment,
      parser: _ohosEmulatorVersion,
      timeout: const Duration(seconds: 5),
    );
    checks.addAll([
      PlatformToolCheck(
        id: 'ohos.sdk',
        label: 'OpenHarmony SDK',
        ok: true,
        message: 'OpenHarmony SDK was found',
        path: toolchain.openHarmonySdk.path,
        version: openHarmonyVersion,
      ),
      _fileCheck(
        id: 'ohos.hdc',
        label: 'hdc',
        file: toolchain.hdc,
        missingMessage: 'hdc was not found in the OpenHarmony toolchain',
        version: hdcVersion,
      ),
      _fileCheck(
        id: 'ohos.emulator',
        label: 'Emulator',
        file: toolchain.emulator,
        missingMessage: 'Emulator was not found at ${toolchain.emulator.path}',
        version: emulatorVersion,
      ),
    ]);
  } on Object catch (error) {
    checks.add(
      PlatformToolCheck(
        id: 'ohos.toolchain',
        label: 'OpenHarmony toolchain',
        ok: false,
        message: error.toString(),
      ),
    );
  }
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
  if (result.exitCode != 0) {
    return PlatformTargetReport(
      platform: FluohPlatform.ios,
      kind: kind,
      ok: false,
      targets: const [],
      message: _commandFailureMessage('xcrun simctl list devices', result),
    );
  }
  final simulators = parseSimctlDevices(
    result.stdout,
    onlyBooted: kind == 'device',
  );
  final physicalDevices = kind == 'device'
      ? await _listIosPhysicalDevices(
          xcrun.path,
          environment.processEnvironment,
        )
      : const <PlatformTarget>[];
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
        ? 'Started iOS simulator ${simulator.name}'
        : _commandFailureMessage(command.join(' '), result),
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

/// Parses `adb devices -l` output into platform targets.
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

/// Parses `xcrun simctl list devices --json` output.
List<PlatformTarget> parseSimctlDevices(
  String output, {
  bool onlyBooted = false,
}) {
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
      final state = item['state']?.toString();
      if (onlyBooted && state != 'Booted') {
        continue;
      }
      targets.add(
        PlatformTarget(
          platform: FluohPlatform.ios,
          id: id,
          name: name,
          kind: 'emulator',
          state: state,
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

/// Parses `xcrun devicectl list devices` JSON output.
List<PlatformTarget> parseDevicectlDevices(String output) {
  final decoded = jsonDecode(output);
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('Expected devicectl JSON object.');
  }
  final result = decoded['result'];
  final devicesObject = result is Map ? result['devices'] : decoded['devices'];
  if (devicesObject is! List) {
    return const [];
  }
  final targets = <PlatformTarget>[];
  for (final device in devicesObject) {
    if (device is! Map) {
      continue;
    }
    final hardware = _objectMap(device['hardwareProperties']);
    final properties = _objectMap(device['deviceProperties']);
    final connection = _objectMap(device['connectionProperties']);
    final platform = _stringValue(hardware['platform'])?.toLowerCase();
    if (platform != null &&
        !platform.contains('ios') &&
        !platform.contains('ipados')) {
      continue;
    }
    final id =
        _stringValue(device['identifier']) ??
        _stringValue(hardware['udid']) ??
        '';
    if (id.isEmpty) {
      continue;
    }
    final name =
        _stringValue(properties['name']) ??
        _stringValue(hardware['marketingName']) ??
        id;
    targets.add(
      PlatformTarget(
        platform: FluohPlatform.ios,
        id: id,
        name: name,
        kind: 'device',
        details: {
          'source': 'devicectl',
          if (_stringValue(hardware['platform']) != null)
            'platform': _stringValue(hardware['platform']),
          if (_stringValue(properties['osVersionNumber']) != null)
            'osVersion': _stringValue(properties['osVersionNumber']),
          if (_stringValue(hardware['marketingName']) != null)
            'model': _stringValue(hardware['marketingName']),
          if (_stringValue(connection['transportType']) != null)
            'transport': _stringValue(connection['transportType']),
          if (_stringValue(connection['pairingState']) != null)
            'pairingState': _stringValue(connection['pairingState']),
          if (_stringValue(connection['tunnelState']) != null)
            'tunnelState': _stringValue(connection['tunnelState']),
        },
      ),
    );
  }
  targets.sort((left, right) => left.name.compareTo(right.name));
  return targets;
}

/// Parses `xcrun xcdevice list --timeout` JSON output.
List<PlatformTarget> parseXcdeviceDevices(String output) {
  final decoded = _decodeJsonOutput(output);
  final devicesObject = switch (decoded) {
    List<Object?> list => list,
    Map<Object?, Object?> map when map['devices'] is List => map['devices'],
    _ => const <Object?>[],
  };
  if (devicesObject is! List) {
    return const [];
  }

  final targets = <PlatformTarget>[];
  for (final device in devicesObject) {
    if (device is! Map) {
      continue;
    }
    if (_isTruthy(device['simulator']) || _isTruthy(device['ignored'])) {
      continue;
    }
    if (_isFalsey(device['available'])) {
      continue;
    }
    final platformName = _stringValue(device['platform']);
    final platform = platformName?.toLowerCase();
    if (platform != null &&
        (platform.contains('simulator') || !_isIosDevicePlatform(platform))) {
      continue;
    }

    final id =
        _stringValue(device['identifier']) ??
        _stringValue(device['udid']) ??
        '';
    if (id.isEmpty) {
      continue;
    }
    final name =
        _stringValue(device['name']) ?? _stringValue(device['modelName']) ?? id;
    final osVersion =
        _stringValue(device['operatingSystemVersion']) ??
        _stringValue(device['osVersion']);
    final model = _stringValue(device['modelName']);
    final transport =
        _stringValue(device['interface']) ??
        _stringValue(device['transport']) ??
        _stringValue(device['connectionType']);
    targets.add(
      PlatformTarget(
        platform: FluohPlatform.ios,
        id: id,
        name: name,
        kind: 'device',
        details: {
          'source': 'xcdevice',
          'platform': ?platformName,
          'osVersion': ?osVersion,
          'model': ?model,
          'transport': ?transport,
        },
      ),
    );
  }
  targets.sort((left, right) => left.name.compareTo(right.name));
  return targets;
}

/// Parses `xcrun xctrace list devices` text output.
List<PlatformTarget> parseXctraceDevices(String output) {
  final targets = <PlatformTarget>[];
  var inDevicesSection = false;
  for (final rawLine in const LineSplitter().convert(output)) {
    final line = rawLine.trim();
    if (line.isEmpty) {
      continue;
    }
    if (line.startsWith('==')) {
      inDevicesSection = line == '== Devices ==';
      continue;
    }
    if (!inDevicesSection) {
      continue;
    }
    final match = RegExp(r'^(.+?) \(([^()]+)\) \(([^()]+)\)$').firstMatch(line);
    if (match == null) {
      continue;
    }
    final version = match.group(2) ?? '';
    if (!RegExp(r'^\d+(?:\.\d+)*$').hasMatch(version)) {
      continue;
    }
    final id = match.group(3) ?? '';
    if (id.isEmpty) {
      continue;
    }
    targets.add(
      PlatformTarget(
        platform: FluohPlatform.ios,
        id: id,
        name: match.group(1) ?? id,
        kind: 'device',
        details: {'source': 'xctrace', 'osVersion': version},
      ),
    );
  }
  targets.sort((left, right) => left.name.compareTo(right.name));
  return targets;
}

void _addUniqueTargets(
  List<PlatformTarget> targets,
  Iterable<PlatformTarget> additions,
) {
  final ids = {
    for (final target in targets) '${target.platform.cliName}:${target.id}',
  };
  for (final target in additions) {
    final duplicateIndex = targets.indexWhere(
      (existing) => _samePhysicalIosDevice(existing, target),
    );
    if (duplicateIndex != -1) {
      final duplicate = targets[duplicateIndex];
      final merged = _mergePhysicalIosDevice(duplicate, target);
      if (merged.id != duplicate.id) {
        ids.remove('${duplicate.platform.cliName}:${duplicate.id}');
        ids.add('${merged.platform.cliName}:${merged.id}');
      }
      targets[duplicateIndex] = merged;
      continue;
    }
    if (ids.add('${target.platform.cliName}:${target.id}')) {
      targets.add(target);
    }
  }
}

bool _samePhysicalIosDevice(PlatformTarget left, PlatformTarget right) {
  if (left.platform != FluohPlatform.ios ||
      right.platform != FluohPlatform.ios ||
      left.kind != 'device' ||
      right.kind != 'device') {
    return false;
  }
  if (left.name.trim().toLowerCase() != right.name.trim().toLowerCase()) {
    return false;
  }
  final leftVersion = left.details['osVersion']?.toString();
  final rightVersion = right.details['osVersion']?.toString();
  if (_nonEmpty(leftVersion) &&
      _nonEmpty(rightVersion) &&
      _comparableOsVersion(leftVersion!) !=
          _comparableOsVersion(rightVersion!)) {
    return false;
  }
  final leftModel = left.details['model']?.toString();
  final rightModel = right.details['model']?.toString();
  if (_nonEmpty(leftModel) &&
      _nonEmpty(rightModel) &&
      leftModel != rightModel) {
    return false;
  }
  return true;
}

bool _hasConnectionDetails(PlatformTarget target) {
  return target.details.containsKey('transport') ||
      target.details.containsKey('pairingState') ||
      target.details.containsKey('tunnelState');
}

PlatformTarget _mergePhysicalIosDevice(
  PlatformTarget existing,
  PlatformTarget incoming,
) {
  final base =
      _hasConnectionDetails(incoming) && !_hasConnectionDetails(existing)
      ? incoming
      : existing;
  final secondary = identical(base, incoming) ? existing : incoming;
  final details = <String, Object?>{...secondary.details, ...base.details};
  final osVersion = _richerOsVersion(
    existing.details['osVersion']?.toString(),
    incoming.details['osVersion']?.toString(),
  );
  if (osVersion != null) {
    details['osVersion'] = osVersion;
  }
  return PlatformTarget(
    platform: base.platform,
    id: base.id,
    name: base.name,
    kind: base.kind,
    state: base.state ?? secondary.state,
    details: details,
  );
}

String? _richerOsVersion(String? left, String? right) {
  if (!_nonEmpty(left)) {
    return _nonEmpty(right) ? right!.trim() : null;
  }
  if (!_nonEmpty(right)) {
    return left!.trim();
  }
  final leftValue = left!.trim();
  final rightValue = right!.trim();
  final leftHasBuild = RegExp(
    r'\([^)]*\)|\s+[A-Za-z0-9]{4,}$',
  ).hasMatch(leftValue);
  final rightHasBuild = RegExp(
    r'\([^)]*\)|\s+[A-Za-z0-9]{4,}$',
  ).hasMatch(rightValue);
  if (rightHasBuild && !leftHasBuild) {
    return rightValue;
  }
  return leftValue;
}

String _comparableOsVersion(String value) {
  return value
      .replaceFirst(RegExp(r'\s*\([^)]*\)\s*$'), '')
      .trim()
      .toLowerCase();
}

Future<String?> _latestAndroidPlatform(io.Directory? sdkRoot) async {
  if (sdkRoot == null) {
    return null;
  }
  final platforms = io.Directory('${sdkRoot.path}/platforms');
  if (!await platforms.exists()) {
    return null;
  }
  final versions = <String>[];
  await for (final entity in platforms.list(followLinks: false)) {
    if (entity is! io.Directory) {
      continue;
    }
    final name = _pathBaseName(entity.path);
    if (RegExp(r'^android-\d+$').hasMatch(name)) {
      versions.add(name);
    }
  }
  versions.sort(_compareAndroidPackageVersions);
  return versions.lastOrNull;
}

Future<String?> _latestBuildToolsVersion(io.Directory? sdkRoot) async {
  if (sdkRoot == null) {
    return null;
  }
  final buildTools = io.Directory('${sdkRoot.path}/build-tools');
  if (!await buildTools.exists()) {
    return null;
  }
  final versions = <String>[];
  await for (final entity in buildTools.list(followLinks: false)) {
    if (entity is! io.Directory) {
      continue;
    }
    final name = _pathBaseName(entity.path);
    if (RegExp(r'^\d+(?:\.\d+)*(?:[-_A-Za-z0-9.]*)?$').hasMatch(name)) {
      versions.add(name);
    }
  }
  versions.sort(_compareAndroidPackageVersions);
  return versions.lastOrNull;
}

Future<bool?> _androidLicensesAccepted(io.Directory? sdkRoot) async {
  if (sdkRoot == null) {
    return null;
  }
  final licenses = io.Directory('${sdkRoot.path}/licenses');
  if (!await licenses.exists()) {
    return false;
  }
  await for (final entity in licenses.list(followLinks: false)) {
    if (entity is io.File) {
      final content = await entity.readAsString().catchError((_) => '');
      if (content.trim().isNotEmpty) {
        return true;
      }
    }
  }
  return false;
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
  String? version,
  Map<String, Object?> details = const {},
}) {
  return PlatformToolCheck(
    id: id,
    label: label,
    ok: executable != null,
    message: executable == null ? missingMessage : '$label was found',
    path: executable?.path,
    version: version,
    details: details,
  );
}

PlatformToolCheck _fileCheck({
  required String id,
  required String label,
  required io.File file,
  required String missingMessage,
  String? version,
}) {
  final exists = file.existsSync();
  return PlatformToolCheck(
    id: id,
    label: label,
    ok: exists,
    message: exists ? '$label was found' : missingMessage,
    path: file.path,
    version: version,
  );
}

Future<String?> _toolVersion(
  io.File? executable,
  List<String> arguments, {
  required Map<String, String> environment,
  String? Function(String output)? parser,
  Duration timeout = const Duration(seconds: 3),
}) async {
  if (executable == null) {
    return null;
  }
  return _commandVersion(
    executable.path,
    arguments,
    environment: environment,
    parser: parser,
    timeout: timeout,
  );
}

Future<String?> _commandVersion(
  String executable,
  List<String> arguments, {
  required Map<String, String> environment,
  String? Function(String output)? parser,
  Duration timeout = const Duration(seconds: 3),
}) async {
  final result = await _runTool(
    executable,
    arguments,
    environment: environment,
    timeout: timeout,
  );
  if (result.exitCode != 0) {
    return null;
  }
  final output = [result.stdout, result.stderr].join('\n');
  return parser?.call(output) ?? _firstNonEmptyLine(output);
}

String? _adbVersion(String output) {
  final match = RegExp(
    r'Android Debug Bridge version\s+([^\s]+)',
  ).firstMatch(output);
  return match?.group(1) ?? _firstNonEmptyLine(output);
}

String? _androidEmulatorVersion(String output) {
  final match = RegExp(
    r'Android emulator version\s+([^\s]+)',
  ).firstMatch(output);
  return match?.group(1) ?? _firstNonEmptyLine(output);
}

Future<String?> _openHarmonySdkVersion(io.Directory sdk) async {
  for (final path in [
    '${sdk.path}/oh-uni-package.json',
    '${sdk.path}/ets/oh-uni-package.json',
  ]) {
    final file = io.File(path);
    if (!await file.exists()) {
      continue;
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, Object?>) {
        final version = decoded['version']?.toString().trim();
        if (_nonEmpty(version)) {
          return version;
        }
      }
    } on Object {
      return null;
    }
  }
  return null;
}

String? _ohosHdcVersion(String output) {
  final value = _firstNonEmptyLine(output);
  if (value == null) {
    return null;
  }
  final match = RegExp(r'^Ver:\s*(.+)$').firstMatch(value.trim());
  return match?.group(1)?.trim() ?? value;
}

String? _ohosEmulatorVersion(String output) {
  final value = _firstNonEmptyLine(output);
  if (value == null) {
    return null;
  }
  return normalizeOhosEmulatorVersion(value);
}

String? _javaVersion(String output) {
  final runtime = RegExp(
    r'^(.+Runtime Environment .+)$',
    multiLine: true,
  ).firstMatch(output);
  if (runtime != null) {
    return runtime.group(1)?.trim();
  }
  final match = RegExp(r'version "([^"]+)"').firstMatch(output);
  return match?.group(1) ?? _firstNonEmptyLine(output);
}

Future<String?> _javaReleaseFileVersion(io.File? java) async {
  if (java == null) {
    return null;
  }
  final release = io.File('${java.parent.parent.path}/release');
  if (!await release.exists()) {
    return null;
  }
  final content = await release.readAsString().catchError((_) => '');
  final runtime = RegExp(
    r'^JAVA_RUNTIME_VERSION="([^"]+)"$',
    multiLine: true,
  ).firstMatch(content)?.group(1)?.trim();
  if (_nonEmpty(runtime)) {
    return runtime;
  }
  return RegExp(
    r'^JAVA_VERSION="([^"]+)"$',
    multiLine: true,
  ).firstMatch(content)?.group(1)?.trim();
}

String? _xcrunVersion(String output) {
  final match = RegExp(
    r'xcrun version\s+([^\s.]+(?:\.[^\s.]+)*)',
  ).firstMatch(output);
  return match?.group(1) ?? _firstNonEmptyLine(output);
}

String? _xcodeVersion(String output) {
  final match = RegExp(r'^Xcode\s+(.+)$', multiLine: true).firstMatch(output);
  return match?.group(1)?.trim() ?? _firstNonEmptyLine(output);
}

String? _xcodeBuildVersion(String output) {
  final match = RegExp(
    r'^Build version\s+(.+)$',
    multiLine: true,
  ).firstMatch(output);
  return match?.group(1)?.trim();
}

String? _firstNonEmptyLine(String output) {
  for (final line in const LineSplitter().convert(output)) {
    final trimmed = line.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return null;
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
    return '$label $query was not found. Available: ${_targetNames(targets)}';
  }
  if (targets.isEmpty) {
    return 'No $label is available';
  }
  return 'Multiple ${label}s are available; pass --emulator with one of: ${_targetNames(targets)}';
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

String _pathBaseName(String path) {
  final normalized = path.replaceAll(r'\', '/');
  final trimmed = normalized.endsWith('/')
      ? normalized.substring(0, normalized.length - 1)
      : normalized;
  final slash = trimmed.lastIndexOf('/');
  return slash == -1 ? trimmed : trimmed.substring(slash + 1);
}

int _compareAndroidPackageVersions(String left, String right) {
  final leftNumbers = _versionNumbers(left);
  final rightNumbers = _versionNumbers(right);
  final maxLength = leftNumbers.length > rightNumbers.length
      ? leftNumbers.length
      : rightNumbers.length;
  for (var index = 0; index < maxLength; index += 1) {
    final leftValue = index < leftNumbers.length ? leftNumbers[index] : 0;
    final rightValue = index < rightNumbers.length ? rightNumbers[index] : 0;
    if (leftValue != rightValue) {
      return leftValue.compareTo(rightValue);
    }
  }
  return left.compareTo(right);
}

List<int> _versionNumbers(String value) {
  return [
    for (final match in RegExp(r'\d+').allMatches(value))
      int.tryParse(match.group(0) ?? '') ?? 0,
  ];
}

bool _isAndroidStudioBundledJdk(String path) {
  final normalized = path.replaceAll(r'\', '/').toLowerCase();
  return normalized.contains('android studio.app/contents/jbr/') ||
      normalized.contains('android studio.app/contents/jre/');
}

List<String> _androidStudioBundledJavaCandidates(Map<String, String> env) {
  final configured = env['FLUOH_ANDROID_STUDIO'];
  final roots = _nonEmpty(configured)
      ? <String>[configured!.trim()]
      : <String>[
          if (io.Platform.isMacOS) ...[
            '/Applications/Android Studio.app',
            '/Applications/Android Studio Preview.app',
            if (_nonEmpty(env['HOME']))
              '${env['HOME']!.trim()}/Applications/Android Studio.app',
            if (_nonEmpty(env['HOME']))
              '${env['HOME']!.trim()}/Applications/Android Studio Preview.app',
          ],
        ];
  return [
    for (final root in roots) ...[
      '$root/Contents/jbr/Contents/Home/bin/java',
      '$root/Contents/jre/Contents/Home/bin/java',
    ],
  ];
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

Map<String, Object?> _optionalDetail(String key, Object? value) {
  return value == null ? const {} : {key: value};
}

Map<Object?, Object?> _objectMap(Object? value) {
  return value is Map ? value : const {};
}

Object? _decodeJsonOutput(String output) {
  try {
    return jsonDecode(output);
  } on FormatException {
    final start = output.indexOf('[');
    final end = output.lastIndexOf(']');
    if (start == -1 || end <= start) {
      rethrow;
    }
    return jsonDecode(output.substring(start, end + 1));
  }
}

bool _isIosDevicePlatform(String platform) {
  return platform == 'ios' ||
      platform.contains('iphoneos') ||
      platform.contains('ipados');
}

/// Normalizes Apple OS versions to the compact form used by Flutter tooling.
///
/// macOS and Xcode tools can report values such as
/// `Version 26.5 (Build 25F71)` or `26.5 (23F77)`. User-facing output keeps the
/// version and build number, but drops the extra labels and parentheses.
String normalizeAppleOperatingSystemVersion(String value) {
  return value
      .trim()
      .replaceFirst(RegExp(r'^Version\s+', caseSensitive: false), '')
      .replaceAllMapped(
        RegExp(r'\s*\((?:Build\s+)?([^)]+)\)', caseSensitive: false),
        (match) => ' ${match.group(1)}',
      );
}

/// Returns the Flutter-style target name used in human output and JSON.
String platformTargetDisplayName(PlatformTarget target, {String? listingKind}) {
  if (listingKind == 'emulator' && target.kind == 'emulator') {
    return platformTargetEmulatorName(target);
  }
  final connection = platformTargetConnection(target);
  final qualifiers = [?connection, platformTargetCategory(target)];
  return '${target.name} ${qualifiers.map((item) => '($item)').join(' ')}';
}

/// Returns the platform column value for a target row.
String platformTargetDisplayPlatform(PlatformTarget target) {
  if (target.platform == FluohPlatform.macos) {
    return target.details['runtime']?.toString() ?? target.platform.cliName;
  }
  return target.platform.cliName;
}

/// Returns the broad device category shown as a target name qualifier.
String platformTargetCategory(PlatformTarget target) {
  return switch (target.platform) {
    FluohPlatform.android ||
    FluohPlatform.ios ||
    FluohPlatform.ohos => 'mobile',
    FluohPlatform.macos => 'desktop',
  };
}

/// Returns a connection qualifier such as `wireless`, when one is relevant.
String? platformTargetConnection(PlatformTarget target) {
  if (target.platform != FluohPlatform.ios || target.kind != 'device') {
    return null;
  }
  return isWirelessTransport(target.details['transport']) ? 'wireless' : null;
}

/// Returns the final details column used for device rows.
String platformTargetSummary(PlatformTarget target) {
  return switch (target.platform) {
    FluohPlatform.android => target.state ?? '',
    FluohPlatform.ios => _iosTargetSummary(target),
    FluohPlatform.macos => _macosTargetSummary(target),
    FluohPlatform.ohos =>
      target.details['details']?.toString() ?? target.state ?? '',
  };
}

/// Returns the display name used by `fluoh emulators`.
String platformTargetEmulatorName(PlatformTarget target) {
  if (target.platform == FluohPlatform.android) {
    return target.name.replaceAll('_', ' ');
  }
  return target.name;
}

/// Returns the manufacturer column for emulator rows, when known.
String? platformTargetManufacturer(PlatformTarget target) {
  if (target.kind != 'emulator') {
    return null;
  }
  return switch (target.platform) {
    FluohPlatform.ios => 'Apple',
    FluohPlatform.ohos => 'Huawei',
    FluohPlatform.android => 'Google',
    FluohPlatform.macos => null,
  };
}

String _iosTargetSummary(PlatformTarget target) {
  if (target.kind == 'emulator') {
    final runtime = target.details['runtime']?.toString();
    return runtime == null || runtime.isEmpty
        ? 'simulator'
        : '$runtime (simulator)';
  }
  final osVersion = target.details['osVersion']?.toString();
  return osVersion == null || osVersion.isEmpty
      ? 'iOS'
      : 'iOS ${normalizeAppleOperatingSystemVersion(osVersion)}';
}

String _macosTargetSummary(PlatformTarget target) {
  final osVersion = target.details['osVersion']?.toString();
  final runtime = target.details['runtime']?.toString();
  final version = osVersion == null || osVersion.isEmpty
      ? 'macOS'
      : 'macOS ${normalizeAppleOperatingSystemVersion(osVersion)}';
  return runtime == null || runtime.isEmpty ? version : '$version $runtime';
}

/// Whether a raw Apple device transport value represents a wireless target.
bool isWirelessTransport(Object? value) {
  final transport = _stringValue(value)?.toLowerCase();
  if (transport == null || transport.isEmpty) {
    return false;
  }
  return transport == 'network' ||
      transport == 'wifi' ||
      transport == 'wi-fi' ||
      transport == 'wireless' ||
      transport.contains('network') ||
      transport.contains('wifi') ||
      transport.contains('wireless');
}

/// Extracts the compact OpenHarmony Emulator version from tool output.
String? normalizeOhosEmulatorVersion(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  for (final pattern in [
    RegExp(r'Emulator\s*:\s*(.+)$', caseSensitive: false),
    RegExp(r'Emulator\s+version\s*:?\s*(.+)$', caseSensitive: false),
    RegExp(r'Version\s*:?\s*(.+)$', caseSensitive: false),
  ]) {
    final match = pattern.firstMatch(trimmed);
    final parsed = match?.group(1)?.trim();
    if (parsed != null && parsed.isNotEmpty) {
      return parsed;
    }
  }
  final version = RegExp(
    r'\d+(?:\.\d+){1,}(?:[-+][0-9A-Za-z.-]+)?',
  ).firstMatch(trimmed)?.group(0);
  return version ?? trimmed;
}

bool _isTruthy(Object? value) {
  if (value is bool) {
    return value;
  }
  final text = _stringValue(value)?.toLowerCase();
  return text == 'true' || text == 'yes' || text == '1';
}

bool _isFalsey(Object? value) {
  if (value is bool) {
    return !value;
  }
  final text = _stringValue(value)?.toLowerCase();
  return text == 'false' || text == 'no' || text == '0';
}

String? _stringValue(Object? value) {
  if (value == null) {
    return null;
  }
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

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
