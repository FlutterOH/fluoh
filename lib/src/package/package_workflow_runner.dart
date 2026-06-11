import 'dart:io';

import 'package:args/command_runner.dart';

import '../cli/fluoh_command_runner.dart';
import '../cli/terminal_output.dart';
import '../context/fluoh_environment.dart';
import '../platform/ohos/build_profile_signing.dart';
import '../platform/ohos/device_runner.dart';
import '../platform/ohos/debug_signer.dart';
import '../platform/ohos/resource_layout.dart';
import '../sdk/flutter_runner.dart';
import '../workflow/workflow_result.dart';
import 'flutter_example_runner.dart';
import 'manifest/package_manifest.dart';
import 'manifest/pubspec_package.dart';
import 'package_examples.dart';

/// Runs the package verification workflow for one package entry.
Future<WorkflowTargetResult> runPackageWorkflow({
  required FluohEnvironment environment,
  required PackageManifest manifest,
  required PackageManifestPackage package,
  required OutputWriter stdout,
  required OutputWriter stderr,
  required TerminalOutput output,
  String usage = '',
  String? buildExampleTarget,
  bool buildExampleDebug = false,
  bool buildExampleForSimulator = false,
  bool autoSignExample = false,
  bool runExample = false,
  String? deviceId,
  bool startEmulator = false,
  String? emulatorName,
  File? sessionFile,
  Duration deviceTimeout = const Duration(seconds: 90),
  Duration logDuration = const Duration(seconds: 8),
  String? preset,
  String? phase,
}) async {
  final repository = environment.workingDirectory;
  final packageRoot = packageDirectory(repository, package.path);
  final packagePath = packageRelativePath(repository, packageRoot);
  final packagePubspec = File('${packageRoot.path}/pubspec.yaml');
  if (!await packagePubspec.exists()) {
    throw UsageException('Missing pubspec.yaml in $packagePath.', usage);
  }
  final isFlutterPackage = await isFlutterPackageDirectory(packageRoot);
  final hasTests = await hasPackageTests(packageRoot);
  final steps = <WorkflowStepResult>[];

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
    output.failure('Package dependency resolution failed for ${package.name}');
    return WorkflowTargetResult.package(
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
    output.failure('Package analysis failed for ${package.name}');
    return WorkflowTargetResult.package(
      packageName: package.name,
      exitCode: packageAnalyze.exitCode,
      steps: steps,
      preset: preset,
      phase: phase,
    );
  }
  output.success('Package analysis passed for ${package.name}');

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
      output.failure('Package tests failed for ${package.name}');
      return WorkflowTargetResult.package(
        packageName: package.name,
        exitCode: packageTest.exitCode,
        steps: steps,
        preset: preset,
        phase: phase,
      );
    }
    output.success('Package tests passed for ${package.name}');
  } else {
    output.skipped('Skipping package tests for ${package.name}: no test files');
    steps.add(
      WorkflowStepResult(
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
      'Skipping example verification for ${package.name}: no top-level example',
    );
    steps.add(
      WorkflowStepResult(
        name: 'example',
        path: packageRelativePath(repository, example),
        command: 'flutter',
        status: 'skipped',
        reason: 'no top-level example',
      ),
    );
    return WorkflowTargetResult.package(
      packageName: package.name,
      exitCode: 0,
      steps: steps,
      preset: preset,
      phase: phase,
    );
  }
  if (!await isFlutterPackageDirectory(example)) {
    output.skipped(
      'Skipping example verification for ${package.name}: example is not Flutter',
    );
    steps.add(
      WorkflowStepResult(
        name: 'example',
        path: packageRelativePath(repository, example),
        command: 'flutter',
        status: 'skipped',
        reason: 'example is not Flutter',
      ),
    );
    return WorkflowTargetResult.package(
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
    output.failure('Example dependency resolution failed for ${package.name}');
    return WorkflowTargetResult.package(
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
    output.failure('Example analysis failed for ${package.name}');
    return WorkflowTargetResult.package(
      packageName: package.name,
      exitCode: exampleAnalyze.exitCode,
      steps: steps,
      preset: preset,
      phase: phase,
    );
  }
  output.success('Example analysis passed for ${package.name}');

  final exampleHasTests = await hasPackageTests(example);
  if (!exampleHasTests) {
    output.skipped(
      'Skipping example tests for ${package.name}: no example test files',
    );
    steps.add(
      WorkflowStepResult(
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
      output.failure('Example tests failed for ${package.name}');
      return WorkflowTargetResult.package(
        packageName: package.name,
        exitCode: exampleTest.exitCode,
        steps: steps,
        preset: preset,
        phase: phase,
      );
    }
    output.success('Example tests passed for ${package.name}');
  }

  final exampleHasIntegrationTests = await hasIntegrationTests(example);
  final exampleHasIntegrationTestDirectory = await hasIntegrationTestDirectory(
    example,
  );
  if (buildExampleTarget == null && !runExample && exampleHasIntegrationTests) {
    output.skipped(
      'Discovered example integration tests for ${package.name}: run a platform target to execute them on a device',
    );
    steps.add(
      _integrationDiscoveryStep(
        name: 'example-integration',
        path: examplePath,
        packageName: package.name,
      ),
    );
  }

  if (buildExampleTarget != null) {
    final buildArguments = [
      'build',
      buildExampleTarget,
      if (buildExampleTarget == 'ios' && buildExampleForSimulator)
        '--simulator',
      if (buildExampleDebug) '--debug',
      if (buildExampleTarget == 'ios' && !buildExampleForSimulator)
        '--no-codesign',
    ];
    OhosBuildProfileSigningSession? signingSession;
    OhosDebugSigningMaterial? signingMaterial;
    var signedHaps = <File>[];
    String? signingMode;
    final ohosDirectory = Directory('${example.path}/ohos');
    if (buildExampleTarget == 'hap') {
      await stabilizeOhosResourceLayout(ohosDirectory);
    }
    if (autoSignExample) {
      if (buildExampleTarget != 'hap') {
        throw UsageException(
          'Automatic OHOS signing only supports the OHOS build target.',
          usage,
        );
      }
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
        return WorkflowTargetResult.package(
          packageName: package.name,
          exitCode: 1,
          steps: steps,
          preset: preset,
          phase: phase,
        );
      }
      output.step('Preparing temporary OHOS debug signing for ${package.name}');
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
            message: 'Could not locate the local OpenHarmony toolchain.',
            reason: error.message,
            details: {'error': error.message},
          ),
        );
        return WorkflowTargetResult.package(
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
        return WorkflowTargetResult.package(
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
        return WorkflowTargetResult.package(
          packageName: package.name,
          exitCode: 1,
          steps: steps,
          preset: preset,
          phase: phase,
        );
      }
      signingMode = 'build-profile';
      steps.add(
        WorkflowStepResult(
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
    SelectedToolResult? firstFailedIosBuild;
    var exampleBuildExitCode = 1;
    var retriedAfterClean = false;
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
      if (exampleBuildExitCode != 0 &&
          buildExampleTarget == 'ios' &&
          _isStaleIosPrecompiledHeaderFailure(exampleBuild)) {
        firstFailedIosBuild = exampleBuild;
        output.step(
          'Cleaning stale iOS build cache before retrying ${package.name}',
        );
        final cleanResult = await _runToolCommand(
          environment: environment,
          directory: example,
          displayPath: examplePath,
          flutter: true,
          arguments: const ['clean'],
          stdout: stdout,
          stderr: stderr,
          output: output,
          usage: usage,
        );
        steps.add(
          _commandStep(
            name: 'example-clean-ios-build-cache',
            packageName: package.name,
            path: examplePath,
            flutter: true,
            arguments: const ['clean'],
            result: cleanResult,
          ),
        );
        if (cleanResult.exitCode == 0) {
          retriedAfterClean = true;
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
        }
      }
      if (exampleBuildExitCode != 0 && signingMaterial != null) {
        output.step('Signing generated unsigned OHOS HAP for ${package.name}');
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
          return WorkflowTargetResult.package(
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
            WorkflowStepResult(
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
        if (buildExampleTarget == 'hap') {
          await stabilizeOhosResourceLayout(ohosDirectory);
        }
        signedHaps = await findInstallableOhosHaps(
          exampleDirectory: example,
          modifiedAfter: buildStartedAt,
        );
      }
    } finally {
      if (signingSession != null) {
        await signingSession.restore();
        output.detail('Restored $examplePath/ohos/build-profile.json5');
      }
    }
    final buildDetails = <String, Object?>{
      if (signedHaps.isNotEmpty) 'installableHaps': _hapPaths(signedHaps),
      if (retriedAfterClean) 'retryAfterClean': true,
      if (firstFailedIosBuild != null)
        'firstFailure': _commandOutputDetails(firstFailedIosBuild),
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
        'Example $buildExampleTarget build failed for ${package.name}',
      );
      return WorkflowTargetResult.package(
        packageName: package.name,
        exitCode: exampleBuildExitCode,
        steps: steps,
        preset: preset,
        phase: phase,
      );
    }
    output.success(
      'Example $buildExampleTarget build passed for ${package.name}',
    );

    if (runExample && buildExampleTarget == 'hap') {
      if (!await ohosDirectory.exists()) {
        const reason = 'Missing OHOS example project';
        steps.add(
          _ohosDiagnosticStep(
            name: 'example-run-ohos',
            packageName: package.name,
            path: examplePath,
            command: 'hdc install -r <hap> && hdc shell aa start',
            code: 'ohos.ohos_project_missing',
            message: reason,
            reason: '$reason. Expected $examplePath/ohos',
            details: {'expectedPath': '$examplePath/ohos'},
          ),
        );
        return WorkflowTargetResult.package(
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
      final runDetails = <String, Object?>{
        if (runResult.targetId != null) 'targetId': runResult.targetId,
        if (runResult.launchInfo != null)
          'launchInfo': {
            'bundleName': runResult.launchInfo!.bundleName,
            'moduleName': runResult.launchInfo!.moduleName,
            'abilityName': runResult.launchInfo!.abilityName,
          },
        if (runResult.logFile != null) 'hilog': runResult.logFile!.path,
        if (runResult.findings.isNotEmpty) 'findings': runResult.findings,
      };
      steps.add(
        WorkflowStepResult(
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
          details: runDetails,
          diagnostics: runResult.diagnostics
              .map(
                (diagnostic) => WorkflowDiagnostic(
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
        output.failure('Example OHOS run failed for ${package.name}');
        if (runResult.reason != null) {
          output.detail(runResult.reason!);
        }
        if (runResult.logFile != null) {
          output.detail('Hilog saved to ${runResult.logFile!.path}');
        }
        for (final finding in runResult.findings) {
          output.detail(finding);
        }
        return WorkflowTargetResult.package(
          packageName: package.name,
          exitCode: runResult.exitCode,
          steps: steps,
          preset: preset,
          phase: phase,
        );
      }
      if (runResult.logFile != null) {
        output.detail('Hilog saved to ${runResult.logFile!.path}');
      }
      output.success('Example OHOS run passed for ${package.name}');
      if (exampleHasIntegrationTests) {
        steps.add(
          _ohosManualAssistedIntegrationStep(
            name: 'example-integration-ohos',
            path: examplePath,
            logFile: runResult.logFile,
            targetId: runResult.targetId,
          ),
        );
        output.next(
          'Complete the OHOS interaction manually, then verify logs or app status before marking interaction evidence passed',
        );
      }
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
        sessionFile: sessionFile,
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
        WorkflowStepResult(
          name: 'example-run-${runResult.platform}',
          path: examplePath,
          command: runResult.command,
          status: runResult.passed ? 'passed' : 'failed',
          exitCode: runResult.exitCode,
          reason: runResult.reason,
          details: runDetails,
          diagnostics: runResult.diagnostics
              .map(
                (diagnostic) => WorkflowDiagnostic(
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
          'Example ${runResult.platform} run failed for ${package.name}',
        );
        if (runResult.reason != null) {
          output.detail(runResult.reason!);
        }
        if (runResult.outputLog != null) {
          output.detail(
            'Flutter run output saved to ${runResult.outputLog!.path}',
          );
        }
        return WorkflowTargetResult.package(
          packageName: package.name,
          exitCode: runResult.exitCode,
          steps: steps,
          preset: preset,
          phase: phase,
        );
      }
      if (runResult.outputLog != null) {
        output.detail(
          'Flutter run output saved to ${runResult.outputLog!.path}',
        );
      }
      output.success(
        'Example ${runResult.platform} run passed for ${package.name}',
      );

      final targetId = runResult.target?.id;
      if (exampleHasIntegrationTests &&
          runResult.platform == 'web' &&
          targetId == 'web-server') {
        const reason =
            'web-server target does not run browser integration tests';
        final suggestedCommand =
            'fluoh run web --package ${package.name} --device-id chrome --json';
        steps.add(
          WorkflowStepResult(
            name: 'example-integration-${runResult.platform}',
            path: examplePath,
            command: 'flutter test integration_test -d <browser-device>',
            status: 'skipped',
            reason: reason,
            details: {
              'platform': runResult.platform,
              'targetId': targetId,
              'requiredTargetKind': 'browser',
              'suggestedDevice': 'chrome',
              'suggestedCommand': suggestedCommand,
            },
            diagnostics: [
              WorkflowDiagnostic(
                code: 'web.integration_target_unsupported',
                severity: 'info',
                message:
                    'Web integration tests require a browser device, not web-server.',
                details: {
                  'platform': runResult.platform,
                  'targetId': targetId,
                  'requiredTargetKind': 'browser',
                  'suggestedDevice': 'chrome',
                  'suggestedCommand': suggestedCommand,
                },
              ),
            ],
          ),
        );
        output.skipped(
          'Skipping ${runResult.platform} integration tests for ${package.name}: $reason',
        );
      } else if (exampleHasIntegrationTests && targetId != null) {
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
            nextCommand: _packageRunNextCommand(
              packageName: package.name,
              platform: runResult.platform,
              deviceId: deviceId,
              startEmulator: startEmulator,
              emulatorName: emulatorName,
            ),
            details: {
              'platform': runResult.platform,
              'targetId': targetId,
              'interactionEvidence': {
                'method': 'integration_test',
                'status': integrationTest.exitCode == 0 ? 'passed' : 'failed',
                'testDirectory': '$examplePath/integration_test',
              },
            },
          ),
        );
        if (integrationTest.exitCode != 0) {
          output.failure(
            'Example ${runResult.platform} integration tests failed for ${package.name}',
          );
          return WorkflowTargetResult.package(
            packageName: package.name,
            exitCode: integrationTest.exitCode,
            steps: steps,
            preset: preset,
            phase: phase,
          );
        }
        output.success(
          'Example ${runResult.platform} integration tests passed for ${package.name}',
        );
      } else if (exampleHasIntegrationTests) {
        steps.add(
          WorkflowStepResult(
            name: 'example-integration-${runResult.platform}',
            path: examplePath,
            command: 'flutter test integration_test -d <device>',
            status: 'skipped',
            reason: 'run target did not expose a device id',
            details: {
              'platform': runResult.platform,
              'interactionEvidence': {
                'status': 'blocked',
                'method': 'integration_test',
                'reason': 'missing target id',
                'testDirectory': '$examplePath/integration_test',
              },
            },
          ),
        );
        output.skipped(
          'Skipping ${runResult.platform} integration tests for ${package.name}: missing target id',
        );
      } else {
        final reason = exampleHasIntegrationTestDirectory
            ? 'no integration test files'
            : 'no integration_test directory';
        steps.add(
          WorkflowStepResult(
            name: 'example-integration-${runResult.platform}',
            path: examplePath,
            command: targetId == null
                ? 'flutter test integration_test -d <device>'
                : 'flutter test integration_test -d $targetId',
            status: 'skipped',
            reason: reason,
            details: {
              'platform': runResult.platform,
              'interactionEvidence': {
                'status': 'not-present',
                'reason': reason,
              },
            },
          ),
        );
        output.skipped(
          'Skipping ${runResult.platform} integration tests for ${package.name}: $reason',
        );
      }
    }
  }

  return WorkflowTargetResult.package(
    packageName: package.name,
    exitCode: 0,
    steps: steps,
    preset: preset,
    phase: phase,
  );
}

WorkflowStepResult _integrationDiscoveryStep({
  required String name,
  required String path,
  required String packageName,
}) {
  final targetOption = ' --package $packageName';
  return WorkflowStepResult(
    name: name,
    path: path,
    command: 'flutter test integration_test -d <device>',
    status: 'skipped',
    reason: 'requires a platform run target',
    details: {
      'testDirectory': '$path/integration_test',
      'interactionEvidence': {
        'status': 'available',
        'method': 'integration_test',
        'execution': 'run fluoh run with a concrete platform and device',
      },
      'suggestedCommands': [
        'fluoh run ohos$targetOption --auto-emulator --json',
        'fluoh run android$targetOption --auto-emulator --json',
        'fluoh run ios$targetOption --auto-emulator --json',
        'fluoh run macos$targetOption --json',
        'fluoh run web$targetOption --device-id chrome --json',
      ],
      'manualAssistedFallback': {
        'when':
            'system UI, permissions, pickers, external apps, or OHOS runner gaps block automatic execution',
        'requiredEvidence':
            'record user steps plus tool-verified logs, session status, stable text, semantics, or app log markers',
      },
    },
  );
}

WorkflowStepResult _ohosManualAssistedIntegrationStep({
  required String name,
  required String path,
  File? logFile,
  String? targetId,
}) {
  return WorkflowStepResult(
    name: name,
    path: path,
    command: 'flutter test integration_test -d <ohos-device>',
    status: 'skipped',
    reason:
        'OHOS integration_test automation is not available; manual-assisted interaction evidence is required.',
    details: {
      'testDirectory': '$path/integration_test',
      'targetId': ?targetId,
      'hilog': ?logFile?.path,
      'interactionEvidence': {
        'status': 'manual-required',
        'method': 'manual-assisted',
        'platform': 'ohos',
        'requiredUserAction':
            'complete the integration scenario on the OHOS emulator or device',
        'verification':
            'after user action, verify app state through hilog, stable text, semantic labels, test keys, or structured app logs',
      },
      'reportMethod': 'manual-assisted',
      'reportRequirement':
          'write an Interaction Evidence row with result passed only after tool-readable evidence confirms the user-completed flow',
    },
  );
}

WorkflowStepResult _commandStep({
  required String name,
  required String packageName,
  required String path,
  required bool flutter,
  required List<String> arguments,
  required SelectedToolResult result,
  int? effectiveExitCode,
  Map<String, Object?> details = const {},
  String? nextCommand,
}) {
  final exitCode = effectiveExitCode ?? result.exitCode;
  return WorkflowStepResult(
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
      nextCommand: nextCommand,
    ),
  );
}

List<WorkflowDiagnostic> _diagnosticsForCommandStep({
  required String name,
  required bool flutter,
  required List<String> arguments,
  required SelectedToolResult result,
  required int effectiveExitCode,
  required String packageName,
  String? nextCommand,
}) {
  if (effectiveExitCode == 0) {
    return const [];
  }
  final command = '${flutter ? 'flutter' : 'dart'} ${arguments.join(' ')}';
  final sdkConstraint = _dartSdkConstraintFailure(result);
  final isPubGetStep = name == 'package-pub-get' || name == 'example-pub-get';
  final code = switch (name) {
    _ when isPubGetStep && sdkConstraint != null =>
      'dart.sdk_constraint_unsatisfied',
    'package-pub-get' || 'example-pub-get' => 'dart.pub_get_failed',
    'package-analyze' || 'example-analyze' => 'dart.analysis_failed',
    'package-test' || 'example-test' => 'dart.test_failed',
    'example-integration-android' => 'android.integration_test_failed',
    'example-integration-ios' => 'ios.integration_test_failed',
    'example-integration-macos' => 'macos.integration_test_failed',
    'example-integration-linux' => 'linux.integration_test_failed',
    'example-integration-web' => 'web.integration_test_failed',
    'example-integration-windows' => 'windows.integration_test_failed',
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
    _
        when arguments.length >= 2 &&
            arguments[0] == 'build' &&
            arguments[1] == 'macos' =>
      'macos.build_failed',
    _
        when arguments.length >= 2 &&
            arguments[0] == 'build' &&
            arguments[1] == 'linux' =>
      'linux.build_failed',
    _
        when arguments.length >= 2 &&
            arguments[0] == 'build' &&
            arguments[1] == 'web' =>
      'web.build_failed',
    _
        when arguments.length >= 2 &&
            arguments[0] == 'build' &&
            arguments[1] == 'windows' =>
      'windows.build_failed',
    _ => 'command.failed',
  };
  final message = switch (code) {
    'dart.sdk_constraint_unsatisfied' =>
      'Package SDK constraint is higher than the selected Dart SDK.',
    'dart.pub_get_failed' => 'Dependency resolution failed.',
    'dart.analysis_failed' => 'Static analysis failed.',
    'dart.test_failed' => 'Tests failed.',
    'android.integration_test_failed' => 'Android integration tests failed.',
    'ios.integration_test_failed' => 'iOS integration tests failed.',
    'macos.integration_test_failed' => 'macOS integration tests failed.',
    'linux.integration_test_failed' => 'Linux integration tests failed.',
    'web.integration_test_failed' => 'Web integration tests failed.',
    'windows.integration_test_failed' => 'Windows integration tests failed.',
    'ohos.hap_build_failed' => 'OHOS HAP build failed.',
    'android.apk_build_failed' => 'Android APK build failed.',
    'ios.build_failed' => 'iOS build failed.',
    'macos.build_failed' => 'macOS build failed.',
    'linux.build_failed' => 'Linux build failed.',
    'web.build_failed' => 'Web build failed.',
    'windows.build_failed' => 'Windows build failed.',
    _ => 'Command failed.',
  };
  return [
    WorkflowDiagnostic(
      code: code,
      message: message,
      details: {
        'command': command,
        'exitCode': effectiveExitCode,
        'sdkConstraint': ?sdkConstraint,
        if (code == 'dart.sdk_constraint_unsatisfied')
          'adaptationPolicy': _lowSdkCompatibilityPolicy(packageName),
        ..._commandOutputDetails(result),
      },
      nextCommand:
          nextCommand ?? _nextCommandForDiagnosticCode(code, packageName),
    ),
  ];
}

Map<String, Object?> _lowSdkCompatibilityPolicy(String packageName) {
  return {
    'defaultAction': 'adapt-selected-upstream-to-selected-sdk',
    'keepSelectedUpstream': true,
    'adjustPackageForSelectedSdk': true,
    'upstreamDowngradeRequiresApproval': true,
    'suggestedEdits': [
      'Update pubspec.yaml environment.sdk only when the selected Dart SDK can support the package after code changes.',
      'Patch package and example configuration for the selected FlutterOH SDK.',
      'Replace Dart language, SDK API, or dependency usage that requires a newer Dart SDK.',
      'Rerun fluoh verify --package $packageName --json after each compatibility edit.',
    ],
  };
}

String? _suggestedEnvironmentSdkConstraint(String dartVersion) {
  final match = RegExp(r'^(\d+)\.(\d+)\.').firstMatch(dartVersion);
  if (match == null) {
    return null;
  }
  final major = int.tryParse(match.group(1)!);
  final minor = int.tryParse(match.group(2)!);
  if (major == null || minor == null) {
    return null;
  }
  return '>=$major.$minor.0 <${major + 1}.0.0';
}

Map<String, Object?>? _dartSdkConstraintFailure(SelectedToolResult result) {
  final output = result.combinedOutput;
  final current = RegExp(
    r'The current Dart SDK version is\s+([^\s.]+(?:\.[^\s.]+)*)\.',
  ).firstMatch(output);
  final required = RegExp(
    r'requires SDK version\s+(.+?),\s+version solving failed',
  ).firstMatch(output);
  if (current == null || required == null) {
    return null;
  }
  final suggestedFlutter = RegExp(
    r'Try using the Flutter SDK version:\s*([^\s.]+(?:\.[^\s.]+)*)',
  ).firstMatch(output);
  final currentVersion = current.group(1);
  return {
    'currentDartVersion': currentVersion,
    'requiredDartConstraint': required.group(1),
    if (currentVersion != null)
      'suggestedEnvironmentSdkConstraint': _suggestedEnvironmentSdkConstraint(
        currentVersion,
      ),
    if (suggestedFlutter != null)
      'suggestedFlutterSdkVersion': suggestedFlutter.group(1),
  };
}

WorkflowStepResult _ohosDiagnosticStep({
  required String name,
  required String packageName,
  required String path,
  required String command,
  required String code,
  required String message,
  required String reason,
  Map<String, Object?> details = const {},
}) {
  return WorkflowStepResult(
    name: name,
    path: path,
    command: command,
    status: 'failed',
    exitCode: 1,
    reason: reason,
    diagnostics: [
      WorkflowDiagnostic(
        code: code,
        message: message,
        details: details,
        nextCommand: _nextCommandForDiagnosticCode(code, packageName),
      ),
    ],
  );
}

String? _nextCommandForDiagnosticCode(String code, String packageName) {
  final baseline = 'fluoh verify --package $packageName';
  final ohosRun = 'fluoh run ohos --package $packageName';
  final ohosAutoRun = '$ohosRun --auto-emulator';
  final androidRun = 'fluoh run android --package $packageName';
  final androidAutoRun = '$androidRun --auto-emulator';
  final iosRun = 'fluoh run ios --package $packageName';
  final iosAutoRun = '$iosRun --auto-emulator';
  final macosRun = 'fluoh run macos --package $packageName';
  final linuxRun = 'fluoh run linux --package $packageName';
  final webRun = 'fluoh run web --package $packageName --device-id web-server';
  final windowsRun = 'fluoh run windows --package $packageName';
  return switch (code) {
    'dart.sdk_constraint_unsatisfied' => '$baseline --json',
    'dart.pub_get_failed' => 'fluoh deps get',
    'dart.analysis_failed' ||
    'dart.test_failed' ||
    'command.failed' => '$baseline --json',
    'ohos.hap_build_failed' ||
    'ohos.signing_profile_failed' ||
    'ohos.build_profile_patch_failed' ||
    'ohos.direct_sign_failed' ||
    'ohos.no_installable_hap' ||
    'ohos.install_failed' ||
    'ohos.launch_failed' ||
    'ohos.runtime_crash' => '$ohosAutoRun --json',
    'ohos.toolchain_missing' ||
    'ohos.auto_sign_failed' ||
    'ohos.hdc_connection_failed' ||
    'ohos.hdc_targets_failed' ||
    'ohos.hdc_target_unavailable' ||
    'ohos.emulator_start_failed' ||
    'ohos.device_not_found' ||
    'ohos.device_ambiguous' ||
    'ohos.launch_info_missing' => 'fluoh doctor --platform ohos --json',
    'ohos.device_missing' => '$ohosRun --auto-emulator --json',
    'ohos.ohos_project_missing' => 'fluoh doctor --platform ohos --json',
    'android.apk_build_failed' ||
    'android.launch_timeout' ||
    'android.run_failed' ||
    'android.runtime_crash' ||
    'android.integration_test_failed' => '$androidAutoRun --json',
    'android.devices_failed' ||
    'android.emulators_failed' ||
    'android.emulator_missing' ||
    'android.emulator_start_failed' => 'fluoh doctor --platform android --json',
    'android.emulator_not_found' ||
    'android.emulator_ambiguous' => '$androidAutoRun --json',
    'android.device_missing' => '$androidAutoRun --json',
    'android.device_not_found' ||
    'android.device_ambiguous' => 'fluoh devices --platform android',
    'ios.build_failed' ||
    'ios.launch_timeout' ||
    'ios.run_failed' ||
    'ios.runtime_crash' ||
    'ios.integration_test_failed' => '$iosAutoRun --json',
    'ios.devices_failed' ||
    'ios.emulators_failed' ||
    'ios.emulator_missing' ||
    'ios.emulator_start_failed' => 'fluoh doctor --platform ios --json',
    'ios.emulator_not_found' ||
    'ios.emulator_ambiguous' => '$iosAutoRun --json',
    'ios.device_missing' => '$iosAutoRun --json',
    'ios.device_not_found' ||
    'ios.device_ambiguous' => 'fluoh devices --platform ios',
    'macos.build_failed' ||
    'macos.launch_timeout' ||
    'macos.run_failed' ||
    'macos.runtime_crash' ||
    'macos.integration_test_failed' => '$macosRun --json',
    'macos.devices_failed' ||
    'macos.emulators_failed' ||
    'macos.emulator_missing' ||
    'macos.emulator_start_failed' => 'fluoh doctor --platform macos --json',
    'macos.emulator_not_found' ||
    'macos.emulator_ambiguous' => '$macosRun --json',
    'macos.device_missing' => '$macosRun --json',
    'macos.device_not_found' ||
    'macos.device_ambiguous' => 'fluoh devices --platform macos',
    'linux.build_failed' ||
    'linux.launch_timeout' ||
    'linux.run_failed' ||
    'linux.runtime_crash' ||
    'linux.integration_test_failed' => '$linuxRun --json',
    'linux.devices_failed' ||
    'linux.emulators_failed' ||
    'linux.emulator_missing' ||
    'linux.emulator_start_failed' => 'fluoh doctor --platform linux --json',
    'linux.emulator_not_found' ||
    'linux.emulator_ambiguous' => '$linuxRun --json',
    'linux.device_missing' => '$linuxRun --json',
    'linux.device_not_found' ||
    'linux.device_ambiguous' => 'fluoh devices --platform linux',
    'web.build_failed' ||
    'web.launch_timeout' ||
    'web.run_failed' ||
    'web.runtime_crash' ||
    'web.integration_test_failed' => '$webRun --json',
    'web.devices_failed' ||
    'web.emulators_failed' ||
    'web.emulator_missing' ||
    'web.emulator_start_failed' => 'fluoh doctor --platform web --json',
    'web.emulator_not_found' || 'web.emulator_ambiguous' => '$webRun --json',
    'web.device_missing' => '$webRun --json',
    'web.device_not_found' ||
    'web.device_ambiguous' => 'fluoh devices --platform web',
    'windows.build_failed' ||
    'windows.launch_timeout' ||
    'windows.run_failed' ||
    'windows.runtime_crash' ||
    'windows.integration_test_failed' => '$windowsRun --json',
    'windows.devices_failed' ||
    'windows.emulators_failed' ||
    'windows.emulator_missing' ||
    'windows.emulator_start_failed' => 'fluoh doctor --platform windows --json',
    'windows.emulator_not_found' ||
    'windows.emulator_ambiguous' => '$windowsRun --json',
    'windows.device_missing' => '$windowsRun --json',
    'windows.device_not_found' ||
    'windows.device_ambiguous' => 'fluoh devices --platform windows',
    _ => null,
  };
}

String _packageRunNextCommand({
  required String packageName,
  required String platform,
  required String? deviceId,
  required bool startEmulator,
  required String? emulatorName,
}) {
  final useDefaultWebServer =
      platform == 'web' && deviceId == null && emulatorName == null;
  return [
    'fluoh run $platform --package $packageName',
    if (deviceId != null) '--device-id $deviceId',
    if (useDefaultWebServer) '--device-id web-server',
    if (startEmulator &&
        emulatorName == null &&
        !_isDesktopRunPlatform(platform))
      '--auto-emulator',
    if (emulatorName != null) '--emulator $emulatorName',
    '--json',
  ].join(' ');
}

bool _isDesktopRunPlatform(String platform) {
  return platform == 'macos' ||
      platform == 'linux' ||
      platform == 'web' ||
      platform == 'windows';
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

bool _isStaleIosPrecompiledHeaderFailure(SelectedToolResult result) {
  final output = result.combinedOutput.toLowerCase();
  return output.contains('precompiled header') &&
      output.contains('has been modified since');
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
