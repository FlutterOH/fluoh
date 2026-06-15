part of 'workflow_commands.dart';

Future<List<WorkflowTargetResult>> _runPackageOrProject({
  required FluohEnvironment environment,
  required String? packageName,
  required TerminalOutput output,
  required OutputWriter stdout,
  required OutputWriter stderr,
  required String usage,
  _PackageWorkflowInvocation Function(PackageManifestPackage package)?
  invocationForPackage,
  _ProjectWorkflowInvocation? projectInvocation,
  Duration deviceTimeout = const Duration(seconds: 90),
  Duration logDuration = const Duration(seconds: 8),
}) async {
  final manifest = await _readOptionalPackageManifest(environment);
  if (manifest == null) {
    if (packageName != null) {
      throw UsageException(
        'Current directory is not a package repository.',
        usage,
      );
    }
    return [
      await _runProjectWorkflow(
        environment: environment,
        output: output,
        stdout: stdout,
        stderr: stderr,
        usage: usage,
        invocation:
            projectInvocation ?? const _ProjectWorkflowInvocation.baseline(),
        deviceTimeout: deviceTimeout,
        logDuration: logDuration,
      ),
    ];
  }

  final packages = [manifest.packageForName(packageName)];
  final results = <WorkflowTargetResult>[];
  for (final package in packages) {
    final invocation =
        invocationForPackage?.call(package) ??
        const _PackageWorkflowInvocation(phase: 'baseline');
    output.step(invocation.stepMessage(package.name));
    final result = await runPackageWorkflow(
      environment: environment,
      manifest: manifest,
      package: package,
      stdout: stdout,
      stderr: stderr,
      output: output,
      usage: usage,
      buildExampleTarget: invocation.buildExampleTarget,
      runExampleTarget: invocation.runExampleTarget,
      buildExampleDebug: invocation.debug,
      buildExampleForSimulator: invocation.buildExampleForSimulator,
      autoSignExample: invocation.autoSign,
      runExample: invocation.runExample,
      deviceId: invocation.deviceId,
      startEmulator: invocation.startEmulator,
      emulatorName: invocation.emulatorName,
      sessionFile: invocation.sessionFile,
      ohosPermissionDialogPolicy: invocation.ohosPermissionDialogPolicy,
      deviceTimeout: deviceTimeout,
      logDuration: logDuration,
      phase: invocation.phase,
    );
    results.add(result);
    if (!result.passed) {
      return results;
    }
  }
  return results;
}

Future<PackageManifest?> _readOptionalPackageManifest(
  FluohEnvironment environment,
) async {
  final file = File('${environment.workingDirectory.path}/fluoh.yaml');
  if (!await file.exists()) {
    return null;
  }
  final content = await file.readAsString();
  final yaml = parseYamlMap(content, label: 'fluoh.yaml');
  if (!yaml.containsKey('packages') &&
      !yaml.containsKey('repository') &&
      !yaml.containsKey('upstream')) {
    return null;
  }
  return readPackageManifest(environment.workingDirectory);
}

class _PackageWorkflowInvocation {
  const _PackageWorkflowInvocation({
    required this.phase,
    this.buildExampleTarget,
    this.runExampleTarget,
    this.debug = false,
    this.buildExampleForSimulator = false,
    this.autoSign = false,
    this.runExample = false,
    this.deviceId,
    this.startEmulator = false,
    this.emulatorName,
    this.sessionFile,
    this.ohosPermissionDialogPolicy = OhosSystemPermissionDialogPolicy.disabled,
  });

  final String phase;
  final String? buildExampleTarget;
  final String? runExampleTarget;
  final bool debug;
  final bool buildExampleForSimulator;
  final bool autoSign;
  final bool runExample;
  final String? deviceId;
  final bool startEmulator;
  final String? emulatorName;
  final File? sessionFile;
  final OhosSystemPermissionDialogPolicy ohosPermissionDialogPolicy;

  String stepMessage(String packageName) {
    if (phase == 'baseline') {
      return 'Verifying $packageName';
    }
    if (phase.endsWith('-build')) {
      return 'Building $packageName ($phase)';
    }
    if (phase.endsWith('-run')) {
      return 'Running $packageName ($phase)';
    }
    return 'Running $packageName ($phase)';
  }
}

