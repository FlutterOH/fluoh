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
    expect(report, containsPair('schemaVersion', 1));
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
        ['run', '--platform', 'android', '--json'],
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
        'fluoh run --platform android --package camera --json',
      ),
    );
    expect(
      runStep,
      containsPair(
        'nextCommand',
        'fluoh run --platform android --package camera --json',
      ),
    );
    expect(
      target,
      containsPair(
        'nextCommand',
        'fluoh run --platform android --package camera --json',
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
        'fluoh run --platform ios --package camera --json',
      ),
    );
    expect(
      runStep,
      containsPair(
        'nextCommand',
        'fluoh run --platform ios --package camera --json',
      ),
    );
    expect(
      target,
      containsPair(
        'nextCommand',
        'fluoh run --platform ios --package camera --json',
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
}

Future<void> _writePackageManifest(Directory repository) async {
  await File('${repository.path}/fluoh.yaml').writeAsString('''
schema: 1
name: camera

sdk:
  version: 3.35.8-ohos-0.0.3

repository:
  git:
    url: git@github.com:FlutterOH/camera.git
    branch: ohos/3.35

upstream:
  git:
    url: https://github.com/flutter/packages.git
    branch: main

packages:
  camera:
    version: 0.1.0
    upstreamVersion: 0.11.0
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

sdk:
  version: 3.35.8-ohos-0.0.3
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

  await _writeExecutable(File('${jbr.path}/keytool'), '''
#!/bin/sh
out=""
while [ "\$#" -gt 0 ]; do
  if [ "\$1" = "-file" ]; then
    shift
    out="\$1"
  fi
  shift
done
if [ -n "\$out" ]; then
  printf "%s\\n%s\\n%s\\n" "-----BEGIN CERTIFICATE-----" "fixture" "-----END CERTIFICATE-----" > "\$out"
fi
exit 0
''');
  await _writeExecutable(File('${jbr.path}/java'), '''
#!/bin/sh
out=""
store=""
while [ "\$#" -gt 0 ]; do
  case "\$1" in
    -outFile)
      shift
      out="\$1"
      ;;
    -keystoreFile)
      shift
      store="\$1"
      ;;
  esac
  shift
done
if [ -n "\$store" ]; then
  printf "keystore\\n" > "\$store"
fi
if [ -n "\$out" ]; then
  printf "%s\\n%s\\n%s\\n" "-----BEGIN CERTIFICATE-----" "fixture" "-----END CERTIFICATE-----" > "\$out"
fi
exit 0
''');
  await _writeExecutable(File('${node.path}/node'), '''
#!/bin/sh
printf "00112233445566778899aabbccddeeff\\n"
exit 0
''');
  await _writeExecutable(File('${toolchains.path}/hdc'), '''
#!/bin/sh
printf "%s\\n" "\$*" >> "${hdcLog.path}"
if [ "\$1" = "list" ] && [ "\$2" = "targets" ]; then
  printf "emulator-5554\\n"
  exit 0
fi
exit 1
''');
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
  String logPath,
) async {
  final sdk = Directory('${root.path}/android-sdk');
  await _writeTool(
    File('${sdk.path}/emulator/emulator'),
    logPath,
    'android-emulator',
    stdoutByCommand: const {'-list-avds': 'Pixel_35'},
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
