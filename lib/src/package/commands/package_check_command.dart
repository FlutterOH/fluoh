import 'dart:convert';

import '../../cli/argument_validation.dart';
import '../../cli/fluoh_command_runner.dart';
import '../../cli/terminal_output.dart';
import '../../context/fluoh_environment.dart';
import '../manifest/package_manifest.dart';
import '../package_checker.dart';

class PackageCheckCommand extends FluohCommand<int> {
  PackageCheckCommand({
    required this.environment,
    required OutputWriter stdout,
    required OutputWriter stderr,
    TerminalOutput? output,
  }) : _stdout = stdout,
       _stderr = stderr,
       _output = output ?? TerminalOutput(stdout: stdout, stderr: stderr) {
    argParser
      ..addOption(
        'package',
        valueHelp: 'name',
        help: 'Package to check when fluoh.yaml registers multiple packages.',
      )
      ..addFlag(
        'all',
        negatable: false,
        help: 'Check every package registered in fluoh.yaml.',
      )
      ..addOption(
        'build-example',
        valueHelp: 'target',
        allowed: const ['hap', 'apk', 'ios'],
        help:
            'Build each Flutter example target after analysis and tests. '
            'iOS builds use --no-codesign.',
      )
      ..addOption(
        'preset',
        valueHelp: 'name',
        allowed: const [
          'baseline',
          'ohos-run',
          'android-run',
          'ios-run',
          'all-run',
          'release',
        ],
        help: 'Use a named check flow instead of spelling out long options.',
        allowedHelp: const {
          'baseline': 'Run dependency resolution, analysis, and tests.',
          'ohos-run': 'Build, auto-sign, install, and launch the HAP.',
          'android-run': 'Build, launch, and smoke-test the Android example.',
          'ios-run': 'Build, launch, and smoke-test the iOS example.',
          'all-run': 'Run OHOS, Android, and iOS run presets in sequence.',
          'release': 'Run build-only OHOS, Android, and iOS release gates.',
        },
      )
      ..addFlag(
        'debug',
        negatable: false,
        help: 'Pass --debug to the example build.',
      )
      ..addFlag(
        'auto-sign',
        negatable: false,
        help: 'Generate and apply temporary OHOS debug signing for HAP builds.',
      )
      ..addFlag(
        'run-example',
        negatable: false,
        help:
            'Install and launch the built example on a target device. '
            'Runs Flutter smoke checks for APK/iOS targets.',
      )
      ..addOption(
        'device',
        valueHelp: 'id',
        help: 'Device id to use with a run check.',
      )
      ..addFlag(
        'start-emulator',
        negatable: false,
        help:
            'Start a local emulator or simulator when no target is connected.',
      )
      ..addOption(
        'emulator',
        valueHelp: 'name',
        help: 'Local emulator name or id to start for a run check.',
      )
      ..addOption(
        'device-timeout',
        valueHelp: 'seconds',
        defaultsTo: '90',
        help: 'Seconds to wait for a target after starting an emulator.',
      )
      ..addOption(
        'log-duration',
        valueHelp: 'seconds',
        defaultsTo: '8',
        help:
            'Seconds of OHOS hilog or Flutter run-smoke output to collect '
            'after launching the example.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help: 'Print the package check result as JSON.',
      );
  }

  final FluohEnvironment environment;
  final OutputWriter _stdout;
  final OutputWriter _stderr;
  final TerminalOutput _output;

  @override
  String get name => 'check';

  @override
  String get description =>
      'Run dependency resolution, analysis, and existing tests for packages.';