class _ProjectWorkflowInvocation {
  const _ProjectWorkflowInvocation.baseline()
    : kind = 'baseline',
      platform = null,
      debug = false,
      autoSign = false,
      deviceId = null,
      startEmulator = false,
      emulatorName = null,
      sessionFile = null,
      ohosPermissionDialogPolicy = OhosSystemPermissionDialogPolicy.disabled;

  const _ProjectWorkflowInvocation.build({
    required this.platform,
    required this.debug,
    required this.autoSign,
  }) : kind = 'build',
       deviceId = null,
       startEmulator = false,
       emulatorName = null,
       sessionFile = null,
       ohosPermissionDialogPolicy = OhosSystemPermissionDialogPolicy.disabled;

  const _ProjectWorkflowInvocation.run({
    required this.platform,
    required this.deviceId,
    required this.startEmulator,
    required this.emulatorName,
    required this.sessionFile,
    required this.autoSign,
    required this.ohosPermissionDialogPolicy,
  }) : kind = 'run',
       debug = true;

  final String kind;
  final String? platform;
  final bool debug;
  final bool autoSign;
  final String? deviceId;
  final bool startEmulator;
  final String? emulatorName;
  final File? sessionFile;
  final OhosSystemPermissionDialogPolicy ohosPermissionDialogPolicy;
}

