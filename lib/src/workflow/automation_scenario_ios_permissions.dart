part of 'automation_scenario.dart';

Future<AutomationScenarioActionResult> _runIosSimulatorPrivacy(
  AutomationScenarioAction action,
  _ScenarioExecutionContext context, {
  required String operation,
}) async {
  final bundleId = action.bundleId;
  final permission = action.permission ?? action.value ?? action.text;
  if (bundleId == null || bundleId.isEmpty || permission == null) {
    return _failedAction(
      action,
      '${action.action} requires bundleId and permission for iOS simctl privacy',
      repairHints: [
        'Add bundleId and permission to the scenario action, or use an iOS UI driver for the runtime prompt.',
      ],
    );
  }
  final xcrun = await findWorkflowXcrun(context.environment.processEnvironment);
  if (xcrun == null) {
    return _failedAction(action, 'xcrun was not found');
  }
  final args = [
    'simctl',
    'privacy',
    context.targetId!,
    operation,
    permission,
    bundleId,
  ];
  final result = await _runTool(
    xcrun.path,
    args,
    environment: context.environment.processEnvironment,
    workingDirectory: context.environment.workingDirectory,
  );
  return _processActionResult(
    action,
    result,
    '${xcrun.path} ${args.join(' ')}',
    details: {
      'driver': 'simctlPrivacy',
      'operation': operation,
      'bundleId': bundleId,
      'permission': permission,
    },
  );
}

Future<AutomationScenarioActionResult> _tapIosPermission(
  AutomationScenarioAction action,
  _ScenarioExecutionContext context, {
  required bool allow,
}) async {
  final configuredDriver = context
      .environment
      .processEnvironment['FLUOH_IOS_PERMISSION_DRIVER']
      ?.trim()
      .toLowerCase();
  const supportedDrivers = {'simctl', 'xctest', 'xcuitest'};
  if (configuredDriver != null &&
      configuredDriver.isNotEmpty &&
      !supportedDrivers.contains(configuredDriver)) {
    return _failedAction(
      action,
      'Unsupported iOS permission driver $configuredDriver',
      details: {
        'configuredDriver': configuredDriver,
        'supportedDrivers': supportedDrivers.toList(),
      },
      repairHints: [
        ...action.repairHints,
        'Set FLUOH_IOS_PERMISSION_DRIVER to xctest, xcuitest, or simctl.',
      ],
    );
  }
  if (configuredDriver == 'simctl') {
    return _runIosSimulatorPrivacy(
      action,
      context,
      operation: allow ? 'grant' : 'revoke',
    );
  }

  final failures = <Map<String, Object?>>[];
  if (configuredDriver == null ||
      configuredDriver.isEmpty ||
      configuredDriver == 'xctest' ||
      configuredDriver == 'xcuitest') {
    final bundleId = action.bundleId?.trim();
    if (bundleId == null || bundleId.isEmpty) {
      final result = _failedAction(
        action,
        'bundleId is required for the built-in XCTest iOS permission driver',
        details: {'driver': 'xctest'},
        repairHints: [
          ...action.repairHints,
          'Add bundleId to the iOS permission scenario action.',
        ],
      );
      if (configuredDriver == 'xctest' || configuredDriver == 'xcuitest') {
        return result;
      }
      failures.add({
        'driver': 'xctest',
        'reason': result.reason,
        ...result.details,
      });
    } else {
      final result = await _tapIosPermissionWithXCTest(
        action,
        context,
        allow: allow,
      );
      if (result.status == 'passed' ||
          configuredDriver == 'xctest' ||
          configuredDriver == 'xcuitest') {
        return result;
      }
      failures.add({
        'driver': 'xctest',
        'reason': result.reason,
        ...result.details,
      });
    }
  }

  return _failedAction(
    action,
    'No iOS UI automation driver could click the system permission prompt',
    details: {
      'attemptedDrivers': failures,
      'configuredDriver': configuredDriver,
    },
    repairHints: [
      ...action.repairHints,
      'Install the full Xcode toolchain for the built-in XCTest iOS driver.',
      'Trigger the runtime permission request before the ${action.action} scenario step.',
      'Use FLUOH_IOS_PERMISSION_DRIVER=simctl only when simulator privacy state control is acceptable evidence.',
    ],
  );
}

