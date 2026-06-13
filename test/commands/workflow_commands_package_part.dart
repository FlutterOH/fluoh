part of 'workflow_commands_test.dart';

void _registerWorkflowCommandsPackageTests() {
  test('build runs a package example build', () async {
    final environment = await createTestEnvironment();
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
    );
    await _writePackageManifest(environment.workingDirectory);
    await _writeFlutterPackage(environment.workingDirectory);
    await _writeFlutterExample(
      Directory('${environment.workingDirectory.path}/example'),
    );
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
        ['build', 'android', '--json'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final root = await environment.workingDirectory.resolveSymbolicLinks();
    expect(
      File(
        '${environment.workingDirectory.path}/package_workflow_invocations.txt',
      ).readAsStringSync(),
      contains('$root/example::flutter build apk --debug'),
    );
    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('command', 'build'));
    expect(report, containsPair('ok', true));
    expect(stderr, isEmpty);
  });

  test('can build example HAP and emit json results', () async {
    final environment = await createTestEnvironment();
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
    );
    await _writePackageManifest(environment.workingDirectory);
    await _writeFlutterPackage(environment.workingDirectory);
    await _writeFlutterExample(
      Directory('${environment.workingDirectory.path}/example'),
    );
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
        ['build', 'ohos', '--debug', '--json'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final root = await environment.workingDirectory.resolveSymbolicLinks();
    expect(
      File(
        '${environment.workingDirectory.path}/package_workflow_invocations.txt',
      ).readAsStringSync(),
      contains('$root/example::flutter build hap --debug'),
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
          containsPair('name', 'example-build-hap'),
          containsPair('command', 'flutter build hap --debug'),
          containsPair('status', 'passed'),
        ),
      ),
    );
    expect(stderr, isEmpty);
  });

  test(
    'package OHOS run suggests auto emulator when no target is connected',
    () async {
      final environment = await createTestEnvironment();
      final hdcLog = File('${environment.homeDirectory.path}/hdc.log');
      final devEco = await _writeWorkflowDevEcoFixture(
        environment.homeDirectory,
        hdcLog: hdcLog,
        targets: '[Empty]\n',
      );
      final source = await _createWorkflowSdkSource(
        environment.homeDirectory,
        environment.workingDirectory,
        flutterStdout: const {'devices --machine': '[]'},
      );
      final workflowEnvironment = FluohEnvironment(
        homeDirectory: environment.homeDirectory,
        workingDirectory: environment.workingDirectory,
        processEnvironment: {
          ...environment.processEnvironment,
          'FLUOH_DEVECO_STUDIO': devEco.path,
          'FLUOH_OHOS_EMULATOR_DEPLOYED':
              '${environment.homeDirectory.path}/no_emulators',
        },
      );
      await _writePackageManifest(environment.workingDirectory);
      await _writeFlutterPackage(environment.workingDirectory);
      await _writeFlutterExample(
        Directory('${environment.workingDirectory.path}/example'),
      );
      await _writeWorkflowOhosProject(
        Directory('${environment.workingDirectory.path}/example'),
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
        1,
      );

      final report = jsonDecode(stdout.single) as Map<String, Object?>;
      expect(report, containsPair('ok', false));
      final targets = report['targets'] as List<Object?>;
      final target = targets.single as Map<String, Object?>;
      final steps = target['steps'] as List<Object?>;
      final runStep = steps.cast<Map<String, Object?>>().singleWhere(
        (step) => step['name'] == 'example-run-ohos',
      );
      final diagnostics = runStep['diagnostics'] as List<Object?>;
      final diagnostic = diagnostics.single as Map<String, Object?>;
      expect(diagnostic, containsPair('code', 'ohos.device_missing'));
      expect(
        diagnostic,
        containsPair(
          'nextCommand',
          'fluoh run ohos --package camera --auto-emulator --json',
        ),
      );
      expect(stderr, isEmpty);
    },
  );

  test('package OHOS run reports Flutter device listing failures', () async {
    final environment = await createTestEnvironment();
    final hdcLog = File('${environment.homeDirectory.path}/hdc.log');
    final devEco = await _writeWorkflowDevEcoFixture(
      environment.homeDirectory,
      hdcLog: hdcLog,
      targets: '',
      hdcListTargetsStderr: 'Connect server failed\n',
    );
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
      flutterFailures: const {'devices --machine': 1},
      flutterStdout: const {'devices --machine': '[]'},
      flutterStderr: const {'devices --machine': 'Connect server failed'},
    );
    final workflowEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: environment.workingDirectory,
      processEnvironment: {
        ...environment.processEnvironment,
        'FLUOH_DEVECO_STUDIO': devEco.path,
      },
    );
    await _writePackageManifest(environment.workingDirectory);
    await _writeFlutterPackage(environment.workingDirectory);
    await _writeFlutterExample(
      Directory('${environment.workingDirectory.path}/example'),
    );
    await _writeWorkflowOhosProject(
      Directory('${environment.workingDirectory.path}/example'),
    );
    final buildProfile = File(
      '${environment.workingDirectory.path}/example/ohos/build-profile.json5',
    );
    final originalBuildProfile = await buildProfile.readAsString();
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
      1,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('ok', false));
    final targets = report['targets'] as List<Object?>;
    final target = targets.single as Map<String, Object?>;
    final steps = target['steps'] as List<Object?>;
    final runStep = steps.cast<Map<String, Object?>>().singleWhere(
      (step) => step['name'] == 'example-run-ohos',
    );
    expect(runStep, containsPair('status', 'failed'));
    expect(runStep, containsPair('exitCode', 1));
    final diagnostics = runStep['diagnostics'] as List<Object?>;
    final diagnostic = diagnostics.single as Map<String, Object?>;
    expect(diagnostic, containsPair('code', 'ohos.devices_failed'));
    expect(
      diagnostic,
      containsPair('nextCommand', 'fluoh doctor --platform ohos --json'),
    );
    final details = diagnostic['details'] as Map<String, Object?>;
    expect(details, containsPair('command', 'flutter devices --machine'));
    expect(details, containsPair('exitCode', 1));
    expect(
      details,
      containsPair('stderrTail', contains('Connect server failed')),
    );
    expect(await buildProfile.readAsString(), originalBuildProfile);
    expect(stderr, isEmpty);
  });

  test('package OHOS run treats Flutter run failures as failed', () async {
    final environment = await createTestEnvironment();
    final hdcLog = File('${environment.homeDirectory.path}/hdc.log');
    final devEco = await _writeWorkflowDevEcoFixture(
      environment.homeDirectory,
      hdcLog: hdcLog,
    );
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
      flutterFailures: const {'run -d emulator-5554 --debug --no-pub': 7},
      flutterStdout: const {
        'devices --machine': _ohosFlutterDevicesJson,
        'run -d emulator-5554 --debug --no-pub': 'Starting application.',
      },
      flutterStderr: const {
        'run -d emulator-5554 --debug --no-pub': 'Connect server failed',
      },
    );
    final workflowEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: environment.workingDirectory,
      processEnvironment: {
        ...environment.processEnvironment,
        'FLUOH_DEVECO_STUDIO': devEco.path,
      },
    );
    await _writePackageManifest(environment.workingDirectory);
    await _writeFlutterPackage(environment.workingDirectory);
    await _writeFlutterExample(
      Directory('${environment.workingDirectory.path}/example'),
    );
    await _writeWorkflowOhosProject(
      Directory('${environment.workingDirectory.path}/example'),
    );
    final buildProfile = File(
      '${environment.workingDirectory.path}/example/ohos/build-profile.json5',
    );
    final originalBuildProfile = await buildProfile.readAsString();
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
      1,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('ok', false));
    final targets = report['targets'] as List<Object?>;
    final target = targets.single as Map<String, Object?>;
    final steps = target['steps'] as List<Object?>;
    final runStep = steps.cast<Map<String, Object?>>().singleWhere(
      (step) => step['name'] == 'example-run-ohos',
    );
    expect(runStep, containsPair('status', 'failed'));
    expect(runStep, containsPair('exitCode', 1));
    final diagnostics = runStep['diagnostics'] as List<Object?>;
    final diagnostic = diagnostics.single as Map<String, Object?>;
    expect(diagnostic, containsPair('code', 'ohos.run_failed'));
    expect(
      diagnostic,
      containsPair(
        'nextCommand',
        'fluoh run ohos --package camera --auto-emulator --json',
      ),
    );
    final details = diagnostic['details'] as Map<String, Object?>;
    expect(
      details,
      containsPair('command', 'flutter run -d emulator-5554 --debug --no-pub'),
    );
    expect(details, containsPair('targetId', 'emulator-5554'));
    expect(details, containsPair('exitCode', 7));
    expect(
      details,
      containsPair('stderrTail', contains('Connect server failed')),
    );
    expect(await buildProfile.readAsString(), originalBuildProfile);
    expect(stderr, isEmpty);
  });

  test('package OHOS run exposes structured launch evidence', () async {
    final environment = await createTestEnvironment();
    final hdcLog = File('${environment.homeDirectory.path}/hdc.log');
    final devEco = await _writeWorkflowDevEcoFixture(
      environment.homeDirectory,
      hdcLog: hdcLog,
      hdcInstallExitCode: 0,
      hdcLaunchExitCode: 0,
    );
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
      flutterStdout: _ohosFlutterRunStdoutByCommand,
    );
    final workflowEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: environment.workingDirectory,
      processEnvironment: {
        ...environment.processEnvironment,
        'FLUOH_DEVECO_STUDIO': devEco.path,
      },
    );
    await _writePackageManifest(environment.workingDirectory);
    await _writeFlutterPackage(environment.workingDirectory);
    await _writeFlutterExample(
      Directory('${environment.workingDirectory.path}/example'),
    );
    await _writeWorkflowOhosProject(
      Directory('${environment.workingDirectory.path}/example'),
    );
    final buildProfile = File(
      '${environment.workingDirectory.path}/example/ohos/build-profile.json5',
    );
    final originalBuildProfile = await buildProfile.readAsString();
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
          '.fluoh/ohos-session.json',
          '--json',
        ],
        environment: workflowEnvironment,
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
    final runStep = steps.cast<Map<String, Object?>>().singleWhere(
      (step) => step['name'] == 'example-run-ohos',
    );
    expect(runStep, containsPair('status', 'passed'));
    expect(runStep, containsPair('exitCode', 0));
    final details = runStep['details'] as Map<String, Object?>;
    expect(details, containsPair('targetId', 'emulator-5554'));
    expect(
      details,
      containsPair('vmServiceUri', 'http://127.0.0.1:23456/ohos=/'),
    );
    expect(details, isNot(contains('findings')));
    final sessionFile =
        '${environment.workingDirectory.path}/.fluoh/ohos-session.json';
    expect(details, containsPair('sessionFile', sessionFile));
    final preparation = details['runPreparation'] as Map<String, Object?>;
    expect(preparation, containsPair('platform', 'ohos'));
    expect(preparation, containsPair('signingMode', 'build-profile'));
    final session =
        jsonDecode(File(sessionFile).readAsStringSync())
            as Map<String, Object?>;
    expect(session, containsPair('kind', 'flutterRunSession'));
    expect(session, containsPair('status', 'passed'));
    expect(session, containsPair('platform', 'ohos'));
    expect(session, containsPair('launchDetected', true));
    expect(session, containsPair('targetId', 'emulator-5554'));
    expect(
      session,
      containsPair('vmServiceUri', 'http://127.0.0.1:23456/ohos=/'),
    );
    expect(await buildProfile.readAsString(), originalBuildProfile);
    expect(stderr, isEmpty);
  });

  test('package OHOS run executes example integration tests', () async {
    final environment = await createTestEnvironment();
    final hdcLog = File('${environment.homeDirectory.path}/hdc.log');
    final devEco = await _writeWorkflowDevEcoFixture(
      environment.homeDirectory,
      hdcLog: hdcLog,
      hdcInstallExitCode: 0,
      hdcLaunchExitCode: 0,
    );
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
      flutterStdout: _ohosFlutterRunStdoutByCommand,
    );
    final workflowEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: environment.workingDirectory,
      processEnvironment: {
        ...environment.processEnvironment,
        'FLUOH_DEVECO_STUDIO': devEco.path,
      },
    );
    await _writePackageManifest(environment.workingDirectory);
    await _writeFlutterPackage(environment.workingDirectory);
    await _writeFlutterExample(
      Directory('${environment.workingDirectory.path}/example'),
    );
    await _writeWorkflowOhosProject(
      Directory('${environment.workingDirectory.path}/example'),
    );
    await Directory(
      '${environment.workingDirectory.path}/example/integration_test',
    ).create(recursive: true);
    await File(
      '${environment.workingDirectory.path}/example/integration_test/app_test.dart',
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
    expect(invocations, contains('$root/example::flutter devices --machine'));
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
    final integrationStep = steps.cast<Map<String, Object?>>().singleWhere(
      (step) => step['name'] == 'example-integration-ohos',
    );
    expect(
      integrationStep,
      containsPair('command', 'flutter test integration_test -d emulator-5554'),
    );
    expect(integrationStep, containsPair('status', 'passed'));
    final details = integrationStep['details'] as Map<String, Object?>;
    expect(details, containsPair('targetId', 'emulator-5554'));
    final evidence = details['interactionEvidence'] as Map<String, Object?>;
    expect(evidence, containsPair('method', 'integration_test'));
    expect(evidence, containsPair('status', 'passed'));
    expect(stderr, isEmpty);
  });

  test('package OHOS run reports integration test failures', () async {
    final environment = await createTestEnvironment();
    final hdcLog = File('${environment.homeDirectory.path}/hdc.log');
    final devEco = await _writeWorkflowDevEcoFixture(
      environment.homeDirectory,
      hdcLog: hdcLog,
      hdcInstallExitCode: 0,
      hdcLaunchExitCode: 0,
    );
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
      flutterFailures: const {'test integration_test -d emulator-5554': 9},
      flutterStdout: _ohosFlutterRunStdoutByCommand,
    );
    final workflowEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: environment.workingDirectory,
      processEnvironment: {
        ...environment.processEnvironment,
        'FLUOH_DEVECO_STUDIO': devEco.path,
      },
    );
    await _writePackageManifest(environment.workingDirectory);
    await _writeFlutterPackage(environment.workingDirectory);
    await _writeFlutterExample(
      Directory('${environment.workingDirectory.path}/example'),
    );
    await _writeWorkflowOhosProject(
      Directory('${environment.workingDirectory.path}/example'),
    );
    await Directory(
      '${environment.workingDirectory.path}/example/integration_test',
    ).create(recursive: true);
    await File(
      '${environment.workingDirectory.path}/example/integration_test/app_test.dart',
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
        ['run', 'ohos', '--auto-emulator', '--log-duration', '0', '--json'],
        environment: workflowEnvironment,
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
        'fluoh run ohos --package camera --auto-emulator --json',
      ),
    );
    final steps = target['steps'] as List<Object?>;
    final integrationStep = steps.cast<Map<String, Object?>>().singleWhere(
      (step) => step['name'] == 'example-integration-ohos',
    );
    expect(integrationStep, containsPair('status', 'failed'));
    expect(
      integrationStep,
      containsPair(
        'nextCommand',
        'fluoh run ohos --package camera --auto-emulator --json',
      ),
    );
    final diagnostics = integrationStep['diagnostics'] as List<Object?>;
    final diagnostic = diagnostics.single as Map<String, Object?>;
    expect(diagnostic, containsPair('code', 'ohos.integration_test_failed'));
    expect(
      diagnostic,
      containsPair(
        'nextCommand',
        'fluoh run ohos --package camera --auto-emulator --json',
      ),
    );
    expect(stderr, isEmpty);
  });
}
