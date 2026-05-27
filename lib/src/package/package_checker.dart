import 'dart:io';

import 'package:args/command_runner.dart';

import '../cli/fluoh_command_runner.dart';
import '../cli/terminal_output.dart';
import '../context/fluoh_environment.dart';
import '../ohos/build_profile_signing.dart';
import '../ohos/device_runner.dart';
import '../ohos/debug_signer.dart';
import '../sdk/flutter_runner.dart';
import 'flutter_example_runner.dart';
import 'manifest/package_manifest.dart';
import 'manifest/pubspec_package.dart';
import 'package_examples.dart';

class PackageCheckResult {
  const PackageCheckResult({
    required this.packageName,
    required this.exitCode,
    required this.steps,
    this.preset,
    this.phase,
  });

  final String packageName;
  final int exitCode;
  final List<PackageCheckStepResult> steps;
  final String? preset;
  final String? phase;

  bool get passed => exitCode == 0;

  String? get nextCommand {
    for (final step in steps) {
      final command = step.nextCommand;
      if (command != null) {
        return command;
      }
    }
    return null;
  }

  Map<String, Object?> toJson() {
    return {
      'package': packageName,
      if (preset != null) 'preset': preset,
      if (phase != null) 'phase': phase,
      'passed': passed,
      'exitCode': exitCode,
      if (nextCommand != null) 'nextCommand': nextCommand,
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
    this.details = const {},
    this.diagnostics = const [],
  });

  final String name;
  final String path;
  final String command;
  final String status;
  final int? exitCode;
  final String? reason;
  final Map<String, Object?> details;
  final List<PackageCheckDiagnostic> diagnostics;

  String? get nextCommand {
    for (final diagnostic in diagnostics) {
      if (diagnostic.nextCommand != null) {
        return diagnostic.nextCommand;
      }
    }
    return null;
  }

  Map<String, Object?> toJson() {
    return {
      'name': name,
      'path': path,
      'command': command,
      'status': status,
      if (exitCode != null) 'exitCode': exitCode,
      if (reason != null) 'reason': reason,
      if (nextCommand != null) 'nextCommand': nextCommand,
      if (details.isNotEmpty) 'details': details,
      if (diagnostics.isNotEmpty)
        'diagnostics': diagnostics.map((item) => item.toJson()).toList(),
    };
  }
}

class PackageCheckDiagnostic {
  const PackageCheckDiagnostic({
    required this.code,
    required this.message,
    this.severity = 'error',
    this.details = const {},
    this.nextCommand,
  });

  final String code;
  final String message;
  final String severity;
  final Map<String, Object?> details;
  final String? nextCommand;

