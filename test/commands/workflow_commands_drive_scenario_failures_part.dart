part of 'workflow_commands_test.dart';

void _registerWorkflowCommandsDriveScenarioFailureTests() {
  test('drive iOS scenario rejects app bundles with mismatched bundle ids', () async {
    final baseEnvironment = await createTestEnvironment();
    final xcrunLog = File('${baseEnvironment.workingDirectory.path}/xcrun.log');
    final xcrun = await _writeXcrunFixture(
      Directory('${baseEnvironment.workingDirectory.path}/tools'),
      xcrunLog.path,
      supportsXCTest: true,
      iosAppInstalled: false,
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
  <string>com.example.other</string>
</dict>
</plist>
''');
    final scenario = File(
      '${environment.workingDirectory.path}/.fluoh/scenarios/camera/ios-wrong-bundle.md',
    );
    await scenario.parent.create(recursive: true);
    await scenario.writeAsString('''
kind: fluoh.automationScenario
schema: 1
name: ios wrong bundle
platform: ios
steps:
  - action: tap
    bundleId: com.example.camera
    x: 20
    y: 30
''');
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'add', 'fixture', source.path],
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
      1,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('ok', false));
    final target =
        (report['targets'] as List<Object?>).single as Map<String, Object?>;
    final steps = (target['steps'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final scenarioStep = steps.singleWhere(
      (step) => step['name'] == 'automation-scenario-ios-ios-wrong-bundle',
    );
    expect(scenarioStep, containsPair('status', 'failed'));
    final scenarioDetails = scenarioStep['details'] as Map<String, Object?>;
    final actions = (scenarioDetails['actions'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final tapAction = actions.singleWhere(
      (action) => action['action'] == 'tap',
    );
    final tapDetails = tapAction['details'] as Map<String, Object?>;
    final appInstall = tapDetails['appInstall'] as Map<String, Object?>;
    expect(appInstall, containsPair('status', 'missingAppBundle'));
    expect(
      appInstall['candidateAppBundles'],
      contains(
        allOf(
          containsPair('path', appInfoPlist.parent.path),
          containsPair('bundleIdentifier', 'com.example.other'),
        ),
      ),
    );
    final invocations = xcrunLog.readAsStringSync();
    expect(invocations, contains('simctl get_app_container'));
    expect(invocations, isNot(contains('simctl install ios-sim')));
    expect(invocations, isNot(contains('xcodebuild test')));
    expect(stderr, isEmpty);
  });

  test('drive Android scenario finds HOME Android SDK adb and verifies evidence', () async {
    final baseEnvironment = await createTestEnvironment();
    final adbLog = File('${baseEnvironment.workingDirectory.path}/adb.log');
    await _writeAndroidAdbFixture(
      Directory(
        '${baseEnvironment.homeDirectory.path}/Library/Android/sdk/platform-tools',
      ),
      adbLog.path,
      uiXml:
          '<hierarchy>'
          '<node text="" content-desc="" resource-id="com.example.camera:id/request_camera" bounds="[10,20][110,80]" />'
          '<node text="Allow" bounds="[10,20][110,80]" />'
          '</hierarchy>',
      logcat: 'permission granted',
    );
    final environment = FluohEnvironment(
      homeDirectory: baseEnvironment.homeDirectory,
      workingDirectory: baseEnvironment.workingDirectory,
      processEnvironment: {
        ...baseEnvironment.processEnvironment,
        'HOME': baseEnvironment.homeDirectory.path,
      },
    );
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
    final scenario = File(
      '${environment.workingDirectory.path}/.fluoh/scenarios/camera/android-permission.md',
    );
    await scenario.parent.create(recursive: true);
    await scenario.writeAsString('''
# Android permission

```yaml
kind: fluoh.automationScenario
schema: 1
name: camera permission
platform: android
coverage:
  - category: publicApi
    item: camera
    path: success
  - category: publicApi
    item: camera
    path: error
    status: notApplicable
    note: Public API error handling is covered by a package test fixture.
  - category: permission
    item: camera
    path: grant
  - category: permission
    item: camera
    path: deny
    status: notApplicable
    note: Denial path is covered by a separate package integration test.
steps:
  - action: clearAppData
    packageName: com.example.camera
  - action: swipe
    x: 10
    y: 20
    endX: 30
    endY: 40
    durationMilliseconds: 250
  - action: tapText
    labels: [request_camera]
  - action: allowPermission
    labels: [Allow]
  - action: screenshot
    outputPath: .fluoh/evidence/screenshots/camera-android-granted.png
  - action: assertLog
    contains: permission granted
  - action: assertSession
    status: passed
```
''');
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'add', 'fixture', source.path],
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
    final automation = report['automation'] as Map<String, Object?>;
    final delivery =
        automation['deliveryRecommendation'] as Map<String, Object?>;
    expect(delivery, containsPair('status', 'readyForReportReview'));
    expect(delivery, containsPair('recommendation', 'ready'));
    expect(delivery, containsPair('ready', true));
    expect(automation['repairQueue'], isEmpty);
    final scenarios = automation['scenarios'] as List<Object?>;
    expect(scenarios.single, containsPair('platform', 'android'));
    final target =
        (report['targets'] as List<Object?>).single as Map<String, Object?>;
    final steps = (target['steps'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final runStep = steps.singleWhere(
      (step) => step['name'] == 'example-run-android',
    );
    final runDetails = runStep['details'] as Map<String, Object?>;
    final postLaunchScreenshot =
        runDetails['postLaunchScreenshot'] as Map<String, Object?>;
    final postLaunchScreenshotPath =
        '${environment.workingDirectory.path}/.fluoh/evidence/screenshots/camera-android-post-launch.png';
    expect(postLaunchScreenshot, containsPair('status', 'passed'));
    expect(
      postLaunchScreenshot,
      containsPair('path', postLaunchScreenshotPath),
    );
    expect(postLaunchScreenshot, containsPair('bytes', greaterThan(0)));
    expect(File(postLaunchScreenshotPath).existsSync(), isTrue);
    final scenarioStep = steps.singleWhere(
      (step) => step['name'] == 'automation-scenario-android-camera-permission',
    );
    expect(scenarioStep, containsPair('status', 'passed'));
    final scenarioDetails = scenarioStep['details'] as Map<String, Object?>;
    final actions = (scenarioDetails['actions'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(actions.map((action) => action['action']), [
      'clearAppData',
      'foregroundApp',
      'swipe',
      'tapText',
      'allowPermission',
      'screenshot',
      'assertLog',
      'assertSession',
    ]);
    final tapAction = actions.singleWhere(
      (action) => action['action'] == 'tapText',
    );
    final tapDetails = tapAction['details'] as Map<String, Object?>;
    expect(tapDetails, containsPair('matchedText', 'request_camera'));
    expect(
      tapDetails,
      containsPair('resourceId', 'com.example.camera:id/request_camera'),
    );
    final screenshotAction = actions.singleWhere(
      (action) => action['action'] == 'screenshot',
    );
    final screenshotDetails =
        screenshotAction['details'] as Map<String, Object?>;
    final screenshotPath = screenshotDetails['path'] as String;
    expect(
      screenshotPath,
      '${environment.workingDirectory.path}/.fluoh/evidence/screenshots/camera-android-granted.png',
    );
    expect(screenshotDetails, containsPair('bytes', greaterThan(0)));
    expect(File(screenshotPath).existsSync(), isTrue);
    final adbInvocations = adbLog.readAsStringSync();
    expect(
      adbInvocations,
      contains('-s emulator-5554 shell pm clear com.example.camera'),
    );
    expect(
      adbInvocations,
      contains(
        '-s emulator-5554 shell monkey -p com.example.camera -c android.intent.category.LAUNCHER 1',
      ),
    );
    expect(
      adbInvocations,
      contains('-s emulator-5554 shell input swipe 10 20 30 40 250'),
    );
    expect(adbInvocations, contains('-s emulator-5554 shell input tap 60 50'));
    expect(adbInvocations, contains('-s emulator-5554 exec-out screencap -p'));
    expect(RegExp('screencap').allMatches(adbInvocations), hasLength(2));
    expect(stderr, isEmpty);
  });

  test('drive screenshot rejects output paths outside evidence directory', () async {
    final baseEnvironment = await createTestEnvironment();
    final adbLog = File('${baseEnvironment.workingDirectory.path}/adb.log');
    final adb = await _writeAndroidAdbFixture(
      Directory(
        '${baseEnvironment.homeDirectory.path}/Library/Android/sdk/platform-tools',
      ),
      adbLog.path,
      uiXml: '<hierarchy></hierarchy>',
      logcat: 'permission granted',
    );
    final environment = FluohEnvironment(
      homeDirectory: baseEnvironment.homeDirectory,
      workingDirectory: baseEnvironment.workingDirectory,
      processEnvironment: {
        ...baseEnvironment.processEnvironment,
        'HOME': baseEnvironment.homeDirectory.path,
        'FLUOH_ANDROID_ADB': adb.path,
      },
    );
    final outside = File(
      '${environment.workingDirectory.parent.path}/outside.png',
    );
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
    final scenario = File(
      '${environment.workingDirectory.path}/.fluoh/scenarios/camera/android-screenshot-path.md',
    );
    await scenario.parent.create(recursive: true);
    await scenario.writeAsString('''
kind: fluoh.automationScenario
schema: 1
name: android screenshot path
platform: android
steps:
  - action: screenshot
    outputPath: ../outside.png
''');
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'add', 'fixture', source.path],
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
      1,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('ok', false));
    final target =
        (report['targets'] as List<Object?>).single as Map<String, Object?>;
    final scenarioStep = (target['steps'] as List<Object?>)
        .cast<Map<String, Object?>>()
        .singleWhere(
          (step) =>
              step['name'] ==
              'automation-scenario-android-android-screenshot-path',
        );
    expect(scenarioStep, containsPair('status', 'failed'));
    final details = scenarioStep['details'] as Map<String, Object?>;
    final actions = (details['actions'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final screenshotAction = actions.singleWhere(
      (action) => action['action'] == 'screenshot',
    );
    expect(
      screenshotAction['reason'],
      contains('Screenshot outputPath must be a relative path'),
    );
    expect(outside.existsSync(), isFalse);
    final adbInvocations = adbLog.existsSync() ? adbLog.readAsStringSync() : '';
    expect(RegExp('screencap').allMatches(adbInvocations), hasLength(1));
    expect(stderr, isEmpty);
  });

  test('drive screenshot rejects evidence directory output path', () async {
    final baseEnvironment = await createTestEnvironment();
    final adbLog = File('${baseEnvironment.workingDirectory.path}/adb.log');
    final adb = await _writeAndroidAdbFixture(
      Directory(
        '${baseEnvironment.homeDirectory.path}/Library/Android/sdk/platform-tools',
      ),
      adbLog.path,
      uiXml: '<hierarchy></hierarchy>',
      logcat: 'permission granted',
    );
    final environment = FluohEnvironment(
      homeDirectory: baseEnvironment.homeDirectory,
      workingDirectory: baseEnvironment.workingDirectory,
      processEnvironment: {
        ...baseEnvironment.processEnvironment,
        'HOME': baseEnvironment.homeDirectory.path,
        'FLUOH_ANDROID_ADB': adb.path,
      },
    );
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
    final scenario = File(
      '${environment.workingDirectory.path}/.fluoh/scenarios/camera/android-screenshot-directory.md',
    );
    await scenario.parent.create(recursive: true);
    await scenario.writeAsString('''
kind: fluoh.automationScenario
schema: 1
name: android screenshot directory
platform: android
steps:
  - action: screenshot
    outputPath: .fluoh/evidence/screenshots
''');
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'add', 'fixture', source.path],
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
      1,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('ok', false));
    final target =
        (report['targets'] as List<Object?>).single as Map<String, Object?>;
    final scenarioStep = (target['steps'] as List<Object?>)
        .cast<Map<String, Object?>>()
        .singleWhere(
          (step) =>
              step['name'] ==
              'automation-scenario-android-android-screenshot-directory',
        );
    expect(scenarioStep, containsPair('status', 'failed'));
    final details = scenarioStep['details'] as Map<String, Object?>;
    final actions = (details['actions'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final screenshotAction = actions.singleWhere(
      (action) => action['action'] == 'screenshot',
    );
    expect(
      screenshotAction['reason'],
      contains('Screenshot outputPath must be a relative path'),
    );
    expect(
      screenshotAction['details'],
      containsPair('outputPath', '.fluoh/evidence/screenshots'),
    );
    final screenshotDirectoryPath =
        '${environment.workingDirectory.path}/.fluoh/evidence/screenshots';
    expect(
      FileSystemEntity.typeSync(screenshotDirectoryPath),
      FileSystemEntityType.directory,
    );
    expect(
      File(
        '$screenshotDirectoryPath/camera-android-post-launch.png',
      ).existsSync(),
      isTrue,
    );
    final adbInvocations = adbLog.existsSync() ? adbLog.readAsStringSync() : '';
    expect(RegExp('screencap').allMatches(adbInvocations), hasLength(1));
    expect(stderr, isEmpty);
  });

  test(
    'drive Android scenario prefers example applicationId over package namespace',
    () async {
      final baseEnvironment = await createTestEnvironment();
      final adbLog = File('${baseEnvironment.workingDirectory.path}/adb.log');
      final adb = await _writeAndroidAdbFixture(
        Directory('${baseEnvironment.workingDirectory.path}/tools'),
        adbLog.path,
        uiXml:
            '<hierarchy>'
            '<node text="" content-desc="" resource-id="com.example.camera:id/request_camera" bounds="[10,20][110,80]" />'
            '</hierarchy>',
        logcat: 'permission granted',
      );
      final environment = FluohEnvironment(
        homeDirectory: baseEnvironment.homeDirectory,
        workingDirectory: baseEnvironment.workingDirectory,
        processEnvironment: {
          ...baseEnvironment.processEnvironment,
          'FLUOH_ANDROID_ADB': adb.path,
        },
      );
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
      await File(
        '${environment.workingDirectory.path}/build.gradle',
      ).writeAsString('''
plugins {
  id 'com.android.library'
}

android {
  namespace 'com.example.plugin'
}
''');
      final exampleDirectory = Directory(
        '${environment.workingDirectory.path}/example',
      );
      await _writeFlutterExample(exampleDirectory);
      final exampleGradle = File(
        '${exampleDirectory.path}/android/app/build.gradle',
      );
      await exampleGradle.parent.create(recursive: true);
      await exampleGradle.writeAsString('''
plugins {
  id 'com.android.application'
}

android {
  namespace 'com.example.camera'
  defaultConfig {
    applicationId 'com.example.camera'
  }
}
''');
      final scenario = File(
        '${environment.workingDirectory.path}/.fluoh/scenarios/camera/android-autoforeground.md',
      );
      await scenario.parent.create(recursive: true);
      await scenario.writeAsString('''
kind: fluoh.automationScenario
schema: 1
name: android autoforeground
platform: android
steps:
  - action: tapText
    labels: [request_camera]
  - action: assertSession
    status: passed
''');
      final stdout = <String>[];
      final stderr = <String>[];

      await runFluoh(
        ['source', 'add', 'fixture', source.path],
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
      expect(report, containsPair('ok', true));
      final target =
          (report['targets'] as List<Object?>).single as Map<String, Object?>;
      final steps = (target['steps'] as List<Object?>)
          .cast<Map<String, Object?>>();
      final scenarioStep = steps.singleWhere(
        (step) =>
            step['name'] ==
            'automation-scenario-android-android-autoforeground',
      );
      expect(scenarioStep, containsPair('status', 'passed'));
      final scenarioDetails = scenarioStep['details'] as Map<String, Object?>;
      final actions = (scenarioDetails['actions'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(actions.map((action) => action['action']), [
        'foregroundApp',
        'tapText',
        'assertSession',
      ]);
      final foregroundDetails =
          actions.first['details'] as Map<String, Object?>;
      expect(
        foregroundDetails,
        containsPair('packageName', 'com.example.camera'),
      );
      final invocations = adbLog.readAsStringSync();
      expect(
        invocations,
        contains(
          '-s emulator-5554 shell monkey -p com.example.camera -c android.intent.category.LAUNCHER 1',
        ),
      );
      expect(invocations, isNot(contains('com.example.plugin')));
      expect(stderr, isEmpty);
    },
  );

  test('drive Android scenario failure returns repair hints', () async {
    final baseEnvironment = await createTestEnvironment();
    final adb = await _writeAndroidAdbFixture(
      Directory('${baseEnvironment.workingDirectory.path}/tools'),
      '${baseEnvironment.workingDirectory.path}/adb.log',
      uiXml:
          '<hierarchy><node text="Not now" bounds="[10,20][110,80]" /></hierarchy>',
      logcat: 'permission missing',
    );
    final environment = FluohEnvironment(
      homeDirectory: baseEnvironment.homeDirectory,
      workingDirectory: baseEnvironment.workingDirectory,
      processEnvironment: {
        ...baseEnvironment.processEnvironment,
        'FLUOH_ANDROID_ADB': adb.path,
      },
    );
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
      flutterFailures: const {'test integration_test -d emulator-5554': 99},
      flutterStdout: const {
        'devices --machine':
            '[{"id":"emulator-5554","name":"Pixel","targetPlatform":"android-arm64","isSupported":true,"emulator":true}]',
        'run -d emulator-5554 --debug --no-pub':
            'Flutter run key commands.\nApplication running.',
      },
    );
    await _writePackageManifest(environment.workingDirectory);
    await _writeFlutterPackage(environment.workingDirectory);
    await _writeFlutterExample(
      Directory('${environment.workingDirectory.path}/example'),
    );
    final scenario = File(
      '${environment.workingDirectory.path}/.fluoh/scenarios/camera/android-permission.md',
    );
    await scenario.parent.create(recursive: true);
    await scenario.writeAsString('''
kind: fluoh.automationScenario
schema: 1
name: denied camera permission
platform: android
steps:
  - action: allowPermission
    labels: [Grant camera]
    timeoutSeconds: 0
    repairHints:
      - Add a stable permission trigger and visible allow label before this step.
''');
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'add', 'fixture', source.path],
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
      1,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('ok', false));
    final automation = report['automation'] as Map<String, Object?>;
    final delivery =
        automation['deliveryRecommendation'] as Map<String, Object?>;
    expect(delivery, containsPair('status', 'needsRepair'));
    expect(delivery, containsPair('recommendation', 'blocked'));
    final repairQueue = (automation['repairQueue'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(
      repairQueue,
      contains(
        allOf(
          containsPair('type', 'diagnostic'),
          containsPair('code', 'android.scenario_allowPermission_failed'),
          containsPair('nextCommand', contains('fluoh drive')),
        ),
      ),
    );
    final repairPlan = automation['repairPlan'] as Map<String, Object?>;
    expect(repairPlan, containsPair('status', 'needsRepair'));
    expect(
      repairPlan['nextStep'],
      allOf(
        containsPair('kind', 'fixDiagnosticAndRerun'),
        containsPair('sourceType', 'diagnostic'),
        containsPair('code', 'android.scenario_allowPermission_failed'),
        containsPair('nextCommand', contains('fluoh drive')),
        containsPair(
          'doneWhen',
          contains(
            'diagnostic android.scenario_allowPermission_failed no longer appears',
          ),
        ),
        containsPair(
          'validation',
          allOf(
            containsPair('kind', 'command'),
            containsPair('command', contains('fluoh drive')),
          ),
        ),
        containsPair(
          'repairHints',
          contains(
            'Add a stable permission trigger and visible allow label before this step.',
          ),
        ),
      ),
    );
    final target =
        (report['targets'] as List<Object?>).single as Map<String, Object?>;
    expect(target, containsPair('passed', false));
    final steps = (target['steps'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final scenarioStep = steps.singleWhere(
      (step) =>
          step['name'] ==
          'automation-scenario-android-denied-camera-permission',
    );
    expect(scenarioStep, containsPair('status', 'failed'));
    final diagnostics = (scenarioStep['diagnostics'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final diagnosticDetails =
        diagnostics.single['details'] as Map<String, Object?>;
    expect(
      diagnosticDetails['repairHints'],
      contains(
        'Add a stable permission trigger and visible allow label before this step.',
      ),
    );
    expect(diagnostics.single['nextCommand'], contains('fluoh drive'));
    expect(stderr, isEmpty);
  });

  test('drive project scenario failure reruns project automation', () async {
    final baseEnvironment = await createTestEnvironment();
    final adb = await _writeAndroidAdbFixture(
      Directory('${baseEnvironment.workingDirectory.path}/tools'),
      '${baseEnvironment.workingDirectory.path}/adb.log',
      uiXml:
          '<hierarchy><node text="Not now" bounds="[10,20][110,80]" /></hierarchy>',
      logcat: 'permission missing',
    );
    final environment = FluohEnvironment(
      homeDirectory: baseEnvironment.homeDirectory,
      workingDirectory: baseEnvironment.workingDirectory,
      processEnvironment: {
        ...baseEnvironment.processEnvironment,
        'FLUOH_ANDROID_ADB': adb.path,
      },
    );
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
      flutterStdout: const {
        'devices --machine':
            '[{"id":"emulator-5554","name":"Pixel","targetPlatform":"android-arm64","isSupported":true,"emulator":true}]',
        'run -d emulator-5554 --debug --no-pub':
            'Flutter run key commands.\nApplication running.',
      },
    );
    await writeFlutterProjectFixture(environment.workingDirectory);
    await _writeProjectSdkConfig(environment.workingDirectory);
    await Directory(
      '${environment.workingDirectory.path}/integration_test',
    ).create(recursive: true);
    await File(
      '${environment.workingDirectory.path}/integration_test/app_test.dart',
    ).writeAsString('void main() {}\n');
    final scenario = File(
      '${environment.workingDirectory.path}/.fluoh/scenarios/current/android-permission.md',
    );
    await scenario.parent.create(recursive: true);
    await scenario.writeAsString('''
kind: fluoh.automationScenario
schema: 1
name: denied camera permission
platform: android
steps:
  - action: allowPermission
    labels: [Grant camera]
    timeoutSeconds: 0
''');
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'add', 'fixture', source.path],
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
          '--no-auto-emulator',
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
      1,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    final target =
        (report['targets'] as List<Object?>).single as Map<String, Object?>;
    expect(target['target'], containsPair('kind', 'project'));
    expect(target, containsPair('nextCommand', isA<String>()));
    final nextCommand = target['nextCommand'] as String;
    expect(nextCommand, contains('fluoh drive android'));
    expect(nextCommand, contains('--no-auto-emulator'));
    expect(nextCommand, contains('--scenario ${scenario.path}'));
    expect(nextCommand, isNot(contains('--package current')));
    final steps = (target['steps'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final integrationStep = steps.singleWhere(
      (step) => step['name'] == 'project-integration-android',
    );
    expect(
      integrationStep,
      containsPair('command', 'flutter test integration_test -d emulator-5554'),
    );
    expect(integrationStep, containsPair('status', 'passed'));
    final integrationDetails =
        integrationStep['details'] as Map<String, Object?>;
    final interactionEvidence =
        integrationDetails['interactionEvidence'] as Map<String, Object?>;
    expect(interactionEvidence, containsPair('method', 'integration_test'));
    expect(interactionEvidence, containsPair('status', 'passed'));
    final scenarioStep = steps.singleWhere(
      (step) =>
          step['name'] ==
          'automation-scenario-android-denied-camera-permission',
    );
    final diagnostics = (scenarioStep['diagnostics'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(diagnostics.single['nextCommand'], nextCommand);
    final root = await environment.workingDirectory.resolveSymbolicLinks();
    final invocations = File(
      '${environment.workingDirectory.path}/package_workflow_invocations.txt',
    ).readAsStringSync();
    expect(
      invocations,
      contains('$root::flutter run -d emulator-5554 --debug --no-pub'),
    );
    expect(
      invocations,
      contains('$root::flutter test integration_test -d emulator-5554'),
    );
    expect(stderr, isEmpty);
  });

  test('drive project scenario waits for integration tests to pass', () async {
    final environment = await createTestEnvironment();
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
      flutterFailures: const {'test integration_test -d emulator-5554': 9},
      flutterStdout: const {
        'devices --machine':
            '[{"id":"emulator-5554","name":"Pixel","targetPlatform":"android-arm64","isSupported":true,"emulator":true}]',
        'run -d emulator-5554 --debug --no-pub':
            'Flutter run key commands.\nApplication running.',
      },
    );
    await writeFlutterProjectFixture(environment.workingDirectory);
    await _writeProjectSdkConfig(environment.workingDirectory);
    await Directory(
      '${environment.workingDirectory.path}/integration_test',
    ).create(recursive: true);
    await File(
      '${environment.workingDirectory.path}/integration_test/app_test.dart',
    ).writeAsString('void main() {}\n');
    final scenario = File(
      '${environment.workingDirectory.path}/.fluoh/scenarios/current/android-permission.md',
    );
    await scenario.parent.create(recursive: true);
    await scenario.writeAsString('''
kind: fluoh.automationScenario
schema: 1
name: denied camera permission
platform: android
steps:
  - action: tap
    x: 10
    y: 20
''');
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'add', 'fixture', source.path],
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
          '--no-auto-emulator',
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
      9,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('ok', false));
    final target =
        (report['targets'] as List<Object?>).single as Map<String, Object?>;
    final steps = (target['steps'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final integrationStep = steps.singleWhere(
      (step) => step['name'] == 'project-integration-android',
    );
    expect(integrationStep, containsPair('status', 'failed'));
    expect(
      steps.map((step) => step['name']),
      isNot(contains('automation-scenario-android-denied-camera-permission')),
    );
    final root = await environment.workingDirectory.resolveSymbolicLinks();
    final invocations = File(
      '${environment.workingDirectory.path}/package_workflow_invocations.txt',
    ).readAsStringSync();
    expect(
      invocations,
      contains('$root::flutter run -d emulator-5554 --debug --no-pub'),
    );
    expect(
      invocations,
      contains('$root::flutter test integration_test -d emulator-5554'),
    );
    expect(stderr, isEmpty);
  });

  test('drive Android scenario kills timed out adb commands', () async {
    final baseEnvironment = await createTestEnvironment();
    final adbLog = File('${baseEnvironment.workingDirectory.path}/adb.log');
    final timeoutMarker = File(
      '${baseEnvironment.workingDirectory.path}/adb-timeout.marker',
    );
    final adb = File('${baseEnvironment.workingDirectory.path}/tools/adb');
    await _writeExecutable(adb, '''
#!/usr/bin/env bash
printf "%s\\n" "\$*" >> ${_shellSingleQuote(adbLog.path)}
if [ "\$1" = "-s" ]; then
  shift 2
fi

if [ "\$*" = "shell uiautomator dump /sdcard/fluoh-window.xml" ]; then
  trap 'printf "%s\\n" "terminated" >> ${_shellSingleQuote(timeoutMarker.path)}; exit 143' TERM INT
  while true; do sleep 1; done
fi

printf "%s\\n" "unsupported adb \$*" >&2
exit 1
''');
    final environment = FluohEnvironment(
      homeDirectory: baseEnvironment.homeDirectory,
      workingDirectory: baseEnvironment.workingDirectory,
      processEnvironment: {
        ...baseEnvironment.processEnvironment,
        'FLUOH_ANDROID_ADB': adb.path,
      },
    );
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
      flutterStdout: const {
        'devices --machine':
            '[{"id":"emulator-5554","name":"Pixel","targetPlatform":"android-arm64","isSupported":true,"emulator":true}]',
        'run -d emulator-5554 --debug --no-pub':
            'Flutter run key commands.\nApplication running.',
      },
    );
    await _writePackageManifest(environment.workingDirectory);
    await _writeFlutterPackage(environment.workingDirectory);
    await _writeFlutterExample(
      Directory('${environment.workingDirectory.path}/example'),
    );
    final scenario = File(
      '${environment.workingDirectory.path}/.fluoh/scenarios/camera/android-timeout.md',
    );
    await scenario.parent.create(recursive: true);
    await scenario.writeAsString('''
kind: fluoh.automationScenario
schema: 1
name: android timeout
platform: android
steps:
  - action: tapText
    labels: [Never appears]
    timeoutSeconds: 1
''');
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'add', 'fixture', source.path],
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
      1,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('ok', false));
    final target =
        (report['targets'] as List<Object?>).single as Map<String, Object?>;
    final steps = (target['steps'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final scenarioStep = steps.singleWhere(
      (step) => step['name'] == 'automation-scenario-android-android-timeout',
    );
    final scenarioDetails = scenarioStep['details'] as Map<String, Object?>;
    final actions = (scenarioDetails['actions'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final tapAction = actions.singleWhere(
      (action) => action['action'] == 'tapText',
    );
    final tapDetails = tapAction['details'] as Map<String, Object?>;
    expect(tapAction, containsPair('status', 'failed'));
    expect(tapAction, containsPair('reason', 'Could not dump Android UI'));
    expect(tapDetails, containsPair('exitCode', 124));
    expect(tapDetails['stderrTail'], contains('Command timed out.'));
    var timeoutMarkerText = '';
    for (var attempt = 0; attempt < 100; attempt += 1) {
      if (await timeoutMarker.exists()) {
        timeoutMarkerText = await timeoutMarker.readAsString();
        if (timeoutMarkerText.contains('terminated')) {
          break;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(timeoutMarkerText, contains('terminated'));
    expect(stderr, isEmpty);
  });
}
