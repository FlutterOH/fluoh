part of 'workflow_commands_test.dart';

void _registerWorkflowCommandsAttachTests() {
  test('attach rejects all platform shortcut', () async {
    final environment = await createTestEnvironment();
    final stdout = <String>[];
    final stderr = <String>[];

    final exitCode = await runFluoh(
      ['attach', 'all', '--device-id', 'test-device', '--dry-run', '--json'],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(exitCode, 64);
    expect(stderr, isEmpty);
    expect(stdout, hasLength(1));
    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('ok', false));
    expect(report, containsPair('exitCode', 64));
    final error = report['error'] as Map<String, Object?>;
    expect(
      error,
      containsPair('message', contains('Unsupported attach platform "all"')),
    );
    expect(error['message'], isNot(contains('Expected one of: all')));
  });

  test('attach uses VM Service URI from a run session', () async {
    final environment = await createTestEnvironment();
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
    );
    await writeFlutterProjectFixture(environment.workingDirectory);
    final sessionFile = File(
      '${environment.workingDirectory.path}/.fluoh/run-session.json',
    );
    await sessionFile.parent.create(recursive: true);
    await sessionFile.writeAsString('''
{
  "schema": 1,
  "kind": "flutterRunSession",
  "status": "running",
  "platform": "ohos",
  "command": "flutter run -d emulator-5554 --debug --no-pub",
  "processId": 1234,
  "targetId": "emulator-5554",
  "vmServiceUri": "http://127.0.0.1:23456/ohos=/",
  "launchDetected": true
}
''');
    final setupStdout = <String>[];
    final setupStderr = <String>[];
    await runFluoh(
      ['source', 'add', 'fixture', source.path],
      environment: environment,
      stdout: setupStdout.add,
      stderr: setupStderr.add,
    );
    await runFluoh(
      ['sdk', 'use', '3.35.8-ohos-0.0.3'],
      environment: environment,
      stdout: setupStdout.add,
      stderr: setupStderr.add,
    );
    final stdout = <String>[];
    final stderr = <String>[];

    final exitCode = await runFluoh(
      ['attach', 'ohos', '--session-file', '.fluoh/run-session.json', '--json'],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(exitCode, 0);
    expect(stderr, isEmpty);
    expect(stdout, hasLength(1));
    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('command', 'attach'));
    expect(report, containsPair('ok', true));
    expect(report, containsPair('exitCode', 0));
    expect(report, containsPair('platform', 'ohos'));
    expect(
      report,
      containsPair('vmServiceUri', 'http://127.0.0.1:23456/ohos=/'),
    );
    expect(
      report,
      containsPair(
        'flutterCommand',
        'flutter attach --debug-uri http://127.0.0.1:23456/ohos=/',
      ),
    );
    final invocations = File(
      '${environment.workingDirectory.path}/package_workflow_invocations.txt',
    ).readAsStringSync();
    expect(
      invocations,
      contains(
        '${environment.workingDirectory.path}::flutter attach --debug-uri http://127.0.0.1:23456/ohos=/',
      ),
    );
  });

  test('attach dry-run uses target id for detached run sessions', () async {
    final environment = await createTestEnvironment();
    await writeFlutterProjectFixture(environment.workingDirectory);
    final sessionFile = File(
      '${environment.workingDirectory.path}/.fluoh/run-session.json',
    );
    await sessionFile.parent.create(recursive: true);
    await sessionFile.writeAsString('''
{
  "schema": 1,
  "kind": "flutterRunSession",
  "status": "passed",
  "platform": "ohos",
  "targetId": "127.0.0.1:5555",
  "vmServiceUri": "http://127.0.0.1:23456/",
  "launchDetected": true,
  "detached": true
}
''');
    final stdout = <String>[];
    final stderr = <String>[];

    final exitCode = await runFluoh(
      [
        'attach',
        'ohos',
        '--session-file',
        '.fluoh/run-session.json',
        '--dry-run',
        '--json',
      ],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(exitCode, 0);
    expect(stderr, isEmpty);
    expect(stdout, hasLength(1));
    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('ok', true));
    expect(report, containsPair('platform', 'ohos'));
    expect(report, containsPair('targetId', '127.0.0.1:5555'));
    expect(report.containsKey('vmServiceUri'), isFalse);
    expect(
      report,
      containsPair('attachTargetSource', 'detachedSessionTargetId'),
    );
    expect(
      report,
      containsPair('flutterCommand', 'flutter attach -d 127.0.0.1:5555'),
    );
  });

  test('attach dry-run falls back to session target id', () async {
    final environment = await createTestEnvironment();
    await writeFlutterProjectFixture(environment.workingDirectory);
    final sessionFile = File(
      '${environment.workingDirectory.path}/.fluoh/run-session.json',
    );
    await sessionFile.parent.create(recursive: true);
    await sessionFile.writeAsString('''
{
  "schema": 1,
  "kind": "flutterRunSession",
  "status": "running",
  "platform": "android",
  "targetId": "emulator-5554",
  "launchDetected": true
}
''');
    final stdout = <String>[];
    final stderr = <String>[];

    final exitCode = await runFluoh(
      [
        'attach',
        'android',
        '--session-file',
        '.fluoh/run-session.json',
        '--dry-run',
        '--json',
      ],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(exitCode, 0);
    expect(stderr, isEmpty);
    expect(stdout, hasLength(1));
    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('ok', true));
    expect(report, containsPair('platform', 'android'));
    expect(report, containsPair('targetId', 'emulator-5554'));
    expect(
      report,
      containsPair('flutterCommand', 'flutter attach -d emulator-5554'),
    );
    expect(
      await File(
        '${environment.workingDirectory.path}/package_workflow_invocations.txt',
      ).exists(),
      isFalse,
    );
  });

  test('attach reports missing VM Service when required', () async {
    final environment = await createTestEnvironment();
    await writeFlutterProjectFixture(environment.workingDirectory);
    final sessionFile = File(
      '${environment.workingDirectory.path}/.fluoh/run-session.json',
    );
    await sessionFile.parent.create(recursive: true);
    await sessionFile.writeAsString('''
{
  "schema": 1,
  "kind": "flutterRunSession",
  "status": "running",
  "platform": "ios",
  "targetId": "ios-sim",
  "launchDetected": true
}
''');
    final stdout = <String>[];
    final stderr = <String>[];

    final exitCode = await runFluoh(
      [
        'attach',
        'ios',
        '--session-file',
        '.fluoh/run-session.json',
        '--require-vm-service',
        '--json',
      ],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(exitCode, 1);
    expect(stderr, isEmpty);
    expect(stdout, hasLength(1));
    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('ok', false));
    final diagnostic = report['diagnostic'] as Map<String, Object?>;
    expect(diagnostic, containsPair('code', 'ios.vm_service_missing'));
  });
}