  Map<String, Object?> toJson() {
    return {
      'code': code,
      'severity': severity,
      'message': message,
      if (nextCommand != null) 'nextCommand': nextCommand,
      if (details.isNotEmpty) 'details': details,
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
  bool autoSignExample = false,
  bool runExample = false,
  String? deviceId,
  bool startEmulator = false,
  String? emulatorName,
  Duration deviceTimeout = const Duration(seconds: 90),
  Duration logDuration = const Duration(seconds: 8),
  String? preset,
  String? phase,
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
      packageName: package.name,
      path: packagePath,
      flutter: isFlutterPackage,
      arguments: const ['pub', 'get'],
      result: packagePubGet,
    ),
  );
  if (packagePubGet.exitCode != 0) {
    output.failure('Package dependency resolution failed for ${package.name}.');
    return PackageCheckResult(
      packageName: package.name,
      exitCode: packagePubGet.exitCode,
      steps: steps,
      preset: preset,
      phase: phase,
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
      packageName: package.name,
      path: packagePath,
      flutter: isFlutterPackage,
      arguments: const ['analyze'],
      result: packageAnalyze,
    ),
  );
  if (packageAnalyze.exitCode != 0) {
    output.failure('Package analysis failed for ${package.name}.');
    return PackageCheckResult(
      packageName: package.name,
      exitCode: packageAnalyze.exitCode,
      steps: steps,
      preset: preset,
      phase: phase,
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
        packageName: package.name,
        path: packagePath,
        flutter: isFlutterPackage,
        arguments: const ['test'],
        result: packageTest,
      ),
    );
    if (packageTest.exitCode != 0) {
      output.failure('Package tests failed for ${package.name}.');
      return PackageCheckResult(
        packageName: package.name,
        exitCode: packageTest.exitCode,
        steps: steps,
        preset: preset,
        phase: phase,
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
      preset: preset,
      phase: phase,
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
      preset: preset,
      phase: phase,
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
      packageName: package.name,
      path: examplePath,
      flutter: true,
      arguments: const ['pub', 'get'],
      result: examplePubGet,
    ),
  );
  if (examplePubGet.exitCode != 0) {
    output.failure('Example dependency resolution failed for ${package.name}.');
    return PackageCheckResult(
      packageName: package.name,
      exitCode: examplePubGet.exitCode,
      steps: steps,
      preset: preset,
      phase: phase,
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
      packageName: package.name,
      path: examplePath,
      flutter: true,
      arguments: const ['analyze'],
      result: exampleAnalyze,
    ),
  );
  if (exampleAnalyze.exitCode != 0) {
    output.failure('Example analysis failed for ${package.name}.');
    return PackageCheckResult(
      packageName: package.name,
      exitCode: exampleAnalyze.exitCode,
      steps: steps,
      preset: preset,
      phase: phase,
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
        packageName: package.name,
        path: examplePath,
        flutter: true,
        arguments: const ['test'],
        result: exampleTest,
      ),
    );
    if (exampleTest.exitCode != 0) {
      output.failure('Example tests failed for ${package.name}.');
      return PackageCheckResult(
        packageName: package.name,
        exitCode: exampleTest.exitCode,
        steps: steps,
        preset: preset,
        phase: phase,
      );
    }
    output.success('Example tests passed for ${package.name}.');
  }

  if (buildExampleTarget != null) {
    final buildArguments = [
      'build',
      buildExampleTarget,
      if (buildExampleDebug) '--debug',
      if (buildExampleTarget == 'ios') '--no-codesign',
    ];
    OhosBuildProfileSigningSession? signingSession;
    OhosDebugSigningMaterial? signingMaterial;
    var signedHaps = <File>[];
    String? signingMode;
    if (autoSignExample) {
      if (buildExampleTarget != 'hap') {
        throw UsageException(
          'Automatic OHOS signing only supports --build-example hap.',
          usage,
        );
      }
      final ohosDirectory = Directory('${example.path}/ohos');
      if (!await ohosDirectory.exists()) {
        const reason = 'Missing OHOS example project.';
        steps.add(
          _ohosDiagnosticStep(
            name: 'ohos-auto-sign',
            packageName: package.name,
            path: examplePath,
            command: 'prepare OHOS debug signing',
            code: 'ohos.ohos_project_missing',
            message: reason,
            reason: '$reason Expected $examplePath/ohos.',
            details: {'expectedPath': '$examplePath/ohos'},
          ),
        );
        return PackageCheckResult(
          packageName: package.name,
          exitCode: 1,
          steps: steps,
          preset: preset,
          phase: phase,
        );
      }
      output.step(
        'Preparing temporary OHOS debug signing for ${package.name}.',
      );
      try {
        signingMaterial = await prepareOhosDebugSigning(
          environment: environment,
          ohosDirectory: ohosDirectory,
          output: output,
          usage: usage,
        );
      } on UsageException catch (error) {
        steps.add(
          _ohosDiagnosticStep(
            name: 'ohos-auto-sign',
            packageName: package.name,
            path: examplePath,
            command: 'prepare OHOS debug signing',
            code: 'ohos.toolchain_missing',
            message: 'Could not locate the local OHOS toolchain.',
            reason: error.message,
            details: {'error': error.message},
          ),
        );
        return PackageCheckResult(
          packageName: package.name,
          exitCode: 1,
          steps: steps,
          preset: preset,
          phase: phase,
        );
      } on Object catch (error) {
        steps.add(
          _ohosDiagnosticStep(
            name: 'ohos-auto-sign',
            packageName: package.name,
            path: examplePath,
            command: 'prepare OHOS debug signing',
            code: error is OhosSigningException
                ? 'ohos.signing_profile_failed'
                : 'ohos.auto_sign_failed',
            message: 'OHOS automatic debug signing failed.',
            reason: error.toString(),
            details: {'error': error.toString()},
          ),
        );
        return PackageCheckResult(
          packageName: package.name,
          exitCode: 1,
          steps: steps,
          preset: preset,
          phase: phase,
        );
      }
      try {
        signingSession = await applyTemporaryOhosSigning(
          ohosDirectory: ohosDirectory,
          config: signingMaterial.signingConfig,
        );
      } on Object catch (error) {
        steps.add(
          _ohosDiagnosticStep(
            name: 'ohos-auto-sign',
            packageName: package.name,
            path: examplePath,
            command: 'patch OHOS build-profile signing',
            code: 'ohos.build_profile_patch_failed',
            message: 'Could not patch OHOS build-profile signing.',
            reason: error.toString(),
            details: {
              ..._signingDetails(signingMaterial),
              'error': error.toString(),
            },
          ),
        );
        return PackageCheckResult(
          packageName: package.name,
          exitCode: 1,
          steps: steps,
          preset: preset,
          phase: phase,
        );
      }
      signingMode = 'build-profile';
      steps.add(
        PackageCheckStepResult(
          name: 'ohos-auto-sign',
          path: examplePath,
          command: 'prepare OHOS debug signing',
          status: 'passed',
          exitCode: 0,
          details: _signingDetails(signingMaterial),
        ),
      );
      if (signingMaterial.permissionProfile.restrictedPermissions.isNotEmpty) {
        output.detail(
          'Restricted permissions: '
          '${signingMaterial.permissionProfile.restrictedPermissions.join(', ')}',
        );
      }
    }
    late SelectedToolResult exampleBuild;
    var exampleBuildExitCode = 1;
    try {
      final buildStartedAt = DateTime.now().subtract(
        const Duration(seconds: 1),
      );
      exampleBuild = await _runToolCommand(
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
      exampleBuildExitCode = exampleBuild.exitCode;
      if (exampleBuildExitCode != 0 && signingMaterial != null) {
        output.step('Signing generated unsigned OHOS HAP for ${package.name}.');
        try {
          signedHaps = await signGeneratedUnsignedHaps(
            environment: environment,
            exampleDirectory: example,
            signingMaterial: signingMaterial,
            output: output,
            modifiedAfter: buildStartedAt,
            usage: usage,
          );
        } on Object catch (error) {
          steps.add(
            _ohosDiagnosticStep(
              name: 'ohos-direct-sign',
              packageName: package.name,
              path: examplePath,
              command: 'sign generated unsigned OHOS HAP',
              code: 'ohos.direct_sign_failed',
              message: 'Could not directly sign generated unsigned OHOS HAP.',
              reason: error.toString(),
              details: {
                ..._signingDetails(signingMaterial),
                ..._commandOutputDetails(exampleBuild),
                'error': error.toString(),
              },
            ),
          );
          return PackageCheckResult(
            packageName: package.name,
            exitCode: 1,
            steps: steps,
            preset: preset,
            phase: phase,
          );
        }
        if (signedHaps.isNotEmpty) {
          output.warning(
            'Flutter HAP build failed during Hvigor signing; '
            'fluoh signed the generated unsigned HAP directly.',
          );
          signingMode = 'direct-sign-fallback';
          exampleBuildExitCode = 0;
          steps.add(
            PackageCheckStepResult(
              name: 'ohos-direct-sign',
              path: examplePath,
              command: 'sign generated unsigned OHOS HAP',
              status: 'passed',
              exitCode: 0,
              details: {
                ..._signingDetails(signingMaterial),
                'signedHaps': _hapPaths(signedHaps),
              },
            ),
          );
        }
      }
      if (exampleBuildExitCode == 0) {
        signedHaps = await findInstallableOhosHaps(
          exampleDirectory: example,
          modifiedAfter: buildStartedAt,
        );
      }
    } finally {
      if (signingSession != null) {
        await signingSession.restore();
        output.detail('Restored $examplePath/ohos/build-profile.json5.');
      }
    }
    final buildDetails = <String, Object?>{
      if (signedHaps.isNotEmpty) 'installableHaps': _hapPaths(signedHaps),
    };
    if (signingMode != null) {
      buildDetails['signingMode'] = signingMode;
    }
    steps.add(
      _commandStep(
        name: 'example-build-$buildExampleTarget',
        packageName: package.name,
        path: examplePath,
        flutter: true,
        arguments: buildArguments,
        result: exampleBuild,
        effectiveExitCode: exampleBuildExitCode,
        details: buildDetails,
      ),
    );
    if (exampleBuildExitCode != 0) {
      output.failure(
        'Example $buildExampleTarget build failed for ${package.name}.',
      );
      return PackageCheckResult(
        packageName: package.name,
        exitCode: exampleBuildExitCode,
        steps: steps,
        preset: preset,
        phase: phase,
      );
    }
    output.success(
      'Example $buildExampleTarget build passed for ${package.name}.',
    );

    if (runExample && buildExampleTarget == 'hap') {
      final ohosDirectory = Directory('${example.path}/ohos');
      if (!await ohosDirectory.exists()) {
        const reason = 'Missing OHOS example project.';
        steps.add(
          _ohosDiagnosticStep(
            name: 'example-run-ohos',
            packageName: package.name,
            path: examplePath,
            command: 'hdc install -r <hap> && hdc shell aa start',
            code: 'ohos.ohos_project_missing',
            message: reason,
            reason: '$reason Expected $examplePath/ohos.',
            details: {'expectedPath': '$examplePath/ohos'},
          ),
        );
        return PackageCheckResult(
          packageName: package.name,
          exitCode: 1,
          steps: steps,
          preset: preset,
          phase: phase,
        );
      }
      final runResult = await runOhosHapsOnDevice(
        environment: environment,
        ohosDirectory: ohosDirectory,
        haps: signedHaps,
        output: output,
        deviceId: deviceId,
        startEmulator: startEmulator,
        emulatorName: emulatorName,
        deviceTimeout: deviceTimeout,
        logDuration: logDuration,
        usage: usage,
      );
      final reasonParts = [
        if (runResult.reason != null) runResult.reason!,
        if (runResult.logFile != null) 'hilog: ${runResult.logFile!.path}',
        if (runResult.findings.isNotEmpty)
          'findings: ${runResult.findings.join(' | ')}',
      ];
      steps.add(
        PackageCheckStepResult(
          name: 'example-run-ohos',
          path: examplePath,
          command: [
            'hdc',
            if (deviceId != null && deviceId.trim().isNotEmpty) '-t $deviceId',
            'install -r',
            '<hap>',
            '&&',
            'hdc',
            'shell aa start',
          ].join(' '),
          status: runResult.passed ? 'passed' : 'failed',
          exitCode: runResult.exitCode,
          reason: reasonParts.isEmpty ? null : reasonParts.join('\n'),
          diagnostics: runResult.diagnostics
              .map(
                (diagnostic) => PackageCheckDiagnostic(
                  code: diagnostic.code,
                  severity: diagnostic.severity,
                  message: diagnostic.message,
                  details: diagnostic.details,
                  nextCommand: _nextCommandForDiagnosticCode(
                    diagnostic.code,
                    package.name,
                  ),
                ),
              )
              .toList(),
        ),
      );
      if (!runResult.passed) {
        output.failure('Example OHOS run failed for ${package.name}.');
        if (runResult.reason != null) {
          output.detail(runResult.reason!);
        }
        if (runResult.logFile != null) {
          output.detail('Hilog saved to ${runResult.logFile!.path}.');
        }
        for (final finding in runResult.findings) {
          output.detail(finding);
        }
        return PackageCheckResult(
          packageName: package.name,
          exitCode: runResult.exitCode,
          steps: steps,
          preset: preset,
          phase: phase,
        );
      }
      if (runResult.logFile != null) {
        output.detail('Hilog saved to ${runResult.logFile!.path}.');
      }
      output.success('Example OHOS run passed for ${package.name}.');
    } else if (runExample) {
      final runResult = await runFlutterExampleOnDevice(
        environment: environment,
        exampleDirectory: example,
        buildExampleTarget: buildExampleTarget,
        output: output,
        stdout: stdout,
        stderr: stderr,
        deviceId: deviceId,
        startEmulator: startEmulator,
        emulatorName: emulatorName,
        deviceTimeout: deviceTimeout,
        runDuration: logDuration,
        usage: usage,
      );
      final runDetails = <String, Object?>{
        ...runResult.details,
        'platform': runResult.platform,
        if (runResult.target != null) 'target': runResult.target!.toJson(),
        if (runResult.emulator != null)
          'emulator': runResult.emulator!.toJson(),
        if (runResult.outputLog != null) 'outputLog': runResult.outputLog!.path,
      };
      steps.add(
        PackageCheckStepResult(
          name: 'example-run-${runResult.platform}',
          path: examplePath,
          command: runResult.command,
          status: runResult.passed ? 'passed' : 'failed',
          exitCode: runResult.exitCode,
          reason: runResult.reason,
          details: runDetails,
          diagnostics: runResult.diagnostics
              .map(
                (diagnostic) => PackageCheckDiagnostic(
                  code: diagnostic.code,
                  severity: diagnostic.severity,
                  message: diagnostic.message,
                  details: diagnostic.details,
                  nextCommand: _nextCommandForDiagnosticCode(
                    diagnostic.code,
                    package.name,
                  ),
                ),
              )
              .toList(),
        ),
      );
      if (!runResult.passed) {
        output.failure(
          'Example ${runResult.platform} run failed for ${package.name}.',
        );
        if (runResult.reason != null) {
          output.detail(runResult.reason!);
        }
        if (runResult.outputLog != null) {
          output.detail(
            'Flutter run output saved to ${runResult.outputLog!.path}.',
          );
        }
        return PackageCheckResult(
          packageName: package.name,
          exitCode: runResult.exitCode,
          steps: steps,
          preset: preset,
          phase: phase,
        );
      }
      if (runResult.outputLog != null) {
        output.detail(
          'Flutter run output saved to ${runResult.outputLog!.path}.',
        );
      }
      output.success(
        'Example ${runResult.platform} run passed for ${package.name}.',
      );

      final integrationDirectory = Directory(
        '${example.path}/integration_test',
      );
      final targetId = runResult.target?.id;
      if (await integrationDirectory.exists() && targetId != null) {
        final integrationArguments = [
          'test',
          'integration_test',
          '-d',
          targetId,
        ];
        final integrationTest = await _runToolCommand(
          environment: environment,
          directory: example,
          displayPath: examplePath,
          flutter: true,
          arguments: integrationArguments,
          stdout: stdout,
          stderr: stderr,
          output: output,
          usage: usage,
        );
        steps.add(
          _commandStep(
            name: 'example-integration-${runResult.platform}',
            packageName: package.name,
            path: examplePath,
            flutter: true,
            arguments: integrationArguments,
            result: integrationTest,
            details: {'platform': runResult.platform, 'targetId': targetId},
          ),
        );
        if (integrationTest.exitCode != 0) {
          output.failure(
            'Example ${runResult.platform} integration tests failed for ${package.name}.',
          );
          return PackageCheckResult(
            packageName: package.name,
            exitCode: integrationTest.exitCode,
            steps: steps,
            preset: preset,
            phase: phase,
          );
        }
        output.success(
          'Example ${runResult.platform} integration tests passed for ${package.name}.',
        );
      } else {
        steps.add(
          PackageCheckStepResult(
            name: 'example-integration-${runResult.platform}',
            path: examplePath,
            command: targetId == null
                ? 'flutter test integration_test -d <device>'
                : 'flutter test integration_test -d $targetId',
            status: 'skipped',
            reason: 'no integration_test directory',
            details: {'platform': runResult.platform},
          ),
        );
        output.skipped(
          'Skipping ${runResult.platform} integration tests for ${package.name}: no integration_test directory.',
        );
      }
    }
  }

  return PackageCheckResult(
    packageName: package.name,
    exitCode: 0,
    steps: steps,
    preset: preset,
    phase: phase,
  );
}

