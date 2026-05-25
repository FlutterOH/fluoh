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
