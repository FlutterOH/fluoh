part of 'automation_scenario.dart';

class _OhosAutomationScenarioDriver extends _AutomationScenarioPlatformDriver {
  const _OhosAutomationScenarioDriver();

  @override
  String get platform => 'ohos';

  @override
  Future<AutomationScenarioActionResult> runAction(
    AutomationScenarioAction action, {
    required _ScenarioExecutionContext context,
    required String nextCommand,
  }) async {
    switch (action.action) {
      case 'clearAppData':
        final bundleName = action.bundleId ?? action.value ?? action.text;
        if (bundleName == null || bundleName.isEmpty) {
          return _failedAction(
            action,
            'OHOS clearAppData requires bundleId or packageName',
          );
        }
        return _withOhosToolchain(action, context, (hdcRun) async {
          final forceStop = await hdcRun([
            'shell',
            'aa',
            'force-stop',
            bundleName,
          ]);
          final result = await hdcRun([
            'shell',
            'bm',
            'clean',
            '-d',
            '-n',
            bundleName,
          ]);
          if (result.exitCode == 0) {
            return _passedAction(
              action,
              command: result.command,
              details: {
                'bundleName': bundleName,
                'forceStop': forceStop.toDetails(),
                ...result.toDetails(),
              },
            );
          }
          return _failedAction(
            action,
            'Command failed with exit code ${result.exitCode}',
            command: result.command,
            details: {
              'bundleName': bundleName,
              'forceStop': forceStop.toDetails(),
              ...result.toDetails(),
            },
            repairHints: action.repairHints,
          );
        });
      case 'launchApp':
        final bundleName = action.bundleId ?? action.value ?? action.text;
        if (bundleName == null || bundleName.isEmpty) {
          return _failedAction(
            action,
            'OHOS launchApp requires bundleId or packageName',
          );
        }
        final abilityName = action.abilityName ?? 'EntryAbility';
        return _withOhosToolchain(action, context, (hdcRun) async {
          final result = await hdcRun([
            'shell',
            'aa',
            'start',
            '-d',
            '0',
            '-a',
            abilityName,
            '-b',
            bundleName,
          ]);
          return _processActionResult(
            action,
            result,
            result.command,
            details: {'bundleName': bundleName, 'abilityName': abilityName},
          );
        });
      case 'tap':
        final coordinates = _tapCoordinates(action);
        if (coordinates == null) {
          return _failedAction(action, 'OHOS tap requires x and y coordinates');
        }
        return _withOhosToolchain(action, context, (hdcRun) async {
          final result = await hdcRun([
            'shell',
            'uitest',
            'uiInput',
            'click',
            '${coordinates.x}',
            '${coordinates.y}',
          ]);
          return _processActionResult(
            action,
            result,
            result.command,
            details: {'gesture': coordinates.toJson()},
          );
        });
      case 'swipe':
      case 'drag':
        final coordinates = _swipeCoordinates(action);
        if (coordinates == null) {
          return _failedAction(
            action,
            'OHOS ${action.action} requires x, y, endX, and endY coordinates',
          );
        }
        return _withOhosToolchain(action, context, (hdcRun) async {
          final result = await hdcRun([
            'shell',
            'uitest',
            'uiInput',
            'swipe',
            '${coordinates.x}',
            '${coordinates.y}',
            '${coordinates.endX}',
            '${coordinates.endY}',
            if (coordinates.durationMilliseconds != null)
              '${coordinates.durationMilliseconds}',
          ]);
          return _processActionResult(
            action,
            result,
            result.command,
            details: {'gesture': coordinates.toJson()},
          );
        });
      case 'tapText':
      case 'waitText':
      case 'assertText':
        return _withOhosToolchain(
          action,
          context,
          (hdcRun) => _runOhosTextAction(action, hdcRun),
        );
      case 'allowPermission':
        return _withOhosToolchain(
          action,
          context,
          (hdcRun) => _tapOhosPermission(action, hdcRun, allow: true),
        );
      case 'denyPermission':
        return _withOhosToolchain(
          action,
          context,
          (hdcRun) => _tapOhosPermission(action, hdcRun, allow: false),
        );
      case 'assertLog':
        return _assertOhosLog(action, context);
      case 'wait':
        return _waitAction(action);
      default:
        return _failedAction(
          action,
          'OHOS action ${action.action} is not supported by fluoh yet',
          repairHints: [
            'Expose this verification through hilog, integration_test, or a coordinate-based tap action.',
          ],
        );
    }
  }
}
