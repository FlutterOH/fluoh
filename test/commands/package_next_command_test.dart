import 'dart:convert';
import 'dart:io';

import 'package:fluoh/fluoh.dart';
import 'package:test/test.dart';

import '../helpers/fluoh_command_context.dart';
import '../helpers/package_test_context.dart';

void main() {
  test('package next asks to review generated package spec first', () async {
    final environment = await createTestEnvironment();
    final packageRepository = await createPackageRepositoryFixture(
      environment,
      reviewSpec: false,
    );
    final packageEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['package', 'next', '--package', 'camera', '--json'],
        environment: packageEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final result = jsonDecode(stdout.single) as Map<String, Object?>;
    final spec = result['spec'] as Map<String, Object?>;
    expect(spec, containsPair('exists', true));
    expect(spec, containsPair('reviewRequired', true));
    final issues = spec['issues'] as List<Object?>;
    expect(
      issues,
      contains(
        isA<Map<String, Object?>>().having(
          (issue) => issue['code'],
          'code',
          'spec.generated_todos_remaining',
        ),
      ),
    );
    final nextAction = result['nextAction'] as Map<String, Object?>;
    expect(nextAction, containsPair('type', 'editRequired'));
    expect(nextAction, containsPair('phase', 'spec-review'));
    final requiredEdits = nextAction['requiredEdits'] as List<Object?>;
    expect(
      requiredEdits,
      contains(
        isA<Map<String, Object?>>()
            .having((edit) => edit['target'], 'target', 'packageSpec')
            .having((edit) => edit['path'], 'path', 'doc/fluoh/camera/spec.md'),
      ),
    );
    final remainingRisks = result['remainingRisks'] as List<Object?>;
    expect(
      remainingRisks,
      contains(
        isA<Map<String, Object?>>().having(
          (risk) => risk['code'],
          'code',
          'spec.review_required',
        ),
      ),
    );
    expect(stderr, isEmpty);
  });

  test(
    'package next asks to replace package spec template placeholders',
    () async {
      final environment = await createTestEnvironment();
      final packageRepository = await createPackageRepositoryFixture(
        environment,
      );
      final specFile = File(
        '${packageRepository.path}/doc/fluoh/camera/spec.md',
      );
      await specFile.writeAsString(
        '${await specFile.readAsString()}\n- SPEC-TODO: Replace template placeholder.\n',
      );
      final packageEnvironment = FluohEnvironment(
        homeDirectory: environment.homeDirectory,
        workingDirectory: packageRepository,
      );
      final stdout = <String>[];
      final stderr = <String>[];

      expect(
        await runFluoh(
          ['package', 'next', '--package', 'camera', '--json'],
          environment: packageEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final result = jsonDecode(stdout.single) as Map<String, Object?>;
      final spec = result['spec'] as Map<String, Object?>;
      expect(spec, containsPair('reviewRequired', true));
      final issues = spec['issues'] as List<Object?>;
      expect(
        issues,
        contains(
          isA<Map<String, Object?>>().having(
            (issue) => issue['code'],
            'code',
            'spec.template_placeholders_remaining',
          ),
        ),
      );
      final nextAction = result['nextAction'] as Map<String, Object?>;
      expect(nextAction, containsPair('type', 'editRequired'));
      expect(nextAction, containsPair('phase', 'spec-review'));
      expect(stderr, isEmpty);
    },
  );

  test('package next asks to initialize support scope first', () async {
    final environment = await createTestEnvironment();
    final packageRepository = await createPackageRepositoryFixture(environment);
    final packageEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['package', 'next', '--package', 'camera', '--json'],
        environment: packageEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final result = jsonDecode(stdout.single) as Map<String, Object?>;
    final scope = result['supportScope'] as Map<String, Object?>;
    expect(scope, containsPair('exists', false));
    final nextAction = result['nextAction'] as Map<String, Object?>;
    expect(nextAction, containsPair('type', 'commandRequired'));
    expect(nextAction, containsPair('phase', 'scope'));
    expect(
      nextAction,
      containsPair(
        'command',
        'fluoh package scope init --package camera --json',
      ),
    );
    final remainingRisks = result['remainingRisks'] as List<Object?>;
    expect(
      remainingRisks,
      contains(
        isA<Map<String, Object?>>().having(
          (risk) => risk['code'],
          'code',
          'scope.missing',
        ),
      ),
    );
    expect(stderr, isEmpty);
  });

  test('package next starts support with package verification', () async {
    final environment = await createTestEnvironment();
    final packageRepository = await createPackageRepositoryFixture(environment);
    await _writePlanningNotes(packageRepository);
    final packageEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['package', 'next', '--package', 'camera', '--json'],
        environment: packageEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final result = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(result, containsPair('command', 'package next'));
    expect(result, containsPair('ok', true));
    expect(result, containsPair('state', 'actionRequired'));
    expect(result, containsPair('stage', 'support'));
    final scope = result['supportScope'] as Map<String, Object?>;
    expect(scope, containsPair('planningReady', true));
    expect(scope, containsPair('functionalEvidenceReady', false));
    final qualityProfile = result['qualityProfile'] as Map<String, Object?>;
    expect(qualityProfile, containsPair('hasFunctionalSurface', false));
    expect(qualityProfile, containsPair('launchOnlyRisk', isA<bool>()));
    final testSurfaces = qualityProfile['testSurfaces'] as Map<String, Object?>;
    expect(testSurfaces, containsPair('exampleIntegrationTestFiles', 0));
    expect(testSurfaces, containsPair('automationScenarioFiles', isEmpty));
    final evidenceSummary = result['evidenceSummary'] as Map<String, Object?>;
    expect(evidenceSummary, containsPair('traceFound', false));
    expect(evidenceSummary, containsPair('reportCreated', false));
    expect(evidenceSummary['completedPhases'], isEmpty);
    expect(
      evidenceSummary['missingPhases'],
      containsAll(<String>[
        'verify',
        'ohos-build',
        'ohos-run',
        'automation-dry-run',
        'automation-run',
      ]),
    );
    final failureStreak = result['failureStreak'] as Map<String, Object?>;
    expect(failureStreak, containsPair('count', 0));
    expect(failureStreak, containsPair('blocking', false));
    final remainingRisks = result['remainingRisks'] as List<Object?>;
    expect(
      remainingRisks,
      contains(
        isA<Map<String, Object?>>().having(
          (risk) => risk['code'],
          'code',
          'evidence.trace_missing',
        ),
      ),
    );
    expect(
      remainingRisks,
      contains(
        isA<Map<String, Object?>>()
            .having(
              (risk) => risk['code'],
              'code',
              'quality.functional_surface_missing',
            )
            .having(
              (risk) => risk['exploratoryCommand'],
              'exploratoryCommand',
              contains('--profile exploratory-smoke'),
            )
            .having(
              (risk) => risk['scenarioCommand'],
              'scenarioCommand',
              contains('new_scenario.py'),
            ),
      ),
    );
    final nextAction = result['nextAction'] as Map<String, Object?>;
    expect(nextAction, containsPair('type', 'commandRequired'));
    expect(nextAction, containsPair('phase', 'verify'));
    expect(
      nextAction,
      containsPair(
        'command',
        allOf(
          startsWith('fluoh verify --package camera --json --trace-dir '),
          contains('.fluoh/tasks/'),
          endsWith('/traces/support'),
        ),
      ),
    );
    expect(
      nextAction,
      containsPair(
        'rerunCommand',
        'fluoh package next --package camera --json',
      ),
    );
    expect(stderr, isEmpty);
  });

  test('package next reports functional verification surfaces', () async {
    final environment = await createTestEnvironment();
    final packageRepository = await createPackageRepositoryFixture(environment);
    await _writePlanningNotes(packageRepository);
    await _writeExampleIntegrationTest(packageRepository);
    await _writeScenario(packageRepository);
    final packageEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['package', 'next', '--package', 'camera', '--json'],
        environment: packageEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final result = jsonDecode(stdout.single) as Map<String, Object?>;
    final qualityProfile = result['qualityProfile'] as Map<String, Object?>;
    expect(qualityProfile, containsPair('hasFunctionalSurface', true));
    expect(
      qualityProfile['interactionEvidenceMethods'],
      containsAll(<String>['example_integration_test', 'fluoh_scenario']),
    );
    final testSurfaces = qualityProfile['testSurfaces'] as Map<String, Object?>;
    expect(testSurfaces, containsPair('exampleIntegrationTestFiles', 1));
    expect(
      testSurfaces['automationScenarioFiles'],
      contains('doc/fluoh/camera/scenarios/ohos-functional.md'),
    );
    final remainingRisks = result['remainingRisks'] as List<Object?>;
    expect(
      remainingRisks,
      isNot(
        contains(
          isA<Map<String, Object?>>().having(
            (risk) => risk['code'],
            'code',
            'quality.functional_surface_missing',
          ),
        ),
      ),
    );
    expect(stderr, isEmpty);
  });

  test('package next reports existing example platform surfaces', () async {
    final environment = await createTestEnvironment();
    final packageRepository = await createPackageRepositoryFixture(environment);
    await _writePlanningNotes(packageRepository);
    await _writeExistingExamplePlatforms(packageRepository, ['android', 'web']);
    final packageEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['package', 'next', '--package', 'camera', '--json'],
        environment: packageEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final result = jsonDecode(stdout.single) as Map<String, Object?>;
    final qualityProfile = result['qualityProfile'] as Map<String, Object?>;
    final example = qualityProfile['example'] as Map<String, Object?>;
    expect(
      example['existingPlatforms'],
      containsAllInOrder(<String>['android', 'web']),
    );
    final evidenceSummary = result['evidenceSummary'] as Map<String, Object?>;
    expect(
      evidenceSummary['missingPhases'],
      containsAll(<String>[
        'existing-android-regression',
        'existing-android-automation-dry-run',
        'existing-android-automation-run',
        'existing-web-regression',
      ]),
    );
    final remainingRisks = result['remainingRisks'] as List<Object?>;
    expect(
      remainingRisks,
      contains(
        isA<Map<String, Object?>>()
            .having(
              (risk) => risk['code'],
              'code',
              'quality.existing_platform_regression_missing',
            )
            .having(
              (risk) => risk['platforms'],
              'platforms',
              containsAll(<String>['android', 'web']),
            ),
      ),
    );
    expect(stderr, isEmpty);
  });

  test('package next reports package-root scenario surfaces', () async {
    final environment = await createTestEnvironment();
    final packageRepository = await createPackageRepositoryFixture(environment);
    await _writePlanningNotes(packageRepository);
    await _movePackagePath(packageRepository, 'packages/camera');
    await _writePackageRootScenario(packageRepository, 'packages/camera');
    final packageEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['package', 'next', '--package', 'camera', '--json'],
        environment: packageEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final result = jsonDecode(stdout.single) as Map<String, Object?>;
    final qualityProfile = result['qualityProfile'] as Map<String, Object?>;
    expect(qualityProfile, containsPair('hasFunctionalSurface', true));
    expect(
      qualityProfile['interactionEvidenceMethods'],
      contains('fluoh_scenario'),
    );
    final testSurfaces = qualityProfile['testSurfaces'] as Map<String, Object?>;
    expect(
      testSurfaces['automationScenarioFiles'],
      contains('packages/camera/doc/fluoh/camera/scenarios/ohos-functional.md'),
    );
    expect(stderr, isEmpty);
  });

  test('package next advances after passed verification trace', () async {
    final environment = await createTestEnvironment();
    final packageRepository = await createPackageRepositoryFixture(environment);
    await _writePlanningNotes(packageRepository);
    await _writeTrace(packageRepository, [
      {
        'commandLine':
            'fluoh verify --package camera --json --trace-dir .fluoh/tasks/test-packageSupport-camera/traces/support',
        'ok': true,
        'exitCode': 0,
        'result': {},
      },
    ]);
    final packageEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['package', 'next', '--json'],
        environment: packageEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final result = jsonDecode(stdout.single) as Map<String, Object?>;
    final nextAction = result['nextAction'] as Map<String, Object?>;
    expect(nextAction, containsPair('type', 'commandRequired'));
    expect(nextAction, containsPair('phase', 'ohos-build'));
    expect(
      nextAction,
      containsPair(
        'command',
        'fluoh build ohos --package camera --auto-sign --json --trace-dir .fluoh/tasks/test-packageSupport-camera/traces/support',
      ),
    );
    final evidence = result['evidence'] as Map<String, Object?>;
    expect(
      evidence,
      containsPair(
        'traceDir',
        '.fluoh/tasks/test-packageSupport-camera/traces/support',
      ),
    );
    final evidenceSummary = result['evidenceSummary'] as Map<String, Object?>;
    expect(evidenceSummary['completedPhases'], contains('verify'));
    expect(evidenceSummary['missingPhases'], contains('ohos-build'));
    expect(stderr, isEmpty);
  });

  test('package next gates automation after passed mobile run', () async {
    final environment = await createTestEnvironment();
    final packageRepository = await createPackageRepositoryFixture(environment);
    await _writeFunctionalNotes(packageRepository);
    await _writeTrace(packageRepository, _passedRunInvocations());
    final packageEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['package', 'next', '--package', 'camera', '--json'],
        environment: packageEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final result = jsonDecode(stdout.single) as Map<String, Object?>;
    final nextAction = result['nextAction'] as Map<String, Object?>;
    expect(nextAction, containsPair('type', 'editRequired'));
    expect(nextAction, containsPair('phase', 'visual-page-readiness'));
    final evidenceSummary = result['evidenceSummary'] as Map<String, Object?>;
    expect(evidenceSummary['completedPhases'], contains('ohos-run'));
    expect(evidenceSummary['missingPhases'], contains('automation-dry-run'));
    final remainingRisks = result['remainingRisks'] as List<Object?>;
    expect(
      remainingRisks,
      contains(
        isA<Map<String, Object?>>().having(
          (risk) => risk['code'],
          'code',
          'quality.visual_page_readiness_missing',
        ),
      ),
    );
    expect(stderr, isEmpty);
  });

  test('package next resumes automation after visual readiness', () async {
    final environment = await createTestEnvironment();
    final packageRepository = await createPackageRepositoryFixture(environment);
    await _writeFunctionalNotes(packageRepository);
    await _writeTrace(packageRepository, _passedRunInvocations());
    await _writeVisualPageReadiness(packageRepository);
    final packageEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['package', 'next', '--package', 'camera', '--json'],
        environment: packageEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final result = jsonDecode(stdout.single) as Map<String, Object?>;
    final nextAction = result['nextAction'] as Map<String, Object?>;
    expect(nextAction, containsPair('type', 'commandRequired'));
    expect(nextAction, containsPair('phase', 'automation-dry-run'));
    expect(
      nextAction,
      containsPair(
        'command',
        'fluoh drive ohos --package camera --dry-run --json --trace-dir .fluoh/tasks/test-packageSupport-camera/traces/support',
      ),
    );
    expect(stderr, isEmpty);
  });

  test('package next does not accept exploratory smoke as automation run', () async {
    final environment = await createTestEnvironment();
    final packageRepository = await createPackageRepositoryFixture(environment);
    await _writeFunctionalNotes(packageRepository);
    await _writeTrace(packageRepository, [
      ..._passedRunInvocations(),
      {
        'commandLine':
            'fluoh drive ohos --package camera --dry-run --json --trace-dir .fluoh/tasks/test-packageSupport-camera/traces/support',
        'ok': true,
        'exitCode': 0,
        'result': {},
      },
      {
        'commandLine':
            'fluoh drive ohos --package camera --profile exploratory-smoke --json --trace-dir .fluoh/tasks/test-packageSupport-camera/traces/support',
        'ok': true,
        'exitCode': 0,
        'result': {},
      },
    ]);
    await _writeVisualPageReadiness(packageRepository);
    final packageEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['package', 'next', '--package', 'camera', '--json'],
        environment: packageEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final result = jsonDecode(stdout.single) as Map<String, Object?>;
    final nextAction = result['nextAction'] as Map<String, Object?>;
    expect(nextAction, containsPair('type', 'commandRequired'));
    expect(nextAction, containsPair('phase', 'automation-run'));
    expect(
      nextAction,
      containsPair(
        'command',
        'fluoh drive ohos --package camera --json --trace-dir .fluoh/tasks/test-packageSupport-camera/traces/support',
      ),
    );
    final evidenceSummary = result['evidenceSummary'] as Map<String, Object?>;
    expect(evidenceSummary['missingPhases'], contains('automation-run'));
    expect(stderr, isEmpty);
  });

  test(
    'package next requires existing platform regression after OHOS evidence',
    () async {
      final environment = await createTestEnvironment();
      final packageRepository = await createPackageRepositoryFixture(
        environment,
      );
      await _writeFunctionalNotes(packageRepository);
      await _writeExistingExamplePlatforms(packageRepository, [
        'android',
        'web',
      ]);
      await _writeTrace(packageRepository, _passedPhaseInvocations());
      await _writeVisualPageReadiness(packageRepository);
      final packageEnvironment = FluohEnvironment(
        homeDirectory: environment.homeDirectory,
        workingDirectory: packageRepository,
      );
      final stdout = <String>[];
      final stderr = <String>[];

      expect(
        await runFluoh(
          ['package', 'next', '--package', 'camera', '--json'],
          environment: packageEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final result = jsonDecode(stdout.single) as Map<String, Object?>;
      final nextAction = result['nextAction'] as Map<String, Object?>;
      expect(nextAction, containsPair('type', 'commandRequired'));
      expect(nextAction, containsPair('phase', 'existing-android-regression'));
      expect(
        nextAction,
        containsPair(
          'command',
          'fluoh run android --package camera --auto-emulator --json --trace-dir .fluoh/tasks/test-packageSupport-camera/traces/support',
        ),
      );
      final evidenceSummary = result['evidenceSummary'] as Map<String, Object?>;
      expect(
        evidenceSummary['completedPhases'],
        containsAll(<String>['verify', 'ohos-build', 'ohos-run']),
      );
      expect(
        evidenceSummary['missingPhases'],
        containsAll(<String>[
          'existing-android-regression',
          'existing-android-automation-dry-run',
          'existing-android-automation-run',
          'existing-web-regression',
        ]),
      );
      expect(stderr, isEmpty);
    },
  );

  test(
    'package next requires existing mobile automation after regression run',
    () async {
      final environment = await createTestEnvironment();
      final packageRepository = await createPackageRepositoryFixture(
        environment,
      );
      await _writeFunctionalNotes(packageRepository);
      await _writeExistingExamplePlatforms(packageRepository, [
        'android',
        'web',
      ]);
      await _writeTrace(packageRepository, [
        ..._passedPhaseInvocations(),
        {
          'commandLine':
              'fluoh run android --package camera --auto-emulator --json --trace-dir .fluoh/tasks/test-packageSupport-camera/traces/support',
          'ok': true,
          'exitCode': 0,
          'result': {},
        },
      ]);
      await _writeVisualPageReadiness(packageRepository);
      final packageEnvironment = FluohEnvironment(
        homeDirectory: environment.homeDirectory,
        workingDirectory: packageRepository,
      );
      final stdout = <String>[];
      final stderr = <String>[];

      expect(
        await runFluoh(
          ['package', 'next', '--package', 'camera', '--json'],
          environment: packageEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final result = jsonDecode(stdout.single) as Map<String, Object?>;
      final nextAction = result['nextAction'] as Map<String, Object?>;
      expect(nextAction, containsPair('type', 'commandRequired'));
      expect(
        nextAction,
        containsPair('phase', 'existing-android-automation-dry-run'),
      );
      expect(
        nextAction,
        containsPair(
          'command',
          'fluoh drive android --package camera --dry-run --json --trace-dir .fluoh/tasks/test-packageSupport-camera/traces/support',
        ),
      );
      final evidenceSummary = result['evidenceSummary'] as Map<String, Object?>;
      expect(
        evidenceSummary['completedPhases'],
        contains('existing-android-regression'),
      );
      expect(
        evidenceSummary['missingPhases'],
        containsAll(<String>[
          'existing-android-automation-dry-run',
          'existing-android-automation-run',
          'existing-web-regression',
        ]),
      );
      expect(stderr, isEmpty);
    },
  );

  test(
    'package next requires existing mobile automation run after dry-run',
    () async {
      final environment = await createTestEnvironment();
      final packageRepository = await createPackageRepositoryFixture(
        environment,
      );
      await _writeFunctionalNotes(packageRepository);
      await _writeExistingExamplePlatforms(packageRepository, [
        'android',
        'web',
      ]);
      await _writeTrace(packageRepository, [
        ..._passedPhaseInvocations(),
        {
          'commandLine':
              'fluoh run android --package camera --auto-emulator --json --trace-dir .fluoh/tasks/test-packageSupport-camera/traces/support',
          'ok': true,
          'exitCode': 0,
          'result': {},
        },
        {
          'commandLine':
              'fluoh drive android --package camera --dry-run --json --trace-dir .fluoh/tasks/test-packageSupport-camera/traces/support',
          'ok': true,
          'exitCode': 0,
          'result': {},
        },
      ]);
      await _writeVisualPageReadiness(packageRepository);
      final packageEnvironment = FluohEnvironment(
        homeDirectory: environment.homeDirectory,
        workingDirectory: packageRepository,
      );
      final stdout = <String>[];
      final stderr = <String>[];

      expect(
        await runFluoh(
          ['package', 'next', '--package', 'camera', '--json'],
          environment: packageEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final result = jsonDecode(stdout.single) as Map<String, Object?>;
      final nextAction = result['nextAction'] as Map<String, Object?>;
      expect(nextAction, containsPair('type', 'commandRequired'));
      expect(
        nextAction,
        containsPair('phase', 'existing-android-automation-run'),
      );
      expect(
        nextAction,
        containsPair(
          'command',
          'fluoh drive android --package camera --json --trace-dir .fluoh/tasks/test-packageSupport-camera/traces/support',
        ),
      );
      final evidenceSummary = result['evidenceSummary'] as Map<String, Object?>;
      expect(
        evidenceSummary['completedPhases'],
        containsAll(<String>[
          'existing-android-regression',
          'existing-android-automation-dry-run',
        ]),
      );
      expect(
        evidenceSummary['missingPhases'],
        containsAll(<String>[
          'existing-android-automation-run',
          'existing-web-regression',
        ]),
      );
      expect(stderr, isEmpty);
    },
  );

  test(
    'package next accepts build-based existing platform regression evidence',
    () async {
      final environment = await createTestEnvironment();
      final packageRepository = await createPackageRepositoryFixture(
        environment,
      );
      await _writeFunctionalNotes(packageRepository);
      await _writeExistingExamplePlatforms(packageRepository, ['linux']);
      await _writeTrace(packageRepository, [
        ..._passedPhaseInvocations(),
        {
          'commandLine':
              'fluoh build linux --package camera --json --trace-dir .fluoh/tasks/test-packageSupport-camera/traces/support',
          'ok': true,
          'exitCode': 0,
          'result': {},
        },
      ]);
      await _writeVisualPageReadiness(packageRepository);
      final packageEnvironment = FluohEnvironment(
        homeDirectory: environment.homeDirectory,
        workingDirectory: packageRepository,
      );
      final stdout = <String>[];
      final stderr = <String>[];

      expect(
        await runFluoh(
          ['package', 'next', '--package', 'camera', '--json'],
          environment: packageEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final result = jsonDecode(stdout.single) as Map<String, Object?>;
      final evidenceSummary = result['evidenceSummary'] as Map<String, Object?>;
      expect(
        evidenceSummary['completedPhases'],
        contains('existing-linux-regression'),
      );
      expect(
        evidenceSummary['missingPhases'],
        isNot(contains('existing-linux-regression')),
      );
      expect(stderr, isEmpty);
    },
  );

  test('package next asks for a focused repair after failed trace', () async {
    final environment = await createTestEnvironment();
    final packageRepository = await createPackageRepositoryFixture(environment);
    await _writeTrace(packageRepository, [
      {
        'commandLine':
            'fluoh build ohos --package camera --auto-sign --json --trace-dir .fluoh/tasks/test-packageSupport-camera/traces/support',
        'ok': false,
        'exitCode': 1,
        'result': {
          'nextCommand':
              'fluoh build ohos --package camera --auto-sign --json --trace-dir .fluoh/tasks/test-packageSupport-camera/traces/support',
          'diagnostics': [
            {'code': 'ohos.build_failed', 'message': 'Build failed'},
          ],
          'stderrTail': 'Compile error',
        },
      },
    ]);
    final packageEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['package', 'next', '--package', 'camera', '--json'],
        environment: packageEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final result = jsonDecode(stdout.single) as Map<String, Object?>;
    final nextAction = result['nextAction'] as Map<String, Object?>;
    expect(nextAction, containsPair('type', 'editRequired'));
    expect(nextAction, containsPair('phase', 'repair'));
    expect(
      nextAction,
      containsPair(
        'rerunCommand',
        'fluoh build ohos --package camera --auto-sign --json --trace-dir .fluoh/tasks/test-packageSupport-camera/traces/support',
      ),
    );
    expect(
      nextAction,
      containsPair(
        'statusCommand',
        'fluoh package next --package camera --json',
      ),
    );
    final details = nextAction['details'] as Map<String, Object?>;
    expect(details, containsPair('stderrTail', 'Compile error'));
    expect(details['diagnostics'], isA<List<Object?>>());
    final failureStreak = result['failureStreak'] as Map<String, Object?>;
    expect(failureStreak, containsPair('count', 1));
    expect(failureStreak, containsPair('blocking', false));
    final remainingRisks = result['remainingRisks'] as List<Object?>;
    expect(
      remainingRisks,
      contains(
        isA<Map<String, Object?>>().having(
          (risk) => risk['code'],
          'code',
          'trace.latest_failure',
        ),
      ),
    );
    expect(stderr, isEmpty);
  });

  test('package next blocks repeated same command failures', () async {
    final environment = await createTestEnvironment();
    final packageRepository = await createPackageRepositoryFixture(environment);
    final failedInvocation = {
      'commandLine':
          'fluoh build ohos --package camera --auto-sign --json --trace-dir .fluoh/tasks/test-packageSupport-camera/traces/support',
      'ok': false,
      'exitCode': 1,
      'result': {
        'diagnostics': [
          {'code': 'ohos.build_failed', 'message': 'Build failed'},
        ],
      },
    };
    await _writeTrace(packageRepository, [
      failedInvocation,
      failedInvocation,
      failedInvocation,
    ]);
    final packageEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['package', 'next', '--package', 'camera', '--json'],
        environment: packageEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final result = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(result, containsPair('state', 'blocked'));
    final nextAction = result['nextAction'] as Map<String, Object?>;
    expect(nextAction, containsPair('type', 'blocked'));
    expect(nextAction, containsPair('phase', 'repair'));
    final failureStreak = result['failureStreak'] as Map<String, Object?>;
    expect(failureStreak, containsPair('count', 3));
    expect(failureStreak, containsPair('blocking', true));
    final remainingRisks = result['remainingRisks'] as List<Object?>;
    expect(
      remainingRisks,
      contains(
        isA<Map<String, Object?>>()
            .having((risk) => risk['code'], 'code', 'trace.latest_failure')
            .having((risk) => risk['severity'], 'severity', 'blocked'),
      ),
    );
    expect(stderr, isEmpty);
  });

  test(
    'package next does not treat a report as ready without evidence',
    () async {
      final environment = await createTestEnvironment();
      final packageRepository = await createPackageRepositoryFixture(
        environment,
      );
      await _writePlanningNotes(packageRepository);
      await _writeReport(packageRepository);
      final packageEnvironment = FluohEnvironment(
        homeDirectory: environment.homeDirectory,
        workingDirectory: packageRepository,
      );
      final stdout = <String>[];
      final stderr = <String>[];

      expect(
        await runFluoh(
          ['package', 'next', '--package', 'camera', '--json'],
          environment: packageEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final result = jsonDecode(stdout.single) as Map<String, Object?>;
      expect(result, containsPair('state', 'actionRequired'));
      final nextAction = result['nextAction'] as Map<String, Object?>;
      expect(nextAction, containsPair('type', 'commandRequired'));
      expect(nextAction, containsPair('phase', 'verify'));
      final evidenceSummary = result['evidenceSummary'] as Map<String, Object?>;
      expect(evidenceSummary, containsPair('reportCreated', true));
      expect(evidenceSummary['missingPhases'], contains('verify'));
      expect(stderr, isEmpty);
    },
  );

  test(
    'package next requires visual page-readiness after mobile run',
    () async {
      final environment = await createTestEnvironment();
      final packageRepository = await createPackageRepositoryFixture(
        environment,
      );
      await _writeFunctionalNotes(packageRepository);
      await _writeTrace(packageRepository, _passedPhaseInvocations());
      final packageEnvironment = FluohEnvironment(
        homeDirectory: environment.homeDirectory,
        workingDirectory: packageRepository,
      );
      final stdout = <String>[];
      final stderr = <String>[];

      expect(
        await runFluoh(
          ['package', 'next', '--package', 'camera', '--json'],
          environment: packageEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final result = jsonDecode(stdout.single) as Map<String, Object?>;
      expect(result, containsPair('state', 'actionRequired'));
      final visualPageReadiness =
          result['visualPageReadiness'] as Map<String, Object?>;
      expect(visualPageReadiness, containsPair('required', true));
      expect(visualPageReadiness, containsPair('exists', false));
      expect(visualPageReadiness, containsPair('ready', false));
      final nextAction = result['nextAction'] as Map<String, Object?>;
      expect(nextAction, containsPair('type', 'editRequired'));
      expect(nextAction, containsPair('phase', 'visual-page-readiness'));
      final remainingRisks = result['remainingRisks'] as List<Object?>;
      expect(
        remainingRisks,
        contains(
          isA<Map<String, Object?>>().having(
            (risk) => risk['code'],
            'code',
            'quality.visual_page_readiness_missing',
          ),
        ),
      );
      expect(stderr, isEmpty);
    },
  );

  test('package next requires report check before ready', () async {
    final environment = await createTestEnvironment();
    final packageRepository = await createPackageRepositoryFixture(environment);
    await _writeFunctionalNotes(packageRepository);
    await _writeTrace(packageRepository, _passedPhaseInvocations());
    await _writeVisualPageReadiness(packageRepository);
    await _writeInvalidReport(packageRepository);
    final packageEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['package', 'next', '--package', 'camera', '--json'],
        environment: packageEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final result = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(result, containsPair('state', 'actionRequired'));
    final reportCheck = result['reportCheck'] as Map<String, Object?>;
    expect(reportCheck, containsPair('required', true));
    expect(reportCheck, containsPair('passed', false));
    final nextAction = result['nextAction'] as Map<String, Object?>;
    expect(nextAction, containsPair('type', 'editRequired'));
    expect(nextAction, containsPair('phase', 'report-check'));
    final remainingRisks = result['remainingRisks'] as List<Object?>;
    expect(
      remainingRisks,
      contains(
        isA<Map<String, Object?>>().having(
          (risk) => risk['code'],
          'code',
          'evidence.report_check_failed',
        ),
      ),
    );
    expect(stderr, isEmpty);
  });

  test('package next is ready after evidence and report exist', () async {
    final environment = await createTestEnvironment();
    final packageRepository = await createPackageRepositoryFixture(environment);
    await _writeFunctionalNotes(packageRepository);
    await _writeTrace(packageRepository, _passedPhaseInvocations());
    await _writeVisualPageReadiness(packageRepository);
    await _writeReport(packageRepository);
    final packageEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['package', 'next', '--package', 'camera', '--json'],
        environment: packageEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final result = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(result, containsPair('state', 'ready'));
    final nextAction = result['nextAction'] as Map<String, Object?>;
    expect(nextAction, containsPair('type', 'ready'));
    final nextCommands = (nextAction['nextCommands'] as List<Object?>)
        .cast<String>();
    expect(
      nextCommands,
      containsAllInOrder([
        'fluoh package status --package camera --json',
        'fluoh package handoff --package camera --json',
        contains('fluoh package check --package camera --report '),
      ]),
    );
    final evidenceSummary = result['evidenceSummary'] as Map<String, Object?>;
    expect(evidenceSummary, containsPair('supportEvidenceReady', true));
    final scope = result['supportScope'] as Map<String, Object?>;
    expect(scope, containsPair('complete', true));
    final remainingRisks = result['remainingRisks'] as List<Object?>;
    expect(
      remainingRisks,
      contains(
        isA<Map<String, Object?>>().having(
          (risk) => risk['code'],
          'code',
          'release.readiness_not_checked',
        ),
      ),
    );
    expect(stderr, isEmpty);
  });
}

Future<void> _writePlanningNotes(Directory packageRepository) async {
  await _writeScopeNotes(packageRepository, evidenceLevel: 'none');
}

Future<void> _writeFunctionalNotes(Directory packageRepository) async {
  await _writeScopeNotes(packageRepository, evidenceLevel: 'functional');
}

Future<void> _writeScopeNotes(
  Directory packageRepository, {
  required String evidenceLevel,
}) async {
  final scope = File('${packageRepository.path}/doc/fluoh/camera/scope.yaml');
  await scope.parent.create(recursive: true);
  await scope.writeAsString('''
schema: 1
kind: fluoh.packageScope
package: camera
platform: ohos
scope:
  - id: camera_preview
    priority: p0
    category: methodApi
    publicApis:
      - CameraController.initialize
    platforms:
      ohos:
        role: implementationTarget
        decision:
          support: supported
          confidence: medium
          reason: OHOS camera API supports preview startup.
          sources:
            - title: OHOS camera API
              url: https://example.invalid/ohos-camera
        implementation:
          status: planned
          files:
            - ohos/src/main/ets/CameraPlugin.ets
          tasks:
            - map preview startup
        tests:
          required: true
          cases:
            - camera_preview_launch
        evidence:
          level: $evidenceLevel
''');
}

Future<Directory> _ensureTask(Directory packageRepository) async {
  final task = Directory(
    '${packageRepository.path}/.fluoh/tasks/test-packageSupport-camera',
  );
  await task.create(recursive: true);
  final current = File('${packageRepository.path}/.fluoh/current-task.json');
  await current.parent.create(recursive: true);
  await current.writeAsString(
    jsonEncode({
      'schema': 1,
      'kind': 'fluoh.currentTask',
      'id': 'test-packageSupport-camera',
      'path': '.fluoh/tasks/test-packageSupport-camera',
      'updatedAt': '2026-06-18T00:00:00.000',
    }),
  );
  return task;
}

Future<void> _writeVisualPageReadiness(Directory packageRepository) async {
  final task = await _ensureTask(packageRepository);
  final readiness = File('${task.path}/evidence/visual-readiness.yaml');
  await readiness.parent.create(recursive: true);
  await readiness.writeAsString('''
schema: 1
kind: fluoh.visualPageReadiness
package: camera
platform: ohos
status: passed
screenshots:
  - .fluoh/tasks/test-packageSupport-camera/evidence/screenshots/camera-ohos-post-launch.jpeg
result: Screenshot shows the camera preview page, not a blank shell.
''');
}

Future<void> _writeTrace(
  Directory packageRepository,
  List<Map<String, Object?>> invocations,
) async {
  final task = await _ensureTask(packageRepository);
  final trace = File('${task.path}/traces/support/trace.json');
  await trace.parent.create(recursive: true);
  await trace.writeAsString(
    jsonEncode({
      'schema': 1,
      'kind': 'fluoh.trace',
      'id': ' support',
      'commandLine': invocations.last['commandLine'],
      'ok': invocations.last['ok'],
      'exitCode': invocations.last['exitCode'],
      'result': invocations.last['result'],
      'invocations': invocations,
    }),
  );
}

List<Map<String, Object?>> _passedPhaseInvocations() {
  return [
    {
      'commandLine':
          'fluoh verify --package camera --json --trace-dir .fluoh/tasks/test-packageSupport-camera/traces/support',
      'ok': true,
      'exitCode': 0,
      'result': {},
    },
    {
      'commandLine':
          'fluoh build ohos --package camera --auto-sign --json --trace-dir .fluoh/tasks/test-packageSupport-camera/traces/support',
      'ok': true,
      'exitCode': 0,
      'result': {},
    },
    {
      'commandLine':
          'fluoh run ohos --package camera --auto-emulator --json --trace-dir .fluoh/tasks/test-packageSupport-camera/traces/support',
      'ok': true,
      'exitCode': 0,
      'result': {},
    },
    {
      'commandLine':
          'fluoh drive ohos --package camera --dry-run --json --trace-dir .fluoh/tasks/test-packageSupport-camera/traces/support',
      'ok': true,
      'exitCode': 0,
      'result': {},
    },
    {
      'commandLine':
          'fluoh drive ohos --package camera --json --trace-dir .fluoh/tasks/test-packageSupport-camera/traces/support',
      'ok': true,
      'exitCode': 0,
      'result': {},
    },
  ];
}

List<Map<String, Object?>> _passedRunInvocations() {
  return _passedPhaseInvocations().take(3).toList();
}

Future<void> _writeInvalidReport(Directory packageRepository) async {
  final task = await _ensureTask(packageRepository);
  final report = File('${task.path}/reports/report-20260616000000.md');
  await report.parent.create(recursive: true);
  await report.writeAsString('# camera\n');
}

Future<void> _writeReport(Directory packageRepository) async {
  final task = await _ensureTask(packageRepository);
  final report = File('${task.path}/reports/report-20260616000000.md');
  await report.parent.create(recursive: true);
  await report.writeAsString('''
# fluoh AI Report

- Scope: camera
- Repository: ${packageRepository.path}
- Package: camera
- Upstream version: 0.11.0
- FlutterOH SDK: 3.35.8-ohos-0.0.3
- Date: 2026-06-16T00:00:00.000Z
- Recommendation: ready

## Summary

- Support evidence is complete for the test fixture.

## Changes

- Added OHOS camera preview support.

## Public API / Compatibility

- Public Dart API changes: none.
- Dependency constraint changes: none.
- Non-OHOS regression risk: existing behavior preserved.

## Official Platform Basis

- Official OHOS Camera Kit API reference reviewed.
- Impact on implementation and tests: preview startup maps to the OHOS camera session API.

## Support Scope

- path: doc/fluoh/camera/scope.yaml
- exists: true
- planningReady: true
- functionalEvidenceReady: true
- complete: true
- p0: total=1, supportedOrDegraded=1, functionalEvidence=1

No support scope issues: P0 planning and functional evidence gates are complete.

## Commands

| Command | Exit | Result | Notes |
| --- | --- | --- | --- |
| `fluoh verify --package camera --json --trace-dir .fluoh/tasks/test-packageSupport-camera/traces/support` | 0 | passed | trace .fluoh/tasks/test-packageSupport-camera/traces/support/trace.json |
| `fluoh build ohos --package camera --auto-sign --json --trace-dir .fluoh/tasks/test-packageSupport-camera/traces/support` | 0 | passed | HAP built |
| `fluoh run ohos --package camera --auto-emulator --json --trace-dir .fluoh/tasks/test-packageSupport-camera/traces/support` | 0 | passed | ohos post-launch screenshot .fluoh/tasks/test-packageSupport-camera/evidence/screenshots/camera-ohos-post-launch.jpeg |
| `fluoh drive ohos --package camera --json --trace-dir .fluoh/tasks/test-packageSupport-camera/traces/support` | 0 | passed | assertText camera preview visible |

## Delivery Checklist

- [x] Diff reviewed; unrelated files, local paths, generated caches, credentials, and private tokens excluded.
- [x] Commands table includes exit codes and enough evidence to reproduce the decision.
- [x] Existing package/app tests, example tests, and `integration_test/` were inspected against public API, platform interfaces, permissions, and behavior paths before final verification.
- [x] P0 support scope includes per-platform support decisions, platform API basis or reasons, implementation plans where required, test cases, and functional or regression evidence.
- [x] Missing or weak functional tests were added or repaired before final verification, or a concrete blocker is recorded.
- [x] Official platform documentation basis was reviewed before implementation, or a concrete unavailable/not-applicable reason is recorded.
- [x] Target-platform build evidence recorded, including OHOS when in scope.
- [x] Target-platform run evidence recorded, or the missing device/emulator blocker is explicit.
- [x] Pub.dev publishability checked with `dart pub publish --dry-run`, or a concrete not-applicable reason is recorded.
- [x] FlutterOH support checked with fluoh verify/build/run/drive/report gates.
- [x] Android, iOS, macOS, Linux, Web, and Windows regression checks recorded when relevant.
- [x] Every existing Android, iOS, macOS, Linux, Web, and Windows platform was functionally checked when supported by the current host/toolchain, or exact diagnostic evidence and skip reason are recorded.
- [x] Interaction automation evidence recorded through a passed `flutter test integration_test -d <device>` command or real `fluoh drive --json`, with no unresolved ready-blocking gates.
- [x] Functional interaction evidence recorded for permission, file, camera, location, media, deep link, external-app, or other device workflows.
- [x] Public API, dependency constraints, and existing-platform regression risk reviewed.
- [x] Remaining risks and release decision are explicit.

## Platform Matrix

| Platform | Build | Run | Integration test | Target | Evidence / blocker |
| --- | --- | --- | --- | --- | --- |
| ohos | passed | passed | notApplicable | emulator | ohos post-launch screenshot .fluoh/tasks/test-packageSupport-camera/evidence/screenshots/camera-ohos-post-launch.jpeg |

## Automation Coverage

- `coveragePolicy.status`: readyForExecution
- `readyForAutomation`: true
- `qualityGateSummary`: ready=10, notReady=0

| Gate | Status | Evidence / blocker |
| --- | --- | --- |
| coverage-inventory | ready | package APIs inventoried |
| coverage-metadata | ready | scenario metadata complete |
| coverage-items | ready | coverage rows complete |
| capability-inventory-coverage | ready | P0 camera preview covered |
| blocked-coverage | ready | no blocked rows |
| scenario-evidence-assertions | ready | assertText verifies preview |
| page-readiness | ready | visualPageReadiness passed |
| existing-test-baseline | ready | tests reviewed |
| manifest-permission-coverage | notApplicable | no manifest permission in fixture |
| behavior-paths | ready | preview success path covered |

## Interaction Evidence

| Scenario | Method | Platform | Target | Result | Evidence / blocker |
| --- | --- | --- | --- | --- | --- |
| camera_preview | AI-assisted | ohos | emulator | passed | `fluoh drive ohos --package camera --json`; assertText camera preview visible; command json recorded |

## Diagnostics

- No unresolved diagnostics.

## Fluoh Feedback

No fluoh feedback: no trace feedback candidates were supplied.

## Signing

- Mode: auto-sign
- Generated HAPs: test fixture
- Hilog: no blocking errors

## Remaining Risks

- No blocking risks.

## Local State

- Git status summary: clean.
- Files intentionally left uncommitted: none.
- Files that must not be committed: .fluoh/tasks.

## Release Decision

Release recommendation: ready

Reason: test fixture report is complete.
''');
}

Future<void> _writeExampleIntegrationTest(Directory packageRepository) async {
  final testFile = File(
    '${packageRepository.path}/example/integration_test/app_test.dart',
  );
  await testFile.parent.create(recursive: true);
  await testFile.writeAsString('''
void main() {}
''');
}

Future<void> _writeExistingExamplePlatforms(
  Directory packageRepository,
  List<String> platforms,
) async {
  for (final platform in platforms) {
    await Directory(
      '${packageRepository.path}/example/$platform',
    ).create(recursive: true);
  }
}

Future<void> _movePackagePath(
  Directory packageRepository,
  String packagePath,
) async {
  final manifest = File('${packageRepository.path}/fluoh.yaml');
  final content = await manifest.readAsString();
  final pathPattern = RegExp(r'^  path: .*$', multiLine: true);
  await manifest.writeAsString(
    pathPattern.hasMatch(content)
        ? content.replaceFirst(pathPattern, '  path: $packagePath')
        : content.replaceFirst(
            '  name: camera\n',
            '  name: camera\n  path: $packagePath\n',
          ),
  );
  final packageRoot = Directory('${packageRepository.path}/$packagePath');
  await packageRoot.create(recursive: true);
  await File('${packageRoot.path}/pubspec.yaml').writeAsString('''
name: camera
version: 0.11.0

environment:
  sdk: ^3.0.0
''');
}

Future<void> _writeScenario(Directory packageRepository) async {
  final scenario = File(
    '${packageRepository.path}/doc/fluoh/camera/scenarios/ohos-functional.md',
  );
  await scenario.parent.create(recursive: true);
  await scenario.writeAsString('''
kind: fluoh.automationScenario
steps: []
''');
}

Future<void> _writePackageRootScenario(
  Directory packageRepository,
  String packagePath,
) async {
  final scenario = File(
    '${packageRepository.path}/$packagePath/doc/fluoh/camera/scenarios/ohos-functional.md',
  );
  await scenario.parent.create(recursive: true);
  await scenario.writeAsString('''
kind: fluoh.automationScenario
steps: []
''');
}
