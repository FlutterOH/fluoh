part of 'workflow_commands.dart';

File _resolveOutputFile(Directory workingDirectory, String path) {
  final file = File(path);
  if (file.isAbsolute) {
    return file;
  }
  return File('${workingDirectory.path}/$path');
}

Directory _resolveOutputDirectory(Directory workingDirectory, String path) {
  final directory = Directory(path);
  if (directory.isAbsolute) {
    return directory;
  }
  return Directory('${workingDirectory.path}/$path');
}

Future<List<AutomationScenario>> _readAutomationScenarios(
  List<String> paths, {
  required Directory workingDirectory,
  required UsageError usageException,
}) async {
  final scenarios = <AutomationScenario>[];
  for (final path in paths) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      usageException('Use a non-empty path for --scenario.');
    }
    try {
      scenarios.add(
        await readAutomationScenario(
          File(trimmed),
          workingDirectory: workingDirectory,
        ),
      );
    } on FileSystemException catch (error) {
      usageException('Could not read scenario $trimmed: ${error.message}');
    } on FormatException catch (error) {
      usageException(error.message);
    }
  }
  return scenarios;
}

void _validateAutomationScenarios(
  List<AutomationScenario> scenarios,
  List<String> platforms,
  UsageError usageException,
) {
  const supportedPlatforms = {'ohos', 'android', 'ios'};
  for (final scenario in scenarios) {
    if (!supportedPlatforms.contains(scenario.platform)) {
      usageException(
        'Scenario ${scenario.path.path} uses unsupported platform ${scenario.platform}.',
      );
    }
    if (!platforms.contains(scenario.platform)) {
      usageException(
        'Scenario ${scenario.path.path} targets ${scenario.platform}, which is not included by the drive platform.',
      );
    }
  }
}

List<String> _drivePlatformsFromArgument(String value) {
  return switch (value) {
    'all' => const ['ohos', 'android', 'ios'],
    'ohos' || 'android' || 'ios' => [value],
    _ => throw ArgumentError.value(value, 'platform', 'Unsupported platform.'),
  };
}

_PackageWorkflowInvocation _automationPackageInvocation({
  required String platform,
  required String packageName,
  required String? deviceId,
  required String? emulatorName,
  required bool autoEmulator,
  required Directory sessionDirectory,
}) {
  final policy = platformWorkflowPolicy(platform);
  final startEmulator = _automationStartsEmulator(
    platform: platform,
    deviceId: deviceId,
    emulatorName: emulatorName,
    autoEmulator: autoEmulator,
  );
  return _PackageWorkflowInvocation(
    phase: '$platform-run',
    buildExampleTarget: policy.runPrebuildTarget,
    runExampleTarget: policy.buildTarget,
    debug: true,
    buildExampleForSimulator: policy.buildExampleForSimulator(
      deviceId: deviceId,
      startEmulator: startEmulator,
    ),
    autoSign: policy.supportsAutoSign,
    runExample: true,
    deviceId: deviceId,
    startEmulator: startEmulator,
    emulatorName: emulatorName,
    sessionFile: _automationSessionFile(
      platform: platform,
      targetName: packageName,
      sessionDirectory: sessionDirectory,
    ),
  );
}

_ProjectWorkflowInvocation _automationProjectInvocation({
  required String platform,
  required String? deviceId,
  required String? emulatorName,
  required bool autoEmulator,
  required Directory sessionDirectory,
}) {
  return _ProjectWorkflowInvocation.run(
    platform: platform,
    deviceId: deviceId,
    startEmulator: _automationStartsEmulator(
      platform: platform,
      deviceId: deviceId,
      emulatorName: emulatorName,
      autoEmulator: autoEmulator,
    ),
    emulatorName: emulatorName,
    sessionFile: _automationSessionFile(
      platform: platform,
      targetName: 'current',
      sessionDirectory: sessionDirectory,
    ),
    autoSign: platformWorkflowPolicy(platform).supportsAutoSign,
  );
}

List<AutomationScenario> _automationScenariosForPlatform(
  List<AutomationScenario> scenarios,
  String platform,
) {
  return [
    for (final scenario in scenarios)
      if (scenario.platform == platform) scenario,
  ];
}