PackageCheckStepResult _commandStep({
  required String name,
  required String packageName,
  required String path,
  required bool flutter,
  required List<String> arguments,
  required SelectedToolResult result,
  int? effectiveExitCode,
  Map<String, Object?> details = const {},
}) {
  final exitCode = effectiveExitCode ?? result.exitCode;
  return PackageCheckStepResult(
    name: name,
    path: path,
    command: '${flutter ? 'flutter' : 'dart'} ${arguments.join(' ')}',
    status: exitCode == 0 ? 'passed' : 'failed',
    exitCode: exitCode,
    details: {
      ...details,
      if (result.exitCode != exitCode) 'originalExitCode': result.exitCode,
      if (result.exitCode != exitCode) ..._commandOutputDetails(result),
    },
    diagnostics: _diagnosticsForCommandStep(
      name: name,
      flutter: flutter,
      arguments: arguments,
      result: result,
      effectiveExitCode: exitCode,
      packageName: packageName,
    ),
  );
}

List<PackageCheckDiagnostic> _diagnosticsForCommandStep({
  required String name,
  required bool flutter,
  required List<String> arguments,
  required SelectedToolResult result,
  required int effectiveExitCode,
  required String packageName,
}) {
  if (effectiveExitCode == 0) {
    return const [];
  }
  final command = '${flutter ? 'flutter' : 'dart'} ${arguments.join(' ')}';
  final code = switch (name) {
    'package-pub-get' || 'example-pub-get' => 'dart.pub_get_failed',
    'package-analyze' || 'example-analyze' => 'dart.analysis_failed',
    'package-test' || 'example-test' => 'dart.test_failed',
    'example-integration-android' => 'android.integration_test_failed',
    'example-integration-ios' => 'ios.integration_test_failed',
    _
        when arguments.length >= 2 &&
            arguments[0] == 'build' &&
            arguments[1] == 'hap' =>
      'ohos.hap_build_failed',
    _
        when arguments.length >= 2 &&
            arguments[0] == 'build' &&
            arguments[1] == 'apk' =>
      'android.apk_build_failed',
    _
        when arguments.length >= 2 &&
            arguments[0] == 'build' &&
            arguments[1] == 'ios' =>
      'ios.build_failed',
    _ => 'command.failed',
  };
  final message = switch (code) {
    'dart.pub_get_failed' => 'Dependency resolution failed.',
    'dart.analysis_failed' => 'Static analysis failed.',
    'dart.test_failed' => 'Tests failed.',
    'android.integration_test_failed' => 'Android integration tests failed.',
    'ios.integration_test_failed' => 'iOS integration tests failed.',
    'ohos.hap_build_failed' => 'OHOS HAP build failed.',
    'android.apk_build_failed' => 'Android APK build failed.',
    'ios.build_failed' => 'iOS build failed.',
    _ => 'Command failed.',
  };
  return [
    PackageCheckDiagnostic(
      code: code,
      message: message,
      details: {
        'command': command,
        'exitCode': effectiveExitCode,
        ..._commandOutputDetails(result),
      },
      nextCommand: _nextCommandForDiagnosticCode(code, packageName),
    ),
  ];
}

