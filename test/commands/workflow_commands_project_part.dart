part of 'workflow_commands_test.dart';

void _registerWorkflowCommandsProjectTests() {
  test('project OHOS auto-sign requires an OHOS platform directory', () async {
    final environment = await createTestEnvironment();
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
    );
    await writeFlutterProjectFixture(environment.workingDirectory);
    await _writeProjectSdkConfig(environment.workingDirectory);
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
        ['build', 'ohos', '--auto-sign', '--json'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      1,
    );

    final invocations = File(
      '${environment.workingDirectory.path}/package_workflow_invocations.txt',
    );
    expect(await invocations.exists(), isFalse);
    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('ok', false));
    final targets = report['targets'] as List<Object?>;
    final target = targets.single as Map<String, Object?>;
    expect(target, containsPair('phase', 'build-ohos'));
    final steps = target['steps'] as List<Object?>;
    final autoSignStep = steps.cast<Map<String, Object?>>().singleWhere(
      (step) => step['name'] == 'ohos-auto-sign',
    );
    expect(autoSignStep, containsPair('status', 'failed'));
    final diagnostics = autoSignStep['diagnostics'] as List<Object?>;
    final diagnostic = diagnostics.single as Map<String, Object?>;
    expect(diagnostic, containsPair('code', 'ohos.ohos_project_missing'));
    expect(
      diagnostic,
      containsPair(
        'nextCommand',
        'fluoh doctor --platform ohos --project --json',
      ),
    );
    expect(stderr, isEmpty);
  });

  test('project OHOS build reports installable HAP artifacts', () async {
    final environment = await createTestEnvironment();
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
      flutterSideEffects: const {
        'build hap --debug':
            'mkdir -p build/ohos/hap\nprintf "hap" > build/ohos/hap/entry-default-signed.hap',
      },
    );
    await writeFlutterProjectFixture(environment.workingDirectory);
    await _writeProjectSdkConfig(environment.workingDirectory);
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
        ['build', 'ohos', '--json'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('ok', true));
    final targets = report['targets'] as List<Object?>;
    final target = targets.single as Map<String, Object?>;
    final steps = target['steps'] as List<Object?>;
    final buildStep = steps.cast<Map<String, Object?>>().singleWhere(
      (step) => step['name'] == 'project-build-ohos',
    );
    final details = buildStep['details'] as Map<String, Object?>;
    expect(
      details,
      containsPair(
        'installableHaps',
        contains(endsWith('build/ohos/hap/entry-default-signed.hap')),
      ),
    );
    expect(stderr, isEmpty);
  });

  test('project OHOS run prepares signing before Flutter run', () async {
    final environment = await createTestEnvironment();
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
    );
    await writeFlutterProjectFixture(environment.workingDirectory);
    await _writeProjectSdkConfig(environment.workingDirectory);
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
        ['run', 'ohos', '--json'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      1,
    );

    final invocations = File(
      '${environment.workingDirectory.path}/package_workflow_invocations.txt',
    );
    expect(await invocations.exists(), isFalse);
    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('ok', false));
    final targets = report['targets'] as List<Object?>;
    final target = targets.single as Map<String, Object?>;
    expect(target, containsPair('phase', 'run-ohos'));
    final steps = target['steps'] as List<Object?>;
    expect(
      steps,
      contains(
        allOf(
          containsPair('name', 'ohos-run-preparation'),
          containsPair('status', 'failed'),
        ),
      ),
    );
    final autoSignStep = steps.cast<Map<String, Object?>>().singleWhere(
      (step) => step['name'] == 'ohos-run-preparation',
    );
    final diagnostics = autoSignStep['diagnostics'] as List<Object?>;
    final diagnostic = diagnostics.single as Map<String, Object?>;
    expect(diagnostic, containsPair('code', 'ohos.ohos_project_missing'));
    expect(
      diagnostic,
      containsPair(
        'nextCommand',
        'fluoh doctor --platform ohos --project --json',
      ),
    );
    expect(stderr, isEmpty);
  });

  test(
    'project OHOS run ignores stale HAP artifacts and uses Flutter run',
    () async {
      final environment = await createTestEnvironment();
      final source = await _createWorkflowSdkSource(
        environment.homeDirectory,
        environment.workingDirectory,
        flutterStdout: _ohosFlutterRunStdoutByCommand,
      );
      final hdcLog = File('${environment.homeDirectory.path}/hdc.log');
      final devEco = await _writeWorkflowDevEcoFixture(
        environment.homeDirectory,
        hdcLog: hdcLog,
      );
      final workflowEnvironment = FluohEnvironment(
        homeDirectory: environment.homeDirectory,
        workingDirectory: environment.workingDirectory,
        processEnvironment: {
          ...environment.processEnvironment,
          'FLUOH_DEVECO_STUDIO': devEco.path,
        },
      );
      await writeFlutterProjectFixture(environment.workingDirectory);
      await _writeWorkflowOhosProject(environment.workingDirectory);
      await _writeProjectSdkConfig(environment.workingDirectory);
      final staleHap = File(
        '${environment.workingDirectory.path}/build/ohos/hap/stale-signed.hap',
      );
      await staleHap.parent.create(recursive: true);
      await staleHap.writeAsString('stale');
      await staleHap.setLastModified(
        DateTime.now().subtract(const Duration(days: 1)),
      );
      final stdout = <String>[];
      final stderr = <String>[];

      await runFluoh(
        ['source', 'add', 'fixture', source.path],
        environment: workflowEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      stdout.clear();
      stderr.clear();

      expect(
        await runFluoh(
          ['run', 'ohos', '--json'],
          environment: workflowEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      expect(await hdcLog.exists(), isFalse);
      final root = await environment.workingDirectory.resolveSymbolicLinks();
      final invocations = File(
        '${environment.workingDirectory.path}/package_workflow_invocations.txt',
      ).readAsStringSync();
      expect(invocations, contains('$root::flutter devices --machine'));
      expect(
        invocations,
        contains('$root::flutter run -d emulator-5554 --debug --no-pub'),
      );
      expect(invocations, isNot(contains('flutter build hap --debug')));
      final report = jsonDecode(stdout.single) as Map<String, Object?>;
      expect(report, containsPair('ok', true));
      final targets = report['targets'] as List<Object?>;
      final target = targets.single as Map<String, Object?>;
      expect(target, containsPair('phase', 'run-ohos'));
      final steps = target['steps'] as List<Object?>;
      final runStep = steps.cast<Map<String, Object?>>().singleWhere(
        (step) => step['name'] == 'project-run-ohos',
        orElse: () =>
            fail('Missing project-run-ohos step: ${jsonEncode(steps)}'),
      );
      expect(runStep, containsPair('status', 'passed'));
      final details = runStep['details'] as Map<String, Object?>;
      expect(details, containsPair('targetId', 'emulator-5554'));
      expect(stderr, isEmpty);
    },
  );

  test('project OHOS run executes Flutter integration tests', () async {
    final environment = await createTestEnvironment();
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
      flutterStdout: _ohosFlutterRunStdoutByCommand,
    );
    final hdcLog = File('${environment.homeDirectory.path}/hdc.log');
    final devEco = await _writeWorkflowDevEcoFixture(
      environment.homeDirectory,
      hdcLog: hdcLog,
      hdcInstallExitCode: 0,
      hdcLaunchExitCode: 0,
    );
    final workflowEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: environment.workingDirectory,
      processEnvironment: {
        ...environment.processEnvironment,
        'FLUOH_DEVECO_STUDIO': devEco.path,
      },
    );
    await writeFlutterProjectFixture(environment.workingDirectory);
    await _writeWorkflowOhosProject(environment.workingDirectory);
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
      ['source', 'add', 'fixture', source.path],
      environment: workflowEnvironment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    stdout.clear();
    stderr.clear();

    expect(
      await runFluoh(
        [
          'run',
          'ohos',
          '--log-duration',
          '0',
          '--session-file',
          '.fluoh/project-ohos-session.json',
          '--json',
        ],
        environment: workflowEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final root = await environment.workingDirectory.resolveSymbolicLinks();
    final invocations = File(
      '${environment.workingDirectory.path}/package_workflow_invocations.txt',
    ).readAsStringSync();
    expect(invocations, contains('$root::flutter devices --machine'));
    expect(
      invocations,
      contains('$root::flutter run -d emulator-5554 --debug --no-pub'),
    );
    expect(
      invocations,
      contains('$root::flutter test integration_test -d emulator-5554'),
    );
    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('ok', true));
    final targets = report['targets'] as List<Object?>;
    final target = targets.single as Map<String, Object?>;
    final steps = target['steps'] as List<Object?>;
    final runStep = steps.cast<Map<String, Object?>>().singleWhere(
      (step) => step['name'] == 'project-run-ohos',
    );
    final runDetails = runStep['details'] as Map<String, Object?>;
    final sessionFile =
        '${environment.workingDirectory.path}/.fluoh/project-ohos-session.json';
    expect(runDetails, containsPair('sessionFile', sessionFile));
    final session =
        jsonDecode(File(sessionFile).readAsStringSync())
            as Map<String, Object?>;
    expect(session, containsPair('kind', 'flutterRunSession'));
    expect(session, containsPair('status', 'passed'));
    expect(session, containsPair('platform', 'ohos'));
    expect(session, containsPair('launchDetected', true));
    final integrationStep = steps.cast<Map<String, Object?>>().singleWhere(
      (step) => step['name'] == 'project-integration-ohos',
    );
    expect(
      integrationStep,
      containsPair('command', 'flutter test integration_test -d emulator-5554'),
    );
    expect(integrationStep, containsPair('status', 'passed'));
    final details = integrationStep['details'] as Map<String, Object?>;
    final evidence = details['interactionEvidence'] as Map<String, Object?>;
    expect(evidence, containsPair('method', 'integration_test'));
    expect(evidence, containsPair('status', 'passed'));
    expect(stderr, isEmpty);
  });

  test('emits platform diagnostics for failed project runs', () async {
    final environment = await createTestEnvironment();
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
      flutterFailures: const {'run -d ios-sim --debug --no-pub': 2},
      flutterStdout: const {
        'devices --machine':
            '[{"id":"ios-sim","name":"iPhone 15","targetPlatform":"ios","isSupported":true}]',
      },
    );
    await writeFlutterProjectFixture(environment.workingDirectory);
    await _writeProjectSdkConfig(environment.workingDirectory);
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
        ['run', 'ios', '--device-id', 'ios-sim', '--json'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      1,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('ok', false));
    final targets = report['targets'] as List<Object?>;
    final target = targets.single as Map<String, Object?>;
    expect(target, containsPair('phase', 'run-ios'));
    final steps = target['steps'] as List<Object?>;
    final runStep = steps.cast<Map<String, Object?>>().singleWhere(
      (step) => step['name'] == 'project-run-ios',
    );
    final diagnostics = runStep['diagnostics'] as List<Object?>;
    final diagnostic = diagnostics.single as Map<String, Object?>;
    expect(diagnostic, containsPair('code', 'ios.run_failed'));
    expect(diagnostic, containsPair('message', 'Flutter example run failed'));
    final details = diagnostic['details'] as Map<String, Object?>;
    expect(
      details,
      containsPair('command', 'flutter run -d ios-sim --debug --no-pub'),
    );
    expect(
      diagnostic,
      containsPair('nextCommand', 'fluoh run ios --device-id ios-sim --json'),
    );
    expect(stderr, isEmpty);
  });

  test('project iOS run accepts native wireless device id', () async {
    final environment = await createTestEnvironment();
    final xcrunLog = File('${environment.workingDirectory.path}/xcrun.log');
    final xcrun = await _writeXcrunFixture(
      environment.homeDirectory,
      xcrunLog.path,
      simctlDevicesJson: '{"devices":{}}',
      devicectlDevicesJson: '''
{
  "result": {
    "devices": [
      {
        "identifier": "WIRELESS-DEVICE-ID",
        "deviceProperties": {
          "name": "nice",
          "osVersionNumber": "26.5.1"
        },
        "hardwareProperties": {
          "platform": "iOS",
          "marketingName": "iPhone 17"
        },
        "connectionProperties": {
          "transportType": "localNetwork",
          "pairingState": "paired",
          "tunnelState": "connected"
        }
      }
    ]
  }
}
''',
    );
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
      flutterStdout: const {
        'devices --machine':
            '[{"id":"00008150-00096DE41146401C","name":"nice","targetPlatform":"ios","isSupported":true}]',
        'run -d 00008150-00096DE41146401C --debug --no-pub':
            'Flutter run key commands.\\nApplication running.',
      },
    );
    await writeFlutterProjectFixture(environment.workingDirectory);
    await _writeProjectSdkConfig(environment.workingDirectory);
    final commandEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: environment.workingDirectory,
      processEnvironment: {
        ...environment.processEnvironment,
        'FLUOH_XCRUN': xcrun.path,
      },
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'add', 'fixture', source.path],
      environment: commandEnvironment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    stdout.clear();
    stderr.clear();

    expect(
      await runFluoh(
        ['run', 'ios', '--device-id', 'WIRELESS-DEVICE-ID', '--json'],
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
      contains(
        '$root::flutter run -d 00008150-00096DE41146401C --debug --no-pub',
      ),
    );
    expect(
      xcrunLog.readAsStringSync(),
      contains('devicectl list devices --json'),
    );
    expect(stderr, isEmpty);
  });

  test('project run fails when Flutter exits before launch is detected', () async {
    final environment = await createTestEnvironment();
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
      flutterStdout: const {
        'devices --machine':
            '[{"id":"emulator-5554","name":"OHOS Emulator","targetPlatform":"ohos-arm64","isSupported":true,"emulator":true}]',
        'run -d emulator-5554 --debug --no-pub': 'Starting application.',
      },
    );
    final hdcLog = File('${environment.homeDirectory.path}/hdc.log');
    final devEco = await _writeWorkflowDevEcoFixture(
      environment.homeDirectory,
      hdcLog: hdcLog,
      hdcInstallExitCode: 0,
      hdcLaunchExitCode: 0,
    );
    final workflowEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: environment.workingDirectory,
      processEnvironment: {
        ...environment.processEnvironment,
        'FLUOH_DEVECO_STUDIO': devEco.path,
      },
    );
    await writeFlutterProjectFixture(environment.workingDirectory);
    await _writeWorkflowOhosProject(environment.workingDirectory);
    await _writeProjectSdkConfig(environment.workingDirectory);
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'add', 'fixture', source.path],
      environment: workflowEnvironment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    stdout.clear();
    stderr.clear();

    expect(
      await runFluoh(
        [
          'run',
          'ohos',
          '--session-file',
          '.fluoh/project-ohos-session.json',
          '--json',
        ],
        environment: workflowEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      1,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('ok', false));
    final targets = report['targets'] as List<Object?>;
    final target = targets.single as Map<String, Object?>;
    final steps = target['steps'] as List<Object?>;
    final runStep = steps.cast<Map<String, Object?>>().singleWhere(
      (step) => step['name'] == 'project-run-ohos',
    );
    expect(runStep, containsPair('status', 'failed'));
    final diagnostics = runStep['diagnostics'] as List<Object?>;
    final diagnostic = diagnostics.single as Map<String, Object?>;
    expect(diagnostic, containsPair('code', 'ohos.launch_missing'));
    expect(diagnostic, containsPair('nextCommand', 'fluoh run ohos --json'));
    final session =
        jsonDecode(
              File(
                '${environment.workingDirectory.path}/.fluoh/project-ohos-session.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    expect(session, containsPair('status', 'failed'));
    expect(session, containsPair('launchDetected', false));
    expect(stderr, isEmpty);
  });

  test('project run executes Flutter integration tests', () async {
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
      ['source', 'add', 'fixture', source.path],
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
      0,
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

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('ok', true));
    final targets = report['targets'] as List<Object?>;
    final target = targets.single as Map<String, Object?>;
    expect(target, containsPair('phase', 'run-android'));
    final steps = target['steps'] as List<Object?>;
    expect(
      steps,
      contains(
        allOf(
          containsPair('name', 'project-integration-android'),
          containsPair(
            'command',
            'flutter test integration_test -d emulator-5554',
          ),
          containsPair('status', 'passed'),
        ),
      ),
    );
    final integrationStep = steps.cast<Map<String, Object?>>().singleWhere(
      (step) => step['name'] == 'project-integration-android',
    );
    final details = integrationStep['details'] as Map<String, Object?>;
    final evidence = details['interactionEvidence'] as Map<String, Object?>;
    expect(evidence, containsPair('method', 'integration_test'));
    expect(evidence, containsPair('status', 'passed'));
    expect(stderr, isEmpty);
  });
}
