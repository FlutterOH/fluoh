part of 'workflow_commands_test.dart';

const _allWorkflowDevicesJson =
    '[{"id":"emulator-5554","name":"OHOS Emulator","targetPlatform":"ohos-arm64","isSupported":true,"emulator":true},'
    '{"id":"android-emulator","name":"Android Emulator","targetPlatform":"android-arm64","isSupported":true,"emulator":true},'
    '{"id":"ios-sim","name":"iPhone Simulator","targetPlatform":"ios","isSupported":true,"emulator":true},'
    '{"id":"macos","name":"macOS","targetPlatform":"darwin-arm64","isSupported":true},'
    '{"id":"linux","name":"Linux","targetPlatform":"linux-x64","isSupported":true},'
    '{"id":"chrome","name":"Chrome","targetPlatform":"web-javascript","isSupported":true},'
    '{"id":"windows","name":"Windows","targetPlatform":"windows-x64","isSupported":true}]';

const _allWorkflowRunStdoutByCommand = {
  'devices --machine': _allWorkflowDevicesJson,
  'run -d emulator-5554 --debug --no-pub': _ohosFlutterRunStdout,
  'run -d android-emulator --debug --no-pub':
      'Flutter run key commands.\\nApplication running.',
  'run -d ios-sim --debug --no-pub':
      'Flutter run key commands.\\nApplication running.',
  'run -d macos --debug --no-pub':
      'Flutter run key commands.\\nApplication running.',
  'run -d linux --debug --no-pub':
      'Flutter run key commands.\\nApplication running.',
  'run -d chrome --debug --no-pub':
      'Flutter run key commands.\\nApplication running.',
  'run -d windows --debug --no-pub':
      'Flutter run key commands.\\nApplication running.',
};

