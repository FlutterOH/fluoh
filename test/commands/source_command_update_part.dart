part of 'source_command_test.dart';

void _registerSourceCommandUpdateTests() {
  test(
    'source sync resolves local package repository urls from source manifests',
    () async {
      final environment = await createTestEnvironment();
      final source = Directory(
        '${environment.homeDirectory.path}/local_source',
      );
      final packageRepository = Directory(
        '${environment.homeDirectory.path}/packages_implementation',
      );
      const repositoryUrl = '../packages_implementation';
      final stdout = <String>[];
      final stderr = <String>[];

      await runFluoh(
        ['source', 'init', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      await _writePackageManifest(
        packageRepository,
        repositoryUrl: repositoryUrl,
      );
      await _writeSourceSyncManifest(
        source,
        packageRepository,
        repositoryUrl: repositoryUrl,
      );
      await initializeGitRepository(packageRepository);
      await _runGit(packageRepository, [
        'tag',
        'camera-0.11.0-ohos-3.35-0.2.0',
      ]);

      expect(
        await runFluoh(
          ['source', 'sync', source.path],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final manifest = File(
        '${source.path}/manifests/camera/fluoh.yaml',
      ).readAsStringSync();
      expect(manifest, contains('url: ../packages_implementation'));
      expect(manifest, contains('upstream:\n            version: 0.11.0'));
      expect(stderr, isEmpty);
    },
  );

  test(
    'source sync resolves relative source paths from the working directory',
    () async {
      final environment = await createTestEnvironment();
      final source = Directory(
        '${environment.workingDirectory.path}/local_source',
      );
      final packageRepository = Directory(
        '${environment.workingDirectory.path}/packages_implementation',
      );
      final stdout = <String>[];
      final stderr = <String>[];

      await runFluoh(
        ['source', 'init', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      await _writePackageManifest(packageRepository);
      await _writeSourceSyncManifest(source, packageRepository);
      await initializeGitRepository(packageRepository);
      await _runGit(packageRepository, [
        'tag',
        'camera-0.11.0-ohos-3.35-0.2.0',
      ]);

      expect(
        await runFluoh(
          ['source', 'sync', 'local_source'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      expect(
        File('${source.path}/manifests/camera/fluoh.yaml').readAsStringSync(),
        contains('upstream:\n            version: 0.11.0'),
      );
      expect(
        stdout,
        contains(
          'Synced source metadata for camera from ${packageRepository.path}',
        ),
      );
      expect(stderr, isEmpty);
    },
  );

  test('source sync writes releases to routed source manifests', () async {
    final environment = await createTestEnvironment();
    final source = Directory('${environment.homeDirectory.path}/local_source');
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/packages_implementation',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'init', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    await _writePackageManifest(packageRepository);
    await _writeSourceSyncManifest(
      source,
      packageRepository,
      manifestName: 'camera',
    );
    await initializeGitRepository(packageRepository);
    await _runGit(packageRepository, ['tag', 'camera-0.11.0-ohos-3.35-0.2.0']);

    expect(
      await runFluoh(
        ['source', 'sync', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(
      File('${source.path}/fluoh.yaml').readAsStringSync(),
      contains('manifests:\n  - name: camera'),
    );
    final manifest = File(
      '${source.path}/manifests/camera/fluoh.yaml',
    ).readAsStringSync();
    expect(manifest, contains('name: camera'));
    expect(manifest, contains('upstream:\n            version: 0.11.0'));
    expect(
      File('${source.path}/manifests/packages/fluoh.yaml').existsSync(),
      isFalse,
    );
    expect(stderr, isEmpty);
  });

  test(
    'source sync ignores upstream branch changes from release manifests',
    () async {
      final environment = await createTestEnvironment();
      final source = Directory(
        '${environment.homeDirectory.path}/local_source',
      );
      final packageRepository = Directory(
        '${environment.homeDirectory.path}/packages_implementation',
      );
      final stdout = <String>[];
      final stderr = <String>[];

      await runFluoh(
        ['source', 'init', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      await _writePackageManifest(packageRepository);
      await _writeSourceSyncManifest(source, packageRepository);
      await initializeGitRepository(packageRepository);
      await _runGit(packageRepository, [
        'tag',
        'camera-0.11.0-ohos-3.35-0.2.0',
      ]);
      await runFluoh(
        ['source', 'sync', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );

      final packageManifest = File('${packageRepository.path}/fluoh.yaml');
      await packageManifest.writeAsString(
        packageManifest
            .readAsStringSync()
            .replaceFirst('branch: main', 'branch: develop')
            .replaceFirst('version: "0.2.0"', 'version: "0.3.0"'),
      );
      await commitAll(
        packageRepository,
        message: 'Release develop branch metadata',
      );
      await _runGit(packageRepository, [
        'tag',
        'camera-0.11.0-ohos-3.35-0.3.0',
      ]);

      expect(
        await runFluoh(
          ['source', 'sync', source.path],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final manifest = File(
        '${source.path}/manifests/camera/fluoh.yaml',
      ).readAsStringSync();
      expect(manifest, isNot(contains('branch: develop')));
      expect(manifest, contains('- version: 0.2.0'));
      expect(manifest, contains('- version: 0.3.0'));
      expect(stderr, isEmpty);
    },
  );

  test(
    'source sync does not create tool config for standalone sources',
    () async {
      final environment = await createTestEnvironment();
      final source = Directory(
        '${environment.homeDirectory.path}/local_source',
      );
      final packageRepository = Directory(
        '${environment.homeDirectory.path}/packages_implementation',
      );
      final configFile = File('${environment.homeDirectory.path}/config.json');
      final lockFile = File(
        '${environment.homeDirectory.path}/sources.lock.json',
      );
      final stdout = <String>[];
      final stderr = <String>[];

      await runFluoh(
        ['source', 'init', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      await _writePackageManifest(packageRepository);
      await _writeSourceSyncManifest(source, packageRepository);
      await initializeGitRepository(packageRepository);
      await _runGit(packageRepository, [
        'tag',
        'camera-0.11.0-ohos-3.35-0.2.0',
      ]);

      expect(configFile.existsSync(), isFalse);
      expect(lockFile.existsSync(), isFalse);

      expect(
        await runFluoh(
          ['source', 'sync', source.path],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      expect(
        File('${source.path}/manifests/camera/fluoh.yaml').readAsStringSync(),
        contains('upstream:\n            version: 0.11.0'),
      );
      expect(configFile.existsSync(), isFalse);
      expect(lockFile.existsSync(), isFalse);
      expect(stderr, isEmpty);
    },
  );

  test(
    'source sync treats repositories without release tags as no-op',
    () async {
      final environment = await createTestEnvironment();
      final source = Directory(
        '${environment.homeDirectory.path}/local_source',
      );
      final packageRepository = Directory(
        '${environment.homeDirectory.path}/packages_implementation',
      );
      final stdout = <String>[];
      final stderr = <String>[];

      await runFluoh(
        ['source', 'init', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      await _writePackageManifest(packageRepository);
      await _writeSourceSyncManifest(source, packageRepository);
      await initializeGitRepository(packageRepository);

      expect(
        await runFluoh(
          ['source', 'sync', source.path],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      expect(stdout, contains('No packages were synced'));
      expect(stderr, isEmpty);
    },
  );

  test('source sync treats sources without manifest routes as no-op', () async {
    final environment = await createTestEnvironment();
    final source = Directory('${environment.homeDirectory.path}/local_source');
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'init', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    stdout.clear();

    expect(
      await runFluoh(
        ['source', 'sync', '--json', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('command', 'source sync'));
    expect(report, containsPair('synced', 0));
    expect(report['plan'], isEmpty);
    expect(report['packages'], isEmpty);
    expect(stderr, isEmpty);
  });

  test(
    'source sync skips frozen packages before release tag validation',
    () async {
      final environment = await createTestEnvironment();
      final source = Directory(
        '${environment.homeDirectory.path}/local_source',
      );
      final packageRepository = Directory(
        '${environment.homeDirectory.path}/packages_implementation',
      );
      final stdout = <String>[];
      final stderr = <String>[];

      await runFluoh(
        ['source', 'init', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      await _writePackageManifest(packageRepository);
      await _writeSourceSyncManifest(source, packageRepository);
      await initializeGitRepository(packageRepository);
      await _runGit(packageRepository, [
        'tag',
        'camera-0.11.0-ohos-3.35-0.2.0',
      ]);
      await runFluoh(
        ['source', 'sync', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );

      final sourceRepository = File(
        '${source.path}/manifests/camera/fluoh.yaml',
      );
      await sourceRepository.writeAsString(
        sourceRepository.readAsStringSync().replaceFirst('  sdks:', '''
  maintenance:
    frozen: true
    note: Upstream now supports OHOS.
  sdks:'''),
      );
      final before = sourceRepository.readAsStringSync();
      final packageManifest = File('${packageRepository.path}/fluoh.yaml');
      await packageManifest.writeAsString(
        packageManifest
            .readAsStringSync()
            .replaceFirst(
              '    upstream:\n      version: "0.11.0"\n      commit:',
              '    upstream:\n      version: "0.12.0"\n      commit:',
            )
            .replaceFirst('version: "0.2.0"', 'version: "0.3.0"'),
      );
      await commitAll(packageRepository, message: 'Release frozen package');
      await _runGit(packageRepository, [
        'tag',
        'camera-0.12.0-ohos-3.35-0.3.0',
      ]);

      expect(
        await runFluoh(
          ['source', 'sync', source.path],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      expect(sourceRepository.readAsStringSync(), before);
      expect(
        stdout,
        contains(
          'Skipped source metadata update for camera because maintenance.frozen is true',
        ),
      );
      expect(stderr, isEmpty);
    },
  );

  test('source init preserves existing local source files', () async {
    final environment = await createTestEnvironment();
    final source = Directory('${environment.homeDirectory.path}/local_source');
    await Directory('${source.path}/manifests/camera').create(recursive: true);
    final repository = File('${source.path}/manifests/camera/fluoh.yaml');
    await repository.writeAsString('''
schema: 1
kind: manifest

repository:
  git:
    url: git@github.com:FlutterOH/camera.git

upstream:
  git:
    url: https://github.com/flutter/packages

package:
  name: camera
  path: packages/camera/camera
  sdks:
    "3.35":
      releases:
        - version: 1
          upstream:
            version: "0.11.0"
            ref: camera-v0.11.0
            commit: "1111111111111111111111111111111111111111"
''');
    final metadata = File('${source.path}/fluoh.yaml');
    await metadata.writeAsString('''
schema: 1
kind: source
name: existing-source
description: existing-source.
repository:
  git:
    url: file:${source.path}
manifests:
  - name: camera
''');
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['source', 'init', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(repository.readAsStringSync(), contains('name: camera'));
    expect(metadata.readAsStringSync(), contains('name: existing-source'));
    expect(Directory('${source.path}/manifests').existsSync(), isTrue);
    expect(
      stdout,
      contains('Local source template already exists at ${source.path}'),
    );
    expect(stderr, isEmpty);
  });

  test('updates local path sources from their original directories', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(
      environment.workingDirectory,
    );
    final cachedSource = Directory(
      '${environment.homeDirectory.path}/sources/local',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['source', 'enable', 'local', 'package_source'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );
    final config =
        jsonDecode(
              File(
                '${environment.homeDirectory.path}/config.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    final sources = config['sources'] as Map<String, Object?>;
    final local = sources['local'] as Map<String, Object?>;
    expect(local['path'], cachedSource.path);
    expect(local['url'], Uri.file(source.path).toString());

    final sourceManifest = File('${source.path}/manifests/camera/fluoh.yaml');
    final lock = File('${environment.homeDirectory.path}/sources.lock.json');
    final previousSnapshotHash = _lockSourceSnapshotHash(lock, 'local');
    await sourceManifest.writeAsString(
      '${sourceManifest.readAsStringSync()}# edited source snapshot\n',
    );
    stdout.clear();
    stderr.clear();

    expect(
      await runFluoh(
        ['source', 'update', 'local'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(File('${cachedSource.path}/fluoh.yaml').existsSync(), isTrue);
    expect(
      File(
        '${cachedSource.path}/manifests/camera/fluoh.yaml',
      ).readAsStringSync(),
      contains('# edited source snapshot'),
    );
    expect(_lockSourceSnapshotHash(lock, 'local'), isNot(previousSnapshotHash));
    expect(Directory('${cachedSource.path}/.git').existsSync(), isFalse);
    expect(stdout, contains('Updated source local'));
    expect(stderr, isEmpty);
  });

  test(
    'rejects unsafe source names without replacing target directories',
    () async {
      final environment = await createTestEnvironment();
      final source = Directory(
        '${environment.homeDirectory.path}/package_source',
      );
      await source.create(recursive: true);
      await File('${source.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: source
name: package-source
description: Package source.

repository:
  git:
    url: file:${source.path}
sdk:
  git:
    url: ${environment.homeDirectory.path}/flutter-ohos-sdk
  versions:
    - 3.35.8-ohos-0.0.3
''');
      final victim = Directory('${environment.homeDirectory.path}/victim');
      await victim.create(recursive: true);
      await File('${victim.path}/keep.txt').writeAsString('user file\n');
      final stdout = <String>[];
      final stderr = <String>[];

      expect(
        await runFluoh(
          ['source', 'enable', '../victim', source.path],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        64,
      );

      expect(stdout, isEmpty);
      expect(stderr.join('\n'), contains('Invalid source name "../victim"'));
      expect(File('${victim.path}/keep.txt').readAsStringSync(), 'user file\n');
      expect(File('${victim.path}/fluoh.yaml').existsSync(), isFalse);
    },
  );

  test(
    'keeps existing cache when enabling an invalid local path source',
    () async {
      final environment = await createTestEnvironment();
      final validSource = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      final invalidSource = Directory(
        '${environment.homeDirectory.path}/invalid',
      );
      await invalidSource.create(recursive: true);
      await File('${invalidSource.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: source
name: Invalid
description: Invalid source.

repository:
  git:
    url: file:${invalidSource.path}
manifests:
  - name: missing
''');
      final cachedSdkIndex = File(
        '${environment.homeDirectory.path}/sources/local/fluoh.yaml',
      );
      final stdout = <String>[];
      final stderr = <String>[];

      expect(
        await runFluoh(
          ['source', 'enable', 'local', validSource.path],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );
      final previousSnapshot = cachedSdkIndex.readAsStringSync();

      expect(
        await runFluoh(
          ['source', 'enable', 'local', invalidSource.path],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        64,
      );

      expect(stderr.join('\n'), contains('Source local could not be read'));
      expect(cachedSdkIndex.readAsStringSync(), previousSnapshot);
      expect(Directory(invalidSource.path).existsSync(), isTrue);
      expect(File('${invalidSource.path}/fluoh.yaml').existsSync(), isTrue);
    },
  );

  test('does not allow replacing the official source', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['source', 'enable', 'flutteroh', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );
    expect(stderr.join('\n'), contains('Cannot replace the official source.'));
  });

  test('disables non-default sources but keeps the official source', () async {
    final baseEnvironment = await createTestEnvironment();
    final defaultSource = await createPackageSourceFixture(
      baseEnvironment.homeDirectory.parent,
    );
    await initializeGitRepository(defaultSource);
    final environment = FluohEnvironment(
      homeDirectory: baseEnvironment.homeDirectory,
      workingDirectory: baseEnvironment.workingDirectory,
      processEnvironment: {
        'FLUOH_DEFAULT_SOURCE_URL': 'file://${defaultSource.path}',
      },
    );
    final source = await createPackageSourceFixture(environment.homeDirectory);
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['source', 'enable', 'team', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );
    expect(
      await runFluoh(
        ['source', 'disable', 'team'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );
    expect(
      await runFluoh(
        ['source', 'list'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(stdout, contains('Disabled source team'));
    expect(stdout.last, '[1] flutteroh file://${defaultSource.path}');

    expect(
      await runFluoh(
        ['source', 'disable', 'flutteroh'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );
    expect(stderr.join('\n'), contains('Cannot disable the official source.'));
  });

  test('reports unknown source names for update and disable', () async {
    final environment = await createTestEnvironment();
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['source', 'update', 'missing'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );
    expect(stderr.join('\n'), contains('Unknown source "missing".'));

    stderr.clear();
    expect(
      await runFluoh(
        ['source', 'disable', 'missing'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );
    expect(stderr.join('\n'), contains('Unknown source "missing".'));
  });
}
