part of 'source_command_test.dart';

void _registerSourceCommandConfigTests() {
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
}
