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

  test('top-level verify runs package workflows', () async {
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
      contains(
        'fluoh run --platform ohos --package camera --auto-emulator --json',
      ),
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
        ['build', '--platform', 'android', '--json', '--trace-dir', traceDir],
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

  test('top-level build runs a package example build', () async {
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
        ['build', '--platform', 'android', '--json'],
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
        ['build', '--platform', 'ohos', '--debug', '--json'],
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
          ['run', '--platform', 'ohos', '--json'],
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
          'fluoh run --platform ohos --package camera --auto-emulator --json',
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
          ['run', '--platform', 'ohos', '--json'],
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
        ['run', '--platform', 'ohos', '--json'],
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
        ['run', '--platform', 'ohos', '--log-duration', '0', '--json'],
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
        ['run', '--platform', 'ohos', '--json'],
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
        'fluoh run --platform ohos --package camera --auto-emulator --json',
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
        ['build', '--platform', 'android', '--debug', '--json'],
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
        ['build', '--platform', 'ios', '--debug', '--json'],
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
        ['build', '--platform', 'macos', '--debug', '--json'],
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
            ['build', '--platform', platform, '--debug', '--json'],
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
        ['build', '--platform', 'android', '--debug', '--json'],
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
        ['build', '--platform', 'ios', '--debug', '--json'],
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

  test('emits platform diagnostics for failed project builds', () async {
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
        ['build', '--platform', 'ohos', '--json'],
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
    expect(
      diagnostic,
      containsPair('nextCommand', 'fluoh build --platform ohos --json'),
    );
    final details = diagnostic['details'] as Map<String, Object?>;
    expect(details, containsPair('command', 'flutter build hap --debug'));
    expect(details, containsPair('stdoutTail', contains('flutter stdout')));
    expect(details, containsPair('stderrTail', contains('flutter stderr')));
    expect(
      buildStep,
      containsPair('nextCommand', 'fluoh build --platform ohos --json'),
    );
    expect(
      target,
      containsPair('nextCommand', 'fluoh build --platform ohos --json'),
    );
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
        ['build', '--platform', 'ohos', '--auto-sign', '--json'],
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
        ['build', '--platform', 'ohos', '--json'],
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
        ['run', '--platform', 'ohos', '--json'],
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
        ['run', '--platform', 'ohos', '--json'],
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
        ['run', '--platform', 'ios', '--device', 'ios-sim', '--json'],
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
      containsPair(
        'nextCommand',
        'fluoh run --platform ios --device ios-sim --json',
      ),
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
        ['run', '--platform', 'android', '--device', 'emulator-5554', '--json'],
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
          [
            'run',
            '--platform',
            'android',
            '--device',
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
          'fluoh run --platform android --device emulator-5554 --json',
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
          'fluoh run --platform android --device emulator-5554 --json',
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
          'fluoh run --platform android --device emulator-5554 --json',
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
        ['run', '--platform', 'android', '--emulator', 'Pixel_35', '--json'],
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
          ['run', '--platform', 'android', '--auto-emulator', '--json'],
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
        ['run', '--platform', 'android', '--auto-emulator', '--json'],
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
          ['run', '--platform', 'android', '--auto-emulator', '--json'],
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
          ['run', '--platform', 'android', '--auto-emulator', '--json'],
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
        ['run', '--platform', 'linux', '--auto-emulator', '--json'],
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
        ['run', '--platform', 'web', '--auto-emulator', '--json'],
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
          ['run', '--platform', 'linux', '--auto-emulator', '--json'],
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
      expect(
        diagnostic,
        containsPair('nextCommand', 'fluoh run --platform linux --json'),
      );
      stdout.clear();
      stderr.clear();

      expect(
        await runFluoh(
          ['run', '--platform', 'web', '--auto-emulator', '--json'],
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
          'fluoh run --platform web --device web-server --json',
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
        ['run', '--platform', 'android', '--emulator', 'Pixel_35', '--json'],
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
        'fluoh run --platform android --emulator Pixel_35 --json',
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
          '--platform',
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

  test('package run integration test failure preserves device next command', () async {
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
          '--platform',
          'android',
          '--package',
          'camera',
          '--device',
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
        'fluoh run --platform android --package camera --device emulator-5554 --json',
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
        'fluoh run --platform android --package camera --device emulator-5554 --json',
      ),
    );
    final diagnostics = integrationStep['diagnostics'] as List<Object?>;
    final diagnostic = diagnostics.single as Map<String, Object?>;
    expect(diagnostic, containsPair('code', 'android.integration_test_failed'));
    expect(
      diagnostic,
      containsPair(
        'nextCommand',
        'fluoh run --platform android --package camera --device emulator-5554 --json',
      ),
    );
    expect(stderr, isEmpty);
  });

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
        ['run', '--platform', 'web', '--json'],
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
        'fluoh run --platform web --package camera --device chrome --json',
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
        ['run', '--platform', 'macos', '--json'],
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
          [
            'run',
            '--platform',
            'android',
            '--device',
            'emulator-5554',
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
        ['run', '--platform', 'android', '--device', 'emulator-5554', '--json'],
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
          ['run', '--platform', 'android', '--emulator', 'Pixel_35', '--json'],
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
        ['run', '--platform', 'android', '--json'],
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
        'fluoh run --platform android --package camera --auto-emulator --json',
      ),
    );
    expect(
      runStep,
      containsPair(
        'nextCommand',
        'fluoh run --platform android --package camera --auto-emulator --json',
      ),
    );
    expect(
      target,
      containsPair(
        'nextCommand',
        'fluoh run --platform android --package camera --auto-emulator --json',
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
        ['run', '--platform', 'ios', '--json'],
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
        'fluoh run --platform ios --package camera --auto-emulator --json',
      ),
    );
    expect(
      runStep,
      containsPair(
        'nextCommand',
        'fluoh run --platform ios --package camera --auto-emulator --json',
      ),
    );
    expect(
      target,
      containsPair(
        'nextCommand',
        'fluoh run --platform ios --package camera --auto-emulator --json',
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
        ['build', '--platform', 'ohos', '--auto-sign', '--json'],
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
        ['build', '--platform', 'android', '--auto-sign'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );

    expect(
      stderr.join('\n'),
      contains('Use --auto-sign only with --platform ohos.'),
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
          '--platform',
          'android',
          '--device',
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
      contains('Use only one of --device or --emulator.'),
    );
  });

  test('does not allow auto emulator with explicit run target', () async {
    final environment = await createTestEnvironment();
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        [
          'run',
          '--platform',
          'android',
          '--device',
          'emulator-5554',
          '--auto-emulator',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );
    expect(
      stderr.join('\n'),
      contains('Use only one of --device or --auto-emulator.'),
    );

    stdout.clear();
    stderr.clear();

    expect(
      await runFluoh(
        [
          'run',
          '--platform',
          'android',
          '--emulator',
          'Pixel',
          '--auto-emulator',
        ],
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
        ['run', '--platform', 'android', '--device-timeout', 'not-seconds'],
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
        [
          'run',
          '--platform',
          'ohos',
          '--session-file',
          '.fluoh/run-session.json',
        ],
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
  Map<String, String> stdoutByCommand = const {},
  Map<String, List<String>> stdoutSequencesByCommand = const {},
  Map<String, String> stderrByCommand = const {},
  Map<String, String> sideEffectsByCommand = const {},
}) async {
  final sequenceBuffer = StringBuffer();
  var sequenceIndex = 0;
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
args = sys.argv[1:]

with open(log_path, "a", encoding="utf-8") as log:
    log.write(" ".join(args) + "\\n")

if len(args) >= 2 and args[0] == "list" and args[1] == "targets":
    sys.stdout.write(targets)
    sys.stderr.write(list_targets_stderr)
    raise SystemExit(list_targets_exit_code)

if "install" in args:
    sys.stdout.write(install_stdout)
    sys.stderr.write(install_stderr)
    raise SystemExit(install_exit_code)

if "aa" in args and "start" in args:
    sys.stdout.write(launch_stdout)
    sys.stderr.write(launch_stderr)
    raise SystemExit(launch_exit_code)

if args and args[-1] == "hilog":
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