PackageCheckStepResult _ohosDiagnosticStep({
  required String name,
  required String packageName,
  required String path,
  required String command,
  required String code,
  required String message,
  required String reason,
  Map<String, Object?> details = const {},
}) {
  return PackageCheckStepResult(
    name: name,
    path: path,
    command: command,
    status: 'failed',
    exitCode: 1,
    reason: reason,
    diagnostics: [
      PackageCheckDiagnostic(
        code: code,
        message: message,
        details: details,
        nextCommand: _nextCommandForDiagnosticCode(code, packageName),
      ),
    ],
  );
}

String? _nextCommandForDiagnosticCode(String code, String packageName) {
  final check = 'fluoh package check --package $packageName';
  return switch (code) {
    'dart.pub_get_failed' => 'fluoh deps get',
    'dart.analysis_failed' ||
    'dart.test_failed' ||
    'command.failed' => '$check --json',
    'ohos.hap_build_failed' ||
    'ohos.signing_profile_failed' ||
    'ohos.build_profile_patch_failed' ||
    'ohos.direct_sign_failed' ||
    'ohos.no_installable_hap' ||
    'ohos.install_failed' ||
    'ohos.launch_failed' ||
    'ohos.runtime_crash' => '$check --preset ohos-run --json',
    'ohos.toolchain_missing' ||
    'ohos.auto_sign_failed' ||
    'ohos.hdc_targets_failed' ||
    'ohos.emulator_start_failed' ||
    'ohos.device_missing' ||
    'ohos.device_not_found' ||
    'ohos.device_ambiguous' ||
    'ohos.launch_info_missing' =>
      'fluoh doctor env --platform ohos --json --strict',
    'ohos.ohos_project_missing' =>
      'fluoh doctor project --platform ohos --json --strict',
    'android.apk_build_failed' ||
    'android.launch_timeout' ||
    'android.run_failed' ||
    'android.runtime_crash' ||
    'android.integration_test_failed' => '$check --preset android-run --json',
    'android.devices_failed' ||
    'android.emulators_failed' ||
    'android.emulator_missing' ||
    'android.emulator_start_failed' =>
      'fluoh doctor env --platform android --json --strict',
    'android.emulator_not_found' ||
    'android.emulator_ambiguous' => '$check --preset android-run --json',
    'android.device_missing' => '$check --preset android-run --json',
    'android.device_not_found' ||
    'android.device_ambiguous' => 'fluohf devices',
    'ios.build_failed' ||
    'ios.launch_timeout' ||
    'ios.run_failed' ||
    'ios.runtime_crash' ||
    'ios.integration_test_failed' => '$check --preset ios-run --json',
    'ios.devices_failed' ||
    'ios.emulators_failed' ||
    'ios.emulator_missing' ||
    'ios.emulator_start_failed' =>
      'fluoh doctor env --platform ios --json --strict',
    'ios.emulator_not_found' ||
    'ios.emulator_ambiguous' => '$check --preset ios-run --json',
    'ios.device_missing' => '$check --preset ios-run --json',
    'ios.device_not_found' || 'ios.device_ambiguous' => 'fluohf devices',
    _ => null,
  };
}

