part of 'workflow_commands_test.dart';

void _registerWorkflowCommandsDrivePlanQualityTests() {
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
}
