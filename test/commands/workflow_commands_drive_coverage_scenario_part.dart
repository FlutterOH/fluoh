part of 'workflow_commands_test.dart';

void _registerWorkflowCommandsDriveCoverageScenarioTests() {
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
}