Future<WorkflowTargetResult> _runProjectWorkflow({
  required FluohEnvironment environment,
  required TerminalOutput output,
  required OutputWriter stdout,
  required OutputWriter stderr,
  required String usage,
  required _ProjectWorkflowInvocation invocation,
  Duration deviceTimeout = const Duration(seconds: 90),
  Duration logDuration = const Duration(seconds: 8),
}) async {
  final project = environment.workingDirectory;
  final pubspec = File('${project.path}/pubspec.yaml');
  if (!await pubspec.exists()) {
    throw UsageException('Missing pubspec.yaml.', usage);
  }
  final isFlutter = await isFlutterPackageDirectory(project);
  final steps = <WorkflowStepResult>[];

  Future<bool> runTool(List<String> arguments, String name) async {
    final result = isFlutter
        ? await runSelectedFlutterResult(
            environment: environment,
            arguments: arguments,
            workingDirectory: project,
            stdout: stdout,
            stderr: stderr,
            output: output,
            usage: usage,
          )
        : await runSelectedDartResult(
            environment: environment,
            arguments: arguments,
            workingDirectory: project,
            stdout: stdout,
            stderr: stderr,
            output: output,
            usage: usage,
          );
    steps.add(
      _toolStep(
        name: name,
        path: '.',
        flutter: isFlutter,
        arguments: arguments,
        result: result,
        diagnosticCode: _projectBaselineDiagnosticCode(name),
        diagnosticMessage: _projectBaselineDiagnosticMessage(name),
        nextCommand: 'fluoh verify --json',
      ),
    );
    return result.exitCode == 0;
  }

  if (invocation.kind == 'baseline') {
    output.step('Running baseline verification in current project');
    if (!await runTool(const ['pub', 'get'], 'project-pub-get')) {
      return WorkflowTargetResult.project(
        projectName: 'current',
        exitCode: _lastExitCode(steps),
        steps: steps,
        phase: 'baseline',
      );
    }
    if (!await runTool(const ['analyze'], 'project-analyze')) {
      return WorkflowTargetResult.project(
        projectName: 'current',
        exitCode: _lastExitCode(steps),
        steps: steps,
        phase: 'baseline',
      );
    }
    if (await hasPackageTests(project)) {
      if (!await runTool(const ['test'], 'project-test')) {
        return WorkflowTargetResult.project(
          projectName: 'current',
          exitCode: _lastExitCode(steps),
          steps: steps,
          phase: 'baseline',
        );
      }
    } else {
      steps.add(
        const WorkflowStepResult(
          name: 'project-test',
          path: '.',
          command: 'test',
          status: 'skipped',
          reason: 'no test files',
        ),
      );
    }
    if (await hasIntegrationTests(project)) {
      output.skipped(
        'Discovered project integration tests: run a platform target to execute them on a device',
      );
      steps.add(
        _projectIntegrationDiscoveryStep(
          name: 'project-integration',
          path: '.',
        ),
      );
    }
    return WorkflowTargetResult.project(
      projectName: 'current',
      exitCode: 0,
      steps: steps,
      phase: 'baseline',
    );
  }

  if (!isFlutter) {
    throw UsageException('Build and run require a Flutter project.', usage);
  }
  final platform = invocation.platform!;
  final policy = platformWorkflowPolicy(platform);
  if (invocation.kind == 'run') {
    final preparation = await preparePlatformRun(
      platform: platform,
      environment: environment,
      projectDirectory: project,
      displayPath: '.',
      output: output,
      usage: usage,
      autoSign: invocation.autoSign,
      doctorNextCommand: policy.doctorCommand(project: true),
      buildNextCommand: policy.buildCommand(autoSign: invocation.autoSign),
    );
    steps.addAll(preparation.steps);
    if (!preparation.passed) {
      steps.add(preparation.failureStep!);
      return WorkflowTargetResult.project(
        projectName: 'current',
        exitCode: 1,
        steps: steps,
        phase: 'run-$platform',
      );
    }
    final FlutterExampleRunResult runResult;
    try {
      runResult = await runFlutterExampleOnDevice(
        environment: environment,
        exampleDirectory: project,
        buildExampleTarget: policy.buildTarget,
        output: output,
        stdout: stdout,
        stderr: stderr,
        deviceId: invocation.deviceId,
        startEmulator: invocation.startEmulator,
        emulatorName: invocation.emulatorName,
        sessionFile: invocation.sessionFile,
        deviceTimeout: deviceTimeout,
        runDuration: logDuration,
        usage: usage,
      );
      final postLaunchScreenshot = runResult.passed && runResult.target != null
          ? await captureMobilePostLaunchScreenshot(
              environment: environment,
              platform: runResult.platform,
              targetId: runResult.target!.id,
              scopeName: 'current',
            )
          : null;
      steps.add(
        WorkflowStepResult(
          name: 'project-run-${runResult.platform}',
          path: '.',
          command: runResult.command,
          status: runResult.passed ? 'passed' : 'failed',
          exitCode: runResult.exitCode,
          reason: runResult.reason,
          details: {
            ...runResult.details,
            ...preparation.details,
            'platform': runResult.platform,
            if (runResult.target != null) 'targetId': runResult.target!.id,
            if (runResult.target != null) 'target': runResult.target!.toJson(),
            if (runResult.emulator != null)
              'emulator': runResult.emulator!.toJson(),
            if (runResult.outputLog != null)
              'outputLog': runResult.outputLog!.path,
            if (postLaunchScreenshot != null)
              'postLaunchScreenshot': postLaunchScreenshot.toJson(),
          },
          diagnostics: runResult.diagnostics
              .map(
                (diagnostic) => WorkflowDiagnostic(
                  code: diagnostic.code,
                  severity: diagnostic.severity,
                  message: diagnostic.message,
                  details: diagnostic.details,
                  nextCommand: _projectNextCommandForDiagnosticCode(
                    diagnostic.code,
                    invocation,
                  ),
                ),
              )
              .toList(),
        ),
      );
      if (!runResult.passed) {
        return WorkflowTargetResult.project(
          projectName: 'current',
          exitCode: runResult.exitCode,
          steps: steps,
          phase: 'run-$platform',
        );
      }
      final integrationExitCode = await _appendProjectIntegrationRunSteps(
        environment: environment,
        project: project,
        platform: runResult.platform,
        targetId: runResult.target?.id,
        stdout: stdout,
        stderr: stderr,
        output: output,
        usage: usage,
        steps: steps,
        nextCommand: _projectRunNextCommand(invocation),
        ohosPermissionDialogPolicy: invocation.ohosPermissionDialogPolicy,
      );
      return WorkflowTargetResult.project(
        projectName: 'current',
        exitCode: integrationExitCode ?? runResult.exitCode,
        steps: steps,
        phase: 'run-$platform',
      );
    } finally {
      await preparation.restoreIfNeeded();
    }
  }

  final buildPreparation = await preparePlatformBuild(
    platform: platform,
    environment: environment,
    projectDirectory: project,
    displayPath: '.',
    displayLabel: 'current project',
    output: output,
    usage: usage,
    autoSign: invocation.autoSign,
    nextCommandForDiagnostic: (code) =>
        _projectBuildPreparationNextCommand(code, policy),
  );
  if (!buildPreparation.passed) {
    steps.add(buildPreparation.failureStep!);
    return WorkflowTargetResult.project(
      projectName: 'current',
      exitCode: 1,
      steps: steps,
      phase: 'build-$platform',
    );
  }
  var signingMode = '';
  if (invocation.autoSign) {
    signingMode = 'build-profile';
  }

  final arguments = [
    'build',
    policy.buildTarget,
    if (invocation.debug) '--debug',
    if (policy.buildWithoutCodesign) '--no-codesign',
  ];
  output.step('Running flutter ${arguments.join(' ')} in current project');
  final SelectedToolResult result;
  var effectiveExitCode = 1;
  var installableArtifactPaths = <String>[];
  final postBuildSteps = <WorkflowStepResult>[];
  try {
    final buildStartedAt = DateTime.now().subtract(const Duration(seconds: 1));
    result = await runSelectedFlutterResult(
      environment: environment,
      arguments: arguments,
      workingDirectory: project,
      stdout: stdout,
      stderr: stderr,
      output: output,
      usage: usage,
    );
    effectiveExitCode = result.exitCode;
    if (effectiveExitCode != 0) {
      final recovery = await buildPreparation.recoverFailedBuild(
        buildResult: result,
        modifiedAfter: buildStartedAt,
      );
      if (recovery.failureStep != null) {
        steps.addAll(buildPreparation.steps);
        steps.add(recovery.failureStep!);
        return WorkflowTargetResult.project(
          projectName: 'current',
          exitCode: 1,
          steps: steps,
          phase: '${invocation.kind}-$platform',
        );
      }
      if (recovery.recovered) {
        postBuildSteps.addAll(recovery.steps);
        installableArtifactPaths = recovery.artifactPaths;
        signingMode = recovery.signingMode ?? signingMode;
        effectiveExitCode = 0;
      }
    }
    if (effectiveExitCode == 0) {
      final artifacts = await buildPreparation.collectSuccessfulBuildArtifacts(
        modifiedAfter: buildStartedAt,
      );
      if (artifacts.artifactPaths.isNotEmpty) {
        installableArtifactPaths = artifacts.artifactPaths;
      }
    }
  } finally {
    await buildPreparation.restoreIfNeeded();
  }
  steps.addAll(buildPreparation.steps);
  steps.addAll(postBuildSteps);
  steps.add(
    _toolStep(
      name: 'project-${invocation.kind}-$platform',
      path: '.',
      flutter: true,
      arguments: arguments,
      result: SelectedToolResult(
        exitCode: effectiveExitCode,
        stdout: result.stdout,
        stderr: result.stderr,
      ),
      diagnosticCode: _projectPlatformDiagnosticCode(
        kind: invocation.kind,
        platform: platform,
      ),
      diagnosticMessage: _projectPlatformDiagnosticMessage(
        kind: invocation.kind,
        platform: platform,
      ),
      nextCommand: _projectPlatformNextCommand(invocation),
      extraDetails: {
        if (installableArtifactPaths.isNotEmpty)
          'installableHaps': installableArtifactPaths,
        if (signingMode.isNotEmpty) 'signingMode': signingMode,
      },
    ),
  );
  return WorkflowTargetResult.project(
    projectName: 'current',
    exitCode: effectiveExitCode,
    steps: steps,
    phase: '${invocation.kind}-$platform',
  );
}