  @override
  Future<int> run() async {
    expectNoArguments(argResults!, usageException);
    final preset = _presetFromOption(argResults!.option('preset'));
    _validatePresetOptions(preset);
    if (argResults!.flag('all') &&
        (argResults!.option('package')?.trim().isNotEmpty ?? false)) {
      usageException('Use only one of --all or --package.');
    }
    if (_trimmedOption('device') != null &&
        _trimmedOption('emulator') != null) {
      usageException('Use only one of --device or --emulator.');
    }
    if (preset == null) {
      if (argResults!.flag('auto-sign') &&
          argResults!.option('build-example') != 'hap') {
        usageException('Use --auto-sign together with --build-example hap.');
      }
      if (argResults!.flag('run-example') &&
          argResults!.option('build-example') == null) {
        usageException(
          'Use --run-example together with --build-example hap, apk, or ios.',
        );
      }
      if ((argResults!.option('device')?.trim().isNotEmpty ?? false) &&
          !argResults!.flag('run-example')) {
        usageException('Use --device together with --run-example.');
      }
      if ((argResults!.option('device')?.trim().isNotEmpty ?? false) &&
          argResults!.flag('start-emulator')) {
        usageException(
          'Use --device for connected targets or --emulator with --start-emulator for local emulator startup.',
        );
      }
      if (argResults!.flag('start-emulator') &&
          !argResults!.flag('run-example')) {
        usageException('Use --start-emulator together with --run-example.');
      }
      if ((argResults!.option('emulator')?.trim().isNotEmpty ?? false) &&
          !argResults!.flag('start-emulator')) {
        usageException('Use --emulator together with --start-emulator.');
      }
    }
    final deviceTimeoutSeconds = int.tryParse(
      argResults!.option('device-timeout') ?? '',
    );
    if (deviceTimeoutSeconds == null || deviceTimeoutSeconds < 0) {
      usageException('Use a non-negative integer for --device-timeout.');
    }
    final logDurationSeconds = int.tryParse(
      argResults!.option('log-duration') ?? '',
    );
    if (logDurationSeconds == null || logDurationSeconds < 0) {
      usageException('Use a non-negative integer for --log-duration.');
    }

    final manifest = await readPackageManifest(environment.workingDirectory);
    final packages = argResults!.flag('all')
        ? manifest.packages
        : [manifest.packageForName(argResults!.option('package'))];
    final json = argResults!.flag('json');
    final output = json
        ? TerminalOutput(stdout: (_) {}, stderr: (_) {})
        : _output;
    final OutputWriter stdout = json ? (_) {} : _stdout;
    final OutputWriter stderr = json ? (_) {} : _stderr;
    final results = <PackageCheckResult>[];
    final invocations = _invocationsForPreset(preset);

    for (final package in packages) {
      for (final invocation in invocations) {
        output.step(invocation.stepMessage(package.name));
        final result = await checkPackage(
          environment: environment,
          manifest: manifest,
          package: package,
          stdout: stdout,
          stderr: stderr,
          output: output,
          usage: usage,
          buildExampleTarget: invocation.buildExampleTarget,
          buildExampleDebug: invocation.debug,
          autoSignExample: invocation.autoSign,
          runExample: invocation.runExample,
          deviceId: invocation.deviceId,
          startEmulator: invocation.startEmulator,
          emulatorName: invocation.emulatorName,
          deviceTimeout: Duration(seconds: deviceTimeoutSeconds),
          logDuration: Duration(seconds: logDurationSeconds),
          preset: preset?.cliName,
          phase: invocation.phase,
        );
        results.add(result);
        if (!result.passed) {
          _printJsonIfRequested(json, results);
          return result.exitCode;
        }
      }
    }

    output.success(
      packages.length == 1
          ? 'Package check passed for ${packages.single.name}.'
          : 'Package check passed for ${packages.length} packages.',
    );
    _printJsonIfRequested(json, results);
    return 0;
  }

  List<_PackageCheckInvocation> _invocationsForPreset(
    _PackageCheckPreset? preset,
  ) {
    final deviceId = _trimmedOption('device');
    final emulatorName = _trimmedOption('emulator');
    final hasDevice = deviceId != null && deviceId.isNotEmpty;
    final hasEmulator = emulatorName != null && emulatorName.isNotEmpty;
    switch (preset) {
      case null:
        return [
          _PackageCheckInvocation(
            phase: 'custom',
            buildExampleTarget: argResults!.option('build-example'),
            debug: argResults!.flag('debug'),
            autoSign: argResults!.flag('auto-sign'),
            runExample: argResults!.flag('run-example'),
            deviceId: deviceId,
            startEmulator: argResults!.flag('start-emulator'),
            emulatorName: emulatorName,
          ),
        ];
      case _PackageCheckPreset.baseline:
        return const [_PackageCheckInvocation(phase: 'baseline')];
      case _PackageCheckPreset.ohosRun:
        return [
          _PackageCheckInvocation.ohosRun(
            deviceId: deviceId,
            emulatorName: emulatorName,
            startEmulator: !hasDevice || hasEmulator,
          ),
        ];
      case _PackageCheckPreset.androidRun:
        return [
          _PackageCheckInvocation.androidRun(
            deviceId: deviceId,
            emulatorName: emulatorName,
            startEmulator: !hasDevice || hasEmulator,
          ),
        ];
      case _PackageCheckPreset.iosRun:
        return [
          _PackageCheckInvocation.iosRun(
            deviceId: deviceId,
            emulatorName: emulatorName,
            startEmulator: !hasDevice || hasEmulator,
          ),
        ];
      case _PackageCheckPreset.allRun:
        return const [
          _PackageCheckInvocation.ohosRun(startEmulator: true),
          _PackageCheckInvocation.androidRun(startEmulator: true),
          _PackageCheckInvocation.iosRun(startEmulator: true),
        ];
      case _PackageCheckPreset.release:
        return const [
          _PackageCheckInvocation.ohosBuild(),
          _PackageCheckInvocation.androidBuild(),
          _PackageCheckInvocation.iosBuild(),
        ];
    }
  }

