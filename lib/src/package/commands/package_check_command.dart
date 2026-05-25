import 'package:args/command_runner.dart';

import '../../cli/argument_validation.dart';
import '../../cli/fluoh_command_runner.dart';
import '../../cli/terminal_output.dart';
import '../../context/fluoh_environment.dart';
import '../manifest/package_manifest.dart';
import '../package_checker.dart';

class PackageCheckCommand extends Command<int> {
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

    for (final package in packages) {
      _output.step('Checking ${package.name}.');
      final result = await checkPackage(
        environment: environment,
        manifest: manifest,
        package: package,
        stdout: _stdout,
        stderr: _stderr,
        output: _output,
        usage: usage,
      );
      if (!result.passed) {
        return result.exitCode;
      }
    }

    _output.success(
      packages.length == 1
          ? 'Package check passed for ${packages.single.name}.'
          : 'Package check passed for ${packages.length} packages.',
    );
    return 0;
  }
}
