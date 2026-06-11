import 'dart:convert';
import 'dart:io';

import 'package:fluoh/fluoh.dart';
import 'package:test/test.dart';

import '../helpers/fluoh_command_context.dart';

void main() {
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
      ['source', 'add', 'fixture', source.path],
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
      ['source', 'add', 'fixture', source.path],
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
    final policy = details['adaptationPolicy'] as Map<String, Object?>;
    expect(policy['defaultAction'], 'adapt-selected-upstream-to-selected-sdk');
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
      ['source', 'add', 'fixture', source.path],
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
      startsWith('${environment.workingDirectory.path}/.fluoh/traces/'),
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

  test('package trace defaults to a package-scoped directory', () async {
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
      ['source', 'add', 'fixture', source.path],
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
      startsWith('${environment.workingDirectory.path}/.fluoh/traces/camera/'),
    );
    final manifest = File(trace['manifest']! as String);
    expect(manifest.existsSync(), isTrue);
    expect(
      manifest.path,
      startsWith('${environment.workingDirectory.path}/.fluoh/traces/camera/'),
    );
    expect(stderr, isEmpty);
  });

  test(
    'trace-dir recovers when an existing trace manifest is invalid',
    () async {
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
        ['source', 'add', 'fixture', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      stdout.clear();
      stderr.clear();

      final traceDir = Directory(
        '${environment.workingDirectory.path}/.fluoh/traces/recover-invalid',
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
    },
  );

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
      ['source', 'add', 'fixture', source.path],
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

  test('trace-dir accumulates an AI adaptation command session', () async {
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

    const traceDir = '.fluoh/traces/adaptation session';
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
    expect(verifyTrace, containsPair('id', 'adaptation-session'));
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
        flutterSideEffects: const {
          'build hap --debug':
              'mkdir -p build/ohos/hap\nprintf "hap" > build/ohos/hap/entry-default-signed.hap',
        },
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

  test(
    'package OHOS run reports hdc connection failure from target discovery',
    () async {
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
        flutterSideEffects: const {
          'build hap --debug':
              'mkdir -p build/ohos/hap\nprintf "hap" > build/ohos/hap/entry-default-signed.hap',
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
      expect(diagnostic, containsPair('code', 'ohos.hdc_connection_failed'));
      expect(
        diagnostic,
        containsPair('nextCommand', 'fluoh doctor --platform ohos --json'),
      );
      final details = diagnostic['details'] as Map<String, Object?>;
      expect(details, containsPair('command', 'hdc list targets'));
      expect(details, containsPair('exitCode', 1));
      expect(details, containsPair('rawExitCode', 0));
      expect(details, containsPair('stderr', 'Connect server failed\n'));
      expect(stderr, isEmpty);
    },
  );

  test('package OHOS run treats hdc install stderr failure as failed', () async {
    final environment = await createTestEnvironment();
    final hdcLog = File('${environment.homeDirectory.path}/hdc.log');
    final devEco = await _writeWorkflowDevEcoFixture(
      environment.homeDirectory,
      hdcLog: hdcLog,
      hdcInstallExitCode: 0,
      hdcInstallStderr: 'Connect server failed\n',
    );
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
      flutterSideEffects: const {
        'build hap --debug':
            'mkdir -p build/ohos/hap\nprintf "hap" > build/ohos/hap/entry-default-signed.hap',
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
    expect(diagnostic, containsPair('code', 'ohos.hdc_connection_failed'));
    expect(
      diagnostic,
      containsPair('nextCommand', 'fluoh doctor --platform ohos --json'),
    );
    final details = diagnostic['details'] as Map<String, Object?>;
    expect(details['command'], contains('hdc -t emulator-5554 install -r'));
    expect(details, containsPair('targetId', 'emulator-5554'));
    expect(details, containsPair('exitCode', 1));
    expect(details, containsPair('rawExitCode', 0));
    expect(details, containsPair('stderr', 'Connect server failed\n'));
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
      flutterSideEffects: const {
        'build hap --debug':
            'mkdir -p build/ohos/hap\nprintf "hap" > build/ohos/hap/entry-default-signed.hap',
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
        ['run', 'ohos', '--log-duration', '0', '--json'],
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
    expect(details, isNot(contains('findings')));
    final launchInfo = details['launchInfo'] as Map<String, Object?>;
    expect(launchInfo, containsPair('bundleName', 'com.example.camera'));
    expect(launchInfo, containsPair('moduleName', 'entry'));
    expect(launchInfo, containsPair('abilityName', 'EntryAbility'));
    expect(stderr, isEmpty);
  });

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
      flutterSideEffects: const {
        'build hap --debug':
            'mkdir -p build/ohos/hap\nprintf "hap" > build/ohos/hap/entry-default-signed.hap',
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
      'assertLog',
      'assertSession',
    ]);
    final waitAction = actions.singleWhere(
      (action) => action['action'] == 'wait',
    );
    expect(waitAction['details'], containsPair('waitSeconds', 0));
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
    expect(stderr, isEmpty);
  });

  test('package OHOS run failure preserves auto emulator next command', () async {
    final environment = await createTestEnvironment();
    final hdcLog = File('${environment.homeDirectory.path}/hdc.log');
    final devEco = await _writeWorkflowDevEcoFixture(
      environment.homeDirectory,
      hdcLog: hdcLog,
    );
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
      flutterSideEffects: const {
        'build hap --debug':
            'mkdir -p build/ohos/hap\nprintf "hap" > build/ohos/hap/entry-default-signed.hap',
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
    expect(diagnostic, containsPair('code', 'ohos.install_failed'));
    expect(
      diagnostic,
      containsPair(
        'nextCommand',
        'fluoh run ohos --package camera --auto-emulator --json',
      ),
    );
    expect(stderr, isEmpty);
  });

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

  test('project OHOS run uses the signed HAP workflow', () async {
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
          containsPair('name', 'ohos-auto-sign'),
          containsPair('status', 'failed'),
        ),
      ),
    );
    final autoSignStep = steps.cast<Map<String, Object?>>().singleWhere(
      (step) => step['name'] == 'ohos-auto-sign',
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

  test('project OHOS run ignores stale HAP artifacts', () async {
    final environment = await createTestEnvironment();
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
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
      1,
    );

    expect(await hdcLog.exists(), isFalse);
    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('ok', false));
    final targets = report['targets'] as List<Object?>;
    final target = targets.single as Map<String, Object?>;
    expect(target, containsPair('phase', 'run-ohos'));
    final steps = target['steps'] as List<Object?>;
    final runStep = steps.cast<Map<String, Object?>>().singleWhere(
      (step) => step['name'] == 'project-run-ohos',
      orElse: () => fail('Missing project-run-ohos step: ${jsonEncode(steps)}'),
    );
    expect(runStep, containsPair('status', 'failed'));
    final diagnostics = runStep['diagnostics'] as List<Object?>;
    final diagnostic = diagnostics.single as Map<String, Object?>;
    expect(diagnostic, containsPair('code', 'ohos.no_installable_hap'));
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
      ['source', 'add', 'fixture', source.path],
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
        ['source', 'add', 'fixture', source.path],
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
      ['source', 'add', 'fixture', source.path],
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
      ['source', 'add', 'fixture', source.path],
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
        ['source', 'add', 'fixture', source.path],
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
        ['source', 'add', 'fixture', source.path],
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
      ['source', 'add', 'fixture', source.path],
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

  test('project run web auto emulator prefers web-server target', () async {
    final environment = await createTestEnvironment();
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
      flutterStdout: const {
        'devices --machine':
            '[{"id":"chrome","name":"Chrome","targetPlatform":"web-javascript","isSupported":true},{"id":"web-server","name":"Web Server","targetPlatform":"web-javascript","isSupported":true}]',
        'run -d web-server --debug --no-pub':
            'Flutter run key commands.\\nApplication running.',
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
      contains('$root::flutter run -d web-server --debug --no-pub'),
    );
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
        ['source', 'add', 'fixture', source.path],
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
        containsPair(
          'nextCommand',
          'fluoh run web --device-id web-server --json',
        ),
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
      startsWith('${environment.homeDirectory.path}/cache/package-runs/'),
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

  test('drive dry-run plans mobile emulator evidence', () async {
    final environment = await createTestEnvironment();
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        [
          'drive',
          'all',
          '--package',
          'camera',
          '--trace-dir',
          '.fluoh/traces/camera/mobile',
          '--dry-run',
          '--json',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('schema', 1));
    expect(report, containsPair('command', 'drive'));
    expect(report, containsPair('ok', true));
    final automation = report['automation'] as Map<String, Object?>;
    expect(automation, containsPair('kind', 'fluoh.mobileAutomation'));
    expect(automation['platforms'], ['ohos', 'android', 'ios']);
    expect(
      automation,
      containsPair(
        'sessionDirectory',
        '${environment.workingDirectory.path}/.fluoh/run-sessions/automation',
      ),
    );
    expect(
      automation,
      containsPair(
        'inspiredBy',
        containsPair('url', 'https://github.com/callstack/agent-device'),
      ),
    );
    final coveragePolicy = automation['coveragePolicy'] as Map<String, Object?>;
    expect(coveragePolicy, containsPair('status', 'needsInteractionInventory'));
    expect(coveragePolicy, containsPair('readyForAutomation', false));
    expect(
      coveragePolicy['qualityGateSummary'],
      allOf(
        containsPair('total', greaterThan(0)),
        containsPair('notReady', isNotEmpty),
      ),
    );
    final recommendation =
        automation['deliveryRecommendation'] as Map<String, Object?>;
    expect(recommendation, containsPair('status', 'needsCoverageReview'));
    expect(
      recommendation['targetSummary'],
      allOf(containsPair('executed', false), containsPair('dryRun', true)),
    );
    final repairQueue = (automation['repairQueue'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final rerunCommand = automation['rerunCommand'] as String;
    expect(
      rerunCommand,
      allOf(
        contains('fluoh drive all --package camera'),
        contains('--trace-dir .fluoh/traces/camera/mobile'),
        contains('--dry-run --json'),
      ),
    );
    final repairPlan = automation['repairPlan'] as Map<String, Object?>;
    expect(repairPlan, containsPair('status', 'needsCoverageReview'));
    expect(repairPlan, containsPair('queueLength', repairQueue.length));
    expect(
      repairPlan['nextStep'],
      allOf(
        containsPair('kind', 'completeCoverageGate'),
        containsPair('sourceType', 'coverage'),
        containsPair('gate', 'coverage-inventory'),
        containsPair(
          'doneWhen',
          contains('quality gate coverage-inventory reports readyForReview'),
        ),
        containsPair(
          'validation',
          allOf(
            containsPair('kind', 'sameDriveCommand'),
            containsPair('command', rerunCommand),
          ),
        ),
      ),
    );
    expect(
      repairQueue,
      contains(
        allOf(
          containsPair('type', 'coverage'),
          containsPair('gate', 'coverage-inventory'),
          containsPair('status', 'needsInventory'),
        ),
      ),
    );
    expect(
      coveragePolicy['capabilityCoverageGuidance'],
      contains('package capability inventory'),
    );
    expect(coveragePolicy['coverageSummary'], containsPair('itemCount', 0));
    final qualityGates = coveragePolicy['qualityGates'] as List<Object?>;
    expect(
      qualityGates,
      contains(
        allOf(
          containsPair('id', 'coverage-inventory'),
          containsPair('status', 'needsInventory'),
        ),
      ),
    );
    final repairLoop = coveragePolicy['repairLoop'] as Map<String, Object?>;
    expect(
      repairLoop['steps'],
      contains(
        allOf(
          containsPair('id', 'rerun-same-command'),
          containsPair('action', contains('Rerun the exact nextCommand')),
        ),
      ),
    );
    final minimumGates = coveragePolicy['minimumGates'] as List<Object?>;
    expect(
      minimumGates,
      contains(
        allOf(
          containsPair('id', 'permission-matrix'),
          containsPair(
            'rule',
            contains('Cover every declared or requestable permission'),
          ),
        ),
      ),
    );
    final checks = automation['checks'] as List<Object?>;
    expect(
      checks,
      contains(
        allOf(
          containsPair('platform', 'ohos'),
          containsPair(
            'command',
            contains('fluoh run ohos --package camera --auto-emulator'),
          ),
          containsPair(
            'driver',
            allOf(
              containsPair('platform', 'ohos'),
              containsPair('supportedActions', contains('assertSession')),
              containsPair('supportedActions', contains('inputText')),
              containsPair('evidenceMethods', contains('OHOS hilog')),
            ),
          ),
        ),
      ),
    );
    expect(
      checks,
      contains(
        allOf(
          containsPair('platform', 'android'),
          containsPair(
            'driver',
            allOf(
              containsPair('platform', 'android'),
              containsPair('supportedActions', contains('tapText')),
              containsPair(
                'evidenceMethods',
                contains('flutterRunSession JSON'),
              ),
            ),
          ),
          containsPair(
            'sessionFile',
            '${environment.workingDirectory.path}/.fluoh/run-sessions/automation/camera-android-session.json',
          ),
        ),
      ),
    );
    expect(
      checks,
      contains(
        allOf(
          containsPair('platform', 'ios'),
          containsPair(
            'sessionFile',
            '${environment.workingDirectory.path}/.fluoh/run-sessions/automation/camera-ios-session.json',
          ),
        ),
      ),
    );
    expect(report['targets'], isEmpty);
    expect(stderr, isEmpty);
  });

  test('drive dry-run asks execution after coverage gates are ready', () async {
    final environment = await createTestEnvironment();
    await _writePackageManifest(environment.workingDirectory);
    await _writeFlutterPackage(environment.workingDirectory);
    final scenario = File(
      '${environment.workingDirectory.path}/.fluoh/scenarios/camera/android-public-api.md',
    );
    await scenario.parent.create(recursive: true);
    await scenario.writeAsString('''
kind: fluoh.automationScenario
schema: 1
name: android public api ready
platform: android
coverage:
  - category: publicApi
    item: camera
    path: success
  - category: publicApi
    item: camera
    path: error
steps:
  - action: assertLog
    contains: camera-ok
''');
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        [
          'drive',
          'android',
          '--package',
          'camera',
          '--scenario',
          scenario.path,
          '--dry-run',
          '--json',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('ok', true));
    final automation = report['automation'] as Map<String, Object?>;
    final recommendation =
        automation['deliveryRecommendation'] as Map<String, Object?>;
    expect(recommendation, containsPair('status', 'needsExecution'));
    expect(recommendation, containsPair('ready', false));
    expect(
      recommendation['targetSummary'],
      allOf(containsPair('executed', false), containsPair('dryRun', true)),
    );
    final repairQueue = (automation['repairQueue'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(repairQueue, hasLength(1));
    expect(repairQueue.single, containsPair('type', 'execution'));
    final repairPlan = automation['repairPlan'] as Map<String, Object?>;
    expect(repairPlan, containsPair('status', 'needsExecution'));
    expect(repairPlan, containsPair('queueLength', 1));
    expect(
      repairPlan['nextStep'],
      allOf(
        containsPair('kind', 'executeAutomation'),
        containsPair('sourceType', 'execution'),
        containsPair('nextCommands', isA<List<Object?>>()),
        containsPair(
          'doneWhen',
          contains('the planned automation command exits successfully'),
        ),
        containsPair('validation', containsPair('kind', 'commands')),
      ),
    );
    final nextCommands = (repairQueue.single['nextCommands'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final executionCommand = nextCommands.single['command'] as String;
    expect(
      nextCommands.single,
      allOf(
        containsPair(
          'command',
          contains('fluoh drive android --package camera'),
        ),
        containsPair('command', contains('--scenario ${scenario.path}')),
        containsPair('command', contains('--json')),
      ),
    );
    expect(executionCommand, isNot(contains('fluoh run android')));
    expect(executionCommand, isNot(contains('--dry-run')));
    final coveragePolicy = automation['coveragePolicy'] as Map<String, Object?>;
    expect(coveragePolicy, containsPair('status', 'readyForExecution'));
    expect(coveragePolicy, containsPair('readyForAutomation', true));
    expect(
      coveragePolicy['qualityGateSummary'],
      allOf(
        containsPair('total', greaterThan(0)),
        containsPair('ready', greaterThan(0)),
        containsPair('notReady', isEmpty),
      ),
    );
    final qualityGates = (coveragePolicy['qualityGates'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(
      qualityGates,
      everyElement(containsPair('status', 'readyForReview')),
    );
    expect(report['targets'], isEmpty);
    expect(stderr, isEmpty);
  });

  test('drive dry-run quotes executable plan command arguments', () async {
    final environment = await createTestEnvironment();
    await _writePackageManifest(environment.workingDirectory);
    await _writeFlutterPackage(environment.workingDirectory);
    final scenario = File(
      '${environment.workingDirectory.path}/.fluoh/scenarios/camera/android-public-api.md',
    );
    await scenario.parent.create(recursive: true);
    await scenario.writeAsString('''
kind: fluoh.automationScenario
schema: 1
name: android public api ready
platform: android
coverage:
  - category: publicApi
    item: camera
    path: success
  - category: publicApi
    item: camera
    path: error
steps:
  - action: assertLog
    contains: camera-ok
''');
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        [
          'drive',
          'android',
          '--package',
          'camera',
          '--emulator',
          'Pixel 35',
          '--session-dir',
          '.fluoh/run sessions/automation state',
          '--trace-dir',
          '.fluoh/traces/camera mobile',
          '--scenario',
          scenario.path,
          '--dry-run',
          '--json',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    final automation = report['automation'] as Map<String, Object?>;
    final checks = (automation['checks'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final command = checks.single['command'] as String;
    expect(command, contains("--emulator 'Pixel 35'"));
    expect(
      command,
      contains(
        "--session-file '${environment.workingDirectory.path}/.fluoh/run sessions/automation state/camera-android-session.json'",
      ),
    );
    expect(command, contains("--trace-dir '.fluoh/traces/camera mobile'"));
    expect(stderr, isEmpty);
  });

  test('drive dry-run routes blocked coverage to maintainer decision', () async {
    final environment = await createTestEnvironment();
    await _writePackageManifest(environment.workingDirectory);
    await _writeFlutterPackage(environment.workingDirectory);
    final scenario = File(
      '${environment.workingDirectory.path}/.fluoh/scenarios/camera/android-blocked-api.md',
    );
    await scenario.parent.create(recursive: true);
    await scenario.writeAsString('''
kind: fluoh.automationScenario
schema: 1
name: android blocked public api
platform: android
coverage:
  - category: publicApi
    item: camera
    path: success
    status: blocked
    note: Requires a camera-capable emulator fixture.
  - category: publicApi
    item: camera
    path: error
    status: notApplicable
    reason: The package has no error callback for this fixture.
steps:
  - action: wait
    timeoutSeconds: 0
''');
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        [
          'drive',
          'android',
          '--package',
          'camera',
          '--scenario',
          scenario.path,
          '--dry-run',
          '--json',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('ok', true));
    final automation = report['automation'] as Map<String, Object?>;
    final coveragePolicy = automation['coveragePolicy'] as Map<String, Object?>;
    expect(coveragePolicy, containsPair('status', 'needsMaintainerDecision'));
    expect(coveragePolicy, containsPair('readyForAutomation', false));
    expect(
      coveragePolicy['qualityGateSummary'],
      allOf(
        containsPair('notReady', isEmpty),
        containsPair('ready', greaterThan(0)),
      ),
    );
    final recommendation =
        automation['deliveryRecommendation'] as Map<String, Object?>;
    expect(recommendation, containsPair('status', 'needsMaintainerDecision'));
    expect(
      recommendation,
      containsPair('recommendation', 'needs-maintainer-decision'),
    );
    final repairQueue = (automation['repairQueue'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(repairQueue, hasLength(1));
    expect(
      repairQueue.single,
      allOf(
        containsPair('type', 'coverageBlocked'),
        containsPair('scenario', 'android blocked public api'),
        containsPair('coverage', containsPair('status', 'blocked')),
      ),
    );
    expect(stderr, isEmpty);
  });

  test('drive dry-run inventories package evidence and permissions', () async {
    final environment = await createTestEnvironment();
    await _writePackageManifest(environment.workingDirectory);
    await _writeFlutterPackage(environment.workingDirectory);
    await _writeFlutterExample(
      Directory('${environment.workingDirectory.path}/example'),
    );
    final androidManifest = File(
      '${environment.workingDirectory.path}/example/android/app/src/main/AndroidManifest.xml',
    );
    await androidManifest.parent.create(recursive: true);
    await androidManifest.writeAsString('''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
  <uses-permission android:name="android.permission.CAMERA" />
</manifest>
''');
    final iosInfoPlist = File(
      '${environment.workingDirectory.path}/example/ios/Runner/Info.plist',
    );
    await iosInfoPlist.parent.create(recursive: true);
    await iosInfoPlist.writeAsString('''
<plist version="1.0">
<dict>
  <key>NSCameraUsageDescription</key>
  <string>Camera access is required.</string>
  <key>NSUserTrackingUsageDescription</key>
  <string>Tracking access is required.</string>
</dict>
</plist>
''');
    final ohosModule = File(
      '${environment.workingDirectory.path}/example/ohos/entry/src/main/module.json5',
    );
    await ohosModule.parent.create(recursive: true);
    await ohosModule.writeAsString('''
{
  module: {
    requestPermissions: [
      { name: "ohos.permission.CAMERA" }
    ]
  }
}
''');
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['drive', 'android', '--package', 'camera', '--dry-run', '--json'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('ok', true));
    final automation = report['automation'] as Map<String, Object?>;
    final coveragePolicy = automation['coveragePolicy'] as Map<String, Object?>;
    final inventory = coveragePolicy['inventory'] as Map<String, Object?>;
    expect(inventory, containsPair('status', 'ready'));
    expect(inventory, containsPair('targetKind', 'package'));
    expect(inventory, containsPair('targetName', 'camera'));
    final tests = inventory['tests'] as Map<String, Object?>;
    expect(tests, containsPair('publicLibraryFiles', 1));
    expect(tests, containsPair('packageTestFiles', 1));
    expect(tests, containsPair('exampleTestFiles', 1));
    expect(tests, containsPair('totalTestFiles', 2));
    expect(
      tests['coverageBaseline'],
      allOf(
        containsPair('status', 'readyForReview'),
        containsPair('missingPackageTestFiles', 0),
      ),
    );
    final platforms = (inventory['platforms'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(
      platforms,
      contains(
        allOf(
          containsPair('platform', 'android'),
          containsPair('exampleDirectoryExists', true),
        ),
      ),
    );
    expect(
      platforms,
      contains(
        allOf(
          containsPair('platform', 'ios'),
          containsPair('exampleDirectoryExists', true),
        ),
      ),
    );
    expect(
      platforms,
      contains(
        allOf(
          containsPair('platform', 'ohos'),
          containsPair('exampleDirectoryExists', true),
        ),
      ),
    );
    final capabilities = (inventory['capabilities'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(
      capabilities,
      contains(
        allOf(
          containsPair('category', 'publicApi'),
          containsPair('item', 'camera'),
          containsPair('coverageItem', 'camera'),
          containsPair('source', 'publicLibrary'),
        ),
      ),
    );
    final permissions = (inventory['manifestPermissions'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(
      permissions,
      contains(
        allOf(
          containsPair('platform', 'android'),
          containsPair('name', 'android.permission.CAMERA'),
          containsPair('coverageItem', 'camera'),
        ),
      ),
    );
    expect(
      permissions,
      contains(
        allOf(
          containsPair('platform', 'ios'),
          containsPair('name', 'NSCameraUsageDescription'),
          containsPair('coverageItem', 'camera'),
        ),
      ),
    );
    expect(
      permissions,
      contains(
        allOf(
          containsPair('platform', 'ios'),
          containsPair('name', 'NSUserTrackingUsageDescription'),
          containsPair('coverageItem', 'appTrackingTransparency'),
        ),
      ),
    );
    expect(
      permissions,
      contains(
        allOf(
          containsPair('platform', 'ohos'),
          containsPair('name', 'ohos.permission.CAMERA'),
          containsPair('coverageItem', 'camera'),
        ),
      ),
    );
    final qualityGates = coveragePolicy['qualityGates'] as List<Object?>;
    expect(
      qualityGates,
      contains(
        allOf(
          containsPair('id', 'existing-test-baseline'),
          containsPair('status', 'readyForReview'),
        ),
      ),
    );
    expect(
      qualityGates,
      contains(
        allOf(
          containsPair('id', 'capability-inventory-coverage'),
          containsPair('status', 'needsCapabilityCoverageRows'),
          containsPair('capabilities', isA<List<Object?>>()),
          containsPair('missingCapabilities', isA<List<Object?>>()),
        ),
      ),
    );
    expect(
      qualityGates,
      contains(
        allOf(
          containsPair('id', 'manifest-permission-coverage'),
          containsPair('status', 'needsPermissionCoverageRows'),
          containsPair('permissions', isA<List<Object?>>()),
        ),
      ),
    );
    expect(stderr, isEmpty);
  });

  test('drive dry-run flags low package test coverage baseline', () async {
    final environment = await createTestEnvironment();
    await _writePackageManifest(environment.workingDirectory);
    await _writeFlutterPackage(environment.workingDirectory);
    await _writeFlutterExample(
      Directory('${environment.workingDirectory.path}/example'),
    );
    await File(
      '${environment.workingDirectory.path}/lib/camera_controller.dart',
    ).writeAsString('class CameraControllerFixture {}\n');
    await File(
      '${environment.workingDirectory.path}/lib/camera_platform.dart',
    ).writeAsString('class CameraPlatformFixture {}\n');
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['drive', 'android', '--package', 'camera', '--dry-run', '--json'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('ok', true));
    final automation = report['automation'] as Map<String, Object?>;
    final coveragePolicy = automation['coveragePolicy'] as Map<String, Object?>;
    final inventory = coveragePolicy['inventory'] as Map<String, Object?>;
    final tests = inventory['tests'] as Map<String, Object?>;
    expect(tests, containsPair('publicLibraryFiles', 3));
    expect(tests, containsPair('packageTestFiles', 1));
    expect(
      tests['coverageBaseline'],
      allOf(
        containsPair('status', 'needsTestCoverageReview'),
        containsPair('packageTestRunner', 'flutter'),
        containsPair('focusedPackageTestCommandPattern', 'flutter test <path>'),
        containsPair('minimumPackageTestFiles', 3),
        containsPair('missingPackageTestFiles', 2),
        containsPair('missingPackageTests', hasLength(2)),
      ),
    );
    final baseline = tests['coverageBaseline'] as Map<String, Object?>;
    final missingPackageTests =
        (baseline['missingPackageTests'] as List<Object?>)
            .cast<Map<String, Object?>>();
    expect(
      missingPackageTests,
      contains(
        allOf(
          containsPair('libraryPath', endsWith('/lib/camera_controller.dart')),
          containsPair(
            'expectedTestPath',
            endsWith('/test/camera_controller_test.dart'),
          ),
          containsPair(
            'testCommand',
            allOf(
              startsWith('flutter test '),
              contains('/test/camera_controller_test.dart'),
            ),
          ),
        ),
      ),
    );
    expect(
      missingPackageTests,
      contains(
        allOf(
          containsPair('libraryPath', endsWith('/lib/camera_platform.dart')),
          containsPair(
            'expectedTestPath',
            endsWith('/test/camera_platform_test.dart'),
          ),
        ),
      ),
    );
    expect(
      missingPackageTests.first['acceptedTestPaths'],
      isA<List<Object?>>(),
    );
    expect(
      inventory['warnings'],
      contains(
        'Package tests appear lower than the public library surface; inspect coverage before reporting ready.',
      ),
    );
    final qualityGates = (coveragePolicy['qualityGates'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final testGate = qualityGates.singleWhere(
      (gate) => gate['id'] == 'existing-test-baseline',
    );
    expect(testGate, containsPair('status', 'needsTestCoverageReview'));
    expect(
      testGate['baseline'],
      allOf(
        containsPair('publicLibraryFiles', 3),
        containsPair('missingPackageTestFiles', 2),
        containsPair('missingPackageTests', hasLength(2)),
      ),
    );
    final repairQueue = (automation['repairQueue'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(repairQueue.first['type'], isNot('coverage'));
    expect(
      repairQueue,
      contains(
        allOf(
          containsPair('type', 'testCoverage'),
          containsPair('gate', 'existing-test-baseline'),
          containsPair('libraryPath', endsWith('/lib/camera_controller.dart')),
          containsPair(
            'expectedTestPath',
            endsWith('/test/camera_controller_test.dart'),
          ),
          containsPair(
            'testCommand',
            allOf(
              startsWith('flutter test '),
              contains('/test/camera_controller_test.dart'),
            ),
          ),
          containsPair(
            'nextAction',
            allOf(
              containsPair('kind', 'createOrExpandPackageTest'),
              containsPair(
                'path',
                endsWith('/test/camera_controller_test.dart'),
              ),
              containsPair(
                'testCommand',
                allOf(
                  startsWith('flutter test '),
                  contains('/test/camera_controller_test.dart'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(stderr, isEmpty);
  });

  test('drive dry-run flags weak package tests', () async {
    final environment = await createTestEnvironment();
    await _writePackageManifest(environment.workingDirectory);
    await _writeFlutterPackage(environment.workingDirectory);
    await File(
      '${environment.workingDirectory.path}/lib/camera.dart',
    ).writeAsString('''
class CameraControllerFixture {
  String describe() => 'camera';
}
''');
    await File(
      '${environment.workingDirectory.path}/test/camera_test.dart',
    ).writeAsString('''
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mentions camera fixture name only', () {
    expect('CameraControllerFixture', isNotEmpty);
  });
}
''');
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['drive', 'android', '--package', 'camera', '--dry-run', '--json'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('ok', true));
    final automation = report['automation'] as Map<String, Object?>;
    final coveragePolicy = automation['coveragePolicy'] as Map<String, Object?>;
    final inventory = coveragePolicy['inventory'] as Map<String, Object?>;
    final tests = inventory['tests'] as Map<String, Object?>;
    final baseline = tests['coverageBaseline'] as Map<String, Object?>;
    expect(
      baseline,
      allOf(
        containsPair('status', 'needsTestCoverageReview'),
        containsPair('missingPackageTestFiles', 0),
        containsPair('weakPackageTestFiles', 1),
        containsPair('weakPackageTests', hasLength(1)),
      ),
    );
    final weakPackageTests = (baseline['weakPackageTests'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(
      weakPackageTests.single,
      allOf(
        containsPair('libraryPath', endsWith('/lib/camera.dart')),
        containsPair('testPath', endsWith('/test/camera_test.dart')),
        containsPair('publicDeclarations', contains('CameraControllerFixture')),
        containsPair(
          'missingDeclarations',
          contains('CameraControllerFixture'),
        ),
        containsPair(
          'testCommand',
          allOf(
            startsWith('flutter test '),
            contains('/test/camera_test.dart'),
          ),
        ),
      ),
    );
    final repairQueue = (automation['repairQueue'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(
      repairQueue,
      contains(
        allOf(
          containsPair('type', 'testCoverage'),
          containsPair('gate', 'existing-test-baseline'),
          containsPair('libraryPath', endsWith('/lib/camera.dart')),
          containsPair('testPath', endsWith('/test/camera_test.dart')),
          containsPair(
            'nextAction',
            allOf(
              containsPair('kind', 'expandPackageTest'),
              containsPair('path', endsWith('/test/camera_test.dart')),
              containsPair(
                'publicDeclarations',
                contains('CameraControllerFixture'),
              ),
              containsPair(
                'missingDeclarations',
                contains('CameraControllerFixture'),
              ),
            ),
          ),
        ),
      ),
    );
    expect(stderr, isEmpty);
  });

  test(
    'drive dry-run accepts tests that exercise public declarations',
    () async {
      final environment = await createTestEnvironment();
      await _writePackageManifest(environment.workingDirectory);
      await _writeFlutterPackage(environment.workingDirectory);
      await File(
        '${environment.workingDirectory.path}/lib/camera.dart',
      ).writeAsString('''
class CameraControllerFixture {
  String describe() => 'camera';
}
''');
      await File(
        '${environment.workingDirectory.path}/test/camera_test.dart',
      ).writeAsString('''
import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('camera fixture behavior', () {
    expect(CameraControllerFixture().describe(), 'camera');
  });
}
''');
      final stdout = <String>[];
      final stderr = <String>[];

      expect(
        await runFluoh(
          ['drive', 'android', '--package', 'camera', '--dry-run', '--json'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final report = jsonDecode(stdout.single) as Map<String, Object?>;
      expect(report, containsPair('ok', true));
      final automation = report['automation'] as Map<String, Object?>;
      final coveragePolicy =
          automation['coveragePolicy'] as Map<String, Object?>;
      final inventory = coveragePolicy['inventory'] as Map<String, Object?>;
      final tests = inventory['tests'] as Map<String, Object?>;
      final baseline = tests['coverageBaseline'] as Map<String, Object?>;
      expect(
        baseline,
        allOf(
          containsPair('status', 'readyForReview'),
          containsPair('missingPackageTestFiles', 0),
          containsPair('weakPackageTestFiles', 0),
          isNot(contains('weakPackageTests')),
        ),
      );
      final qualityGates = (coveragePolicy['qualityGates'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(
        qualityGates.singleWhere(
          (gate) => gate['id'] == 'existing-test-baseline',
        ),
        containsPair('status', 'readyForReview'),
      );
      final repairQueue = (automation['repairQueue'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(
        repairQueue.where((item) => item['type'] == 'testCoverage'),
        isEmpty,
      );
      expect(stderr, isEmpty);
    },
  );

  test('drive dry-run flags untested public declarations', () async {
    final environment = await createTestEnvironment();
    await _writePackageManifest(environment.workingDirectory);
    await _writeFlutterPackage(environment.workingDirectory);
    await File(
      '${environment.workingDirectory.path}/lib/camera.dart',
    ).writeAsString('''
class CameraControllerFixture {
  String describe() => 'camera';
}

class CameraPermissionFixture {
  bool get isGranted => true;
}
''');
    await File(
      '${environment.workingDirectory.path}/test/camera_test.dart',
    ).writeAsString('''
import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('camera fixture behavior', () {
    expect(CameraControllerFixture().describe(), 'camera');
  });
}
''');
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['drive', 'android', '--package', 'camera', '--dry-run', '--json'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('ok', true));
    final automation = report['automation'] as Map<String, Object?>;
    final coveragePolicy = automation['coveragePolicy'] as Map<String, Object?>;
    final inventory = coveragePolicy['inventory'] as Map<String, Object?>;
    final tests = inventory['tests'] as Map<String, Object?>;
    final baseline = tests['coverageBaseline'] as Map<String, Object?>;
    expect(
      baseline,
      allOf(
        containsPair('status', 'needsTestCoverageReview'),
        containsPair('weakPackageTestFiles', 1),
        containsPair('weakPackageTests', hasLength(1)),
      ),
    );
    final weakPackageTests = (baseline['weakPackageTests'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(
      weakPackageTests.single,
      allOf(
        containsPair('libraryPath', endsWith('/lib/camera.dart')),
        containsPair('publicDeclarationCount', 2),
        containsPair('exercisedDeclarationCount', 1),
        containsPair('missingDeclarationCount', 1),
        containsPair(
          'exercisedDeclarations',
          contains('CameraControllerFixture'),
        ),
        containsPair(
          'missingDeclarations',
          contains('CameraPermissionFixture'),
        ),
      ),
    );
    final repairQueue = (automation['repairQueue'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(
      repairQueue,
      contains(
        allOf(
          containsPair('type', 'testCoverage'),
          containsPair('testPath', endsWith('/test/camera_test.dart')),
          containsPair(
            'missingDeclarations',
            contains('CameraPermissionFixture'),
          ),
          containsPair(
            'nextAction',
            allOf(
              containsPair('kind', 'expandPackageTest'),
              containsPair(
                'publicDeclarations',
                contains('CameraPermissionFixture'),
              ),
              containsPair(
                'missingDeclarations',
                contains('CameraPermissionFixture'),
              ),
            ),
          ),
        ),
      ),
    );
    expect(stderr, isEmpty);
  });

  test(
    'drive dry-run prints dart package test command for coverage repair',
    () async {
      final environment = await createTestEnvironment();
      await _writePackageManifest(environment.workingDirectory);
      await _writeDartPackage(environment.workingDirectory);
      await File(
        '${environment.workingDirectory.path}/lib/camera_controller.dart',
      ).writeAsString('class CameraControllerFixture {}\n');
      final scenario = File(
        '${environment.workingDirectory.path}/.fluoh/scenarios/camera/android-api.md',
      );
      await scenario.parent.create(recursive: true);
      await scenario.writeAsString('''
kind: fluoh.automationScenario
schema: 1
name: android api coverage
platform: android
coverage:
  - category: publicApi
    item: camera
    path: success
  - category: publicApi
    item: camera
    path: error
  - category: publicApi
    item: CameraControllerFixture
    path: success
  - category: publicApi
    item: CameraControllerFixture
    path: error
steps:
  - action: assertLog
    contains: camera-api-ok
''');
      final stdout = <String>[];
      final stderr = <String>[];

      expect(
        await runFluoh(
          [
            'drive',
            'android',
            '--package',
            'camera',
            '--scenario',
            scenario.path,
            '--dry-run',
            '--json',
          ],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final report = jsonDecode(stdout.single) as Map<String, Object?>;
      expect(report, containsPair('ok', true));
      final automation = report['automation'] as Map<String, Object?>;
      final coveragePolicy =
          automation['coveragePolicy'] as Map<String, Object?>;
      final inventory = coveragePolicy['inventory'] as Map<String, Object?>;
      final tests = inventory['tests'] as Map<String, Object?>;
      final baseline = tests['coverageBaseline'] as Map<String, Object?>;
      expect(tests, containsPair('packageTestRunner', 'dart'));
      expect(
        baseline,
        allOf(
          containsPair('status', 'needsTestCoverageReview'),
          containsPair('packageTestRunner', 'dart'),
          containsPair('focusedPackageTestCommandPattern', 'dart test <path>'),
        ),
      );
      final missingPackageTests =
          (baseline['missingPackageTests'] as List<Object?>)
              .cast<Map<String, Object?>>();
      expect(
        missingPackageTests.single,
        allOf(
          containsPair('libraryPath', endsWith('/lib/camera_controller.dart')),
          containsPair(
            'expectedTestPath',
            endsWith('/test/camera_controller_test.dart'),
          ),
          containsPair(
            'testCommand',
            allOf(
              startsWith('dart test '),
              contains('/test/camera_controller_test.dart'),
            ),
          ),
          containsPair('acceptedTestCommands', isA<List<Object?>>()),
        ),
      );
      final repairQueue = (automation['repairQueue'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(
        repairQueue.first,
        allOf(
          containsPair('type', 'testCoverage'),
          containsPair('gate', 'existing-test-baseline'),
          containsPair(
            'testCommand',
            allOf(
              startsWith('dart test '),
              contains('/test/camera_controller_test.dart'),
            ),
          ),
          containsPair(
            'nextAction',
            allOf(
              containsPair('kind', 'createOrExpandPackageTest'),
              containsPair(
                'testCommand',
                allOf(
                  startsWith('dart test '),
                  contains('/test/camera_controller_test.dart'),
                ),
              ),
            ),
          ),
        ),
      );
      final repairPlan = automation['repairPlan'] as Map<String, Object?>;
      final rerunCommand = automation['rerunCommand'] as String;
      expect(
        repairPlan['nextStep'],
        allOf(
          containsPair('kind', 'createOrExpandPackageTest'),
          containsPair('sourceType', 'testCoverage'),
          containsPair(
            'validation',
            allOf(
              containsPair('kind', 'packageTestsThenDrive'),
              containsPair(
                'testCommand',
                allOf(
                  startsWith('dart test '),
                  contains('/test/camera_controller_test.dart'),
                ),
              ),
              containsPair('driveCommand', rerunCommand),
              containsPair('commands', contains(rerunCommand)),
            ),
          ),
        ),
      );
      expect(stderr, isEmpty);
    },
  );

  test('drive dry-run reports generic package capability gaps', () async {
    final environment = await createTestEnvironment();
    await File('${environment.workingDirectory.path}/fluoh.yaml').writeAsString(
      '''
schema: 1
kind: package

sdk:
  version: 3.35.8-ohos-0.0.3

repository:
  git:
    url: git@github.com:FlutterOH/sample_tool.git
    branch: ohos/3.35/sample_tool

upstream:
  git:
    url: https://github.com/example/sample_tool.git
    branch: main

package:
  name: sample_tool
  path: .
  release:
    version: 0.1.0
    upstream:
      version: 1.0.0
      commit: "1111111111111111111111111111111111111111"
    status: experimental
''',
    );
    await File(
      '${environment.workingDirectory.path}/pubspec.yaml',
    ).writeAsString('''
name: sample_tool
version: 1.0.0

environment:
  sdk: ^3.0.0

dependencies:
  flutter:
    sdk: flutter

dev_dependencies:
  flutter_test:
    sdk: flutter
''');
    await Directory(
      '${environment.workingDirectory.path}/lib/src',
    ).create(recursive: true);
    await File(
      '${environment.workingDirectory.path}/lib/sample_tool.dart',
    ).writeAsString('''
export 'src/exported_tool.dart';

class SampleTool {}

Future<String> formatSample(String value) async => value;

String get sampleVersion => '1.0.0';

const sampleLimit = 10;
''');
    await File(
      '${environment.workingDirectory.path}/lib/src/exported_tool.dart',
    ).writeAsString('''
class ExportedTool {}
''');
    await File(
      '${environment.workingDirectory.path}/lib/src/sample_channel.dart',
    ).writeAsString('''
import 'package:flutter/services.dart';

class SampleChannel {
  Future<void> open() {
    return const MethodChannel('sample_tool').invokeMethod('openPicker');
  }

  Stream<dynamic> events() {
    return const EventChannel('sample/events').receiveBroadcastStream();
  }

  BasicMessageChannel<String?> messages() {
    return const BasicMessageChannel<String?>('sample/messages', StringCodec());
  }
}
''');
    await Directory(
      '${environment.workingDirectory.path}/example/lib',
    ).create(recursive: true);
    await File(
      '${environment.workingDirectory.path}/example/lib/main.dart',
    ).writeAsString('void main() {}\n');
    final scenario = File(
      '${environment.workingDirectory.path}/.fluoh/scenarios/sample_tool/android-public-api.md',
    );
    await scenario.parent.create(recursive: true);
    await scenario.writeAsString('''
kind: fluoh.automationScenario
schema: 1
name: sample public api
platform: android
coverage:
  - category: publicApi
    item: SampleTool
    path: success
steps:
  - action: assertLog
    contains: sample-ok
''');
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        [
          'drive',
          'android',
          '--package',
          'sample_tool',
          '--scenario',
          scenario.path,
          '--dry-run',
          '--json',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('ok', true));
    final automation = report['automation'] as Map<String, Object?>;
    final coveragePolicy = automation['coveragePolicy'] as Map<String, Object?>;
    final coverageSummary =
        coveragePolicy['coverageSummary'] as Map<String, Object?>;
    expect(coverageSummary, containsPair('capabilityCount', 10));
    expect(coverageSummary, containsPair('capabilityCoverageWarningCount', 9));
    final inventory = coveragePolicy['inventory'] as Map<String, Object?>;
    final capabilities = (inventory['capabilities'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(
      capabilities,
      contains(
        allOf(
          containsPair('category', 'publicApi'),
          containsPair('item', 'SampleTool'),
        ),
      ),
    );
    expect(
      capabilities,
      contains(
        allOf(
          containsPair('category', 'publicApi'),
          containsPair('item', 'ExportedTool'),
          containsPair('path', endsWith('/lib/src/exported_tool.dart')),
        ),
      ),
    );
    expect(
      capabilities,
      contains(
        allOf(
          containsPair('category', 'publicApi'),
          containsPair('item', 'formatSample'),
        ),
      ),
    );
    expect(
      capabilities,
      contains(
        allOf(
          containsPair('category', 'publicApi'),
          containsPair('item', 'sampleVersion'),
        ),
      ),
    );
    expect(
      capabilities,
      contains(
        allOf(
          containsPair('category', 'publicApi'),
          containsPair('item', 'sampleLimit'),
        ),
      ),
    );
    expect(
      capabilities,
      contains(
        allOf(
          containsPair('category', 'methodChannel'),
          containsPair('item', 'openPicker'),
        ),
      ),
    );
    expect(
      capabilities,
      contains(
        allOf(
          containsPair('category', 'platformChannel'),
          containsPair('item', 'sample_tool'),
        ),
      ),
    );
    expect(
      capabilities,
      contains(
        allOf(
          containsPair('category', 'platformChannel'),
          containsPair('item', 'sample/events'),
        ),
      ),
    );
    expect(
      capabilities,
      contains(
        allOf(
          containsPair('category', 'platformChannel'),
          containsPair('item', 'sample/messages'),
        ),
      ),
    );
    expect(
      capabilities,
      contains(
        allOf(
          containsPair('category', 'exampleFlow'),
          containsPair('item', 'main'),
        ),
      ),
    );
    final capabilityCoverage =
        (coveragePolicy['capabilityCoverage'] as List<Object?>)
            .cast<Map<String, Object?>>();
    expect(
      capabilityCoverage,
      contains(
        allOf(
          containsPair('category', 'publicApi'),
          containsPair('item', 'SampleTool'),
          containsPair('status', 'readyForReview'),
        ),
      ),
    );
    final qualityGates = (coveragePolicy['qualityGates'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final capabilityGate = qualityGates.singleWhere(
      (gate) => gate['id'] == 'capability-inventory-coverage',
    );
    expect(
      capabilityGate,
      containsPair('status', 'needsCapabilityCoverageRows'),
    );
    final missingCapabilities =
        (capabilityGate['missingCapabilities'] as List<Object?>)
            .cast<Map<String, Object?>>();
    expect(
      missingCapabilities.map((item) => item['item']),
      containsAll([
        'ExportedTool',
        'formatSample',
        'main',
        'openPicker',
        'sample/events',
        'sample/messages',
        'sampleLimit',
        'sampleVersion',
        'sample_tool',
      ]),
    );
    expect(
      missingCapabilities.first['suggestedCoverage'],
      isA<List<Object?>>(),
    );
    final repairQueue = (automation['repairQueue'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(repairQueue.first, containsPair('type', 'scenarioCoverage'));
    final rerunCommand = automation['rerunCommand'] as String;
    expect(
      rerunCommand,
      allOf(
        contains('fluoh drive android --package sample_tool'),
        contains('--scenario ${scenario.path}'),
        contains('--dry-run --json'),
      ),
    );
    final repairPlan = automation['repairPlan'] as Map<String, Object?>;
    expect(repairPlan, containsPair('status', 'needsCoverageReview'));
    expect(
      repairPlan['nextStep'],
      allOf(
        containsPair('kind', 'addScenarioCoverageRows'),
        containsPair('sourceType', 'scenarioCoverage'),
        containsPair('gate', 'capability-inventory-coverage'),
        containsPair('nextAction', isA<Map<String, Object?>>()),
        containsPair(
          'doneWhen',
          contains(contains('capability coverage reports readyForReview')),
        ),
        containsPair(
          'validation',
          allOf(
            containsPair('kind', 'sameDriveCommand'),
            containsPair('command', rerunCommand),
          ),
        ),
      ),
    );
    expect(
      repairQueue,
      contains(
        allOf(
          containsPair('type', 'scenarioCoverage'),
          containsPair('gate', 'capability-inventory-coverage'),
          containsPair('item', 'openPicker'),
          containsPair(
            'nextAction',
            allOf(
              containsPair('kind', 'addScenarioCoverageRows'),
              containsPair(
                'scenarioCandidates',
                contains(
                  allOf(
                    containsPair('platform', 'android'),
                    containsPair(
                      'path',
                      endsWith(
                        '/.fluoh/scenarios/sample_tool/android-openPicker.md',
                      ),
                    ),
                  ),
                ),
              ),
              containsPair(
                'coverage',
                contains(
                  allOf(
                    containsPair('category', 'methodChannel'),
                    containsPair('item', 'openPicker'),
                    containsPair('path', 'success'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(stderr, isEmpty);
  });

  test('drive dry-run requires every manifest permission row', () async {
    final environment = await createTestEnvironment();
    await _writePackageManifest(environment.workingDirectory);
    await _writeFlutterPackage(environment.workingDirectory);
    await _writeFlutterExample(
      Directory('${environment.workingDirectory.path}/example'),
    );
    final androidManifest = File(
      '${environment.workingDirectory.path}/example/android/app/src/main/AndroidManifest.xml',
    );
    await androidManifest.parent.create(recursive: true);
    await androidManifest.writeAsString('''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
  <uses-permission android:name="android.permission.CAMERA" />
  <uses-permission android:name="android.permission.GET_ACCOUNTS" />
  <uses-permission android:name="android.permission.RECEIVE_MMS" />
  <uses-permission android:name="android.permission.READ_MEDIA_AUDIO" />
  <uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />
  <uses-permission android:name="android.permission.NEARBY_WIFI_DEVICES" />
  <uses-permission android:name="android.permission.RECORD_AUDIO" />
</manifest>
''');
    final scenario = File(
      '${environment.workingDirectory.path}/.fluoh/scenarios/camera/android-camera.md',
    );
    await scenario.parent.create(recursive: true);
    await scenario.writeAsString('''
kind: fluoh.automationScenario
schema: 1
name: android camera only
platform: android
coverage:
  - category: permission
    item: camera
    path: grant
  - category: permission
    item: camera
    path: deny
  - category: permission
    item: contacts
    path: grant
  - category: permission
    item: contacts
    path: deny
  - category: permission
    item: sms
    path: grant
  - category: permission
    item: sms
    path: deny
  - category: permission
    item: audio
    path: grant
  - category: permission
    item: audio
    path: deny
  - category: permission
    item: ignoreBatteryOptimizations
    path: grant
  - category: permission
    item: ignoreBatteryOptimizations
    path: deny
  - category: permission
    item: nearbyWifiDevices
    path: grant
  - category: permission
    item: nearbyWifiDevices
    path: deny
steps:
  - action: wait
    timeoutSeconds: 0
''');
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        [
          'drive',
          'android',
          '--package',
          'camera',
          '--scenario',
          scenario.path,
          '--dry-run',
          '--json',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('ok', true));
    final automation = report['automation'] as Map<String, Object?>;
    final coveragePolicy = automation['coveragePolicy'] as Map<String, Object?>;
    final manifestPermissionCoverage =
        (coveragePolicy['manifestPermissionCoverage'] as List<Object?>)
            .cast<Map<String, Object?>>();
    expect(
      manifestPermissionCoverage,
      contains(
        allOf(
          containsPair('permission', 'android.permission.CAMERA'),
          containsPair('coverageItem', 'camera'),
          containsPair('status', 'readyForReview'),
        ),
      ),
    );
    expect(
      manifestPermissionCoverage,
      contains(
        allOf(
          containsPair('permission', 'android.permission.GET_ACCOUNTS'),
          containsPair('coverageItem', 'contacts'),
          containsPair('status', 'readyForReview'),
        ),
      ),
    );
    expect(
      manifestPermissionCoverage,
      contains(
        allOf(
          containsPair('permission', 'android.permission.RECEIVE_MMS'),
          containsPair('coverageItem', 'sms'),
          containsPair('status', 'readyForReview'),
        ),
      ),
    );
    expect(
      manifestPermissionCoverage,
      contains(
        allOf(
          containsPair('permission', 'android.permission.READ_MEDIA_AUDIO'),
          containsPair('coverageItem', 'audio'),
          containsPair('status', 'readyForReview'),
        ),
      ),
    );
    expect(
      manifestPermissionCoverage,
      contains(
        allOf(
          containsPair(
            'permission',
            'android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
          ),
          containsPair('coverageItem', 'ignoreBatteryOptimizations'),
          containsPair('status', 'readyForReview'),
        ),
      ),
    );
    expect(
      manifestPermissionCoverage,
      contains(
        allOf(
          containsPair('permission', 'android.permission.NEARBY_WIFI_DEVICES'),
          containsPair('coverageItem', 'nearbyWifiDevices'),
          containsPair('status', 'readyForReview'),
        ),
      ),
    );
    expect(
      manifestPermissionCoverage,
      contains(
        allOf(
          containsPair('permission', 'android.permission.RECORD_AUDIO'),
          containsPair('coverageItem', 'microphone'),
          containsPair('status', 'needsPermissionCoverageRows'),
          containsPair('needsPositivePath', true),
          containsPair('needsNegativeOrErrorPath', true),
        ),
      ),
    );
    final qualityGates = coveragePolicy['qualityGates'] as List<Object?>;
    final permissionGate = qualityGates
        .cast<Map<String, Object?>>()
        .singleWhere((gate) => gate['id'] == 'manifest-permission-coverage');
    expect(
      permissionGate,
      containsPair('status', 'needsPermissionCoverageRows'),
    );
    final missingPermissions =
        (permissionGate['missingPermissions'] as List<Object?>)
            .cast<Map<String, Object?>>();
    expect(missingPermissions, hasLength(1));
    expect(
      missingPermissions.single,
      allOf(
        containsPair('permission', 'android.permission.RECORD_AUDIO'),
        containsPair('coverageItem', 'microphone'),
      ),
    );
    expect(
      missingPermissions.single['suggestedCoverage'],
      contains(
        allOf(
          containsPair('category', 'permission'),
          containsPair('item', 'microphone'),
          containsPair('path', 'grant'),
        ),
      ),
    );
    final repairQueue = (automation['repairQueue'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(repairQueue.first['type'], isNot('coverage'));
    expect(
      repairQueue,
      contains(
        allOf(
          containsPair('type', 'permissionCoverage'),
          containsPair('gate', 'manifest-permission-coverage'),
          containsPair('platform', 'android'),
          containsPair('permission', 'android.permission.RECORD_AUDIO'),
          containsPair('coverageItem', 'microphone'),
          containsPair(
            'nextAction',
            allOf(
              containsPair('kind', 'addScenarioCoverageRows'),
              containsPair('platform', 'android'),
              containsPair(
                'path',
                endsWith('/.fluoh/scenarios/camera/android-microphone.md'),
              ),
              containsPair(
                'scenarioCandidates',
                contains(
                  allOf(
                    containsPair('platform', 'android'),
                    containsPair(
                      'path',
                      endsWith(
                        '/.fluoh/scenarios/camera/android-microphone.md',
                      ),
                    ),
                  ),
                ),
              ),
              containsPair(
                'coverage',
                contains(
                  allOf(
                    containsPair('category', 'permission'),
                    containsPair('item', 'microphone'),
                    containsPair('path', 'deny'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(stderr, isEmpty);
  });

  test('drive dry-run reports scenario coverage matrix', () async {
    final environment = await createTestEnvironment();
    final scenarioDirectory = Directory(
      '${environment.workingDirectory.path}/.fluoh/scenarios/sample_permissions',
    );
    await scenarioDirectory.create(recursive: true);
    final cameraScenario = File('${scenarioDirectory.path}/android-camera.md');
    await cameraScenario.writeAsString('''
kind: fluoh.automationScenario
schema: 1
name: android camera permission matrix
platform: android
coverage:
  - category: permission
    item: camera
    path: grant
  - category: permission
    item: camera
    path: deny
steps:
  - action: wait
    timeoutSeconds: 0
''');
    final mediaScenario = File('${scenarioDirectory.path}/android-media.md');
    await mediaScenario.writeAsString('''
kind: fluoh.automationScenario
schema: 1
name: android media permission matrix
platform: android
coverage:
  items:
    - category: permission
      item: photos
      path: grant
    - category: permission
      item: locationWhenInUse
      path: grant
      status: blocked
      note: Requires a location-capable emulator fixture.
steps:
  - action: wait
    timeoutSeconds: 0
''');
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        [
          'drive',
          'android',
          '--package',
          'sample_permissions',
          '--scenario',
          cameraScenario.path,
          '--scenario',
          mediaScenario.path,
          '--dry-run',
          '--json',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('ok', true));
    final automation = report['automation'] as Map<String, Object?>;
    final scenarios = (automation['scenarios'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(scenarios, hasLength(2));
    expect(
      scenarios.first['coverage'],
      contains(
        allOf(
          containsPair('category', 'permission'),
          containsPair('item', 'camera'),
          containsPair('path', 'grant'),
        ),
      ),
    );
    final coveragePolicy = automation['coveragePolicy'] as Map<String, Object?>;
    expect(coveragePolicy, containsPair('status', 'needsAgentCoverageReview'));
    final coverageSummary =
        coveragePolicy['coverageSummary'] as Map<String, Object?>;
    expect(coverageSummary, containsPair('scenarioCount', 2));
    expect(coverageSummary, containsPair('itemCount', 4));
    expect(
      coverageSummary['statusCounts'],
      allOf(containsPair('covered', 3), containsPair('blocked', 1)),
    );
    expect(coverageSummary['categoryCounts'], containsPair('permission', 4));
    expect(coverageSummary['scenariosWithoutCoverage'], isEmpty);
    expect(coverageSummary, containsPair('pathGroupCount', 3));
    expect(coverageSummary, containsPair('pathCoverageWarningCount', 2));
    expect(coverageSummary, containsPair('scenarioEvidenceWarningCount', 2));
    final pathCoverage = (coveragePolicy['pathCoverage'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final cameraCoverage = pathCoverage.singleWhere(
      (item) => item['item'] == 'camera',
    );
    expect(cameraCoverage, containsPair('status', 'readyForReview'));
    expect(cameraCoverage['paths'], ['deny', 'grant']);
    final photosCoverage = pathCoverage.singleWhere(
      (item) => item['item'] == 'photos',
    );
    expect(
      photosCoverage,
      allOf(
        containsPair('status', 'needsPathCoverageReview'),
        containsPair('needsNegativeOrErrorPath', true),
      ),
    );
    final qualityGates = coveragePolicy['qualityGates'] as List<Object?>;
    expect(
      qualityGates,
      contains(
        allOf(
          containsPair('id', 'coverage-metadata'),
          containsPair('status', 'readyForReview'),
        ),
      ),
    );
    expect(
      qualityGates,
      contains(
        allOf(
          containsPair('id', 'behavior-paths'),
          containsPair('status', 'needsPathCoverageReview'),
        ),
      ),
    );
    expect(
      qualityGates,
      contains(
        allOf(
          containsPair('id', 'scenario-evidence-assertions'),
          containsPair('status', 'needsEvidenceAssertions'),
        ),
      ),
    );
    final scenarioEvidence =
        (coveragePolicy['scenarioEvidence'] as List<Object?>)
            .cast<Map<String, Object?>>();
    expect(scenarioEvidence, hasLength(2));
    expect(
      scenarioEvidence,
      everyElement(
        allOf(
          containsPair('status', 'needsEvidenceAssertions'),
          containsPair('verificationActions', isEmpty),
          containsPair('suggestedActions', isA<List<Object?>>()),
        ),
      ),
    );
    final repairQueue = (automation['repairQueue'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(
      repairQueue,
      contains(
        allOf(
          containsPair('type', 'pathCoverage'),
          containsPair('gate', 'behavior-paths'),
          containsPair('item', 'photos'),
          containsPair('scenarioPaths', contains(mediaScenario.path)),
          containsPair('needsNegativeOrErrorPath', true),
          containsPair(
            'nextAction',
            allOf(
              containsPair('kind', 'addScenarioCoverageRows'),
              containsPair('path', mediaScenario.path),
              containsPair(
                'coverage',
                contains(
                  allOf(
                    containsPair('category', 'permission'),
                    containsPair('item', 'photos'),
                    containsPair('path', 'error'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(
      repairQueue,
      contains(
        allOf(
          containsPair('type', 'scenarioEvidence'),
          containsPair('gate', 'scenario-evidence-assertions'),
          containsPair('scenario', 'android camera permission matrix'),
          containsPair(
            'nextAction',
            allOf(
              containsPair('kind', 'addScenarioVerificationAction'),
              containsPair(
                'actions',
                contains(allOf(containsPair('action', 'assertLog'))),
              ),
            ),
          ),
        ),
      ),
    );
    final scenarioCoverage =
        (coveragePolicy['scenarioCoverage'] as List<Object?>)
            .cast<Map<String, Object?>>();
    expect(scenarioCoverage, hasLength(2));
    final allItems = scenarioCoverage
        .expand((scenario) => scenario['items'] as List<Object?>)
        .cast<Map<String, Object?>>()
        .toList();
    expect(
      allItems,
      contains(
        allOf(
          containsPair('category', 'permission'),
          containsPair('item', 'camera'),
          containsPair('path', 'deny'),
          containsPair('status', 'covered'),
        ),
      ),
    );
    expect(
      allItems,
      contains(
        allOf(containsPair('item', 'photos'), containsPair('path', 'grant')),
      ),
    );
    expect(
      allItems,
      contains(
        allOf(
          containsPair('item', 'locationWhenInUse'),
          containsPair('status', 'blocked'),
          containsPair('note', 'Requires a location-capable emulator fixture.'),
        ),
      ),
    );
    expect(report['targets'], isEmpty);
    expect(stderr, isEmpty);
  });

  test('drive dry-run allows explanatory coverage without assertions', () async {
    final environment = await createTestEnvironment();
    final scenario = File(
      '${environment.workingDirectory.path}/.fluoh/scenarios/sample/explanatory-coverage.md',
    );
    await scenario.parent.create(recursive: true);
    await scenario.writeAsString('''
kind: fluoh.automationScenario
schema: 1
name: explanatory coverage
platform: android
coverage:
  - category: permission
    item: camera
    path: grant
    status: blocked
    note: Requires a camera-capable emulator fixture.
  - category: permission
    item: photos
    path: deny
    status: notApplicable
    reason: Android build does not request photo permissions.
steps:
  - action: wait
    timeoutSeconds: 0
''');
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        [
          'drive',
          'android',
          '--package',
          'sample_permissions',
          '--scenario',
          scenario.path,
          '--dry-run',
          '--json',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('ok', true));
    final automation = report['automation'] as Map<String, Object?>;
    final coveragePolicy = automation['coveragePolicy'] as Map<String, Object?>;
    final scenarioEvidence =
        (coveragePolicy['scenarioEvidence'] as List<Object?>)
            .cast<Map<String, Object?>>();
    expect(scenarioEvidence, hasLength(1));
    expect(
      scenarioEvidence.single,
      allOf(
        containsPair('status', 'readyForReview'),
        containsPair('coverageItemCount', 2),
        containsPair('coveredCoverageItemCount', 0),
        containsPair('explanatoryCoverageItemCount', 2),
        containsPair('verificationActions', isEmpty),
      ),
    );
    final qualityGates = (coveragePolicy['qualityGates'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(
      qualityGates,
      contains(
        allOf(
          containsPair('id', 'scenario-evidence-assertions'),
          containsPair('status', 'readyForReview'),
        ),
      ),
    );
    final repairQueue = (automation['repairQueue'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(
      repairQueue.where(
        (item) => item['gate'] == 'scenario-evidence-assertions',
      ),
      isEmpty,
    );
    expect(stderr, isEmpty);
  });

  test('drive rejects invalid scenario coverage status', () async {
    final environment = await createTestEnvironment();
    final scenario = File(
      '${environment.workingDirectory.path}/.fluoh/scenarios/sample/invalid-coverage.md',
    );
    await scenario.parent.create(recursive: true);
    await scenario.writeAsString('''
kind: fluoh.automationScenario
schema: 1
name: invalid coverage
platform: android
coverage:
  - category: permission
    item: camera
    status: maybe
steps:
  - action: wait
    timeoutSeconds: 0
''');
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        [
          'drive',
          'android',
          '--package',
          'sample_permissions',
          '--scenario',
          scenario.path,
          '--dry-run',
          '--json',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('ok', false));
    final error = report['error'] as Map<String, Object?>;
    expect(error['message'], contains('status must be covered'));
    expect(error['message'], contains('notApplicable, or blocked'));
    expect(stderr, isEmpty);
  });

  test('drive rejects blocked coverage without a reason', () async {
    final environment = await createTestEnvironment();
    final scenario = File(
      '${environment.workingDirectory.path}/.fluoh/scenarios/sample/blocked-coverage.md',
    );
    await scenario.parent.create(recursive: true);
    await scenario.writeAsString('''
kind: fluoh.automationScenario
schema: 1
name: blocked coverage
platform: android
coverage:
  - category: permission
    item: camera
    path: grant
    status: blocked
steps:
  - action: wait
    timeoutSeconds: 0
''');
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        [
          'drive',
          'android',
          '--package',
          'sample_permissions',
          '--scenario',
          scenario.path,
          '--dry-run',
          '--json',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('ok', false));
    final error = report['error'] as Map<String, Object?>;
    expect(error['message'], contains('status blocked'));
    expect(error['message'], contains('non-empty note or reason'));
    expect(stderr, isEmpty);
  });

  test('drive Android package run writes session evidence', () async {
    final environment = await createTestEnvironment();
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
      flutterStdout: const {
        'devices --machine':
            '[{"id":"emulator-5554","name":"Pixel","targetPlatform":"android-arm64","isSupported":true,"emulator":true}]',
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
          'drive',
          'android',
          '--package',
          'camera',
          '--log-duration',
          '0',
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
    expect(
      invocations,
      contains('$root/example::flutter run -d emulator-5554 --debug --no-pub'),
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('command', 'drive'));
    expect(report, containsPair('ok', true));
    final automation = report['automation'] as Map<String, Object?>;
    expect(automation['platforms'], ['android']);
    final targets = report['targets'] as List<Object?>;
    final target = targets.single as Map<String, Object?>;
    expect(target, containsPair('phase', 'android-run'));
    final steps = target['steps'] as List<Object?>;
    final runStep = steps.cast<Map<String, Object?>>().singleWhere(
      (step) => step['name'] == 'example-run-android',
    );
    final details = runStep['details'] as Map<String, Object?>;
    final sessionFile =
        '${environment.workingDirectory.path}/.fluoh/run-sessions/automation/camera-android-session.json';
    expect(details, containsPair('sessionFile', sessionFile));
    expect(
      details,
      containsPair('vmServiceUri', 'http://127.0.0.1:12345/abc=/'),
    );
    final session =
        jsonDecode(File(sessionFile).readAsStringSync())
            as Map<String, Object?>;
    expect(session, containsPair('kind', 'flutterRunSession'));
    expect(session, containsPair('status', 'passed'));
    expect(session, containsPair('platform', 'android'));
    expect(stderr, isEmpty);
  });

  test('drive iOS scenario taps permission via built-in XCTest', () async {
    final baseEnvironment = await createTestEnvironment();
    final xcrunLog = File('${baseEnvironment.workingDirectory.path}/xcrun.log');
    final xcrun = await _writeXcrunFixture(
      Directory('${baseEnvironment.workingDirectory.path}/tools'),
      xcrunLog.path,
      supportsXCTest: true,
    );
    final environment = FluohEnvironment(
      homeDirectory: baseEnvironment.homeDirectory,
      workingDirectory: baseEnvironment.workingDirectory,
      processEnvironment: {
        ...baseEnvironment.processEnvironment,
        'FLUOH_XCRUN': xcrun.path,
      },
    );
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
      flutterExitCodeSequences: const {
        'build ios --simulator --debug': [1, 0],
      },
      flutterStdout: const {
        'devices --machine':
            '[{"id":"ios-sim","name":"iPhone","targetPlatform":"ios","isSupported":true,"emulator":true}]',
        'run -d ios-sim --debug --no-pub':
            'Flutter run key commands.\n'
            'Debug service listening on http://127.0.0.1:23456/ios=/\n'
            'Application running.',
      },
      flutterStderr: const {
        'build ios --simulator --debug':
            "Swift Compiler Error (Xcode): File 'FlutterPlugin.h' has been modified since the precompiled header 'Runner-primary-Bridging-header.pch' was built",
      },
    );
    await _writePackageManifest(environment.workingDirectory);
    await _writeFlutterPackage(environment.workingDirectory);
    final exampleDirectory = Directory(
      '${environment.workingDirectory.path}/example',
    );
    await _writeFlutterExample(exampleDirectory);
    final appInfoPlist = File(
      '${exampleDirectory.path}/build/ios/iphonesimulator/Runner.app/Info.plist',
    );
    await appInfoPlist.parent.create(recursive: true);
    await appInfoPlist.writeAsString('''
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>com.example.camera</string>
</dict>
</plist>
''');
    final scenario = File(
      '${environment.workingDirectory.path}/.fluoh/scenarios/camera/ios-xctest-permission.md',
    );
    await scenario.parent.create(recursive: true);
    await scenario.writeAsString('''
kind: fluoh.automationScenario
schema: 1
name: ios xctest camera permission
platform: ios
steps:
  - action: resetPermission
    bundleId: com.example.camera
    permission: camera
  - action: allowPermission
    bundleId: com.example.camera
    permission: camera
  - action: assertSession
    status: passed
''');
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

    final exitCode = await runFluoh(
      [
        'drive',
        'ios',
        '--package',
        'camera',
        '--scenario',
        scenario.path,
        '--log-duration',
        '0',
        '--json',
      ],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    expect(exitCode, 0, reason: stdout.join('\n'));

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('command', 'drive'));
    expect(report, containsPair('ok', true));
    final automation = report['automation'] as Map<String, Object?>;
    final delivery =
        automation['deliveryRecommendation'] as Map<String, Object?>;
    expect(delivery, containsPair('status', 'needsCoverageReview'));
    expect(delivery, containsPair('recommendation', 'blocked'));
    final repairQueue = (automation['repairQueue'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(repairQueue.first['type'], isNot('coverage'));
    expect(
      repairQueue.first,
      allOf(
        containsPair('type', 'scenarioCoverage'),
        containsPair('nextAction', isA<Map<String, Object?>>()),
        containsPair('scenarioCandidates', isNotEmpty),
      ),
    );
    expect(
      repairQueue,
      contains(
        allOf(
          containsPair('type', 'coverage'),
          containsPair('gate', 'behavior-paths'),
          containsPair('status', 'needsPathCoverageReview'),
        ),
      ),
    );
    final plannedScenario =
        (automation['scenarios'] as List<Object?>).single
            as Map<String, Object?>;
    final inferredCoverage = plannedScenario['coverage'] as List<Object?>;
    expect(
      inferredCoverage,
      contains(
        allOf(
          containsPair('category', 'permission'),
          containsPair('item', 'camera'),
          containsPair('path', 'grant'),
        ),
      ),
    );
    expect(
      inferredCoverage,
      contains(
        allOf(
          containsPair('category', 'permission'),
          containsPair('item', 'camera'),
          containsPair('path', 'reset'),
        ),
      ),
    );
    final target =
        (report['targets'] as List<Object?>).single as Map<String, Object?>;
    final steps = (target['steps'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final scenarioStep = steps.singleWhere(
      (step) =>
          step['name'] ==
          'automation-scenario-ios-ios-xctest-camera-permission',
    );
    expect(scenarioStep, containsPair('status', 'passed'));
    final scenarioDetails = scenarioStep['details'] as Map<String, Object?>;
    final actions = (scenarioDetails['actions'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final allowAction = actions.singleWhere(
      (action) => action['action'] == 'allowPermission',
    );
    final allowDetails = allowAction['details'] as Map<String, Object?>;
    expect(allowDetails, containsPair('driver', 'xctest'));
    expect(allowDetails, containsPair('method', 'xcodebuildTest'));
    expect(allowDetails, containsPair('bundleId', 'com.example.camera'));
    final generatedTest = File(
      '${environment.homeDirectory.path}/cache/automation/ios-xctest/FluohIosAutomationUITests/PermissionPromptUITests.swift',
    );
    expect(await generatedTest.exists(), isTrue);
    final generatedSource = await generatedTest.readAsString();
    expect(generatedSource, contains('com.example.camera'));
    expect(generatedSource, contains('PermissionPromptUITests'));
    final invocations = xcrunLog.readAsStringSync();
    expect(
      invocations,
      contains('simctl privacy ios-sim reset camera com.example.camera'),
    );
    expect(invocations, contains('xcodebuild test'));
    expect(invocations, contains('CODE_SIGNING_ALLOWED=NO'));
    expect(
      invocations,
      isNot(contains('simctl privacy ios-sim grant camera com.example.camera')),
    );
    expect(stderr, isEmpty);
  });

  test('drive iOS scenario runs text actions via built-in XCTest', () async {
    final baseEnvironment = await createTestEnvironment();
    final xcrunLog = File('${baseEnvironment.workingDirectory.path}/xcrun.log');
    final xcrun = await _writeXcrunFixture(
      Directory('${baseEnvironment.workingDirectory.path}/tools'),
      xcrunLog.path,
      supportsXCTest: true,
      iosAppInstalled: false,
    );
    final openLog = File('${baseEnvironment.workingDirectory.path}/open.log');
    final open = File('${baseEnvironment.workingDirectory.path}/tools/open');
    await _writeExecutable(open, '''
#!/usr/bin/env bash
printf "%s\\n" "\$*" >> "${openLog.path}"
exit 0
''');
    final environment = FluohEnvironment(
      homeDirectory: baseEnvironment.homeDirectory,
      workingDirectory: baseEnvironment.workingDirectory,
      processEnvironment: {
        ...baseEnvironment.processEnvironment,
        'FLUOH_XCRUN': xcrun.path,
        'FLUOH_OPEN': open.path,
      },
    );
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
      flutterExitCodeSequences: const {
        'build ios --simulator --debug': [1, 0],
      },
      flutterStdout: const {
        'devices --machine':
            '[{"id":"ios-sim","name":"iPhone","targetPlatform":"ios","isSupported":true,"emulator":true}]',
        'run -d ios-sim --debug --no-pub':
            'Flutter run key commands.\n'
            'Debug service listening on http://127.0.0.1:23456/ios=/\n'
            'Application running.',
      },
      flutterStderr: const {
        'build ios --simulator --debug':
            "Swift Compiler Error (Xcode): File 'FlutterPlugin.h' has been modified since the precompiled header 'Runner-primary-Bridging-header.pch' was built",
      },
    );
    await _writePackageManifest(environment.workingDirectory);
    await _writeFlutterPackage(environment.workingDirectory);
    final exampleDirectory = Directory(
      '${environment.workingDirectory.path}/example',
    );
    await _writeFlutterExample(exampleDirectory);
    final appInfoPlist = File(
      '${exampleDirectory.path}/build/ios/iphonesimulator/Runner.app/Info.plist',
    );
    await appInfoPlist.parent.create(recursive: true);
    await appInfoPlist.writeAsString('''
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>com.example.camera</string>
</dict>
</plist>
''');
    final debugAppInfoPlist = File(
      '${exampleDirectory.path}/build/ios/Debug-iphonesimulator/Runner.app/Info.plist',
    );
    await debugAppInfoPlist.parent.create(recursive: true);
    await debugAppInfoPlist.writeAsString('''
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>com.example.camera</string>
</dict>
</plist>
''');
    final scenario = File(
      '${environment.workingDirectory.path}/.fluoh/scenarios/camera/ios-xctest-text.md',
    );
    await scenario.parent.create(recursive: true);
    await scenario.writeAsString('''
kind: fluoh.automationScenario
schema: 1
name: ios xctest text
platform: ios
steps:
  - action: wait
    timeoutSeconds: 0
  - action: tapText
    bundleId: com.example.camera
    labels: [Permission.camera]
  - action: assertText
    bundleId: com.example.camera
    labels: [PermissionStatus.granted]
  - action: assertLog
    contains: Application running.
  - action: assertSession
    status: passed
''');
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

    final exitCode = await runFluoh(
      [
        'drive',
        'ios',
        '--package',
        'camera',
        '--scenario',
        scenario.path,
        '--log-duration',
        '0',
        '--json',
      ],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    expect(exitCode, 0, reason: stdout.join('\n'));

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('command', 'drive'));
    expect(report, containsPair('ok', true));
    final target =
        (report['targets'] as List<Object?>).single as Map<String, Object?>;
    final steps = (target['steps'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(
      steps,
      contains(
        allOf(
          containsPair('name', 'example-clean-ios-build-cache'),
          containsPair('command', 'flutter clean'),
          containsPair('status', 'passed'),
        ),
      ),
    );
    final buildStep = steps.singleWhere(
      (step) => step['name'] == 'example-build-ios',
    );
    final buildDetails = buildStep['details'] as Map<String, Object?>;
    expect(buildStep, containsPair('status', 'passed'));
    expect(buildDetails, containsPair('retryAfterClean', true));
    expect(
      buildDetails,
      containsPair('firstFailure', isA<Map<String, Object?>>()),
    );
    final scenarioStep = steps.singleWhere(
      (step) => step['name'] == 'automation-scenario-ios-ios-xctest-text',
    );
    expect(scenarioStep, containsPair('status', 'passed'));
    final scenarioDetails = scenarioStep['details'] as Map<String, Object?>;
    final actions = (scenarioDetails['actions'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(actions.map((action) => action['action']), [
      'wait',
      'tapText',
      'assertText',
      'assertLog',
      'assertSession',
    ]);
    final tapAction = actions.singleWhere(
      (action) => action['action'] == 'tapText',
    );
    final tapDetails = tapAction['details'] as Map<String, Object?>;
    expect(tapDetails, containsPair('driver', 'xctest'));
    expect(tapDetails, containsPair('method', 'xcodebuildTest'));
    expect(tapDetails, containsPair('bundleId', 'com.example.camera'));
    final appInstall = tapDetails['appInstall'] as Map<String, Object?>;
    final foreground = appInstall['foreground'] as Map<String, Object?>;
    expect(foreground, containsPair('status', 'foregrounded'));
    final waitAction = actions.singleWhere(
      (action) => action['action'] == 'wait',
    );
    expect(waitAction['details'], containsPair('waitSeconds', 0));
    final assertLogAction = actions.singleWhere(
      (action) => action['action'] == 'assertLog',
    );
    final assertLogDetails = assertLogAction['details'] as Map<String, Object?>;
    expect(assertLogDetails, containsPair('source', 'flutterRunOutput'));
    expect(assertLogDetails['path'], isA<String>());
    final generatedTest = File(
      '${environment.homeDirectory.path}/cache/automation/ios-xctest/FluohIosAutomationUITests/PermissionPromptUITests.swift',
    );
    expect(await generatedTest.exists(), isTrue);
    final generatedSource = await generatedTest.readAsString();
    expect(generatedSource, contains('TextActionUITests'));
    expect(generatedSource, contains('PermissionStatus.granted'));
    final invocations = xcrunLog.readAsStringSync();
    final workflowInvocations = File(
      '${environment.workingDirectory.path}/package_workflow_invocations.txt',
    ).readAsStringSync();
    expect(
      workflowInvocations,
      contains('example::flutter build ios --simulator --debug'),
    );
    expect(workflowInvocations, contains('example::flutter clean'));
    expect(
      RegExp(
        r'example::flutter build ios --simulator --debug',
      ).allMatches(workflowInvocations),
      hasLength(2),
    );
    expect(
      workflowInvocations,
      isNot(contains('example::flutter build ios --debug --no-codesign')),
    );
    expect(
      invocations,
      contains('simctl get_app_container ios-sim com.example.camera app'),
    );
    expect(invocations, contains('simctl install ios-sim'));
    expect(invocations, contains('simctl launch ios-sim com.example.camera'));
    expect(invocations, contains('build/ios/iphonesimulator/Runner.app'));
    expect(invocations, isNot(contains('Debug-iphonesimulator/Runner.app')));
    final openInvocations = openLog.readAsStringSync();
    expect(
      openInvocations,
      contains('-a Simulator --args -CurrentDeviceUDID ios-sim'),
    );
    expect(RegExp('xcodebuild test').allMatches(invocations), hasLength(2));
    expect(invocations, contains('CODE_SIGNING_ALLOWED=NO'));
    expect(stderr, isEmpty);
  });

  test('drive iOS scenario runs coordinate gestures via built-in XCTest', () async {
    final baseEnvironment = await createTestEnvironment();
    final xcrunLog = File('${baseEnvironment.workingDirectory.path}/xcrun.log');
    final xcrun = await _writeXcrunFixture(
      Directory('${baseEnvironment.workingDirectory.path}/tools'),
      xcrunLog.path,
      supportsXCTest: true,
    );
    final environment = FluohEnvironment(
      homeDirectory: baseEnvironment.homeDirectory,
      workingDirectory: baseEnvironment.workingDirectory,
      processEnvironment: {
        ...baseEnvironment.processEnvironment,
        'FLUOH_XCRUN': xcrun.path,
      },
    );
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
      flutterStdout: const {
        'devices --machine':
            '[{"id":"ios-sim","name":"iPhone","targetPlatform":"ios","isSupported":true,"emulator":true}]',
        'run -d ios-sim --debug --no-pub':
            'Flutter run key commands.\n'
            'Debug service listening on http://127.0.0.1:23456/ios=/\n'
            'Application running.',
      },
    );
    await _writePackageManifest(environment.workingDirectory);
    await _writeFlutterPackage(environment.workingDirectory);
    await _writeFlutterExample(
      Directory('${environment.workingDirectory.path}/example'),
    );
    final scenario = File(
      '${environment.workingDirectory.path}/.fluoh/scenarios/camera/ios-xctest-gestures.md',
    );
    await scenario.parent.create(recursive: true);
    await scenario.writeAsString('''
kind: fluoh.automationScenario
schema: 1
name: ios xctest gestures
platform: ios
steps:
  - action: tap
    bundleId: com.example.camera
    x: 20
    y: 30
  - action: swipe
    bundleId: com.example.camera
    x: 10
    y: 20
    endX: 30
    endY: 40
    durationMilliseconds: 250
  - action: assertSession
    status: passed
''');
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
          'drive',
          'ios',
          '--package',
          'camera',
          '--scenario',
          scenario.path,
          '--log-duration',
          '0',
          '--json',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('command', 'drive'));
    expect(report, containsPair('ok', true));
    final target =
        (report['targets'] as List<Object?>).single as Map<String, Object?>;
    final steps = (target['steps'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final scenarioStep = steps.singleWhere(
      (step) => step['name'] == 'automation-scenario-ios-ios-xctest-gestures',
    );
    expect(scenarioStep, containsPair('status', 'passed'));
    final scenarioDetails = scenarioStep['details'] as Map<String, Object?>;
    final actions = (scenarioDetails['actions'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(actions.map((action) => action['action']), [
      'tap',
      'swipe',
      'assertSession',
    ]);
    final tapDetails = actions.first['details'] as Map<String, Object?>;
    expect(tapDetails, containsPair('driver', 'xctest'));
    expect(tapDetails, containsPair('method', 'xcodebuildTest'));
    expect(tapDetails['gesture'], containsPair('x', 20));
    final swipeDetails = actions[1]['details'] as Map<String, Object?>;
    expect(swipeDetails, containsPair('driver', 'xctest'));
    expect(
      swipeDetails['gesture'],
      allOf(
        containsPair('x', 10),
        containsPair('y', 20),
        containsPair('endX', 30),
        containsPair('endY', 40),
        containsPair('durationMilliseconds', 250),
      ),
    );
    final generatedTest = File(
      '${environment.homeDirectory.path}/cache/automation/ios-xctest/FluohIosAutomationUITests/PermissionPromptUITests.swift',
    );
    expect(await generatedTest.exists(), isTrue);
    final generatedSource = await generatedTest.readAsString();
    expect(generatedSource, contains('CoordinateActionUITests'));
    expect(generatedSource, contains('press(forDuration: 0.25'));
    final invocations = xcrunLog.readAsStringSync();
    expect(RegExp('xcodebuild test').allMatches(invocations), hasLength(2));
    expect(stderr, isEmpty);
  });

  test('drive iOS scenario rejects app bundles with mismatched bundle ids', () async {
    final baseEnvironment = await createTestEnvironment();
    final xcrunLog = File('${baseEnvironment.workingDirectory.path}/xcrun.log');
    final xcrun = await _writeXcrunFixture(
      Directory('${baseEnvironment.workingDirectory.path}/tools'),
      xcrunLog.path,
      supportsXCTest: true,
      iosAppInstalled: false,
    );
    final environment = FluohEnvironment(
      homeDirectory: baseEnvironment.homeDirectory,
      workingDirectory: baseEnvironment.workingDirectory,
      processEnvironment: {
        ...baseEnvironment.processEnvironment,
        'FLUOH_XCRUN': xcrun.path,
      },
    );
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
      flutterStdout: const {
        'devices --machine':
            '[{"id":"ios-sim","name":"iPhone","targetPlatform":"ios","isSupported":true,"emulator":true}]',
        'run -d ios-sim --debug --no-pub':
            'Flutter run key commands.\n'
            'Debug service listening on http://127.0.0.1:23456/ios=/\n'
            'Application running.',
      },
    );
    await _writePackageManifest(environment.workingDirectory);
    await _writeFlutterPackage(environment.workingDirectory);
    final exampleDirectory = Directory(
      '${environment.workingDirectory.path}/example',
    );
    await _writeFlutterExample(exampleDirectory);
    final appInfoPlist = File(
      '${exampleDirectory.path}/build/ios/iphonesimulator/Runner.app/Info.plist',
    );
    await appInfoPlist.parent.create(recursive: true);
    await appInfoPlist.writeAsString('''
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>com.example.other</string>
</dict>
</plist>
''');
    final scenario = File(
      '${environment.workingDirectory.path}/.fluoh/scenarios/camera/ios-wrong-bundle.md',
    );
    await scenario.parent.create(recursive: true);
    await scenario.writeAsString('''
kind: fluoh.automationScenario
schema: 1
name: ios wrong bundle
platform: ios
steps:
  - action: tap
    bundleId: com.example.camera
    x: 20
    y: 30
''');
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
          'drive',
          'ios',
          '--package',
          'camera',
          '--scenario',
          scenario.path,
          '--log-duration',
          '0',
          '--json',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      1,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('ok', false));
    final target =
        (report['targets'] as List<Object?>).single as Map<String, Object?>;
    final steps = (target['steps'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final scenarioStep = steps.singleWhere(
      (step) => step['name'] == 'automation-scenario-ios-ios-wrong-bundle',
    );
    expect(scenarioStep, containsPair('status', 'failed'));
    final scenarioDetails = scenarioStep['details'] as Map<String, Object?>;
    final actions = (scenarioDetails['actions'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final tapAction = actions.singleWhere(
      (action) => action['action'] == 'tap',
    );
    final tapDetails = tapAction['details'] as Map<String, Object?>;
    final appInstall = tapDetails['appInstall'] as Map<String, Object?>;
    expect(appInstall, containsPair('status', 'missingAppBundle'));
    expect(
      appInstall['candidateAppBundles'],
      contains(
        allOf(
          containsPair('path', appInfoPlist.parent.path),
          containsPair('bundleIdentifier', 'com.example.other'),
        ),
      ),
    );
    final invocations = xcrunLog.readAsStringSync();
    expect(invocations, contains('simctl get_app_container'));
    expect(invocations, isNot(contains('simctl install ios-sim')));
    expect(invocations, isNot(contains('xcodebuild test')));
    expect(stderr, isEmpty);
  });

  test(
    'drive Android scenario finds HOME Android SDK adb and verifies evidence',
    () async {
      final baseEnvironment = await createTestEnvironment();
      final adbLog = File('${baseEnvironment.workingDirectory.path}/adb.log');
      await _writeAndroidAdbFixture(
        Directory(
          '${baseEnvironment.homeDirectory.path}/Library/Android/sdk/platform-tools',
        ),
        adbLog.path,
        uiXml:
            '<hierarchy>'
            '<node text="" content-desc="" resource-id="com.example.camera:id/request_camera" bounds="[10,20][110,80]" />'
            '<node text="Allow" bounds="[10,20][110,80]" />'
            '</hierarchy>',
        logcat: 'permission granted',
      );
      final environment = FluohEnvironment(
        homeDirectory: baseEnvironment.homeDirectory,
        workingDirectory: baseEnvironment.workingDirectory,
        processEnvironment: {
          ...baseEnvironment.processEnvironment,
          'HOME': baseEnvironment.homeDirectory.path,
        },
      );
      final source = await _createWorkflowSdkSource(
        environment.homeDirectory,
        environment.workingDirectory,
        flutterStdout: const {
          'devices --machine':
              '[{"id":"emulator-5554","name":"Pixel","targetPlatform":"android-arm64","isSupported":true,"emulator":true}]',
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
      final scenario = File(
        '${environment.workingDirectory.path}/.fluoh/scenarios/camera/android-permission.md',
      );
      await scenario.parent.create(recursive: true);
      await scenario.writeAsString('''
# Android permission

```yaml
kind: fluoh.automationScenario
schema: 1
name: camera permission
platform: android
coverage:
  - category: publicApi
    item: camera
    path: success
  - category: publicApi
    item: camera
    path: error
    status: notApplicable
    note: Public API error handling is covered by a package test fixture.
  - category: permission
    item: camera
    path: grant
  - category: permission
    item: camera
    path: deny
    status: notApplicable
    note: Denial path is covered by a separate package integration test.
steps:
  - action: clearAppData
    packageName: com.example.camera
  - action: swipe
    x: 10
    y: 20
    endX: 30
    endY: 40
    durationMilliseconds: 250
  - action: tapText
    labels: [request_camera]
  - action: allowPermission
    labels: [Allow]
  - action: assertLog
    contains: permission granted
  - action: assertSession
    status: passed
```
''');
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
            'drive',
            'android',
            '--package',
            'camera',
            '--scenario',
            scenario.path,
            '--log-duration',
            '0',
            '--json',
          ],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final report = jsonDecode(stdout.single) as Map<String, Object?>;
      expect(report, containsPair('command', 'drive'));
      expect(report, containsPair('ok', true));
      final automation = report['automation'] as Map<String, Object?>;
      final delivery =
          automation['deliveryRecommendation'] as Map<String, Object?>;
      expect(delivery, containsPair('status', 'readyForReportReview'));
      expect(delivery, containsPair('recommendation', 'ready'));
      expect(delivery, containsPair('ready', true));
      expect(automation['repairQueue'], isEmpty);
      final scenarios = automation['scenarios'] as List<Object?>;
      expect(scenarios.single, containsPair('platform', 'android'));
      final target =
          (report['targets'] as List<Object?>).single as Map<String, Object?>;
      final steps = (target['steps'] as List<Object?>)
          .cast<Map<String, Object?>>();
      final scenarioStep = steps.singleWhere(
        (step) =>
            step['name'] == 'automation-scenario-android-camera-permission',
      );
      expect(scenarioStep, containsPair('status', 'passed'));
      final scenarioDetails = scenarioStep['details'] as Map<String, Object?>;
      final actions = (scenarioDetails['actions'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(actions.map((action) => action['action']), [
        'clearAppData',
        'foregroundApp',
        'swipe',
        'tapText',
        'allowPermission',
        'assertLog',
        'assertSession',
      ]);
      final tapAction = actions.singleWhere(
        (action) => action['action'] == 'tapText',
      );
      final tapDetails = tapAction['details'] as Map<String, Object?>;
      expect(tapDetails, containsPair('matchedText', 'request_camera'));
      expect(
        tapDetails,
        containsPair('resourceId', 'com.example.camera:id/request_camera'),
      );
      expect(
        adbLog.readAsStringSync(),
        contains('-s emulator-5554 shell pm clear com.example.camera'),
      );
      expect(
        adbLog.readAsStringSync(),
        contains(
          '-s emulator-5554 shell monkey -p com.example.camera -c android.intent.category.LAUNCHER 1',
        ),
      );
      expect(
        adbLog.readAsStringSync(),
        contains('-s emulator-5554 shell input swipe 10 20 30 40 250'),
      );
      expect(
        adbLog.readAsStringSync(),
        contains('-s emulator-5554 shell input tap 60 50'),
      );
      expect(stderr, isEmpty);
    },
  );

  test(
    'drive Android scenario prefers example applicationId over package namespace',
    () async {
      final baseEnvironment = await createTestEnvironment();
      final adbLog = File('${baseEnvironment.workingDirectory.path}/adb.log');
      final adb = await _writeAndroidAdbFixture(
        Directory('${baseEnvironment.workingDirectory.path}/tools'),
        adbLog.path,
        uiXml:
            '<hierarchy>'
            '<node text="" content-desc="" resource-id="com.example.camera:id/request_camera" bounds="[10,20][110,80]" />'
            '</hierarchy>',
        logcat: 'permission granted',
      );
      final environment = FluohEnvironment(
        homeDirectory: baseEnvironment.homeDirectory,
        workingDirectory: baseEnvironment.workingDirectory,
        processEnvironment: {
          ...baseEnvironment.processEnvironment,
          'FLUOH_ANDROID_ADB': adb.path,
        },
      );
      final source = await _createWorkflowSdkSource(
        environment.homeDirectory,
        environment.workingDirectory,
        flutterStdout: const {
          'devices --machine':
              '[{"id":"emulator-5554","name":"Pixel","targetPlatform":"android-arm64","isSupported":true,"emulator":true}]',
          'run -d emulator-5554 --debug --no-pub':
              'Flutter run key commands.\n'
              'Debug service listening on http://127.0.0.1:12345/abc=/\n'
              'Application running.',
        },
      );
      await _writePackageManifest(environment.workingDirectory);
      await _writeFlutterPackage(environment.workingDirectory);
      await File(
        '${environment.workingDirectory.path}/build.gradle',
      ).writeAsString('''
plugins {
  id 'com.android.library'
}

android {
  namespace 'com.example.plugin'
}
''');
      final exampleDirectory = Directory(
        '${environment.workingDirectory.path}/example',
      );
      await _writeFlutterExample(exampleDirectory);
      final exampleGradle = File(
        '${exampleDirectory.path}/android/app/build.gradle',
      );
      await exampleGradle.parent.create(recursive: true);
      await exampleGradle.writeAsString('''
plugins {
  id 'com.android.application'
}

android {
  namespace 'com.example.camera'
  defaultConfig {
    applicationId 'com.example.camera'
  }
}
''');
      final scenario = File(
        '${environment.workingDirectory.path}/.fluoh/scenarios/camera/android-autoforeground.md',
      );
      await scenario.parent.create(recursive: true);
      await scenario.writeAsString('''
kind: fluoh.automationScenario
schema: 1
name: android autoforeground
platform: android
steps:
  - action: tapText
    labels: [request_camera]
  - action: assertSession
    status: passed
''');
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
            'drive',
            'android',
            '--package',
            'camera',
            '--scenario',
            scenario.path,
            '--log-duration',
            '0',
            '--json',
          ],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final report = jsonDecode(stdout.single) as Map<String, Object?>;
      expect(report, containsPair('ok', true));
      final target =
          (report['targets'] as List<Object?>).single as Map<String, Object?>;
      final steps = (target['steps'] as List<Object?>)
          .cast<Map<String, Object?>>();
      final scenarioStep = steps.singleWhere(
        (step) =>
            step['name'] ==
            'automation-scenario-android-android-autoforeground',
      );
      expect(scenarioStep, containsPair('status', 'passed'));
      final scenarioDetails = scenarioStep['details'] as Map<String, Object?>;
      final actions = (scenarioDetails['actions'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(actions.map((action) => action['action']), [
        'foregroundApp',
        'tapText',
        'assertSession',
      ]);
      final foregroundDetails =
          actions.first['details'] as Map<String, Object?>;
      expect(
        foregroundDetails,
        containsPair('packageName', 'com.example.camera'),
      );
      final invocations = adbLog.readAsStringSync();
      expect(
        invocations,
        contains(
          '-s emulator-5554 shell monkey -p com.example.camera -c android.intent.category.LAUNCHER 1',
        ),
      );
      expect(invocations, isNot(contains('com.example.plugin')));
      expect(stderr, isEmpty);
    },
  );

  test('drive Android scenario failure returns repair hints', () async {
    final baseEnvironment = await createTestEnvironment();
    final adb = await _writeAndroidAdbFixture(
      Directory('${baseEnvironment.workingDirectory.path}/tools'),
      '${baseEnvironment.workingDirectory.path}/adb.log',
      uiXml:
          '<hierarchy><node text="Not now" bounds="[10,20][110,80]" /></hierarchy>',
      logcat: 'permission missing',
    );
    final environment = FluohEnvironment(
      homeDirectory: baseEnvironment.homeDirectory,
      workingDirectory: baseEnvironment.workingDirectory,
      processEnvironment: {
        ...baseEnvironment.processEnvironment,
        'FLUOH_ANDROID_ADB': adb.path,
      },
    );
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
      flutterStdout: const {
        'devices --machine':
            '[{"id":"emulator-5554","name":"Pixel","targetPlatform":"android-arm64","isSupported":true,"emulator":true}]',
        'run -d emulator-5554 --debug --no-pub':
            'Flutter run key commands.\nApplication running.',
      },
    );
    await _writePackageManifest(environment.workingDirectory);
    await _writeFlutterPackage(environment.workingDirectory);
    await _writeFlutterExample(
      Directory('${environment.workingDirectory.path}/example'),
    );
    final scenario = File(
      '${environment.workingDirectory.path}/.fluoh/scenarios/camera/android-permission.md',
    );
    await scenario.parent.create(recursive: true);
    await scenario.writeAsString('''
kind: fluoh.automationScenario
schema: 1
name: denied camera permission
platform: android
steps:
  - action: allowPermission
    labels: [Grant camera]
    timeoutSeconds: 0
    repairHints:
      - Add a stable permission trigger and visible allow label before this step.
''');
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
          'drive',
          'android',
          '--package',
          'camera',
          '--scenario',
          scenario.path,
          '--log-duration',
          '0',
          '--json',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      1,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('ok', false));
    final automation = report['automation'] as Map<String, Object?>;
    final delivery =
        automation['deliveryRecommendation'] as Map<String, Object?>;
    expect(delivery, containsPair('status', 'needsRepair'));
    expect(delivery, containsPair('recommendation', 'blocked'));
    final repairQueue = (automation['repairQueue'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(
      repairQueue,
      contains(
        allOf(
          containsPair('type', 'diagnostic'),
          containsPair('code', 'android.scenario_allowPermission_failed'),
          containsPair('nextCommand', contains('fluoh drive')),
        ),
      ),
    );
    final repairPlan = automation['repairPlan'] as Map<String, Object?>;
    expect(repairPlan, containsPair('status', 'needsRepair'));
    expect(
      repairPlan['nextStep'],
      allOf(
        containsPair('kind', 'fixDiagnosticAndRerun'),
        containsPair('sourceType', 'diagnostic'),
        containsPair('code', 'android.scenario_allowPermission_failed'),
        containsPair('nextCommand', contains('fluoh drive')),
        containsPair(
          'doneWhen',
          contains(
            'diagnostic android.scenario_allowPermission_failed no longer appears',
          ),
        ),
        containsPair(
          'validation',
          allOf(
            containsPair('kind', 'command'),
            containsPair('command', contains('fluoh drive')),
          ),
        ),
        containsPair(
          'repairHints',
          contains(
            'Add a stable permission trigger and visible allow label before this step.',
          ),
        ),
      ),
    );
    final target =
        (report['targets'] as List<Object?>).single as Map<String, Object?>;
    expect(target, containsPair('passed', false));
    final steps = (target['steps'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final scenarioStep = steps.singleWhere(
      (step) =>
          step['name'] ==
          'automation-scenario-android-denied-camera-permission',
    );
    expect(scenarioStep, containsPair('status', 'failed'));
    final diagnostics = (scenarioStep['diagnostics'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final diagnosticDetails =
        diagnostics.single['details'] as Map<String, Object?>;
    expect(
      diagnosticDetails['repairHints'],
      contains(
        'Add a stable permission trigger and visible allow label before this step.',
      ),
    );
    expect(diagnostics.single['nextCommand'], contains('fluoh drive'));
    expect(stderr, isEmpty);
  });

  test('drive project scenario failure reruns project automation', () async {
    final baseEnvironment = await createTestEnvironment();
    final adb = await _writeAndroidAdbFixture(
      Directory('${baseEnvironment.workingDirectory.path}/tools'),
      '${baseEnvironment.workingDirectory.path}/adb.log',
      uiXml:
          '<hierarchy><node text="Not now" bounds="[10,20][110,80]" /></hierarchy>',
      logcat: 'permission missing',
    );
    final environment = FluohEnvironment(
      homeDirectory: baseEnvironment.homeDirectory,
      workingDirectory: baseEnvironment.workingDirectory,
      processEnvironment: {
        ...baseEnvironment.processEnvironment,
        'FLUOH_ANDROID_ADB': adb.path,
      },
    );
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
      flutterStdout: const {
        'devices --machine':
            '[{"id":"emulator-5554","name":"Pixel","targetPlatform":"android-arm64","isSupported":true,"emulator":true}]',
        'run -d emulator-5554 --debug --no-pub':
            'Flutter run key commands.\nApplication running.',
      },
    );
    await writeFlutterProjectFixture(environment.workingDirectory);
    await _writeProjectSdkConfig(environment.workingDirectory);
    final scenario = File(
      '${environment.workingDirectory.path}/.fluoh/scenarios/current/android-permission.md',
    );
    await scenario.parent.create(recursive: true);
    await scenario.writeAsString('''
kind: fluoh.automationScenario
schema: 1
name: denied camera permission
platform: android
steps:
  - action: allowPermission
    labels: [Grant camera]
    timeoutSeconds: 0
''');
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
          'drive',
          'android',
          '--no-auto-emulator',
          '--scenario',
          scenario.path,
          '--log-duration',
          '0',
          '--json',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      1,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    final target =
        (report['targets'] as List<Object?>).single as Map<String, Object?>;
    expect(target['target'], containsPair('kind', 'project'));
    expect(target, containsPair('nextCommand', isA<String>()));
    final nextCommand = target['nextCommand'] as String;
    expect(nextCommand, contains('fluoh drive android'));
    expect(nextCommand, contains('--no-auto-emulator'));
    expect(nextCommand, contains('--scenario ${scenario.path}'));
    expect(nextCommand, isNot(contains('--package current')));
    final steps = (target['steps'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final scenarioStep = steps.singleWhere(
      (step) =>
          step['name'] ==
          'automation-scenario-android-denied-camera-permission',
    );
    final diagnostics = (scenarioStep['diagnostics'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(diagnostics.single['nextCommand'], nextCommand);
    expect(stderr, isEmpty);
  });

  test('drive Android scenario kills timed out adb commands', () async {
    final baseEnvironment = await createTestEnvironment();
    final adbLog = File('${baseEnvironment.workingDirectory.path}/adb.log');
    final timeoutMarker = File(
      '${baseEnvironment.workingDirectory.path}/adb-timeout.marker',
    );
    final adb = File('${baseEnvironment.workingDirectory.path}/tools/adb');
    await _writeExecutable(adb, '''
#!/usr/bin/env bash
printf "%s\\n" "\$*" >> ${_shellSingleQuote(adbLog.path)}
if [ "\$1" = "-s" ]; then
  shift 2
fi

if [ "\$*" = "shell uiautomator dump /sdcard/fluoh-window.xml" ]; then
  trap 'printf "%s\\n" "terminated" >> ${_shellSingleQuote(timeoutMarker.path)}; exit 143' TERM INT
  while true; do sleep 1; done
fi

printf "%s\\n" "unsupported adb \$*" >&2
exit 1
''');
    final environment = FluohEnvironment(
      homeDirectory: baseEnvironment.homeDirectory,
      workingDirectory: baseEnvironment.workingDirectory,
      processEnvironment: {
        ...baseEnvironment.processEnvironment,
        'FLUOH_ANDROID_ADB': adb.path,
      },
    );
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
      flutterStdout: const {
        'devices --machine':
            '[{"id":"emulator-5554","name":"Pixel","targetPlatform":"android-arm64","isSupported":true,"emulator":true}]',
        'run -d emulator-5554 --debug --no-pub':
            'Flutter run key commands.\nApplication running.',
      },
    );
    await _writePackageManifest(environment.workingDirectory);
    await _writeFlutterPackage(environment.workingDirectory);
    await _writeFlutterExample(
      Directory('${environment.workingDirectory.path}/example'),
    );
    final scenario = File(
      '${environment.workingDirectory.path}/.fluoh/scenarios/camera/android-timeout.md',
    );
    await scenario.parent.create(recursive: true);
    await scenario.writeAsString('''
kind: fluoh.automationScenario
schema: 1
name: android timeout
platform: android
steps:
  - action: tapText
    labels: [Never appears]
    timeoutSeconds: 1
''');
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
          'drive',
          'android',
          '--package',
          'camera',
          '--scenario',
          scenario.path,
          '--log-duration',
          '0',
          '--json',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      1,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('ok', false));
    final target =
        (report['targets'] as List<Object?>).single as Map<String, Object?>;
    final steps = (target['steps'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final scenarioStep = steps.singleWhere(
      (step) => step['name'] == 'automation-scenario-android-android-timeout',
    );
    final scenarioDetails = scenarioStep['details'] as Map<String, Object?>;
    final actions = (scenarioDetails['actions'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final tapAction = actions.singleWhere(
      (action) => action['action'] == 'tapText',
    );
    final tapDetails = tapAction['details'] as Map<String, Object?>;
    expect(tapAction, containsPair('status', 'failed'));
    expect(tapAction, containsPair('reason', 'Could not dump Android UI'));
    expect(tapDetails, containsPair('exitCode', 124));
    expect(tapDetails['stderrTail'], contains('Command timed out.'));
    var timeoutMarkerText = '';
    for (var attempt = 0; attempt < 100; attempt += 1) {
      if (await timeoutMarker.exists()) {
        timeoutMarkerText = await timeoutMarker.readAsString();
        if (timeoutMarkerText.contains('terminated')) {
          break;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(timeoutMarkerText, contains('terminated'));
    expect(stderr, isEmpty);
  });

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

  test('web package run skips integration tests on web-server target', () async {
    final environment = await createTestEnvironment();
    final source = await _createWorkflowSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
      flutterStdout: const {
        'devices --machine':
            '[{"id":"chrome","name":"Chrome","targetPlatform":"web-javascript","isSupported":true},{"id":"web-server","name":"Web Server","targetPlatform":"web-javascript","isSupported":true}]',
        'run -d web-server --debug --no-pub':
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
      contains('$root/example::flutter run -d web-server --debug --no-pub'),
    );
    expect(
      invocations,
      isNot(
        contains('$root/example::flutter test integration_test -d web-server'),
      ),
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('ok', true));
    final targets = report['targets'] as List<Object?>;
    final target = targets.single as Map<String, Object?>;
    expect(target.containsKey('nextCommand'), isFalse);
    final steps = target['steps'] as List<Object?>;
    final integrationStep = steps.cast<Map<String, Object?>>().singleWhere(
      (step) => step['name'] == 'example-integration-web',
    );
    expect(
      integrationStep,
      containsPair(
        'command',
        'flutter test integration_test -d <browser-device>',
      ),
    );
    expect(integrationStep, containsPair('status', 'skipped'));
    expect(
      integrationStep,
      containsPair(
        'reason',
        'web-server target does not run browser integration tests',
      ),
    );
    expect(integrationStep.containsKey('nextCommand'), isFalse);
    final details = integrationStep['details'] as Map<String, Object?>;
    expect(details, containsPair('targetId', 'web-server'));
    expect(details, containsPair('requiredTargetKind', 'browser'));
    expect(
      details,
      containsPair(
        'suggestedCommand',
        'fluoh run web --package camera --device-id chrome --json',
      ),
    );
    final diagnostics = integrationStep['diagnostics'] as List<Object?>;
    final diagnostic = diagnostics.single as Map<String, Object?>;
    expect(
      diagnostic,
      containsPair('code', 'web.integration_target_unsupported'),
    );
    expect(diagnostic, containsPair('severity', 'info'));
    expect(diagnostic.containsKey('nextCommand'), isFalse);
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

  test('requires OHOS platform when automatic signing is requested', () async {
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
      contains('Use --auto-sign only with build platform ohos.'),
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
        ['run', 'ohos', '--session-file', '.fluoh/run-session.json'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );

    expect(
      stderr.join('\n'),
      contains(
        'Use --session-file only with Android, iOS, macOS, Linux, Web, or Windows runs.',
      ),
    );
  });
}

Future<void> _writePackageManifest(Directory repository) async {
  await File('${repository.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: package

sdk:
  version: 3.35.8-ohos-0.0.3

repository:
  git:
    url: git@github.com:FlutterOH/camera.git
    branch: ohos/3.35/camera

upstream:
  git:
    url: https://github.com/flutter/packages.git
    branch: main

package:
  name: camera
  path: .
  release:
    version: 0.1.0
    upstream:
      version: 0.11.0
      commit: "1111111111111111111111111111111111111111"
    status: experimental
''');
}

Future<void> _writeFlutterPackage(
  Directory directory, {
  bool withTests = true,
}) async {
  await Directory('${directory.path}/lib').create(recursive: true);
  await File(
    '${directory.path}/lib/camera.dart',
  ).writeAsString('library camera;\n');
  if (withTests) {
    await Directory('${directory.path}/test').create(recursive: true);
    await File('${directory.path}/test/camera_test.dart').writeAsString('''
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('camera fixture test', () {
    expect(true, isTrue);
  });
}
''');
  }
  await File('${directory.path}/pubspec.yaml').writeAsString('''
name: camera
version: 0.11.0

environment:
  sdk: ^3.0.0

dependencies:
  flutter:
    sdk: flutter

dev_dependencies:
  flutter_test:
    sdk: flutter
''');
}

Future<void> _writeFlutterExample(
  Directory directory, {
  bool withTests = true,
}) async {
  if (withTests) {
    await Directory('${directory.path}/test').create(recursive: true);
  } else {
    await directory.create(recursive: true);
  }
  await File('${directory.path}/pubspec.yaml').writeAsString('''
name: camera_example

environment:
  sdk: ^3.0.0

dependencies:
  flutter:
    sdk: flutter
  camera:
    path: ..

dev_dependencies:
  flutter_test:
    sdk: flutter
''');
  if (withTests) {
    await File('${directory.path}/test/widget_test.dart').writeAsString('''
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('camera example fixture test', () {
    expect(true, isTrue);
  });
}
''');
  }
}

Future<void> _writeWorkflowOhosProject(Directory project) async {
  final ohos = Directory('${project.path}/ohos');
  await Directory('${ohos.path}/AppScope').create(recursive: true);
  await Directory('${ohos.path}/entry/src/main').create(recursive: true);
  await File('${ohos.path}/AppScope/app.json5').writeAsString('''
{
  "app": {
    "bundleName": "com.example.camera"
  }
}
''');
  await File('${ohos.path}/entry/src/main/module.json5').writeAsString('''
{
  "module": {
    "name": "entry",
    "type": "entry",
    "mainElement": "EntryAbility",
    "abilities": [
      {
        "name": "EntryAbility",
        "exported": true,
        "skills": [
          {
            "entities": ["entity.system.home"],
            "actions": ["action.system.home"]
          }
        ]
      }
    ]
  }
}
''');
  await File('${ohos.path}/build-profile.json5').writeAsString('''
{
  "app": {
    "signingConfigs": [],
    "products": [
      {
        "name": "default",
        "compatibleSdkVersion": 18
      }
    ]
  }
}
''');
}

Future<void> _writeProjectSdkConfig(Directory directory) async {
  await File('${directory.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: project

sdk:
  version: 3.35.8-ohos-0.0.3
dependencyPolicy:
  pubspecSection: dependency_overrides
  versionChanges: compatible
''');
}

Future<void> _writeDartPackage(Directory directory) async {
  await Directory('${directory.path}/lib').create(recursive: true);
  await Directory('${directory.path}/test').create(recursive: true);
  await File(
    '${directory.path}/lib/camera.dart',
  ).writeAsString('library camera;\n');
  await File('${directory.path}/test/camera_test.dart').writeAsString('''
import 'package:test/test.dart';

void main() {
  test('camera fixture test', () {
    expect(true, isTrue);
  });
}
''');
  await File('${directory.path}/pubspec.yaml').writeAsString('''
name: camera
version: 0.11.0

environment:
  sdk: ^3.0.0

dev_dependencies:
  test: ^1.25.0
''');
}

Future<Directory> _createWorkflowSdkSource(
  Directory parent,
  Directory project, {
  Map<String, int> flutterFailures = const {},
  Map<String, List<int>> flutterExitCodeSequences = const {},
  Map<String, String> flutterStdout = const {},
  Map<String, List<String>> flutterStdoutSequences = const {},
  Map<String, String> flutterStderr = const {},
  Map<String, String> flutterSideEffects = const {},
  Map<String, int> dartFailures = const {},
}) async {
  final source = Directory('${parent.path}/package_workflow_source');
  final sdkRepository = Directory('${parent.path}/package_workflow_sdk');
  await sdkRepository.create(recursive: true);
  await _runProcess('git', ['init', '--initial-branch=main'], sdkRepository);
  await _runProcess('git', [
    'config',
    'user.email',
    'fixture@example.com',
  ], sdkRepository);
  await _runProcess('git', ['config', 'user.name', 'Fixture'], sdkRepository);
  await Directory('${sdkRepository.path}/bin').create(recursive: true);
  await _writeTool(
    File('${sdkRepository.path}/bin/flutter'),
    '${project.path}/package_workflow_invocations.txt',
    'flutter',
    failures: flutterFailures,
    exitCodeSequencesByCommand: flutterExitCodeSequences,
    stdoutByCommand: flutterStdout,
    stdoutSequencesByCommand: flutterStdoutSequences,
    stderrByCommand: flutterStderr,
    sideEffectsByCommand: flutterSideEffects,
  );
  await _writeTool(
    File('${sdkRepository.path}/bin/dart'),
    '${project.path}/package_workflow_invocations.txt',
    'dart',
    failures: dartFailures,
  );
  await File('${sdkRepository.path}/README.md').writeAsString('# SDK\n');
  await _runProcess('git', ['add', '.'], sdkRepository);
  await _runProcess('git', ['commit', '-m', 'Initial SDK'], sdkRepository);
  await _runProcess('git', ['tag', '3.35.8-ohos-0.0.3'], sdkRepository);
  await writeSdkSourceFixture(
    source,
    sdkRepository: sdkRepository.path,
    releases: {'3.35.8-ohos-0.0.3': 'stable'},
  );
  return source;
}

Future<void> _writeTool(
  File tool,
  String logPath,
  String name, {
  Map<String, int> failures = const {},
  Map<String, List<int>> exitCodeSequencesByCommand = const {},
  Map<String, String> stdoutByCommand = const {},
  Map<String, List<String>> stdoutSequencesByCommand = const {},
  Map<String, String> stderrByCommand = const {},
  Map<String, String> sideEffectsByCommand = const {},
}) async {
  final sequenceBuffer = StringBuffer();
  var sequenceIndex = 0;
  for (final entry in exitCodeSequencesByCommand.entries) {
    final countPath = '$logPath.$name.exit.$sequenceIndex.count';
    final cases = StringBuffer();
    for (var index = 0; index < entry.value.length; index += 1) {
      cases.writeln('    $index) exit_code=${entry.value[index]} ;;');
    }
    cases.writeln('    *) exit_code=${entry.value.last} ;;');
    final stdout = stdoutByCommand[entry.key];
    final stderr = stderrByCommand[entry.key];
    sequenceBuffer.writeln('''
if [ "\$*" = ${_shellSingleQuote(entry.key)} ]; then
  count_file=${_shellSingleQuote(countPath)}
  count=0
  if [ -f "\$count_file" ]; then
    count=\$(cat "\$count_file")
  fi
  next=\$((count + 1))
  printf "%s\\n" "\$next" > "\$count_file"
  case "\$count" in
$cases  esac
${stdout == null ? '' : '  printf "%s\\\\n" ${_shellSingleQuote(stdout)}'}
${stderr == null ? '' : '  printf "%s\\\\n" ${_shellSingleQuote(stderr)} >&2'}
  exit "\$exit_code"
fi
''');
    sequenceIndex += 1;
  }
  for (final entry in stdoutSequencesByCommand.entries) {
    final countPath = '$logPath.$name.$sequenceIndex.count';
    final cases = StringBuffer();
    for (var index = 0; index < entry.value.length; index += 1) {
      cases.writeln(
        '    $index) printf "%s\\\\n" '
        '${_shellSingleQuote(entry.value[index])} ;;',
      );
    }
    cases.writeln(
      '    *) printf "%s\\\\n" ${_shellSingleQuote(entry.value.last)} ;;',
    );
    sequenceBuffer.writeln('''
if [ "\$*" = ${_shellSingleQuote(entry.key)} ]; then
  count_file=${_shellSingleQuote(countPath)}
  count=0
  if [ -f "\$count_file" ]; then
    count=\$(cat "\$count_file")
  fi
  next=\$((count + 1))
  printf "%s\\n" "\$next" > "\$count_file"
  case "\$count" in
$cases  esac
  exit ${failures[entry.key] ?? 0}
fi
''');
    sequenceIndex += 1;
  }
  final commandOutputs = stdoutByCommand.entries.map((entry) {
    final stderr = stderrByCommand[entry.key];
    final sideEffect = sideEffectsByCommand[entry.key];
    return '''
if [ "\$*" = ${_shellSingleQuote(entry.key)} ]; then
${sideEffect == null ? '' : '$sideEffect\n'}
  printf "%s\\n" ${_shellSingleQuote(entry.value)}
${stderr == null ? '' : '  printf "%s\\\\n" ${_shellSingleQuote(stderr)} >&2'}
  exit ${failures[entry.key] ?? 0}
fi
''';
  }).join();
  final failureChecks = failures.entries
      .where(
        (entry) =>
            !stdoutByCommand.containsKey(entry.key) &&
            !exitCodeSequencesByCommand.containsKey(entry.key) &&
            !stdoutSequencesByCommand.containsKey(entry.key),
      )
      .map(
        (entry) =>
            '''
if [ "\$*" = ${_shellSingleQuote(entry.key)} ]; then
  exit ${entry.value}
fi
''',
      )
      .join();
  await tool.parent.create(recursive: true);
  final sideEffectChecks = sideEffectsByCommand.entries
      .where(
        (entry) =>
            !stdoutByCommand.containsKey(entry.key) &&
            !exitCodeSequencesByCommand.containsKey(entry.key) &&
            !stdoutSequencesByCommand.containsKey(entry.key),
      )
      .map(
        (entry) =>
            '''
if [ "\$*" = ${_shellSingleQuote(entry.key)} ]; then
${entry.value}
  exit ${failures[entry.key] ?? 0}
fi
''',
      )
      .join();
  await tool.writeAsString('''
#!/bin/sh
printf "%s::$name %s\\n" "\$(pwd)" "\$*" >> "$logPath"
$sequenceBuffer
$commandOutputs
printf "$name stdout\\n"
printf "$name stderr\\n" >&2
$sideEffectChecks
$failureChecks
exit 0
''');
  await _runProcess('chmod', ['+x', tool.path], tool.parent);
}

Future<Directory> _writeWorkflowDevEcoFixture(
  Directory root, {
  required File hdcLog,
  String targets = 'emulator-5554\n',
  int hdcListTargetsExitCode = 0,
  String hdcListTargetsStderr = '',
  int hdcInstallExitCode = 1,
  String hdcInstallStdout = '',
  String hdcInstallStderr = '',
  int hdcLaunchExitCode = 1,
  String hdcLaunchStdout = '',
  String hdcLaunchStderr = '',
  String hdcHilogStdout = '',
  String hdcAppDeniedLayout = '',
  String hdcPermissionDialogLayout = '',
  String hdcAppGrantedLayout = '',
}) async {
  final devEco = Directory('${root.path}/DevEco-Studio.app');
  final openHarmony = Directory(
    '${devEco.path}/Contents/sdk/default/openharmony',
  );
  final toolchains = Directory('${openHarmony.path}/toolchains');
  final lib = Directory('${toolchains.path}/lib');
  final jbr = Directory('${devEco.path}/Contents/jbr/Contents/Home/bin');
  final node = Directory('${devEco.path}/Contents/tools/node/bin');
  final emulatorDirectory = Directory('${devEco.path}/Contents/tools/emulator');
  await Directory(
    '${openHarmony.path}/previewer/common/resources',
  ).create(recursive: true);
  await lib.create(recursive: true);
  await jbr.create(recursive: true);
  await node.create(recursive: true);
  await emulatorDirectory.create(recursive: true);
  await File('${lib.path}/hap-sign-tool.jar').writeAsString('');
  await File('${lib.path}/OpenHarmony.p12').writeAsString('');
  await File('${lib.path}/OpenHarmonyProfileDebug.pem').writeAsString('');
  await File(
    '${openHarmony.path}/previewer/common/resources/module.json',
  ).writeAsString('{"definePermissions": []}');

  final fakeKeytool = File('${root.path}/fake_keytool');
  await _writeExecutable(fakeKeytool, r'''
#!/usr/bin/env python3
import sys

args = sys.argv[1:]
if "-file" in args:
    index = args.index("-file")
    if index + 1 < len(args):
        with open(args[index + 1], "w", encoding="utf-8") as out:
            out.write("-----BEGIN CERTIFICATE-----\nfixture\n-----END CERTIFICATE-----\n")
''');
  await Link('${jbr.path}/keytool').create(fakeKeytool.path);
  final fakeJava = File('${root.path}/fake_java');
  await _writeExecutable(fakeJava, r'''
#!/usr/bin/env python3
import sys

args = sys.argv[1:]
if "-keystoreFile" in args:
    index = args.index("-keystoreFile")
    if index + 1 < len(args):
        with open(args[index + 1], "w", encoding="utf-8") as store:
            store.write("keystore\n")
if "-outFile" in args:
    index = args.index("-outFile")
    if index + 1 < len(args):
        with open(args[index + 1], "w", encoding="utf-8") as out:
            out.write("-----BEGIN CERTIFICATE-----\nfixture\n-----END CERTIFICATE-----\n")
''');
  await Link('${jbr.path}/java').create(fakeJava.path);
  final fakeNode = File('${root.path}/fake_node');
  await _writeExecutable(fakeNode, '''
#!/bin/sh
printf "00112233445566778899aabbccddeeff\\n"
exit 0
''');
  await Link('${node.path}/node').create(fakeNode.path);
  final fakeHdc = File('${root.path}/fake_hdc');
  await _writeExecutable(fakeHdc, '''
#!/usr/bin/env python3
import sys

log_path = ${jsonEncode(hdcLog.path)}
targets = ${jsonEncode(targets)}
list_targets_exit_code = $hdcListTargetsExitCode
list_targets_stderr = ${jsonEncode(hdcListTargetsStderr)}
install_exit_code = $hdcInstallExitCode
install_stdout = ${jsonEncode(hdcInstallStdout)}
install_stderr = ${jsonEncode(hdcInstallStderr)}
launch_exit_code = $hdcLaunchExitCode
launch_stdout = ${jsonEncode(hdcLaunchStdout)}
launch_stderr = ${jsonEncode(hdcLaunchStderr)}
hilog_stdout = ${jsonEncode(hdcHilogStdout)}
app_denied_layout = ${jsonEncode(hdcAppDeniedLayout)}
permission_dialog_layout = ${jsonEncode(hdcPermissionDialogLayout)}
app_granted_layout = ${jsonEncode(hdcAppGrantedLayout)}
state_path = log_path + ".state"
args = sys.argv[1:]

with open(log_path, "a", encoding="utf-8") as log:
    log.write(" ".join(args) + "\\n")

def read_state():
    try:
        with open(state_path, "r", encoding="utf-8") as state:
            value = state.read().strip()
            if value:
                return value
    except FileNotFoundError:
        pass
    return "app_denied"

def write_state(value):
    with open(state_path, "w", encoding="utf-8") as state:
        state.write(value)

if len(args) >= 2 and args[0] == "list" and args[1] == "targets":
    sys.stdout.write(targets)
    sys.stderr.write(list_targets_stderr)
    raise SystemExit(list_targets_exit_code)

if "install" in args:
    sys.stdout.write(install_stdout)
    sys.stderr.write(install_stderr)
    raise SystemExit(install_exit_code)

if "aa" in args and "start" in args:
    if not read_state():
        write_state("app_denied")
    sys.stdout.write(launch_stdout)
    sys.stderr.write(launch_stderr)
    raise SystemExit(launch_exit_code)

if "aa" in args and "force-stop" in args:
    raise SystemExit(0)

if "bm" in args and "clean" in args:
    write_state("app_denied")
    sys.stdout.write("clean bundle data files successfully.\\n")
    raise SystemExit(0)

if "uitest" in args and "dumpLayout" in args:
    sys.stdout.write("DumpLayout saved to:/data/local/tmp/layout_fixture.json\\n")
    raise SystemExit(0)

if len(args) >= 2 and args[-2] == "cat" and args[-1] == "/data/local/tmp/layout_fixture.json":
    state = read_state()
    if state == "permission_dialog":
        sys.stdout.write(permission_dialog_layout)
    elif state == "app_granted":
        sys.stdout.write(app_granted_layout)
    else:
        sys.stdout.write(app_denied_layout)
    raise SystemExit(0)

if "uitest" in args and "click" in args:
    state = read_state()
    if state == "app_denied":
        write_state("permission_dialog")
    elif state == "permission_dialog":
        write_state("app_granted")
    raise SystemExit(0)

if "uitest" in args and "swipe" in args:
    raise SystemExit(0)

if "uitest" in args and "inputText" in args:
    raise SystemExit(0)

if "uitest" in args and "keyEvent" in args:
    raise SystemExit(0)

if "hilog" in args:
    sys.stdout.write(hilog_stdout)
    raise SystemExit(0)

raise SystemExit(1)
''');
  await Link('${toolchains.path}/hdc').create(fakeHdc.path);
  await _writeExecutable(File('${emulatorDirectory.path}/Emulator'), '''
#!/bin/sh
exit 0
''');
  return devEco;
}

String _ohosPermissionExampleLayout(String cameraStatus) {
  return jsonEncode({
    'attributes': {'bounds': '[0,0][1272,2756]'},
    'children': [
      {
        'attributes': {
          'bounds': '[0,563][1272,806]',
          'clickable': 'true',
          'text': 'Permission.camera\n$cameraStatus',
          'originalText': 'Permission.camera\n$cameraStatus',
          'type': 'Button',
        },
        'children': <Object?>[],
      },
    ],
  });
}

String _ohosPermissionDialogLayout() {
  return jsonEncode({
    'attributes': {'bounds': '[0,0][1272,2756]'},
    'children': [
      {
        'attributes': {
          'bounds': '[108,1582][608,1717]',
          'clickable': 'true',
          'id': 'permission_dialog_deny_button',
          'key': 'permission_dialog_deny_button',
          'type': 'Button',
        },
        'children': [
          {
            'attributes': {
              'bounds': '[277,1618][439,1681]',
              'text': '不允许',
              'originalText': '不允许',
              'type': 'Text',
            },
            'children': <Object?>[],
          },
        ],
      },
      {
        'attributes': {
          'bounds': '[664,1582][1164,1717]',
          'clickable': 'true',
          'id': 'permission_dialog_primary_button',
          'key': 'permission_dialog_primary_button',
          'type': 'Button',
        },
        'children': [
          {
            'attributes': {
              'bounds': '[760,1618][1068,1681]',
              'text': '本次使用允许',
              'originalText': '本次使用允许',
              'type': 'Text',
            },
            'children': <Object?>[],
          },
        ],
      },
    ],
  });
}

Future<void> _writeExecutable(File file, String content) async {
  await file.parent.create(recursive: true);
  await file.writeAsString(content);
  await _runProcess('chmod', ['+x', file.path], file.parent);
}

Future<Directory> _writeAndroidSdkFixture(
  Directory root,
  String logPath, {
  String avds = 'Pixel_35',
  Map<String, int> emulatorFailures = const {},
}) async {
  final sdk = Directory('${root.path}/android-sdk');
  await _writeTool(
    File('${sdk.path}/emulator/emulator'),
    logPath,
    'android-emulator',
    failures: emulatorFailures,
    stdoutByCommand: {'-list-avds': avds},
  );
  return sdk;
}

Future<File> _writeAndroidAdbFixture(
  Directory root,
  String logPath, {
  required String uiXml,
  required String logcat,
}) async {
  final adb = File('${root.path}/adb');
  await _writeExecutable(adb, '''
#!/bin/sh
printf "%s\\n" "\$*" >> ${_shellSingleQuote(logPath)}
if [ "\$1" = "-s" ]; then
  shift 2
fi

case "\$*" in
  "shell pm clear com.example.camera")
    exit 0
    ;;
  "shell monkey -p com.example.camera -c android.intent.category.LAUNCHER 1")
    exit 0
    ;;
  "shell uiautomator dump /sdcard/fluoh-window.xml")
    printf "%s\\n" "UI hierarchy dumped to /sdcard/fluoh-window.xml"
    exit 0
    ;;
  "exec-out cat /sdcard/fluoh-window.xml")
    printf "%s\\n" ${_shellSingleQuote(uiXml)}
    exit 0
    ;;
  "shell input tap 60 50")
    exit 0
    ;;
  "shell input swipe 10 20 30 40 250")
    exit 0
    ;;
  "logcat -d -t 200")
    printf "%s\\n" ${_shellSingleQuote(logcat)}
    exit 0
    ;;
esac

printf "%s\\n" "unsupported adb \$*" >&2
exit 1
''');
  return adb;
}

Future<File> _writeXcrunFixture(
  Directory root,
  String logPath, {
  bool supportsXCTest = false,
  bool iosAppInstalled = true,
  String? simctlDevicesJson,
  String? bootSimulatorId,
}) async {
  final xcrun = File('${root.path}/xcrun');
  await _writeExecutable(xcrun, '''
#!/bin/sh
printf "%s\\n" "\$*" >> ${_shellSingleQuote(logPath)}

case "\$*" in
${simctlDevicesJson == null ? '' : '''
  "simctl list devices available --json")
    cat <<'JSON'
$simctlDevicesJson
JSON
    exit 0
    ;;
'''}
${bootSimulatorId == null ? '' : '''
  "simctl boot $bootSimulatorId")
    exit 0
    ;;
  "simctl bootstatus $bootSimulatorId -b")
    exit 0
    ;;
'''}
  simctl\\ get_app_container\\ ios-sim\\ *\\ app)
${iosAppInstalled ? '''
    printf "%s\\n" "/tmp/Runner.app"
    exit 0
''' : '''
    printf "%s\\n" "No such file or directory" >&2
    exit 1
'''}
    ;;
  simctl\\ install\\ ios-sim\\ *)
    exit 0
    ;;
  simctl\\ launch\\ ios-sim\\ *)
    printf "%s\\n" "com.example.camera: 12345"
    exit 0
    ;;
  "simctl privacy ios-sim reset camera com.example.camera")
    exit 0
    ;;
  "simctl privacy ios-sim grant camera com.example.camera")
    exit 0
    ;;
${supportsXCTest ? '''
  xcodebuild\\ test*)
    printf "%s\\n" "Test Suite 'PermissionPromptUITests' passed"
    exit 0
    ;;
''' : ''}
esac

printf "%s\\n" "unsupported xcrun \$*" >&2
exit 1
''');
  return xcrun;
}

String _shellSingleQuote(String value) {
  return "'${value.replaceAll("'", "'\"'\"'")}'";
}

Future<void> _runProcess(
  String executable,
  List<String> arguments,
  Directory workingDirectory,
) async {
  final result = await Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory.path,
  );
  if (result.exitCode != 0) {
    fail('$executable ${arguments.join(' ')} failed:\n${result.stderr}');
  }
}
