import 'dart:io';

import 'package:args/command_runner.dart';

import '../cli/fluoh_command_runner.dart';
import '../cli/terminal_output.dart';
import '../context/fluoh_environment.dart';
import '../sdk/flutter_runner.dart';
import 'manifest/package_manifest.dart';
import 'manifest/pubspec_package.dart';
import 'package_examples.dart';

class PackageCheckResult {
  const PackageCheckResult({required this.exitCode});

  final int exitCode;

  bool get passed => exitCode == 0;
}

Future<PackageCheckResult> checkPackage({
  required FluohEnvironment environment,
  required PackageManifest manifest,
  required PackageManifestPackage package,
  required OutputWriter stdout,
  required OutputWriter stderr,
  required TerminalOutput output,
  String usage = '',
}) async {
  final repository = environment.workingDirectory;
  final packageRoot = packageDirectory(repository, package.repositoryPath);
  final packagePath = packageRelativePath(repository, packageRoot);
  final packagePubspec = File('${packageRoot.path}/pubspec.yaml');
  if (!await packagePubspec.exists()) {
    throw UsageException('Missing pubspec.yaml in $packagePath.', usage);
  }
  final isFlutterPackage = await isFlutterPackageDirectory(packageRoot);
  final hasTests = await hasPackageTests(packageRoot);

  final packagePubGet = await _runToolCommand(
    environment: environment,
    directory: packageRoot,
    displayPath: packagePath,
    flutter: isFlutterPackage,
    arguments: const ['pub', 'get'],
    stdout: stdout,
    stderr: stderr,
    output: output,
    usage: usage,
  );
  if (packagePubGet != 0) {
    output.failure('Package dependency resolution failed for ${package.name}.');
    return PackageCheckResult(exitCode: packagePubGet);
  }

  final packageAnalyze = await _runToolCommand(
    environment: environment,
    directory: packageRoot,
    displayPath: packagePath,
    flutter: isFlutterPackage,
    arguments: const ['analyze'],
    stdout: stdout,
    stderr: stderr,
    output: output,
    usage: usage,
  );
  if (packageAnalyze != 0) {
    output.failure('Package analysis failed for ${package.name}.');
    return PackageCheckResult(exitCode: packageAnalyze);
  }
  output.success('Package analysis passed for ${package.name}.');

  if (hasTests) {
    final packageTest = await _runToolCommand(
      environment: environment,
      directory: packageRoot,
      displayPath: packagePath,
      flutter: isFlutterPackage,
      arguments: const ['test'],
      stdout: stdout,
      stderr: stderr,
      output: output,
      usage: usage,
    );
    if (packageTest != 0) {
      output.failure('Package tests failed for ${package.name}.');
      return PackageCheckResult(exitCode: packageTest);
    }
    output.success('Package tests passed for ${package.name}.');
  } else {
    output.skipped(
      'Skipping package tests for ${package.name}: no test files.',
    );
  }

  final example = Directory('${packageRoot.path}/example');
  final examplePubspec = File('${example.path}/pubspec.yaml');
  if (!await examplePubspec.exists()) {
    output.skipped(
      'Skipping example checks for ${package.name}: no top-level example.',
    );
    return const PackageCheckResult(exitCode: 0);
  }
  if (!await isFlutterPackageDirectory(example)) {
    output.skipped(
      'Skipping example checks for ${package.name}: example is not Flutter.',
    );
    return const PackageCheckResult(exitCode: 0);
  }

  final examplePath = packageRelativePath(repository, example);
  final examplePubGet = await _runToolCommand(
    environment: environment,
    directory: example,
    displayPath: examplePath,
    flutter: true,
    arguments: const ['pub', 'get'],
    stdout: stdout,
    stderr: stderr,
    output: output,
    usage: usage,
  );
  if (examplePubGet != 0) {
    output.failure('Example dependency resolution failed for ${package.name}.');
    return PackageCheckResult(exitCode: examplePubGet);
  }

  final exampleAnalyze = await _runToolCommand(
    environment: environment,
    directory: example,
    displayPath: examplePath,
    flutter: true,
    arguments: const ['analyze'],
    stdout: stdout,
    stderr: stderr,
    output: output,
    usage: usage,
  );
  if (exampleAnalyze != 0) {
    output.failure('Example analysis failed for ${package.name}.');
    return PackageCheckResult(exitCode: exampleAnalyze);
  }
  output.success('Example analysis passed for ${package.name}.');

  if (!await hasPackageTests(example)) {
    output.skipped(
      'Skipping example tests for ${package.name}: no example test files.',
    );
    return const PackageCheckResult(exitCode: 0);
  }

  final exampleTest = await _runToolCommand(
    environment: environment,
    directory: example,
    displayPath: examplePath,
    flutter: true,
    arguments: const ['test'],
    stdout: stdout,
    stderr: stderr,
    output: output,
    usage: usage,
  );
  if (exampleTest != 0) {
    output.failure('Example tests failed for ${package.name}.');
    return PackageCheckResult(exitCode: exampleTest);
  }
  output.success('Example tests passed for ${package.name}.');
  return const PackageCheckResult(exitCode: 0);
}

Future<int> _runToolCommand({
  required FluohEnvironment environment,
  required Directory directory,
  required String displayPath,
  required bool flutter,
  required List<String> arguments,
  required OutputWriter stdout,
  required OutputWriter stderr,
  required TerminalOutput output,
  required String usage,
}) async {
  final commandEnvironment = FluohEnvironment(
    homeDirectory: environment.homeDirectory,
    workingDirectory: directory,
    processEnvironment: environment.processEnvironment,
  );

  output.step(
    'Running ${flutter ? 'flutter' : 'dart'} ${arguments.join(' ')} in '
    '$displayPath',
  );
  return flutter
      ? runSelectedFlutter(
          environment: commandEnvironment,
          arguments: arguments,
          workingDirectory: directory,
          stdout: stdout,
          stderr: stderr,
          output: output,
          usage: usage,
        )
      : runSelectedDart(
          environment: commandEnvironment,
          arguments: arguments,
          workingDirectory: directory,
          stdout: stdout,
          stderr: stderr,
          output: output,
          usage: usage,
        );
}
