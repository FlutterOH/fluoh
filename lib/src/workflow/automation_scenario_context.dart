part of 'automation_scenario.dart';

class _ScenarioExecutionContext {
  const _ScenarioExecutionContext({
    required this.scenario,
    required this.target,
    required this.environment,
    required this.targetId,
    required this.sessionFile,
    required this.outputLog,
    required this.hilog,
    required this.ohosBundleName,
    required this.ohosAbilityName,
    required this.rebuiltIosApps,
    required this.foregroundedIosSimulators,
    required this.launchedIosApps,
  });

  factory _ScenarioExecutionContext.fromTarget({
    required AutomationScenario scenario,
    required WorkflowTargetResult target,
    required FluohEnvironment environment,
  }) {
    String? targetId;
    File? sessionFile;
    File? outputLog;
    File? hilog;
    String? ohosBundleName;
    String? ohosAbilityName;
    for (final step in target.steps.reversed) {
      targetId ??= _targetIdFromDetails(step.details);
      sessionFile ??= _fileFromDetails(step.details, 'sessionFile');
      outputLog ??= _fileFromDetails(step.details, 'outputLog');
      hilog ??= _fileFromDetails(step.details, 'hilog');
      final launchInfo = step.details['launchInfo'];
      ohosBundleName ??= _stringFromMap(launchInfo, 'bundleName');
      ohosAbilityName ??= _stringFromMap(launchInfo, 'abilityName');
      final runPreparation = step.details['runPreparation'];
      ohosBundleName ??= _stringFromMap(runPreparation, 'bundleName');
    }
    return _ScenarioExecutionContext(
      scenario: scenario,
      target: target,
      environment: environment,
      targetId: targetId,
      sessionFile: sessionFile,
      outputLog: outputLog,
      hilog: hilog,
      ohosBundleName: ohosBundleName,
      ohosAbilityName: ohosAbilityName,
      rebuiltIosApps: <String>{},
      foregroundedIosSimulators: <String>{},
      launchedIosApps: <String>{},
    );
  }

  final AutomationScenario scenario;
  final WorkflowTargetResult target;
  final FluohEnvironment environment;
  final String? targetId;
  final File? sessionFile;
  final File? outputLog;
  final File? hilog;
  final String? ohosBundleName;
  final String? ohosAbilityName;
  final Set<String> rebuiltIosApps;
  final Set<String> foregroundedIosSimulators;
  final Set<String> launchedIosApps;
}

String? _targetIdFromDetails(Map<String, Object?> details) {
  final target = details['target'];
  if (target is Map && target['id'] is String) {
    return target['id'] as String;
  }
  final targetId = details['targetId'];
  if (targetId is String && targetId.trim().isNotEmpty) {
    return targetId.trim();
  }
  return null;
}

String? _stringFromMap(Object? value, String key) {
  if (value is Map) {
    final raw = value[key];
    if (raw is String && raw.trim().isNotEmpty) {
      return raw.trim();
    }
  }
  return null;
}

File? _fileFromDetails(Map<String, Object?> details, String key) {
  final value = details[key];
  if (value is String && value.trim().isNotEmpty) {
    return File(value.trim());
  }
  return null;
}

Future<AutomationScenarioActionResult> _runScenarioAction(
  AutomationScenarioAction action, {
  required _ScenarioExecutionContext context,
  required String nextCommand,
}) async {
  final driver = _AutomationScenarioPlatformDrivers.forPlatform(
    context.scenario.platform,
  );
  final result = await driver.runAction(
    action,
    context: context,
    nextCommand: nextCommand,
  );
  if (result.status == 'failed' && action.optional) {
    return AutomationScenarioActionResult(
      index: result.index,
      action: result.action,
      status: 'skipped',
      command: result.command,
      reason: result.reason,
      details: result.details,
      repairHints: result.repairHints,
    );
  }
  return result;
}

Future<AutomationScenarioActionResult?> _foregroundScenarioAppIfNeeded(
  _ScenarioExecutionContext context,
  AutomationScenarioAction beforeAction, {
  required String nextCommand,
}) async {
  switch (context.scenario.platform) {
    case 'android':
      var packageName = _firstScenarioBundleId(context);
      packageName ??= await _findAndroidApplicationId(context);
      if (packageName == null || packageName.isEmpty) {
        return null;
      }
      final launch = await _runScenarioAction(
        AutomationScenarioAction(
          action: 'launchApp',
          index: 0,
          bundleId: packageName,
          timeout: beforeAction.timeout,
          repairHints: [
            ...beforeAction.repairHints,
            'Confirm the Android applicationId is declared in android/app/build.gradle or add packageName to the scenario.',
          ],
        ),
        context: context,
        nextCommand: nextCommand,
      );
      return _foregroundActionResult(
        launch,
        platform: 'android',
        beforeAction: beforeAction.action,
        details: {'packageName': packageName},
      );
    case 'ohos':
      final bundleName =
          _firstScenarioBundleId(context) ?? context.ohosBundleName;
      if (bundleName == null || bundleName.isEmpty) {
        return null;
      }
      final abilityName =
          _firstScenarioAbilityName(context) ??
          context.ohosAbilityName ??
          'EntryAbility';
      final launch = await _runScenarioAction(
        AutomationScenarioAction(
          action: 'launchApp',
          index: 0,
          bundleId: bundleName,
          abilityName: abilityName,
          timeout: beforeAction.timeout,
          repairHints: [
            ...beforeAction.repairHints,
            'Confirm the OHOS bundleName and abilityName are present in the scenario or run result launchInfo.',
          ],
        ),
        context: context,
        nextCommand: nextCommand,
      );
      return _foregroundActionResult(
        launch,
        platform: 'ohos',
        beforeAction: beforeAction.action,
        details: {'bundleName': bundleName, 'abilityName': abilityName},
      );
    default:
      return null;
  }
}

AutomationScenarioActionResult _foregroundActionResult(
  AutomationScenarioActionResult launch, {
  required String platform,
  required String beforeAction,
  required Map<String, Object?> details,
}) {
  return AutomationScenarioActionResult(
    index: 0,
    action: 'foregroundApp',
    status: launch.status,
    command: launch.command,
    reason: launch.reason,
    details: {
      'platform': platform,
      'beforeAction': beforeAction,
      ...details,
      if (launch.details.isNotEmpty) 'launch': launch.details,
    },
    repairHints: launch.repairHints,
  );
}

bool _shouldAutoForegroundScenarioApp(
  _ScenarioExecutionContext context,
  AutomationScenarioAction action,
) {
  if (!platformWorkflowPolicy(
    context.scenario.platform,
  ).supportsScenarioAutoForeground) {
    return false;
  }
  const uiActions = {
    'tap',
    'swipe',
    'drag',
    'tapText',
    'waitText',
    'assertText',
    'allowPermission',
    'denyPermission',
    'inputText',
    'press',
  };
  return uiActions.contains(action.action);
}

String? _firstScenarioBundleId(_ScenarioExecutionContext context) {
  for (final action in context.scenario.steps) {
    final bundleId = _nonEmptyString(action.bundleId);
    if (bundleId != null) {
      return bundleId;
    }
    if (action.action == 'launchApp' || action.action == 'clearAppData') {
      final value =
          _nonEmptyString(action.value) ?? _nonEmptyString(action.text);
      if (value != null) {
        return value;
      }
    }
  }
  return null;
}

String? _firstScenarioAbilityName(_ScenarioExecutionContext context) {
  for (final action in context.scenario.steps) {
    final abilityName = _nonEmptyString(action.abilityName);
    if (abilityName != null) {
      return abilityName;
    }
  }
  return null;
}
