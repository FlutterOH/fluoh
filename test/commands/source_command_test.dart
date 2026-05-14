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
      '${environment.homeDirectory.path}/sources/flutteroh',
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
    expect(stdout.join('\n'), contains('Available subcommands:'));
    expect(stdout.join('\n'), contains('Use configured sources:'));
    expect(stdout.join('\n'), contains('Maintain source repositories:'));
    expect(stdout.join('\n'), contains('  list'));
    expect(stdout.join('\n'), contains('  sync'));
    expect(stderr, isEmpty);
  });

  test(
    'lists the default FlutterOH source before user configuration',
    () async {
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

      expect(stdout, contains('[1] flutteroh file://${defaultSource.path}'));
      expect(configFile.existsSync(), isTrue);
      expect(
        configFile.readAsStringSync(),
        contains('file://${defaultSource.path}'),
      );
      expect(
        File(
          '${environment.homeDirectory.path}/sources/flutteroh/fluoh.yaml',
        ).existsSync(),
        isTrue,
      );
      final lock = File('${environment.homeDirectory.path}/sources.lock.json');
      expect(lock.existsSync(), isTrue);
      expect(lock.readAsStringSync(), isNot(contains('"schema"')));
      expect(stderr, isEmpty);
    },
  );

  test(
    'validates source configuration when source has no subcommand',
    () async {
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
          '${environment.homeDirectory.path}/sources/flutteroh/fluoh.yaml',
        ).existsSync(),
        isTrue,
      );
      expect(stderr.join('\n'), contains('Missing subcommand'));
    },
  );

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

    expect(stdout, contains('[1] private file://${source.path}'));
    expect(File('$cachePath/fluoh.yaml').existsSync(), isTrue);
    expect(stderr, isEmpty);
  });

  test('repairs invalid private git source snapshots when listing', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    await initializeGitRepository(source);
    final cachePath = '${environment.homeDirectory.path}/sources/private';
    await Directory(cachePath).create(recursive: true);
    await File('${source.path}/fluoh.yaml').copy('$cachePath/fluoh.yaml');
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

    expect(stdout, contains('[1] private file://${source.path}'));
    expect(File('$cachePath/manifests/camera/fluoh.yaml').existsSync(), isTrue);
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

  test(
    'reports invalid source priority without throwing a stack trace',
    () async {
      final environment = await createTestEnvironment();
      final cachePath = '${environment.homeDirectory.path}/sources/local';
      await File('${environment.homeDirectory.path}/config.json').writeAsString(
        '''
{
  "sources": {
    "local": {
      "path": "$cachePath",
      "priority": "high"
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
      expect(stderr.join('\n'), contains('source priority must be an integer'));
      expect(stderr.join('\n'), isNot(contains('Unhandled exception')));
    },
  );

  test('reports invalid configured source names before syncing', () async {
    final environment = await createTestEnvironment();
    final victim = Directory('${environment.homeDirectory.path}/victim');
    await victim.create(recursive: true);
    await File('${victim.path}/keep.txt').writeAsString('user file\n');
    await File('${environment.homeDirectory.path}/config.json').writeAsString(
      '''
{
  "sources": {
    "../victim": {
      "path": "${environment.homeDirectory.path}/sources/../victim",
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
    expect(stderr.join('\n'), contains('Invalid source name "../victim"'));
    expect(File('${victim.path}/keep.txt').readAsStringSync(), 'user file\n');
  });

  test('adds, lists, and updates a named pub source', () async {
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
    expect(stdout, contains('[2] fixture ${cachedSource.path}'));
    expect(stdout, contains('Updated source fixture.'));
    expect(File('${cachedSource.path}/fluoh.yaml').existsSync(), isTrue);
    expect(
      File('${cachedSource.path}/manifests/camera/fluoh.yaml').existsSync(),
      isTrue,
    );
    final lock = File('${environment.homeDirectory.path}/sources.lock.json');
    expect(lock.existsSync(), isTrue);
    expect(lock.readAsStringSync(), contains('"fixture"'));
    expect(lock.readAsStringSync(), contains('"camera"'));
    expect(Directory('${cachedSource.path}/packages').existsSync(), isFalse);
    expect(Directory('${cachedSource.path}/.git').existsSync(), isFalse);
    expect(stderr, isEmpty);
  });

  test('creates a complete local source template', () async {
    final environment = await createTestEnvironment();
    final source = Directory('${environment.homeDirectory.path}/local_source');
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
    expect(
      await runFluoh(
        ['source', 'add', 'local', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(File('${source.path}/fluoh.yaml').readAsStringSync(), '''
schema: 1
kind: source
name: "Local FlutterOH source"
description: "Local FlutterOH source maintained by fluoh users."

repository:
  git:
    url: "file:${source.path}"

environment:
  fluoh: ">=0.1.0"

# Uncomment to publish Flutter OHOS SDK versions from this source.
# sdk:
#   git:
#     url: "https://github.com/openharmony-sig/flutter_flutter.git"
#   versions:
#     - 3.35.8-ohos-0.0.3

# Uncomment after editing manifests/example/fluoh.yaml, or run:
# fluoh source sync . <pub-repo-path>
# manifests:
#   - name: example
''');
    expect(
      File('${source.path}/manifests/example/fluoh.yaml').readAsStringSync(),
      contains('# kind: manifest'),
    );
    expect(File('${source.path}/README.md').existsSync(), isTrue);
    expect(
      stdout,
      contains('Created local source template at ${source.path}.'),
    );
    expect(
      stdout,
      contains('Edit manifest files directly, or sync released packages with:'),
    );
    expect(
      stdout,
      contains('  fluoh source sync ${source.path} <pub-repo-path>'),
    );
    expect(
      stdout,
      contains('Add it with: fluoh source add <name> ${source.path}'),
    );
    expect(stdout, contains('Added source local: ${source.path}'));
    expect(stderr, isEmpty);
  });

  test('source init creates an editable empty source scaffold', () async {
    final environment = await createTestEnvironment();
    final source = Directory('${environment.homeDirectory.path}/local_source');
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
    expect(
      await runFluoh(
        ['source', 'add', 'empty', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final content = File('${source.path}/fluoh.yaml').readAsStringSync();
    expect(content, contains('# sdk:'));
    expect(content, contains('# manifests:'));
    expect(content, contains('# fluoh source sync . <pub-repo-path>'));
    expect(content, isNot(contains('manifests: []')));
    expect(
      File('${source.path}/manifests/example/fluoh.yaml').readAsStringSync(),
      contains('# name: example'),
    );
    final lock = File(
      '${environment.homeDirectory.path}/sources.lock.json',
    ).readAsStringSync();
    expect(lock, contains('"versions": {}'));
    expect(lock, contains('"packages": {}'));

    expect(
      stdout,
      contains('Created local source template at ${source.path}.'),
    );
    expect(stdout, contains('Added source empty: ${source.path}'));
    expect(stderr, isEmpty);
  });

  test('source sync imports released pub repository manifests', () async {
    final environment = await createTestEnvironment();
    final source = Directory('${environment.homeDirectory.path}/local_source');
    final pubRepository = Directory(
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
    await _writePubRepositoryManifest(pubRepository);
    await initializeGitRepository(pubRepository);
    await _runGit(pubRepository, ['tag', 'camera-0.11.0-ohos-3.35-0.2.0']);
    final pubManifest = File('${pubRepository.path}/fluoh.yaml');
    await pubManifest.writeAsString(
      pubManifest
          .readAsStringSync()
          .replaceFirst('version: 0.2.0', 'version: 0.3.0')
          .replaceFirst('upstreamVersion: 0.11.0', 'upstreamVersion: 0.12.0'),
    );

    expect(
      await runFluoh(
        ['source', 'sync', source.path, pubRepository.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(
      File('${source.path}/fluoh.yaml').readAsStringSync(),
      contains('manifests:\n  - name: packages'),
    );
    final manifest = File(
      '${source.path}/manifests/packages/fluoh.yaml',
    ).readAsStringSync();
    expect(manifest, contains('name: packages'));
    expect(manifest, contains('url: "git@github.com:FlutterOH/packages.git"'));
    expect(manifest, contains('upstreamVersion: 0.11.0'));
    expect(manifest, contains('- version: 0.2.0'));
    expect(manifest, isNot(contains('upstreamVersion: 0.12.0')));
    expect(manifest, isNot(contains('- version: 0.3.0')));
    expect(manifest, isNot(contains('status: experimental')));
    expect(
      stdout,
      contains('Synced source metadata for camera from ${pubRepository.path}.'),
    );
    expect(stderr, isEmpty);
  });

  test(
    'source sync follows upstream branch changes from release manifests',
    () async {
      final environment = await createTestEnvironment();
      final source = Directory(
        '${environment.homeDirectory.path}/local_source',
      );
      final pubRepository = Directory(
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
      await _writePubRepositoryManifest(pubRepository);
      await initializeGitRepository(pubRepository);
      await _runGit(pubRepository, ['tag', 'camera-0.11.0-ohos-3.35-0.2.0']);
      await runFluoh(
        ['source', 'sync', source.path, pubRepository.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );

      final pubManifest = File('${pubRepository.path}/fluoh.yaml');
      await pubManifest.writeAsString(
        pubManifest
            .readAsStringSync()
            .replaceFirst('branch: main', 'branch: develop')
            .replaceFirst('version: 0.2.0', 'version: 0.3.0'),
      );
      await commitAll(
        pubRepository,
        message: 'Release develop branch metadata',
      );
      await _runGit(pubRepository, ['tag', 'camera-0.11.0-ohos-3.35-0.3.0']);

      expect(
        await runFluoh(
          ['source', 'sync', source.path, pubRepository.path],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final manifest = File(
        '${source.path}/manifests/packages/fluoh.yaml',
      ).readAsStringSync();
      expect(manifest, contains('branch: develop'));
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
      final pubRepository = Directory(
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
      await _writePubRepositoryManifest(pubRepository);
      await initializeGitRepository(pubRepository);
      await _runGit(pubRepository, ['tag', 'camera-0.11.0-ohos-3.35-0.2.0']);

      expect(configFile.existsSync(), isFalse);
      expect(lockFile.existsSync(), isFalse);

      expect(
        await runFluoh(
          ['source', 'sync', source.path, pubRepository.path],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      expect(
        File('${source.path}/manifests/packages/fluoh.yaml').readAsStringSync(),
        contains('upstreamVersion: 0.11.0'),
      );
      expect(configFile.existsSync(), isFalse);
      expect(lockFile.existsSync(), isFalse);
      expect(stderr, isEmpty);
    },
  );

  test('source sync requires released tags', () async {
    final environment = await createTestEnvironment();
    final source = Directory('${environment.homeDirectory.path}/local_source');
    final pubRepository = Directory(
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
    await _writePubRepositoryManifest(pubRepository);
    await initializeGitRepository(pubRepository);

    expect(
      await runFluoh(
        ['source', 'sync', source.path, pubRepository.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );

    expect(
      stderr.join('\n'),
      contains('No released Package fluoh.yaml records found'),
    );
  });

  test(
    'source sync skips frozen packages before release tag validation',
    () async {
      final environment = await createTestEnvironment();
      final source = Directory(
        '${environment.homeDirectory.path}/local_source',
      );
      final pubRepository = Directory(
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
      await _writePubRepositoryManifest(pubRepository);
      await initializeGitRepository(pubRepository);
      await _runGit(pubRepository, ['tag', 'camera-0.11.0-ohos-3.35-0.2.0']);
      await runFluoh(
        ['source', 'sync', source.path, pubRepository.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );

      final sourceRepository = File(
        '${source.path}/manifests/packages/fluoh.yaml',
      );
      await sourceRepository.writeAsString(
        sourceRepository.readAsStringSync().replaceFirst('    sdks:', '''
    maintenance:
      status: frozen
      reason: Upstream now supports OHOS.
    sdks:'''),
      );
      final before = sourceRepository.readAsStringSync();
      final pubManifest = File('${pubRepository.path}/fluoh.yaml');
      await pubManifest.writeAsString(
        pubManifest
            .readAsStringSync()
            .replaceFirst('upstreamVersion: 0.11.0', 'upstreamVersion: 0.12.0')
            .replaceFirst('version: 0.2.0', 'version: 0.3.0'),
      );

      expect(
        await runFluoh(
          ['source', 'sync', source.path, pubRepository.path],
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
          'Skipped source metadata update for camera because maintenance.status is frozen.',
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
name: camera

repository:
  git:
    url: git@github.com:FlutterOH/camera.git

upstream:
  git:
    url: https://github.com/flutter/packages
    branch: main

packages:
  camera:
    sdks:
      "3.35":
        releases:
          - version: 1
            upstreamVersion: "0.11.0"
''');
    final metadata = File('${source.path}/fluoh.yaml');
    await metadata.writeAsString('''
schema: 1
kind: source
name: Existing source
description: Existing source.
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
    expect(metadata.readAsStringSync(), contains('name: Existing source'));
    expect(Directory('${source.path}/manifests').existsSync(), isTrue);
    expect(
      stdout,
      contains('Local source template already exists at ${source.path}.'),
    );
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
    await File('${source.path}/fluoh.yaml').writeAsString('not: valid');

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
      File('${cachedSource.path}/fluoh.yaml').readAsStringSync(),
      isNot('not: valid'),
    );
    expect(Directory('${cachedSource.path}/.git').existsSync(), isFalse);
    expect(stdout, contains('Updated source local.'));
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
name: Package source
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
          ['source', 'add', '../victim', source.path],
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
    'keeps existing cache when adding an invalid local path source',
    () async {
      final environment = await createTestEnvironment();
      final validSource = await createPubSourceFixture(
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

      expect(stderr.join('\n'), contains('Source local could not be read'));
      expect(cachedSdkIndex.readAsStringSync(), previousSnapshot);
      expect(Directory(invalidSource.path).existsSync(), isTrue);
      expect(File('${invalidSource.path}/fluoh.yaml').existsSync(), isTrue);
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
    expect(stdout.last, '[1] flutteroh file://${defaultSource.path}');

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

  test('updates a file URL source into the local source cache', () async {
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
      final source = await createPubSourceFixture(environment.homeDirectory);
      await initializeGitRepository(source);
      final cachedSdkIndex = File(
        '${environment.homeDirectory.path}/sources/remote/fluoh.yaml',
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
      final firstSource = await createPubSourceFixture(firstParent);
      final remoteSource = await createPubSourceFixture(remoteParent);
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
      final cachedManifest = File(
        '${environment.homeDirectory.path}/sources/remote/manifests/camera/fluoh.yaml',
      );
      final stdout = <String>[];
      final stderr = <String>[];

      expect(
        await runFluoh(
          [
            'source',
            'add',
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
            'add',
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
      final previousSnapshot = cachedManifest.readAsStringSync();

      final remoteManifest = File(
        '${remoteSource.path}/manifests/camera/fluoh.yaml',
      );
      await remoteManifest.writeAsString(
        remoteManifest.readAsStringSync().replaceAll(
          '${firstParent.path}/camera',
          '${remoteParent.path}/camera',
        ),
      );
      await commitAll(remoteSource, message: 'Change camera repository URL');

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
        contains('Conflicting OHOS implementation camera'),
      );
      expect(cachedManifest.readAsStringSync(), previousSnapshot);
      expect(
        cachedManifest.readAsStringSync(),
        isNot(contains('${remoteParent.path}/camera')),
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
name: Supplemental
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
name: team

repository:
  git:
    url: ${environment.homeDirectory.path}/team

upstream:
  git:
    url: https://github.com/example/team

packages:
  team_package:
    sdks:
      "3.35":
        releases:
          - version: 0.1.0
            upstreamVersion: 1.0.0
''');
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

  test('rejects sources that require a newer fluoh version', () async {
    final environment = await createTestEnvironment();
    final source = Directory('${environment.homeDirectory.path}/future_source');
    await source.create(recursive: true);
    await File('${source.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: source
name: Future source
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
        ['source', 'add', 'future', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );

    expect(stdout, isEmpty);
    expect(stderr.join('\n'), contains('Requires fluoh >=999.0.0'));
    expect(stderr.join('\n'), contains('current version is $packageVersion'));
  });

  test('updates a YAML source', () async {
    final environment = await createTestEnvironment();
    final source = Directory('${environment.homeDirectory.path}/schema_source');
    await source.create(recursive: true);
    await File('${source.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: source
name: Schema source
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

  test('rejects unsupported source fluoh.yaml schema versions', () async {
    final environment = await createTestEnvironment();
    final source = Directory('${environment.homeDirectory.path}/schema_source');
    await source.create(recursive: true);
    await File('${source.path}/fluoh.yaml').writeAsString('''
schema: 2
name: Future source
repository: file:${source.path}
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
      64,
    );

    expect(stdout, isEmpty);
    expect(
      stderr.join('\n'),
      contains('Source schema is not valid: fluoh.yaml schema 2'),
    );
  });

  test(
    'reports missing repository manifests when adding local sources',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPubSourceFixture(environment.homeDirectory);
      await File('${source.path}/manifests/camera/fluoh.yaml').delete();
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
      expect(stderr.join('\n'), contains('manifests/camera/fluoh.yaml'));
    },
  );

  test('reports invalid local source indexes as usage errors', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
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
        ['source', 'add', 'broken', source.path],
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

Future<void> _writePubRepositoryManifest(Directory repository) async {
  await repository.create(recursive: true);
  await File('${repository.path}/fluoh.yaml').writeAsString('''
schema: 1
name: packages

sdk:
  version: 3.35.8-ohos-0.0.3

repository:
  git:
    url: git@github.com:FlutterOH/packages.git
    branch: ohos/3.35

upstream:
  git:
    url: https://github.com/flutter/packages
    branch: main

packages:
  camera:
    repository:
      path: packages/camera/camera
    upstream:
      path: packages/camera/camera
    version: 0.2.0
    upstreamVersion: 0.11.0
''');
}

Future<ProcessResult> _runGit(Directory repo, List<String> arguments) async {
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: repo.path,
  );
  if (result.exitCode != 0) {
    fail('git ${arguments.join(' ')} failed:\n${result.stderr}');
  }
  return result;
}
