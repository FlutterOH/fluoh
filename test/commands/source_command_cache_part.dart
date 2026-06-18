part of 'source_command_test.dart';

void _registerSourceCommandCacheTests() {
  test('updates a file URL source into the local source cache', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    await Directory('${source.path}/docs').create(recursive: true);
    await File('${source.path}/docs/notes.md').writeAsString('# Notes\n');
    await Directory(
      '${source.path}/packages/artifacts',
    ).create(recursive: true);
    await File(
      '${source.path}/packages/artifacts/cache.bin',
    ).writeAsString('unused');
    final sourceUrl = 'file://${source.path}';
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['source', 'enable', 'remote', sourceUrl],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );
    expect(
      await runFluoh(
        ['source', 'update', 'remote'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(stdout, contains('Enabled source remote: $sourceUrl'));
    expect(stdout, contains('Updated source remote'));
    expect(
      File(
        '${environment.homeDirectory.path}/sources/remote/fluoh.yaml',
      ).existsSync(),
      isTrue,
    );
    expect(
      File(
        '${environment.homeDirectory.path}/sources/remote/manifests/camera/fluoh.yaml',
      ).existsSync(),
      isTrue,
    );
    expect(
      File(
        '${environment.homeDirectory.path}/sources/remote/docs/notes.md',
      ).existsSync(),
      isFalse,
    );
    expect(
      Directory(
        '${environment.homeDirectory.path}/sources/remote/packages',
      ).existsSync(),
      isFalse,
    );
    expect(
      Directory(
        '${environment.homeDirectory.path}/sources/remote/.git',
      ).existsSync(),
      isFalse,
    );
    expect(stderr, isEmpty);
  });

  test(
    'keeps the previous git source snapshot when update validation fails',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      await initializeGitRepository(source);
      final cachedSdkIndex = File(
        '${environment.homeDirectory.path}/sources/remote/fluoh.yaml',
      );
      final sourceUrl = 'file://${source.path}';
      final stdout = <String>[];
      final stderr = <String>[];

      expect(
        await runFluoh(
          ['source', 'enable', 'remote', sourceUrl],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );
      expect(
        await runFluoh(
          ['source', 'update', 'remote'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );
      final previousSnapshot = cachedSdkIndex.readAsStringSync();

      await File('${source.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: source
name: Broken
description: Broken source.

repository:
  git:
    url: file:${source.path}

manifests:
  - name: missing
''');
      await commitAll(source, message: 'Break source fixture');

      expect(
        await runFluoh(
          ['source', 'update', 'remote'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        64,
      );

      expect(stderr.join('\n'), contains('Source remote could not be read'));
      expect(cachedSdkIndex.readAsStringSync(), previousSnapshot);
      expect(
        Directory('${cachedSdkIndex.parent.parent.path}/.git').existsSync(),
        isFalse,
      );
    },
  );

  test(
    'keeps the previous git source snapshot when update lock generation fails',
    () async {
      final environment = await createTestEnvironment();
      final firstParent = Directory('${environment.homeDirectory.path}/first');
      final remoteParent = Directory(
        '${environment.homeDirectory.path}/remote',
      );
      final firstSource = await createPackageSourceFixture(firstParent);
      final remoteSource = await createPackageSourceFixture(remoteParent);
      await File('${remoteSource.path}/fluoh.yaml').writeAsString(
        File('${remoteSource.path}/fluoh.yaml').readAsStringSync().replaceAll(
          '${remoteParent.path}/flutter-ohos-sdk',
          '${firstParent.path}/flutter-ohos-sdk',
        ),
      );
      await File(
        '${remoteSource.path}/manifests/camera/fluoh.yaml',
      ).writeAsString(
        File(
          '${remoteSource.path}/manifests/camera/fluoh.yaml',
        ).readAsStringSync().replaceAll(
          '${remoteParent.path}/camera',
          '${firstParent.path}/camera',
        ),
      );
      await File(
        '${remoteSource.path}/manifests/share_plus/fluoh.yaml',
      ).writeAsString(
        File(
          '${remoteSource.path}/manifests/share_plus/fluoh.yaml',
        ).readAsStringSync().replaceAll(
          '${remoteParent.path}/share_plus',
          '${firstParent.path}/share_plus',
        ),
      );
      await initializeGitRepository(firstSource);
      await initializeGitRepository(remoteSource);
      final cachedSourceRoot = File(
        '${environment.homeDirectory.path}/sources/remote/fluoh.yaml',
      );
      final stdout = <String>[];
      final stderr = <String>[];

      expect(
        await runFluoh(
          [
            'source',
            'enable',
            'first',
            'file://${firstSource.path}',
            '--priority',
            '10',
          ],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );
      expect(
        await runFluoh(
          [
            'source',
            'enable',
            'remote',
            'file://${remoteSource.path}',
            '--priority',
            '10',
          ],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );
      final previousSnapshot = cachedSourceRoot.readAsStringSync();

      final remoteRoot = File('${remoteSource.path}/fluoh.yaml');
      await remoteRoot.writeAsString(
        remoteRoot.readAsStringSync().replaceAll(
          '${firstParent.path}/flutter-ohos-sdk',
          '${remoteParent.path}/flutter-ohos-sdk',
        ),
      );
      await commitAll(remoteSource, message: 'Change SDK repository URL');

      expect(
        await runFluoh(
          ['source', 'update', 'remote'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        64,
      );

      expect(
        stderr.join('\n'),
        contains('Conflicting SDK version 3.35.8-ohos-0.0.3'),
      );
      expect(cachedSourceRoot.readAsStringSync(), previousSnapshot);
      expect(
        cachedSourceRoot.readAsStringSync(),
        isNot(contains('${remoteParent.path}/flutter-ohos-sdk')),
      );
    },
  );

  test(
    'updates all sources and accepts package metadata supplemental sources',
    () async {
      final environment = await createTestEnvironment();
      final supplemental = Directory(
        '${environment.homeDirectory.path}/supplemental',
      );
      await supplemental.create(recursive: true);
      await Directory(
        '${supplemental.path}/manifests/team',
      ).create(recursive: true);
      await File('${supplemental.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: source
name: supplemental
description: Supplemental source.

repository:
  git:
    url: file:${supplemental.path}

manifests:
  - name: team
''');
      await File(
        '${supplemental.path}/manifests/team/fluoh.yaml',
      ).writeAsString('''
schema: 1
kind: manifest

repository:
  git:
    url: ${environment.homeDirectory.path}/team

origin:
  kind: ported

upstream:
  git:
    url: https://github.com/example/team

package:
  name: team
  sdks:
    "3.35":
      releases:
        - version: 0.1.0
          tag: team-1.0.0-ohos-3.35-0.1.0
          upstream:
            version: 1.0.0
            ref: team-v1.0.0
            commit: "1111111111111111111111111111111111111111"
''');
      final stdout = <String>[];
      final stderr = <String>[];

      expect(
        await runFluoh(
          ['source', 'enable', 'team', supplemental.path, '--priority', '200'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );
      expect(
        await runFluoh(
          ['source', 'update', 'team'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      expect(stdout, contains('Updated source team'));
      expect(stderr, isEmpty);
    },
  );

  test('rejects source environment compatibility fields', () async {
    final environment = await createTestEnvironment();
    final source = Directory('${environment.homeDirectory.path}/future_source');
    await source.create(recursive: true);
    await File('${source.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: source
name: future-source
description: Future source.

repository:
  git:
    url: file:${source.path}

environment:
  fluoh: ">=999.0.0"

sdk:
  git:
    url: ${environment.homeDirectory.path}/flutter-ohos-sdk
  versions:
    - 3.35.8-ohos-0.0.3
''');
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['source', 'enable', 'future', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );

    expect(stdout, isEmpty);
    expect(
      stderr.join('\n'),
      contains(
        'Source future is not valid: fluoh.yaml must not contain "environment"',
      ),
    );
  });

  test('updates a YAML source', () async {
    final environment = await createTestEnvironment();
    final source = Directory('${environment.homeDirectory.path}/schema_source');
    await source.create(recursive: true);
    await File('${source.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: source
name: schema-source
description: Schema source.

repository:
  git:
    url: file:${source.path}

sdk:
  git:
    url: ${environment.homeDirectory.path}/flutter-ohos-sdk
  versions:
    - 3.35.8-ohos-0.0.3
''');
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['source', 'enable', 'schema', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(
      await runFluoh(
        ['source', 'update', 'schema'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(stdout, contains('Updated source schema'));
    expect(stderr, isEmpty);
  });

  test('rejects unsupported source fluoh.yaml schema versions', () async {
    final environment = await createTestEnvironment();
    final source = Directory('${environment.homeDirectory.path}/schema_source');
    await source.create(recursive: true);
    await File('${source.path}/fluoh.yaml').writeAsString('''
schema: 2
name: future-source
repository: file:${source.path}
''');
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['source', 'enable', 'schema', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );

    expect(stdout, isEmpty);
    expect(
      stderr.join('\n'),
      contains('Source schema is not valid: fluoh.yaml schema 2'),
    );
  });

  test(
    'reports missing repository manifests when enabling local sources',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      await File('${source.path}/manifests/camera/fluoh.yaml').delete();
      final stdout = <String>[];
      final stderr = <String>[];

      expect(
        await runFluoh(
          ['source', 'enable', 'broken', source.path],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        64,
      );

      expect(stderr.join('\n'), contains('Source broken could not be read'));
      expect(stderr.join('\n'), contains('manifests/camera/fluoh.yaml'));
    },
  );

  test('reports invalid local source indexes as usage errors', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    await File('${source.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: source
name: Broken
description: Broken source.

repository:
  git:
    url: file:${source.path}

sdk:
  git:
    url: ${environment.homeDirectory.path}/flutter-ohos-sdk
  versions: invalid
''');
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['source', 'enable', 'broken', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );

    expect(stderr.join('\n'), contains('Source broken is not valid'));
    expect(stderr.join('\n'), contains('sdk versions must be a YAML list'));
  });
}