void _registerWorkflowCommandsPresetsTests() {
  test(
    'package run integration test failure preserves device next command',
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
            'run',
            'android',
            '--package',
            'camera',
            '--device-id',
            'emulator-5554',
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
      final targets = report['targets'] as List<Object?>;
      final target = targets.single as Map<String, Object?>;
      expect(
        target,
        containsPair(
          'nextCommand',
          'fluoh run android --package camera --device-id emulator-5554 --json',
        ),
      );
      final steps = target['steps'] as List<Object?>;
      final integrationStep = steps.cast<Map<String, Object?>>().singleWhere(
        (step) => step['name'] == 'example-integration-android',
      );
      expect(integrationStep, containsPair('status', 'failed'));
      expect(
        integrationStep,
        containsPair(
          'nextCommand',
          'fluoh run android --package camera --device-id emulator-5554 --json',
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
          'fluoh run android --package camera --device-id emulator-5554 --json',
        ),
      );
      expect(stderr, isEmpty);
    },
  );

  test(
    'package run all collects every platform and continues after failure',
    () async {
      final environment = await createTestEnvironment();
      final hdcLog = File('${environment.homeDirectory.path}/hdc.log');
      final devEco = await _writeWorkflowDevEcoFixture(
        environment.homeDirectory,
        hdcLog: hdcLog,
        hdcInstallExitCode: 0,
        hdcLaunchExitCode: 0,
      );
      final runStdout = Map<String, String>.of(_allWorkflowRunStdoutByCommand)
        ..['run -d ios-sim --debug --no-pub'] = 'Starting application.';
      final source = await _createWorkflowSdkSource(
        environment.homeDirectory,
        environment.workingDirectory,
        flutterFailures: const {'run -d ios-sim --debug --no-pub': 7},
        flutterStdout: runStdout,
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
      final example = Directory('${environment.workingDirectory.path}/example');
      await _writeFlutterExample(example);
      await _writeWorkflowPlatformDirectories(example);
      await _writeWorkflowOhosProject(example);
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
            'all',
            '--package',
            'camera',
            '--auto-emulator',
            '--log-duration',
            '0',
            '--json',
          ],
          environment: workflowEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        1,
      );

      final root = await environment.workingDirectory.resolveSymbolicLinks();
      final invocations = File(
        '${environment.workingDirectory.path}/package_workflow_invocations.txt',
      ).readAsStringSync();
      for (final entry in const {
        'emulator-5554': 'ohos',
        'android-emulator': 'android',
        'ios-sim': 'ios',
        'macos': 'macos',
        'linux': 'linux',
        'chrome': 'web',
        'windows': 'windows',
      }.entries) {
        expect(
          invocations,
          contains(
            '$root/example::flutter run -d ${entry.key} --debug --no-pub',
          ),
          reason: 'missing ${entry.value} run invocation',
        );
      }

      final report = jsonDecode(stdout.single) as Map<String, Object?>;
      expect(report, containsPair('ok', false));
      expect(report, containsPair('exitCode', 1));
      final workflowEvidence =
          report['workflowEvidence'] as Map<String, Object?>;
      expect(workflowEvidence, containsPair('classification', 'launchSmoke'));
      final observedEvidence =
          workflowEvidence['observedEvidence'] as Map<String, Object?>;
      final interactionEvidence =
          observedEvidence['interaction'] as Map<String, Object?>;
      expect(
        interactionEvidence,
        containsPair('status', 'notCollectedByThisCommand'),
      );
      expect(
        workflowEvidence['blockingDiagnostics'],
        contains('repairFailedTargets'),
      );
      final targets = (report['targets'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(targets.map((target) => target['phase']), [
        'ohos-run',
        'android-run',
        'ios-run',
        'macos-run',
        'linux-run',
        'web-run',
        'windows-run',
      ]);
      final iosTarget = targets.singleWhere(
        (target) => target['phase'] == 'ios-run',
      );
      expect(iosTarget, containsPair('exitCode', 1));
      final iosRunStep = (iosTarget['steps'] as List<Object?>)
          .cast<Map<String, Object?>>()
          .singleWhere((step) => step['name'] == 'example-run-ios');
      final iosDiagnostic =
          (iosRunStep['diagnostics'] as List<Object?>).single
              as Map<String, Object?>;
      final iosDetails = iosDiagnostic['details'] as Map<String, Object?>;
      expect(iosDetails, containsPair('exitCode', 7));
      final laterTargets = targets.skipWhile(
        (target) => target['phase'] != 'macos-run',
      );
      expect(laterTargets.map((target) => target['exitCode']), everyElement(0));
      expect(stderr, isEmpty);
    },
  );

  test(
    'package run all reports integration failure before passed evidence',
    () async {
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
        flutterFailures: const {'test integration_test -d ios-sim': 7},
        flutterStdout: _allWorkflowRunStdoutByCommand,
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
      final example = Directory('${environment.workingDirectory.path}/example');
      await _writeFlutterExample(example);
      await _writeWorkflowPlatformDirectories(example);
      await _writeWorkflowOhosProject(example);
      await Directory(
        '${example.path}/integration_test',
      ).create(recursive: true);
      await File(
        '${example.path}/integration_test/app_test.dart',
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
            'all',
            '--package',
            'camera',
            '--auto-emulator',
            '--log-duration',
            '0',
            '--json',
          ],
          environment: workflowEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        7,
      );

      final report = jsonDecode(stdout.single) as Map<String, Object?>;
      expect(report, containsPair('ok', false));
      final workflowEvidence =
          report['workflowEvidence'] as Map<String, Object?>;
      final observedEvidence =
          workflowEvidence['observedEvidence'] as Map<String, Object?>;
      final interactionEvidence =
          observedEvidence['interaction'] as Map<String, Object?>;
      expect(
        interactionEvidence,
        containsPair('status', 'integrationTestEvidenceFailed'),
      );
      expect(
        interactionEvidence,
        containsPair('passedIntegrationTargetCount', 6),
      );
      expect(
        interactionEvidence,
        containsPair('failedIntegrationTargetCount', 1),
      );
      expect(
        interactionEvidence['passedIntegrationCommands'],
        contains('flutter test integration_test -d emulator-5554'),
      );
      expect(
        interactionEvidence['failedIntegrationCommands'],
        contains('flutter test integration_test -d ios-sim'),
      );
      expect(
        workflowEvidence['notCollectedEvidenceKinds'],
        contains('functionalInteraction'),
      );
      expect(
        workflowEvidence['collectedEvidenceKinds'],
        contains('integrationTestCommandResult'),
      );
      expect(stderr, isEmpty);
    },
  );

  test('package run all reports launch smoke and suggests drive', () async {
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
      flutterStdout: _allWorkflowRunStdoutByCommand,
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
    final example = Directory('${environment.workingDirectory.path}/example');
    await _writeFlutterExample(example);
    await _writeWorkflowPlatformDirectories(example);
    await _writeWorkflowOhosProject(example);
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
          'all',
          '--package',
          'camera',
          '--auto-emulator',
          '--log-duration',
          '0',
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
    final workflowEvidence = report['workflowEvidence'] as Map<String, Object?>;
    expect(workflowEvidence, containsPair('classification', 'launchSmoke'));
    expect(
      workflowEvidence['notCollectedEvidenceKinds'],
      contains('functionalInteraction'),
    );
    expect(
      workflowEvidence['notCollectedEvidenceKinds'],
      contains('postLaunchScreenshot'),
    );
    expect(
      workflowEvidence['notCollectedEvidenceKinds'],
      contains('visualPageReadiness'),
    );
    expect(
      workflowEvidence['workflowContinuations'],
      contains('postLaunchScreenshotReview'),
    );
    expect(
      workflowEvidence['workflowContinuations'],
      contains('demoRepairBeforeFullAutomation'),
    );
    expect(workflowEvidence['workflowContinuations'], contains('reportCheck'));
    final toolCommands = (workflowEvidence['toolCommands'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(
      toolCommands,
      contains(
        allOf(
          containsPair('purpose', contains('capture post-launch screenshot')),
          containsPair(
            'command',
            'fluoh drive all --package camera --auto-emulator --dry-run --json',
          ),
        ),
      ),
    );
    expect(stderr, isEmpty);
  });

  test('package build all builds every workflow platform', () async {
    final environment = await createTestEnvironment();
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
    );
    await _writePackageManifest(environment.workingDirectory);
    await _writeFlutterPackage(environment.workingDirectory);
    final example = Directory('${environment.workingDirectory.path}/example');
    await _writeFlutterExample(example);
    await _writeWorkflowPlatformDirectories(example);
    await _writeWorkflowOhosProject(example);
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
        ['build', 'all', '--package', 'camera', '--json'],
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
    for (final command in const [
      'flutter build hap --debug',
      'flutter build apk --debug',
      'flutter build ios --debug --no-codesign',
      'flutter build macos --debug',
      'flutter build linux --debug',
      'flutter build web --debug',
      'flutter build windows --debug',
    ]) {
      expect(
        invocations,
        contains('$root/example::$command'),
        reason: 'missing $command',
      );
    }
    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('ok', true));
    final workflowEvidence = report['workflowEvidence'] as Map<String, Object?>;
    expect(workflowEvidence, containsPair('classification', 'buildOnly'));
    expect(
      workflowEvidence['notCollectedEvidenceKinds'],
      contains('launchSmoke'),
    );
    expect(workflowEvidence['workflowContinuations'], contains('reportCheck'));
    final toolCommands = (workflowEvidence['toolCommands'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(
      toolCommands,
      contains(
        containsPair(
          'command',
          'fluoh run all --package camera --auto-emulator --json',
        ),
      ),
    );
    final targets = (report['targets'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(targets.map((target) => target['phase']), [
      'ohos-build',
      'android-build',
      'ios-build',
      'macos-build',
      'linux-build',
      'web-build',
      'windows-build',
    ]);
    expect(stderr, isEmpty);
  });

  test(
    'package build all only uses existing example platform directories',
    () async {
      final environment = await createTestEnvironment();
      final source = await _createWorkflowSdkSource(
        environment.homeDirectory,
        environment.workingDirectory,
      );
      await _writePackageManifest(environment.workingDirectory);
      await _writeFlutterPackage(environment.workingDirectory);
      final example = Directory('${environment.workingDirectory.path}/example');
      await _writeFlutterExample(example);
      await _writeWorkflowOhosProject(example);
      await Directory('${example.path}/android').create(recursive: true);
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
          ['build', 'all', '--package', 'camera', '--json'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final report = jsonDecode(stdout.single) as Map<String, Object?>;
      final targets = (report['targets'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(targets.map((target) => target['phase']), [
        'ohos-build',
        'android-build',
      ]);
      final workflowEvidence =
          report['workflowEvidence'] as Map<String, Object?>;
      final scope = workflowEvidence['scope'] as Map<String, Object?>;
      expect(scope, containsPair('platforms', ['ohos', 'android']));
      expect(scope, containsPair('requestedPlatform', 'all'));
      expect(stderr, isEmpty);
    },
  );

  test('web package run uses browser target for integration tests', () async {
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
        ['run', 'web', '--json'],
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
      contains('$root/example::flutter run -d chrome --debug --no-pub'),
    );
    expect(
      invocations,
      contains('$root/example::flutter test integration_test -d chrome'),
    );
    expect(invocations, isNot(contains('run -d web-server')));

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('ok', true));
    final workflowEvidence = report['workflowEvidence'] as Map<String, Object?>;
    final observedEvidence =
        workflowEvidence['observedEvidence'] as Map<String, Object?>;
    final workflowInteractionEvidence =
        observedEvidence['interaction'] as Map<String, Object?>;
    expect(
      workflowInteractionEvidence,
      containsPair('status', 'integrationTestEvidencePresent'),
    );
    expect(
      workflowEvidence['notCollectedEvidenceKinds'],
      isNot(contains('functionalInteraction')),
    );
    expect(
      workflowEvidence['collectedEvidenceKinds'],
      contains('integrationTestCommandResult'),
    );
    final targets = report['targets'] as List<Object?>;
    final target = targets.single as Map<String, Object?>;
    expect(target.containsKey('nextCommand'), isFalse);
    final steps = target['steps'] as List<Object?>;
    final integrationStep = steps.cast<Map<String, Object?>>().singleWhere(
      (step) => step['name'] == 'example-integration-web',
    );
    expect(
      integrationStep,
      containsPair('command', 'flutter test integration_test -d chrome'),
    );
    expect(integrationStep, containsPair('status', 'passed'));
    expect(integrationStep.containsKey('nextCommand'), isFalse);
    final details = integrationStep['details'] as Map<String, Object?>;
    expect(details, containsPair('targetId', 'chrome'));
    expect(stderr, isEmpty);
  });

  test('can run macOS example and integration tests', () async {
    final environment = await createTestEnvironment();
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
      flutterStdout: const {
        'devices --machine':
            '[{"id":"macos","name":"macOS","targetPlatform":"darwin-arm64","isSupported":true}]',
        'run -d macos --debug --no-pub':
            'Flutter run key commands.\\nApplication running.',
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
        ['run', 'macos', '--json'],
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
    expect(invocations, contains('$root/example::flutter build macos --debug'));
    expect(
      invocations,
      contains('$root/example::flutter run -d macos --debug --no-pub'),
    );
    expect(
      invocations,
      contains('$root/example::flutter test integration_test -d macos'),
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
          containsPair('name', 'example-run-macos'),
          containsPair('command', 'flutter run -d macos --debug --no-pub'),
          containsPair('status', 'passed'),
        ),
      ),
    );
    expect(
      steps,
      contains(
        allOf(
          containsPair('name', 'example-integration-macos'),
          containsPair('command', 'flutter test integration_test -d macos'),
          containsPair('status', 'passed'),
        ),
      ),
    );
    expect(stderr, isEmpty);
  });

  test(
    'android run preset expands to debug build and selected device run',
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
      expect(invocations, contains('$root/example::flutter build apk --debug'));
      expect(
        invocations,
        contains(
          '$root/example::flutter run -d emulator-5554 --debug --no-pub',
        ),
      );

      final report = jsonDecode(stdout.single) as Map<String, Object?>;
      final targets = report['targets'] as List<Object?>;
      final target = targets.single as Map<String, Object?>;
      expect(target, containsPair('phase', 'android-run'));
      expect(report, containsPair('ok', true));
      expect(stderr, isEmpty);
    },
  );

  test('package run skips empty integration_test directory', () async {
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
    await _writePackageManifest(environment.workingDirectory);
    await _writeFlutterPackage(environment.workingDirectory);
    await _writeFlutterExample(
      Directory('${environment.workingDirectory.path}/example'),
    );
    await Directory(
      '${environment.workingDirectory.path}/example/integration_test',
    ).create(recursive: true);
    await File(
      '${environment.workingDirectory.path}/example/integration_test/README.md',
    ).writeAsString('# Integration notes\n');
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
      contains('$root/example::flutter run -d emulator-5554 --debug --no-pub'),
    );
    expect(
      invocations,
      isNot(contains('$root/example::flutter test integration_test -d')),
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('ok', true));
    final targets = report['targets'] as List<Object?>;
    final target = targets.single as Map<String, Object?>;
    final steps = target['steps'] as List<Object?>;
    final integrationStep = steps.cast<Map<String, Object?>>().singleWhere(
      (step) => step['name'] == 'example-integration-android',
    );
    expect(integrationStep, containsPair('status', 'skipped'));
    expect(
      integrationStep,
      containsPair('reason', 'no integration test files'),
    );
    final details = integrationStep['details'] as Map<String, Object?>;
    final evidence = details['interactionEvidence'] as Map<String, Object?>;
    expect(evidence, containsPair('status', 'not-present'));
    expect(evidence, containsPair('reason', 'no integration test files'));
    expect(stderr, isEmpty);
  });

  test(
    'android emulator preset starts requested emulator instead of connected device',
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
      await _writePackageManifest(environment.workingDirectory);
      await _writeFlutterPackage(environment.workingDirectory);
      await _writeFlutterExample(
        Directory('${environment.workingDirectory.path}/example'),
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
        contains(
          '$root/example::flutter run -d emulator-5554 --debug --no-pub',
        ),
      );
      expect(invocations, isNot(contains('flutter run -d connected-device')));

      final report = jsonDecode(stdout.single) as Map<String, Object?>;
      expect(report, containsPair('ok', true));
      expect(stderr, isEmpty);
    },
  );

  test('emits Android diagnostics when no run target is available', () async {
    final environment = await createTestEnvironment();
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
      flutterStdout: const {'devices --machine': '[]'},
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
        ['run', 'android', '--json'],
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
    final steps = target['steps'] as List<Object?>;
    final runStep = steps.cast<Map<String, Object?>>().singleWhere(
      (step) => step['name'] == 'example-run-android',
    );
    final diagnostics = runStep['diagnostics'] as List<Object?>;
    final diagnostic = diagnostics.single as Map<String, Object?>;
    expect(diagnostic, containsPair('code', 'android.device_missing'));
    expect(
      diagnostic,
      containsPair(
        'nextCommand',
        'fluoh run android --package camera --auto-emulator --json',
      ),
    );
    expect(
      runStep,
      containsPair(
        'nextCommand',
        'fluoh run android --package camera --auto-emulator --json',
      ),
    );
    expect(
      target,
      containsPair(
        'nextCommand',
        'fluoh run android --package camera --auto-emulator --json',
      ),
    );
    expect(stderr, isEmpty);
  });

  test('emits Web diagnostics when no browser target is available', () async {
    final environment = await createTestEnvironment();
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
      flutterStdout: const {'devices --machine': '[]'},
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
        ['run', 'web', '--package', 'camera', '--json'],
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
    final steps = target['steps'] as List<Object?>;
    final runStep = steps.cast<Map<String, Object?>>().singleWhere(
      (step) => step['name'] == 'example-run-web',
    );
    final diagnostics = runStep['diagnostics'] as List<Object?>;
    final diagnostic = diagnostics.single as Map<String, Object?>;
    expect(diagnostic, containsPair('code', 'web.device_missing'));
    expect(
      diagnostic,
      containsPair('nextCommand', 'fluoh doctor --platform web --json'),
    );
    expect(
      runStep,
      containsPair('nextCommand', 'fluoh doctor --platform web --json'),
    );
    expect(
      target,
      containsPair('nextCommand', 'fluoh doctor --platform web --json'),
    );
    expect(stderr, isEmpty);
  });
}