Future<List<WorkflowTargetResult>> _runAutomationScenariosForPlatform(
  List<WorkflowTargetResult> results, {
  required List<AutomationScenario> scenarios,
  required String platform,
  required FluohEnvironment environment,
  required TerminalOutput output,
  required String? packageName,
  required bool all,
  required String? deviceId,
  required String? emulatorName,
  required bool autoEmulator,
  required Directory sessionDirectory,
  required TraceOptions traceOptions,
}) async {
  if (scenarios.isEmpty) {
    return results;
  }
  final updated = <WorkflowTargetResult>[];
  for (final target in results) {
    var current = target;
    for (final scenario in scenarios) {
      output.step(
        'Running ${_platformLabel(platform)} scenario ${scenario.name}',
      );
      final nextCommand = _automationScenarioNextCommand(
        scenario: scenario,
        platform: platform,
        targetKind: target.targetKind,
        packageName: packageName,
        targetName: target.targetName,
        all: all,
        deviceId: deviceId,
        emulatorName: emulatorName,
        autoEmulator: autoEmulator,
        sessionDirectory: sessionDirectory,
        traceOptions: traceOptions,
      );
      final scenarioResult = await runAutomationScenario(
        scenario: scenario,
        target: current,
        environment: environment,
        nextCommand: nextCommand,
      );
      current = _appendAutomationScenarioResult(
        current,
        scenarioResult,
        environment: environment,
        command: nextCommand,
      );
      if (!current.passed) {
        break;
      }
    }
    updated.add(current);
  }
  return updated;
}

WorkflowTargetResult _appendAutomationScenarioResult(
  WorkflowTargetResult target,
  AutomationScenarioRunResult result, {
  required FluohEnvironment environment,
  required String command,
}) {
  final steps = [
    ...target.steps,
    _automationScenarioStep(result, environment: environment, command: command),
  ];
  final exitCode = target.exitCode != 0 ? target.exitCode : result.exitCode;
  if (target.targetKind == 'package') {
    return WorkflowTargetResult.package(
      packageName: target.targetName,
      exitCode: exitCode,
      steps: steps,
      preset: target.preset,
      phase: target.phase,
    );
  }
  return WorkflowTargetResult.project(
    projectName: target.targetName,
    exitCode: exitCode,
    steps: steps,
    preset: target.preset,
    phase: target.phase,
  );
}

WorkflowStepResult _automationScenarioStep(
  AutomationScenarioRunResult result, {
  required FluohEnvironment environment,
  required String command,
}) {
  return WorkflowStepResult(
    name:
        'automation-scenario-${result.scenario.platform}-${_automationPathSlug(result.scenario.name)}',
    path: _automationScenarioStepPath(
      environment.workingDirectory,
      result.scenario.path.parent,
    ),
    command: command,
    status: result.status,
    exitCode: result.exitCode,
    reason: result.reason,
    details: result.toJson(),
    diagnostics: [if (result.diagnostic != null) result.diagnostic!],
  );
}

String _automationScenarioStepPath(Directory root, Directory directory) {
  final rootPath = root.absolute.path;
  final directoryPath = directory.absolute.path;
  if (directoryPath == rootPath) {
    return '.';
  }
  final prefix = '$rootPath${Platform.pathSeparator}';
  if (directoryPath.startsWith(prefix)) {
    return directoryPath.substring(prefix.length);
  }
  return directory.path;
}

String _automationScenarioNextCommand({
  required AutomationScenario scenario,
  required String platform,
  required String targetKind,
  required String? packageName,
  required String targetName,
  required bool all,
  required String? deviceId,
  required String? emulatorName,
  required bool autoEmulator,
  required Directory sessionDirectory,
  required TraceOptions traceOptions,
}) {
  final parts = [
    'fluoh',
    'drive',
    platform,
    if (packageName != null) ...[
      '--package',
      packageName,
    ] else if (all)
      '--all'
    else if (targetKind == 'package') ...[
      '--package',
      targetName,
    ],
    if (deviceId != null) ...['--device-id', deviceId],
    if (emulatorName != null) ...['--emulator', emulatorName],
    if (deviceId == null && emulatorName == null)
      autoEmulator ? '--auto-emulator' : '--no-auto-emulator',
    '--session-dir',
    sessionDirectory.path,
    '--scenario',
    scenario.path.path,
    if (traceOptions.enabled && traceOptions.directory == null) '--trace',
    if (traceOptions.directory != null) ...[
      '--trace-dir',
      traceOptions.directory!.path,
    ],
    '--json',
  ];
  return parts.map(_workflowShellQuote).join(' ');
}

bool _automationStartsEmulator({
  required String platform,
  required String? deviceId,
  required String? emulatorName,
  required bool autoEmulator,
}) {
  if (deviceId != null) {
    return false;
  }
  if (emulatorName != null) {
    return true;
  }
  return autoEmulator && !_isDesktopRunPlatform(platform);
}

File? _automationSessionFile({
  required String platform,
  required String targetName,
  required Directory sessionDirectory,
}) {
  if (!platformWorkflowPolicy(platform).supportsSessionFile) {
    return null;
  }
  return File(
    '${sessionDirectory.path}/${_automationPathSlug(targetName)}-$platform-session.json',
  );
}

String _automationPathSlug(String value) {
  final normalized = value
      .trim()
      .replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '-')
      .replaceAll(RegExp(r'^[-._]+|[-._]+$'), '');
  return normalized.isEmpty ? 'target' : normalized;
}
