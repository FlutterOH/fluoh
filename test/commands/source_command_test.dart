import 'dart:io';
import 'dart:convert';

import 'package:fluoh/fluoh.dart';
import 'package:fluoh/src/schema/schema.dart' show sdkLineFromSdkVersion;
import 'package:fluoh/src/source/source_runtime.dart';
import 'package:test/test.dart';

import '../helpers/fluoh_command_context.dart';

void main() {
  test('does not repair sources when showing nested command help', () async {
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
    expect(stdout.join('\n'), contains('Configured sources:'));
    expect(stdout.join('\n'), contains('Source repositories:'));
    expect(stdout.join('\n'), contains('  list'));
    expect(stdout.join('\n'), contains('  sync'));
    expect(stdout.join('\n'), contains('  check'));
    expect(stderr, isEmpty);
  });

  test(
    'schema-only check validates a local source without config effects',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.workingDirectory,
      );
      final stdout = <String>[];
      final stderr = <String>[];

      expect(
        await runFluoh(
          ['source', 'check', 'package_source', '--schema-only', '--json'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      expect(stderr, isEmpty);
      expect(stdout, hasLength(1));
      final report = jsonDecode(stdout.single) as Map<String, Object?>;
      expect(report, containsPair('command', 'source check'));
      expect(report, containsPair('ok', true));
      expect(report, containsPair('exitCode', 0));
      expect(report, containsPair('schemaOnly', true));
      expect(report, isNot(contains('workRoot')));
      expect(report, containsPair('sourcePath', source.path));
      expect(
        report,
        containsPair('checkedManifests', ['camera', 'share_plus']),
      );
      expect(report, containsPair('releaseChecks', isEmpty));
      expect(report, containsPair('sdkChecks', isEmpty));
      expect(
        File('${environment.homeDirectory.path}/config.json').existsSync(),
        isFalse,
      );
      expect(
        File(
          '${environment.homeDirectory.path}/sources.lock.json',
        ).existsSync(),
        isFalse,
      );
    },
  );

  test(
    'schema-only check reports invalid source without config effects',
    () async {
      final environment = await createTestEnvironment();
      final source = Directory('${environment.workingDirectory.path}/broken');
      await source.create(recursive: true);
      await File('${source.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: source
name: broken-source
repository:
  git: {}
''');
      final stdout = <String>[];
      final stderr = <String>[];

      expect(
        await runFluoh(
          ['source', 'check', 'broken', '--schema-only', '--json'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        1,
      );

      expect(stderr, isEmpty);
      expect(stdout, hasLength(1));
      final report = jsonDecode(stdout.single) as Map<String, Object?>;
      expect(report, containsPair('command', 'source check'));
      expect(report, containsPair('ok', false));
      expect(report, containsPair('exitCode', 1));
      expect(report, containsPair('schemaOnly', true));
      expect(report, isNot(contains('workRoot')));
      final sourceValidation =
          report['sourceValidation'] as Map<String, Object?>;
      expect(sourceValidation, containsPair('ok', false));
      expect(
        sourceValidation['message'],
        contains('Source ${source.path} is not valid'),
      );
      expect(sourceValidation['message'], contains('Expected "url"'));
      expect(
        File('${environment.homeDirectory.path}/config.json').existsSync(),
        isFalse,
      );
      expect(
        File(
          '${environment.homeDirectory.path}/sources.lock.json',
        ).existsSync(),
        isFalse,
      );
    },
  );

  test('schema-only check rejects unknown manifest filters as json', () async {
    final environment = await createTestEnvironment();
    await createPackageSourceFixture(environment.workingDirectory);
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        [
          'source',
          'check',
          'package_source',
          '--schema-only',
          '--manifest',
          'missing',
          '--json',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      1,
    );

    expect(stderr, isEmpty);
    expect(stdout, hasLength(1));
    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('command', 'source check'));
    expect(report, containsPair('ok', false));
    expect(report, containsPair('exitCode', 1));
    expect(report, containsPair('schemaOnly', true));
    expect(report, containsPair('checkedManifests', isEmpty));
    expect(
      report['errors'],
      contains('Unknown Source manifest route filter: missing'),
    );
  });

  test('does not repair sources when list has unexpected arguments', () async {
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
    final configFile = File('${environment.homeDirectory.path}/config.json');
    final sourceCache = Directory(
      '${environment.homeDirectory.path}/sources/flutteroh',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await environment.homeDirectory.delete(recursive: true);

    expect(
      await runFluoh(
        ['source', 'list', 'extra'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );

    expect(configFile.existsSync(), isFalse);
    expect(sourceCache.existsSync(), isFalse);
    expect(stdout, isEmpty);
    expect(stderr.join('\n'), contains('Unexpected argument: extra.'));
  });

  test(
    'lists the default FlutterOH source before user configuration',
    () async {
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

  test('lists configured sources as json', () async {
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
    final stdout = <String>[];
    final stderr = <String>[];

    await environment.homeDirectory.delete(recursive: true);

    expect(
      await runFluoh(
        ['source', 'list', '--json'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(stdout, hasLength(1));
    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('schema', 1));
    expect(report, containsPair('command', 'source list'));
    expect(report, containsPair('ok', true));
    expect(report, containsPair('exitCode', 0));
    expect(report, containsPair('count', 1));
    final sources = report['sources'] as List<Object?>;
    expect(
      sources.single,
      allOf(
        containsPair('name', 'flutteroh'),
        containsPair('source', 'file://${defaultSource.path}'),
        containsPair('url', 'file://${defaultSource.path}'),
        containsPair(
          'path',
          '${environment.homeDirectory.path}/sources/flutteroh',
        ),
        containsPair('priority', 0),
      ),
    );
    expect(stderr, isEmpty);
  });

  test('lists sources as json without decorated repair progress', () async {
    final root = await Directory.systemTemp.createTemp('fluoh_cli_');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final home = Directory('${root.path}/home');
    final source = await createPackageSourceFixture(root);
    await initializeGitRepository(source);

    final result = await Process.run(
      Platform.resolvedExecutable,
      ['bin/fluoh.dart', 'source', 'list', '--json'],
      workingDirectory: Directory.current.path,
      environment: {
        ...Platform.environment,
        'FLUOH_HOME': home.path,
        'FLUOH_DEFAULT_SOURCE_URL': source.path,
        'FORCE_COLOR': '1',
        'TERM': 'xterm-256color',
      },
    );

    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(result.stderr, isEmpty);
    final output = result.stdout.toString();
    expect(output, isNot(contains('Syncing source')));
    final report = jsonDecode(output) as Map<String, Object?>;
    expect(report, containsPair('schema', 1));
    expect(report, containsPair('command', 'source list'));
    expect(report, containsPair('ok', true));
    expect(report, containsPair('exitCode', 0));
    expect(report, containsPair('count', 1));
  });

  test(
    'validates source configuration when source has no subcommand',
    () async {
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
    final source = await createPackageSourceFixture(environment.homeDirectory);
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
    final source = await createPackageSourceFixture(environment.homeDirectory);
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
    expect(stdout, contains('[2] fixture ${Uri.file(source.path)}'));
    expect(stdout, contains('Updated source fixture'));
    expect(File('${cachedSource.path}/fluoh.yaml').existsSync(), isTrue);
    expect(
      File('${cachedSource.path}/manifests/camera/fluoh.yaml').existsSync(),
      isTrue,
    );
    final lock = File('${environment.homeDirectory.path}/sources.lock.json');
    expect(lock.existsSync(), isTrue);
    final lockJson = _readJsonObject(lock);
    final packageRoutes = lockJson['packageRoutes'] as Map<String, Object?>;
    final fixturePackages = packageRoutes['fixture'] as Map<String, Object?>;
    expect(fixturePackages, contains('camera'));
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
name: local-flutteroh-source
description: "Local FlutterOH source maintained by fluoh users."

# Uncomment to document where this source is published.
# repository:
#   git:
#     url: "https://github.com/FlutterOH/source.git"

# Uncomment to publish FlutterOH SDK versions from this source.
# sdk:
#   git:
#     url: "https://gitcode.com/CPF-Flutter/flutter_flutter.git"
#   versions:
#     - 3.35.8-ohos-0.0.3
#     - 3.35.8-ohos-1.0.1

# Uncomment after editing manifests/example/fluoh.yaml, or run:
# fluoh source sync .
# manifests:
#   - name: example
''');
    expect(
      File('${source.path}/fluoh.yaml').readAsStringSync(),
      isNot(contains('file:.')),
    );
    expect(
      File('${source.path}/manifests/example/fluoh.yaml').readAsStringSync(),
      contains('# kind: manifest'),
    );
    expect(File('${source.path}/README.md').existsSync(), isTrue);
    expect(stdout, contains('Created local source template at ${source.path}'));
    expect(stdout.join('\n'), contains('fluoh source sync ${source.path}'));
    expect(
      stdout.join('\n'),
      contains('fluoh source add <name> ${source.path}'),
    );
    expect(stdout, contains('Added source local: ${source.path}'));
    expect(stderr, isEmpty);
  });

  test(
    'source init resolves relative paths from the working directory',
    () async {
      final environment = await createTestEnvironment();
      final source = Directory(
        '${environment.workingDirectory.path}/local_source',
      );
      final stdout = <String>[];
      final stderr = <String>[];

      expect(
        await runFluoh(
          ['source', 'init', 'local_source'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      expect(File('${source.path}/fluoh.yaml').existsSync(), isTrue);
      final readme = File('${source.path}/README.md').readAsStringSync();
      expect(readme, contains('fluoh source add <name> .'));
      expect(readme, contains('fluoh source sync .'));
      expect(readme, contains('fluoh.yaml'));
      expect(readme, contains('manifests/example/fluoh.yaml'));
      expect(
        stdout,
        contains('Created local source template at ${source.path}'),
      );
      expect(stderr, isEmpty);
    },
  );

  test('writes compact source locks and source snapshot state', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
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

    final state = File(
      '${environment.homeDirectory.path}/sources/fixture/.fluoh-source-state.json',
    );
    expect(state.existsSync(), isTrue);
    final stateContent = state.readAsStringSync();
    expect(stateContent, contains('"snapshotHash"'));
    expect(stateContent, isNot(contains('"contentHash"')));

    final lockFile = File(
      '${environment.homeDirectory.path}/sources.lock.json',
    );
    final lockContent = lockFile.readAsStringSync();
    final lock = jsonDecode(lockContent) as Map<String, Object?>;
    final sdk = lock['sdk'] as Map<String, Object?>;
    final sdkSources = sdk['sources'] as Map<String, Object?>;
    final sdkSource = sdkSources['fixture'] as Map<String, Object?>;
    final sdkSourceGit = sdkSource['git'] as Map<String, Object?>;
    expect(sdkSourceGit['url'], isA<String>());
    final sdkVersions = sdk['versions'] as Map<String, Object?>;
    final sdkRelease = sdkVersions['3.35.8-ohos-0.0.3'] as Map<String, Object?>;
    expect(sdkRelease, containsPair('source', 'fixture'));
    expect(sdkRelease, isNot(contains('git')));
    expect(sdkRelease, isNot(contains('priority')));
    expect(sdkRelease, isNot(contains('versionSeries')));
    expect(sdkRelease, isNot(contains('flutterVersion')));
    expect(sdkRelease, isNot(contains('channel')));
    expect(sdkRelease, isNot(contains('tag')));
    final packageRoutes = lock['packageRoutes'] as Map<String, Object?>;
    final fixturePackages = packageRoutes['fixture'] as Map<String, Object?>;
    expect(fixturePackages, containsPair('camera', ['3.35']));
    expect(lockContent, isNot(contains('"packages"')));
    expect(lockContent, isNot(contains('"manifests"')));
    expect(lockContent, isNot(contains('packages/camera/camera')));
    expect(lockContent, isNot(contains('"upstreamVersion"')));
    final sdkIndex = await SourceRuntime(environment).loadSdkIndex();
    final resolvedRelease = sdkIndex.releases.singleWhere(
      (release) => release.version == '3.35.8-ohos-0.0.3',
    );
    expect(resolvedRelease.sourceName, 'fixture');
    expect(resolvedRelease.repository, sdkSourceGit['url']);
    expect(stderr, isEmpty);
  });

  test('refreshes source lock when cached snapshot changes', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
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

    final lock = File('${environment.homeDirectory.path}/sources.lock.json');
    final previousSnapshotHash = _lockSourceSnapshotHash(lock, 'fixture');
    final cachedManifest = File(
      '${environment.homeDirectory.path}/sources/fixture/manifests/camera/fluoh.yaml',
    );
    await cachedManifest.writeAsString(
      '${cachedManifest.readAsStringSync()}# edited cached snapshot\n',
    );
    stdout.clear();
    stderr.clear();

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
      _lockSourceSnapshotHash(lock, 'fixture'),
      isNot(previousSnapshotHash),
    );
    expect(stderr, isEmpty);
  });

  test('source init creates an editable empty source scaffold', () async {
    final baseEnvironment = await createTestEnvironment();
    final source = Directory(
      '${baseEnvironment.homeDirectory.path}/local_source',
    );
    final environment = FluohEnvironment(
      homeDirectory: baseEnvironment.homeDirectory,
      workingDirectory: baseEnvironment.workingDirectory,
      processEnvironment: {
        'FLUOH_DEFAULT_SOURCE_URL': Uri.file(source.path).toString(),
      },
    );
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
    expect(content, contains('# fluoh source sync .'));
    expect(content, isNot(contains('manifests: []')));
    expect(
      File('${source.path}/manifests/example/fluoh.yaml').readAsStringSync(),
      contains('#   name: example'),
    );
    final lock = _readJsonObject(
      File('${environment.homeDirectory.path}/sources.lock.json'),
    );
    final sdk = lock['sdk'] as Map<String, Object?>;
    final sources = sdk['sources'] as Map<String, Object?>;
    final versions = sdk['versions'] as Map<String, Object?>;
    expect(sources, isEmpty);
    expect(versions, isEmpty);
    expect(lock['packageRoutes'], isEmpty);

    expect(stdout, contains('Created local source template at ${source.path}'));
    expect(stdout, contains('Added source empty: ${source.path}'));
    expect(stderr, isEmpty);
  });

  test('source sync imports released package repository manifests', () async {
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
    await _writePackageManifest(
      packageRepository,
      upstreamRef: 'camera-v0.11.0',
    );
    await _writeSourceSyncManifest(source, packageRepository);
    await initializeGitRepository(packageRepository);
    await _runGit(packageRepository, ['tag', 'camera-0.11.0-ohos-3.35-0.2.0']);
    final packageManifest = File('${packageRepository.path}/fluoh.yaml');
    await packageManifest.writeAsString(
      packageManifest
          .readAsStringSync()
          .replaceFirst('version: "0.2.0"', 'version: "0.3.0"')
          .replaceFirst(
            '    upstream:\n      version: "0.11.0"\n      ref:',
            '    upstream:\n      version: "0.12.0"\n      ref:',
          ),
    );

    expect(
      await runFluoh(
        ['source', 'sync'],
        environment: FluohEnvironment(
          homeDirectory: environment.homeDirectory,
          workingDirectory: source,
        ),
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
    expect(manifest, contains('url: "file:${packageRepository.path}"'));
    expect(manifest, contains('upstream:\n            version: 0.11.0'));
    expect(manifest, contains('ref: camera-v0.11.0'));
    expect(
      manifest,
      contains('commit: "1111111111111111111111111111111111111111"'),
    );
    expect(manifest, contains('- version: 0.2.0'));
    expect(manifest, isNot(contains('version: 0.12.0')));
    expect(manifest, isNot(contains('- version: 0.3.0')));
    expect(manifest, isNot(contains('status: experimental')));
    expect(
      stdout,
      contains(
        'Synced source metadata for camera from ${packageRepository.path}',
      ),
    );
    expect(stderr, isEmpty);
  });

  test('source sync reads release manifests from fetched tag refs', () async {
    final environment = await createTestEnvironment();
    final source = Directory(
      '${environment.homeDirectory.path}/tag_only_source',
    );
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/tag_only_package',
    );
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
      upstreamRef: 'camera-v0.11.0',
    );
    await _writeSourceSyncManifest(source, packageRepository);
    await initializeGitRepository(packageRepository);
    await _runGit(packageRepository, [
      'tag',
      '-a',
      'camera-0.11.0-ohos-3.35-0.2.0',
      '-m',
      'Release 0.2.0',
    ]);
    await _writePackageManifest(
      packageRepository,
      releaseVersion: '0.3.0',
      upstreamVersion: '0.12.0',
      upstreamRef: 'camera-v0.12.0',
      upstreamCommit: '2222222222222222222222222222222222222222',
    );
    await commitAll(packageRepository, message: 'Release 0.3.0 metadata');
    await _runGit(packageRepository, ['tag', 'camera-0.12.0-ohos-3.35-0.3.0']);
    await File('${packageRepository.path}/fluoh.yaml').delete();

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
    expect(manifest, contains('upstream:\n            version: 0.11.0'));
    expect(manifest, contains('ref: camera-v0.11.0'));
    expect(manifest, contains('- version: 0.2.0'));
    expect(manifest, contains('upstream:\n            version: 0.12.0'));
    expect(manifest, contains('ref: camera-v0.12.0'));
    expect(
      manifest,
      contains('commit: "2222222222222222222222222222222222222222"'),
    );
    expect(manifest, contains('- version: 0.3.0'));
    expect(
      stdout,
      contains(
        'Synced source metadata for camera from ${packageRepository.path}',
      ),
    );
    expect(stderr, isEmpty);
  });

  test('source sync can emit json results', () async {
    final environment = await createTestEnvironment();
    final source = Directory('${environment.homeDirectory.path}/json_source');
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/json_packages_implementation',
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
    await _runGit(packageRepository, ['tag', 'camera-0.11.0-ohos-3.35-0.2.0']);
    stdout.clear();

    expect(
      await runFluoh(
        ['source', 'sync', '--json'],
        environment: FluohEnvironment(
          homeDirectory: environment.homeDirectory,
          workingDirectory: source,
        ),
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('schema', 1));
    expect(report, containsPair('command', 'source sync'));
    expect(report, containsPair('ok', true));
    expect(report, containsPair('exitCode', 0));
    expect(report, containsPair('synced', 1));
    final packages = report['packages'] as List<Object?>;
    expect(
      packages,
      contains(
        allOf(
          containsPair('package', 'camera'),
          containsPair('status', 'synced'),
        ),
      ),
    );
    expect(stderr, isEmpty);
  });

  test(
    'source sync skips package tags for SDK lines missing from the source',
    () async {
      final environment = await createTestEnvironment();
      final source = Directory(
        '${environment.homeDirectory.path}/missing_sdk_source',
      );
      final packageRepository = Directory(
        '${environment.homeDirectory.path}/missing_sdk_package',
      );
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
        sdkVersion: '3.36.1-ohos-0.0.1',
      );
      await _writeSourceSyncManifest(
        source,
        packageRepository,
        sdkVersions: const ['3.35.8-ohos-0.0.3'],
      );
      await initializeGitRepository(packageRepository);
      await _runGit(packageRepository, [
        'tag',
        'camera-0.11.0-ohos-3.36-0.2.0',
      ]);
      stdout.clear();

      expect(
        await runFluoh(
          ['source', 'sync', '--json'],
          environment: FluohEnvironment(
            homeDirectory: environment.homeDirectory,
            workingDirectory: source,
          ),
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final report = jsonDecode(stdout.single) as Map<String, Object?>;
      expect(report, containsPair('synced', 0));
      expect(report, containsPair('skippedTags', 1));
      expect(report['packages'], isEmpty);
      final plan = report['plan'] as List<Object?>;
      final routePlan = plan.single as Map<String, Object?>;
      expect(routePlan, containsPair('status', 'skipped'));
      expect(routePlan, containsPair('tagsToSync', isEmpty));
      final skippedTags = routePlan['skippedTags'] as List<Object?>;
      expect(
        skippedTags.single,
        allOf(
          containsPair('tag', 'camera-0.11.0-ohos-3.36-0.2.0'),
          containsPair('sdkLine', '3.36'),
          containsPair('reason', 'sdk-line-not-in-source'),
        ),
      );
      final manifest = File(
        '${source.path}/manifests/camera/fluoh.yaml',
      ).readAsStringSync();
      expect(manifest, isNot(contains('"3.36"')));
      expect(stderr, isEmpty);
    },
  );

  test('source sync skips invalid package release tag metadata', () async {
    final environment = await createTestEnvironment();
    final source = Directory(
      '${environment.homeDirectory.path}/invalid_tag_source',
    );
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/invalid_tag_package',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'init', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    await _writeSourceSyncManifest(source, packageRepository);
    await packageRepository.create(recursive: true);
    await File('${packageRepository.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: package
''');
    await initializeGitRepository(packageRepository);
    await _runGit(packageRepository, ['tag', 'camera-0.11.0-ohos-3.35-0.2.0']);
    stdout.clear();
    stderr.clear();

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
    expect(report, containsPair('synced', 0));
    expect(report, containsPair('skippedTags', 1));
    expect(report['packages'], isEmpty);
    final plan = report['plan'] as List<Object?>;
    final routePlan = plan.single as Map<String, Object?>;
    expect(routePlan, containsPair('status', 'skipped'));
    expect(routePlan, containsPair('tagsToSync', isEmpty));
    final skippedTags = routePlan['skippedTags'] as List<Object?>;
    expect(
      skippedTags.single,
      allOf(
        containsPair('tag', 'camera-0.11.0-ohos-3.35-0.2.0'),
        containsPair('sdkLine', '3.35'),
        containsPair('reason', 'invalid-package-manifest'),
      ),
    );
    expect(stderr, isEmpty);
  });

  test('source sync skips package tags with a different package path', () async {
    final environment = await createTestEnvironment();
    final source = Directory(
      '${environment.homeDirectory.path}/path_mismatch_source',
    );
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/path_mismatch_package',
    );
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
      packagePath: 'packages/camera/camera_ohos',
    );
    await _writeSourceSyncManifest(source, packageRepository);
    await initializeGitRepository(packageRepository);
    await _runGit(packageRepository, ['tag', 'camera-0.11.0-ohos-3.35-0.2.0']);
    stdout.clear();
    stderr.clear();

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
    expect(report, containsPair('synced', 0));
    expect(report, containsPair('skippedTags', 1));
    expect(report['packages'], isEmpty);
    final plan = report['plan'] as List<Object?>;
    final routePlan = plan.single as Map<String, Object?>;
    expect(routePlan, containsPair('status', 'skipped'));
    expect(routePlan, containsPair('tagsToSync', isEmpty));
    final skippedTags = routePlan['skippedTags'] as List<Object?>;
    expect(
      skippedTags.single,
      allOf(
        containsPair('tag', 'camera-0.11.0-ohos-3.35-0.2.0'),
        containsPair('sdkLine', '3.35'),
        containsPair('reason', 'package-path-mismatch'),
        containsPair(
          'message',
          'package.path is packages/camera/camera_ohos, expected packages/camera/camera',
        ),
      ),
    );
    expect(stderr, isEmpty);
  });

  test(
    'source sync does not open repositories when tags are current',
    () async {
      final environment = await createTestEnvironment();
      final source = Directory('${environment.homeDirectory.path}/json_source');
      final packageRepository = Directory(
        '${environment.homeDirectory.path}/current_packages_implementation',
      );
      final stdout = <String>[];
      final stderr = <String>[];

      await runFluoh(
        ['source', 'init', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      await packageRepository.create(recursive: true);
      await File('${packageRepository.path}/README.md').writeAsString('repo');
      await _writeSourceSyncManifest(source, packageRepository);
      await initializeGitRepository(packageRepository);
      await _runGit(packageRepository, [
        'tag',
        'camera-0.10.0-ohos-3.35-0.1.0',
      ]);
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
      expect(report, containsPair('skipped', 0));
      expect(report['packages'], isEmpty);
      final plan = report['plan'] as List<Object?>;
      final routePlan = plan.single as Map<String, Object?>;
      expect(routePlan, containsPair('status', 'up-to-date'));
      expect(routePlan, containsPair('tagsToSync', isEmpty));
      expect(routePlan['knownTags'], contains('camera-0.10.0-ohos-3.35-0.1.0'));
      expect(stderr, isEmpty);
    },
  );

  test('source sync json usage errors keep a stable command name', () async {
    final environment = await createTestEnvironment();
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['source', 'sync', 'missing-source', '--json'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('command', 'source sync'));
    expect(report, containsPair('ok', false));
    expect(report, containsPair('exitCode', 64));
    expect(report['error'], isA<Map<String, Object?>>());
    expect(stderr, isEmpty);
  });

  test(
    'source check validates changed manifests and declared package releases',
    () async {
      final environment = await createTestEnvironment();
      final root = environment.homeDirectory;
      final fluoh = await _writeFakeSourceCheckFluoh(root);
      final source = Directory('${root.path}/source');
      final packageRepository = Directory('${root.path}/camera_ohos');
      final checkWorkRoot = Directory('${root.path}/check');
      final stdout = <String>[];
      final stderr = <String>[];

      await _writePackageManifest(
        packageRepository,
        repositoryUrl: packageRepository.path,
        name: 'camera',
        releaseVersion: '1.0.0',
        upstreamVersion: '0.11.0',
      );
      await initializeGitRepository(packageRepository);
      await _runGit(packageRepository, ['checkout', '-b', 'ohos/3.35/camera']);
      await _runGit(packageRepository, [
        'tag',
        'camera-0.11.0-ohos-3.35-1.0.0',
      ]);

      await source.create(recursive: true);
      await File('${source.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: source
name: test-source
manifests: []
''');
      await initializeGitRepository(source);
      await _runGit(source, ['checkout', '-b', 'pr/add-camera']);
      await Directory(
        '${source.path}/manifests/camera',
      ).create(recursive: true);
      await File('${source.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: source
name: test-source

manifests:
  - name: camera
''');
      await File('${source.path}/manifests/camera/fluoh.yaml').writeAsString('''
schema: 1
kind: manifest

repository:
  git:
    url: ${packageRepository.path}

upstream:
  git:
    url: https://github.com/flutter/packages

package:
  name: camera
  path: packages/camera/camera
  sdks:
    "3.35":
      releases:
        - version: "1.0.0"
          upstream:
            version: "0.11.0"
            ref: "1111111111111111111111111111111111111111"
            commit: "1111111111111111111111111111111111111111"
''');
      await commitAll(source, message: 'Add camera manifest');

      expect(
        await runFluoh(
          [
            'source',
            'check',
            '--base-ref',
            'main',
            '--fluoh-command',
            fluoh.path,
            '--work-root',
            checkWorkRoot.path,
            '--json',
          ],
          environment: FluohEnvironment(
            homeDirectory: environment.homeDirectory,
            workingDirectory: source,
          ),
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      expect(stderr, isEmpty);
      expect(stdout, hasLength(1));
      final report = jsonDecode(stdout.single) as Map<String, Object?>;
      expect(report, containsPair('schema', 1));
      expect(report, containsPair('command', 'source check'));
      expect(report, containsPair('ok', true));
      expect(report, containsPair('exitCode', 0));
      expect(report, containsPair('recommendation', 'ready'));
      expect(report, containsPair('all', false));
      expect(report, containsPair('checkedManifests', ['camera']));
      expect(report['errors'], isEmpty);
      final checkedManifestDetails = report['manifests'] as List<Object?>;
      final checkedManifest =
          checkedManifestDetails.single as Map<String, Object?>;
      expect(checkedManifest, containsPair('name', 'camera'));
      expect(
        checkedManifest,
        containsPair('packagePath', 'packages/camera/camera'),
      );
      expect(checkedManifest, isNot(contains('repositoryPath')));
      expect(checkedManifest, isNot(contains('upstreamPath')));
      expect(checkedManifest, isNot(contains('packages')));
      expect(checkedManifest['package'], containsPair('name', 'camera'));
      expect(
        checkedManifest['package'],
        containsPair('path', 'packages/camera/camera'),
      );
      final sourceValidation =
          report['sourceValidation'] as Map<String, Object?>;
      expect(sourceValidation, containsPair('ok', true));
      expect(report['sourceCheckout'], containsPair('kind', 'local'));
      final releaseChecks = report['releaseChecks'] as List<Object?>;
      final manifestCheck = releaseChecks.single as Map<String, Object?>;
      expect(manifestCheck, containsPair('manifest', 'camera'));
      expect(manifestCheck, containsPair('ok', true));
      final releaseCheckPlan =
          report['releaseCheckPlan'] as Map<String, Object?>;
      final releaseCheckPlanItems = releaseCheckPlan['items'] as List<Object?>;
      expect(releaseCheckPlanItems, hasLength(1));
      expect(
        releaseCheckPlanItems.single,
        containsPair('reason', 'new-manifest'),
      );
      final checks = manifestCheck['checks'] as List<Object?>;
      final releaseCheck = checks.single as Map<String, Object?>;
      expect(releaseCheck, containsPair('package', 'camera'));
      expect(
        releaseCheck,
        containsPair('tag', 'camera-0.11.0-ohos-3.35-1.0.0'),
      );
      expect(releaseCheck, containsPair('branch', 'ohos/3.35/camera'));
      expect(releaseCheck, containsPair('ok', true));
      final packageCheck = releaseCheck['packageCheck'] as Map<String, Object?>;
      expect(
        packageCheck['command'],
        containsAll([
          fluoh.path,
          'package',
          'check',
          '--package',
          'camera',
          '--json',
        ]),
      );

      stdout.clear();
      stderr.clear();
      expect(
        await runFluoh(
          ['source', 'check', '--all', '--skip-release-checks', '--json'],
          environment: FluohEnvironment(
            homeDirectory: environment.homeDirectory,
            workingDirectory: source,
          ),
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );
      expect(stderr, isEmpty);
      final allReport = jsonDecode(stdout.single) as Map<String, Object?>;
      expect(allReport, containsPair('command', 'source check'));
      expect(allReport, containsPair('all', true));
      expect(allReport, containsPair('changedFiles', isEmpty));
      expect(allReport, containsPair('checkedManifests', ['camera']));
      expect(allReport['warnings'], isEmpty);
      expect(allReport['releaseChecks'], isEmpty);
      final skippedReleaseChecks =
          allReport['skippedReleaseChecks'] as List<Object?>;
      expect(skippedReleaseChecks, hasLength(1));
      expect(
        skippedReleaseChecks.single,
        containsPair('skipReason', 'release-checks-skipped'),
      );
    },
    skip: Platform.isWindows ? 'uses POSIX test executables' : false,
  );

  test(
    'source check verifies only added release records',
    () async {
      final environment = await createTestEnvironment();
      final root = environment.homeDirectory;
      final fluoh = await _writeFakeSourceCheckFluoh(root);
      final source = Directory('${root.path}/source');
      final packageRepository = Directory('${root.path}/camera_ohos');
      final stdout = <String>[];
      final stderr = <String>[];

      await _writePackageManifest(
        packageRepository,
        repositoryUrl: packageRepository.path,
        name: 'camera',
        releaseVersion: '2.0.0',
        upstreamVersion: '0.12.0',
      );
      await initializeGitRepository(packageRepository);
      await _runGit(packageRepository, ['checkout', '-b', 'ohos/3.35/camera']);
      await _runGit(packageRepository, [
        'tag',
        'camera-0.11.0-ohos-3.35-1.0.0',
      ]);
      await _runGit(packageRepository, [
        'tag',
        'camera-0.12.0-ohos-3.35-2.0.0',
      ]);

      await source.create(recursive: true);
      await _writeCameraSourceManifest(
        source,
        packageRepository,
        releases: const [('1.0.0', '0.11.0')],
      );
      await initializeGitRepository(source);
      await _runGit(source, ['checkout', '-b', 'pr/add-camera-release']);
      await _writeCameraSourceManifest(
        source,
        packageRepository,
        releases: const [('1.0.0', '0.11.0'), ('2.0.0', '0.12.0')],
      );
      await commitAll(source, message: 'Add camera release');

      expect(
        await runFluoh(
          [
            'source',
            'check',
            '--base-ref',
            'main',
            '--fluoh-command',
            fluoh.path,
            '--json',
            source.path,
          ],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      expect(stderr, isEmpty);
      final report = jsonDecode(stdout.single) as Map<String, Object?>;
      expect(report, containsPair('checkedManifests', ['camera']));
      final plan = report['releaseCheckPlan'] as Map<String, Object?>;
      final planned = plan['items'] as List<Object?>;
      expect(planned, hasLength(1));
      expect(
        planned.single,
        allOf(
          containsPair('package', 'camera'),
          containsPair('version', '2.0.0'),
          containsPair('upstreamVersion', '0.12.0'),
          containsPair('reason', 'release-added'),
        ),
      );
      final releaseChecks = report['releaseChecks'] as List<Object?>;
      final manifestCheck = releaseChecks.single as Map<String, Object?>;
      final checks = manifestCheck['checks'] as List<Object?>;
      expect(checks, hasLength(1));
      expect(
        checks.single,
        containsPair('tag', 'camera-0.12.0-ohos-3.35-2.0.0'),
      );
    },
    skip: Platform.isWindows ? 'uses POSIX test executables' : false,
  );

  test(
    'source check rejects explicit release tag fields',
    () async {
      final environment = await createTestEnvironment();
      final root = environment.homeDirectory;
      final fluoh = await _writeFakeSourceCheckFluoh(root);
      final source = Directory('${root.path}/source');
      final packageRepository = Directory('${root.path}/camera_ohos');
      final stdout = <String>[];
      final stderr = <String>[];

      await _writePackageManifest(
        packageRepository,
        repositoryUrl: packageRepository.path,
        name: 'camera',
        releaseVersion: '1.0.0',
        upstreamVersion: '0.11.0',
      );
      await initializeGitRepository(packageRepository);
      await _runGit(packageRepository, ['checkout', '-b', 'ohos/3.35/camera']);
      await _runGit(packageRepository, [
        'tag',
        'camera-0.11.0-ohos-3.35-1.0.0',
      ]);

      await source.create(recursive: true);
      await File('${source.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: source
name: test-source
manifests: []
''');
      await initializeGitRepository(source);
      await _runGit(source, ['checkout', '-b', 'pr/add-explicit-tag']);
      await _writeCameraSourceManifestRaw(
        source,
        packageRepository,
        releaseYaml: '''
          - version: "1.0.0"
            upstream:
              version: "0.11.0"
              ref: "1111111111111111111111111111111111111111"
              commit: "1111111111111111111111111111111111111111"
            tag: camera-0.11.0-ohos-3.35-1.0.0
''',
      );
      await commitAll(source, message: 'Add forbidden camera release tag');

      expect(
        await runFluoh(
          [
            'source',
            'check',
            '--base-ref',
            'main',
            '--fluoh-command',
            fluoh.path,
            '--json',
            source.path,
          ],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        1,
      );

      expect(stderr, isEmpty);
      final report = jsonDecode(stdout.single) as Map<String, Object?>;
      expect(report, containsPair('recommendation', 'blocked'));
      expect(
        report['errors'],
        contains(
          contains('package sdks.3.35 releases[0] must not contain "tag"'),
        ),
      );
    },
    skip: Platform.isWindows ? 'uses POSIX test executables' : false,
  );

  test(
    'source check rejects release metadata that does not match tag metadata',
    () async {
      final environment = await createTestEnvironment();
      final root = environment.homeDirectory;
      final fluoh = await _writeFakeSourceCheckFluoh(root);
      final source = Directory('${root.path}/source');
      final packageRepository = Directory('${root.path}/camera_ohos');
      final stdout = <String>[];
      final stderr = <String>[];

      await _writePackageManifest(
        packageRepository,
        repositoryUrl: packageRepository.path,
        name: 'camera',
        releaseVersion: '1.0.0',
        upstreamVersion: '0.11.0',
      );
      await initializeGitRepository(packageRepository);
      await _runGit(packageRepository, ['checkout', '-b', 'ohos/3.35/camera']);
      await _runGit(packageRepository, [
        'tag',
        'camera-0.12.0-ohos-3.35-1.0.0',
      ]);

      await source.create(recursive: true);
      await _writeCameraSourceManifest(
        source,
        packageRepository,
        releases: const [('1.0.0', '0.11.0')],
      );
      await initializeGitRepository(source);
      await _runGit(source, ['checkout', '-b', 'pr/bad-release-metadata']);
      await _writeCameraSourceManifestRaw(
        source,
        packageRepository,
        releaseYaml: '''
          - version: "1.0.0"
            upstream:
              version: "0.12.0"
              ref: camera-v0.12.0
              commit: "2222222222222222222222222222222222222222"
''',
      );
      await commitAll(source, message: 'Break camera release metadata');

      expect(
        await runFluoh(
          [
            'source',
            'check',
            '--base-ref',
            'main',
            '--fluoh-command',
            fluoh.path,
            '--json',
            source.path,
          ],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        1,
      );

      expect(stderr, isEmpty);
      final report = jsonDecode(stdout.single) as Map<String, Object?>;
      expect(report, containsPair('recommendation', 'blocked'));
      expect(
        report['errors'],
        contains(
          contains(
            'Declared release check failed for camera at '
            'camera-0.12.0-ohos-3.35-1.0.0',
          ),
        ),
      );
      expect(
        report['errors'],
        contains(
          contains(
            'upstream ref is 1111111111111111111111111111111111111111, expected camera-v0.12.0',
          ),
        ),
      );
      expect(
        report['errors'],
        contains(
          contains(
            'upstream commit is 1111111111111111111111111111111111111111, expected 2222222222222222222222222222222222222222',
          ),
        ),
      );
      final releaseChecks = report['releaseChecks'] as List<Object?>;
      final manifestCheck = releaseChecks.single as Map<String, Object?>;
      final checks = manifestCheck['checks'] as List<Object?>;
      final check = checks.single as Map<String, Object?>;
      expect(check.containsKey('checkout'), false);
      expect(check.containsKey('packageCheck'), false);
      final metadataCheck = check['metadataCheck'] as Map<String, Object?>;
      expect(metadataCheck, containsPair('ok', false));
      expect(
        metadataCheck['message'],
        contains('upstream version is 0.11.0, expected 0.12.0'),
      );
      expect(
        metadataCheck['message'],
        contains(
          'upstream ref is 1111111111111111111111111111111111111111, expected camera-v0.12.0',
        ),
      );
      expect(
        metadataCheck['message'],
        contains(
          'upstream commit is 1111111111111111111111111111111111111111, expected 2222222222222222222222222222222222222222',
        ),
      );
    },
    skip: Platform.isWindows ? 'uses POSIX test executables' : false,
  );

  test(
    'source check verifies package path changes against tag metadata',
    () async {
      final environment = await createTestEnvironment();
      final root = environment.homeDirectory;
      final fluoh = await _writeFakeSourceCheckFluoh(root);
      final source = Directory('${root.path}/source');
      final packageRepository = Directory('${root.path}/camera_ohos');
      final stdout = <String>[];
      final stderr = <String>[];

      await _writePackageManifest(
        packageRepository,
        repositoryUrl: packageRepository.path,
        name: 'camera',
        releaseVersion: '1.0.0',
        upstreamVersion: '0.11.0',
      );
      await initializeGitRepository(packageRepository);
      await _runGit(packageRepository, ['checkout', '-b', 'ohos/3.35/camera']);
      await _runGit(packageRepository, [
        'tag',
        'camera-0.11.0-ohos-3.35-1.0.0',
      ]);

      await source.create(recursive: true);
      await _writeCameraSourceManifest(
        source,
        packageRepository,
        releases: const [('1.0.0', '0.11.0')],
      );
      await initializeGitRepository(source);
      await _runGit(source, ['checkout', '-b', 'pr/change-upstream-path']);
      await _writeCameraSourceManifest(
        source,
        packageRepository,
        releases: const [('1.0.0', '0.11.0')],
        packagePath: 'packages/camera/camera_android',
      );
      await commitAll(source, message: 'Change camera package path');

      expect(
        await runFluoh(
          [
            'source',
            'check',
            '--base-ref',
            'main',
            '--fluoh-command',
            fluoh.path,
            '--json',
            source.path,
          ],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        1,
      );

      expect(stderr, isEmpty);
      final report = jsonDecode(stdout.single) as Map<String, Object?>;
      expect(report, containsPair('recommendation', 'blocked'));
      final plan = report['releaseCheckPlan'] as Map<String, Object?>;
      final planned = plan['items'] as List<Object?>;
      expect(planned.single, containsPair('reason', 'package-path-changed'));
      expect(
        report['errors'],
        contains(
          contains(
            'package.path is packages/camera/camera, expected '
            'packages/camera/camera_android',
          ),
        ),
      );
      final releaseChecks = report['releaseChecks'] as List<Object?>;
      final manifestCheck = releaseChecks.single as Map<String, Object?>;
      final checks = manifestCheck['checks'] as List<Object?>;
      final check = checks.single as Map<String, Object?>;
      expect(check.containsKey('checkout'), false);
      final metadataCheck = check['metadataCheck'] as Map<String, Object?>;
      expect(metadataCheck, containsPair('ok', false));
    },
    skip: Platform.isWindows ? 'uses POSIX test executables' : false,
  );

  test('source check skips advisory-only manifest changes', () async {
    final environment = await createTestEnvironment();
    final source = Directory('${environment.homeDirectory.path}/source');
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/missing_camera_ohos',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await source.create(recursive: true);
    await _writeCameraSourceManifest(
      source,
      packageRepository,
      releases: const [('1.0.0', '0.11.0')],
    );
    await initializeGitRepository(source);

    await _runGit(source, ['checkout', '-b', 'pr/advisory']);
    await _writeCameraSourceManifest(
      source,
      packageRepository,
      releases: const [('1.0.0', '0.11.0')],
      advisory: 'Known migration note.',
    );
    await commitAll(source, message: 'Add advisory');

    expect(
      await runFluoh(
        ['source', 'check', '--base-ref', 'main', '--json', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(stderr, isEmpty);
    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('recommendation', 'ready'));
    expect(report, containsPair('checkedManifests', ['camera']));
    final plan = report['releaseCheckPlan'] as Map<String, Object?>;
    expect(plan['items'], isEmpty);
    expect(report['releaseChecks'], isEmpty);
  });

  test(
    'source check reports deleted release records without cloning',
    () async {
      final environment = await createTestEnvironment();
      final source = Directory('${environment.homeDirectory.path}/source');
      final packageRepository = Directory(
        '${environment.homeDirectory.path}/missing_camera_ohos',
      );
      final stdout = <String>[];
      final stderr = <String>[];

      await source.create(recursive: true);
      await _writeCameraSourceManifest(
        source,
        packageRepository,
        releases: const [('1.0.0', '0.11.0'), ('2.0.0', '0.12.0')],
      );
      await initializeGitRepository(source);

      await _runGit(source, ['checkout', '-b', 'pr/delete-release']);
      await _writeCameraSourceManifest(
        source,
        packageRepository,
        releases: const [('2.0.0', '0.12.0')],
      );
      await commitAll(source, message: 'Delete old camera release');

      expect(
        await runFluoh(
          ['source', 'check', '--base-ref', 'main', '--json', source.path],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      expect(stderr, isEmpty);
      final report = jsonDecode(stdout.single) as Map<String, Object?>;
      expect(report, containsPair('recommendation', 'ready'));
      expect(report['releaseChecks'], isEmpty);
      expect(report['changeTypes'], contains('release-record-deleted'));
      final skippedReleaseChecks =
          report['skippedReleaseChecks'] as List<Object?>;
      expect(skippedReleaseChecks, hasLength(1));
      expect(
        skippedReleaseChecks.single,
        allOf(
          containsPair('version', '1.0.0'),
          containsPair('tag', 'camera-0.11.0-ohos-3.35-1.0.0'),
          containsPair('skipReason', 'release-deleted'),
        ),
      );
    },
  );

  test(
    'source check supports manifest filters and skipped release plans',
    () async {
      final environment = await createTestEnvironment();
      final source = Directory('${environment.homeDirectory.path}/source');
      final stdout = <String>[];
      final stderr = <String>[];

      await source.create(recursive: true);
      await File('${source.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: source
name: test-source

manifests:
  - name: camera
  - name: path_provider
''');
      await _writeSimpleSourceManifest(source, 'camera');
      await _writeSimpleSourceManifest(source, 'path_provider');

      expect(
        await runFluoh(
          [
            'source',
            'check',
            '--all',
            '--skip-release-checks',
            '--manifest',
            'camera',
            '--package',
            'camera',
            '--shard',
            '1/1',
            '--concurrency',
            '2',
            '--json',
            source.path,
          ],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      expect(stderr, isEmpty);
      final report = jsonDecode(stdout.single) as Map<String, Object?>;
      expect(report, containsPair('checkedManifests', ['camera']));
      expect(report, containsPair('affectedManifests', ['camera']));
      expect(report['releaseChecks'], isEmpty);
      final skippedReleaseChecks =
          report['skippedReleaseChecks'] as List<Object?>;
      expect(skippedReleaseChecks, hasLength(1));
      expect(
        skippedReleaseChecks.single,
        allOf(
          containsPair('manifest', 'camera'),
          containsPair('package', 'camera'),
          containsPair('skipReason', 'release-checks-skipped'),
        ),
      );
    },
  );

  test(
    'source check rejects mutually exclusive diff options as json',
    () async {
      final environment = await createTestEnvironment();
      final stdout = <String>[];
      final stderr = <String>[];

      expect(
        await runFluoh(
          ['source', 'check', '--all', '--base-ref', 'main', '--json'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        64,
      );

      expect(stderr, isEmpty);
      final report = jsonDecode(stdout.single) as Map<String, Object?>;
      expect(report, containsPair('command', 'source check'));
      expect(report, containsPair('ok', false));
      expect(
        report['errors'],
        contains('--all cannot be used with --base-ref.'),
      );
    },
  );

  test(
    'source check schema-only rejects release and diff options as json',
    () async {
      final environment = await createTestEnvironment();
      final stdout = <String>[];
      final stderr = <String>[];

      expect(
        await runFluoh(
          [
            'source',
            'check',
            '--schema-only',
            '--skip-release-checks',
            '--json',
          ],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        64,
      );

      expect(stderr, isEmpty);
      final report = jsonDecode(stdout.single) as Map<String, Object?>;
      expect(report, containsPair('command', 'source check'));
      expect(report, containsPair('ok', false));
      expect(
        report['errors'],
        contains('--schema-only cannot be used with --skip-release-checks.'),
      );
    },
  );

  test('source check limits root route changes to added manifests', () async {
    final environment = await createTestEnvironment();
    final source = Directory('${environment.homeDirectory.path}/source');
    final stdout = <String>[];
    final stderr = <String>[];

    await source.create(recursive: true);
    await File('${source.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: source
name: test-source

manifests:
  - name: path_provider
  - name: shared_preferences
''');
    await _writeSimpleSourceManifest(source, 'path_provider');
    await _writeSimpleSourceManifest(source, 'shared_preferences');
    await initializeGitRepository(source);

    await _runGit(source, ['checkout', '-b', 'pr/add-camera']);
    await File('${source.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: source
name: test-source

manifests:
  - name: camera
  - name: path_provider
  - name: shared_preferences
''');
    await _writeSimpleSourceManifest(source, 'camera');
    await commitAll(source, message: 'Add camera manifest');

    expect(
      await runFluoh(
        [
          'source',
          'check',
          '--base-ref',
          'main',
          '--skip-release-checks',
          '--json',
          source.path,
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(stderr, isEmpty);
    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('command', 'source check'));
    expect(report, containsPair('ok', true));
    expect(report, containsPair('checkedManifests', ['camera']));
    expect(report['changedFiles'], contains('fluoh.yaml'));
    expect(report['changedFiles'], contains('manifests/camera/fluoh.yaml'));
    expect(report['releaseChecks'], isEmpty);
  });

  test(
    'source check does not expand sdk-only root changes to manifests',
    () async {
      final environment = await createTestEnvironment();
      final source = Directory('${environment.homeDirectory.path}/source');
      final sdkRepository = Directory(
        '${environment.homeDirectory.path}/flutter_ohos_sdk',
      );
      final stdout = <String>[];
      final stderr = <String>[];

      await sdkRepository.create(recursive: true);
      await File('${sdkRepository.path}/README.md').writeAsString('sdk');
      await initializeGitRepository(sdkRepository);
      await _runGit(sdkRepository, ['tag', '3.35.8-ohos-0.0.3']);
      await _runGit(sdkRepository, ['tag', '3.35.8-ohos-1.0.1']);

      await source.create(recursive: true);
      await File('${source.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: source
name: test-source

sdk:
  git:
    url: ${sdkRepository.path}
  versions:
    - 3.35.8-ohos-0.0.3

manifests:
  - name: path_provider
  - name: shared_preferences
''');
      await _writeSimpleSourceManifest(source, 'path_provider');
      await _writeSimpleSourceManifest(source, 'shared_preferences');
      await initializeGitRepository(source);

      await _runGit(source, ['checkout', '-b', 'pr/add-sdk']);
      await File('${source.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: source
name: test-source

sdk:
  git:
    url: ${sdkRepository.path}
  versions:
    - 3.35.8-ohos-0.0.3
    - 3.35.8-ohos-1.0.1

manifests:
  - name: path_provider
  - name: shared_preferences
''');
      await commitAll(source, message: 'Add SDK release');

      expect(
        await runFluoh(
          ['source', 'check', '--base-ref', 'main', '--json', source.path],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      expect(stderr, isEmpty);
      final report = jsonDecode(stdout.single) as Map<String, Object?>;
      expect(report, containsPair('command', 'source check'));
      expect(report, containsPair('ok', true));
      expect(report, containsPair('checkedManifests', isEmpty));
      expect(report['changedFiles'], contains('fluoh.yaml'));
      expect(report['releaseChecks'], isEmpty);
      final sdkChecks = report['sdkChecks'] as List<Object?>;
      expect(sdkChecks, hasLength(1));
      expect(
        sdkChecks.single,
        allOf(
          containsPair('version', '3.35.8-ohos-1.0.1'),
          containsPair('ok', true),
          containsPair('reason', 'added-sdk-release'),
        ),
      );
      expect(report, containsPair('recommendation', 'ready'));
      expect(report['warnings'], isEmpty);
    },
  );

  test(
    'source check scopes source validation for sdk-only pull requests',
    () async {
      final environment = await createTestEnvironment();
      final source = Directory('${environment.homeDirectory.path}/source');
      final sdkRepository = Directory(
        '${environment.homeDirectory.path}/flutter_ohos_sdk',
      );
      final stdout = <String>[];
      final stderr = <String>[];

      await sdkRepository.create(recursive: true);
      await File('${sdkRepository.path}/README.md').writeAsString('sdk');
      await initializeGitRepository(sdkRepository);
      await _runGit(sdkRepository, ['tag', '3.35.8-ohos-0.0.3']);
      await _runGit(sdkRepository, ['tag', '3.35.8-ohos-1.0.1']);

      await source.create(recursive: true);
      await File('${source.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: source
name: test-source

sdk:
  git:
    url: ${sdkRepository.path}
  versions:
    - 3.35.8-ohos-0.0.3

manifests:
  - name: path_provider
  - name: shared_preferences
''');
      await _writeSimpleSourceManifest(source, 'path_provider');
      await _writeSimpleSourceManifest(source, 'shared_preferences');
      await File(
        '${source.path}/manifests/path_provider/fluoh.yaml',
      ).writeAsString('''
schema: 1
kind: manifest

repository:
  git:
    url: file:${source.path}/../path_provider_repo

upstream:
  git:
    url: https://github.com/flutter/packages

package:
  name:
''');
      await initializeGitRepository(source);

      await _runGit(source, ['checkout', '-b', 'pr/add-sdk']);
      await File('${source.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: source
name: test-source

sdk:
  git:
    url: ${sdkRepository.path}
  versions:
    - 3.35.8-ohos-0.0.3
    - 3.35.8-ohos-1.0.1

manifests:
  - name: path_provider
  - name: shared_preferences
''');
      await commitAll(source, message: 'Add SDK release');

      expect(
        await runFluoh(
          ['source', 'check', '--base-ref', 'main', '--json', source.path],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      expect(stderr, isEmpty);
      final prReport = jsonDecode(stdout.single) as Map<String, Object?>;
      expect(prReport, containsPair('recommendation', 'ready'));
      expect(prReport, containsPair('checkedManifests', isEmpty));
      expect(prReport['warnings'], isEmpty);
      final prValidation = prReport['sourceValidation'] as Map<String, Object?>;
      expect(prValidation, containsPair('ok', true));

      stdout.clear();
      stderr.clear();
      expect(
        await runFluoh(
          ['source', 'check', '--skip-release-checks', '--json', source.path],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        1,
      );

      expect(stderr, isEmpty);
      final fullReport = jsonDecode(stdout.single) as Map<String, Object?>;
      expect(fullReport, containsPair('recommendation', 'blocked'));
      final fullValidation =
          fullReport['sourceValidation'] as Map<String, Object?>;
      expect(fullValidation, containsPair('ok', false));
      expect(
        fullReport['errors'],
        contains(contains('Expected "name" to be a non-empty string')),
      );
    },
  );

  test('source check reports missing changed SDK tags', () async {
    final environment = await createTestEnvironment();
    final source = Directory('${environment.homeDirectory.path}/source');
    final sdkRepository = Directory(
      '${environment.homeDirectory.path}/flutter_ohos_sdk',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await sdkRepository.create(recursive: true);
    await File('${sdkRepository.path}/README.md').writeAsString('sdk');
    await initializeGitRepository(sdkRepository);
    await _runGit(sdkRepository, ['tag', '3.35.8-ohos-0.0.3']);

    await source.create(recursive: true);
    await File('${source.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: source
name: test-source

sdk:
  git:
    url: ${sdkRepository.path}
  versions:
    - 3.35.8-ohos-0.0.3
''');
    await initializeGitRepository(source);

    await _runGit(source, ['checkout', '-b', 'pr/add-missing-sdk']);
    await File('${source.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: source
name: test-source

sdk:
  git:
    url: ${sdkRepository.path}
  versions:
    - 3.35.8-ohos-0.0.3
    - 3.35.8-ohos-1.0.1
''');
    await commitAll(source, message: 'Add missing SDK release');

    expect(
      await runFluoh(
        ['source', 'check', '--base-ref', 'main', '--json', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      1,
    );

    expect(stderr, isEmpty);
    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('recommendation', 'blocked'));
    final sdkChecks = report['sdkChecks'] as List<Object?>;
    expect(sdkChecks, hasLength(1));
    expect(
      sdkChecks.single,
      allOf(
        containsPair('version', '3.35.8-ohos-1.0.1'),
        containsPair('ok', false),
      ),
    );
    expect(
      report['errors'],
      contains(startsWith('SDK tag check failed for 3.35.8-ohos-1.0.1:')),
    );
  });

  test('source check reports source validation failures as json', () async {
    final environment = await createTestEnvironment();
    final source = Directory('${environment.homeDirectory.path}/source');
    final stdout = <String>[];
    final stderr = <String>[];

    await source.create(recursive: true);
    await File('${source.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: source
name: broken-source
manifests:
  - name: camera
''');
    await Directory('${source.path}/manifests/camera').create(recursive: true);
    await File('${source.path}/manifests/camera/fluoh.yaml').writeAsString('''
schema: 1
kind: manifest
name:
''');

    expect(
      await runFluoh(
        ['source', 'check', source.path, '--json'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      1,
    );

    expect(stderr, isEmpty);
    expect(stdout, hasLength(1));
    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('command', 'source check'));
    expect(report, containsPair('ok', false));
    expect(report, containsPair('exitCode', 1));
    expect(report, containsPair('recommendation', 'blocked'));
    expect(report, containsPair('checkedManifests', ['camera']));
    expect(report, containsPair('releaseChecks', isEmpty));
    final sourceValidation = report['sourceValidation'] as Map<String, Object?>;
    expect(sourceValidation, containsPair('ok', false));
    expect(report['errors'], contains(startsWith('Source validation failed:')));
  });

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
        ['source', 'add', 'local', 'package_source'],
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
    final source = await createPackageSourceFixture(environment.homeDirectory);
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

    expect(stdout, contains('Removed source team'));
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

upstream:
  git:
    url: https://github.com/example/team

package:
  name: team
  sdks:
    "3.35":
      releases:
        - version: 0.1.0
          upstream:
            version: 1.0.0
            ref: team-v1.0.0
            commit: "1111111111111111111111111111111111111111"
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
        ['source', 'add', 'future', source.path],
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
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
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

Future<void> _writeCameraSourceManifest(
  Directory source,
  Directory packageRepository, {
  required List<(String, String)> releases,
  String? advisory,
  String packagePath = 'packages/camera/camera',
}) async {
  await File('${source.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: source
name: test-source

manifests:
  - name: camera
''');
  final manifest = File('${source.path}/manifests/camera/fluoh.yaml');
  await manifest.parent.create(recursive: true);
  await manifest.writeAsString('''
schema: 1
kind: manifest

repository:
  git:
    url: ${packageRepository.path}

upstream:
  git:
    url: https://github.com/flutter/packages

package:
  name: camera
  path: $packagePath
${advisory == null ? '' : '  advisory:\n    message: "$advisory"\n'}  sdks:
    "3.35":
      releases:
${releases.map((release) => '        - version: "${release.$1}"\n          upstream:\n            version: "${release.$2}"\n            ref: "1111111111111111111111111111111111111111"\n            commit: "1111111111111111111111111111111111111111"').join('\n')}
''');
}

Future<void> _writeCameraSourceManifestRaw(
  Directory source,
  Directory packageRepository, {
  required String releaseYaml,
  String packagePath = 'packages/camera/camera',
}) async {
  await File('${source.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: source
name: test-source

manifests:
  - name: camera
''');
  final manifest = File('${source.path}/manifests/camera/fluoh.yaml');
  await manifest.parent.create(recursive: true);
  await manifest.writeAsString('''
schema: 1
kind: manifest

repository:
  git:
    url: ${packageRepository.path}

upstream:
  git:
    url: https://github.com/flutter/packages

package:
  name: camera
  path: $packagePath
  sdks:
    "3.35":
      releases:
$releaseYaml
''');
}

Future<void> _writeSimpleSourceManifest(
  Directory source,
  String manifestName,
) async {
  final manifest = File('${source.path}/manifests/$manifestName/fluoh.yaml');
  await manifest.parent.create(recursive: true);
  await manifest.writeAsString('''
schema: 1
kind: manifest

repository:
  git:
    url: file:${source.path}/../${manifestName}_repo

upstream:
  git:
    url: https://github.com/flutter/packages

package:
  name: $manifestName
  path: packages/$manifestName/$manifestName
  sdks:
    "3.35":
      releases:
        - version: "1.0.0"
          upstream:
            version: "1.0.0"
            ref: $manifestName-v1.0.0
            commit: "1111111111111111111111111111111111111111"
''');
}

Future<void> _writePackageManifest(
  Directory repository, {
  String? repositoryUrl,
  String name = 'packages',
  String packageName = 'camera',
  String packagePath = 'packages/camera/camera',
  String sdkVersion = '3.35.8-ohos-0.0.3',
  String releaseVersion = '0.2.0',
  String upstreamVersion = '0.11.0',
  String? upstreamRef,
  String upstreamCommit = '1111111111111111111111111111111111111111',
  String upstreamBranch = 'main',
}) async {
  repositoryUrl ??= 'file:${repository.path}';
  final sdkLine = sdkLineFromSdkVersion(sdkVersion);
  await repository.create(recursive: true);
  final upstreamRefLine = upstreamRef == null
      ? ''
      : '      ref: "$upstreamRef"\n';
  await File('${repository.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: package

sdk:
  version: $sdkVersion

repository:
  git:
    url: "$repositoryUrl"
    branch: ohos/$sdkLine/$packageName

upstream:
  git:
    url: https://github.com/flutter/packages
    branch: $upstreamBranch

package:
  name: $packageName
  path: $packagePath
  release:
    version: "$releaseVersion"
    upstream:
      version: "$upstreamVersion"
$upstreamRefLine      commit: "$upstreamCommit"
''');
}

Future<void> _writeSourceSyncManifest(
  Directory source,
  Directory repository, {
  String? repositoryUrl,
  String manifestName = 'camera',
  List<String>? sdkVersions,
}) async {
  repositoryUrl ??= 'file:${repository.path}';
  final sdkLines = sdkVersions == null
      ? ''
      : '''

sdk:
  git:
    url: /tmp/flutter-ohos-sdk
  versions:
${sdkVersions.map((version) => '    - $version').join('\n')}
''';
  await File('${source.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: source
name: local-flutteroh-source

repository:
  git:
    url: "file:${source.path}"
$sdkLines

manifests:
  - name: $manifestName
''');
  final manifest = File('${source.path}/manifests/$manifestName/fluoh.yaml');
  await manifest.parent.create(recursive: true);
  await manifest.writeAsString('''
schema: 1
kind: manifest

repository:
  git:
    url: "$repositoryUrl"

upstream:
  git:
    url: https://github.com/flutter/packages

package:
  name: camera
  path: packages/camera/camera
  sdks:
    "3.35":
      releases:
        - version: 0.1.0
          upstream:
            version: 0.10.0
            ref: camera-v0.10.0
            commit: "1111111111111111111111111111111111111111"
''');
}

Future<File> _writeFakeSourceCheckFluoh(Directory root) async {
  final tool = File('${root.path}/fluoh-source-check');
  await tool.writeAsString(r'''
#!/bin/sh
if [ "$1" = "package" ] && [ "$2" = "check" ] && [ "$3" = "--package" ] && [ "$5" = "--json" ]; then
  printf '{"schema":1,"command":"package check","ok":true,"exitCode":0,"tags":["%s-0.11.0-ohos-3.35-1.0.0"]}\n' "$4"
  exit 0
fi
echo "unexpected args: $@" >&2
exit 64
''');
  final chmod = await Process.run('chmod', ['+x', tool.path]);
  expect(chmod.exitCode, 0, reason: chmod.stderr.toString());
  return tool;
}

Map<String, Object?> _readJsonObject(File file) {
  return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
}

String _lockSourceSnapshotHash(File lockFile, String sourceName) {
  final lock = _readJsonObject(lockFile);
  final fingerprint = lock['fingerprint'] as Map<String, Object?>;
  final sources = fingerprint['sources'] as List<Object?>;
  final source = sources.cast<Map<String, Object?>>().singleWhere(
    (source) => source['name'] == sourceName,
  );
  return source['snapshotHash'] as String;
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
