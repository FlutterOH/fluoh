part of 'workflow_commands_test.dart';

void _registerWorkflowCommandsDriveCoverageTests() {
  test('drive dry-run reports generic package capability gaps', () async {
    final environment = await createTestEnvironment();
    await File('${environment.workingDirectory.path}/fluoh.yaml').writeAsString(
      '''
schema: 1
kind: package

sdk:
  version: 3.35.8-ohos-0.0.3

repository:
  git:
    url: git@github.com:FlutterOH/sample_tool.git
    branch: ohos/3.35/sample_tool

upstream:
  git:
    url: https://github.com/example/sample_tool.git
    branch: main

package:
  name: sample_tool
  path: .
  release:
    version: 0.1.0
    upstream:
      version: 1.0.0
      commit: "1111111111111111111111111111111111111111"
    status: experimental
''',
    );
    await File(
      '${environment.workingDirectory.path}/pubspec.yaml',
    ).writeAsString('''
name: sample_tool
version: 1.0.0

environment:
  sdk: ^3.0.0

dependencies:
  flutter:
    sdk: flutter

dev_dependencies:
  flutter_test:
    sdk: flutter
''');
    await Directory(
      '${environment.workingDirectory.path}/lib/src',
    ).create(recursive: true);
    await File(
      '${environment.workingDirectory.path}/lib/sample_tool.dart',
    ).writeAsString('''
export 'src/exported_tool.dart';

class SampleTool {}

Future<String> formatSample(String value) async => value;

String get sampleVersion => '1.0.0';

const sampleLimit = 10;
''');
    await File(
      '${environment.workingDirectory.path}/lib/src/exported_tool.dart',
    ).writeAsString('''
class ExportedTool {}
''');
    await File(
      '${environment.workingDirectory.path}/lib/src/sample_channel.dart',
    ).writeAsString('''
import 'package:flutter/services.dart';

class SampleChannel {
  Future<void> open() {
    return const MethodChannel('sample_tool').invokeMethod('openPicker');
  }

  Stream<dynamic> events() {
    return const EventChannel('sample/events').receiveBroadcastStream();
  }

  BasicMessageChannel<String?> messages() {
    return const BasicMessageChannel<String?>('sample/messages', StringCodec());
  }
}
''');
    await Directory(
      '${environment.workingDirectory.path}/example/lib',
    ).create(recursive: true);
    await File(
      '${environment.workingDirectory.path}/example/lib/main.dart',
    ).writeAsString('void main() {}\n');
    final scenario = File(
      '${environment.workingDirectory.path}/.fluoh/scenarios/sample_tool/android-public-api.md',
    );
    await scenario.parent.create(recursive: true);
    await scenario.writeAsString('''
kind: fluoh.automationScenario
schema: 1
name: sample public api
platform: android
coverage:
  - category: publicApi
    item: SampleTool
    path: success
steps:
  - action: assertLog
    contains: sample-ok
''');
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        [
          'drive',
          'android',
          '--package',
          'sample_tool',
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
    final minimumGates = (coveragePolicy['minimumGates'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final interactionGate = minimumGates.singleWhere(
      (gate) => gate['id'] == 'interaction-matrix',
    );
    expect(
      interactionGate['rule'],
      contains('manual-assisted tool-readable evidence'),
    );
    final coverageSummary =
        coveragePolicy['coverageSummary'] as Map<String, Object?>;
    expect(coverageSummary, containsPair('capabilityCount', 10));
    expect(coverageSummary, containsPair('capabilityCoverageWarningCount', 9));
    final inventory = coveragePolicy['inventory'] as Map<String, Object?>;
    final capabilities = (inventory['capabilities'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(
      capabilities,
      contains(
        allOf(
          containsPair('category', 'publicApi'),
          containsPair('item', 'SampleTool'),
        ),
      ),
    );
    expect(
      capabilities,
      contains(
        allOf(
          containsPair('category', 'publicApi'),
          containsPair('item', 'ExportedTool'),
          containsPair('path', endsWith('/lib/src/exported_tool.dart')),
        ),
      ),
    );
    expect(
      capabilities,
      contains(
        allOf(
          containsPair('category', 'publicApi'),
          containsPair('item', 'formatSample'),
        ),
      ),
    );
    expect(
      capabilities,
      contains(
        allOf(
          containsPair('category', 'publicApi'),
          containsPair('item', 'sampleVersion'),
        ),
      ),
    );
    expect(
      capabilities,
      contains(
        allOf(
          containsPair('category', 'publicApi'),
          containsPair('item', 'sampleLimit'),
        ),
      ),
    );
    expect(
      capabilities,
      contains(
        allOf(
          containsPair('category', 'methodChannel'),
          containsPair('item', 'openPicker'),
        ),
      ),
    );
    expect(
      capabilities,
      contains(
        allOf(
          containsPair('category', 'platformChannel'),
          containsPair('item', 'sample_tool'),
        ),
      ),
    );
    expect(
      capabilities,
      contains(
        allOf(
          containsPair('category', 'platformChannel'),
          containsPair('item', 'sample/events'),
        ),
      ),
    );
    expect(
      capabilities,
      contains(
        allOf(
          containsPair('category', 'platformChannel'),
          containsPair('item', 'sample/messages'),
        ),
      ),
    );
    expect(
      capabilities,
      contains(
        allOf(
          containsPair('category', 'exampleFlow'),
          containsPair('item', 'main'),
        ),
      ),
    );
    final capabilityCoverage =
        (coveragePolicy['capabilityCoverage'] as List<Object?>)
            .cast<Map<String, Object?>>();
    expect(
      capabilityCoverage,
      contains(
        allOf(
          containsPair('category', 'publicApi'),
          containsPair('item', 'SampleTool'),
          containsPair('status', 'readyForReview'),
        ),
      ),
    );
    final qualityGates = (coveragePolicy['qualityGates'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final capabilityGate = qualityGates.singleWhere(
      (gate) => gate['id'] == 'capability-inventory-coverage',
    );
    expect(
      capabilityGate,
      containsPair('status', 'needsCapabilityCoverageRows'),
    );
    final missingCapabilities =
        (capabilityGate['missingCapabilities'] as List<Object?>)
            .cast<Map<String, Object?>>();
    expect(
      missingCapabilities.map((item) => item['item']),
      containsAll([
        'ExportedTool',
        'formatSample',
        'main',
        'openPicker',
        'sample/events',
        'sample/messages',
        'sampleLimit',
        'sampleVersion',
        'sample_tool',
      ]),
    );
    expect(
      missingCapabilities.first['suggestedCoverage'],
      isA<List<Object?>>(),
    );
    final repairQueue = (automation['repairQueue'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(repairQueue.first, containsPair('type', 'scenarioCoverage'));
    final rerunCommand = automation['rerunCommand'] as String;
    expect(
      rerunCommand,
      allOf(
        contains('fluoh drive android --package sample_tool'),
        contains('--scenario ${scenario.path}'),
        contains('--dry-run --json'),
      ),
    );
    final repairPlan = automation['repairPlan'] as Map<String, Object?>;
    expect(repairPlan, containsPair('status', 'needsCoverageReview'));
    expect(
      repairPlan['nextStep'],
      allOf(
        containsPair('kind', 'addScenarioCoverageRows'),
        containsPair('sourceType', 'scenarioCoverage'),
        containsPair('gate', 'capability-inventory-coverage'),
        containsPair('nextAction', isA<Map<String, Object?>>()),
        containsPair(
          'doneWhen',
          contains(contains('capability coverage reports readyForReview')),
        ),
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
          containsPair('type', 'scenarioCoverage'),
          containsPair('gate', 'capability-inventory-coverage'),
          containsPair('item', 'openPicker'),
          containsPair(
            'nextAction',
            allOf(
              containsPair('kind', 'addScenarioCoverageRows'),
              containsPair(
                'scenarioCandidates',
                contains(
                  allOf(
                    containsPair('platform', 'android'),
                    containsPair(
                      'path',
                      endsWith(
                        '/.fluoh/scenarios/sample_tool/android-openPicker.md',
                      ),
                    ),
                  ),
                ),
              ),
              containsPair(
                'coverage',
                contains(
                  allOf(
                    containsPair('category', 'methodChannel'),
                    containsPair('item', 'openPicker'),
                    containsPair('path', 'success'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(stderr, isEmpty);
  });

  test('drive dry-run requires every manifest permission row', () async {
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
  <uses-permission android:name="android.permission.GET_ACCOUNTS" />
  <uses-permission android:name="android.permission.RECEIVE_MMS" />
  <uses-permission android:name="android.permission.READ_MEDIA_AUDIO" />
  <uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />
  <uses-permission android:name="android.permission.NEARBY_WIFI_DEVICES" />
  <uses-permission android:name="android.permission.RECORD_AUDIO" />
</manifest>
''');
    final scenario = File(
      '${environment.workingDirectory.path}/.fluoh/scenarios/camera/android-camera.md',
    );
    await scenario.parent.create(recursive: true);
    await scenario.writeAsString('''
kind: fluoh.automationScenario
schema: 1
name: android camera only
platform: android
coverage:
  - category: permission
    item: camera
    path: grant
  - category: permission
    item: camera
    path: deny
  - category: permission
    item: contacts
    path: grant
  - category: permission
    item: contacts
    path: deny
  - category: permission
    item: sms
    path: grant
  - category: permission
    item: sms
    path: deny
  - category: permission
    item: audio
    path: grant
  - category: permission
    item: audio
    path: deny
  - category: permission
    item: ignoreBatteryOptimizations
    path: grant
  - category: permission
    item: ignoreBatteryOptimizations
    path: deny
  - category: permission
    item: nearbyWifiDevices
    path: grant
  - category: permission
    item: nearbyWifiDevices
    path: deny
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
    final manifestPermissionCoverage =
        (coveragePolicy['manifestPermissionCoverage'] as List<Object?>)
            .cast<Map<String, Object?>>();
    expect(
      manifestPermissionCoverage,
      contains(
        allOf(
          containsPair('permission', 'android.permission.CAMERA'),
          containsPair('coverageItem', 'camera'),
          containsPair('status', 'readyForReview'),
        ),
      ),
    );
    expect(
      manifestPermissionCoverage,
      contains(
        allOf(
          containsPair('permission', 'android.permission.GET_ACCOUNTS'),
          containsPair('coverageItem', 'contacts'),
          containsPair('status', 'readyForReview'),
        ),
      ),
    );
    expect(
      manifestPermissionCoverage,
      contains(
        allOf(
          containsPair('permission', 'android.permission.RECEIVE_MMS'),
          containsPair('coverageItem', 'sms'),
          containsPair('status', 'readyForReview'),
        ),
      ),
    );
    expect(
      manifestPermissionCoverage,
      contains(
        allOf(
          containsPair('permission', 'android.permission.READ_MEDIA_AUDIO'),
          containsPair('coverageItem', 'audio'),
          containsPair('status', 'readyForReview'),
        ),
      ),
    );
    expect(
      manifestPermissionCoverage,
      contains(
        allOf(
          containsPair(
            'permission',
            'android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
          ),
          containsPair('coverageItem', 'ignoreBatteryOptimizations'),
          containsPair('status', 'readyForReview'),
        ),
      ),
    );
    expect(
      manifestPermissionCoverage,
      contains(
        allOf(
          containsPair('permission', 'android.permission.NEARBY_WIFI_DEVICES'),
          containsPair('coverageItem', 'nearbyWifiDevices'),
          containsPair('status', 'readyForReview'),
        ),
      ),
    );
    expect(
      manifestPermissionCoverage,
      contains(
        allOf(
          containsPair('permission', 'android.permission.RECORD_AUDIO'),
          containsPair('coverageItem', 'microphone'),
          containsPair('status', 'needsPermissionCoverageRows'),
          containsPair('needsPositivePath', true),
          containsPair('needsNegativeOrErrorPath', true),
        ),
      ),
    );
    final qualityGates = coveragePolicy['qualityGates'] as List<Object?>;
    final permissionGate = qualityGates
        .cast<Map<String, Object?>>()
        .singleWhere((gate) => gate['id'] == 'manifest-permission-coverage');
    expect(
      permissionGate,
      containsPair('status', 'needsPermissionCoverageRows'),
    );
    final missingPermissions =
        (permissionGate['missingPermissions'] as List<Object?>)
            .cast<Map<String, Object?>>();
    expect(missingPermissions, hasLength(1));
    expect(
      missingPermissions.single,
      allOf(
        containsPair('permission', 'android.permission.RECORD_AUDIO'),
        containsPair('coverageItem', 'microphone'),
      ),
    );
    expect(
      missingPermissions.single['suggestedCoverage'],
      contains(
        allOf(
          containsPair('category', 'permission'),
          containsPair('item', 'microphone'),
          containsPair('path', 'grant'),
        ),
      ),
    );
    final repairQueue = (automation['repairQueue'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(repairQueue.first['type'], isNot('coverage'));
    expect(
      repairQueue,
      contains(
        allOf(
          containsPair('type', 'permissionCoverage'),
          containsPair('gate', 'manifest-permission-coverage'),
          containsPair('platform', 'android'),
          containsPair('permission', 'android.permission.RECORD_AUDIO'),
          containsPair('coverageItem', 'microphone'),
          containsPair(
            'nextAction',
            allOf(
              containsPair('kind', 'addScenarioCoverageRows'),
              containsPair('platform', 'android'),
              containsPair(
                'path',
                endsWith('/.fluoh/scenarios/camera/android-microphone.md'),
              ),
              containsPair(
                'scenarioCandidates',
                contains(
                  allOf(
                    containsPair('platform', 'android'),
                    containsPair(
                      'path',
                      endsWith(
                        '/.fluoh/scenarios/camera/android-microphone.md',
                      ),
                    ),
                  ),
                ),
              ),
              containsPair(
                'coverage',
                contains(
                  allOf(
                    containsPair('category', 'permission'),
                    containsPair('item', 'microphone'),
                    containsPair('path', 'deny'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(stderr, isEmpty);
  });

  test('drive dry-run keeps blocked coverage rows in repair queue', () async {
    final environment = await createTestEnvironment();
    await _writePackageManifest(environment.workingDirectory);
    await _writeFlutterPackage(environment.workingDirectory);
    await _writeFlutterExample(
      Directory('${environment.workingDirectory.path}/example'),
    );
    final scenario = File(
      '${environment.workingDirectory.path}/.fluoh/scenarios/camera/android-blocked.md',
    );
    await scenario.parent.create(recursive: true);
    await scenario.writeAsString('''
kind: fluoh.automationScenario
schema: 1
name: android blocked camera
platform: android
coverage:
  - category: permission
    item: camera
    path: grant
    status: blocked
    note: missing grant automation
  - category: permission
    item: camera
    path: deny
    status: blocked
    note: missing deny automation
steps:
  - action: waitText
    labels: [Permission.camera]
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
    final automation = report['automation'] as Map<String, Object?>;
    final coveragePolicy = automation['coveragePolicy'] as Map<String, Object?>;
    expect(coveragePolicy, containsPair('status', 'needsAgentCoverageReview'));
    expect(coveragePolicy, containsPair('readyForAutomation', false));
    final qualityGates = (coveragePolicy['qualityGates'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final blockedGate = qualityGates.singleWhere(
      (gate) => gate['id'] == 'blocked-coverage',
    );
    expect(
      blockedGate,
      allOf(
        containsPair('status', 'needsBlockedCoverageRepair'),
        containsPair('blockedCoverageCount', 2),
      ),
    );
    final delivery =
        automation['deliveryRecommendation'] as Map<String, Object?>;
    expect(delivery, containsPair('recommendation', 'blocked'));
    expect(delivery, containsPair('status', 'needsCoverageReview'));
    final repairQueue = (automation['repairQueue'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(
      repairQueue,
      contains(
        allOf(
          containsPair('type', 'coverage'),
          containsPair('gate', 'blocked-coverage'),
          containsPair('status', 'needsBlockedCoverageRepair'),
        ),
      ),
    );
    expect(
      repairQueue,
      contains(
        allOf(
          containsPair('type', 'coverageBlocked'),
          containsPair('platform', 'android'),
          containsPair('scenario', 'android blocked camera'),
        ),
      ),
    );
    expect(stderr, isEmpty);
  });
}
