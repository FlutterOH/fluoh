part of 'workflow_commands_test.dart';

void _registerWorkflowCommandsProjectAutoTargetTests() {
  test('project run auto emulator prefers iPhone simulator over iPad', () async {
    final environment = await createTestEnvironment();
    final xcrunLog = File('${environment.workingDirectory.path}/xcrun.log');
    final openLog = File('${environment.workingDirectory.path}/open.log');
    final xcrun = await _writeXcrunFixture(
      Directory('${environment.workingDirectory.path}/tools'),
      xcrunLog.path,
      simctlDevicesJson: '''
{
  "devices": {
    "com.apple.CoreSimulator.SimRuntime.iOS-26-4": [
      {
        "name": "iPad (A16)",
        "udid": "SIM-IPAD",
        "state": "Shutdown",
        "isAvailable": true
      }
    ],
    "com.apple.CoreSimulator.SimRuntime.iOS-26-5": [
      {
        "name": "iPhone 17 Pro",
        "udid": "SIM-IPHONE",
        "state": "Shutdown",
        "isAvailable": true
      }
    ]
  }
}
''',
      bootSimulatorId: 'SIM-IPHONE',
    );
    final open = File('${environment.workingDirectory.path}/tools/open');
    await _writeExecutable(open, '''
#!/usr/bin/env bash
printf "%s\\n" "\$*" >> "${openLog.path}"
exit 0
''');
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
      flutterStdout: const {
        'run -d SIM-IPHONE --debug --no-pub':
            'Flutter run key commands.\\nApplication running.',
      },
      flutterStdoutSequences: const {
        'devices --machine': [
          '[]',
          '[{"id":"SIM-IPAD","name":"iPad (A16)","targetPlatform":"ios","isSupported":true,"emulator":true},{"id":"SIM-IPHONE","name":"iPhone 17 Pro","targetPlatform":"ios","isSupported":true,"emulator":true}]',
        ],
      },
    );
    final commandEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: environment.workingDirectory,
      processEnvironment: {
        ...environment.processEnvironment,
        'FLUOH_XCRUN': xcrun.path,
        'FLUOH_OPEN': open.path,
      },
    );
    await writeFlutterProjectFixture(environment.workingDirectory);
    await _writeProjectSdkConfig(environment.workingDirectory);
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'enable', 'fixture', source.path],
      environment: commandEnvironment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    stdout.clear();
    stderr.clear();

    expect(
      await runFluoh(
        ['run', 'ios', '--auto-emulator', '--json'],
        environment: commandEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final root = await environment.workingDirectory.resolveSymbolicLinks();
    final invocations = File(
      '${environment.workingDirectory.path}/package_workflow_invocations.txt',
    ).readAsStringSync();
    expect(
      invocations,
      contains('$root::flutter run -d SIM-IPHONE --debug --no-pub'),
    );
    expect(invocations, isNot(contains('flutter run -d SIM-IPAD')));
    final xcrunInvocations = xcrunLog.readAsStringSync();
    expect(xcrunInvocations, contains('simctl list devices available --json'));
    expect(xcrunInvocations, contains('simctl boot SIM-IPHONE'));
    expect(xcrunInvocations, contains('simctl bootstatus SIM-IPHONE -b'));
    expect(xcrunInvocations, isNot(contains('simctl boot SIM-IPAD')));
    final openInvocations = openLog.readAsStringSync();
    expect(
      openInvocations,
      contains('-a Simulator --args -CurrentDeviceUDID SIM-IPHONE'),
    );
    expect(stderr, isEmpty);
  });

  test('project run auto emulator reuses a running emulator', () async {
    final environment = await createTestEnvironment();
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
      flutterStdout: const {
        'devices --machine':
            '[{"id":"connected-device","name":"Connected Phone","targetPlatform":"android-arm64","isSupported":true},{"id":"emulator-5554","name":"Pixel","targetPlatform":"android-arm64","isSupported":true,"emulator":true}]',
        'run -d emulator-5554 --debug --no-pub':
            'Flutter run key commands.\\nApplication running.',
      },
    );
    await writeFlutterProjectFixture(environment.workingDirectory);
    await _writeProjectSdkConfig(environment.workingDirectory);
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
        ['run', 'android', '--auto-emulator', '--json'],
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
    expect(invocations, isNot(contains('android-emulator -list-avds')));
    expect(
      invocations,
      contains('$root::flutter run -d emulator-5554 --debug --no-pub'),
    );
    expect(invocations, isNot(contains('flutter run -d connected-device')));
    expect(stderr, isEmpty);
  });

  test(
    'project run auto emulator falls back to device when no emulator exists',
    () async {
      final environment = await createTestEnvironment();
      final androidSdk = await _writeAndroidSdkFixture(
        environment.homeDirectory,
        '${environment.workingDirectory.path}/package_workflow_invocations.txt',
        avds: '',
      );
      final source = await _createWorkflowSdkSource(
        environment.homeDirectory,
        environment.workingDirectory,
        flutterStdout: const {
          'devices --machine':
              '[{"id":"connected-device","name":"Connected Phone","targetPlatform":"android-arm64","isSupported":true}]',
          'run -d connected-device --debug --no-pub':
              'Flutter run key commands.\\nApplication running.',
        },
      );
      final commandEnvironment = FluohEnvironment(
        homeDirectory: environment.homeDirectory,
        workingDirectory: environment.workingDirectory,
        processEnvironment: {
          ...environment.processEnvironment,
          'ANDROID_HOME': androidSdk.path,
        },
      );
      await writeFlutterProjectFixture(environment.workingDirectory);
      await _writeProjectSdkConfig(environment.workingDirectory);
      final stdout = <String>[];
      final stderr = <String>[];

      await runFluoh(
        ['source', 'enable', 'fixture', source.path],
        environment: commandEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      stdout.clear();
      stderr.clear();

      expect(
        await runFluoh(
          ['run', 'android', '--auto-emulator', '--json'],
          environment: commandEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final root = await environment.workingDirectory.resolveSymbolicLinks();
      final invocations = File(
        '${environment.workingDirectory.path}/package_workflow_invocations.txt',
      ).readAsStringSync();
      expect(invocations, contains('android-emulator -list-avds'));
      expect(invocations, isNot(contains('android-emulator -avd')));
      expect(
        invocations,
        contains('$root::flutter run -d connected-device --debug --no-pub'),
      );
      expect(stderr, isEmpty);
    },
  );

  test(
    'project run auto emulator falls back to device when emulator list fails',
    () async {
      final environment = await createTestEnvironment();
      final androidSdk = await _writeAndroidSdkFixture(
        environment.homeDirectory,
        '${environment.workingDirectory.path}/package_workflow_invocations.txt',
        emulatorFailures: {'-list-avds': 1},
      );
      final source = await _createWorkflowSdkSource(
        environment.homeDirectory,
        environment.workingDirectory,
        flutterStdout: const {
          'devices --machine':
              '[{"id":"connected-device","name":"Connected Phone","targetPlatform":"android-arm64","isSupported":true}]',
          'run -d connected-device --debug --no-pub':
              'Flutter run key commands.\\nApplication running.',
        },
      );
      final commandEnvironment = FluohEnvironment(
        homeDirectory: environment.homeDirectory,
        workingDirectory: environment.workingDirectory,
        processEnvironment: {
          ...environment.processEnvironment,
          'ANDROID_HOME': androidSdk.path,
        },
      );
      await writeFlutterProjectFixture(environment.workingDirectory);
      await _writeProjectSdkConfig(environment.workingDirectory);
      final stdout = <String>[];
      final stderr = <String>[];

      await runFluoh(
        ['source', 'enable', 'fixture', source.path],
        environment: commandEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      stdout.clear();
      stderr.clear();

      expect(
        await runFluoh(
          ['run', 'android', '--auto-emulator', '--json'],
          environment: commandEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final root = await environment.workingDirectory.resolveSymbolicLinks();
      final invocations = File(
        '${environment.workingDirectory.path}/package_workflow_invocations.txt',
      ).readAsStringSync();
      expect(invocations, contains('android-emulator -list-avds'));
      expect(invocations, isNot(contains('android-emulator -avd')));
      expect(
        invocations,
        contains('$root::flutter run -d connected-device --debug --no-pub'),
      );
      final report = jsonDecode(stdout.single) as Map<String, Object?>;
      final targets = report['targets'] as List<Object?>;
      final target = targets.single as Map<String, Object?>;
      final steps = target['steps'] as List<Object?>;
      final runStep = steps.cast<Map<String, Object?>>().singleWhere(
        (step) => step['name'] == 'project-run-android',
      );
      final details = runStep['details'] as Map<String, Object?>;
      final fallback = details['autoEmulatorFallback'] as Map<String, Object?>;
      final diagnostics = fallback['diagnostics'] as List<Object?>;
      expect(
        diagnostics.cast<Map<String, Object?>>().single,
        containsPair('code', 'android.emulators_failed'),
      );
      expect(stderr, isEmpty);
    },
  );

  test('project run desktop auto emulator uses the host target', () async {
    final environment = await createTestEnvironment();
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
      flutterStdout: const {
        'devices --machine':
            '[{"id":"linux","name":"Linux","targetPlatform":"linux-x64","isSupported":true}]',
        'run -d linux --debug --no-pub':
            'Flutter run key commands.\\nApplication running.',
      },
    );
    await writeFlutterProjectFixture(environment.workingDirectory);
    await _writeProjectSdkConfig(environment.workingDirectory);
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
        ['run', 'linux', '--auto-emulator', '--json'],
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
    expect(invocations, isNot(contains('native emulator')));
    expect(
      invocations,
      contains('$root::flutter run -d linux --debug --no-pub'),
    );
    expect(stderr, isEmpty);
  });

  test('project run web auto emulator uses browser target', () async {
    final environment = await createTestEnvironment();
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
      flutterStdout: const {
        'devices --machine':
            '[{"id":"chrome","name":"Chrome","targetPlatform":"web-javascript","isSupported":true},{"id":"web-server","name":"Web Server","targetPlatform":"web-javascript","isSupported":true}]',
        'run -d chrome --debug --no-pub':
            'Flutter run key commands.\\nApplication running.',
      },
    );
    await writeFlutterProjectFixture(environment.workingDirectory);
    await _writeProjectSdkConfig(environment.workingDirectory);
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
        ['run', 'web', '--auto-emulator', '--json'],
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
    expect(invocations, isNot(contains('native emulator')));
    expect(
      invocations,
      contains('$root::flutter run -d chrome --debug --no-pub'),
    );
    expect(invocations, isNot(contains('run -d web-server')));
    expect(stderr, isEmpty);
  });

  test(
    'project desktop and web run diagnostics omit auto emulator next command',
    () async {
      final environment = await createTestEnvironment();
      final source = await _createWorkflowSdkSource(
        environment.homeDirectory,
        environment.workingDirectory,
        flutterStdout: const {'devices --machine': '[]'},
      );
      await writeFlutterProjectFixture(environment.workingDirectory);
      await _writeProjectSdkConfig(environment.workingDirectory);
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
          ['run', 'linux', '--auto-emulator', '--json'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        1,
      );

      final report = jsonDecode(stdout.single) as Map<String, Object?>;
      final targets = report['targets'] as List<Object?>;
      final target = targets.single as Map<String, Object?>;
      final steps = target['steps'] as List<Object?>;
      final runStep = steps.single as Map<String, Object?>;
      final diagnostics = runStep['diagnostics'] as List<Object?>;
      final diagnostic = diagnostics.single as Map<String, Object?>;
      expect(diagnostic, containsPair('code', 'linux.device_missing'));
      expect(diagnostic, containsPair('nextCommand', 'fluoh run linux --json'));
      stdout.clear();
      stderr.clear();

      expect(
        await runFluoh(
          ['run', 'web', '--auto-emulator', '--json'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        1,
      );

      final webReport = jsonDecode(stdout.single) as Map<String, Object?>;
      final webTargets = webReport['targets'] as List<Object?>;
      final webTarget = webTargets.single as Map<String, Object?>;
      final webSteps = webTarget['steps'] as List<Object?>;
      final webRunStep = webSteps.single as Map<String, Object?>;
      final webDiagnostics = webRunStep['diagnostics'] as List<Object?>;
      final webDiagnostic = webDiagnostics.single as Map<String, Object?>;
      expect(webDiagnostic, containsPair('code', 'web.device_missing'));
      expect(
        webDiagnostic,
        containsPair('nextCommand', 'fluoh doctor --platform web --json'),
      );
      expect(stderr, isEmpty);
    },
  );

  test('project run diagnostics preserve requested emulator', () async {
    final environment = await createTestEnvironment();
    final androidSdk = await _writeAndroidSdkFixture(
      environment.homeDirectory,
      '${environment.workingDirectory.path}/package_workflow_invocations.txt',
    );
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
      flutterFailures: const {'run -d emulator-5554 --debug --no-pub': 2},
      flutterStdoutSequences: const {
        'devices --machine': [
          '[{"id":"connected-device","name":"Connected Phone","targetPlatform":"android-arm64","isSupported":true}]',
          '[{"id":"connected-device","name":"Connected Phone","targetPlatform":"android-arm64","isSupported":true},{"id":"emulator-5554","name":"Pixel","targetPlatform":"android-arm64","isSupported":true}]',
        ],
      },
    );
    final commandEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: environment.workingDirectory,
      processEnvironment: {
        ...environment.processEnvironment,
        'ANDROID_HOME': androidSdk.path,
      },
    );
    await writeFlutterProjectFixture(environment.workingDirectory);
    await _writeProjectSdkConfig(environment.workingDirectory);
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'enable', 'fixture', source.path],
      environment: commandEnvironment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    stdout.clear();
    stderr.clear();

    expect(
      await runFluoh(
        ['run', 'android', '--emulator', 'Pixel_35', '--json'],
        environment: commandEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      1,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    final targets = report['targets'] as List<Object?>;
    final target = targets.single as Map<String, Object?>;
    final steps = target['steps'] as List<Object?>;
    final runStep = steps.cast<Map<String, Object?>>().singleWhere(
      (step) => step['name'] == 'project-run-android',
    );
    final diagnostics = runStep['diagnostics'] as List<Object?>;
    final diagnostic = diagnostics.single as Map<String, Object?>;
    expect(diagnostic, containsPair('code', 'android.run_failed'));
    expect(
      diagnostic,
      containsPair(
        'nextCommand',
        'fluoh run android --emulator Pixel_35 --json',
      ),
    );
    expect(stderr, isEmpty);
  });

  test('can run Android example and integration tests', () async {
    final environment = await createTestEnvironment();
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
      flutterStdout: const {
        'devices --machine':
            '[{"id":"emulator-5554","name":"Pixel","targetPlatform":"android-arm64","isSupported":true}]',
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
    await Directory(
      '${environment.workingDirectory.path}/example/integration_test',
    ).create(recursive: true);
    await File(
      '${environment.workingDirectory.path}/example/integration_test/app_test.dart',
    ).writeAsString('''
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('fixture integration test', (tester) async {});
}
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
          'run',
          'android',
          '--session-file',
          '.fluoh/run-session.json',
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
    expect(invocations, contains('$root/example::flutter build apk --debug'));
    expect(
      invocations,
      contains('$root/example::flutter run -d emulator-5554 --debug --no-pub'),
    );
    expect(
      invocations,
      contains('$root/example::flutter test integration_test -d emulator-5554'),
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('ok', true));
    final targets = report['targets'] as List<Object?>;
    final target = targets.single as Map<String, Object?>;
    final steps = target['steps'] as List<Object?>;
    expect(
      steps,
      contains(
        allOf(
          containsPair('name', 'example-run-android'),
          containsPair(
            'command',
            'flutter run -d emulator-5554 --debug --no-pub',
          ),
          containsPair('status', 'passed'),
        ),
      ),
    );
    final runStep = steps.cast<Map<String, Object?>>().singleWhere(
      (step) => step['name'] == 'example-run-android',
    );
    final runDetails = runStep['details'] as Map<String, Object?>;
    expect(
      runDetails,
      containsPair('vmServiceUri', 'http://127.0.0.1:12345/abc=/'),
    );
    expect(
      runDetails,
      containsPair(
        'sessionFile',
        '${environment.workingDirectory.path}/.fluoh/run-session.json',
      ),
    );
    expect(
      runDetails['outputLog'],
      allOf(
        startsWith('${environment.workingDirectory.path}/.fluoh/tasks/'),
        contains('/evidence/logs/flutter-run-android-'),
      ),
    );
    final session =
        jsonDecode(
              File(
                '${environment.workingDirectory.path}/.fluoh/run-session.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    expect(session, containsPair('kind', 'flutterRunSession'));
    expect(session, containsPair('status', 'passed'));
    expect(session, containsPair('platform', 'android'));
    expect(session, containsPair('launchDetected', true));
    expect(
      session,
      containsPair('vmServiceUri', 'http://127.0.0.1:12345/abc=/'),
    );
    expect(session['processId'], isA<int>());
    expect(
      steps,
      contains(
        allOf(
          containsPair('name', 'example-integration-android'),
          containsPair(
            'command',
            'flutter test integration_test -d emulator-5554',
          ),
          containsPair('status', 'passed'),
        ),
      ),
    );
    expect(stderr, isEmpty);
  });
}
