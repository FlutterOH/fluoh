/// Platform-specific workflow command and diagnostic routing policy.
///
/// Keep build/run command shapes and repair routing here so project, package,
/// plan, and generated guidance do not each encode their own platform table.
abstract class PlatformWorkflowPolicy {
  /// Creates a platform workflow policy.
  const PlatformWorkflowPolicy();

  /// Platform CLI name, such as `android` or `web`.
  String get platform;

  /// User-facing platform label.
  String get label;

  /// Flutter build target for this platform.
  String get buildTarget;

  /// Whether `fluoh run` targets the local host/browser instead of a device.
  bool get isDesktopRunPlatform => false;

  /// Whether `--session-file` is valid for this platform run.
  bool get supportsSessionFile => true;

  /// Whether this platform accepts `--auto-sign`.
  bool get supportsAutoSign => false;

  /// Whether project runs use the OHOS-specific HAP install/launch workflow.
  bool get usesOhosProjectRunner => false;

  /// Whether builds need OHOS resource layout stabilization.
  bool get stabilizesOhosResourceLayout => false;

  /// Whether Flutter builds should pass `--no-codesign`.
  bool get buildWithoutCodesign => false;

  /// Whether package example builds should target an iOS simulator artifact.
  bool buildExampleForSimulator({
    required String? deviceId,
    required bool startEmulator,
  }) {
    return false;
  }

  /// Diagnostic code for a Flutter integration-test failure.
  String get integrationTestDiagnosticCode =>
      '$platform.integration_test_failed';

  /// Extra evidence entries recorded by automation plans for this platform.
  List<String> get automationEvidenceItems => const [];

  /// Extra platform-specific metadata recorded by automation plans.
  Map<String, Object?> get automationMetadata => const {};

  /// `fluoh doctor --platform <platform>` command.
  String doctorCommand({bool project = false, bool strict = false}) {
    return [
      'fluoh doctor --platform $platform',
      if (project) '--project',
      '--json',
      if (strict) '--strict',
    ].join(' ');
  }

  /// `fluoh devices --platform <platform>` command.
  String devicesCommand({bool json = false}) {
    return ['fluoh devices --platform $platform', if (json) '--json'].join(' ');
  }

  /// `fluoh emulators --platform <platform>` command.
  String emulatorsCommand({bool json = false}) {
    return [
      'fluoh emulators --platform $platform',
      if (json) '--json',
    ].join(' ');
  }

  /// `fluoh run <platform>` command.
  String runCommand({
    String? packageName,
    String? deviceId,
    bool startEmulator = false,
    String? emulatorName,
    String? sessionFile,
    String? traceDir,
  }) {
    return [
      'fluoh run $platform',
      if (packageName != null) '--package $packageName',
      if (deviceId != null) '--device-id $deviceId',
      if (startEmulator && emulatorName == null && !isDesktopRunPlatform)
        '--auto-emulator',
      if (emulatorName != null) '--emulator $emulatorName',
      if (sessionFile != null) '--session-file $sessionFile',
      '--json',
      if (traceDir != null) '--trace-dir $traceDir',
    ].join(' ');
  }

  /// `fluoh build <platform>` command.
  String buildCommand({
    String? packageName,
    bool debug = true,
    bool autoSign = false,
    String? traceDir,
  }) {
    return [
      'fluoh build $platform',
      if (packageName != null) '--package $packageName',
      if (!debug) '--no-debug',
      if (autoSign && supportsAutoSign) '--auto-sign',
      '--json',
      if (traceDir != null) '--trace-dir $traceDir',
    ].join(' ');
  }

  /// Suggested regression command for this platform.
  String regressionCommand({String? packageName, required String traceDir}) {
    return runCommand(packageName: packageName, traceDir: traceDir);
  }

  /// Diagnostic code for a project build or run step.
  String diagnosticCode({required String kind}) {
    if (kind == 'run') {
      return '$platform.run_failed';
    }
    return '$platform.build_failed';
  }

  /// Diagnostic message for a project build or run step.
  String diagnosticMessage({required String kind}) {
    final action = kind == 'run' ? 'run' : 'build';
    return '$label $action failed.';
  }

