part of 'automation_scenario.dart';

Future<AutomationScenarioActionResult> _captureIosScreenshot(
  AutomationScenarioAction action,
  _ScenarioExecutionContext context,
) async {
  final xcrun = await _xcrun(context.environment.processEnvironment);
  if (xcrun == null) {
    return _failedAction(
      action,
      'xcrun was not found for iOS screenshot capture',
      repairHints: [
        ...action.repairHints,
        'Install Xcode command line tools or set FLUOH_XCRUN.',
      ],
    );
  }
  final selection = await _scenarioScreenshotFile(
    context,
    action,
    defaultExtension: 'png',
  );
  if (selection.failure != null) {
    return selection.failure!;
  }
  final file = selection.file!;
  final args = ['simctl', 'io', context.targetId!, 'screenshot', file.path];
  final result = await _runTool(
    xcrun.path,
    args,
    environment: context.environment.processEnvironment,
    workingDirectory: context.environment.workingDirectory,
    timeout: action.timeout,
  );
  if (result.exitCode == 0) {
    final fileFailure = await _screenshotFileFailure(
      action,
      file,
      command: result.command,
      platform: 'iOS',
    );
    if (fileFailure != null) {
      return fileFailure;
    }
    return _passedAction(
      action,
      command: result.command,
      details: await _screenshotDetails(
        file,
        method: 'xcrun simctl io screenshot',
      ),
    );
  }
  return _failedAction(
    action,
    'Could not capture iOS screenshot',
    command: result.command,
    details: {'path': file.path, ...result.toDetails()},
    repairHints: action.repairHints,
  );
}

Future<AutomationScenarioActionResult> _runIosTextAction(
  AutomationScenarioAction action,
  _ScenarioExecutionContext context,
) async {
  final bundleId = action.bundleId?.trim();
  if (bundleId == null || bundleId.isEmpty) {
    return _failedAction(
      action,
      '${action.action} requires bundleId for the built-in XCTest iOS text driver',
      details: {'driver': 'xctest'},
      repairHints: [
        ...action.repairHints,
        'Add bundleId to the iOS text scenario action.',
      ],
    );
  }
  final labels = _actionLabels(action);
  if (labels.isEmpty) {
    return _failedAction(action, '${action.action} requires text or labels');
  }
  final installCheck = await _ensureIosAppInstalled(
    context,
    bundleId: bundleId,
  );
  if (!installCheck.passed) {
    return _failedAction(
      action,
      installCheck.reason ?? 'Could not install the iOS app before XCTest',
      command: installCheck.command,
      details: {
        'driver': 'xctest',
        'bundleId': bundleId,
        'appInstall': installCheck.toJson(),
      },
      repairHints: [
        ...action.repairHints,
        'Run fluoh run ios first, or make sure build/ios/iphonesimulator contains the app bundle for this scenario bundleId.',
      ],
    );
  }
  final xcodebuild = await _iosXcodebuild(
    context.environment.processEnvironment,
  );
  if (xcodebuild == null) {
    return _failedAction(
      action,
      'xcodebuild was not found for the built-in XCTest iOS text driver',
      details: {'driver': 'xctest'},
      repairHints: [
        ...action.repairHints,
        'Install the full Xcode app and make it active with xcode-select.',
        'If XCTest is unavailable in this environment, use integration_test or a manual-assisted tool-readable scenario for this iOS text step.',
      ],
    );
  }

  final project = await writeIosXCTestTextActionProject(
    cacheRoot: Directory(
      '${context.environment.homeDirectory.path}/cache/automation',
    ),
    bundleId: bundleId,
    labels: labels,
    match: action.match,
    timeoutSeconds: action.timeout.inSeconds,
    action: action.action,
  );
  final args = [
    ...xcodebuild.prefixArguments,
    'test',
    '-project',
    project.projectFile.path,
    '-scheme',
    iosXCTestSchemeName,
    '-destination',
    'id=${context.targetId!}',
    '-derivedDataPath',
    project.derivedData.path,
    'CODE_SIGNING_ALLOWED=NO',
  ];
  final result = await _runTool(
    xcodebuild.executable.path,
    args,
    environment: context.environment.processEnvironment,
    workingDirectory: context.environment.workingDirectory,
    timeout: Duration(seconds: action.timeout.inSeconds + 180),
  );
  return _processActionResult(
    action,
    result,
    result.command,
    details: {
      'driver': 'xctest',
      'method': 'xcodebuildTest',
      'project': project.projectFile.path,
      'derivedData': project.derivedData.path,
      'bundleId': bundleId,
      'labels': labels,
      'match': action.match,
      'appInstall': installCheck.toJson(),
    },
  );
}

