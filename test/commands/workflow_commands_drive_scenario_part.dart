part of 'workflow_commands_test.dart';

void _registerWorkflowCommandsDriveScenarioTests() {
  test('drive Android package run writes session evidence', () async {
    final environment = await createTestEnvironment();
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
      flutterStdout: const {
        'devices --machine':
            '[{"id":"emulator-5554","name":"Pixel","targetPlatform":"android-arm64","isSupported":true,"emulator":true}]',
        'run -d emulator-5554 --debug --no-pub':
            'Flutter run key commands.\n'
            'Debug service listening on http://127.0.0.1:12345/abc=/\n'
            'Application running.',
      },
    );
    await _writePackageManifest(environment.workingDirectory);
    await _writeFlutterPackage(environment.workingDirectory);
    await _writeFlutterExample(
      Directory('${environment.workingDirectory.path}/example'),
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'enable', 'fixture', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    stdout.clear();
    stderr.clear();

    expect(
      await runFluoh(
        [
          'drive',
          'android',
          '--package',
          'camera',
          '--log-duration',
          '0',
          '--json',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final root = await environment.workingDirectory.resolveSymbolicLinks();
    final invocations = File(
      '${environment.workingDirectory.path}/package_workflow_invocations.txt',
    ).readAsStringSync();
    expect(invocations, contains('$root/example::flutter devices --machine'));
    expect(
      invocations,
      contains('$root/example::flutter run -d emulator-5554 --debug --no-pub'),
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('command', 'drive'));
    expect(report, containsPair('ok', true));
    final automation = report['automation'] as Map<String, Object?>;
    expect(automation['platforms'], ['android']);
    final targets = report['targets'] as List<Object?>;
    final target = targets.single as Map<String, Object?>;
    expect(target, containsPair('phase', 'android-run'));
    final steps = target['steps'] as List<Object?>;
    final runStep = steps.cast<Map<String, Object?>>().singleWhere(
      (step) => step['name'] == 'example-run-android',
    );
    final details = runStep['details'] as Map<String, Object?>;
    final sessionFile = details['sessionFile'] as String;
    expect(
      sessionFile,
      allOf(
        startsWith('${environment.workingDirectory.path}/.fluoh/tasks/'),
        endsWith('/evidence/sessions/camera-android-session.json'),
      ),
    );
    expect(details, containsPair('sessionFile', sessionFile));
    expect(
      details,
      containsPair('vmServiceUri', 'http://127.0.0.1:12345/abc=/'),
    );
    final session =
        jsonDecode(File(sessionFile).readAsStringSync())
            as Map<String, Object?>;
    expect(session, containsPair('kind', 'flutterRunSession'));
    expect(session, containsPair('status', 'passed'));
    expect(session, containsPair('platform', 'android'));
    expect(stderr, isEmpty);
  });

  test('drive iOS scenario taps permission via built-in XCTest', () async {
    final baseEnvironment = await createTestEnvironment();
    final xcrunLog = File('${baseEnvironment.workingDirectory.path}/xcrun.log');
    final xcrun = await _writeXcrunFixture(
      Directory('${baseEnvironment.workingDirectory.path}/tools'),
      xcrunLog.path,
      supportsXCTest: true,
    );
    final environment = FluohEnvironment(
      homeDirectory: baseEnvironment.homeDirectory,
      workingDirectory: baseEnvironment.workingDirectory,
      processEnvironment: {
        ...baseEnvironment.processEnvironment,
        'FLUOH_XCRUN': xcrun.path,
      },
    );
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
      flutterExitCodeSequences: const {
        'build ios --simulator --debug': [1, 0],
      },
      flutterStdout: const {
        'devices --machine':
            '[{"id":"ios-sim","name":"iPhone","targetPlatform":"ios","isSupported":true,"emulator":true}]',
        'run -d ios-sim --debug --no-pub':
            'Flutter run key commands.\n'
            'Debug service listening on http://127.0.0.1:23456/ios=/\n'
            'Application running.',
      },
      flutterStderr: const {
        'build ios --simulator --debug':
            "Swift Compiler Error (Xcode): File 'FlutterPlugin.h' has been modified since the precompiled header 'Runner-primary-Bridging-header.pch' was built",
      },
    );
    await _writePackageManifest(environment.workingDirectory);
    await _writeFlutterPackage(environment.workingDirectory);
    final exampleDirectory = Directory(
      '${environment.workingDirectory.path}/example',
    );
    await _writeFlutterExample(exampleDirectory);
    final appInfoPlist = File(
      '${exampleDirectory.path}/build/ios/iphonesimulator/Runner.app/Info.plist',
    );
    await appInfoPlist.parent.create(recursive: true);
    await appInfoPlist.writeAsString('''
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>com.example.camera</string>
</dict>
</plist>
''');
    final scenario = File(
      '${environment.workingDirectory.path}/doc/fluoh/camera/scenarios/ios-xctest-permission.md',
    );
    await scenario.parent.create(recursive: true);
    await scenario.writeAsString('''
kind: fluoh.automationScenario
schema: 1
name: ios xctest camera permission
platform: ios
steps:
  - action: resetPermission
    bundleId: com.example.camera
    permission: camera
  - action: allowPermission
    bundleId: com.example.camera
    permission: camera
  - action: assertSession
    status: passed
''');
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'enable', 'fixture', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    stdout.clear();
    stderr.clear();

    final exitCode = await runFluoh(
      [
        'drive',
        'ios',
        '--package',
        'camera',
        '--scenario',
        scenario.path,
        '--log-duration',
        '0',
        '--json',
      ],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    expect(exitCode, 0, reason: stdout.join('\n'));

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('command', 'drive'));
    expect(report, containsPair('ok', true));
    final automation = report['automation'] as Map<String, Object?>;
    final delivery =
        automation['deliveryRecommendation'] as Map<String, Object?>;
    expect(delivery, containsPair('status', 'needsCoverageReview'));
    expect(delivery, containsPair('recommendation', 'blocked'));
    final repairQueue = (automation['repairQueue'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(repairQueue.first['type'], isNot('coverage'));
    expect(
      repairQueue.first,
      allOf(
        containsPair('type', 'scenarioCoverage'),
        containsPair('nextAction', isA<Map<String, Object?>>()),
        containsPair('scenarioCandidates', isNotEmpty),
      ),
    );
    expect(
      repairQueue,
      contains(
        allOf(
          containsPair('type', 'coverage'),
          containsPair('gate', 'behavior-paths'),
          containsPair('status', 'needsPathCoverageReview'),
        ),
      ),
    );
    final plannedScenario =
        (automation['scenarios'] as List<Object?>).single
            as Map<String, Object?>;
    final inferredCoverage = plannedScenario['coverage'] as List<Object?>;
    expect(
      inferredCoverage,
      contains(
        allOf(
          containsPair('category', 'permission'),
          containsPair('item', 'camera'),
          containsPair('path', 'grant'),
        ),
      ),
    );
    expect(
      inferredCoverage,
      contains(
        allOf(
          containsPair('category', 'permission'),
          containsPair('item', 'camera'),
          containsPair('path', 'reset'),
        ),
      ),
    );
    final target =
        (report['targets'] as List<Object?>).single as Map<String, Object?>;
    final steps = (target['steps'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final scenarioStep = steps.singleWhere(
      (step) =>
          step['name'] ==
          'automation-scenario-ios-ios-xctest-camera-permission',
    );
    expect(scenarioStep, containsPair('status', 'passed'));
    final scenarioDetails = scenarioStep['details'] as Map<String, Object?>;
    final actions = (scenarioDetails['actions'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final allowAction = actions.singleWhere(
      (action) => action['action'] == 'allowPermission',
    );
    final allowDetails = allowAction['details'] as Map<String, Object?>;
    expect(allowDetails, containsPair('driver', 'xctest'));
    expect(allowDetails, containsPair('method', 'xcodebuildTest'));
    expect(allowDetails, containsPair('bundleId', 'com.example.camera'));
    final generatedTest = await _findTaskFile(
      environment.workingDirectory,
      'scratch/automation/ios-xctest/FluohIosAutomationUITests/PermissionPromptUITests.swift',
    );
    expect(await generatedTest.exists(), isTrue);
    final generatedSource = await generatedTest.readAsString();
    expect(generatedSource, contains('com.example.camera'));
    expect(generatedSource, contains('PermissionPromptUITests'));
    final invocations = xcrunLog.readAsStringSync();
    expect(
      invocations,
      contains('simctl privacy ios-sim reset camera com.example.camera'),
    );
    expect(invocations, contains('xcodebuild test'));
    expect(invocations, contains('CODE_SIGNING_ALLOWED=NO'));
    expect(
      invocations,
      isNot(contains('simctl privacy ios-sim grant camera com.example.camera')),
    );
    expect(stderr, isEmpty);
  });

  test('drive iOS scenario runs text actions via built-in XCTest', () async {
    final baseEnvironment = await createTestEnvironment();
    final xcrunLog = File('${baseEnvironment.workingDirectory.path}/xcrun.log');
    final xcrun = await _writeXcrunFixture(
      Directory('${baseEnvironment.workingDirectory.path}/tools'),
      xcrunLog.path,
      supportsXCTest: true,
      iosAppInstalled: false,
    );
    final openLog = File('${baseEnvironment.workingDirectory.path}/open.log');
    final open = File('${baseEnvironment.workingDirectory.path}/tools/open');
    await _writeExecutable(open, '''
#!/usr/bin/env bash
printf "%s\\n" "\$*" >> "${openLog.path}"
exit 0
''');
    final environment = FluohEnvironment(
      homeDirectory: baseEnvironment.homeDirectory,
      workingDirectory: baseEnvironment.workingDirectory,
      processEnvironment: {
        ...baseEnvironment.processEnvironment,
        'FLUOH_XCRUN': xcrun.path,
        'FLUOH_OPEN': open.path,
      },
    );
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
      flutterExitCodeSequences: const {
        'build ios --simulator --debug': [1, 0],
      },
      flutterStdout: const {
        'devices --machine':
            '[{"id":"ios-sim","name":"iPhone","targetPlatform":"ios","isSupported":true,"emulator":true}]',
        'run -d ios-sim --debug --no-pub':
            'Flutter run key commands.\n'
            'Debug service listening on http://127.0.0.1:23456/ios=/\n'
            'Application running.',
      },
      flutterStderr: const {
        'build ios --simulator --debug':
            "Swift Compiler Error (Xcode): File 'FlutterPlugin.h' has been modified since the precompiled header 'Runner-primary-Bridging-header.pch' was built",
      },
    );
    await _writePackageManifest(environment.workingDirectory);
    await _writeFlutterPackage(environment.workingDirectory);
    final exampleDirectory = Directory(
      '${environment.workingDirectory.path}/example',
    );
    await _writeFlutterExample(exampleDirectory);
    final appInfoPlist = File(
      '${exampleDirectory.path}/build/ios/iphonesimulator/Runner.app/Info.plist',
    );
    await appInfoPlist.parent.create(recursive: true);
    await appInfoPlist.writeAsString('''
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>com.example.camera</string>
</dict>
</plist>
''');
    final debugAppInfoPlist = File(
      '${exampleDirectory.path}/build/ios/Debug-iphonesimulator/Runner.app/Info.plist',
    );
    await debugAppInfoPlist.parent.create(recursive: true);
    await debugAppInfoPlist.writeAsString('''
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>com.example.camera</string>
</dict>
</plist>
''');
    final scenario = File(
      '${environment.workingDirectory.path}/doc/fluoh/camera/scenarios/ios-xctest-text.md',
    );
    await scenario.parent.create(recursive: true);
    await scenario.writeAsString('''
kind: fluoh.automationScenario
schema: 1
name: ios xctest text
platform: ios
steps:
  - action: wait
    timeoutSeconds: 0
  - action: tapText
    bundleId: com.example.camera
    labels: [Permission.camera]
  - action: assertText
    bundleId: com.example.camera
    labels: [PermissionStatus.granted]
  - action: captureScreenshot
    outputPath: camera-ios-granted.png
  - action: assertLog
    contains: Application running.
  - action: assertSession
    status: passed
''');
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'enable', 'fixture', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    stdout.clear();
    stderr.clear();

    final exitCode = await runFluoh(
      [
        'drive',
        'ios',
        '--package',
        'camera',
        '--scenario',
        scenario.path,
        '--log-duration',
        '0',
        '--json',
      ],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    expect(exitCode, 0, reason: stdout.join('\n'));

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('command', 'drive'));
    expect(report, containsPair('ok', true));
    final target =
        (report['targets'] as List<Object?>).single as Map<String, Object?>;
    final steps = (target['steps'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(
      steps,
      contains(
        allOf(
          containsPair('name', 'example-clean-ios-build-cache'),
          containsPair('command', 'flutter clean'),
          containsPair('status', 'passed'),
        ),
      ),
    );
    final buildStep = steps.singleWhere(
      (step) => step['name'] == 'example-build-ios',
    );
    final buildDetails = buildStep['details'] as Map<String, Object?>;
    expect(buildStep, containsPair('status', 'passed'));
    expect(buildDetails, containsPair('retryAfterClean', true));
    expect(
      buildDetails,
      containsPair('firstFailure', isA<Map<String, Object?>>()),
    );
    final scenarioStep = steps.singleWhere(
      (step) => step['name'] == 'automation-scenario-ios-ios-xctest-text',
    );
    expect(scenarioStep, containsPair('status', 'passed'));
    final scenarioDetails = scenarioStep['details'] as Map<String, Object?>;
    final actions = (scenarioDetails['actions'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(actions.map((action) => action['action']), [
      'wait',
      'tapText',
      'assertText',
      'captureScreenshot',
      'assertLog',
      'assertSession',
    ]);
    final tapAction = actions.singleWhere(
      (action) => action['action'] == 'tapText',
    );
    final tapDetails = tapAction['details'] as Map<String, Object?>;
    expect(tapDetails, containsPair('driver', 'xctest'));
    expect(tapDetails, containsPair('method', 'xcodebuildTest'));
    expect(tapDetails, containsPair('bundleId', 'com.example.camera'));
    final appInstall = tapDetails['appInstall'] as Map<String, Object?>;
    final foreground = appInstall['foreground'] as Map<String, Object?>;
    expect(foreground, containsPair('status', 'foregrounded'));
    final waitAction = actions.singleWhere(
      (action) => action['action'] == 'wait',
    );
    expect(waitAction['details'], containsPair('waitSeconds', 0));
    final screenshotAction = actions.singleWhere(
      (action) => action['action'] == 'captureScreenshot',
    );
    final screenshotDetails =
        screenshotAction['details'] as Map<String, Object?>;
    final screenshotPath = screenshotDetails['path'] as String;
    expect(
      screenshotPath,
      allOf(
        startsWith('${environment.workingDirectory.path}/.fluoh/tasks/'),
        endsWith('/evidence/screenshots/camera-ios-granted.png'),
      ),
    );
    expect(screenshotDetails, containsPair('bytes', greaterThan(0)));
    expect(File(screenshotPath).existsSync(), isTrue);
    final assertLogAction = actions.singleWhere(
      (action) => action['action'] == 'assertLog',
    );
    final assertLogDetails = assertLogAction['details'] as Map<String, Object?>;
    expect(assertLogDetails, containsPair('source', 'flutterRunOutput'));
    expect(assertLogDetails['path'], isA<String>());
    final generatedTest = await _findTaskFile(
      environment.workingDirectory,
      'scratch/automation/ios-xctest/FluohIosAutomationUITests/PermissionPromptUITests.swift',
    );
    expect(await generatedTest.exists(), isTrue);
    final generatedSource = await generatedTest.readAsString();
    expect(generatedSource, contains('TextActionUITests'));
    expect(generatedSource, contains('PermissionStatus.granted'));
    final invocations = xcrunLog.readAsStringSync();
    final workflowInvocations = File(
      '${environment.workingDirectory.path}/package_workflow_invocations.txt',
    ).readAsStringSync();
    expect(
      workflowInvocations,
      contains('example::flutter build ios --simulator --debug'),
    );
    expect(workflowInvocations, contains('example::flutter clean'));
    expect(
      RegExp(
        r'example::flutter build ios --simulator --debug',
      ).allMatches(workflowInvocations),
      hasLength(2),
    );
    expect(
      workflowInvocations,
      isNot(contains('example::flutter build ios --debug --no-codesign')),
    );
    expect(
      invocations,
      contains('simctl get_app_container ios-sim com.example.camera app'),
    );
    expect(invocations, contains('simctl install ios-sim'));
    expect(invocations, contains('simctl launch ios-sim com.example.camera'));
    expect(
      invocations,
      contains('simctl io ios-sim screenshot $screenshotPath'),
    );
    expect(invocations, contains('build/ios/iphonesimulator/Runner.app'));
    expect(invocations, isNot(contains('Debug-iphonesimulator/Runner.app')));
    final openInvocations = openLog.readAsStringSync();
    expect(
      openInvocations,
      contains('-a Simulator --args -CurrentDeviceUDID ios-sim'),
    );
    expect(RegExp('xcodebuild test').allMatches(invocations), hasLength(2));
    expect(invocations, contains('CODE_SIGNING_ALLOWED=NO'));
    expect(stderr, isEmpty);
  });

  test('drive iOS scenario runs coordinate gestures via built-in XCTest', () async {
    final baseEnvironment = await createTestEnvironment();
    final xcrunLog = File('${baseEnvironment.workingDirectory.path}/xcrun.log');
    final xcrun = await _writeXcrunFixture(
      Directory('${baseEnvironment.workingDirectory.path}/tools'),
      xcrunLog.path,
      supportsXCTest: true,
    );
    final environment = FluohEnvironment(
      homeDirectory: baseEnvironment.homeDirectory,
      workingDirectory: baseEnvironment.workingDirectory,
      processEnvironment: {
        ...baseEnvironment.processEnvironment,
        'FLUOH_XCRUN': xcrun.path,
      },
    );
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
      flutterStdout: const {
        'devices --machine':
            '[{"id":"ios-sim","name":"iPhone","targetPlatform":"ios","isSupported":true,"emulator":true}]',
        'run -d ios-sim --debug --no-pub':
            'Flutter run key commands.\n'
            'Debug service listening on http://127.0.0.1:23456/ios=/\n'
            'Application running.',
      },
    );
    await _writePackageManifest(environment.workingDirectory);
    await _writeFlutterPackage(environment.workingDirectory);
    await _writeFlutterExample(
      Directory('${environment.workingDirectory.path}/example'),
    );
    final scenario = File(
      '${environment.workingDirectory.path}/doc/fluoh/camera/scenarios/ios-xctest-gestures.md',
    );
    await scenario.parent.create(recursive: true);
    await scenario.writeAsString('''
kind: fluoh.automationScenario
schema: 1
name: ios xctest gestures
platform: ios
steps:
  - action: tap
    bundleId: com.example.camera
    x: 20
    y: 30
  - action: swipe
    bundleId: com.example.camera
    x: 10
    y: 20
    endX: 30
    endY: 40
    durationMilliseconds: 250
  - action: assertSession
    status: passed
''');
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'enable', 'fixture', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    stdout.clear();
    stderr.clear();

    expect(
      await runFluoh(
        [
          'drive',
          'ios',
          '--package',
          'camera',
          '--scenario',
          scenario.path,
          '--log-duration',
          '0',
          '--json',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('command', 'drive'));
    expect(report, containsPair('ok', true));
    final target =
        (report['targets'] as List<Object?>).single as Map<String, Object?>;
    final steps = (target['steps'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final scenarioStep = steps.singleWhere(
      (step) => step['name'] == 'automation-scenario-ios-ios-xctest-gestures',
    );
    expect(scenarioStep, containsPair('status', 'passed'));
    final scenarioDetails = scenarioStep['details'] as Map<String, Object?>;
    final actions = (scenarioDetails['actions'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(actions.map((action) => action['action']), [
      'tap',
      'swipe',
      'assertSession',
    ]);
    final tapDetails = actions.first['details'] as Map<String, Object?>;
    expect(tapDetails, containsPair('driver', 'xctest'));
    expect(tapDetails, containsPair('method', 'xcodebuildTest'));
    expect(tapDetails['gesture'], containsPair('x', 20));
    final swipeDetails = actions[1]['details'] as Map<String, Object?>;
    expect(swipeDetails, containsPair('driver', 'xctest'));
    expect(
      swipeDetails['gesture'],
      allOf(
        containsPair('x', 10),
        containsPair('y', 20),
        containsPair('endX', 30),
        containsPair('endY', 40),
        containsPair('durationMilliseconds', 250),
      ),
    );
    final generatedTest = await _findTaskFile(
      environment.workingDirectory,
      'scratch/automation/ios-xctest/FluohIosAutomationUITests/PermissionPromptUITests.swift',
    );
    expect(await generatedTest.exists(), isTrue);
    final generatedSource = await generatedTest.readAsString();
    expect(generatedSource, contains('CoordinateActionUITests'));
    expect(generatedSource, contains('press(forDuration: 0.25'));
    final invocations = xcrunLog.readAsStringSync();
    expect(RegExp('xcodebuild test').allMatches(invocations), hasLength(2));
    expect(stderr, isEmpty);
  });
}

Future<File> _findTaskFile(Directory workingDirectory, String suffix) async {
  final tasksDirectory = Directory('${workingDirectory.path}/.fluoh/tasks');
  final matches = await tasksDirectory
      .list(recursive: true)
      .where((entity) => entity is File && entity.path.endsWith(suffix))
      .cast<File>()
      .toList();
  expect(matches, hasLength(1));
  return matches.single;
}