  /// Repair command for a package workflow diagnostic.
  String? packageRepairCommand(String code, String packageName) {
    final suffix = _diagnosticSuffix(code);
    if (suffix == null) {
      return null;
    }
    if (_runRepairDiagnostics.contains(suffix) ||
        _emulatorRetryDiagnostics.contains(suffix) ||
        suffix == 'device_missing') {
      return runCommand(packageName: packageName);
    }
    if (_doctorRepairDiagnostics.contains(suffix)) {
      return doctorCommand();
    }
    if (_devicesRepairDiagnostics.contains(suffix)) {
      return devicesCommand();
    }
    return null;
  }

  /// Repair command for a project workflow diagnostic.
  String? projectRepairCommand(
    String code, {
    required String currentCommand,
    required String autoEmulatorCommand,
  }) {
    final suffix = _diagnosticSuffix(code);
    if (suffix == null) {
      return null;
    }
    if (_runRepairDiagnostics.contains(suffix)) {
      return currentCommand;
    }
    if (_doctorRepairDiagnostics.contains(suffix)) {
      return doctorCommand();
    }
    if (_devicesRepairDiagnostics.contains(suffix)) {
      return devicesCommand();
    }
    if (_mobileAutoEmulatorDiagnostics.contains(suffix)) {
      return isDesktopRunPlatform ? currentCommand : autoEmulatorCommand;
    }
    if (_emulatorRetryDiagnostics.contains(suffix)) {
      return currentCommand;
    }
    return null;
  }

  String? _diagnosticSuffix(String code) {
    final prefix = '$platform.';
    return code.startsWith(prefix) ? code.substring(prefix.length) : null;
  }
}

class _OhosWorkflowPolicy extends PlatformWorkflowPolicy {
  const _OhosWorkflowPolicy();

  @override
  String get platform => 'ohos';

  @override
  String get label => 'OHOS';

  @override
  String get buildTarget => 'hap';

  @override
  bool get supportsSessionFile => false;

  @override
  bool get supportsAutoSign => true;

  @override
  bool get usesOhosProjectRunner => true;

  @override
  bool get stabilizesOhosResourceLayout => true;

  @override
  String regressionCommand({String? packageName, required String traceDir}) {
    return runCommand(
      packageName: packageName,
      startEmulator: true,
      traceDir: traceDir,
    );
  }

  @override
  String diagnosticCode({required String kind}) {
    return kind == 'run' ? 'ohos.run_failed' : 'ohos.hap_build_failed';
  }

  @override
  String diagnosticMessage({required String kind}) {
    return kind == 'run' ? 'OHOS run failed.' : 'OHOS HAP build failed.';
  }

  @override
  String get integrationTestDiagnosticCode => 'integration_test.failed';

  @override
  List<String> get automationEvidenceItems => const ['OHOS hilog runtime scan'];

  @override
  Map<String, Object?> get automationMetadata => const {
    'ohos': {
      'sessionFile': null,
      'debugEvidence':
          'installable HAP, launch ability metadata, target id, hilog file, and runtime findings',
    },
  };

  @override
  String? packageRepairCommand(String code, String packageName) {
    final suffix = _diagnosticSuffix(code);
    if (suffix == null) {
      return null;
    }
    if (const {
      'hap_build_failed',
      'signing_profile_failed',
      'build_profile_patch_failed',
      'direct_sign_failed',
      'no_installable_hap',
      'install_failed',
      'launch_failed',
      'runtime_crash',
      'device_missing',
    }.contains(suffix)) {
      return runCommand(packageName: packageName, startEmulator: true);
    }
    if (const {
      'toolchain_missing',
      'auto_sign_failed',
      'hdc_connection_failed',
      'hdc_targets_failed',
      'hdc_target_unavailable',
      'emulator_start_failed',
      'device_not_found',
      'device_ambiguous',
      'launch_info_missing',
      'ohos_project_missing',
    }.contains(suffix)) {
      return doctorCommand();
    }
    return null;
  }

