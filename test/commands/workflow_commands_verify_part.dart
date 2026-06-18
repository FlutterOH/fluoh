part of 'workflow_commands_test.dart';

void _registerWorkflowCommandsVerifyTests() {
  test('runs existing Flutter package and example tests', () async {
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
      ['source', 'enable', 'fixture', source.path],
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
        '$root::flutter test',
        '$root/example::flutter pub get',
        '$root/example::flutter analyze',
        '$root/example::flutter test',
        '',
      ].join('\n'),
    );
    expect(stdout, contains('Verifying camera'));
    expect(stdout, contains('Package analysis passed for camera'));
    expect(stdout, contains('Package tests passed for camera'));
    expect(stdout, contains('Example analysis passed for camera'));
    expect(stdout, contains('Example tests passed for camera'));
    expect(stdout, contains('Verification passed'));
    expect(stderr, contains('flutter stderr'));
  });

  test('verify runs package workflows', () async {
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
      ['source', 'enable', 'fixture', source.path],
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
      0,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('schema', 1));
    expect(report, containsPair('command', 'verify'));
    expect(report, containsPair('ok', true));
    final targets = report['targets'] as List<Object?>;
    final target = targets.single as Map<String, Object?>;
    final identity = target['target'] as Map<String, Object?>;
    expect(identity, containsPair('kind', 'package'));
    expect(identity, containsPair('name', 'camera'));
    expect(target, containsPair('phase', 'baseline'));
    expect(stderr, isEmpty);
  });

  test('verify reports discovered example integration tests', () async {
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
    await Directory(
      '${environment.workingDirectory.path}/example/integration_test',
    ).create(recursive: true);
    await File(
      '${environment.workingDirectory.path}/example/integration_test/app_test.dart',
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
        ['verify', '--json'],
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
      isNot(contains('$root/example::flutter test integration_test -d')),
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('ok', true));
    final targets = report['targets'] as List<Object?>;
    final target = targets.single as Map<String, Object?>;
    expect(target.containsKey('nextCommand'), isFalse);
    final steps = target['steps'] as List<Object?>;
    final integrationStep = steps.cast<Map<String, Object?>>().singleWhere(
      (step) => step['name'] == 'example-integration',
    );
    expect(integrationStep, containsPair('status', 'skipped'));
    expect(
      integrationStep,
      containsPair('reason', 'requires a platform run target'),
    );
    final details = integrationStep['details'] as Map<String, Object?>;
    expect(details, containsPair('testDirectory', 'example/integration_test'));
    expect(
      details['suggestedCommands'] as List<Object?>,
      contains('fluoh run ohos --package camera --auto-emulator --json'),
    );
    final evidence = details['interactionEvidence'] as Map<String, Object?>;
    expect(evidence, containsPair('method', 'integration_test'));
    expect(evidence, containsPair('status', 'available'));
    expect(details, contains('manualAssistedFallback'));
    expect(stderr, isEmpty);
  });

  test('verify reports working tree changes left by workflow tools', () async {
    final environment = await createTestEnvironment();
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
      flutterSideEffects: const {
        'pub get':
            'mkdir -p ohos/flutter example/.dart_tool '
            'ios/Flutter/ephemeral example/ios/Flutter/ephemeral\n'
            'printf "%s\\n" generated > ohos/flutter/generated_plugins.cmake\n'
            'printf "%s\\n" "{}" > example/.dart_tool/package_config.json\n'
            'printf "%s\\n" helper > ios/Flutter/ephemeral/flutter_lldb_helper.py\n'
            'printf "%s\\n" init > example/ios/Flutter/ephemeral/flutter_lldbinit',
      },
    );
    await _writePackageManifest(environment.workingDirectory);
    await _writeFlutterPackage(environment.workingDirectory);
    await File(
      '${environment.workingDirectory.path}/.gitignore',
    ).writeAsString('package_workflow_invocations.txt*\n');
    await _runProcess('git', [
      'init',
      '--initial-branch=main',
    ], environment.workingDirectory);
    await _runProcess('git', [
      'config',
      'user.email',
      'fixture@example.com',
    ], environment.workingDirectory);
    await _runProcess('git', [
      'config',
      'user.name',
      'Fixture',
    ], environment.workingDirectory);
    await _runProcess('git', ['add', '.'], environment.workingDirectory);
    await _runProcess('git', [
      'commit',
      '-m',
      'Initial package',
    ], environment.workingDirectory);
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
        ['verify', '--package', 'camera', '--json'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report['dirtyAfterVerify'], isTrue);
    final changes = report['workingTreeChanges'] as Map<String, Object?>;
    expect(changes['available'], isTrue);
    expect(changes['beforeDirty'], isFalse);
    expect(changes['afterDirty'], isTrue);
    expect(changes['changedDuringCommand'], isTrue);
    expect(changes['generatedFilesChanged'], isTrue);
    expect(
      changes['generatedFiles'] as List<Object?>,
      contains('ohos/flutter/generated_plugins.cmake'),
    );
    expect(
      changes['generatedFiles'] as List<Object?>,
      contains('example/.dart_tool/package_config.json'),
    );
    expect(
      changes['generatedFiles'] as List<Object?>,
      contains('ios/Flutter/ephemeral/flutter_lldb_helper.py'),
    );
    expect(
      changes['generatedFiles'] as List<Object?>,
      contains('example/ios/Flutter/ephemeral/flutter_lldbinit'),
    );
    expect(changes['nextCommand'], 'git status --short');
    expect(stderr, isEmpty);
  });

  test('verify classifies package Dart SDK constraint failures', () async {
    final environment = await createTestEnvironment();
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
      flutterFailures: {'pub get': 1},
      flutterStdout: {'pub get': 'Resolving dependencies...'},
      flutterStderr: {
        'pub get': '''
The current Dart SDK version is 3.9.2.

Because camera requires SDK version ^3.10.0, version solving failed.

You can try the following suggestion to make the pubspec resolve:
* Try using the Flutter SDK version: 3.44.1.
Failed to update packages.
''',
      },
    );
    await _writePackageManifest(environment.workingDirectory);
    await _writeFlutterPackage(environment.workingDirectory);
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
        ['verify', '--package', 'camera', '--json'],
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
    expect(
      target,
      containsPair('nextCommand', 'fluoh verify --package camera --json'),
    );
    final steps = target['steps'] as List<Object?>;
    final pubGet = steps.single as Map<String, Object?>;
    expect(
      pubGet,
      containsPair('nextCommand', 'fluoh verify --package camera --json'),
    );
    final diagnostics = pubGet['diagnostics'] as List<Object?>;
    final diagnostic = diagnostics.single as Map<String, Object?>;
    expect(diagnostic, containsPair('code', 'dart.sdk_constraint_unsatisfied'));
    expect(
      diagnostic,
      containsPair('nextCommand', 'fluoh verify --package camera --json'),
    );
    final details = diagnostic['details'] as Map<String, Object?>;
    final sdkConstraint = details['sdkConstraint'] as Map<String, Object?>;
    expect(sdkConstraint, containsPair('currentDartVersion', '3.9.2'));
    expect(sdkConstraint, containsPair('requiredDartConstraint', '^3.10.0'));
    expect(
      sdkConstraint,
      containsPair('suggestedEnvironmentSdkConstraint', '>=3.9.0 <4.0.0'),
    );
    expect(sdkConstraint, containsPair('suggestedFlutterSdkVersion', '3.44.1'));
    final policy = details['supportPolicy'] as Map<String, Object?>;
    expect(
      policy['defaultAction'],
      'implement-selected-upstream-for-selected-sdk',
    );
    expect(policy['keepSelectedUpstream'], isTrue);
    expect(policy['adjustPackageForSelectedSdk'], isTrue);
    expect(policy['upstreamDowngradeRequiresApproval'], isTrue);
    expect(stderr, isEmpty);
  });

  test('verify can write an AI diagnostic trace', () async {
    final environment = await createTestEnvironment();
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
    );
    await _writePackageManifest(environment.workingDirectory);
    await _writeFlutterPackage(environment.workingDirectory);
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
        ['verify', '--json', '--trace'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('ok', true));
    final trace = report['trace'] as Map<String, Object?>;
    expect(trace, containsPair('schema', 1));
    expect(trace['id'], startsWith('verify-'));
    final manifest = File(trace['manifest']! as String);
    expect(manifest.existsSync(), isTrue);
    expect(
      manifest.path,
      allOf(
        startsWith('${environment.workingDirectory.path}/.fluoh/tasks/'),
        contains('/traces/'),
      ),
    );

    final traceReport =
        jsonDecode(manifest.readAsStringSync()) as Map<String, Object?>;
    expect(traceReport, containsPair('kind', 'fluoh.trace'));
    expect(traceReport, containsPair('command', 'verify'));
    expect(traceReport, containsPair('ok', true));
    expect(traceReport, containsPair('exitCode', 0));
    expect(
      traceReport,
      containsPair('commandLine', 'fluoh verify --json --trace'),
    );
    expect(traceReport['feedbackCandidates'], isEmpty);
    final result = traceReport['result'] as Map<String, Object?>;
    final targets = result['targets'] as List<Object?>;
    expect(targets, hasLength(1));
    expect(stderr, isEmpty);
  });

  test('package trace defaults to the current task trace directory', () async {
    final environment = await createTestEnvironment();
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
    );
    await _writePackageManifest(environment.workingDirectory);
    await _writeFlutterPackage(environment.workingDirectory);
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
        ['verify', '--package', 'camera', '--json', '--trace'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    final trace = report['trace'] as Map<String, Object?>;
    expect(trace['id'], startsWith('verify-'));
    expect(
      trace['path'],
      allOf(
        startsWith('${environment.workingDirectory.path}/.fluoh/tasks/'),
        contains('/traces/'),
      ),
    );
    final manifest = File(trace['manifest']! as String);
    expect(manifest.existsSync(), isTrue);
    expect(
      manifest.path,
      allOf(
        startsWith('${environment.workingDirectory.path}/.fluoh/tasks/'),
        contains('/traces/'),
      ),
    );
    expect(stderr, isEmpty);
  });

  test('trace-dir recovers when an existing trace manifest is invalid', () async {
    final environment = await createTestEnvironment();
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
    );
    await _writePackageManifest(environment.workingDirectory);
    await _writeFlutterPackage(environment.workingDirectory);
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

    final traceDir = Directory(
      '${environment.workingDirectory.path}/.fluoh/tasks/manual/traces/recover-invalid',
    );
    await traceDir.create(recursive: true);
    final manifest = File('${traceDir.path}/trace.json');
    await manifest.writeAsString('{invalid');

    expect(
      await runFluoh(
        ['verify', '--json', '--trace-dir', traceDir.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('ok', true));
    final trace = report['trace'] as Map<String, Object?>;
    expect(trace, containsPair('manifest', manifest.path));
    final traceReport =
        jsonDecode(manifest.readAsStringSync()) as Map<String, Object?>;
    expect(traceReport, containsPair('command', 'verify'));
    expect(traceReport['previousManifestError'], contains('Could not parse'));
    expect(traceReport['invocations'], hasLength(1));
    expect(stderr, isEmpty);
  });

  test('trace write failures do not fail json workflow commands', () async {
    final environment = await createTestEnvironment();
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
    );
    await _writePackageManifest(environment.workingDirectory);
    await _writeFlutterPackage(environment.workingDirectory);
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

    final blockedTracePath = File(
      '${environment.workingDirectory.path}/trace-blocker',
    );
    await blockedTracePath.writeAsString('not a directory');

    expect(
      await runFluoh(
        ['verify', '--json', '--trace-dir', blockedTracePath.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('ok', true));
    expect(report, isNot(contains('trace')));
    expect(report['traceError'], contains('Could not write trace manifest'));
    expect(
      report['traceError'],
      contains('${blockedTracePath.path}/trace.json'),
    );
    expect(stderr, isEmpty);
  });

  test('trace-dir accumulates an AI support command session', () async {
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
      ['source', 'enable', 'fixture', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    stdout.clear();
    stderr.clear();

    const traceDir = '.fluoh/tasks/manual/traces/support session';
    expect(
      await runFluoh(
        ['verify', '--json', '--trace-dir', traceDir],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );
    final verifyReport = jsonDecode(stdout.single) as Map<String, Object?>;
    stdout.clear();

    expect(
      await runFluoh(
        ['build', 'android', '--json', '--trace-dir', traceDir],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );
    final buildReport = jsonDecode(stdout.single) as Map<String, Object?>;

    final verifyTrace = verifyReport['trace'] as Map<String, Object?>;
    final buildTrace = buildReport['trace'] as Map<String, Object?>;
    expect(verifyTrace['manifest'], buildTrace['manifest']);
    expect(verifyTrace, containsPair('id', 'support-session'));
    final manifest = File(buildTrace['manifest']! as String);
    final traceReport =
        jsonDecode(manifest.readAsStringSync()) as Map<String, Object?>;
    expect(traceReport, containsPair('command', 'build'));
    expect(traceReport, containsPair('commandLine', contains("'$traceDir'")));
    final invocations = traceReport['invocations'] as List<Object?>;
    expect(invocations, hasLength(2));
    expect(
      invocations.map((item) => (item as Map<String, Object?>)['command']),
      ['verify', 'build'],
    );
    expect(
      invocations.first,
      containsPair(
        'commandLine',
        "fluoh verify --json --trace-dir '$traceDir'",
      ),
    );
    expect(traceReport['feedbackCandidates'], isEmpty);
    expect(stderr, isEmpty);
  });
}