  String? _trimmedOption(String name) {
    final value = argResults!.option(name)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  void _validatePresetOptions(_PackageCheckPreset? preset) {
    if (preset == null) {
      return;
    }
    final hasBuildExample =
        argResults!.option('build-example')?.trim().isNotEmpty ?? false;
    if (hasBuildExample ||
        argResults!.flag('debug') ||
        argResults!.flag('auto-sign') ||
        argResults!.flag('run-example') ||
        argResults!.flag('start-emulator')) {
      usageException(
        'Do not combine --preset with --build-example, --debug, --auto-sign, --run-example, or --start-emulator.',
      );
    }
    final hasDevice = _trimmedOption('device') != null;
    final hasEmulator = _trimmedOption('emulator') != null;
    if (hasDevice && hasEmulator) {
      usageException('Use only one of --device or --emulator.');
    }
    if (preset == _PackageCheckPreset.allRun && (hasDevice || hasEmulator)) {
      usageException(
        'Use --device or --emulator with a single-platform run preset, not --preset all-run.',
      );
    }
    if ((preset == _PackageCheckPreset.baseline ||
            preset == _PackageCheckPreset.release) &&
        (hasDevice || hasEmulator)) {
      usageException('Use --device or --emulator only with run presets.');
    }
  }

  void _printJsonIfRequested(bool json, List<PackageCheckResult> results) {
    if (!json) {
      return;
    }
    _stdout(
      jsonEncode({
        'passed': results.every((result) => result.passed),
        'exitCode': results
            .map((result) => result.exitCode)
            .firstWhere((exitCode) => exitCode != 0, orElse: () => 0),
        'packages': results.map((result) => result.toJson()).toList(),
      }),
    );
  }
}

enum _PackageCheckPreset {
  baseline('baseline'),
  ohosRun('ohos-run'),
  androidRun('android-run'),
  iosRun('ios-run'),
  allRun('all-run'),
  release('release');

  const _PackageCheckPreset(this.cliName);

  final String cliName;
}

_PackageCheckPreset? _presetFromOption(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }
  for (final preset in _PackageCheckPreset.values) {
    if (preset.cliName == value) {
      return preset;
    }
  }
  return null;
}

class _PackageCheckInvocation {
  const _PackageCheckInvocation({
    required this.phase,
    this.buildExampleTarget,
    this.debug = false,
    this.autoSign = false,
    this.runExample = false,
    this.deviceId,
    this.startEmulator = false,
    this.emulatorName,
  });

  const _PackageCheckInvocation.ohosBuild()
    : this(
        phase: 'ohos-build',
        buildExampleTarget: 'hap',
        debug: true,
        autoSign: true,
      );

  const _PackageCheckInvocation.androidBuild()
    : this(phase: 'android-build', buildExampleTarget: 'apk', debug: true);

  const _PackageCheckInvocation.iosBuild()
    : this(phase: 'ios-build', buildExampleTarget: 'ios', debug: true);

  const _PackageCheckInvocation.ohosRun({
    String? deviceId,
    bool startEmulator = false,
    String? emulatorName,
  }) : this(
         phase: 'ohos-run',
         buildExampleTarget: 'hap',
         debug: true,
         autoSign: true,
         runExample: true,
         deviceId: deviceId,
         startEmulator: startEmulator,
         emulatorName: emulatorName,
       );

  const _PackageCheckInvocation.androidRun({
    String? deviceId,
    bool startEmulator = false,
    String? emulatorName,
  }) : this(
         phase: 'android-run',
         buildExampleTarget: 'apk',
         debug: true,
         runExample: true,
         deviceId: deviceId,
         startEmulator: startEmulator,
         emulatorName: emulatorName,
       );

  const _PackageCheckInvocation.iosRun({
    String? deviceId,
    bool startEmulator = false,
    String? emulatorName,
  }) : this(
         phase: 'ios-run',
         buildExampleTarget: 'ios',
         debug: true,
         runExample: true,
         deviceId: deviceId,
         startEmulator: startEmulator,
         emulatorName: emulatorName,
       );

  final String phase;
  final String? buildExampleTarget;
  final bool debug;
  final bool autoSign;
  final bool runExample;
  final String? deviceId;
  final bool startEmulator;
  final String? emulatorName;

  String stepMessage(String packageName) {
    return phase == 'custom'
        ? 'Checking $packageName.'
        : 'Checking $packageName ($phase).';
  }
}