  @override
  String? projectRepairCommand(
    String code, {
    required String currentCommand,
    required String autoEmulatorCommand,
  }) {
    final suffix = _diagnosticSuffix(code);
    if (suffix == null) {
      return null;
    }
    if (const {
      'hap_build_failed',
      'launch_timeout',
      'run_failed',
      'runtime_crash',
    }.contains(suffix)) {
      return currentCommand;
    }
    if (const {
      'devices_failed',
      'hdc_connection_failed',
      'hdc_targets_failed',
      'emulators_failed',
      'emulator_missing',
      'emulator_start_failed',
    }.contains(suffix)) {
      return doctorCommand();
    }
    if (const {
      'device_not_found',
      'device_ambiguous',
      'hdc_target_unavailable',
    }.contains(suffix)) {
      return devicesCommand();
    }
    if (suffix == 'device_missing') {
      return autoEmulatorCommand;
    }
    if (_emulatorRetryDiagnostics.contains(suffix)) {
      return currentCommand;
    }
    return null;
  }
}

class _AndroidWorkflowPolicy extends PlatformWorkflowPolicy {
  const _AndroidWorkflowPolicy();

  @override
  String get platform => 'android';

  @override
  String get label => 'Android';

  @override
  String get buildTarget => 'apk';

  @override
  String regressionCommand({String? packageName, required String traceDir}) {
    return runCommand(
      packageName: packageName,
      startEmulator: true,
      traceDir: traceDir,
    );
  }

  @override
  String diagnosticCode({required String kind}) {
    return kind == 'run' ? 'android.run_failed' : 'android.apk_build_failed';
  }

  @override
  List<String> get automationEvidenceItems => const [
    'flutterRunSession JSON',
    'Flutter VM Service URI when exposed',
    'flutter run output log',
  ];

  @override
  String? packageRepairCommand(String code, String packageName) {
    final suffix = _diagnosticSuffix(code);
    if (suffix == null) {
      return null;
    }
    if (_runRepairDiagnostics.contains(suffix) ||
        _emulatorRetryDiagnostics.contains(suffix) ||
        suffix == 'device_missing') {
      return runCommand(packageName: packageName, startEmulator: true);
    }
    if (_doctorRepairDiagnostics.contains(suffix)) {
      return doctorCommand();
    }
    if (_devicesRepairDiagnostics.contains(suffix)) {
      return devicesCommand();
    }
    return null;
  }
}

class _IosWorkflowPolicy extends PlatformWorkflowPolicy {
  const _IosWorkflowPolicy();

  @override
  String get platform => 'ios';

  @override
  String get label => 'iOS';

  @override
  String get buildTarget => 'ios';

  @override
  bool get buildWithoutCodesign => true;

  @override
  bool buildExampleForSimulator({
    required String? deviceId,
    required bool startEmulator,
  }) {
    return deviceId == null && startEmulator;
  }

  @override
  List<String> get automationEvidenceItems => const [
    'flutterRunSession JSON',
    'Flutter VM Service URI when exposed',
    'flutter run output log',
  ];

  @override
  String regressionCommand({String? packageName, required String traceDir}) {
    return runCommand(
      packageName: packageName,
      startEmulator: true,
      traceDir: traceDir,
    );
  }

  @override
  String? packageRepairCommand(String code, String packageName) {
    final suffix = _diagnosticSuffix(code);
    if (suffix == null) {
      return null;
    }
    if (_runRepairDiagnostics.contains(suffix) ||
        _emulatorRetryDiagnostics.contains(suffix) ||
        suffix == 'device_missing') {
      return runCommand(packageName: packageName, startEmulator: true);
    }
    if (_doctorRepairDiagnostics.contains(suffix)) {
      return doctorCommand();
    }
    if (_devicesRepairDiagnostics.contains(suffix)) {
      return devicesCommand();
    }
    return null;
  }
}

class _MacosWorkflowPolicy extends _DesktopWorkflowPolicy {
  const _MacosWorkflowPolicy()
    : super(platformName: 'macos', platformLabel: 'macOS');
}

class _LinuxWorkflowPolicy extends _DesktopWorkflowPolicy {
  const _LinuxWorkflowPolicy()
    : super(platformName: 'linux', platformLabel: 'Linux');

  @override
  String regressionCommand({String? packageName, required String traceDir}) {
    return buildCommand(packageName: packageName, traceDir: traceDir);
  }
}

