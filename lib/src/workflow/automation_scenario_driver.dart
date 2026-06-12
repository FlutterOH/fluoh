part of 'automation_scenario.dart';

abstract class _AutomationScenarioPlatformDriver {
  const _AutomationScenarioPlatformDriver();

  String get platform;

  Set<String> get supportedActions;

  List<String> get evidenceMethods;

  Map<String, Object?> get metadata {
    return {
      'platform': platform,
      'supportedActions': supportedActions.toList()..sort(),
      'evidenceMethods': evidenceMethods,
    };
  }

  Future<AutomationScenarioActionResult> runAction(
    AutomationScenarioAction action, {
    required _ScenarioExecutionContext context,
    required String nextCommand,
  });

  AutomationScenarioActionResult unsupportedAction(
    AutomationScenarioAction action,
  ) {
    return _failedAction(
      action,
      '$platform action ${action.action} is not supported by fluoh yet',
      details: metadata,
      repairHints: [
        ...action.repairHints,
        'Use one of ${supportedActions.toList()..sort()}, integration_test, or manual-assisted tool-readable evidence.',
      ],
    );
  }
}

class _AutomationScenarioPlatformDrivers {
  const _AutomationScenarioPlatformDrivers._();

  static const _drivers = <String, _AutomationScenarioPlatformDriver>{
    'android': _AndroidAutomationScenarioDriver(),
    'ios': _IosAutomationScenarioDriver(),
    'ohos': _OhosAutomationScenarioDriver(),
  };

  static _AutomationScenarioPlatformDriver forPlatform(String platform) {
    return _drivers[platform] ??
        _UnsupportedAutomationScenarioPlatformDriver(platform);
  }

  static Map<String, Object?> metadataForPlatform(String platform) {
    return forPlatform(platform).metadata;
  }
}

class _UnsupportedAutomationScenarioPlatformDriver
    extends _AutomationScenarioPlatformDriver {
  const _UnsupportedAutomationScenarioPlatformDriver(this.platform);

  @override
  final String platform;

  @override
  Set<String> get supportedActions => const {};

  @override
  List<String> get evidenceMethods => const [];

  @override
  Future<AutomationScenarioActionResult> runAction(
    AutomationScenarioAction action, {
    required _ScenarioExecutionContext context,
    required String nextCommand,
  }) async {
    return AutomationScenarioActionResult(
      index: action.index,
      action: action.action,
      status: 'failed',
      reason: 'platform ${context.scenario.platform} is not supported',
      repairHints: [
        'Run $nextCommand without --scenario and collect manual-assisted tool-readable evidence.',
      ],
    );
  }
}