WorkflowStepResult _projectIntegrationDiscoveryStep({
  required String name,
  required String path,
}) {
  return WorkflowStepResult(
    name: name,
    path: path,
    command: 'flutter test integration_test -d <device>',
    status: 'skipped',
    reason: 'requires a platform run target',
    details: {
      'testDirectory': 'integration_test',
      'interactionEvidence': {
        'status': 'available',
        'method': 'integration_test',
        'execution': 'run fluoh run with a concrete platform and device',
      },
      'suggestedCommands': integrationDiscoveryRunCommands(),
      'manualAssistedFallback': {
        'when':
            'system UI, permissions, pickers, external apps, or platform tooling gaps block automatic execution',
        'requiredEvidence':
            'record user steps plus tool-verified logs, session status, stable text, semantics, or app log markers',
      },
    },
  );
}

Future<int?> _appendProjectIntegrationRunSteps({
  required FluohEnvironment environment,
  required Directory project,
  required String platform,
  required String? targetId,
  required OutputWriter stdout,
  required OutputWriter stderr,
  required TerminalOutput output,
  required String usage,
  required List<WorkflowStepResult> steps,
  required String nextCommand,
  required OhosSystemPermissionDialogPolicy ohosPermissionDialogPolicy,
}) async {
  if (!await hasIntegrationTests(project)) {
    return null;
  }
  if (targetId == null) {
    steps.add(
      WorkflowStepResult(
        name: 'project-integration-$platform',
        path: '.',
        command: 'flutter test integration_test -d <device>',
        status: 'skipped',
        reason: 'run target did not expose a device id',
        details: {
          'platform': platform,
          'interactionEvidence': {
            'status': 'blocked',
            'method': 'integration_test',
            'reason': 'missing target id',
          },
        },
      ),
    );
    output.skipped(
      'Skipping $platform integration tests in current project: missing target id',
    );
    return null;
  }
  final arguments = ['test', 'integration_test', '-d', targetId];
  output.step('Running flutter ${arguments.join(' ')} in current project');
  final permissionDialogWatcher = platform == 'ohos'
      ? await OhosSystemPermissionDialogWatcher.start(
          environment: environment,
          targetId: targetId,
          policy: ohosPermissionDialogPolicy,
          output: output,
        )
      : null;
  late final SelectedToolResult result;
  OhosSystemPermissionDialogSummary? permissionDialogs;
  try {
    result = await runSelectedFlutterResult(
      environment: environment,
      arguments: arguments,
      workingDirectory: project,
      stdout: stdout,
      stderr: stderr,
      output: output,
      usage: usage,
    );
  } finally {
    permissionDialogs = await permissionDialogWatcher?.stop();
  }
  final command = 'flutter ${arguments.join(' ')}';
  steps.add(
    WorkflowStepResult(
      name: 'project-integration-$platform',
      path: '.',
      command: command,
      status: result.exitCode == 0 ? 'passed' : 'failed',
      exitCode: result.exitCode,
      details: {
        'platform': platform,
        'targetId': targetId,
        'interactionEvidence': {
          'method': 'integration_test',
          'status': result.exitCode == 0 ? 'passed' : 'failed',
          'testDirectory': 'integration_test',
        },
        if (permissionDialogs != null && permissionDialogs.hasEvidence)
          'systemPermissionDialogs': permissionDialogs.toJson(),
        ..._toolOutputDetails(result),
      },
      diagnostics: result.exitCode == 0
          ? const []
          : [
              WorkflowDiagnostic(
                code: _projectIntegrationDiagnosticCode(platform),
                message:
                    '${_platformLabel(platform)} integration tests failed.',
                details: {
                  'command': command,
                  'exitCode': result.exitCode,
                  ..._toolOutputDetails(result),
                },
                nextCommand: nextCommand,
              ),
            ],
    ),
  );
  if (result.exitCode != 0) {
    output.failure(
      '${_platformLabel(platform)} integration tests failed in current project',
    );
    return result.exitCode;
  }
  output.success(
    '${_platformLabel(platform)} integration tests passed in current project',
  );
  return null;
}

