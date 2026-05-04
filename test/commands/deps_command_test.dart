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
    final manifest = File('${source.path}/packages/manifests/camera.yaml');
    await manifest.writeAsString(
      manifest
          .readAsStringSync()
          .replaceAll(
            'camera-v0.11.0-ohos-3.35.8-0',
            'camera-v0.11.0-ohos-3.35.8-9',
          )
          .replaceAll(
            'camera-v0.11.0-ohos-3.35.8-1',
            'camera-v0.11.0-ohos-3.35.8-10',
          ),
    );
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
      ['sdk', 'use', '3.35.8-ohos-0.0.3'],
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
    await File('${secondSource.path}/sdk/index.yaml').writeAsString(
      File('${firstSource.path}/sdk/index.yaml').readAsStringSync(),
    );
    final manifest = File(
      '${secondSource.path}/packages/manifests/camera.yaml',
    );
    await manifest.writeAsString(
      manifest.readAsStringSync().replaceAll(
        '${environment.homeDirectory.path}/second/camera',
        '${environment.homeDirectory.path}/different',
      ),
    );
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
      ['sdk', 'use', '3.35.8-ohos-0.0.3'],
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
      await File('${highPrioritySource.path}/sdk/index.yaml').writeAsString(
        File('${lowPrioritySource.path}/sdk/index.yaml').readAsStringSync(),
      );
      await _setCompatibilityStatus(
        lowPrioritySource,
        packageName: 'camera',
        status: 'compatible',
      );
      await _setCompatibilityStatus(
        highPrioritySource,
        packageName: 'camera',
        status: 'broken',
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
        ['sdk', 'use', '3.35.8-ohos-0.0.3'],
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

  test(
    'layers package-only supplemental sources over the official source',
    () async {
      final environment = await createTestEnvironment();
      final official = await createPubSourceFixture(
        Directory('${environment.homeDirectory.path}/official'),
      );
      final supplemental = Directory('${environment.homeDirectory.path}/team');
      await Directory(
        '${supplemental.path}/packages/manifests',
      ).create(recursive: true);
      await File('${supplemental.path}/packages/registry.yaml').writeAsString(
        '''
schema: 1
packages:
  - name: share_plus
    repositoryUrl: ${environment.homeDirectory.path}/share_plus
    packagePath: packages/share_plus/share_plus
''',
      );
      await File(
        '${supplemental.path}/packages/manifests/share_plus.yaml',
      ).writeAsString('''
schema: 1
package:
  name: share_plus
  repositoryUrl: ${environment.homeDirectory.path}/share_plus
  upstreamUrl: https://github.com/fluttercommunity/plus_plugins/tree/main/packages/share_plus/share_plus
  packagePath: packages/share_plus/share_plus
releases:
  - version: 10.0.0
    upstreamRef: share_plus-v10.0.0
    sdk:
      versionSeries: 3.35.8-ohos
      versions:
        - 3.35.8-ohos-0.0.3
    status: compatible
    sourceBranch: ohos/3.35.8-ohos-0.0.3
    release:
      version: "1"
      tag: share_plus-v10.0.0-ohos-3.35.8-1
    replacement:
      type: git
      url: ${environment.homeDirectory.path}/share_plus
      ref: share_plus-v10.0.0-ohos-3.35.8-1
      path: packages/share_plus/share_plus
''');
      await writeFlutterProjectFixture(environment.workingDirectory);
      final stdout = <String>[];
      final stderr = <String>[];

      await runFluoh(
        ['source', 'add', 'official', official.path, '--priority', '10'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      await runFluoh(
        ['source', 'add', 'team', supplemental.path, '--priority', '200'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      await runFluoh(
        ['sdk', 'use', '3.35.8-ohos-0.0.3'],
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

      expect(stdout, contains('camera adapted camera-v0.11.0-ohos-3.35.8-1'));
      expect(
        stdout,
        contains('share_plus adapted share_plus-v10.0.0-ohos-3.35.8-1'),
      );
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
    ['sdk', 'use', '3.35.8-ohos-0.0.3'],
    environment: environment,
    stdout: stdout.add,
    stderr: stderr.add,
  );

  return environment;
}

Future<void> _setCompatibilityStatus(
  Directory source, {
  required String packageName,
  required String status,
}) async {
  final manifest = File('${source.path}/packages/manifests/$packageName.yaml');
  final content = manifest.readAsStringSync();
  expect(content, contains('versionSeries: 3.35.8-ohos'));
  expect(content, contains('        - 3.35.8-ohos-0.0.3'));
  await manifest.writeAsString(
    content.replaceAll('status: compatible', 'status: $status'),
  );
}
