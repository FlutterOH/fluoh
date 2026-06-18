import 'dart:convert';
import 'dart:io';

import 'package:fluoh/fluoh.dart';
import 'package:test/test.dart';

import '../helpers/fluoh_command_context.dart';
import '../helpers/package_test_context.dart';

void main() {
  test('package scope init creates a package support scope', () async {
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
        ['package', 'scope', 'init', '--package', 'camera', '--json'],
        environment: packageEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final result = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(result, containsPair('command', 'package scope init'));
    expect(result, containsPair('ok', true));
    expect(result, containsPair('path', 'doc/fluoh/camera/scope.yaml'));
    final scope = result['supportScope'] as Map<String, Object?>;
    expect(scope, containsPair('exists', true));
    expect(scope, containsPair('p0Count', 0));
    expect(result, containsPair('seededFromSpec', false));
    expect(result, containsPair('seededScopeEntries', 0));
    expect(result, containsPair('seededPlatformRows', 0));
    expect(
      await File(
        '${packageRepository.path}/doc/fluoh/camera/scope.yaml',
      ).exists(),
      true,
    );
    expect(stderr, isEmpty);
  });

  test('package scope init seeds rows from reviewed package spec', () async {
    final environment = await createTestEnvironment();
    final packageRepository = await createPackageRepositoryFixture(environment);
    final spec = File('${packageRepository.path}/doc/fluoh/camera/spec.md');
    await spec.writeAsString('''
# camera FlutterOH Spec

Reviewed upstream commit fixture.

## Support Scope Seeds

| Scope entry | Priority | Platform | Role | Decision | Reason/source | Test case |
| --- | --- | --- | --- | --- | --- | --- |
| camera_preview | P0 | ohos | implementationTarget | supported | OHOS Camera Kit API reviewed | camera_preview_launch |
| camera_preview | P0 | android | preserveBaseline | preserved | Upstream Android implementation reviewed | android_camera_preview_regression |

## Upstream Review Notes

- Reviewed fixture baseline.
''');
    final packageEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['package', 'scope', 'init', '--package', 'camera', '--json'],
        environment: packageEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final result = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(result, containsPair('seededFromSpec', true));
    expect(result, containsPair('seededScopeEntries', 1));
    expect(result, containsPair('seededPlatformRows', 2));
    final scope = result['supportScope'] as Map<String, Object?>;
    expect(scope, containsPair('scopeEntryCount', 1));
    expect(scope, containsPair('p0Count', 1));
    expect(scope, containsPair('planningReady', true));
    expect(scope, containsPair('functionalEvidenceReady', false));
    expect(scope['targetPlatforms'], containsAll(['android', 'ohos']));
    final matrix = scope['platformMatrix'] as List<Object?>;
    expect(
      matrix,
      contains(
        allOf(
          isA<Map<String, Object?>>(),
          containsPair('scopeEntry', 'camera_preview'),
          containsPair('platform', 'android'),
          containsPair('support', 'preserved'),
        ),
      ),
    );
    final content = await File(
      '${packageRepository.path}/doc/fluoh/camera/scope.yaml',
    ).readAsString();
    expect(content, contains('id: "camera_preview"'));
    expect(content, contains('"android":'));
    expect(content, contains('android_camera_preview_regression'));
    expect(stderr, isEmpty);
  });

  test('package scope check reports missing P0 scope entries', () async {
    final environment = await createTestEnvironment();
    final packageRepository = await createPackageRepositoryFixture(environment);
    final packageEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    final initStdout = <String>[];
    expect(
      await runFluoh(
        ['package', 'scope', 'init', '--package', 'camera', '--json'],
        environment: packageEnvironment,
        stdout: initStdout.add,
        stderr: (_) {},
      ),
      0,
    );

    final stdout = <String>[];
    final stderr = <String>[];
    expect(
      await runFluoh(
        ['package', 'scope', 'check', '--package', 'camera', '--json'],
        environment: packageEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      1,
    );

    final result = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(result, containsPair('command', 'package scope check'));
    expect(result, containsPair('ok', false));
    final scope = result['supportScope'] as Map<String, Object?>;
    expect(scope, containsPair('planningReady', false));
    final issues = scope['issues'] as List<Object?>;
    expect(
      issues,
      contains(
        isA<Map<String, Object?>>().having(
          (issue) => issue['code'],
          'code',
          'scope.p0_missing',
        ),
      ),
    );
    expect(stderr, isEmpty);
  });

  test('package scope check passes with P0 functional evidence', () async {
    final environment = await createTestEnvironment();
    final packageRepository = await createPackageRepositoryFixture(environment);
    await _writeScopeNotes(packageRepository);
    final packageEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['package', 'scope', 'check', '--package', 'camera', '--json'],
        environment: packageEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final result = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(result, containsPair('command', 'package scope check'));
    expect(result, containsPair('ok', true));
    final scope = result['supportScope'] as Map<String, Object?>;
    expect(scope, containsPair('planningReady', true));
    expect(scope, containsPair('functionalEvidenceReady', true));
    expect(scope, containsPair('complete', true));
    expect(stderr, isEmpty);
  });

  test('package scope check rejects flat scope rows', () async {
    final environment = await createTestEnvironment();
    final packageRepository = await createPackageRepositoryFixture(environment);
    await _writeFlatScopeNotes(packageRepository);
    final packageEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['package', 'scope', 'check', '--package', 'camera', '--json'],
        environment: packageEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      1,
    );

    final result = jsonDecode(stdout.single) as Map<String, Object?>;
    final scope = result['supportScope'] as Map<String, Object?>;
    expect(scope, containsPair('planningReady', false));
    final issues = scope['issues'] as List<Object?>;
    expect(
      issues,
      contains(
        allOf(
          isA<Map<String, Object?>>(),
          containsPair('code', 'scope.p0_platforms_missing'),
          containsPair('field', 'platforms'),
        ),
      ),
    );
    expect(stderr, isEmpty);
  });

  test('package scope check reports platform matrix evidence gaps', () async {
    final environment = await createTestEnvironment();
    final packageRepository = await createPackageRepositoryFixture(environment);
    await _writePlatformMatrixNotes(packageRepository);
    final packageEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['package', 'scope', 'check', '--package', 'camera', '--json'],
        environment: packageEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      1,
    );

    final result = jsonDecode(stdout.single) as Map<String, Object?>;
    final scope = result['supportScope'] as Map<String, Object?>;
    expect(scope, containsPair('planningReady', true));
    expect(scope, containsPair('functionalEvidenceReady', false));
    expect(scope['targetPlatforms'], containsAll(['android', 'ohos']));
    final matrix = scope['platformMatrix'] as List<Object?>;
    expect(
      matrix,
      contains(
        allOf(
          isA<Map<String, Object?>>(),
          containsPair('platform', 'android'),
          containsPair('support', 'preserved'),
          containsPair('needsFunctionalEvidence', true),
        ),
      ),
    );
    final issues = scope['issues'] as List<Object?>;
    expect(
      issues,
      contains(
        allOf(
          isA<Map<String, Object?>>(),
          containsPair('code', 'scope.p0_functional_evidence_missing'),
          containsPair('platform', 'android'),
          containsPair('field', 'platforms.android.evidence.level'),
        ),
      ),
    );
    expect(stderr, isEmpty);
  });

  test('package scope check requires rows for declared platforms', () async {
    final environment = await createTestEnvironment();
    final packageRepository = await createPackageRepositoryFixture(environment);
    await _writeMissingDeclaredPlatformNotes(packageRepository);
    final packageEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['package', 'scope', 'check', '--package', 'camera', '--json'],
        environment: packageEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      1,
    );

    final result = jsonDecode(stdout.single) as Map<String, Object?>;
    final scope = result['supportScope'] as Map<String, Object?>;
    expect(scope, containsPair('planningReady', false));
    final issues = scope['issues'] as List<Object?>;
    expect(
      issues,
      contains(
        allOf(
          isA<Map<String, Object?>>(),
          containsPair('code', 'scope.p0_platform_row_missing'),
          containsPair('platform', 'android'),
          containsPair('field', 'platforms.android'),
        ),
      ),
    );
    expect(stderr, isEmpty);
  });

  test('package scope status does not fail on incomplete scope', () async {
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
        ['package', 'scope', 'status', '--package', 'camera', '--json'],
        environment: packageEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final result = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(result, containsPair('command', 'package scope status'));
    expect(result, containsPair('ok', true));
    final scope = result['supportScope'] as Map<String, Object?>;
    expect(scope, containsPair('exists', false));
    expect(
      result,
      containsPair(
        'nextCommand',
        'fluoh package scope init --package camera --json',
      ),
    );
    expect(stderr, isEmpty);
  });
}