Future<AutomationScenarioActionResult> _runIosCoordinateAction(
  AutomationScenarioAction action,
  _ScenarioExecutionContext context,
) async {
  final bundleId = action.bundleId?.trim();
  if (bundleId == null || bundleId.isEmpty) {
    return _failedAction(
      action,
      '${action.action} requires bundleId for the built-in XCTest iOS coordinate driver',
      details: {'driver': 'xctest'},
      repairHints: [
        ...action.repairHints,
        'Add bundleId to the iOS coordinate scenario action.',
      ],
    );
  }
  final coordinates = action.action == 'tap'
      ? _tapCoordinates(action)
      : _swipeCoordinates(action);
  if (coordinates == null) {
    return _failedAction(
      action,
      action.action == 'tap'
          ? 'tap requires x and y coordinates'
          : '${action.action} requires x, y, endX, and endY coordinates',
      details: {'driver': 'xctest'},
      repairHints: action.repairHints,
    );
  }
  final installCheck = await _ensureIosAppInstalled(
    context,
    bundleId: bundleId,
  );
  if (!installCheck.passed) {
    return _failedAction(
      action,
      installCheck.reason ?? 'Could not install the iOS app before XCTest',
      command: installCheck.command,
      details: {
        'driver': 'xctest',
        'bundleId': bundleId,
        'appInstall': installCheck.toJson(),
      },
      repairHints: [
        ...action.repairHints,
        'Run fluoh run ios first, or make sure build/ios/iphonesimulator contains the app bundle for this scenario bundleId.',
      ],
    );
  }
  final xcodebuild = await _iosXcodebuild(
    context.environment.processEnvironment,
  );
  if (xcodebuild == null) {
    return _failedAction(
      action,
      'xcodebuild was not found for the built-in XCTest iOS coordinate driver',
      details: {'driver': 'xctest'},
      repairHints: [
        ...action.repairHints,
        'Install the full Xcode app and make it active with xcode-select.',
      ],
    );
  }

  final project = await writeIosXCTestCoordinateActionProject(
    cacheRoot: Directory(
      '${context.environment.homeDirectory.path}/cache/automation',
    ),
    bundleId: bundleId,
    x: coordinates.x,
    y: coordinates.y,
    endX: coordinates.endX,
    endY: coordinates.endY,
    durationMilliseconds: coordinates.durationMilliseconds,
    action: action.action == 'drag' ? 'swipe' : action.action,
  );
  final args = [
    ...xcodebuild.prefixArguments,
    'test',
    '-project',
    project.projectFile.path,
    '-scheme',
    iosXCTestSchemeName,
    '-destination',
    'id=${context.targetId!}',
    '-derivedDataPath',
    project.derivedData.path,
    'CODE_SIGNING_ALLOWED=NO',
  ];
  final result = await _runTool(
    xcodebuild.executable.path,
    args,
    environment: context.environment.processEnvironment,
    workingDirectory: context.environment.workingDirectory,
    timeout: Duration(seconds: action.timeout.inSeconds + 180),
  );
  return _processActionResult(
    action,
    result,
    result.command,
    details: {
      'driver': 'xctest',
      'method': 'xcodebuildTest',
      'bundleId': bundleId,
      'gesture': coordinates.toJson(),
      'project': project.projectFile.path,
      'derivedData': project.derivedData.path,
      'appInstall': installCheck.toJson(),
    },
  );
}
