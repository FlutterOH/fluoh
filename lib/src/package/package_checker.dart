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
  const PackageCheckResult({
    required this.packageName,
    required this.exitCode,
    required this.steps,
  });

  final String packageName;
  final int exitCode;
  final List<PackageCheckStepResult> steps;

  bool get passed => exitCode == 0;

  Map<String, Object?> toJson() {
    return {
      'package': packageName,
      'passed': passed,
      'exitCode': exitCode,
      'steps': steps.map((step) => step.toJson()).toList(),
    };
  }
}

class PackageCheckStepResult {
  const PackageCheckStepResult({
    required this.name,
    required this.path,
    required this.command,
    required this.status,
    this.exitCode,
    this.reason,
  });

  final String name;
  final String path;
  final String command;
  final String status;
  final int? exitCode;
  final String? reason;

  Map<String, Object?> toJson() {
    return {
      'name': name,
      'path': path,
      'command': command,
      'status': status,
      if (exitCode != null) 'exitCode': exitCode,
      if (reason != null) 'reason': reason,
    };
  }
}

Future<PackageCheckResult> checkPackage({
  required FluohEnvironment environment,
  required PackageManifest manifest,
  required PackageManifestPackage package,
  required OutputWriter stdout,
  required OutputWriter stderr,
  required TerminalOutput output,
  String usage = '',
  String? buildExampleTarget,
  bool buildExampleDebug = false,
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
  final steps = <PackageCheckStepResult>[];

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
  steps.add(
    _commandStep(
      name: 'package-pub-get',
      path: packagePath,
      flutter: isFlutterPackage,
      arguments: const ['pub', 'get'],
      exitCode: packagePubGet,
    ),
  );
  if (packagePubGet != 0) {
    output.failure('Package dependency resolution failed for ${package.name}.');
    return PackageCheckResult(
      packageName: package.name,
      exitCode: packagePubGet,
      steps: steps,
    );
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
  steps.add(
    _commandStep(
      name: 'package-analyze',
      path: packagePath,
      flutter: isFlutterPackage,
      arguments: const ['analyze'],
      exitCode: packageAnalyze,
    ),
  );
  if (packageAnalyze != 0) {
    output.failure('Package analysis failed for ${package.name}.');
    return PackageCheckResult(
      packageName: package.name,
      exitCode: packageAnalyze,
      steps: steps,
    );
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
    steps.add(
      _commandStep(
        name: 'package-test',
        path: packagePath,
        flutter: isFlutterPackage,
        arguments: const ['test'],
        exitCode: packageTest,
      ),
    );
    if (packageTest != 0) {
      output.failure('Package tests failed for ${package.name}.');
      return PackageCheckResult(
        packageName: package.name,
        exitCode: packageTest,
        steps: steps,
      );
    }
    output.success('Package tests passed for ${package.name}.');
  } else {
    output.skipped(
      'Skipping package tests for ${package.name}: no test files.',
    );
    steps.add(
      PackageCheckStepResult(
        name: 'package-test',
        path: packagePath,
        command: 'test',
        status: 'skipped',
        reason: 'no test files',
      ),
    );
  }

  final example = Directory('${packageRoot.path}/example');
  final examplePubspec = File('${example.path}/pubspec.yaml');
  if (!await examplePubspec.exists()) {
    output.skipped(
      'Skipping example checks for ${package.name}: no top-level example.',
    );
    steps.add(
      PackageCheckStepResult(
        name: 'example',
        path: packageRelativePath(repository, example),
        command: 'flutter',
        status: 'skipped',
        reason: 'no top-level example',
      ),
    );
    return PackageCheckResult(
      packageName: package.name,
      exitCode: 0,
      steps: steps,
    );
  }
  if (!await isFlutterPackageDirectory(example)) {
    output.skipped(
      'Skipping example checks for ${package.name}: example is not Flutter.',
    );
    steps.add(
      PackageCheckStepResult(
        name: 'example',
        path: packageRelativePath(repository, example),
        command: 'flutter',
        status: 'skipped',
        reason: 'example is not Flutter',
      ),
    );
    return PackageCheckResult(
      packageName: package.name,
      exitCode: 0,
      steps: steps,
    );
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
  steps.add(
    _commandStep(
      name: 'example-pub-get',
      path: examplePath,
      flutter: true,
      arguments: const ['pub', 'get'],
      exitCode: examplePubGet,
    ),
  );
  if (examplePubGet != 0) {
    output.failure('Example dependency resolution failed for ${package.name}.');
    return PackageCheckResult(
      packageName: package.name,
      exitCode: examplePubGet,
      steps: steps,
    );
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
  steps.add(
    _commandStep(
      name: 'example-analyze',
      path: examplePath,
      flutter: true,
      arguments: const ['analyze'],
      exitCode: exampleAnalyze,
    ),
  );
  if (exampleAnalyze != 0) {
    output.failure('Example analysis failed for ${package.name}.');
    return PackageCheckResult(
      packageName: package.name,
      exitCode: exampleAnalyze,
      steps: steps,
    );
  }
  output.success('Example analysis passed for ${package.name}.');

  final exampleHasTests = await hasPackageTests(example);
  if (!exampleHasTests) {
    output.skipped(
      'Skipping example tests for ${package.name}: no example test files.',
    );
    steps.add(
      PackageCheckStepResult(
        name: 'example-test',
        path: examplePath,
        command: 'flutter test',
        status: 'skipped',
        reason: 'no example test files',
      ),
    );
  } else {
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
    steps.add(
      _commandStep(
        name: 'example-test',
        path: examplePath,
        flutter: true,
        arguments: const ['test'],
        exitCode: exampleTest,
      ),
    );
    if (exampleTest != 0) {
      output.failure('Example tests failed for ${package.name}.');
      return PackageCheckResult(
        packageName: package.name,
        exitCode: exampleTest,
        steps: steps,
      );
    }
    output.success('Example tests passed for ${package.name}.');
  }

  if (buildExampleTarget != null) {
    final buildArguments = [
      'build',
      buildExampleTarget,
      if (buildExampleDebug) '--debug',
    ];
    final exampleBuild = await _runToolCommand(
      environment: environment,
      directory: example,
      displayPath: examplePath,
      flutter: true,
      arguments: buildArguments,
      stdout: stdout,
      stderr: stderr,
      output: output,
      usage: usage,
    );
    steps.add(
      _commandStep(
        name: 'example-build-$buildExampleTarget',
        path: examplePath,
        flutter: true,
        arguments: buildArguments,
        exitCode: exampleBuild,
      ),
    );
    if (exampleBuild != 0) {
      output.failure(
        'Example $buildExampleTarget build failed for ${package.name}.',
      );
      return PackageCheckResult(
        packageName: package.name,
        exitCode: exampleBuild,
        steps: steps,
      );
    }
    output.success(
      'Example $buildExampleTarget build passed for ${package.name}.',
    );
  }

  return PackageCheckResult(
    packageName: package.name,
    exitCode: 0,
    steps: steps,
  );
}

PackageCheckStepResult _commandStep({
  required String name,
  required String path,
  required bool flutter,
  required List<String> arguments,
  required int exitCode,
}) {
  return PackageCheckStepResult(
    name: name,
    path: path,
    command: '${flutter ? 'flutter' : 'dart'} ${arguments.join(' ')}',
    status: exitCode == 0 ? 'passed' : 'failed',
    exitCode: exitCode,
  );
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
