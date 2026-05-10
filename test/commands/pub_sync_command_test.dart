import 'dart:io';

import 'package:fluoh/fluoh.dart';
import 'package:test/test.dart';

import '../helpers/fluoh_test_context.dart';
import '../helpers/pub_test_context.dart';

void main() {
  test(
    'pub sync fast-forwards upstream, merges the pub branch, and refreshes upstream metadata',
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
      await commitGeneratedPubRepository(pubRepository);
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

      final branch = await runGit(pubRepository, ['branch', '--show-current']);
      final pubspec = File(
        '${pubRepository.path}/pubspec.yaml',
      ).readAsStringSync();
      final manifest = File(
        '${pubRepository.path}/fluoh.yaml',
      ).readAsStringSync();
      final mainHead = await runGit(pubRepository, ['rev-parse', 'main']);
      final subject = await runGit(pubRepository, ['log', '-1', '--format=%s']);
      expect(branch.stdout.toString().trim(), 'ohos/3.35');
      expect(pubspec, contains('version: 0.12.0'));
      expect(manifest, contains('packages:\n  camera:'));
      expect(manifest, contains('      version: 0.1.0'));
      expect(manifest, contains('      version: 0.12.0'));
      expect(manifest, contains('  ref: ${mainHead.stdout.toString().trim()}'));
      expect(subject.stdout.toString().trim(), 'Sync upstream packages');

      await runGit(pubRepository, ['checkout', 'main']);
      final upstreamPubspec = File(
        '${pubRepository.path}/pubspec.yaml',
      ).readAsStringSync();
      expect(upstreamPubspec, contains('version: 0.12.0'));
      expect(File('${pubRepository.path}/fluoh.yaml').existsSync(), isFalse);
      expect(stdout, contains('Synchronized main from upstream/main.'));
      expect(stdout, contains('Merged main into ohos/3.35.'));
      expect(
        stdout,
        contains('Updated upstream metadata for registered packages.'),
      );
      expect(stderr, isEmpty);
    },
  );

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
      await commitGeneratedPubRepository(pubRepository);

      await runGit(pubRepository, ['checkout', 'main']);
      await File('${pubRepository.path}/LOCAL.md').writeAsString('local\n');
      await runGit(pubRepository, ['add', 'LOCAL.md']);
      await runGit(pubRepository, ['commit', '-m', 'Local main change']);
      await runGit(pubRepository, ['checkout', 'ohos/3.35']);
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

      final branch = await runGit(pubRepository, ['branch', '--show-current']);
      expect(branch.stdout.toString().trim(), 'ohos/3.35');
      expect(stderr.join('\n'), contains('Not possible to fast-forward'));
    },
  );

  test(
    'pub sync refuses dirty pub branches before switching branches',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPubSourceFixture(environment.homeDirectory);
      final upstream = await createUpstreamPackageRepository(
        Directory('${environment.homeDirectory.path}/upstream_sync_dirty'),
      );
      final pubRepository = Directory(
        '${environment.homeDirectory.path}/pub_sync_dirty',
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
      await commitGeneratedPubRepository(pubRepository);
      await bumpUpstreamPackageVersion(upstream, version: '0.12.0');

      await File(
        '${pubRepository.path}/README.md',
      ).writeAsString('# camera\n\nUncommitted OHOS notes.\n');
      await File(
        '${pubRepository.path}/LOCAL_NOTES.md',
      ).writeAsString('untracked\n');

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

      final branch = await runGit(pubRepository, ['branch', '--show-current']);
      final status = await runGit(pubRepository, ['status', '--short']);
      expect(branch.stdout.toString().trim(), 'ohos/3.35');
      expect(status.stdout.toString(), contains('M README.md'));
      expect(status.stdout.toString(), contains('?? LOCAL_NOTES.md'));
      expect(
        stderr.join('\n'),
        contains('Sync requires a clean working tree.'),
      );
    },
  );

  test('pub sync continuation commands require an active merge', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamPackageRepository(
      Directory('${environment.homeDirectory.path}/upstream_sync_no_merge'),
    );
    final pubRepository = Directory(
      '${environment.homeDirectory.path}/pub_sync_no_merge',
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
    await commitGeneratedPubRepository(pubRepository);

    final pubEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: pubRepository,
    );
    expect(
      await runFluoh(
        ['pub', 'sync', '--continue'],
        environment: pubEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );
    expect(
      await runFluoh(
        ['pub', 'sync', '--abort'],
        environment: pubEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );
    expect(
      stderr.where((message) => message == 'No pub sync merge is in progress.'),
      hasLength(2),
    );
  });

  test('pub sync abort validates the current pub branch', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamPackageRepository(
      Directory('${environment.homeDirectory.path}/upstream_sync_abort_branch'),
    );
    final pubRepository = Directory(
      '${environment.homeDirectory.path}/pub_sync_abort_branch',
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
    await commitGeneratedPubRepository(pubRepository);

    await runGit(pubRepository, ['checkout', '-b', 'feature/manual-merge']);
    await runGit(pubRepository, ['checkout', 'ohos/3.35']);
    await File(
      '${pubRepository.path}/UPSTREAM_NOTE.md',
    ).writeAsString('upstream note\n');
    await runGit(pubRepository, ['add', 'UPSTREAM_NOTE.md']);
    await runGit(pubRepository, ['commit', '-m', 'Add upstream note']);
    await runGit(pubRepository, ['checkout', 'feature/manual-merge']);
    await runGit(pubRepository, [
      'merge',
      '--no-ff',
      '--no-commit',
      'ohos/3.35',
    ]);

    final pubEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: pubRepository,
    );
    expect(
      await runFluoh(
        ['pub', 'sync', '--abort'],
        environment: pubEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );

    final mergeHead = await runGit(pubRepository, [
      'rev-parse',
      '--verify',
      'MERGE_HEAD',
    ]);
    expect(mergeHead.stdout.toString().trim(), isNotEmpty);
    expect(
      stderr.join('\n'),
      contains('Sync must run from an ohos/* pub branch.'),
    );
    await runGit(pubRepository, ['merge', '--abort']);
  });

  test('pub sync preserves package release metadata', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamPackageRepository(
      Directory('${environment.homeDirectory.path}/upstream_sync_metadata'),
    );
    final pubRepository = Directory(
      '${environment.homeDirectory.path}/pub_sync_metadata',
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
      manifestFile
          .readAsStringSync()
          .replaceFirst(
            'repository:',
            'dependencyPolicy:\n  replacementMode: overrides\n\nrepository:',
          )
          .replaceFirst('      version: 0.1.0', '      version: 0.2.0')
          .replaceFirst('status: experimental', 'status: compatible'),
    );
    await commitGeneratedPubRepository(
      pubRepository,
      message: 'Promote manifest status',
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

    final manifest = manifestFile.readAsStringSync();
    expect(
      manifest,
      contains('dependencyPolicy:\n  replacementMode: overrides'),
    );
    expect(manifest, contains('packages:\n  camera:'));
    expect(manifest, contains('      version: 0.2.0'));
    expect(manifest, contains('status: compatible'));
    expect(manifest, contains('      version: 0.12.0'));
    expect(stderr, isEmpty);
  });

  test('pub sync continues after resolved merge conflicts', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamPackageRepository(
      Directory('${environment.homeDirectory.path}/upstream_sync_conflict'),
    );
    final pubRepository = Directory(
      '${environment.homeDirectory.path}/pub_sync_conflict',
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
    await commitGeneratedPubRepository(pubRepository);

    await File(
      '${pubRepository.path}/README.md',
    ).writeAsString('# camera\n\nLocal OHOS notes.\n');
    await runGit(pubRepository, ['add', 'README.md']);
    await runGit(pubRepository, ['commit', '-m', 'Adapt README']);
    await File(
      '${upstream.path}/README.md',
    ).writeAsString('# camera\n\nUpstream notes.\n');
    await File('${upstream.path}/pubspec.yaml').writeAsString('''
name: camera
version: 0.12.0

environment:
  sdk: ^3.0.0
''');
    await runGit(upstream, ['add', 'README.md', 'pubspec.yaml']);
    await runGit(upstream, ['commit', '-m', 'Release 0.12.0']);

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
    expect(
      stderr.join('\n'),
      contains('Resolve conflicts, stage the resolved files, and run'),
    );

    await File(
      '${pubRepository.path}/README.md',
    ).writeAsString('# camera\n\nLocal OHOS notes.\nUpstream notes.\n');
    await runGit(pubRepository, ['add', 'README.md']);
    expect(
      await runFluoh(
        ['pub', 'sync', '--continue'],
        environment: pubEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final manifest = File(
      '${pubRepository.path}/fluoh.yaml',
    ).readAsStringSync();
    final subject = await runGit(pubRepository, ['log', '-1', '--format=%s']);
    expect(manifest, contains('      version: 0.12.0'));
    expect(subject.stdout.toString().trim(), 'Sync upstream packages');
  });

  test('pub sync preserves separate upstream and dependency paths', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamMonorepoRepository(
      Directory('${environment.homeDirectory.path}/upstream_sync_paths'),
      packagePath: 'packages/camera/camera',
    );
    final pubRepository = Directory(
      '${environment.homeDirectory.path}/pub_sync_paths',
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
        '--path',
        'packages/camera/camera',
      ],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );

    final manifestFile = File('${pubRepository.path}/fluoh.yaml');
    await Directory(
      '${pubRepository.path}/adapter/camera',
    ).create(recursive: true);
    await File(
      '${pubRepository.path}/adapter/camera/pubspec.yaml',
    ).writeAsString('''
name: camera
version: 0.11.0

environment:
  sdk: ^3.0.0
''');
    await manifestFile.writeAsString(
      manifestFile.readAsStringSync().replaceFirst(
        '    path: packages/camera/camera',
        '    path: adapter/camera',
      ),
    );
    await commitGeneratedPubRepository(
      pubRepository,
      message: 'Use separate dependency path',
    );
    await bumpUpstreamPackageVersion(
      upstream,
      version: '0.12.0',
      packagePath: 'packages/camera/camera',
    );

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

    final manifest = manifestFile.readAsStringSync();
    expect(manifest, contains('version: 0.12.0'));
    expect(manifest, contains('    path: adapter/camera'));
    expect(manifest, contains('    path: packages/camera/camera'));
    expect(stderr, isEmpty);
  });

  test('pub sync does not copy upstream paths to root adapters', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamMonorepoRepository(
      Directory('${environment.homeDirectory.path}/upstream_sync_root_path'),
      packagePath: 'packages/camera/camera',
    );
    final pubRepository = Directory(
      '${environment.homeDirectory.path}/pub_sync_root_path',
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
        '--path',
        'packages/camera/camera',
      ],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );

    final manifestFile = File('${pubRepository.path}/fluoh.yaml');
    await manifestFile.writeAsString(
      manifestFile.readAsStringSync().replaceFirst(
        '    path: packages/camera/camera\n',
        '',
      ),
    );
    await commitGeneratedPubRepository(
      pubRepository,
      message: 'Use root dependency path',
    );
    await bumpUpstreamPackageVersion(
      upstream,
      version: '0.12.0',
      packagePath: 'packages/camera/camera',
    );

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

    final manifest = manifestFile.readAsStringSync();
    expect(manifest, contains('version: 0.12.0'));
    expect(
      RegExp(
        r'^\s+path: packages/camera/camera$',
        multiLine: true,
      ).allMatches(manifest),
      hasLength(1),
    );
    expect(stderr, isEmpty);
  });

  test(
    'pub sync fails when an upstream path points at another package',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPubSourceFixture(environment.homeDirectory);
      final upstream = await createUpstreamMonorepoRepository(
        Directory('${environment.homeDirectory.path}/upstream_sync_wrong_path'),
        packagePath: 'packages/camera/camera',
        packageName: 'camera',
      );
      await _addMonorepoPackage(
        upstream,
        path: 'packages/share_plus/share_plus',
        name: 'share_plus',
        version: '9.0.0',
      );
      final pubRepository = Directory(
        '${environment.homeDirectory.path}/pub_sync_wrong_path',
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
          '--path',
          'packages/camera/camera',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );

      final manifestFile = File('${pubRepository.path}/fluoh.yaml');
      await manifestFile.writeAsString(
        manifestFile.readAsStringSync().replaceFirst(
          '      path: packages/camera/camera',
          '      path: packages/share_plus/share_plus',
        ),
      );
      await commitGeneratedPubRepository(
        pubRepository,
        message: 'Point camera upstream path at share_plus',
      );

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

      expect(
        stderr.join('\n'),
        contains(
          'Package path packages/share_plus/share_plus contains share_plus, '
          'expected camera.',
        ),
      );
    },
  );
}

Future<void> _addMonorepoPackage(
  Directory repository, {
  required String path,
  required String name,
  required String version,
}) async {
  final packageDirectory = Directory('${repository.path}/$path');
  await packageDirectory.create(recursive: true);
  await File('${packageDirectory.path}/pubspec.yaml').writeAsString('''
name: $name
version: $version

environment:
  sdk: ^3.0.0
''');
  await runGit(repository, ['add', '.']);
  await runGit(repository, ['commit', '-m', 'Add $name fixture']);
}