String _projectIntegrationDiagnosticCode(String platform) {
  return platformWorkflowPolicy(platform).integrationTestDiagnosticCode;
}

String _platformLabel(String platform) {
  return platformWorkflowPolicy(platform).label;
}

String? _projectBuildPreparationNextCommand(
  String code,
  PlatformWorkflowPolicy policy,
) {
  return switch (code) {
    'ohos.ohos_project_missing' => policy.doctorCommand(project: true),
    'ohos.build_profile_patch_failed' ||
    'ohos.direct_sign_failed' => policy.buildCommand(autoSign: true),
    _ => policy.doctorCommand(),
  };
}

WorkflowStepResult _toolStep({
  required String name,
  required String path,
  required bool flutter,
  required List<String> arguments,
  required SelectedToolResult result,
  String? diagnosticCode,
  String? diagnosticMessage,
  String? nextCommand,
  Map<String, Object?> extraDetails = const {},
}) {
  final command = '${flutter ? 'flutter' : 'dart'} ${arguments.join(' ')}';
  return WorkflowStepResult(
    name: name,
    path: path,
    command: command,
    status: result.exitCode == 0 ? 'passed' : 'failed',
    exitCode: result.exitCode,
    details: {..._toolOutputDetails(result), ...extraDetails},
    diagnostics: result.exitCode == 0
        ? const []
        : [
            WorkflowDiagnostic(
              code: diagnosticCode ?? 'command.failed',
              message: diagnosticMessage ?? 'Command failed.',
              details: {
                'command': command,
                'exitCode': result.exitCode,
                ..._toolOutputDetails(result),
              },
              nextCommand: nextCommand ?? 'fluoh verify --json',
            ),
          ],
  );
}

