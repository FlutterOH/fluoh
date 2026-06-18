part of 'workflow_commands_test.dart';

void _registerWorkflowCommandsDrivePlanTests() {
  test('drive dry-run plans mobile emulator evidence', () async {
    final environment = await createTestEnvironment();
    await _writePackageManifest(environment.workingDirectory);
    await _writeFlutterPackage(environment.workingDirectory);
    final example = Directory('${environment.workingDirectory.path}/example');
    await _writeFlutterExample(example);
    await _writeWorkflowPlatformDirectories(example);
    await _writeWorkflowOhosProject(example);
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        [
          'drive',
          'all',
          '--package',
          'camera',
          '--trace-dir',
          '.fluoh/tasks/manual/traces/camera/mobile',
          '--dry-run',
          '--json',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('schema', 1));
    expect(report, containsPair('command', 'drive'));
    expect(report, containsPair('ok', true));
    final automation = report['automation'] as Map<String, Object?>;
    expect(automation, containsPair('kind', 'fluoh.mobileAutomation'));
    expect(automation['platforms'], ['ohos', 'android', 'ios']);
    expect(
      automation,
      containsPair(
        'sessionDirectory',
        allOf(
          startsWith('${environment.workingDirectory.path}/.fluoh/tasks/'),
          endsWith('/evidence/sessions'),
        ),
      ),
    );
    expect(
      automation,
      containsPair(
        'inspiredBy',
        containsPair('url', 'https://github.com/callstack/agent-device'),
      ),
    );
    final coveragePolicy = automation['coveragePolicy'] as Map<String, Object?>;
    expect(coveragePolicy, containsPair('status', 'needsInteractionInventory'));
    expect(coveragePolicy, containsPair('readyForAutomation', false));
    expect(
      coveragePolicy['qualityGateSummary'],
      allOf(
        containsPair('total', greaterThan(0)),
        containsPair('notReady', isNotEmpty),
      ),
    );
    final recommendation =
        automation['deliveryRecommendation'] as Map<String, Object?>;
    expect(recommendation, containsPair('status', 'needsCoverageReview'));
    expect(
      recommendation['targetSummary'],
      allOf(containsPair('executed', false), containsPair('dryRun', true)),
    );
    final repairQueue = (automation['repairQueue'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final rerunCommand = automation['rerunCommand'] as String;
    expect(
      rerunCommand,
      allOf(
        contains('fluoh drive all --package camera'),
        contains('--trace-dir .fluoh/tasks/manual/traces/camera/mobile'),
        contains('--dry-run --json'),
      ),
    );
    final repairPlan = automation['repairPlan'] as Map<String, Object?>;
    expect(repairPlan, containsPair('status', 'needsCoverageReview'));
    expect(repairPlan, containsPair('queueLength', repairQueue.length));
    expect(
      repairPlan['nextStep'],
      allOf(
        containsPair(
          'sourceType',
          anyOf('coverage', 'scenarioCoverage', 'capabilityCoverage'),
        ),
        containsPair('gate', isNotEmpty),
        containsPair('doneWhen', isNotEmpty),
        containsPair(
          'validation',
          allOf(
            containsPair('kind', 'sameDriveCommand'),
            containsPair('command', rerunCommand),
          ),
        ),
      ),
    );
    expect(
      repairQueue,
      contains(
        allOf(
          containsPair('type', 'coverage'),
          containsPair('gate', 'coverage-inventory'),
          containsPair('status', 'needsInventory'),
        ),
      ),
    );
    expect(
      coveragePolicy['capabilityCoverageGuidance'],
      contains('package capability inventory'),
    );
    expect(coveragePolicy['coverageSummary'], containsPair('itemCount', 0));
    final qualityGates = coveragePolicy['qualityGates'] as List<Object?>;
    expect(
      qualityGates,
      contains(
        allOf(
          containsPair('id', 'coverage-inventory'),
          containsPair('status', 'needsInventory'),
        ),
      ),
    );
    final repairLoop = coveragePolicy['repairLoop'] as Map<String, Object?>;
    expect(
      repairLoop['steps'],
      contains(
        allOf(
          containsPair('id', 'rerun-same-command'),
          containsPair('action', contains('Rerun the exact nextCommand')),
        ),
      ),
    );
    final minimumGates = coveragePolicy['minimumGates'] as List<Object?>;
    expect(
      minimumGates,
      contains(
        allOf(
          containsPair('id', 'permission-matrix'),
          containsPair(
            'rule',
            contains('Cover every declared or requestable permission'),
          ),
        ),
      ),
    );
    final checks = automation['checks'] as List<Object?>;
    expect(
      checks,
      contains(
        allOf(
          containsPair('platform', 'ohos'),
          containsPair(
            'command',
            contains('fluoh run ohos --package camera --auto-emulator'),
          ),
          containsPair(
            'driver',
            allOf(
              containsPair('platform', 'ohos'),
              containsPair('supportedActions', contains('assertSession')),
              containsPair('supportedActions', contains('captureScreenshot')),
              containsPair('supportedActions', contains('inputText')),
              containsPair(
                'evidenceMethods',
                contains('hdc shell snapshot_display'),
              ),
              containsPair('evidenceMethods', contains('OHOS hilog')),
            ),
          ),
        ),
      ),
    );
    expect(
      checks,
      contains(
        allOf(
          containsPair('platform', 'android'),
          containsPair(
            'driver',
            allOf(
              containsPair('platform', 'android'),
              containsPair('supportedActions', contains('screenshot')),
              containsPair('supportedActions', contains('tapText')),
              containsPair(
                'evidenceMethods',
                contains('flutterRunSession JSON'),
              ),
            ),
          ),
          containsPair(
            'sessionFile',
            allOf(
              startsWith('${environment.workingDirectory.path}/.fluoh/tasks/'),
              endsWith('/evidence/sessions/camera-android-session.json'),
            ),
          ),
        ),
      ),
    );
    expect(
      checks,
      contains(
        allOf(
          containsPair('platform', 'ios'),
          containsPair(
            'driver',
            allOf(
              containsPair('supportedActions', contains('captureScreenshot')),
              containsPair(
                'evidenceMethods',
                contains('xcrun simctl io screenshot'),
              ),
            ),
          ),
          containsPair(
            'sessionFile',
            allOf(
              startsWith('${environment.workingDirectory.path}/.fluoh/tasks/'),
              endsWith('/evidence/sessions/camera-ios-session.json'),
            ),
          ),
        ),
      ),
    );
    final targets = (report['targets'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(
      targets.single,
      allOf(
        containsPair('target', {'kind': 'package', 'name': 'camera'}),
        containsPair('phase', 'automation-dry-run'),
        containsPair('passed', true),
      ),
    );
    final trace = report['trace'] as Map<String, Object?>;
    final traceManifest = File(trace['manifest'] as String);
    expect(await traceManifest.exists(), isTrue);
    final traceContent =
        jsonDecode(await traceManifest.readAsString()) as Map<String, Object?>;
    expect(traceContent, containsPair('command', 'drive'));
    expect(traceContent['commandLine'], contains('--dry-run'));
    expect(stderr, isEmpty);
  });

  test('drive dry-run plans exploratory smoke profile separately', () async {
    final environment = await createTestEnvironment();
    await _writePackageManifest(environment.workingDirectory);
    await _writeFlutterPackage(environment.workingDirectory);
    final example = Directory('${environment.workingDirectory.path}/example');
    await _writeFlutterExample(example);
    await _writeWorkflowPlatformDirectories(example);
    await _writeWorkflowOhosProject(example);
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        [
          'drive',
          'ohos',
          '--package',
          'camera',
          '--profile',
          'exploratory-smoke',
          '--dry-run',
          '--json',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    final automation = report['automation'] as Map<String, Object?>;
    expect(automation, isNot(contains('scenarios')));
    expect(
      automation['rerunCommand'],
      allOf(
        contains('fluoh drive ohos --package camera'),
        contains('--profile exploratory-smoke'),
        contains('--dry-run --json'),
      ),
    );
    final profile = automation['profile'] as Map<String, Object?>;
    expect(profile, containsPair('name', 'exploratory-smoke'));
    expect(profile, containsPair('classification', 'exploratory-smoke'));
    expect(profile, containsPair('releaseGate', false));
    final generatedScenarios = (profile['generatedScenarios'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(generatedScenarios, hasLength(1));
    expect(generatedScenarios.single, containsPair('platform', 'ohos'));
    final steps = (generatedScenarios.single['steps'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(steps, contains(containsPair('action', 'screenshot')));
    expect(
      steps,
      contains(
        allOf(containsPair('action', 'swipe'), containsPair('optional', true)),
      ),
    );
    final coveragePolicy = automation['coveragePolicy'] as Map<String, Object?>;
    expect(coveragePolicy['coverageSummary'], containsPair('scenarioCount', 0));
    expect(stderr, isEmpty);
  });

  test('drive dry-run auto-discovers package scenarios', () async {
    final environment = await createTestEnvironment();
    await _writePackageManifest(environment.workingDirectory);
    await _writeFlutterPackage(environment.workingDirectory);
    final scenario = File(
      '${environment.workingDirectory.path}/doc/fluoh/camera/scenarios/android-public-api.md',
    );
    await scenario.parent.create(recursive: true);
    await scenario.writeAsString('''
kind: fluoh.automationScenario
schema: 1
name: android public api ready
platform: android
coverage:
  - category: publicApi
    item: camera
    path: success
steps:
  - action: assertLog
    contains: camera-ok
''');
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['drive', 'android', '--package', 'camera', '--dry-run', '--json'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    final automation = report['automation'] as Map<String, Object?>;
    final scenarios = (automation['scenarios'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(scenarios, hasLength(1));
    expect(scenarios.single, containsPair('path', scenario.path));
    expect(
      automation['rerunCommand'],
      allOf(
        contains('fluoh drive android --package camera'),
        contains('--scenario ${scenario.path}'),
        contains('--json'),
      ),
    );
    expect(stderr, isEmpty);
  });

  test(
    'drive dry-run discovers repository scenarios for subpath packages',
    () async {
      final environment = await createTestEnvironment();
      await File(
        '${environment.workingDirectory.path}/fluoh.yaml',
      ).writeAsString('''
schema: 1
kind: package

sdk:
  version: 3.35.8-ohos-0.0.3

repository:
  git:
    url: git@github.com:FlutterOH/camera.git
    branch: ohos/3.35/camera

origin:
  kind: ported

upstream:
  git:
    url: https://github.com/flutter/packages.git
    branch: main

package:
  name: camera
  path: packages/camera/camera
  release:
    version: 0.1.0
    upstream:
      version: 0.11.0
      commit: "1111111111111111111111111111111111111111"
    status: experimental
''');
      await _writeFlutterPackage(
        Directory(
          '${environment.workingDirectory.path}/packages/camera/camera',
        ),
      );
      final scenario = File(
        '${environment.workingDirectory.path}/doc/fluoh/camera/scenarios/android-public-api.md',
      );
      await scenario.parent.create(recursive: true);
      await scenario.writeAsString('''
kind: fluoh.automationScenario
schema: 1
name: android public api ready
platform: android
coverage:
  - category: publicApi
    item: camera
    path: success
steps:
  - action: assertLog
    contains: camera-ok
''');
      final stdout = <String>[];
      final stderr = <String>[];

      expect(
        await runFluoh(
          ['drive', 'android', '--package', 'camera', '--dry-run', '--json'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final report = jsonDecode(stdout.single) as Map<String, Object?>;
      final automation = report['automation'] as Map<String, Object?>;
      final scenarios = (automation['scenarios'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(scenarios, hasLength(1));
      expect(scenarios.single, containsPair('path', scenario.path));
      expect(
        automation['rerunCommand'],
        contains('--scenario ${scenario.path}'),
      );
      expect(stderr, isEmpty);
    },
  );

  test('drive dry-run filters auto-discovered scenarios by platform', () async {
    final environment = await createTestEnvironment();
    await _writePackageManifest(environment.workingDirectory);
    await _writeFlutterPackage(environment.workingDirectory);
    final scenarioDirectory = Directory(
      '${environment.workingDirectory.path}/doc/fluoh/camera/scenarios',
    );
    await scenarioDirectory.create(recursive: true);
    final ohosScenario = File('${scenarioDirectory.path}/ohos-public-api.md');
    await ohosScenario.writeAsString('''
kind: fluoh.automationScenario
schema: 1
name: ohos public api ready
platform: ohos
coverage:
  - category: publicApi
    item: camera
    path: success
steps:
  - action: assertLog
    contains: camera-ok
''');
    final androidScenario = File(
      '${scenarioDirectory.path}/android-public-api.md',
    );
    await androidScenario.writeAsString('''
kind: fluoh.automationScenario
schema: 1
name: android public api ready
platform: android
coverage:
  - category: publicApi
    item: camera
    path: success
steps:
  - action: assertLog
    contains: camera-ok
''');
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['drive', 'ohos', '--package', 'camera', '--dry-run', '--json'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    final automation = report['automation'] as Map<String, Object?>;
    final scenarios = (automation['scenarios'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(scenarios, hasLength(1));
    expect(scenarios.single, containsPair('path', ohosScenario.path));
    expect(
      automation['rerunCommand'],
      allOf(
        contains('--scenario ${ohosScenario.path}'),
        isNot(contains('--scenario ${androidScenario.path}')),
      ),
    );
    expect(stderr, isEmpty);
  });

  test('drive dry-run asks execution after coverage gates are ready', () async {
    final environment = await createTestEnvironment();
    await _writePackageManifest(environment.workingDirectory);
    await _writeFlutterPackage(environment.workingDirectory);
    final scenario = File(
      '${environment.workingDirectory.path}/doc/fluoh/camera/scenarios/android-public-api.md',
    );
    await scenario.parent.create(recursive: true);
    await scenario.writeAsString('''
kind: fluoh.automationScenario
schema: 1
name: android public api ready
platform: android
coverage:
  - category: publicApi
    item: camera
    path: success
  - category: publicApi
    item: camera
    path: error
steps:
  - action: assertLog
    contains: camera-ok
''');
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        [
          'drive',
          'android',
          '--package',
          'camera',
          '--scenario',
          scenario.path,
          '--dry-run',
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
    final automation = report['automation'] as Map<String, Object?>;
    final recommendation =
        automation['deliveryRecommendation'] as Map<String, Object?>;
    expect(recommendation, containsPair('status', 'needsExecution'));
    expect(recommendation, containsPair('ready', false));
    expect(
      recommendation['targetSummary'],
      allOf(containsPair('executed', false), containsPair('dryRun', true)),
    );
    final repairQueue = (automation['repairQueue'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(repairQueue, hasLength(1));
    expect(repairQueue.single, containsPair('type', 'execution'));
    final repairPlan = automation['repairPlan'] as Map<String, Object?>;
    expect(repairPlan, containsPair('status', 'needsExecution'));
    expect(repairPlan, containsPair('queueLength', 1));
    expect(
      repairPlan['nextStep'],
      allOf(
        containsPair('kind', 'executeAutomation'),
        containsPair('sourceType', 'execution'),
        containsPair('nextCommands', isA<List<Object?>>()),
        containsPair(
          'doneWhen',
          contains('the planned automation command exits successfully'),
        ),
        containsPair('validation', containsPair('kind', 'commands')),
      ),
    );
    final nextCommands = (repairQueue.single['nextCommands'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final executionCommand = nextCommands.single['command'] as String;
    expect(
      nextCommands.single,
      allOf(
        containsPair(
          'command',
          contains('fluoh drive android --package camera'),
        ),
        containsPair('command', contains('--scenario ${scenario.path}')),
        containsPair('command', contains('--json')),
      ),
    );
    expect(executionCommand, isNot(contains('fluoh run android')));
    expect(executionCommand, isNot(contains('--dry-run')));
    final coveragePolicy = automation['coveragePolicy'] as Map<String, Object?>;
    expect(coveragePolicy, containsPair('status', 'readyForExecution'));
    expect(coveragePolicy, containsPair('readyForAutomation', true));
    expect(
      coveragePolicy['qualityGateSummary'],
      allOf(
        containsPair('total', greaterThan(0)),
        containsPair('ready', greaterThan(0)),
        containsPair('notReady', isEmpty),
      ),
    );
    final qualityGates = (coveragePolicy['qualityGates'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(
      qualityGates,
      everyElement(containsPair('status', 'readyForReview')),
    );
    expect(
      report['targets'],
      contains(
        allOf(
          containsPair('target', {'kind': 'package', 'name': 'camera'}),
          containsPair('phase', 'automation-dry-run'),
          containsPair('passed', true),
        ),
      ),
    );
    expect(stderr, isEmpty);
  });

  test('drive dry-run quotes executable plan command arguments', () async {
    final environment = await createTestEnvironment();
    await _writePackageManifest(environment.workingDirectory);
    await _writeFlutterPackage(environment.workingDirectory);
    final scenario = File(
      '${environment.workingDirectory.path}/doc/fluoh/camera/scenarios/android-public-api.md',
    );
    await scenario.parent.create(recursive: true);
    await scenario.writeAsString('''
kind: fluoh.automationScenario
schema: 1
name: android public api ready
platform: android
coverage:
  - category: publicApi
    item: camera
    path: success
  - category: publicApi
    item: camera
    path: error
steps:
  - action: assertLog
    contains: camera-ok
''');
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        [
          'drive',
          'android',
          '--package',
          'camera',
          '--emulator',
          'Pixel 35',
          '--session-dir',
          '.fluoh/tasks/manual/evidence/sessions/automation state',
          '--trace-dir',
          '.fluoh/tasks/manual/traces/camera mobile',
          '--scenario',
          scenario.path,
          '--dry-run',
          '--json',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    final automation = report['automation'] as Map<String, Object?>;
    final checks = (automation['checks'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final command = checks.single['command'] as String;
    expect(command, contains("--emulator 'Pixel 35'"));
    expect(
      command,
      contains(
        "--session-file '${environment.workingDirectory.path}/.fluoh/tasks/manual/evidence/sessions/automation state/camera-android-session.json'",
      ),
    );
    expect(
      command,
      contains("--trace-dir '.fluoh/tasks/manual/traces/camera mobile'"),
    );
    expect(stderr, isEmpty);
  });

  test('drive dry-run keeps blocked coverage in the repair queue', () async {
    final environment = await createTestEnvironment();
    await _writePackageManifest(environment.workingDirectory);
    await _writeFlutterPackage(environment.workingDirectory);
    final scenario = File(
      '${environment.workingDirectory.path}/doc/fluoh/camera/scenarios/android-blocked-api.md',
    );
    await scenario.parent.create(recursive: true);
    await scenario.writeAsString('''
kind: fluoh.automationScenario
schema: 1
name: android blocked public api
platform: android
coverage:
  - category: publicApi
    item: camera
    path: success
    status: blocked
    note: Requires a camera-capable emulator fixture.
  - category: publicApi
    item: camera
    path: error
    status: notApplicable
    reason: The package has no error callback for this fixture.
steps:
  - action: wait
    timeoutSeconds: 0
''');
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        [
          'drive',
          'android',
          '--package',
          'camera',
          '--scenario',
          scenario.path,
          '--dry-run',
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
    final automation = report['automation'] as Map<String, Object?>;
    final coveragePolicy = automation['coveragePolicy'] as Map<String, Object?>;
    expect(coveragePolicy, containsPair('status', 'needsAgentCoverageReview'));
    expect(coveragePolicy, containsPair('readyForAutomation', false));
    final qualityGates = (coveragePolicy['qualityGates'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(
      qualityGates,
      contains(
        allOf(
          containsPair('id', 'blocked-coverage'),
          containsPair('status', 'needsBlockedCoverageRepair'),
        ),
      ),
    );
    final recommendation =
        automation['deliveryRecommendation'] as Map<String, Object?>;
    expect(recommendation, containsPair('status', 'needsCoverageReview'));
    expect(recommendation, containsPair('recommendation', 'blocked'));
    final repairQueue = (automation['repairQueue'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(
      repairQueue,
      contains(
        allOf(
          containsPair('type', 'coverage'),
          containsPair('gate', 'blocked-coverage'),
        ),
      ),
    );
    expect(
      repairQueue,
      contains(
        allOf(
          containsPair('type', 'coverageBlocked'),
          containsPair('scenario', 'android blocked public api'),
          containsPair('coverage', containsPair('status', 'blocked')),
        ),
      ),
    );
    expect(stderr, isEmpty);
  });

  test('drive dry-run inventories package evidence and permissions', () async {
    final environment = await createTestEnvironment();
    await _writePackageManifest(environment.workingDirectory);
    await _writeFlutterPackage(environment.workingDirectory);
    await _writeFlutterExample(
      Directory('${environment.workingDirectory.path}/example'),
    );
    final androidManifest = File(
      '${environment.workingDirectory.path}/example/android/app/src/main/AndroidManifest.xml',
    );
    await androidManifest.parent.create(recursive: true);
    await androidManifest.writeAsString('''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
  <uses-permission android:name="android.permission.CAMERA" />
</manifest>
''');
    final iosInfoPlist = File(
      '${environment.workingDirectory.path}/example/ios/Runner/Info.plist',
    );
    await iosInfoPlist.parent.create(recursive: true);
    await iosInfoPlist.writeAsString('''
<plist version="1.0">
<dict>
  <key>NSCameraUsageDescription</key>
  <string>Camera access is required.</string>
  <key>NSUserTrackingUsageDescription</key>
  <string>Tracking access is required.</string>
</dict>
</plist>
''');
    final ohosModule = File(
      '${environment.workingDirectory.path}/example/ohos/entry/src/main/module.json5',
    );
    await ohosModule.parent.create(recursive: true);
    await ohosModule.writeAsString('''
{
  module: {
    requestPermissions: [
      { name: "ohos.permission.CAMERA" }
    ]
  }
}
''');
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['drive', 'android', '--package', 'camera', '--dry-run', '--json'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('ok', true));
    final automation = report['automation'] as Map<String, Object?>;
    final coveragePolicy = automation['coveragePolicy'] as Map<String, Object?>;
    final inventory = coveragePolicy['inventory'] as Map<String, Object?>;
    expect(inventory, containsPair('status', 'ready'));
    expect(inventory, containsPair('targetKind', 'package'));
    expect(inventory, containsPair('targetName', 'camera'));
    final tests = inventory['tests'] as Map<String, Object?>;
    expect(tests, containsPair('publicLibraryFiles', 1));
    expect(tests, containsPair('packageTestFiles', 1));
    expect(tests, containsPair('exampleTestFiles', 1));
    expect(tests, containsPair('totalTestFiles', 2));
    expect(
      tests['coverageBaseline'],
      allOf(
        containsPair('status', 'readyForReview'),
        containsPair('missingPackageTestFiles', 0),
      ),
    );
    final platforms = (inventory['platforms'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(
      platforms,
      contains(
        allOf(
          containsPair('platform', 'android'),
          containsPair('exampleDirectoryExists', true),
        ),
      ),
    );
    expect(
      platforms,
      contains(
        allOf(
          containsPair('platform', 'ios'),
          containsPair('exampleDirectoryExists', true),
        ),
      ),
    );
    expect(
      platforms,
      contains(
        allOf(
          containsPair('platform', 'ohos'),
          containsPair('exampleDirectoryExists', true),
        ),
      ),
    );
    final capabilities = (inventory['capabilities'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(
      capabilities,
      contains(
        allOf(
          containsPair('category', 'publicApi'),
          containsPair('item', 'camera'),
          containsPair('coverageItem', 'camera'),
          containsPair('source', 'publicLibrary'),
        ),
      ),
    );
    final permissions = (inventory['manifestPermissions'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(
      permissions,
      contains(
        allOf(
          containsPair('platform', 'android'),
          containsPair('name', 'android.permission.CAMERA'),
          containsPair('coverageItem', 'camera'),
        ),
      ),
    );
    expect(
      permissions,
      contains(
        allOf(
          containsPair('platform', 'ios'),
          containsPair('name', 'NSCameraUsageDescription'),
          containsPair('coverageItem', 'camera'),
        ),
      ),
    );
    expect(
      permissions,
      contains(
        allOf(
          containsPair('platform', 'ios'),
          containsPair('name', 'NSUserTrackingUsageDescription'),
          containsPair('coverageItem', 'appTrackingTransparency'),
        ),
      ),
    );
    expect(
      permissions,
      contains(
        allOf(
          containsPair('platform', 'ohos'),
          containsPair('name', 'ohos.permission.CAMERA'),
          containsPair('coverageItem', 'camera'),
        ),
      ),
    );
    final qualityGates = coveragePolicy['qualityGates'] as List<Object?>;
    expect(
      qualityGates,
      contains(
        allOf(
          containsPair('id', 'existing-test-baseline'),
          containsPair('status', 'readyForReview'),
        ),
      ),
    );
    expect(
      qualityGates,
      contains(
        allOf(
          containsPair('id', 'capability-inventory-coverage'),
          containsPair('status', 'needsCapabilityCoverageRows'),
          containsPair('capabilities', isA<List<Object?>>()),
          containsPair('missingCapabilities', isA<List<Object?>>()),
        ),
      ),
    );
    expect(
      qualityGates,
      contains(
        allOf(
          containsPair('id', 'manifest-permission-coverage'),
          containsPair('status', 'needsPermissionCoverageRows'),
          containsPair('permissions', isA<List<Object?>>()),
        ),
      ),
    );
    expect(stderr, isEmpty);
  });
}
