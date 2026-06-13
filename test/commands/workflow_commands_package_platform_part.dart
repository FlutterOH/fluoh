part of 'workflow_commands_test.dart';

void _registerWorkflowCommandsPackagePlatformTests() {
  test('drive OHOS scenario grants permission through UI text', () async {
    final environment = await createTestEnvironment();
    final hdcLog = File('${environment.homeDirectory.path}/hdc.log');
    final devEco = await _writeWorkflowDevEcoFixture(
      environment.homeDirectory,
      hdcLog: hdcLog,
      hdcInstallExitCode: 0,
      hdcLaunchExitCode: 0,
      hdcHilogStdout: 'sample_permissions_ohos: requestPermissions\n',
      hdcAppDeniedLayout: _ohosPermissionExampleLayout(
        'PermissionStatus.denied',
      ),
      hdcPermissionDialogLayout: _ohosPermissionDialogLayout(),
      hdcAppGrantedLayout: _ohosPermissionExampleLayout(
        'PermissionStatus.granted',
      ),
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
    await Directory(
      '${environment.workingDirectory.path}/example/integration_test',
    ).create(recursive: true);
    await File(
      '${environment.workingDirectory.path}/example/integration_test/app_test.dart',
    ).writeAsString('void main() {}\n');
    await _writeWorkflowOhosProject(
      Directory('${environment.workingDirectory.path}/example'),
    );
    final scenario = File(
      '${environment.workingDirectory.path}/.fluoh/scenarios/camera/ohos-permission.md',
    );
    await scenario.parent.create(recursive: true);
    await scenario.writeAsString('''
kind: fluoh.automationScenario
schema: 1
name: ohos permission
platform: ohos
steps:
  - action: clearAppData
    bundleId: com.example.camera
    abilityName: PermissionAbility
  - action: resetPermission
    bundleId: com.example.camera
  - action: swipe
    x: 10
    y: 20
    endX: 30
    endY: 40
    durationMilliseconds: 250
  - action: inputText
    value: camera
  - action: press
    value: 2072
  - action: wait
    timeoutSeconds: 0
  - action: waitText
    labels: [Permission.camera]
  - action: tapText
    labels: [Permission.camera]
  - action: allowPermission
  - action: assertText
    labels: [PermissionStatus.granted]
  - action: captureScreenshot
    outputPath: .fluoh/evidence/screenshots/camera-ohos-granted.jpeg
  - action: assertLog
    contains: "sample_permissions_ohos: requestPermissions"
  - action: assertSession
    contains: com.example.camera
''');
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
          'drive',
          'ohos',
          '--package',
          'camera',
          '--scenario',
          scenario.path,
          '--log-duration',
          '0',
          '--json',
        ],
        environment: workflowEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
      reason: [...stdout, ...stderr].join('\n'),
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('command', 'drive'));
    expect(report, containsPair('ok', true));
    final target =
        (report['targets'] as List<Object?>).single as Map<String, Object?>;
    final steps = (target['steps'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final scenarioStep = steps.singleWhere(
      (step) => step['name'] == 'automation-scenario-ohos-ohos-permission',
    );
    expect(scenarioStep, containsPair('status', 'passed'));
    final integrationStep = steps.singleWhere(
      (step) => step['name'] == 'example-integration-ohos',
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
    final scenarioDetails = scenarioStep['details'] as Map<String, Object?>;
    final actions = (scenarioDetails['actions'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(actions.map((action) => action['action']), [
      'clearAppData',
      'resetPermission',
      'foregroundApp',
      'swipe',
      'inputText',
      'press',
      'wait',
      'waitText',
      'tapText',
      'allowPermission',
      'assertText',
      'captureScreenshot',
      'assertLog',
      'assertSession',
    ]);
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
      '${environment.workingDirectory.path}/.fluoh/evidence/screenshots/camera-ohos-granted.jpeg',
    );
    expect(screenshotDetails, containsPair('bytes', greaterThan(0)));
    expect(File(screenshotPath).existsSync(), isTrue);
    final workflowInvocations = File(
      '${environment.workingDirectory.path}/package_workflow_invocations.txt',
    ).readAsStringSync();
    expect(
      workflowInvocations,
      contains('flutter test integration_test -d emulator-5554'),
    );
    final invocations = hdcLog.readAsStringSync();
    expect(
      invocations,
      contains('-t emulator-5554 shell aa force-stop com.example.camera'),
    );
    expect(
      invocations,
      contains('-t emulator-5554 shell bm clean -d -n com.example.camera'),
    );
    expect(
      invocations,
      contains(
        '-t emulator-5554 shell aa start -d 0 -a PermissionAbility -b com.example.camera',
      ),
    );
    expect(
      invocations,
      contains('-t emulator-5554 shell uitest uiInput swipe 10 20 30 40 250'),
    );
    expect(
      invocations,
      contains('-t emulator-5554 shell uitest uiInput inputText camera'),
    );
    expect(
      invocations,
      contains('-t emulator-5554 shell uitest uiInput keyEvent 2072'),
    );
    expect(
      invocations,
      contains('-t emulator-5554 shell uitest uiInput click 636 685'),
    );
    expect(
      invocations,
      contains('-t emulator-5554 shell uitest uiInput click 914 1650'),
    );
    expect(invocations, contains('-t emulator-5554 shell uitest dumpLayout'));
    expect(
      invocations,
      contains(
        '-t emulator-5554 shell cat /data/local/tmp/layout_fixture.json',
      ),
    );
    expect(invocations, contains('-t emulator-5554 shell hilog -x -z 1000'));
    expect(
      invocations,
      contains(
        '-t emulator-5554 shell snapshot_display -f /data/local/tmp/fluoh-ohos-permission-step-11.jpeg',
      ),
    );
    expect(
      invocations,
      contains(
        '-t emulator-5554 file recv /data/local/tmp/fluoh-ohos-permission-step-11.jpeg ${environment.workingDirectory.path}/.fluoh/evidence/screenshots/camera-ohos-granted.jpeg',
      ),
    );
    expect(stderr, isEmpty);
  });

  test(
    'package OHOS run failure preserves auto emulator next command',
    () async {
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
        flutterStdout: const {'devices --machine': _ohosFlutterDevicesJson},
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
      final targets = report['targets'] as List<Object?>;
      final target = targets.single as Map<String, Object?>;
      final steps = target['steps'] as List<Object?>;
      final runStep = steps.cast<Map<String, Object?>>().singleWhere(
        (step) => step['name'] == 'example-run-ohos',
      );
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
      expect(stderr, isEmpty);
    },
  );

  test('can build example APK and emit json results', () async {
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
        ['build', 'android', '--debug', '--json'],
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
    expect(report, containsPair('ok', true));
    final targets = report['targets'] as List<Object?>;
    final target = targets.single as Map<String, Object?>;
    final steps = target['steps'] as List<Object?>;
    expect(
      steps,
      contains(
        allOf(
          containsPair('name', 'example-build-apk'),
          containsPair('command', 'flutter build apk --debug'),
          containsPair('status', 'passed'),
        ),
      ),
    );
    expect(stderr, isEmpty);
  });

  test('can build example iOS without codesigning', () async {
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
        ['build', 'ios', '--debug', '--json'],
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
      contains('$root/example::flutter build ios --debug --no-codesign'),
    );
    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    final targets = report['targets'] as List<Object?>;
    final target = targets.single as Map<String, Object?>;
    final steps = target['steps'] as List<Object?>;
    expect(
      steps,
      contains(
        allOf(
          containsPair('name', 'example-build-ios'),
          containsPair('command', 'flutter build ios --debug --no-codesign'),
          containsPair('status', 'passed'),
        ),
      ),
    );
    expect(stderr, isEmpty);
  });

  test('can build example macOS and emit json results', () async {
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
        ['build', 'macos', '--debug', '--json'],
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
      contains('$root/example::flutter build macos --debug'),
    );
    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    final targets = report['targets'] as List<Object?>;
    final target = targets.single as Map<String, Object?>;
    final steps = target['steps'] as List<Object?>;
    expect(
      steps,
      contains(
        allOf(
          containsPair('name', 'example-build-macos'),
          containsPair('command', 'flutter build macos --debug'),
          containsPair('status', 'passed'),
        ),
      ),
    );
    expect(stderr, isEmpty);
  });

  test(
    'can build Linux, Web, and Windows examples and emit json results',
    () async {
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

      for (final platform in ['linux', 'web', 'windows']) {
        expect(
          await runFluoh(
            ['build', platform, '--debug', '--json'],
            environment: environment,
            stdout: stdout.add,
            stderr: stderr.add,
          ),
          0,
        );

        final report = jsonDecode(stdout.removeLast()) as Map<String, Object?>;
        final targets = report['targets'] as List<Object?>;
        final target = targets.single as Map<String, Object?>;
        final steps = target['steps'] as List<Object?>;
        expect(
          steps,
          contains(
            allOf(
              containsPair('name', 'example-build-$platform'),
              containsPair('command', 'flutter build $platform --debug'),
              containsPair('status', 'passed'),
            ),
          ),
        );
      }

      final root = await environment.workingDirectory.resolveSymbolicLinks();
      final invocations = File(
        '${environment.workingDirectory.path}/package_workflow_invocations.txt',
      ).readAsStringSync();
      expect(
        invocations,
        contains('$root/example::flutter build linux --debug'),
      );
      expect(invocations, contains('$root/example::flutter build web --debug'));
      expect(
        invocations,
        contains('$root/example::flutter build windows --debug'),
      );
      expect(stderr, isEmpty);
    },
  );

  test('emits platform diagnostics for failed example builds', () async {
    final environment = await createTestEnvironment();
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
      flutterFailures: const {'build apk --debug': 3},
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
        ['build', 'android', '--debug', '--json'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      3,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('ok', false));
    expect(report, containsPair('exitCode', 3));
    final targets = report['targets'] as List<Object?>;
    final target = targets.single as Map<String, Object?>;
    final steps = target['steps'] as List<Object?>;
    final buildStep = steps.cast<Map<String, Object?>>().singleWhere(
      (step) => step['name'] == 'example-build-apk',
    );
    final diagnostics = buildStep['diagnostics'] as List<Object?>;
    final diagnostic = diagnostics.single as Map<String, Object?>;
    expect(diagnostic, containsPair('code', 'android.apk_build_failed'));
    expect(diagnostic, containsPair('message', 'Android APK build failed.'));
    final details = diagnostic['details'] as Map<String, Object?>;
    expect(details, containsPair('command', 'flutter build apk --debug'));
    expect(details, containsPair('stdoutTail', contains('flutter stdout')));
    expect(details, containsPair('stderrTail', contains('flutter stderr')));
    expect(stderr, isEmpty);
  });

  test('emits OHOS build retry for failed package HAP builds', () async {
    final environment = await createTestEnvironment();
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
      flutterFailures: const {'build hap --debug': 3},
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
      3,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    final targets = report['targets'] as List<Object?>;
    final target = targets.single as Map<String, Object?>;
    final steps = target['steps'] as List<Object?>;
    final buildStep = steps.cast<Map<String, Object?>>().singleWhere(
      (step) => step['name'] == 'example-build-hap',
    );
    final diagnostics = buildStep['diagnostics'] as List<Object?>;
    final diagnostic = diagnostics.single as Map<String, Object?>;
    expect(diagnostic, containsPair('code', 'ohos.hap_build_failed'));
    expect(
      diagnostic,
      containsPair('nextCommand', 'fluoh build ohos --package camera --json'),
    );
    expect(stderr, isEmpty);
  });

  test('emits iOS diagnostics for failed example builds', () async {
    final environment = await createTestEnvironment();
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
      flutterFailures: const {'build ios --debug --no-codesign': 4},
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
        ['build', 'ios', '--debug', '--json'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      4,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('ok', false));
    expect(report, containsPair('exitCode', 4));
    final targets = report['targets'] as List<Object?>;
    final target = targets.single as Map<String, Object?>;
    final steps = target['steps'] as List<Object?>;
    final buildStep = steps.cast<Map<String, Object?>>().singleWhere(
      (step) => step['name'] == 'example-build-ios',
    );
    final diagnostics = buildStep['diagnostics'] as List<Object?>;
    final diagnostic = diagnostics.single as Map<String, Object?>;
    expect(diagnostic, containsPair('code', 'ios.build_failed'));
    expect(diagnostic, containsPair('message', 'iOS build failed.'));
    final details = diagnostic['details'] as Map<String, Object?>;
    expect(
      details,
      containsPair('command', 'flutter build ios --debug --no-codesign'),
    );
    expect(stderr, isEmpty);
  });

  test('emits platform diagnostics for failed builds', () async {
    final environment = await createTestEnvironment();
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
      flutterFailures: const {'build hap --debug': 7},
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
      7,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('ok', false));
    expect(report, containsPair('exitCode', 7));
    final targets = report['targets'] as List<Object?>;
    final target = targets.single as Map<String, Object?>;
    expect(target['target'], containsPair('kind', 'project'));
    expect(target, containsPair('phase', 'build-ohos'));
    final steps = target['steps'] as List<Object?>;
    final buildStep = steps.cast<Map<String, Object?>>().singleWhere(
      (step) => step['name'] == 'project-build-ohos',
    );
    final diagnostics = buildStep['diagnostics'] as List<Object?>;
    final diagnostic = diagnostics.single as Map<String, Object?>;
    expect(diagnostic, containsPair('code', 'ohos.hap_build_failed'));
    expect(diagnostic, containsPair('message', 'OHOS HAP build failed.'));
    expect(diagnostic, containsPair('nextCommand', 'fluoh build ohos --json'));
    final details = diagnostic['details'] as Map<String, Object?>;
    expect(details, containsPair('command', 'flutter build hap --debug'));
    expect(details, containsPair('stdoutTail', contains('flutter stdout')));
    expect(details, containsPair('stderrTail', contains('flutter stderr')));
    expect(buildStep, containsPair('nextCommand', 'fluoh build ohos --json'));
    expect(target, containsPair('nextCommand', 'fluoh build ohos --json'));
    expect(stderr, isEmpty);
  });
}
