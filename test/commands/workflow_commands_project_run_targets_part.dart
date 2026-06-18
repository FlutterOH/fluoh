part of 'workflow_commands_test.dart';

void _registerWorkflowCommandsProjectRunTargetTests() {
  test(
    'project run integration test failure preserves device next command',
    () async {
      final environment = await createTestEnvironment();
      final source = await _createWorkflowSdkSource(
        environment.homeDirectory,
        environment.workingDirectory,
        flutterStdout: const {
          'devices --machine':
              '[{"id":"emulator-5554","name":"Pixel","targetPlatform":"android-arm64","isSupported":true}]',
          'run -d emulator-5554 --debug --no-pub':
              'Flutter run key commands.\\nApplication running.',
        },
        flutterFailures: const {'test integration_test -d emulator-5554': 9},
      );
      await writeFlutterProjectFixture(environment.workingDirectory);
      await _writeProjectSdkConfig(environment.workingDirectory);
      await Directory(
        '${environment.workingDirectory.path}/integration_test',
      ).create(recursive: true);
      await File(
        '${environment.workingDirectory.path}/integration_test/app_test.dart',
      ).writeAsString('void main() {}\n');
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
          ['run', 'android', '--device-id', 'emulator-5554', '--json'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        9,
      );

      final report = jsonDecode(stdout.single) as Map<String, Object?>;
      expect(report, containsPair('ok', false));
      final targets = report['targets'] as List<Object?>;
      final target = targets.single as Map<String, Object?>;
      expect(
        target,
        containsPair(
          'nextCommand',
          'fluoh run android --device-id emulator-5554 --json',
        ),
      );
      final steps = target['steps'] as List<Object?>;
      final integrationStep = steps.cast<Map<String, Object?>>().singleWhere(
        (step) => step['name'] == 'project-integration-android',
      );
      expect(integrationStep, containsPair('status', 'failed'));
      expect(
        integrationStep,
        containsPair(
          'nextCommand',
          'fluoh run android --device-id emulator-5554 --json',
        ),
      );
      final diagnostics = integrationStep['diagnostics'] as List<Object?>;
      final diagnostic = diagnostics.single as Map<String, Object?>;
      expect(
        diagnostic,
        containsPair('code', 'android.integration_test_failed'),
      );
      expect(
        diagnostic,
        containsPair(
          'nextCommand',
          'fluoh run android --device-id emulator-5554 --json',
        ),
      );
      expect(stderr, isEmpty);
    },
  );

  test('project run starts requested emulator before selecting device', () async {
    final environment = await createTestEnvironment();
    final androidSdk = await _writeAndroidSdkFixture(
      environment.homeDirectory,
      '${environment.workingDirectory.path}/package_workflow_invocations.txt',
    );
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
      flutterStdout: const {
        'run -d emulator-5554 --debug --no-pub':
            'Flutter run key commands.\\nApplication running.',
      },
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
      0,
    );

    final root = await environment.workingDirectory.resolveSymbolicLinks();
    final invocations = File(
      '${environment.workingDirectory.path}/package_workflow_invocations.txt',
    ).readAsStringSync();
    expect(invocations, contains('android-emulator -list-avds'));
    expect(invocations, contains('android-emulator -avd Pixel_35'));
    expect(
      invocations,
      contains('$root::flutter run -d emulator-5554 --debug --no-pub'),
    );
    expect(invocations, isNot(contains('flutter run -d connected-device')));

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('ok', true));
    final targets = report['targets'] as List<Object?>;
    final target = targets.single as Map<String, Object?>;
    final steps = target['steps'] as List<Object?>;
    expect(
      steps,
      contains(
        allOf(
          containsPair('name', 'project-run-android'),
          containsPair(
            'command',
            'flutter run -d emulator-5554 --debug --no-pub',
          ),
          containsPair('status', 'passed'),
        ),
      ),
    );
    expect(stderr, isEmpty);
  });

  test(
    'project OHOS run maps requested emulator to localhost Flutter device',
    () async {
      final environment = await createTestEnvironment();
      final hdcLog = File('${environment.homeDirectory.path}/hdc.log');
      final devEco = await _writeWorkflowDevEcoFixture(
        environment.homeDirectory,
        hdcLog: hdcLog,
        targets: '127.0.0.1:5555\n',
      );
      final deployed = Directory('${environment.homeDirectory.path}/deployed')
        ..createSync(recursive: true);
      final emulatorDirectory = Directory('${deployed.path}/Huawei_Phone')
        ..createSync(recursive: true);
      await File(
        '${emulatorDirectory.path}/config.ini',
      ).writeAsString('hw.lcd.density=520\n');
      await File('${deployed.path}/lists.json').writeAsString(
        jsonEncode([
          {'name': 'Huawei_Phone', 'apiVersion': 19},
        ]),
      );
      final imageRoot = Directory(
        '${environment.homeDirectory.path}/Huawei/Sdk',
      )..createSync(recursive: true);
      const ohosLocalhostDevice =
          '[{"id":"127.0.0.1:5555","name":"127.0.0.1:5555",'
          '"targetPlatform":"ohos-arm64","isSupported":true,'
          '"emulator":false}]';
      final source = await _createWorkflowSdkSource(
        environment.homeDirectory,
        environment.workingDirectory,
        flutterStdout: const {
          'run -d 127.0.0.1:5555 --debug --no-pub': _ohosFlutterRunStdout,
        },
        flutterStdoutSequences: const {
          'devices --machine': [ohosLocalhostDevice, ohosLocalhostDevice],
        },
      );
      final workflowEnvironment = FluohEnvironment(
        homeDirectory: environment.homeDirectory,
        workingDirectory: environment.workingDirectory,
        processEnvironment: {
          ...environment.processEnvironment,
          'FLUOH_DEVECO_STUDIO': devEco.path,
          'FLUOH_OHOS_EMULATOR_DEPLOYED': deployed.path,
          'FLUOH_HARMONYOS_SDK_ROOT': imageRoot.path,
          'FLUOH_OHOS_EMULATOR_MIN_FREE_KB': '0',
        },
      );
      await writeFlutterProjectFixture(environment.workingDirectory);
      await _writeWorkflowOhosProject(environment.workingDirectory);
      await _writeProjectSdkConfig(environment.workingDirectory);
      final stdout = <String>[];
      final stderr = <String>[];

      await runFluoh(
        ['source', 'enable', 'fixture', source.path],
        environment: workflowEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      stdout.clear();
      stderr.clear();

      final exitCode = await runFluoh(
        [
          'run',
          'ohos',
          '--emulator',
          'Huawei_Phone',
          '--device-timeout',
          '1',
          '--json',
        ],
        environment: workflowEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      );

      expect(exitCode, 0, reason: 'stdout=$stdout stderr=$stderr');

      final root = await environment.workingDirectory.resolveSymbolicLinks();
      final invocations = File(
        '${environment.workingDirectory.path}/package_workflow_invocations.txt',
      ).readAsStringSync();
      expect(
        invocations,
        contains('$root::flutter run -d 127.0.0.1:5555 --debug --no-pub'),
      );
      final report = jsonDecode(stdout.single) as Map<String, Object?>;
      final targets = report['targets'] as List<Object?>;
      final target = targets.single as Map<String, Object?>;
      final steps = target['steps'] as List<Object?>;
      final runStep = steps.cast<Map<String, Object?>>().singleWhere(
        (step) => step['name'] == 'project-run-ohos',
      );
      expect(runStep, containsPair('status', 'passed'));
      final details = runStep['details'] as Map<String, Object?>;
      expect(
        details['emulator'],
        allOf(isA<Map<String, Object?>>(), containsPair('id', 'Huawei_Phone')),
      );
      expect(details, containsPair('targetId', '127.0.0.1:5555'));
      expect(stderr, isEmpty);
    },
  );

  test(
    'project run polls devices once when immediate emulator timeout expires',
    () async {
      final environment = await createTestEnvironment();
      final androidSdk = await _writeAndroidSdkFixture(
        environment.homeDirectory,
        '${environment.workingDirectory.path}/package_workflow_invocations.txt',
      );
      final source = await _createWorkflowSdkSource(
        environment.homeDirectory,
        environment.workingDirectory,
        flutterStdoutSequences: const {
          'devices --machine': ['[]', '[]'],
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
          [
            'run',
            'android',
            '--emulator',
            'Pixel_35',
            '--device-timeout',
            '0',
            '--json',
          ],
          environment: commandEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        1,
      );

      final root = await environment.workingDirectory.resolveSymbolicLinks();
      final invocations = File(
        '${environment.workingDirectory.path}/package_workflow_invocations.txt',
      ).readAsLinesSync();
      expect(
        invocations.where((line) => line == '$root::flutter devices --machine'),
        hasLength(2),
      );
      expect(
        invocations.any(
          (line) => line.contains('android-emulator -avd Pixel_35'),
        ),
        isTrue,
      );

      final report = jsonDecode(stdout.single) as Map<String, Object?>;
      expect(report, containsPair('ok', false));
      final targets = report['targets'] as List<Object?>;
      final target = targets.single as Map<String, Object?>;
      final steps = target['steps'] as List<Object?>;
      final runStep = steps.cast<Map<String, Object?>>().singleWhere(
        (step) => step['name'] == 'project-run-android',
      );
      expect(runStep, containsPair('status', 'failed'));
      final details = runStep['details'] as Map<String, Object?>;
      expect(details, containsPair('timeoutSeconds', 0));
      expect(details, containsPair('stdoutTail', '[]'));
      final diagnostics = runStep['diagnostics'] as List<Object?>;
      expect(
        diagnostics.single,
        allOf(
          isA<Map<String, Object?>>(),
          containsPair('code', 'android.device_missing'),
        ),
      );
      expect(stderr, isEmpty);
    },
  );

  test('project run starts requested iOS simulator by name', () async {
    final environment = await createTestEnvironment();
    final xcrunLog = File('${environment.workingDirectory.path}/xcrun.log');
    final openLog = File('${environment.workingDirectory.path}/open.log');
    final tools = Directory('${environment.workingDirectory.path}/tools');
    final xcrun = await _writeXcrunFixture(
      tools,
      xcrunLog.path,
      simctlDevicesJson: '''
{
  "devices": {
    "com.apple.CoreSimulator.SimRuntime.iOS-26-5": [
      {
        "name": "iPhone 17 Pro",
        "udid": "SIM-IPHONE",
        "state": "Shutdown",
        "isAvailable": true
      },
      {
        "name": "iPad (A16)",
        "udid": "SIM-IPAD",
        "state": "Shutdown",
        "isAvailable": true
      }
    ]
  }
}
''',
      bootSimulatorId: 'SIM-IPHONE',
    );
    final open = File('${tools.path}/open');
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
          '[{"id":"SIM-IPHONE","name":"iPhone 17 Pro","targetPlatform":"ios","isSupported":true,"emulator":true}]',
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
        ['run', 'ios', '--emulator', 'iPhone 17 Pro', '--json'],
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

  test(
    'project run auto emulator prefers emulator over connected device',
    () async {
      final environment = await createTestEnvironment();
      final androidSdk = await _writeAndroidSdkFixture(
        environment.homeDirectory,
        '${environment.workingDirectory.path}/package_workflow_invocations.txt',
      );
      final source = await _createWorkflowSdkSource(
        environment.homeDirectory,
        environment.workingDirectory,
        flutterStdout: const {
          'run -d emulator-5554 --debug --no-pub':
              'Flutter run key commands.\\nApplication running.',
        },
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
      expect(invocations, contains('android-emulator -avd Pixel_35'));
      expect(
        invocations,
        contains('$root::flutter run -d emulator-5554 --debug --no-pub'),
      );
      expect(invocations, isNot(contains('flutter run -d connected-device')));
      expect(stderr, isEmpty);
    },
  );
}