class _WebWorkflowPolicy extends _DesktopWorkflowPolicy {
  const _WebWorkflowPolicy() : super(platformName: 'web', platformLabel: 'Web');

  @override
  String? packageRepairCommand(String code, String packageName) {
    final suffix = _diagnosticSuffix(code);
    if (suffix == null) {
      return null;
    }
    if (_runRepairDiagnostics.contains(suffix) ||
        _emulatorRetryDiagnostics.contains(suffix)) {
      return runCommand(packageName: packageName);
    }
    if (_doctorRepairDiagnostics.contains(suffix) ||
        suffix == 'device_missing') {
      return doctorCommand();
    }
    if (_devicesRepairDiagnostics.contains(suffix)) {
      return devicesCommand();
    }
    return null;
  }

  @override
  String? projectRepairCommand(
    String code, {
    required String currentCommand,
    required String autoEmulatorCommand,
  }) {
    final suffix = _diagnosticSuffix(code);
    if (suffix == null) {
      return null;
    }
    if (_doctorRepairDiagnostics.contains(suffix) ||
        suffix == 'device_missing') {
      return doctorCommand();
    }
    return super.projectRepairCommand(
      code,
      currentCommand: currentCommand,
      autoEmulatorCommand: autoEmulatorCommand,
    );
  }
}

class _WindowsWorkflowPolicy extends _DesktopWorkflowPolicy {
  const _WindowsWorkflowPolicy()
    : super(platformName: 'windows', platformLabel: 'Windows');

  @override
  String regressionCommand({String? packageName, required String traceDir}) {
    return buildCommand(packageName: packageName, traceDir: traceDir);
  }
}

abstract class _DesktopWorkflowPolicy extends PlatformWorkflowPolicy {
  const _DesktopWorkflowPolicy({
    required this.platformName,
    required this.platformLabel,
  });

  final String platformName;
  final String platformLabel;

  @override
  String get platform => platformName;

  @override
  String get label => platformLabel;

  @override
  String get buildTarget => platformName;

  @override
  bool get isDesktopRunPlatform => true;
}

/// Supported workflow platform names.
const workflowPlatformNames = [
  'ohos',
  'android',
  'ios',
  'macos',
  'linux',
  'web',
  'windows',
];

/// Returns the workflow policy for [platform].
PlatformWorkflowPolicy platformWorkflowPolicy(String platform) {
  return switch (platform) {
    'ohos' => const _OhosWorkflowPolicy(),
    'android' => const _AndroidWorkflowPolicy(),
    'ios' => const _IosWorkflowPolicy(),
    'macos' => const _MacosWorkflowPolicy(),
    'linux' => const _LinuxWorkflowPolicy(),
    'web' => const _WebWorkflowPolicy(),
    'windows' => const _WindowsWorkflowPolicy(),
    _ => throw ArgumentError.value(
      platform,
      'platform',
      'Unsupported platform.',
    ),
  };
}

/// Suggested commands for discovering runnable integration-test targets.
List<String> integrationDiscoveryRunCommands({String? packageName}) {
  return [
    platformWorkflowPolicy(
      'ohos',
    ).runCommand(packageName: packageName, startEmulator: true),
    platformWorkflowPolicy(
      'android',
    ).runCommand(packageName: packageName, startEmulator: true),
    platformWorkflowPolicy(
      'ios',
    ).runCommand(packageName: packageName, startEmulator: true),
    platformWorkflowPolicy('macos').runCommand(packageName: packageName),
    platformWorkflowPolicy('web').runCommand(packageName: packageName),
  ];
}

const _runRepairDiagnostics = {
  'build_failed',
  'apk_build_failed',
  'launch_timeout',
  'run_failed',
  'runtime_crash',
  'integration_test_failed',
};

const _doctorRepairDiagnostics = {
  'devices_failed',
  'emulators_failed',
  'emulator_missing',
  'emulator_start_failed',
};

const _devicesRepairDiagnostics = {'device_not_found', 'device_ambiguous'};

const _mobileAutoEmulatorDiagnostics = {'device_missing'};

const _emulatorRetryDiagnostics = {'emulator_not_found', 'emulator_ambiguous'};