Future<void> _writeMissingDeclaredPlatformNotes(
  Directory packageRepository,
) async {
  final scope = File('${packageRepository.path}/doc/fluoh/camera/scope.yaml');
  await scope.parent.create(recursive: true);
  await scope.writeAsString('''
schema: 1
kind: fluoh.packageScope
package: camera
platform: ohos
targetPlatforms:
  - ohos
  - android
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
          status: done
        tests:
          required: true
          cases:
            - camera_preview_launch
        evidence:
          level: functional
''');
}

Future<void> _writePlatformMatrixNotes(Directory packageRepository) async {
  final scope = File('${packageRepository.path}/doc/fluoh/camera/scope.yaml');
  await scope.parent.create(recursive: true);
  await scope.writeAsString('''
schema: 1
kind: fluoh.packageScope
package: camera
platform: ohos
targetPlatforms:
  - ohos
  - android
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
          status: done
        tests:
          required: true
          cases:
            - camera_preview_launch
        evidence:
          level: functional
      android:
        role: preserveBaseline
        decision:
          support: preserved
          confidence: medium
          reason: Existing upstream Android camera preview must keep working.
          sources:
            - title: Upstream Android camera implementation
              path: android/src/main
        tests:
          required: true
          cases:
            - android_camera_preview_regression
        evidence:
          level: none
''');
}

Future<void> _writeScopeNotes(Directory packageRepository) async {
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
          status: done
          files:
            - ohos/src/main/ets/CameraPlugin.ets
          tasks:
            - map preview startup
        tests:
          required: true
          cases:
            - camera_preview_launch
        evidence:
          level: functional
''');
}

Future<void> _writeFlatScopeNotes(Directory packageRepository) async {
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
    decision:
      support: supported
      confidence: medium
      reason: OHOS camera API supports preview startup.
      sources:
        - title: OHOS camera API
          url: https://example.invalid/ohos-camera
    implementation:
      status: done
    tests:
      required: true
      cases:
        - camera_preview_launch
    evidence:
      level: functional
''');
}
