import 'dart:convert';
import 'dart:io';

import 'package:fluoh/fluoh.dart';
import 'package:test/test.dart';

import '../helpers/fluoh_test_context.dart';

void main() {
  test('checks dependency compatibility and emits json', () async {
    final environment = await _preparedEnvironment();
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['deps', 'check'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );
    expect(
      await runFluoh(
        ['deps', 'check', '--json'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(stdout, contains('camera adapted camera-v0.11.0-ohos-3.35.8-1'));
    expect(
      stdout,
      contains('share_plus version-mismatch share_plus-v9.0.0-ohos-3.35.8-1'),
    );
    expect(stdout, contains('mystery_package unknown'));

    final jsonReport = jsonDecode(stdout.last) as Map<String, Object?>;
    final dependencies = jsonReport['dependencies'] as List<Object?>;
    expect(
      dependencies,
      contains(
        allOf(
          containsPair('name', 'camera'),
          containsPair('status', 'adapted'),
          containsPair('direct', true),
        ),
      ),
    );
    expect(
      dependencies,
      contains(
        allOf(
          containsPair('name', 'camera_platform_interface'),
          containsPair('dependencyChain', [
            'camera',
            'camera_platform_interface',
          ]),
        ),
      ),
    );
    expect(stderr, isEmpty);
  });

  test(
    'plans and writes tag-based overrides only for direct adapted packages',
    () async {
      final environment = await _preparedEnvironment();
      final stdout = <String>[];
      final stderr = <String>[];

      expect(
        await runFluoh(
          ['deps', 'fix'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );
      expect(
        File(
          '${environment.workingDirectory.path}/pubspec.yaml',
        ).readAsStringSync(),
        isNot(contains('dependency_overrides')),
      );

      expect(
        await runFluoh(
          ['deps', 'fix', '--yes'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final pubspec = File(
        '${environment.workingDirectory.path}/pubspec.yaml',
      ).readAsStringSync();
      expect(
        stdout,
        contains('Would override camera -> camera-v0.11.0-ohos-3.35.8-1'),
      );
      expect(stdout, contains('Wrote 1 dependency override.'));
      expect(pubspec, contains('dependency_overrides:'));
      expect(pubspec, contains('camera-v0.11.0-ohos-3.35.8-1'));
      expect(pubspec, contains('path: packages/camera/camera'));
      expect(pubspec, isNot(contains('camera_platform_interface:')));
      expect(pubspec, isNot(contains('share_plus-v9.0.0-ohos-3.35.8-1')));
      expect(stderr, isEmpty);
    },
  );

  test('rewrites direct dependencies instead of writing overrides', () async {
    final environment = await _preparedEnvironment();
    final pubspecFile = File(
      '${environment.workingDirectory.path}/pubspec.yaml',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['deps', 'fix', '--yes', '--rewrite'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final pubspec = pubspecFile.readAsStringSync();
    expect(pubspec, contains('dependencies:'));
    expect(pubspec, contains('  camera:'));
    expect(pubspec, contains('    git:'));
    expect(pubspec, contains('camera-v0.11.0-ohos-3.35.8-1'));
    expect(pubspec, contains('path: packages/camera/camera'));
    expect(pubspec, isNot(contains('dependency_overrides:')));
    expect(stderr, isEmpty);
  });

  test('selects adapter version 10 over version 9 numerically', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    final packageIndexFile = File(
      '${source.path}/generated/package-index.json',
    );
    final packageIndex =
        jsonDecode(packageIndexFile.readAsStringSync()) as Map<String, Object?>;
    final packages = packageIndex['packages'] as Map<String, Object?>;
    final camera = packages['camera'] as Map<String, Object?>;
    camera['adapters'] = [
      {
        'sdkLine': '3.35',
        'upstreamVersion': '0.11.0',
        'repository': '${environment.homeDirectory.path}/camera',
        'tag': 'camera-v0.11.0-ohos-3.35.8-9',
      },
      {
        'sdkLine': '3.35',
        'upstreamVersion': '0.11.0',
        'repository': '${environment.homeDirectory.path}/camera',
        'tag': 'camera-v0.11.0-ohos-3.35.8-10',
      },
    ];
    await packageIndexFile.writeAsString(jsonEncode(packageIndex));
    await writeFlutterProjectFixture(environment.workingDirectory);
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'add', 'fixture', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    await runFluoh(
      ['source', 'use', 'fixture'],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    await runFluoh(
      ['use', '3.35'],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(
      await runFluoh(
        ['deps', 'check'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );
    expect(stdout, contains('camera adapted camera-v0.11.0-ohos-3.35.8-10'));
    expect(stderr, isEmpty);
  });

  test('stops when equal-priority sources disagree on an adapter', () async {
    final environment = await createTestEnvironment();
    final firstSource = await createPubSourceFixture(
      Directory('${environment.homeDirectory.path}/first'),
    );
    final secondSource = await createPubSourceFixture(
      Directory('${environment.homeDirectory.path}/second'),
    );
    await File('${secondSource.path}/generated/sdk-index.json').writeAsString(
      File('${firstSource.path}/generated/sdk-index.json').readAsStringSync(),
    );
    final packageIndexFile = File(
      '${secondSource.path}/generated/package-index.json',
    );
    final packageIndex =
        jsonDecode(packageIndexFile.readAsStringSync()) as Map<String, Object?>;
    final packages = packageIndex['packages'] as Map<String, Object?>;
    final camera = packages['camera'] as Map<String, Object?>;
    final adapters = camera['adapters'] as List<Object?>;
    final adapter = adapters.first as Map<String, Object?>;
    adapter['repository'] = '${environment.homeDirectory.path}/different';
    await packageIndexFile.writeAsString(jsonEncode(packageIndex));
    await writeFlutterProjectFixture(environment.workingDirectory);
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'add', 'first', firstSource.path, '--priority', '100'],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    await runFluoh(
      ['source', 'add', 'second', secondSource.path, '--priority', '100'],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    await runFluoh(
      ['source', 'use', 'first'],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    await runFluoh(
      ['use', '3.35'],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(
      await runFluoh(
        ['deps', 'check'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );
    expect(stderr.join('\n'), contains('Conflicting package adapter'));
  });

  test(
    'uses higher-priority compatibility status for overlapping sources',
    () async {
      final environment = await createTestEnvironment();
      final lowPrioritySource = await createPubSourceFixture(
        Directory('${environment.homeDirectory.path}/low'),
      );
      final highPrioritySource = await createPubSourceFixture(
        Directory('${environment.homeDirectory.path}/high'),
      );
      await File(
        '${highPrioritySource.path}/generated/sdk-index.json',
      ).writeAsString(
        File(
          '${lowPrioritySource.path}/generated/sdk-index.json',
        ).readAsStringSync(),
      );
      await _setCompatibilityStatus(
        lowPrioritySource,
        sdkLine: '3.35',
        packageName: 'camera',
        status: 'native',
      );
      await _setCompatibilityStatus(
        highPrioritySource,
        sdkLine: '3.35',
        packageName: 'camera',
        status: 'blocked',
      );
      await writeFlutterProjectFixture(environment.workingDirectory);
      final stdout = <String>[];
      final stderr = <String>[];

      await runFluoh(
        ['source', 'add', 'low', lowPrioritySource.path, '--priority', '100'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      await runFluoh(
        ['source', 'add', 'high', highPrioritySource.path, '--priority', '200'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      await runFluoh(
        ['source', 'use', 'high'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      await runFluoh(
        ['use', '3.35'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );

      expect(
        await runFluoh(
          ['deps', 'check'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );
      expect(stdout, contains('camera blocked camera-v0.11.0-ohos-3.35.8-1'));
      expect(stderr, isEmpty);
    },
  );
}

Future<FluohEnvironment> _preparedEnvironment() async {
  final environment = await createTestEnvironment();
  final source = await createPubSourceFixture(environment.homeDirectory);
  await writeFlutterProjectFixture(environment.workingDirectory);
  final stdout = <String>[];
  final stderr = <String>[];

  await runFluoh(
    ['source', 'add', 'fixture', source.path],
    environment: environment,
    stdout: stdout.add,
    stderr: stderr.add,
  );
  await runFluoh(
    ['source', 'use', 'fixture'],
    environment: environment,
    stdout: stdout.add,
    stderr: stderr.add,
  );
  await runFluoh(
    ['use', '3.35'],
    environment: environment,
    stdout: stdout.add,
    stderr: stderr.add,
  );

  return environment;
}

Future<void> _setCompatibilityStatus(
  Directory source, {
  required String sdkLine,
  required String packageName,
  required String status,
}) async {
  final matrixFile = File('${source.path}/generated/compatibility-matrix.json');
  final matrix =
      jsonDecode(matrixFile.readAsStringSync()) as Map<String, Object?>;
  final sdkLines = matrix['sdkLines'] as Map<String, Object?>;
  final line = sdkLines[sdkLine] as Map<String, Object?>;
  for (final key in ['native', 'adapted', 'blocked']) {
    final packages = line[key] as List<Object?>;
    packages.remove(packageName);
  }
  (line[status] as List<Object?>).add(packageName);
  await matrixFile.writeAsString(jsonEncode(matrix));
}
