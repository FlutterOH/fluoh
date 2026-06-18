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
  required _AutomationInventory inventory,
  required List<String> platforms,
  required UsageError usageException,
}) async {
  final autoDiscovered = paths.isEmpty;
  final selectedPaths = paths.isEmpty
      ? await _discoverAutomationScenarioPaths(
          inventory,
          workingDirectory: workingDirectory,
        )
      : paths;
  final scenarios = <AutomationScenario>[];
  for (final path in selectedPaths) {
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
  if (autoDiscovered) {
    return [
      for (final scenario in scenarios)
        if (platforms.contains(scenario.platform)) scenario,
    ];
  }
  return scenarios;
}

Future<List<String>> _discoverAutomationScenarioPaths(
  _AutomationInventory inventory, {
  required Directory workingDirectory,
}) async {
  final scope = _automationPathSlug(
    inventory.targetName ?? _pathBasename(inventory.rootPath),
  );
  final roots = {
    '${inventory.rootPath}/doc/fluoh/$scope/scenarios',
    '${workingDirectory.path}/doc/fluoh/$scope/scenarios',
  };
  final paths = <String>{};
  for (final rootPath in roots) {
    final root = Directory(rootPath);
    if (!await root.exists()) {
      continue;
    }
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File && _isAutomationScenarioPath(entity.path)) {
        paths.add(entity.path);
      }
    }
  }
  return paths.toList()..sort();
}

bool _isAutomationScenarioPath(String path) {
  final normalized = path.toLowerCase();
  return normalized.endsWith('.md') ||
      normalized.endsWith('.yaml') ||
      normalized.endsWith('.yml') ||
      normalized.endsWith('.json');
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
    traceDir: null,
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
    ohosPermissionDialogPolicy: OhosSystemPermissionDialogPolicy.disabled,
    traceDir: null,
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
    if (!target.passed) {
      updated.add(target);
      continue;
    }
    var current = target;
    for (final scenario in scenarios) {
      output.step(
        'Running ${_platformLabel(platform)} scenario ${scenario.name}',
      );
      final nextCommand = _isAutomationProfileScenario(scenario)
          ? _automationProfileNextCommand(
              platform: platform,
              profile: 'exploratory-smoke',
              targetKind: target.targetKind,
              packageName: packageName,
              targetName: target.targetName,
              deviceId: deviceId,
              emulatorName: emulatorName,
              autoEmulator: autoEmulator,
              sessionDirectory: sessionDirectory,
              traceOptions: traceOptions,
            )
          : _automationScenarioNextCommand(
              scenario: scenario,
              platform: platform,
              targetKind: target.targetKind,
              packageName: packageName,
              targetName: target.targetName,
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
  final profile = _isAutomationProfileScenario(result.scenario);
  final prefix = profile ? 'automation-profile' : 'automation-scenario';
  return WorkflowStepResult(
    name:
        '$prefix-${result.scenario.platform}-${_automationPathSlug(result.scenario.name)}',
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

bool _isAutomationProfileScenario(AutomationScenario scenario) {
  final path = scenario.path.path;
  final profileSegment =
      '${Platform.pathSeparator}evidence${Platform.pathSeparator}profiles${Platform.pathSeparator}';
  return path.contains(profileSegment) || path.contains('/evidence/profiles/');
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
    ] else if (targetKind == 'package') ...[
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

String _automationProfileNextCommand({
  required String platform,
  required String profile,
  required String targetKind,
  required String? packageName,
  required String targetName,
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
    ] else if (targetKind == 'package') ...[
      '--package',
      targetName,
    ],
    if (deviceId != null) ...['--device-id', deviceId],
    if (emulatorName != null) ...['--emulator', emulatorName],
    if (deviceId == null && emulatorName == null)
      autoEmulator ? '--auto-emulator' : '--no-auto-emulator',
    '--session-dir',
    sessionDirectory.path,
    '--profile',
    profile,
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