Map<String, Object?> _signingDetails(OhosDebugSigningMaterial signingMaterial) {
  final profile = signingMaterial.permissionProfile;
  return {
    'bundleName': profile.bundleName,
    'requestedPermissions': profile.requestedPermissions,
    'restrictedPermissions': profile.restrictedPermissions,
    'apl': profile.apl,
    'signingConfig': signingMaterial.signingConfig.name,
    'profile': signingMaterial.signingConfig.profile,
  };
}

List<String> _hapPaths(List<File> haps) {
  return [for (final hap in haps) hap.path];
}

Map<String, Object?> _commandOutputDetails(SelectedToolResult result) {
  return {
    if (result.stdout.trim().isNotEmpty) 'stdoutTail': result.stdout,
    if (result.stderr.trim().isNotEmpty) 'stderrTail': result.stderr,
    if (result.combinedOutput.trim().isNotEmpty)
      'outputTail': result.combinedOutput,
  };
}

Future<SelectedToolResult> _runToolCommand({
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
      ? runSelectedFlutterResult(
          environment: commandEnvironment,
          arguments: arguments,
          workingDirectory: directory,
          stdout: stdout,
          stderr: stderr,
          output: output,
          usage: usage,
        )
      : runSelectedDartResult(
          environment: commandEnvironment,
          arguments: arguments,
          workingDirectory: directory,
          stdout: stdout,
          stderr: stderr,
          output: output,
          usage: usage,
        );
}
