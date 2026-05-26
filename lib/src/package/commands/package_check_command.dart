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
        allowed: const ['hap'],
        help: 'Build each Flutter example target after analysis and tests.',
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
        help: 'Install and launch the built OHOS example HAP on a device.',
      )
      ..addOption(
        'device',
        valueHelp: 'id',
        help: 'OHOS hdc target id to use with --run-example.',
      )
      ..addFlag(
        'start-emulator',
        negatable: false,
        help: 'Start a local DevEco emulator when no OHOS target is connected.',
      )
      ..addOption(
        'emulator',
        valueHelp: 'name',
        help: 'Local DevEco emulator name to start with --start-emulator.',
      )
      ..addOption(
        'device-timeout',
        valueHelp: 'seconds',
        defaultsTo: '90',
        help: 'Seconds to wait for an OHOS target after starting an emulator.',
      )
      ..addOption(
        'log-duration',
        valueHelp: 'seconds',
        defaultsTo: '8',
        help: 'Seconds of OHOS hilog to collect after launching the example.',
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
    if (argResults!.flag('all') &&
        (argResults!.option('package')?.trim().isNotEmpty ?? false)) {
      usageException('Use only one of --all or --package.');
    }
    if (argResults!.flag('auto-sign') &&
        argResults!.option('build-example') != 'hap') {
      usageException('Use --auto-sign together with --build-example hap.');
    }
    if (argResults!.flag('run-example') &&
        argResults!.option('build-example') != 'hap') {
      usageException('Use --run-example together with --build-example hap.');
    }
    if ((argResults!.option('device')?.trim().isNotEmpty ?? false) &&
        !argResults!.flag('run-example')) {
      usageException('Use --device together with --run-example.');
    }
    if (argResults!.flag('start-emulator') &&
        !argResults!.flag('run-example')) {
      usageException('Use --start-emulator together with --run-example.');
    }
    if ((argResults!.option('emulator')?.trim().isNotEmpty ?? false) &&
        !argResults!.flag('start-emulator')) {
      usageException('Use --emulator together with --start-emulator.');
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

    for (final package in packages) {
      output.step('Checking ${package.name}.');
      final result = await checkPackage(
        environment: environment,
        manifest: manifest,
        package: package,
        stdout: stdout,
        stderr: stderr,
        output: output,
        usage: usage,
        buildExampleTarget: argResults!.option('build-example'),
        buildExampleDebug: argResults!.flag('debug'),
        autoSignExample: argResults!.flag('auto-sign'),
        runExample: argResults!.flag('run-example'),
        deviceId: argResults!.option('device')?.trim(),
        startEmulator: argResults!.flag('start-emulator'),
        emulatorName: argResults!.option('emulator')?.trim(),
        deviceTimeout: Duration(seconds: deviceTimeoutSeconds),
        logDuration: Duration(seconds: logDurationSeconds),
      );
      results.add(result);
      if (!result.passed) {
        _printJsonIfRequested(json, results);
        return result.exitCode;
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