Map<String, Object?> _toolOutputDetails(SelectedToolResult result) {
  return {
    if (result.stdout.trim().isNotEmpty) 'stdoutTail': result.stdout,
    if (result.stderr.trim().isNotEmpty) 'stderrTail': result.stderr,
    if (result.combinedOutput.trim().isNotEmpty)
      'outputTail': result.combinedOutput,
  };
}

String _projectBaselineDiagnosticCode(String stepName) {
  return switch (stepName) {
    'project-pub-get' => 'dart.pub_get_failed',
    'project-analyze' => 'dart.analysis_failed',
    'project-test' => 'dart.test_failed',
    _ => 'command.failed',
  };
}

String _projectBaselineDiagnosticMessage(String stepName) {
  return switch (stepName) {
    'project-pub-get' => 'Dependency resolution failed.',
    'project-analyze' => 'Static analysis failed.',
    'project-test' => 'Tests failed.',
    _ => 'Command failed.',
  };
}

String _projectPlatformDiagnosticCode({
  required String kind,
  required String platform,
}) {
  return platformWorkflowPolicy(platform).diagnosticCode(kind: kind);
}

String _projectPlatformDiagnosticMessage({
  required String kind,
  required String platform,
}) {
  return platformWorkflowPolicy(platform).diagnosticMessage(kind: kind);
}

String _projectPlatformNextCommand(_ProjectWorkflowInvocation invocation) {
  final platform = invocation.platform!;
  if (invocation.kind == 'run') {
    return _projectRunNextCommand(invocation);
  }
  return platformWorkflowPolicy(
    platform,
  ).buildCommand(debug: invocation.debug, autoSign: invocation.autoSign);
}

String? _projectNextCommandForDiagnosticCode(
  String code,
  _ProjectWorkflowInvocation invocation,
) {
  final platform = invocation.platform!;
  final runCommand = _projectPlatformNextCommand(invocation);
  final autoEmulatorRunCommand = _projectRunNextCommand(
    invocation,
    startEmulator: true,
  );
  return platformWorkflowPolicy(platform).projectRepairCommand(
    code,
    currentCommand: runCommand,
    autoEmulatorCommand: autoEmulatorRunCommand,
  );
}

String _projectRunNextCommand(
  _ProjectWorkflowInvocation invocation, {
  bool? startEmulator,
}) {
  final platform = invocation.platform!;
  return platformWorkflowPolicy(platform).runCommand(
    deviceId: invocation.deviceId,
    startEmulator: startEmulator ?? invocation.startEmulator,
    emulatorName: invocation.emulatorName,
  );
}
