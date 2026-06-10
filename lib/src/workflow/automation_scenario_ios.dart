part of 'automation_scenario.dart';

class _IosAutomationScenarioDriver extends _AutomationScenarioPlatformDriver {
  const _IosAutomationScenarioDriver();

  @override
  String get platform => 'ios';

  @override
  Future<AutomationScenarioActionResult> runAction(
    AutomationScenarioAction action, {
    required _ScenarioExecutionContext context,
    required String nextCommand,
  }) async {
    switch (action.action) {
      case 'resetPermission':
        return _runIosSimulatorPrivacy(action, context, operation: 'reset');
      case 'allowPermission':
        return _tapIosPermission(action, context, allow: true);
      case 'denyPermission':
        return _tapIosPermission(action, context, allow: false);
      case 'tap':
        return _runIosCoordinateAction(action, context);
      case 'swipe':
      case 'drag':
        return _runIosCoordinateAction(action, context);
      case 'tapText':
      case 'waitText':
      case 'assertText':
        return _runIosTextAction(action, context);
      case 'assertLog':
        return _assertIosLog(action, context);
      case 'assertSession':
        return _assertSession(action, context);
      case 'wait':
        return _waitAction(action);
      default:
        return _failedAction(
          action,
          'iOS action ${action.action} is not supported by fluoh yet',
          repairHints: [
            'Use integration_test, XCTest-backed tooling, or record manual-assisted evidence with flutterRunSession output.',
          ],
        );
    }
  }
}