Future<AutomationScenarioActionResult> _tapIosPermissionWithXCTest(
  AutomationScenarioAction action,
  _ScenarioExecutionContext context, {
  required bool allow,
}) async {
  final xcodebuild = await _iosXcodebuild(
    context.environment.processEnvironment,
  );
  if (xcodebuild == null) {
    return _failedAction(
      action,
      'xcodebuild was not found for the built-in XCTest iOS permission driver',
      details: {'driver': 'xctest'},
      repairHints: [
        ...action.repairHints,
        'Install the full Xcode app and make it active with xcode-select.',
        'If UI clicking is unavailable in this environment, use FLUOH_IOS_PERMISSION_DRIVER=simctl only when simulator privacy state control is acceptable evidence.',
      ],
    );
  }

  final labels = _iosPermissionLabels(action, allow: allow);
  final installCheck = await _ensureIosAppInstalled(
    context,
    bundleId: action.bundleId!.trim(),
  );
  if (!installCheck.passed) {
    return _failedAction(
      action,
      installCheck.reason ?? 'Could not install the iOS app before XCTest',
      command: installCheck.command,
      details: {
        'driver': 'xctest',
        'bundleId': action.bundleId,
        'appInstall': installCheck.toJson(),
      },
      repairHints: [
        ...action.repairHints,
        'Run fluoh run ios first, or make sure build/ios/iphonesimulator contains the app bundle for this scenario bundleId.',
      ],
    );
  }
  final task = await TaskWorkspace(
    context.environment,
  ).resolveOrCreate(type: 'automation', scopeName: context.scenario.name);
  final project = await writeIosXCTestPermissionProject(
    cacheRoot: Directory('${task.scratchDirectory.path}/automation'),
    bundleId: action.bundleId!.trim(),
    labels: labels,
    match: action.match,
    timeoutSeconds: action.timeout.inSeconds,
    allow: allow,
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
      'bundleId': action.bundleId,
      'labels': labels,
      'permissionAction': allow ? 'allow' : 'deny',
      'appInstall': installCheck.toJson(),
    },
  );
}

List<String> _iosPermissionLabels(
  AutomationScenarioAction action, {
  required bool allow,
}) {
  final labels = [
    ...action.labels,
    if (action.text != null) action.text!,
    if (allow) ..._iosAllowPermissionLabels,
    if (!allow) ..._iosDenyPermissionLabels,
  ];
  final seen = <String>{};
  return [
    for (final label in labels)
      if (label.trim().isNotEmpty && seen.add(label.trim())) label.trim(),
  ];
}

const _iosAllowPermissionLabels = [
  'Allow',
  'OK',
  'Allow Once',
  'Allow While Using App',
  'Allow While Using the App',
  '允许',
  '好',
  '允许一次',
  '使用App时允许',
  '使用应用期间允许',
  '仅在使用中允许',
];

const _iosDenyPermissionLabels = [
  "Don’t Allow",
  "Don't Allow",
  'Deny',
  'Not Now',
  'Cancel',
  '不允许',
  '拒绝',
  '暂不',
  '取消',
];

Future<AutomationScenarioActionResult> _assertIosLog(
  AutomationScenarioAction action,
  _ScenarioExecutionContext context,
) async {
  final expected = action.text ?? action.value;
  if (expected == null || expected.isEmpty) {
    return _failedAction(action, 'assertLog requires text, contains, or value');
  }
  final output = await _readOptionalFile(context.outputLog);
  if (output == null) {
    return _failedAction(
      action,
      'iOS flutter run output log is missing',
      repairHints: [
        ...action.repairHints,
        'Run drive on iOS so fluoh can capture the flutter run output log.',
      ],
    );
  }
  if (!_matches(output, expected, action.match)) {
    return _failedAction(
      action,
      'iOS flutter run output did not contain $expected',
      details: {
        'source': 'flutterRunOutput',
        'path': context.outputLog!.path,
        'tail': _tail(output),
      },
      repairHints: [
        ...action.repairHints,
        'Emit a stable structured print or platform log marker for this scenario result.',
      ],
    );
  }
  return _passedAction(
    action,
    details: {
      'source': 'flutterRunOutput',
      'path': context.outputLog!.path,
      'tail': _tail(output),
    },
  );
}
