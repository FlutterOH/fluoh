import 'dart:io';

import 'package:args/command_runner.dart';

import '../cli/fluoh_command_runner.dart';
import '../cli/terminal_output.dart';
import '../context/fluoh_environment.dart';
import '../sdk/flutter_runner.dart';
import '../workflow/platform_build_preparation.dart';
import '../workflow/platform_run_preparation.dart';
import '../workflow/platform_workflow_policy.dart';
import '../workflow/mobile_run_evidence.dart';
import '../workflow/workflow_result.dart';
import '../platform/ohos/system_permission_dialog_watcher.dart';
import 'flutter_example_runner.dart';
import 'manifest/package_manifest.dart';
import 'manifest/pubspec_package.dart';
import 'package_examples.dart';

part 'package_workflow_steps.dart';

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
  String? runExampleTarget,
  bool buildExampleDebug = false,
  bool buildExampleForSimulator = false,
  bool autoSignExample = false,
  bool runExample = false,
  String? deviceId,
  bool startEmulator = false,
  String? emulatorName,
  File? sessionFile,
  OhosSystemPermissionDialogPolicy ohosPermissionDialogPolicy =
      OhosSystemPermissionDialogPolicy.disabled,
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
    final buildPolicy = platformWorkflowPolicy(
      _platformForExampleTarget(buildExampleTarget),
    );
    final buildArguments = buildPolicy.buildExampleArguments(
      debug: buildExampleDebug,
      forSimulator: buildExampleForSimulator,
    );
    var installableArtifactPaths = <String>[];
    String? signingMode;
    if (autoSignExample && !buildPolicy.supportsAutoSign) {
      throw UsageException(
        'Automatic signing is not supported for this build target.',
        usage,
      );
    }
    final buildPreparation = await preparePlatformBuild(
      platform: buildPolicy.platform,
      environment: environment,
      projectDirectory: example,
      displayPath: examplePath,
      displayLabel: package.name,
      output: output,
      usage: usage,
      autoSign: autoSignExample,
      nextCommandForDiagnostic: (code) => _buildNextCommandForDiagnosticCode(
        code: code,
        packageName: package.name,
        policy: buildPolicy,
        debug: buildExampleDebug,
        autoSign: autoSignExample,
      ),
    );
    steps.addAll(buildPreparation.steps);
    if (!buildPreparation.passed) {
      steps.add(buildPreparation.failureStep!);
      return WorkflowTargetResult.package(
        packageName: package.name,
        exitCode: 1,
        steps: steps,
        preset: preset,
        phase: phase,
      );
    }
    if (autoSignExample) {
      signingMode = 'build-profile';
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
          buildPolicy.retriesStalePrecompiledHeaderBuildCache &&
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
      if (exampleBuildExitCode != 0) {
        final recovery = await buildPreparation.recoverFailedBuild(
          buildResult: exampleBuild,
          modifiedAfter: buildStartedAt,
        );
        if (recovery.failureStep != null) {
          steps.add(recovery.failureStep!);
          return WorkflowTargetResult.package(
            packageName: package.name,
            exitCode: 1,
            steps: steps,
            preset: preset,
            phase: phase,
          );
        }
        if (recovery.recovered) {
          steps.addAll(recovery.steps);
          installableArtifactPaths = recovery.artifactPaths;
          signingMode = recovery.signingMode;
          exampleBuildExitCode = 0;
        }
      }
      if (exampleBuildExitCode == 0) {
        final artifacts = await buildPreparation
            .collectSuccessfulBuildArtifacts(modifiedAfter: buildStartedAt);
        if (artifacts.artifactPaths.isNotEmpty) {
          installableArtifactPaths = artifacts.artifactPaths;
        }
      }
    } finally {
      await buildPreparation.restoreIfNeeded();
    }
    final buildDetails = <String, Object?>{
      if (installableArtifactPaths.isNotEmpty)
        'installableHaps': installableArtifactPaths,
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
        nextCommand: buildPolicy.buildCommand(
          packageName: package.name,
          debug: buildExampleDebug,
          autoSign: autoSignExample,
        ),
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
  }
  final effectiveRunExampleTarget = runExampleTarget ?? buildExampleTarget;
  if (runExample && effectiveRunExampleTarget != null) {
    final runPlatform = platformWorkflowPolicy(
      _platformForExampleTarget(effectiveRunExampleTarget),
    );
    final preparation = await preparePlatformRun(
      platform: runPlatform.platform,
      environment: environment,
      projectDirectory: example,
      displayPath: examplePath,
      output: output,
      usage: usage,
      autoSign: autoSignExample,
      doctorNextCommand: runPlatform.doctorCommand(project: true),
      buildNextCommand: runPlatform.buildCommand(
        packageName: package.name,
        autoSign: autoSignExample,
      ),
    );
    steps.addAll(preparation.steps);
    if (!preparation.passed) {
      steps.add(preparation.failureStep!);
      return WorkflowTargetResult.package(
        packageName: package.name,
        exitCode: 1,
        steps: steps,
        preset: preset,
        phase: phase,
      );
    }
    final FlutterExampleRunResult runResult;
    try {
      runResult = await runFlutterExampleOnDevice(
        environment: environment,
        exampleDirectory: example,
        buildExampleTarget: effectiveRunExampleTarget,
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
      final postLaunchScreenshot = runResult.passed && runResult.target != null
          ? await captureMobilePostLaunchScreenshot(
              environment: environment,
              platform: runResult.platform,
              targetId: runResult.target!.id,
              scopeName: package.name,
            )
          : null;
      final runDetails = <String, Object?>{
        ...runResult.details,
        ...preparation.details,
        'platform': runResult.platform,
        if (runResult.target != null) 'targetId': runResult.target!.id,
        if (runResult.target != null) 'target': runResult.target!.toJson(),
        if (runResult.emulator != null)
          'emulator': runResult.emulator!.toJson(),
        if (runResult.outputLog != null) 'outputLog': runResult.outputLog!.path,
        if (postLaunchScreenshot != null)
          'postLaunchScreenshot': postLaunchScreenshot.toJson(),
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
      if (exampleHasIntegrationTests && targetId != null) {
        final integrationArguments = [
          'test',
          'integration_test',
          '-d',
          targetId,
        ];
        final permissionDialogWatcher = runResult.platform == 'ohos'
            ? await OhosSystemPermissionDialogWatcher.start(
                environment: environment,
                targetId: targetId,
                policy: ohosPermissionDialogPolicy,
                output: output,
              )
            : null;
        late final SelectedToolResult integrationTest;
        OhosSystemPermissionDialogSummary? permissionDialogs;
        try {
          integrationTest = await _runToolCommand(
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
        } finally {
          permissionDialogs = await permissionDialogWatcher?.stop();
        }
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
              if (permissionDialogs != null && permissionDialogs.hasEvidence)
                'systemPermissionDialogs': permissionDialogs.toJson(),
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
    } finally {
      await preparation.restoreIfNeeded();
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
