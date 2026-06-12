part of 'automation_scenario.dart';

/// Runs a parsed automation scenario against a passed workflow target.
Future<AutomationScenarioRunResult> runAutomationScenario({
  required AutomationScenario scenario,
  required WorkflowTargetResult target,
  required FluohEnvironment environment,
  required String nextCommand,
}) async {
  if (!target.passed) {
    return AutomationScenarioRunResult(
      scenario: scenario,
      status: 'skipped',
      exitCode: target.exitCode,
      actions: const [],
      reason: 'workflow target did not pass before scenario execution',
    );
  }
  final context = _ScenarioExecutionContext.fromTarget(
    scenario: scenario,
    target: target,
    environment: environment,
  );
  if (context.targetId == null) {
    final diagnostic = WorkflowDiagnostic(
      code: '${scenario.platform}.scenario_target_missing',
      message: 'Scenario target id is missing.',
      details: {
        'scenario': scenario.path.path,
        'platform': scenario.platform,
        'target': target.toJson()['target'],
      },
      nextCommand: nextCommand,
    );
    return AutomationScenarioRunResult(
      scenario: scenario,
      status: 'failed',
      exitCode: 1,
      actions: const [],
      reason: diagnostic.message,
      diagnostic: diagnostic,
    );
  }

  final actions = <AutomationScenarioActionResult>[];
  var appForegroundedForUi = false;
  var foregroundAttempted = false;
  for (final action in scenario.steps) {
    if (!appForegroundedForUi &&
        !foregroundAttempted &&
        _shouldAutoForegroundScenarioApp(context, action)) {
      foregroundAttempted = true;
      final foregroundResult = await _foregroundScenarioAppIfNeeded(
        context,
        action,
        nextCommand: nextCommand,
      );
      if (foregroundResult != null) {
        actions.add(foregroundResult);
        if (foregroundResult.status == 'failed') {
          final diagnostic = WorkflowDiagnostic(
            code: '${scenario.platform}.scenario_foregroundApp_failed',
            message: 'Scenario action foregroundApp failed.',
            details: {
              'scenario': scenario.path.path,
              'action': {
                'action': 'foregroundApp',
                'beforeAction': action.toJson(),
              },
              'result': foregroundResult.toJson(),
              if (foregroundResult.repairHints.isNotEmpty)
                'repairHints': foregroundResult.repairHints,
            },
            nextCommand: nextCommand,
          );
          return AutomationScenarioRunResult(
            scenario: scenario,
            status: 'failed',
            exitCode: 1,
            actions: actions,
            reason: foregroundResult.reason,
            diagnostic: diagnostic,
          );
        }
        appForegroundedForUi = foregroundResult.status == 'passed';
      }
    }
    final result = await _runScenarioAction(
      action,
      context: context,
      nextCommand: nextCommand,
    );
    actions.add(result);
    if (result.status == 'failed') {
      final diagnostic = WorkflowDiagnostic(
        code: '${scenario.platform}.scenario_${action.action}_failed',
        message: 'Scenario action ${action.action} failed.',
        details: {
          'scenario': scenario.path.path,
          'action': action.toJson(),
          'result': result.toJson(),
          if (result.repairHints.isNotEmpty) 'repairHints': result.repairHints,
        },
        nextCommand: nextCommand,
      );
      return AutomationScenarioRunResult(
        scenario: scenario,
        status: 'failed',
        exitCode: 1,
        actions: actions,
        reason: result.reason,
        diagnostic: diagnostic,
      );
    }
    if (action.action == 'launchApp' && result.status == 'passed') {
      appForegroundedForUi = true;
      foregroundAttempted = true;
    } else if (action.action == 'clearAppData' && result.status == 'passed') {
      appForegroundedForUi = false;
      foregroundAttempted = false;
    }
  }
  return AutomationScenarioRunResult(
    scenario: scenario,
    status: 'passed',
    exitCode: 0,
    actions: actions,
  );
}
