part of 'automation_scenario.dart';

abstract class _AutomationScenarioPlatformDriver {
  const _AutomationScenarioPlatformDriver();

  String get platform;

  Future<AutomationScenarioActionResult> runAction(
    AutomationScenarioAction action, {
    required _ScenarioExecutionContext context,
    required String nextCommand,
  });
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
}

class _UnsupportedAutomationScenarioPlatformDriver
    extends _AutomationScenarioPlatformDriver {
  const _UnsupportedAutomationScenarioPlatformDriver(this.platform);

  @override
  final String platform;

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
        'Run $nextCommand without --scenario and collect manual-assisted evidence.',
      ],
    );
  }
}
