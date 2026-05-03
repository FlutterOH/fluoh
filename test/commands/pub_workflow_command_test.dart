import 'dart:io';

import 'package:fluoh/fluoh.dart';
import 'package:test/test.dart';

import '../helpers/fluoh_test_context.dart';

void main() {
  test(
    'creates a pub branch and release tag from an upstream repository',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPubSourceFixture(environment.homeDirectory);
      final upstream = await createUpstreamPackageRepository(
        Directory('${environment.homeDirectory.path}/upstream_camera'),
      );
      final pubRepository = Directory(
        '${environment.homeDirectory.path}/pub_camera',
      );
      final stdout = <String>[];
      final stderr = <String>[];

      await runFluoh(
        ['source', 'add', 'fixture', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );

      expect(
        await runFluoh(
          [
            'pub',
            'create',
            upstream.path,
            '--output',
            pubRepository.path,
            '--sdk',
            '3.35.8-ohos-0.0.3',
          ],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final branch = await _git(pubRepository, ['branch', '--show-current']);
      final origin = await _git(pubRepository, ['remote', 'get-url', 'origin']);
      final upstreamRemote = await _git(pubRepository, [
        'remote',
        'get-url',
        'upstream',
      ]);
      expect(branch.stdout.toString().trim(), 'ohos/3.35.8-ohos-0.0.3');
      expect(
        origin.stdout.toString().trim(),
        'git@github.com:FlutterOH/camera.git',
      );
      expect(upstreamRemote.stdout.toString().trim(), upstream.path);
      expect(
        File('${pubRepository.path}/fluoh.yaml').readAsStringSync(),
        allOf(
          contains('schema: 1'),
          contains('name: camera'),
          contains('url: git@github.com:FlutterOH/camera.git'),
          contains('branch: ohos/3.35.8-ohos-0.0.3'),
          contains('3.35.8-ohos-0.0.3'),
          contains('status: experimental'),
          contains('ref: camera-v0.11.0-ohos-3.35.8-ohos-0.0.3-0.1.0'),
        ),
      );
      expect(File('${pubRepository.path}/FLUOH_ADAPT.md').existsSync(), isTrue);

      final releaseEnvironment = FluohEnvironment(
        homeDirectory: environment.homeDirectory,
        workingDirectory: pubRepository,
      );
      expect(
        await runFluoh(
          ['pub', 'release'],
          environment: releaseEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final tags = await _git(pubRepository, ['tag', '--list']);
      expect(
        tags.stdout.toString().split('\n'),
        contains('camera-v0.11.0-ohos-3.35.8-ohos-0.0.3-0.1.0'),
      );
      expect(
        stdout,
        contains('Created pub repository at ${pubRepository.path}.'),
      );
      expect(
        stdout,
        contains(
          'Created release tag '
          'camera-v0.11.0-ohos-3.35.8-ohos-0.0.3-0.1.0.',
        ),
      );
      expect(stderr, isEmpty);
    },
  );

  test('uses --path as a package path inside a monorepo upstream', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamMonorepoRepository(
      Directory('${environment.homeDirectory.path}/upstream_monorepo'),
    );
    final pubRepository = Directory(
      '${environment.homeDirectory.path}/pub_monorepo',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'add', 'fixture', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(
      await runFluoh(
        [
          'pub',
          'create',
          upstream.path,
          '--path',
          'packages/camera/camera',
          '--output',
          pubRepository.path,
          '--sdk',
          '3.35.8-ohos-0.0.3',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final manifest = File(
      '${pubRepository.path}/fluoh.yaml',
    ).readAsStringSync();
    expect(manifest, contains('name: camera'));
    expect(manifest, contains('path: packages/camera/camera'));
    expect(stderr, isEmpty);
  });

  test('finds a monorepo package by --package', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamMonorepoRepository(
      Directory('${environment.homeDirectory.path}/upstream_by_package'),
    );
    final pubRepository = Directory(
      '${environment.homeDirectory.path}/pub_by_package',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'add', 'fixture', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(
      await runFluoh(
        [
          'pub',
          'create',
          upstream.path,
          '--package',
          'camera',
          '--output',
          pubRepository.path,
          '--sdk',
          '3.35.8-ohos-0.0.3',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final manifest = File(
      '${pubRepository.path}/fluoh.yaml',
    ).readAsStringSync();
    expect(manifest, contains('name: camera'));
    expect(manifest, contains('path: packages/camera/camera'));
    expect(stderr, isEmpty);
  });

  test('uses an explicit pub repository URL when provided', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamPackageRepository(
      Directory('${environment.homeDirectory.path}/upstream_custom_remote'),
    );
    final pubRepository = Directory(
      '${environment.homeDirectory.path}/pub_custom_remote',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'add', 'fixture', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(
      await runFluoh(
        [
          'pub',
          'create',
          upstream.path,
          '--output',
          pubRepository.path,
          '--sdk',
          '3.35.8-ohos-0.0.3',
          '--repository',
          'git@github.com:FlutterOH/camera.git',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final origin = await _git(pubRepository, ['remote', 'get-url', 'origin']);
    final manifest = File(
      '${pubRepository.path}/fluoh.yaml',
    ).readAsStringSync();
    expect(
      origin.stdout.toString().trim(),
      'git@github.com:FlutterOH/camera.git',
    );
    expect(manifest, contains('url: git@github.com:FlutterOH/camera.git'));
    expect(stderr, isEmpty);
  });

  test('pub create leaves upstream default branch unchanged', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamPackageRepository(
      Directory('${environment.homeDirectory.path}/upstream_clean_main'),
    );
    final pubRepository = Directory(
      '${environment.homeDirectory.path}/pub_clean_main',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'add', 'fixture', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(
      await runFluoh(
        [
          'pub',
          'create',
          upstream.path,
          '--output',
          pubRepository.path,
          '--sdk',
          '3.35.8-ohos-0.0.3',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    await _git(pubRepository, ['checkout', 'main']);
    expect(File('${pubRepository.path}/fluoh.yaml').existsSync(), isFalse);
    expect(File('${pubRepository.path}/FLUOH_ADAPT.md').existsSync(), isFalse);
    final status = await _git(pubRepository, ['status', '--porcelain']);
    expect(status.stdout.toString().trim(), isEmpty);
    expect(stderr, isEmpty);
  });

  test(
    'pub sync fast-forwards the clean default branch from upstream',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPubSourceFixture(environment.homeDirectory);
      final upstream = await createUpstreamPackageRepository(
        Directory('${environment.homeDirectory.path}/upstream_sync'),
      );
      final pubRepository = Directory(
        '${environment.homeDirectory.path}/pub_sync',
      );
      final stdout = <String>[];
      final stderr = <String>[];

      await runFluoh(
        ['source', 'add', 'fixture', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      await runFluoh(
        [
          'pub',
          'create',
          upstream.path,
          '--output',
          pubRepository.path,
          '--sdk',
          '3.35.8-ohos-0.0.3',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      await bumpUpstreamPackageVersion(upstream, version: '0.12.0');

      final pubEnvironment = FluohEnvironment(
        homeDirectory: environment.homeDirectory,
        workingDirectory: pubRepository,
      );
      expect(
        await runFluoh(
          ['pub', 'sync'],
          environment: pubEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final branch = await _git(pubRepository, ['branch', '--show-current']);
      expect(branch.stdout.toString().trim(), 'ohos/3.35.8-ohos-0.0.3');

      await _git(pubRepository, ['checkout', 'main']);
      final pubspec = File(
        '${pubRepository.path}/pubspec.yaml',
      ).readAsStringSync();
      expect(pubspec, contains('version: 0.12.0'));
      expect(File('${pubRepository.path}/fluoh.yaml').existsSync(), isFalse);
      expect(stdout, contains('Synchronized main from upstream/main.'));
      expect(stderr, isEmpty);
    },
  );

  test(
    'pub adapt merges default branch and refreshes upstream metadata',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPubSourceFixture(environment.homeDirectory);
      final upstream = await createUpstreamPackageRepository(
        Directory('${environment.homeDirectory.path}/upstream_adapt'),
      );
      final pubRepository = Directory(
        '${environment.homeDirectory.path}/pub_adapt',
      );
      final stdout = <String>[];
      final stderr = <String>[];

      await runFluoh(
        ['source', 'add', 'fixture', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      await runFluoh(
        [
          'pub',
          'create',
          upstream.path,
          '--output',
          pubRepository.path,
          '--sdk',
          '3.35.8-ohos-0.0.3',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      await bumpUpstreamPackageVersion(upstream, version: '0.12.0');

      final pubEnvironment = FluohEnvironment(
        homeDirectory: environment.homeDirectory,
        workingDirectory: pubRepository,
      );
      expect(
        await runFluoh(
          ['pub', 'sync'],
          environment: pubEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );
      expect(
        await runFluoh(
          ['pub', 'adapt'],
          environment: pubEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final branch = await _git(pubRepository, ['branch', '--show-current']);
      final manifest = File(
        '${pubRepository.path}/fluoh.yaml',
      ).readAsStringSync();
      expect(branch.stdout.toString().trim(), 'ohos/3.35.8-ohos-0.0.3');
      expect(manifest, contains('version: 0.12.0'));
      expect(manifest, contains('version: 3.35.8-ohos-0.0.3'));
      expect(stdout, contains('Merged main into ohos/3.35.8-ohos-0.0.3.'));
      expect(stdout, contains('Updated pub manifest for camera 0.12.0.'));
      expect(stderr, isEmpty);
    },
  );

  test('pub adapt preserves a non-default manifest status', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamPackageRepository(
      Directory('${environment.homeDirectory.path}/upstream_adapt_status'),
    );
    final pubRepository = Directory(
      '${environment.homeDirectory.path}/pub_adapt_status',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'add', 'fixture', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    await runFluoh(
      [
        'pub',
        'create',
        upstream.path,
        '--output',
        pubRepository.path,
        '--sdk',
        '3.35.8-ohos-0.0.3',
      ],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );

    final manifestFile = File('${pubRepository.path}/fluoh.yaml');
    await manifestFile.writeAsString(
      manifestFile.readAsStringSync().replaceFirst(
        'status: experimental',
        'status: compatible',
      ),
    );
    await _git(pubRepository, ['add', 'fluoh.yaml']);
    await _git(pubRepository, ['commit', '-m', 'Promote manifest status']);
    await bumpUpstreamPackageVersion(upstream, version: '0.12.0');

    final pubEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: pubRepository,
    );
    expect(
      await runFluoh(
        ['pub', 'sync'],
        environment: pubEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );
    expect(
      await runFluoh(
        ['pub', 'adapt'],
        environment: pubEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final manifest = manifestFile.readAsStringSync();
    expect(manifest, contains('status: compatible'));
    expect(manifest, isNot(contains('status: experimental')));
    expect(stderr, isEmpty);
  });

  test(
    'pub sync restores the starting branch when fast-forward fails',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPubSourceFixture(environment.homeDirectory);
      final upstream = await createUpstreamPackageRepository(
        Directory('${environment.homeDirectory.path}/upstream_sync_diverged'),
      );
      final pubRepository = Directory(
        '${environment.homeDirectory.path}/pub_sync_diverged',
      );
      final stdout = <String>[];
      final stderr = <String>[];

      await runFluoh(
        ['source', 'add', 'fixture', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      await runFluoh(
        [
          'pub',
          'create',
          upstream.path,
          '--output',
          pubRepository.path,
          '--sdk',
          '3.35.8-ohos-0.0.3',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );

      await _git(pubRepository, ['checkout', 'main']);
      await File('${pubRepository.path}/LOCAL.md').writeAsString('local\n');
      await _git(pubRepository, ['add', 'LOCAL.md']);
      await _git(pubRepository, ['commit', '-m', 'Local main change']);
      await _git(pubRepository, ['checkout', 'ohos/3.35.8-ohos-0.0.3']);
      await bumpUpstreamPackageVersion(upstream, version: '0.12.0');

      final pubEnvironment = FluohEnvironment(
        homeDirectory: environment.homeDirectory,
        workingDirectory: pubRepository,
      );
      expect(
        await runFluoh(
          ['pub', 'sync'],
          environment: pubEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        64,
      );

      final branch = await _git(pubRepository, ['branch', '--show-current']);
      expect(branch.stdout.toString().trim(), 'ohos/3.35.8-ohos-0.0.3');
      expect(stderr.join('\n'), contains('Not possible to fast-forward'));
    },
  );

  test('does not accept removed GitHub automation flags', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamPackageRepository(
      Directory('${environment.homeDirectory.path}/upstream_github_flags'),
    );
    final pubRepository = Directory(
      '${environment.homeDirectory.path}/pub_github_flags',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'add', 'fixture', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(
      await runFluoh(
        [
          'pub',
          'create',
          upstream.path,
          '--output',
          pubRepository.path,
          '--sdk',
          '3.35.8-ohos-0.0.3',
          '--github',
          '--org',
          'FlutterOH',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );
    expect(stderr.join('\n'), contains('Could not find an option named'));
  });
  test('release writes a pub source package update', () async {
    final environment = await createTestEnvironment();
    final pubRepository = await _createPubFixture(environment);
    final pubSource = Directory('${environment.homeDirectory.path}/pub_update');
    final releaseEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: pubRepository,
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['pub', 'release', '--source-update', pubSource.path],
        environment: releaseEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final registryYaml = File('${pubSource.path}/packages/registry.yaml');
    final manifestYaml = File(
      '${pubSource.path}/packages/manifests/camera.yaml',
    );
    expect(registryYaml.existsSync(), isTrue);
    expect(manifestYaml.existsSync(), isTrue);
    expect(registryYaml.readAsStringSync(), contains('name: camera'));
    expect(
      manifestYaml.readAsStringSync(),
      contains('version: 3.35.8-ohos-0.0.3'),
    );
    expect(manifestYaml.readAsStringSync(), isNot(contains('versionSeries')));
    expect(
      manifestYaml.readAsStringSync(),
      contains('sourceBranch: ohos/3.35.8-ohos-0.0.3'),
    );
    expect(
      manifestYaml.readAsStringSync(),
      contains('tag: camera-v0.11.0-ohos-3.35.8-ohos-0.0.3-0.1.0'),
    );
    expect(File('${pubSource.path}/packages/index.yaml').existsSync(), isFalse);
    expect(
      File('${pubSource.path}/packages/camera.yaml').existsSync(),
      isFalse,
    );
    expect(
      await runFluoh(
        ['source', 'add', 'generated', pubSource.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );
    expect(stdout, contains('Wrote pub source update for camera.'));
    expect(stdout, contains('Added source generated: ${pubSource.path}'));
    expect(stderr, isEmpty);
  });

  test(
    'release fails for dirty pub worktrees and mismatched branches',
    () async {
      final environment = await createTestEnvironment();
      final pubRepository = await _createPubFixture(environment);
      final stdout = <String>[];
      final stderr = <String>[];

      await File('${pubRepository.path}/README.md').writeAsString('# dirty\n');
      final dirtyEnvironment = FluohEnvironment(
        homeDirectory: environment.homeDirectory,
        workingDirectory: pubRepository,
      );
      expect(
        await runFluoh(
          ['pub', 'release'],
          environment: dirtyEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        64,
      );
      expect(
        stderr.join('\n'),
        contains('Release requires a clean working tree'),
      );

      await _git(pubRepository, ['checkout', '--', 'README.md']);
      await _git(pubRepository, ['checkout', '-b', 'ohos/3.35.8-ohos-9.9.9']);
      stderr.clear();
      expect(
        await runFluoh(
          ['pub', 'release'],
          environment: dirtyEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        64,
      );
      expect(
        stderr.join('\n'),
        contains('does not match pub branch ohos/3.35.8-ohos-0.0.3'),
      );
    },
  );

  test('release validates SDK tag and existing release tag commit', () async {
    final environment = await createTestEnvironment();
    final pubRepository = await _createPubFixture(environment);
    final releaseEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: pubRepository,
    );
    final stdout = <String>[];
    final stderr = <String>[];

    var manifest = File('${pubRepository.path}/fluoh.yaml').readAsStringSync();
    await File('${pubRepository.path}/fluoh.yaml').writeAsString(
      manifest.replaceFirst(
        '  version: 3.35.8-ohos-0.0.3',
        '  version: 3.35.8-ohos-9.9.9',
      ),
    );
    await _git(pubRepository, ['add', 'fluoh.yaml']);
    await _git(pubRepository, ['commit', '-m', 'Use invalid SDK tag']);

    expect(
      await runFluoh(
        ['pub', 'release'],
        environment: releaseEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );
    expect(stderr.join('\n'), contains('was not found in configured sources'));

    manifest = File('${pubRepository.path}/fluoh.yaml').readAsStringSync();
    await File('${pubRepository.path}/fluoh.yaml').writeAsString(
      manifest.replaceFirst(
        '  version: 3.35.8-ohos-9.9.9',
        '  version: 3.35.8-ohos-0.0.3',
      ),
    );
    await _git(pubRepository, ['add', 'fluoh.yaml']);
    await _git(pubRepository, ['commit', '-m', 'Restore valid SDK tag']);
    await _git(pubRepository, [
      'tag',
      'camera-v0.11.0-ohos-3.35.8-ohos-0.0.3-0.1.0',
      'HEAD~1',
    ]);

    stderr.clear();
    expect(
      await runFluoh(
        ['pub', 'release'],
        environment: releaseEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );
    expect(stderr.join('\n'), contains('already exists on a different commit'));
  });
}

Future<Directory> _createPubFixture(FluohEnvironment environment) async {
  final source = await createPubSourceFixture(environment.homeDirectory);
  final upstream = await createUpstreamPackageRepository(
    Directory('${environment.homeDirectory.path}/upstream_camera'),
  );
  final pubRepository = Directory(
    '${environment.homeDirectory.path}/pub_release',
  );
  final stdout = <String>[];
  final stderr = <String>[];

  await runFluoh(
    ['source', 'add', 'fixture', source.path],
    environment: environment,
    stdout: stdout.add,
    stderr: stderr.add,
  );
  await runFluoh(
    [
      'pub',
      'create',
      upstream.path,
      '--output',
      pubRepository.path,
      '--sdk',
      '3.35.8-ohos-0.0.3',
    ],
    environment: environment,
    stdout: stdout.add,
    stderr: stderr.add,
  );

  return pubRepository;
}

Future<ProcessResult> _git(Directory repo, List<String> arguments) async {
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
