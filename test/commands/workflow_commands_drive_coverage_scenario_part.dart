part of 'workflow_commands_test.dart';

void _registerWorkflowCommandsDriveCoverageScenarioTests() {
  test('drive dry-run reports scenario coverage matrix', () async {
    final environment = await createTestEnvironment();
    final scenarioDirectory = Directory(
      '${environment.workingDirectory.path}/doc/fluoh/sample_permissions',
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
    expect(coverageSummary, containsPair('pageReadinessWarningCount', 2));
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
          containsPair('status', 'needsFunctionalEvidence'),
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
          containsPair('status', 'needsFunctionalEvidence'),
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
    expect(
      report['targets'],
      contains(
        allOf(
          containsPair('target', {
            'kind': 'package',
            'name': 'sample_permissions',
          }),
          containsPair('phase', 'automation-dry-run'),
          containsPair('passed', true),
        ),
      ),
    );
    expect(stderr, isEmpty);
  });

  test(
    'drive dry-run treats assertSession and screenshots as launch evidence only',
    () async {
      final environment = await createTestEnvironment();
      final scenario = File(
        '${environment.workingDirectory.path}/doc/fluoh/sample_permissions/scenarios/android-launch-only.md',
      );
      await scenario.parent.create(recursive: true);
      await scenario.writeAsString('''
kind: fluoh.automationScenario
schema: 1
name: android launch-only permission evidence
platform: android
coverage:
  - category: permission
    item: camera
    path: grant
  - category: permission
    item: camera
    path: deny
steps:
  - action: assertSession
    status: passed
  - action: captureScreenshot
    outputPath: camera-launch-only.png
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
      final automation = report['automation'] as Map<String, Object?>;
      final coveragePolicy =
          automation['coveragePolicy'] as Map<String, Object?>;
      expect(
        coveragePolicy,
        containsPair('status', 'needsAgentCoverageReview'),
      );
      final scenarioEvidence =
          (coveragePolicy['scenarioEvidence'] as List<Object?>)
              .cast<Map<String, Object?>>();
      expect(
        scenarioEvidence.single,
        allOf(
          containsPair('status', 'needsFunctionalEvidence'),
          containsPair('verificationActions', isEmpty),
          containsPair(
            'launchEvidenceActions',
            containsAll(['assertSession', 'captureScreenshot']),
          ),
          containsPair('evidenceGaps', hasLength(2)),
          containsPair('suggestedScenarioPatch', isA<Map<String, Object?>>()),
        ),
      );
      final pageReadiness = (coveragePolicy['pageReadiness'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(
        pageReadiness.single,
        allOf(
          containsPair('status', 'needsPageReadinessEvidence'),
          containsPair('suggestedScenarioPatch', isA<Map<String, Object?>>()),
        ),
      );
      final repairQueue = (automation['repairQueue'] as List<Object?>)
          .cast<Map<String, Object?>>();
      final scenarioRepair = repairQueue.singleWhere(
        (item) => item['type'] == 'scenarioEvidence',
      );
      final nextAction = scenarioRepair['nextAction'] as Map<String, Object?>;
      final actions = (nextAction['actions'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(actions, isNot(contains(containsPair('action', 'assertSession'))));
      expect(actions, contains(containsPair('action', 'assertText')));
      expect(actions, contains(containsPair('action', 'tapText')));
      expect(
        nextAction,
        containsPair('scenarioPatch', isA<Map<String, Object?>>()),
      );
      expect(
        repairQueue,
        contains(
          allOf(
            containsPair('type', 'pageReadiness'),
            containsPair('gate', 'page-readiness'),
          ),
        ),
      );
      expect(stderr, isEmpty);
    },
  );

  test(
    'drive dry-run accepts explicit coverage evidence step bindings',
    () async {
      final environment = await createTestEnvironment();
      final scenario = File(
        '${environment.workingDirectory.path}/doc/fluoh/sample_permissions/scenarios/android-bound-evidence.md',
      );
      await scenario.parent.create(recursive: true);
      await scenario.writeAsString('''
kind: fluoh.automationScenario
schema: 1
name: android bound permission evidence
platform: android
coverage:
  - category: permission
    item: camera
    path: grant
    interactionStep: 3
    assertionStep: 4
  - category: permission
    item: camera
    path: deny
    interactionStep: 6
    assertionStep: 7
steps:
  - action: launchApp
  - action: tapText
    labels: [Open camera]
  - action: allowPermission
    permission: camera
  - action: assertText
    labels: [Camera permission granted]
  - action: tapText
    labels: [Open camera]
  - action: denyPermission
    permission: camera
  - action: assertLog
    contains: camera permission denied
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
      final automation = report['automation'] as Map<String, Object?>;
      final coveragePolicy =
          automation['coveragePolicy'] as Map<String, Object?>;
      final scenarioEvidence =
          (coveragePolicy['scenarioEvidence'] as List<Object?>)
              .cast<Map<String, Object?>>();
      final evidence = scenarioEvidence.single;
      expect(evidence, containsPair('status', 'readyForReview'));
      final bindings = (evidence['coverageEvidenceBindings'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(
        bindings,
        everyElement(
          allOf(
            containsPair('status', 'readyForReview'),
            containsPair('bindingMode', 'explicit'),
            containsPair('interactionStep', isA<int>()),
            containsPair('assertionStep', isA<int>()),
          ),
        ),
      );
      final pageReadiness = (coveragePolicy['pageReadiness'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(pageReadiness.single, containsPair('status', 'readyForReview'));
      final repairQueue = (automation['repairQueue'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(
        repairQueue.where((item) => item['type'] == 'scenarioEvidence'),
        isEmpty,
      );
      expect(stderr, isEmpty);
    },
  );

  test('drive dry-run rejects coverage bound to launch-only assertion', () async {
    final environment = await createTestEnvironment();
    final scenario = File(
      '${environment.workingDirectory.path}/doc/fluoh/sample_permissions/scenarios/android-bad-binding.md',
    );
    await scenario.parent.create(recursive: true);
    await scenario.writeAsString('''
kind: fluoh.automationScenario
schema: 1
name: android bad bound evidence
platform: android
coverage:
  - category: permission
    item: camera
    path: grant
    interactionStep: 1
    assertionStep: 2
steps:
  - action: allowPermission
    permission: camera
  - action: assertSession
    status: passed
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
    final automation = report['automation'] as Map<String, Object?>;
    final coveragePolicy = automation['coveragePolicy'] as Map<String, Object?>;
    final scenarioEvidence =
        (coveragePolicy['scenarioEvidence'] as List<Object?>)
            .cast<Map<String, Object?>>();
    final binding =
        ((scenarioEvidence.single['coverageEvidenceBindings'] as List<Object?>)
                .cast<Map<String, Object?>>())
            .single;
    expect(binding, containsPair('status', 'needsFunctionalEvidence'));
    expect(
      binding['missingReasons'],
      contains('assertionStepMustReferenceFunctionalAssertion:2:assertSession'),
    );
    expect(
      scenarioEvidence.single,
      containsPair('suggestedScenarioPatch', isA<Map<String, Object?>>()),
    );
    final repairQueue = (automation['repairQueue'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final scenarioRepair = repairQueue.singleWhere(
      (item) => item['type'] == 'scenarioEvidence',
    );
    expect(
      scenarioRepair['nextAction'],
      containsPair('scenarioPatch', isA<Map<String, Object?>>()),
    );
    expect(stderr, isEmpty);
  });

  test(
    'drive dry-run treats runtime-permission profile coverage as interactive',
    () async {
      final environment = await createTestEnvironment();
      final scenario = File(
        '${environment.workingDirectory.path}/doc/fluoh/sample_permissions/scenarios/android-runtime-permission.md',
      );
      await scenario.parent.create(recursive: true);
      await scenario.writeAsString('''
kind: fluoh.automationScenario
schema: 1
name: android runtime permission profile coverage
platform: android
coverage:
  - category: runtime-permission
    item: camera
    path: grant
steps:
  - action: assertText
    labels: [Camera permission granted]
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
      final automation = report['automation'] as Map<String, Object?>;
      final coveragePolicy =
          automation['coveragePolicy'] as Map<String, Object?>;
      final scenarioEvidence =
          (coveragePolicy['scenarioEvidence'] as List<Object?>)
              .cast<Map<String, Object?>>();
      final binding =
          ((scenarioEvidence.single['coverageEvidenceBindings']
                      as List<Object?>)
                  .cast<Map<String, Object?>>())
              .single;
      expect(binding, containsPair('status', 'needsFunctionalEvidence'));
      expect(binding['missingReasons'], contains('missingInteractionStep'));
      final repairQueue = (automation['repairQueue'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(repairQueue, contains(containsPair('type', 'scenarioEvidence')));
      expect(stderr, isEmpty);
    },
  );

  test('drive dry-run allows explanatory coverage without assertions', () async {
    final environment = await createTestEnvironment();
    final scenario = File(
      '${environment.workingDirectory.path}/doc/fluoh/sample/explanatory-coverage.md',
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
      '${environment.workingDirectory.path}/doc/fluoh/sample/invalid-coverage.md',
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
      '${environment.workingDirectory.path}/doc/fluoh/sample/blocked-coverage.md',
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
}
