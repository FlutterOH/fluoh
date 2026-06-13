part of 'automation_scenario.dart';

class _AndroidAutomationScenarioDriver
    extends _AutomationScenarioPlatformDriver {
  const _AndroidAutomationScenarioDriver();

  @override
  String get platform => 'android';

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
    'screenshot',
    'swipe',
    'tap',
    'tapText',
    'wait',
    'waitText',
  };

  @override
  List<String> get evidenceMethods => const [
    'adb shell input',
    'uiautomator window dump',
    'adb exec-out screencap -p',
    'Android logcat',
    'flutterRunSession JSON',
  ];

  @override
  Future<AutomationScenarioActionResult> runAction(
    AutomationScenarioAction action, {
    required _ScenarioExecutionContext context,
    required String nextCommand,
  }) async {
    final adb = await _androidAdb(context.environment.processEnvironment);
    if (adb == null) {
      return _failedAction(
        action,
        'adb was not found in the Android SDK or PATH',
        repairHints: [
          'Install Android platform-tools or set FLUOH_ANDROID_ADB.',
        ],
      );
    }
    Future<_ToolRun> adbRun(List<String> args) {
      return _runTool(
        adb.path,
        ['-s', context.targetId!, ...args],
        environment: context.environment.processEnvironment,
        workingDirectory: context.environment.workingDirectory,
        timeout: action.timeout,
      );
    }

    switch (action.action) {
      case 'clearAppData':
        final packageName = action.bundleId ?? action.value ?? action.text;
        if (packageName == null || packageName.isEmpty) {
          return _failedAction(
            action,
            'clearAppData requires packageName or bundleId',
          );
        }
        final args = ['shell', 'pm', 'clear', packageName];
        final result = await adbRun(args);
        return _processActionResult(
          action,
          result,
          'adb ${args.join(' ')}',
          details: {'packageName': packageName},
        );
      case 'launchApp':
        final packageName = action.bundleId ?? action.value ?? action.text;
        if (packageName == null || packageName.isEmpty) {
          return _failedAction(
            action,
            'launchApp requires packageName or bundleId',
          );
        }
        final args = [
          'shell',
          'monkey',
          '-p',
          packageName,
          '-c',
          'android.intent.category.LAUNCHER',
          '1',
        ];
        final result = await adbRun(args);
        return _processActionResult(
          action,
          result,
          'adb ${args.join(' ')}',
          details: {'packageName': packageName},
        );
      case 'tap':
        final coordinates = _tapCoordinates(action);
        if (coordinates == null) {
          return _failedAction(action, 'tap requires x and y coordinates');
        }
        final args = [
          'shell',
          'input',
          'tap',
          '${coordinates.x}',
          '${coordinates.y}',
        ];
        final result = await adbRun(args);
        return _processActionResult(
          action,
          result,
          'adb ${args.join(' ')}',
          details: {'gesture': coordinates.toJson()},
        );
      case 'captureScreenshot':
      case 'screenshot':
        final selection = await _scenarioScreenshotFile(
          context,
          action,
          defaultExtension: 'png',
        );
        if (selection.failure != null) {
          return selection.failure!;
        }
        final file = selection.file!;
        final args = ['-s', context.targetId!, 'exec-out', 'screencap', '-p'];
        final result = await _runToolToFile(
          adb.path,
          args,
          environment: context.environment.processEnvironment,
          workingDirectory: context.environment.workingDirectory,
          outputFile: file,
          timeout: action.timeout,
        );
        if (result.exitCode == 0) {
          final fileFailure = await _screenshotFileFailure(
            action,
            file,
            command: result.command,
            platform: 'Android',
          );
          if (fileFailure != null) {
            return fileFailure;
          }
          return _passedAction(
            action,
            command: result.command,
            details: await _screenshotDetails(
              file,
              method: 'adb exec-out screencap -p',
            ),
          );
        }
        return _failedAction(
          action,
          'Could not capture Android screenshot',
          command: result.command,
          details: {'path': file.path, ...result.toDetails()},
          repairHints: action.repairHints,
        );
      case 'swipe':
      case 'drag':
        final coordinates = _swipeCoordinates(action);
        if (coordinates == null) {
          return _failedAction(
            action,
            '${action.action} requires x, y, endX, and endY coordinates',
          );
        }
        final args = [
          'shell',
          'input',
          'swipe',
          '${coordinates.x}',
          '${coordinates.y}',
          '${coordinates.endX}',
          '${coordinates.endY}',
          if (coordinates.durationMilliseconds != null)
            '${coordinates.durationMilliseconds}',
        ];
        final result = await adbRun(args);
        return _processActionResult(
          action,
          result,
          'adb ${args.join(' ')}',
          details: {'gesture': coordinates.toJson()},
        );
      case 'tapText':
      case 'waitText':
      case 'assertText':
        return _runAndroidTextAction(action, adbRun);
      case 'allowPermission':
        return _tapAndroidPermission(action, adbRun, allow: true);
      case 'denyPermission':
        return _tapAndroidPermission(action, adbRun, allow: false);
      case 'inputText':
        final value = action.value ?? action.text;
        if (value == null || value.isEmpty) {
          return _failedAction(action, 'inputText requires value or text');
        }
        final args = ['shell', 'input', 'text', _androidInputText(value)];
        final result = await adbRun(args);
        return _processActionResult(action, result, 'adb ${args.join(' ')}');
      case 'press':
        final keyCode = action.keyCode ?? action.value ?? action.text;
        if (keyCode == null || keyCode.isEmpty) {
          return _failedAction(action, 'press requires keyCode');
        }
        final args = ['shell', 'input', 'keyevent', keyCode];
        final result = await adbRun(args);
        return _processActionResult(action, result, 'adb ${args.join(' ')}');
      case 'assertLog':
        return _assertAndroidLog(action, adbRun);
      case 'assertSession':
        return _assertSession(action, context);
      case 'wait':
        return _waitAction(action);
      default:
        return unsupportedAction(action);
    }
  }
}
