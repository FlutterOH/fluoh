part of 'workflow_commands_test.dart';

void _registerWorkflowCommandsPresetsDiagnosticsTests() {
  test('emits iOS diagnostics when example run fails', () async {
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
        ['run', 'ios', '--json'],
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
      (step) => step['name'] == 'example-run-ios',
    );
    final diagnostics = runStep['diagnostics'] as List<Object?>;
    final diagnostic = diagnostics.single as Map<String, Object?>;
    expect(diagnostic, containsPair('code', 'ios.run_failed'));
    expect(diagnostic, containsPair('message', 'Flutter example run failed'));
    expect(
      diagnostic,
      containsPair(
        'nextCommand',
        'fluoh run ios --package camera --auto-emulator --json',
      ),
    );
    expect(
      runStep,
      containsPair(
        'nextCommand',
        'fluoh run ios --package camera --auto-emulator --json',
      ),
    );
    expect(
      target,
      containsPair(
        'nextCommand',
        'fluoh run ios --package camera --auto-emulator --json',
      ),
    );
    expect(stderr, isEmpty);
  });

  test('emits structured diagnostics for failed JSON checks', () async {
    final environment = await createTestEnvironment();
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
      flutterFailures: const {'analyze': 2},
    );
    await _writePackageManifest(environment.workingDirectory);
    await _writeFlutterPackage(environment.workingDirectory);
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
        ['verify', '--json'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      2,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('ok', false));
    expect(report, containsPair('exitCode', 2));
    final targets = report['targets'] as List<Object?>;
    final target = targets.single as Map<String, Object?>;
    final steps = target['steps'] as List<Object?>;
    final analyzeStep = steps.cast<Map<String, Object?>>().singleWhere(
      (step) => step['name'] == 'package-analyze',
    );
    final diagnostics = analyzeStep['diagnostics'] as List<Object?>;
    final diagnostic = diagnostics.single as Map<String, Object?>;
    expect(diagnostic, containsPair('code', 'dart.analysis_failed'));
    expect(diagnostic, containsPair('severity', 'error'));
    final details = diagnostic['details'] as Map<String, Object?>;
    expect(details, containsPair('command', 'flutter analyze'));
    expect(details, containsPair('stdoutTail', contains('flutter stdout')));
    expect(details, containsPair('stderrTail', contains('flutter stderr')));
    expect(details, containsPair('outputTail', contains('flutter stdout')));
    expect(details, containsPair('outputTail', contains('flutter stderr')));
    expect(
      diagnostic,
      containsPair('nextCommand', 'fluoh verify --package camera --json'),
    );
    expect(
      analyzeStep,
      containsPair('nextCommand', 'fluoh verify --package camera --json'),
    );
    expect(
      target,
      containsPair('nextCommand', 'fluoh verify --package camera --json'),
    );
    expect(stderr, isEmpty);
  });

  test('emits JSON diagnostics when automatic signing cannot start', () async {
    final environment = await createTestEnvironment();
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
    );
    final workflowEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: environment.workingDirectory,
      processEnvironment: {
        ...environment.processEnvironment,
        'FLUOH_DEVECO_STUDIO':
            '${environment.homeDirectory.path}/missing/DevEco-Studio.app',
      },
    );
    await _writePackageManifest(environment.workingDirectory);
    await _writeFlutterPackage(environment.workingDirectory, withTests: false);
    await _writeFlutterExample(
      Directory('${environment.workingDirectory.path}/example'),
      withTests: false,
    );
    await Directory(
      '${environment.workingDirectory.path}/example/ohos',
    ).create(recursive: true);
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
        ['build', 'ohos', '--auto-sign', '--json'],
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
    final autoSignStep = steps.cast<Map<String, Object?>>().singleWhere(
      (step) => step['name'] == 'ohos-auto-sign',
    );
    expect(autoSignStep, containsPair('status', 'failed'));
    final diagnostics = autoSignStep['diagnostics'] as List<Object?>;
    final diagnostic = diagnostics.single as Map<String, Object?>;
    expect(diagnostic, containsPair('code', 'ohos.toolchain_missing'));
    expect(stderr, isEmpty);
  });

  test('uses dart test for non-Flutter packages', () async {
    final environment = await createTestEnvironment();
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
    );
    await _writePackageManifest(environment.workingDirectory);
    await _writeDartPackage(environment.workingDirectory);
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'add', 'fixture', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    stdout.clear();

    expect(
      await runFluoh(
        ['verify'],
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
      [
        '$root::dart pub get',
        '$root::dart analyze',
        '$root::dart test',
        '',
      ].join('\n'),
    );
    expect(stdout, contains('Package analysis passed for camera'));
    expect(stdout, contains('Package tests passed for camera'));
    expect(
      stdout.join('\n'),
      contains('Skipping example verification for camera'),
    );
    expect(stderr, contains('dart stderr'));
  });

  test('runs analysis even when no tests exist', () async {
    final environment = await createTestEnvironment();
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
    );
    await _writePackageManifest(environment.workingDirectory);
    await _writeFlutterPackage(environment.workingDirectory, withTests: false);
    await _writeFlutterExample(
      Directory('${environment.workingDirectory.path}/example'),
      withTests: false,
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

    expect(
      await runFluoh(
        ['verify'],
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
      [
        '$root::flutter pub get',
        '$root::flutter analyze',
        '$root/example::flutter pub get',
        '$root/example::flutter analyze',
        '',
      ].join('\n'),
    );
    expect(stdout, contains('Package analysis passed for camera'));
    expect(stdout, contains('Example analysis passed for camera'));
    expect(
      stdout.join('\n'),
      contains('Skipping package tests for camera: no test files'),
    );
    expect(
      stdout.join('\n'),
      contains('Skipping example tests for camera: no example test files'),
    );
    expect(stdout, contains('Verification passed'));
    expect(stderr, contains('flutter stderr'));
  });

  test('fails when a registered package has no pubspec', () async {
    final environment = await createTestEnvironment();
    await _writePackageManifest(environment.workingDirectory);
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['verify'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );

    expect(stderr.join('\n'), contains('Missing pubspec.yaml in .'));
    expect(stdout, contains('Verifying camera'));
    expect(stdout, isNot(contains('Verification passed')));
  });

  test('requires automatic signing support when requested', () async {
    final environment = await createTestEnvironment();
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['build', 'android', '--auto-sign'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );

    expect(
      stderr.join('\n'),
      contains(
        'Use --auto-sign only with platforms that support automatic signing.',
      ),
    );
  });

  test('does not allow device and emulator together', () async {
    final environment = await createTestEnvironment();
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        [
          'run',
          'android',
          '--device-id',
          'emulator-5554',
          '--emulator',
          'Pixel',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );

    expect(
      stderr.join('\n'),
      contains('Use only one of --device-id or --emulator.'),
    );
  });

  test('does not allow auto emulator with explicit run target', () async {
    final environment = await createTestEnvironment();
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['run', 'android', '--device-id', 'emulator-5554', '--auto-emulator'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );
    expect(
      stderr.join('\n'),
      contains('Use only one of --device-id or --auto-emulator.'),
    );

    stdout.clear();
    stderr.clear();

    expect(
      await runFluoh(
        ['run', 'android', '--emulator', 'Pixel', '--auto-emulator'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );
    expect(
      stderr.join('\n'),
      contains('Use only one of --emulator or --auto-emulator.'),
    );
  });

  test('validates run timeout options', () async {
    final environment = await createTestEnvironment();
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['run', 'android', '--device-timeout', 'not-seconds'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );

    expect(
      stderr.join('\n'),
      contains('Use a non-negative integer for --device-timeout.'),
    );
  });

  test('validates run debug session options', () async {
    final environment = await createTestEnvironment();
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['run', 'all', '--session-file', '.fluoh/run-session.json'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );

    expect(
      stderr.join('\n'),
      contains(
        'Use --session-file with one run platform and one run target at a time.',
      ),
    );
  });

  test('validates all-platform run target options', () async {
    final environment = await createTestEnvironment();
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['run', 'all', '--session-file', '.fluoh/run-session.json'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );
    expect(
      stderr.join('\n'),
      contains(
        'Use --session-file with one run platform and one run target at a time.',
      ),
    );

    stdout.clear();
    stderr.clear();
    expect(
      await runFluoh(
        ['run', 'all', '--device-id', 'emulator-5554'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );
    expect(
      stderr.join('\n'),
      contains('Use --device-id with one run platform.'),
    );
  });
}
