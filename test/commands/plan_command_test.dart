import 'dart:convert';
import 'dart:io';

import 'package:fluoh/fluoh.dart';
import 'package:test/test.dart';

import '../helpers/fluoh_command_context.dart';
import '../helpers/package_test_context.dart';

void main() {
  test('plan app and package default to read-only plan mode', () async {
    final environment = await createTestEnvironment();
    final appStdout = <String>[];
    final appStderr = <String>[];

    expect(
      await runFluoh(
        ['plan', 'app', '--json'],
        environment: environment,
        stdout: appStdout.add,
        stderr: appStderr.add,
      ),
      0,
    );

    expect(appStderr, isEmpty);
    final appPayload = jsonDecode(appStdout.single) as Map<String, Object?>;
    expect(appPayload, containsPair('command', 'plan app'));
    expect(appPayload, containsPair('ok', false));
    expect(appPayload, containsPair('exitCode', 0));
    final appPlan = appPayload['plan'] as Map<String, Object?>;
    expect(appPlan, containsPair('readyToPlan', false));
    expect(appPlan['error'], {'message': 'Missing pubspec.yaml.'});

    final packageStdout = <String>[];
    final packageStderr = <String>[];
    expect(
      await runFluoh(
        ['plan', 'package', '--json'],
        environment: environment,
        stdout: packageStdout.add,
        stderr: packageStderr.add,
      ),
      0,
    );

    expect(packageStderr, isEmpty);
    final packagePayload =
        jsonDecode(packageStdout.single) as Map<String, Object?>;
    expect(packagePayload, containsPair('command', 'plan package'));
    expect(packagePayload, containsPair('ok', false));
    expect(packagePayload, containsPair('exitCode', 0));
    final packagePlan = packagePayload['plan'] as Map<String, Object?>;
    expect(packagePlan, containsPair('readyToPlan', false));
  });

  test('plan app emits no command queue outside Flutter apps', () async {
    final environment = await createTestEnvironment();
    await File(
      '${environment.workingDirectory.path}/pubspec.yaml',
    ).writeAsString('''
name: dart_package
dependencies:
  args: ^2.7.0
''');
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['plan', 'app', '--json'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('command', 'plan app'));
    expect(report, containsPair('ok', false));
    final plan = report['plan'] as Map<String, Object?>;
    expect(plan, containsPair('readyToPlan', false));
    expect(plan['error'], {
      'message': 'Current directory is not a Flutter app project.',
    });
    expect(plan['queue'], isEmpty);
    expect(stderr, isEmpty);
  });

  test('plan app emits a command queue as json', () async {
    final environment = await createTestEnvironment();
    await File(
      '${environment.workingDirectory.path}/pubspec.yaml',
    ).writeAsString('''
name: example_app
dependencies:
  flutter:
    sdk: flutter
''');
    await File('${environment.workingDirectory.path}/fluoh.yaml').writeAsString(
      '''
schema: 1
kind: project

sdk:
  version: 3.35.8-ohos-0.0.3

dependencyPolicy:
  pubspecSection: dependency_overrides
  versionChanges: compatible
''',
    );
    await Directory('${environment.workingDirectory.path}/ohos').create();
    await Directory('${environment.workingDirectory.path}/android').create();
    await Directory('${environment.workingDirectory.path}/web').create();
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['plan', 'app', '--json'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
      reason: [...stdout, ...stderr].join('\n'),
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('schema', 1));
    expect(report, containsPair('command', 'plan app'));
    expect(report, containsPair('ok', true));
    expect(report, containsPair('changed', false));
    expect(report, containsPair('applied', false));
    final plan = report['plan'] as Map<String, Object?>;
    expect(plan, containsPair('adaptationKind', 'app'));
    expect(plan, containsPair('readyToPlan', true));
    expect(plan, containsPair('projectName', 'example_app'));
    expect(
      plan['sdk'],
      allOf(
        containsPair('selected', '3.35.8-ohos-0.0.3'),
        containsPair('source', 'fluoh.yaml'),
      ),
    );
    final project = plan['project'] as Map<String, Object?>;
    expect(project, containsPair('hasOhos', true));
    final platforms = project['platformDirectories'] as Map<String, Object?>;
    expect(platforms, containsPair('android', true));
    expect(platforms, containsPair('web', true));
    expect(platforms, containsPair('ios', false));
    final queue = (plan['queue'] as List<Object?>).cast<Map<String, Object?>>();
    expect(
      queue.map((item) => item['command']).toList(),
      containsAllInOrder([
        'fluoh source update',
        'fluoh sdk use 3.35.8-ohos-0.0.3 --pub-get',
        'fluoh deps check --json',
        'fluoh build ohos --auto-sign --json --trace-dir .fluoh/traces/example_app/adaptation',
        'fluoh devices --platform ohos --json',
        'fluoh emulators --platform ohos --json',
        'fluoh run ohos --auto-emulator --json --trace-dir .fluoh/traces/example_app/adaptation',
        'fluoh drive ohos --json --trace-dir .fluoh/traces/example_app/adaptation',
        'fluoh drive android --json --trace-dir .fluoh/traces/example_app/adaptation',
        'fluoh doctor --platform android --json --strict',
        'fluoh run android --auto-emulator --json --trace-dir .fluoh/traces/example_app/adaptation',
        'fluoh doctor --platform web --json --strict',
        'fluoh run web --json --trace-dir .fluoh/traces/example_app/adaptation',
        'fluoh report create --scope example_app --trace-dir .fluoh/traces/example_app/adaptation --json',
        'python3 <skill-dir>/scripts/check_report.py <report-path>',
      ]),
    );
    expect(
      queue,
      contains(
        allOf(
          containsPair('phase', 'setup'),
          containsPair('command', 'fluoh source update'),
          containsPair('mutating', true),
          containsPair('requiresApproval', true),
          containsPair('expectedEvidence', 'source update result'),
        ),
      ),
    );
    expect(
      queue,
      contains(
        allOf(
          containsPair('phase', 'ohos'),
          containsPair('command', 'fluoh devices --platform ohos --json'),
          containsPair('requiresApproval', false),
          containsPair('expectedEvidence', 'connected OHOS target inventory'),
        ),
      ),
    );
    expect(
      queue,
      contains(
        allOf(
          containsPair('phase', 'automation'),
          containsPair('requiresApproval', true),
          containsPair(
            'expectedEvidence',
            'automation coverage policy, scenarios, and repair queue',
          ),
        ),
      ),
    );
    expect(
      queue,
      contains(
        allOf(
          containsPair('phase', 'report'),
          containsPair('requiresApproval', true),
          containsPair('expectedEvidence', 'local AI report path'),
          containsPair('mustCompleteForDelivery', true),
          containsPair('failureAction', contains('report check')),
        ),
      ),
    );
    expect(
      queue,
      contains(
        allOf(
          containsPair('phase', 'report-check'),
          containsPair(
            'command',
            'python3 <skill-dir>/scripts/check_report.py <report-path>',
          ),
          containsPair('requiresApproval', false),
          containsPair('expectedEvidence', 'canonical report validation JSON'),
          containsPair('mustCompleteForDelivery', true),
        ),
      ),
    );
    final automationRunbook = plan['automationRunbook'] as Map<String, Object?>;
    expect(automationRunbook, containsPair('mode', 'autonomous-to-delivery'));
    final appQualityGates = (automationRunbook['qualityGates'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(
      appQualityGates.map((gate) => gate['id']),
      containsAll([
        'functional-test-baseline',
        'complete-existing-platform-matrix',
        'behavior-evidence-not-smoke',
      ]),
    );
    expect(
      stringList(automationRunbook['executionRules']),
      containsAll([
        contains('add or repair missing functional tests'),
        contains('Do not focus only on OHOS'),
      ]),
    );
    final appCheckpointPolicy =
        automationRunbook['checkpointPolicy'] as Map<String, Object?>;
    expect(appCheckpointPolicy, containsPair('mode', 'auto-local-commits'));
    expect(
      appCheckpointPolicy,
      containsPair('scopeApprovalAuthorizesCommits', true),
    );
    expect(
      stringList(appCheckpointPolicy['commitPhases']),
      containsAll(['implementation', 'delivery report handoff']),
    );
    final deliveryGate = plan['deliveryGate'] as Map<String, Object?>;
    expect(deliveryGate, containsPair('status', 'active'));
    expect(
      stringList(deliveryGate['finalCheckCommands']),
      containsAll([
        'git diff --check',
        'fluoh drive ohos --json --trace-dir .fluoh/traces/example_app/adaptation',
        'fluoh drive android --json --trace-dir .fluoh/traces/example_app/adaptation',
        'fluoh doctor --platform android --json --strict',
        'fluoh doctor --platform web --json --strict',
        'python3 <skill-dir>/scripts/check_report.py <report-path>',
      ]),
    );
    expect(
      stringList(deliveryGate['readyRequires']),
      containsAll([
        contains('existing tests and integration tests were reviewed'),
        contains('functional evidence validates'),
        contains('every existing non-OHOS platform directory'),
        contains('reportCheckCommand passes'),
      ]),
    );
    expect(
      queue,
      contains(
        allOf(
          containsPair('phase', 'regression'),
          containsPair(
            'command',
            'fluoh run android --auto-emulator --json --trace-dir .fluoh/traces/example_app/adaptation',
          ),
          containsPair(
            'expectedEvidence',
            'android functional regression evidence',
          ),
        ),
      ),
    );
    expect(stderr, isEmpty);
  });

  test('plan package emits a command queue as json', () async {
    final environment = await createTestEnvironment();
    final packageRepository = await createPackageRepositoryFixture(environment);
    await Directory(
      '${packageRepository.path}/example/android',
    ).create(recursive: true);
    await Directory(
      '${packageRepository.path}/example/web',
    ).create(recursive: true);
    await File(
      '${packageRepository.path}/example/android/.keep',
    ).writeAsString('');
    await File('${packageRepository.path}/example/web/.keep').writeAsString('');
    await commitAll(packageRepository, message: 'Add example platforms');
    final packageEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['plan', 'package', '--json'],
        environment: packageEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
      reason: [...stdout, ...stderr].join('\n'),
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('schema', 1));
    expect(report, containsPair('command', 'plan package'));
    expect(report, containsPair('ok', true));
    expect(report, containsPair('changed', false));
    expect(report, containsPair('applied', false));
    final plan = report['plan'] as Map<String, Object?>;
    expect(plan, containsPair('adaptationKind', 'package'));
    expect(plan, containsPair('readyToPlan', true));
    expect(
      plan['sdk'],
      allOf(
        containsPair('selected', '3.35.8-ohos-0.0.3'),
        containsPair('source', 'fluoh.yaml'),
      ),
    );
    final repository = plan['repository'] as Map<String, Object?>;
    expect(repository, containsPair('branchMatchesManifest', true));
    expect(repository, containsPair('dirty', false));
    final package = plan['package'] as Map<String, Object?>;
    expect(package, containsPair('name', 'camera'));
    expect(package, containsPair('path', '.'));
    expect(package, containsPair('upstreamVersion', '0.11.0'));
    expect(package, containsPair('releaseVersion', '0.1.0'));
    expect(package, containsPair('hasExample', true));
    final platforms = package['examplePlatforms'] as Map<String, Object?>;
    expect(platforms, containsPair('android', true));
    expect(platforms, containsPair('web', true));
    expect(platforms, containsPair('ios', false));
    final queue = (plan['queue'] as List<Object?>).cast<Map<String, Object?>>();
    expect(
      queue.map((item) => item['command']).toList(),
      containsAllInOrder([
        'fluoh package docs refresh --dry-run',
        'fluoh package docs refresh',
        'fluoh verify --package camera --json --trace-dir .fluoh/traces/camera/adaptation',
        'fluoh build ohos --package camera --auto-sign --json --trace-dir .fluoh/traces/camera/adaptation',
        'fluoh devices --platform ohos --json',
        'fluoh emulators --platform ohos --json',
        'fluoh run ohos --package camera --auto-emulator --json --trace-dir .fluoh/traces/camera/adaptation',
        'fluoh drive ohos --package camera --json --trace-dir .fluoh/traces/camera/adaptation',
        'fluoh drive android --package camera --json --trace-dir .fluoh/traces/camera/adaptation',
        'fluoh run android --package camera --auto-emulator --json --trace-dir .fluoh/traces/camera/adaptation',
        'fluoh run web --package camera --json --trace-dir .fluoh/traces/camera/adaptation',
        'fluoh report create --scope camera --package camera --trace-dir .fluoh/traces/camera/adaptation --json',
        'python3 <skill-dir>/scripts/check_report.py <report-path>',
        'fluoh package handoff --package camera --json',
        'fluoh package check --package camera --report <report-path> --json',
      ]),
    );
    expect(
      queue,
      contains(
        allOf(
          containsPair('phase', 'docs'),
          containsPair('command', 'fluoh package docs refresh'),
          containsPair('requiresApproval', true),
        ),
      ),
    );
    expect(
      queue,
      contains(
        allOf(
          containsPair('phase', 'handoff'),
          containsPair(
            'command',
            'fluoh package handoff --package camera --json',
          ),
          containsPair('requiresApproval', false),
          containsPair('mustCompleteForDelivery', true),
        ),
      ),
    );
    final safety = plan['safety'] as Map<String, Object?>;
    expect(safety, containsPair('autoCheckpointCommits', true));
    expect(safety, containsPair('scopeApprovalAuthorizesLocalCommits', true));
    expect(
      stringList(safety['willNotRunWithoutSeparateApproval']),
      isNot(contains('commit')),
    );
    final automationRunbook = plan['automationRunbook'] as Map<String, Object?>;
    final packageQualityGates =
        (automationRunbook['qualityGates'] as List<Object?>)
            .cast<Map<String, Object?>>();
    expect(
      packageQualityGates.map((gate) => gate['id']),
      containsAll([
        'functional-test-baseline',
        'complete-existing-platform-matrix',
        'behavior-evidence-not-smoke',
      ]),
    );
    expect(
      stringList(automationRunbook['executionRules']),
      containsAll([
        contains('add or repair missing functional tests'),
        contains('every existing platform'),
      ]),
    );
    final checkpointPolicy =
        automationRunbook['checkpointPolicy'] as Map<String, Object?>;
    expect(checkpointPolicy, containsPair('mode', 'auto-local-commits'));
    expect(
      stringList(checkpointPolicy['commitPhases']),
      containsAll(['release metadata', 'delivery report handoff']),
    );
    final deliveryGate = plan['deliveryGate'] as Map<String, Object?>;
    expect(deliveryGate, containsPair('status', 'active'));
    expect(
      stringList(deliveryGate['finalCheckCommands']),
      containsAll([
        'git diff --check',
        'fluoh verify --package camera --json --trace-dir .fluoh/traces/camera/adaptation',
        'fluoh drive ohos --package camera --json --trace-dir .fluoh/traces/camera/adaptation',
        'fluoh drive android --package camera --json --trace-dir .fluoh/traces/camera/adaptation',
        'fluoh doctor --platform android --json --strict',
        'fluoh doctor --platform web --json --strict',
        'python3 <skill-dir>/scripts/check_report.py <report-path>',
        'fluoh package handoff --package camera --json',
        'fluoh package check --package camera --report <report-path> --json',
      ]),
    );
    expect(
      stringList(deliveryGate['needsMaintainerDecision']),
      allOf(contains(contains('release')), isNot(contains(contains('commit')))),
    );
    expect(
      stringList(deliveryGate['readyRequires']),
      containsAll([
        contains('existing tests and integration tests were reviewed'),
        contains('functional evidence validates'),
        contains('every existing non-OHOS platform directory'),
      ]),
    );
    expect(
      queue,
      contains(
        allOf(
          containsPair('phase', 'regression'),
          containsPair(
            'command',
            'fluoh run android --package camera --auto-emulator --json --trace-dir .fluoh/traces/camera/adaptation',
          ),
          containsPair(
            'expectedEvidence',
            'android package example functional evidence',
          ),
        ),
      ),
    );
    expect(
      queue,
      contains(
        allOf(
          containsPair('phase', 'report-check'),
          containsPair(
            'command',
            'python3 <skill-dir>/scripts/check_report.py <report-path>',
          ),
          containsPair('requiresApproval', false),
          containsPair('expectedEvidence', 'canonical report validation JSON'),
          containsPair('mustCompleteForDelivery', true),
        ),
      ),
    );
    expect(stderr, isEmpty);
  });
}

List<String> stringList(Object? value) {
  return (value as List<Object?>).cast<String>();
}
