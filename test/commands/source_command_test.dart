import 'dart:io';

import 'package:fluoh/fluoh.dart';
import 'package:test/test.dart';

import '../helpers/fluoh_test_context.dart';

void main() {
  test('does not repair sources when showing nested command help', () async {
    final baseEnvironment = await createTestEnvironment();
    final defaultSource = await createPubSourceFixture(
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
    final configFile = File('${environment.homeDirectory.path}/config.json');
    final sourceCache = Directory(
      '${environment.homeDirectory.path}/sources/flutteroh-pub',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await environment.homeDirectory.delete(recursive: true);

    expect(
      await runFluoh(
        ['source', '--help'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(configFile.existsSync(), isFalse);
    expect(sourceCache.existsSync(), isFalse);
    expect(stdout, isEmpty);
    expect(stderr, isEmpty);
  });

  test('lists the default FlutterOH source before user configuration', () async {
    final baseEnvironment = await createTestEnvironment();
    final defaultSource = await createPubSourceFixture(
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
    final configFile = File('${environment.homeDirectory.path}/config.json');
    final stdout = <String>[];
    final stderr = <String>[];

    await environment.homeDirectory.delete(recursive: true);

    expect(
      await runFluoh(
        ['source', 'list'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(stdout, contains('flutteroh file://${defaultSource.path}'));
    expect(configFile.existsSync(), isTrue);
    expect(
      configFile.readAsStringSync(),
      contains('file://${defaultSource.path}'),
    );
    expect(
      File(
        '${environment.homeDirectory.path}/sources/flutteroh-pub/sdk/index.yaml',
      ).existsSync(),
      isTrue,
    );
    expect(stderr, isEmpty);
  });

  test('validates source configuration when source has no subcommand', () async {
    final baseEnvironment = await createTestEnvironment();
    final defaultSource = await createPubSourceFixture(
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
    final configFile = File('${environment.homeDirectory.path}/config.json');
    final stdout = <String>[];
    final stderr = <String>[];

    await environment.homeDirectory.delete(recursive: true);

    expect(
      await runFluoh(
        ['source'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );

    expect(configFile.existsSync(), isTrue);
    expect(
      configFile.readAsStringSync(),
      contains('file://${defaultSource.path}'),
    );
    expect(
      File(
        '${environment.homeDirectory.path}/sources/flutteroh-pub/sdk/index.yaml',
      ).existsSync(),
      isTrue,
    );
    expect(stderr.join('\n'), contains('Missing subcommand'));
  });

  test('repairs missing private git source snapshots when listing', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    await initializeGitRepository(source);
    final cachePath = '${environment.homeDirectory.path}/sources/private';
    await File('${environment.homeDirectory.path}/config.json').writeAsString(
      '''
{
  "sources": {
    "private": {
      "path": "$cachePath",
      "url": "file://${source.path}",
      "priority": 100
    }
  }
}
''',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['source', 'list'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(stdout, contains('private file://${source.path}'));
    expect(File('$cachePath/sdk/index.yaml').existsSync(), isTrue);
    expect(stderr, isEmpty);
  });

  test('repairs invalid private git source snapshots when listing', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    await initializeGitRepository(source);
    final cachePath = '${environment.homeDirectory.path}/sources/private';
    await Directory('$cachePath/packages').create(recursive: true);
    await File(
      '${source.path}/packages/registry.yaml',
    ).copy('$cachePath/packages/registry.yaml');
    await File('${environment.homeDirectory.path}/config.json').writeAsString(
      '''
{
  "sources": {
    "private": {
      "path": "$cachePath",
      "url": "file://${source.path}",
      "priority": 100
    }
  }
}
''',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['source', 'list'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(stdout, contains('private file://${source.path}'));
    expect(
      File('$cachePath/packages/manifests/camera.yaml').existsSync(),
      isTrue,
    );
    expect(stderr, isEmpty);
  });

  test('reports missing local source snapshots when listing', () async {
    final environment = await createTestEnvironment();
    final cachePath = '${environment.homeDirectory.path}/sources/local';
    await File('${environment.homeDirectory.path}/config.json').writeAsString(
      '''
{
  "sources": {
    "local": {
      "path": "$cachePath",
      "priority": 100
    }
  }
}
''',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['source', 'list'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );

    expect(stdout, isEmpty);
    expect(stderr.join('\n'), contains('Source local cache is missing'));
    expect(stderr.join('\n'), contains('fluoh source add local <path>'));
  });

  test('reports malformed source configuration without replacing it', () async {
    final environment = await createTestEnvironment();
    final configFile = File('${environment.homeDirectory.path}/config.json');
    await configFile.writeAsString('{');
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['source', 'list'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );

    expect(configFile.readAsStringSync(), '{');
    expect(stderr.join('\n'), contains('fluoh config'));
  });

  test('adds, lists, and updates a named pub source', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    await Directory('${source.path}/docs').create(recursive: true);
    await File('${source.path}/docs/notes.md').writeAsString('# Notes\n');
    await Directory(
      '${source.path}/packages/artifacts',
    ).create(recursive: true);
    await File(
      '${source.path}/packages/artifacts/cache.bin',
    ).writeAsString('unused');
    final cachedSource = Directory(
      '${environment.homeDirectory.path}/sources/fixture',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['source', 'add', 'fixture', source.path],
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
    expect(
      await runFluoh(
        ['source', 'update', 'fixture'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(stdout, contains('Added source fixture: ${source.path}'));
    expect(stdout, contains('fixture ${cachedSource.path}'));
    expect(stdout, contains('Updated source fixture.'));
    expect(File('${cachedSource.path}/sdk/index.yaml').existsSync(), isTrue);
    expect(
      File('${cachedSource.path}/packages/registry.yaml').existsSync(),
      isTrue,
    );
    expect(
      File('${cachedSource.path}/packages/manifests/camera.yaml').existsSync(),
      isTrue,
    );
    expect(File('${cachedSource.path}/docs/notes.md').existsSync(), isFalse);
    expect(
      File('${cachedSource.path}/packages/artifacts/cache.bin').existsSync(),
      isFalse,
    );
    expect(Directory('${cachedSource.path}/.git').existsSync(), isFalse);
    expect(stderr, isEmpty);
  });

  test('adds local path sources as isolated cache snapshots', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    final cachedSource = Directory(
      '${environment.homeDirectory.path}/sources/local',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['source', 'add', 'local', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );
    await File('${source.path}/sdk/index.yaml').writeAsString('not: valid');

    expect(
      await runFluoh(
        ['source', 'update', 'local'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(File('${cachedSource.path}/sdk/index.yaml').existsSync(), isTrue);
    expect(
      File('${cachedSource.path}/sdk/index.yaml').readAsStringSync(),
      isNot('not: valid'),
    );
    expect(Directory('${cachedSource.path}/.git').existsSync(), isFalse);
    expect(stdout, contains('Updated source local.'));
    expect(stderr, isEmpty);
  });

  test(
    'keeps existing cache when adding an invalid local path source',
    () async {
      final environment = await createTestEnvironment();
      final validSource = await createPubSourceFixture(
        environment.homeDirectory,
      );
      final invalidSource = Directory(
        '${environment.homeDirectory.path}/invalid',
      );
      await Directory('${invalidSource.path}/sdk').create(recursive: true);
      await File('${invalidSource.path}/sdk/index.yaml').writeAsString('''
schema: 1
repositoryUrl: ${environment.homeDirectory.path}/flutter-ohos-sdk
versions: {}
''');
      final cachedSdkIndex = File(
        '${environment.homeDirectory.path}/sources/local/sdk/index.yaml',
      );
      final stdout = <String>[];
      final stderr = <String>[];

      expect(
        await runFluoh(
          ['source', 'add', 'local', validSource.path],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );
      final previousSnapshot = cachedSdkIndex.readAsStringSync();

      expect(
        await runFluoh(
          ['source', 'add', 'local', invalidSource.path],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        64,
      );

      expect(stderr.join('\n'), contains('Source local is not valid'));
      expect(cachedSdkIndex.readAsStringSync(), previousSnapshot);
      expect(Directory(invalidSource.path).existsSync(), isTrue);
      expect(File('${invalidSource.path}/sdk/index.yaml').existsSync(), isTrue);
    },
  );

  test('does not allow replacing the official source', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['source', 'add', 'flutteroh', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );
    expect(stderr.join('\n'), contains('Cannot replace the official source.'));
  });

  test('removes non-default sources but keeps the official source', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['source', 'add', 'team', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );
    expect(
      await runFluoh(
        ['source', 'remove', 'team'],
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

    expect(stdout, contains('Removed source team.'));
    expect(stdout.last, 'flutteroh https://github.com/FlutterOH/pub.git');

    expect(
      await runFluoh(
        ['source', 'remove', 'flutteroh'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );
    expect(stderr.join('\n'), contains('Cannot remove the official source.'));
  });

  test('reports unknown source names for update and remove', () async {
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
        ['source', 'remove', 'missing'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );
    expect(stderr.join('\n'), contains('Unknown source "missing".'));
  });

  test('updates a git source URL into the local source cache', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    await Directory('${source.path}/docs').create(recursive: true);
    await File('${source.path}/docs/notes.md').writeAsString('# Notes\n');
    await Directory(
      '${source.path}/packages/artifacts',
    ).create(recursive: true);
    await File(
      '${source.path}/packages/artifacts/cache.bin',
    ).writeAsString('unused');
    await initializeGitRepository(source);
    final sourceUrl = 'file://${source.path}';
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['source', 'add', 'remote', sourceUrl],
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

    expect(stdout, contains('Added source remote: $sourceUrl'));
    expect(stdout, contains('Updated source remote.'));
    expect(
      File(
        '${environment.homeDirectory.path}/sources/remote/sdk/index.yaml',
      ).existsSync(),
      isTrue,
    );
    expect(
      File(
        '${environment.homeDirectory.path}/sources/remote/packages/registry.yaml',
      ).existsSync(),
      isTrue,
    );
    expect(
      File(
        '${environment.homeDirectory.path}/sources/remote/packages/manifests/camera.yaml',
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
      File(
        '${environment.homeDirectory.path}/sources/remote/packages/artifacts/cache.bin',
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
      final source = await createPubSourceFixture(environment.homeDirectory);
      await initializeGitRepository(source);
      final cachedSdkIndex = File(
        '${environment.homeDirectory.path}/sources/remote/sdk/index.yaml',
      );
      final sourceUrl = 'file://${source.path}';
      final stdout = <String>[];
      final stderr = <String>[];

      expect(
        await runFluoh(
          ['source', 'add', 'remote', sourceUrl],
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

      await File('${source.path}/sdk/index.yaml').writeAsString('''
schema: 1
repositoryUrl: ${environment.homeDirectory.path}/flutter-ohos-sdk
versions: {}
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

      expect(stderr.join('\n'), contains('Source remote is not valid'));
      expect(cachedSdkIndex.readAsStringSync(), previousSnapshot);
      expect(
        Directory('${cachedSdkIndex.parent.parent.path}/.git').existsSync(),
        isFalse,
      );
    },
  );

  test(
    'updates all sources and accepts package-only supplemental sources',
    () async {
      final environment = await createTestEnvironment();
      final supplemental = Directory(
        '${environment.homeDirectory.path}/supplemental',
      );
      await Directory('${supplemental.path}/packages').create(recursive: true);
      await File('${supplemental.path}/packages/registry.yaml').writeAsString(
        '''
schema: 1
packages: []
''',
      );
      final stdout = <String>[];
      final stderr = <String>[];

      expect(
        await runFluoh(
          ['source', 'add', 'team', supplemental.path, '--priority', '200'],
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

      expect(stdout, contains('Updated source team.'));
      expect(stderr, isEmpty);
    },
  );

  test('updates a YAML source', () async {
    final environment = await createTestEnvironment();
    final source = Directory('${environment.homeDirectory.path}/schema_source');
    await Directory('${source.path}/sdk').create(recursive: true);
    await Directory('${source.path}/packages').create(recursive: true);
    await File('${source.path}/sdk/index.yaml').writeAsString('''
schema: 1
repositoryUrl: ${environment.homeDirectory.path}/flutter-ohos-sdk
versions:
  - version: 3.35.8-ohos-0.0.3
    tag: 3.35.8-ohos-0.0.3
    status: stable
''');
    await File('${source.path}/packages/registry.yaml').writeAsString('''
schema: 1
packages: []
''');
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['source', 'add', 'schema', source.path],
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

    expect(stdout, contains('Updated source schema.'));
    expect(stderr, isEmpty);
  });

  test('reports missing package manifests when adding local sources', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    await File('${source.path}/packages/manifests/camera.yaml').delete();
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['source', 'add', 'broken', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );

    expect(stderr.join('\n'), contains('Source broken could not be read'));
    expect(stderr.join('\n'), contains('camera.yaml'));
  });

  test('reports invalid local source indexes as usage errors', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    await File('${source.path}/sdk/index.yaml').writeAsString('''
schema: 1
repositoryUrl: ${environment.homeDirectory.path}/flutter-ohos-sdk
versions: {}
''');
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['source', 'add', 'broken', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );

    expect(stderr.join('\n'), contains('Source broken is not valid'));
    expect(stderr.join('\n'), contains('SDK source versions must be a list.'));
  });
}
