part of 'automation_scenario.dart';

class _OhosAutomationScenarioDriver extends _AutomationScenarioPlatformDriver {
  const _OhosAutomationScenarioDriver();

  @override
  String get platform => 'ohos';

  @override
  Set<String> get supportedActions => const {
    'allowPermission',
    'assertLog',
    'assertSession',
    'assertText',
    'captureScreenshot',
    'clearAppData',
    'denyPermission',
    'drag',
    'inputText',
    'launchApp',
    'press',
    'resetPermission',
    'screenshot',
    'swipe',
    'tap',
    'tapText',
    'wait',
    'waitText',
  };

  @override
  List<String> get evidenceMethods => const [
    'hdc shell uitest',
    'OHOS UI dump',
    'hdc shell snapshot_display',
    'OHOS hilog',
    'launch ability metadata',
  ];

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
      case 'resetPermission':
        final bundleName = action.bundleId ?? action.value ?? action.text;
        if (bundleName == null || bundleName.isEmpty) {
          return _failedAction(
            action,
            'OHOS resetPermission requires bundleId or packageName',
          );
        }
        return _withOhosToolchain(action, context, (hdcRun) async {
          final result = await hdcRun([
            'shell',
            'bm',
            'clean',
            '-d',
            '-n',
            bundleName,
          ]);
          return _processActionResult(
            action,
            result,
            result.command,
            details: {
              'bundleName': bundleName,
              'method': 'bm clean -d',
              'permission': action.permission,
            },
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
      case 'captureScreenshot':
      case 'screenshot':
        return _withOhosToolchain(action, context, (hdcRun) async {
          final selection = await _scenarioScreenshotFile(
            context,
            action,
            defaultExtension: 'jpeg',
          );
          if (selection.failure != null) {
            return selection.failure!;
          }
          final file = selection.file!;
          final remotePath =
              '/data/local/tmp/fluoh-${_scenarioArtifactSlug(context.scenario.name)}-step-${action.index}.jpeg';
          final capture = await hdcRun([
            'shell',
            'snapshot_display',
            '-f',
            remotePath,
          ]);
          if (capture.exitCode != 0) {
            return _failedAction(
              action,
              'Could not capture OHOS screenshot',
              command: capture.command,
              details: {
                'path': file.path,
                'remotePath': remotePath,
                ...capture.toDetails(),
              },
              repairHints: action.repairHints,
            );
          }
          final recv = await hdcRun(['file', 'recv', remotePath, file.path]);
          if (recv.exitCode == 0) {
            final fileFailure = await _screenshotFileFailure(
              action,
              file,
              command: recv.command,
              platform: 'OHOS',
              details: {
                'remotePath': remotePath,
                'capture': capture.toDetails(),
              },
            );
            if (fileFailure != null) {
              return fileFailure;
            }
            return _passedAction(
              action,
              command: recv.command,
              details: await _screenshotDetails(
                file,
                method: 'hdc shell snapshot_display',
                remotePath: remotePath,
                extra: {'capture': capture.toDetails()},
              ),
            );
          }
          return _failedAction(
            action,
            'Could not receive OHOS screenshot',
            command: recv.command,
            details: {
              'path': file.path,
              'remotePath': remotePath,
              'capture': capture.toDetails(),
              ...recv.toDetails(),
            },
            repairHints: action.repairHints,
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
      case 'inputText':
        final value = action.value ?? action.text;
        if (value == null || value.isEmpty) {
          return _failedAction(action, 'OHOS inputText requires value or text');
        }
        return _withOhosToolchain(action, context, (hdcRun) async {
          final result = await hdcRun([
            'shell',
            'uitest',
            'uiInput',
            'inputText',
            value,
          ]);
          return _processActionResult(
            action,
            result,
            result.command,
            details: {'inputLength': value.length},
          );
        });
      case 'press':
        final keyCode = action.keyCode ?? action.value ?? action.text;
        if (keyCode == null || keyCode.isEmpty) {
          return _failedAction(action, 'OHOS press requires keyCode');
        }
        return _withOhosToolchain(action, context, (hdcRun) async {
          final result = await hdcRun([
            'shell',
            'uitest',
            'uiInput',
            'keyEvent',
            keyCode,
          ]);
          return _processActionResult(
            action,
            result,
            result.command,
            details: {'keyCode': keyCode},
          );
        });
      case 'assertLog':
        return _assertOhosLog(action, context);
      case 'assertSession':
        return _assertOhosSession(action, context);
      case 'wait':
        return _waitAction(action);
      default:
        return unsupportedAction(action);
    }
  }
}
