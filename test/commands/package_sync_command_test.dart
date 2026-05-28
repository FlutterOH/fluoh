import 'dart:io';
import 'dart:convert';

import 'package:fluoh/fluoh.dart';
import 'package:test/test.dart';

import '../helpers/fluoh_command_context.dart';
import '../helpers/package_test_context.dart';

void main() {
  test(
    'package sync fast-forwards upstream, merges the package branch, and refreshes upstream metadata',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      final upstream = await createUpstreamPackageRepository(
        Directory('${environment.homeDirectory.path}/upstream_sync'),
      );
      final packageRepository = Directory(
        '${environment.homeDirectory.path}/package_sync',
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
          'package',
          'create',
          upstream.path,
          '--output',
          packageRepository.path,
          '--sdk',
          '3.35.8-ohos-0.0.3',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      await commitGeneratedPackageRepository(packageRepository);
      await bumpUpstreamPackageVersion(upstream, version: '0.12.0');

      final packageEnvironment = FluohEnvironment(
        homeDirectory: environment.homeDirectory,
        workingDirectory: packageRepository,
      );
      expect(
        await runFluoh(
          ['package', 'sync'],
          environment: packageEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final branch = await runGit(packageRepository, [
        'branch',
        '--show-current',
      ]);
      final pubspec = File(
        '${packageRepository.path}/pubspec.yaml',
      ).readAsStringSync();
      final manifest = File(
        '${packageRepository.path}/fluoh.yaml',
      ).readAsStringSync();
      final subject = await runGit(packageRepository, [
        'log',
        '-1',
        '--format=%s',
      ]);
      expect(branch.stdout.toString().trim(), 'ohos/3.35');
      expect(pubspec, contains('version: 0.12.0'));
      expect(manifest, contains('packages:\n  camera:'));
      expect(manifest, contains('    version: 0.1.0'));
      expect(manifest, contains('    upstreamVersion: 0.12.0'));
      expect(subject.stdout.toString().trim(), 'Sync upstream packages');

      await runGit(packageRepository, ['checkout', 'main']);
      final upstreamPubspec = File(
        '${packageRepository.path}/pubspec.yaml',
      ).readAsStringSync();
      expect(upstreamPubspec, contains('version: 0.12.0'));
      expect(
        File('${packageRepository.path}/fluoh.yaml').existsSync(),
        isFalse,
      );
      expect(stdout, contains('Synchronized main from upstream/main'));
      expect(stdout, contains('Merged main into ohos/3.35'));
      expect(
        stdout,
        contains('Updated upstream metadata for registered packages'),
      );
      expect(stderr, isEmpty);
    },
  );

  test('package sync can emit json results', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamPackageRepository(
      Directory('${environment.homeDirectory.path}/upstream_sync_json'),
    );
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_sync_json',
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
        'package',
        'create',
        upstream.path,
        '--output',
        packageRepository.path,
        '--sdk',
        '3.35.8-ohos-0.0.3',
      ],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    await commitGeneratedPackageRepository(packageRepository);
    await bumpUpstreamPackageVersion(upstream, version: '0.12.0');
    stdout.clear();

    expect(
      await runFluoh(
        ['package', 'sync', '--json'],
        environment: FluohEnvironment(
          homeDirectory: environment.homeDirectory,
          workingDirectory: packageRepository,
        ),
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('schemaVersion', 1));
    expect(report, containsPair('command', 'package sync'));
    expect(report, containsPair('ok', true));
    expect(report, containsPair('exitCode', 0));
    expect(report, containsPair('status', 'synced'));
    expect(report, containsPair('committed', true));
    expect(report, containsPair('packageBranch', 'ohos/3.35'));
    expect(stderr, isEmpty);
  });

  test(
    'package sync restores the starting branch when fast-forward fails',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      final upstream = await createUpstreamPackageRepository(
        Directory('${environment.homeDirectory.path}/upstream_sync_diverged'),
      );
      final packageRepository = Directory(
        '${environment.homeDirectory.path}/package_sync_diverged',
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
          'package',
          'create',
          upstream.path,
          '--output',
          packageRepository.path,
          '--sdk',
          '3.35.8-ohos-0.0.3',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      await commitGeneratedPackageRepository(packageRepository);

      await runGit(packageRepository, ['checkout', 'main']);
      await File('${packageRepository.path}/LOCAL.md').writeAsString('local\n');
      await runGit(packageRepository, ['add', 'LOCAL.md']);
      await runGit(packageRepository, ['commit', '-m', 'Local main change']);
      await runGit(packageRepository, ['checkout', 'ohos/3.35']);
      await bumpUpstreamPackageVersion(upstream, version: '0.12.0');

      final packageEnvironment = FluohEnvironment(
        homeDirectory: environment.homeDirectory,
        workingDirectory: packageRepository,
      );
      expect(
        await runFluoh(
          ['package', 'sync'],
          environment: packageEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        64,
      );

      final branch = await runGit(packageRepository, [
        'branch',
        '--show-current',
      ]);
      expect(branch.stdout.toString().trim(), 'ohos/3.35');
      expect(stderr.join('\n'), contains('Not possible to fast-forward'));
    },
  );

  test(
    'package sync refuses dirty package branches before switching branches',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      final upstream = await createUpstreamPackageRepository(
        Directory('${environment.homeDirectory.path}/upstream_sync_dirty'),
      );
      final packageRepository = Directory(
        '${environment.homeDirectory.path}/package_sync_dirty',
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
          'package',
          'create',
          upstream.path,
          '--output',
          packageRepository.path,
          '--sdk',
          '3.35.8-ohos-0.0.3',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      await commitGeneratedPackageRepository(packageRepository);
      await bumpUpstreamPackageVersion(upstream, version: '0.12.0');

      await File(
        '${packageRepository.path}/README.md',
      ).writeAsString('# camera\n\nUncommitted OHOS notes.\n');
      await File(
        '${packageRepository.path}/LOCAL_NOTES.md',
      ).writeAsString('untracked\n');

      final packageEnvironment = FluohEnvironment(
        homeDirectory: environment.homeDirectory,
        workingDirectory: packageRepository,
      );
      expect(
        await runFluoh(
          ['package', 'sync'],
          environment: packageEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        64,
      );

      final branch = await runGit(packageRepository, [
        'branch',
        '--show-current',
      ]);
      final status = await runGit(packageRepository, ['status', '--short']);
      expect(branch.stdout.toString().trim(), 'ohos/3.35');
      expect(status.stdout.toString(), contains('M README.md'));
      expect(status.stdout.toString(), contains('?? LOCAL_NOTES.md'));
      expect(
        stderr.join('\n'),
        contains('Sync requires a clean working tree.'),
      );
    },
  );

  test('package sync continuation commands require an active merge', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamPackageRepository(
      Directory('${environment.homeDirectory.path}/upstream_sync_no_merge'),
    );
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_sync_no_merge',
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
        'package',
        'create',
        upstream.path,
        '--output',
        packageRepository.path,
        '--sdk',
        '3.35.8-ohos-0.0.3',
      ],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    await commitGeneratedPackageRepository(packageRepository);

    final packageEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    expect(
      await runFluoh(
        ['package', 'sync', '--continue'],
        environment: packageEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );
    expect(
      await runFluoh(
        ['package', 'sync', '--abort'],
        environment: packageEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );
    expect(
      stderr.where(
        (message) => message == 'No package sync merge is in progress.',
      ),
      hasLength(2),
    );
  });

  test('package sync abort validates the current package branch', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamPackageRepository(
      Directory('${environment.homeDirectory.path}/upstream_sync_abort_branch'),
    );
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_sync_abort_branch',
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
        'package',
        'create',
        upstream.path,
        '--output',
        packageRepository.path,
        '--sdk',
        '3.35.8-ohos-0.0.3',
      ],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    await commitGeneratedPackageRepository(packageRepository);

    await runGit(packageRepository, ['checkout', '-b', 'feature/manual-merge']);
    await runGit(packageRepository, ['checkout', 'ohos/3.35']);
    await File(
      '${packageRepository.path}/UPSTREAM_NOTE.md',
    ).writeAsString('upstream note\n');
    await runGit(packageRepository, ['add', 'UPSTREAM_NOTE.md']);
    await runGit(packageRepository, ['commit', '-m', 'Add upstream note']);
    await runGit(packageRepository, ['checkout', 'feature/manual-merge']);
    await runGit(packageRepository, [
      'merge',
      '--no-ff',
      '--no-commit',
      'ohos/3.35',
    ]);

    final packageEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    expect(
      await runFluoh(
        ['package', 'sync', '--abort'],
        environment: packageEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );

    final mergeHead = await runGit(packageRepository, [
      'rev-parse',
      '--verify',
      'MERGE_HEAD',
    ]);
    expect(mergeHead.stdout.toString().trim(), isNotEmpty);
    expect(
      stderr.join('\n'),
      contains(
        'Current branch feature/manual-merge does not match package branch '
        'ohos/3.35.',
      ),
    );
    await runGit(packageRepository, ['merge', '--abort']);
  });

  test('package sync preserves package release metadata', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamPackageRepository(
      Directory('${environment.homeDirectory.path}/upstream_sync_metadata'),
    );
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_sync_metadata',
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
        'package',
        'create',
        upstream.path,
        '--output',
        packageRepository.path,
        '--sdk',
        '3.35.8-ohos-0.0.3',
      ],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );

    final manifestFile = File('${packageRepository.path}/fluoh.yaml');
    await manifestFile.writeAsString(
      manifestFile
          .readAsStringSync()
          .replaceFirst('    version: 0.1.0', '    version: 0.2.0')
          .replaceFirst('status: experimental', 'status: compatible'),
    );
    await commitGeneratedPackageRepository(
      packageRepository,
      message: 'Promote manifest status',
    );
    await bumpUpstreamPackageVersion(upstream, version: '0.12.0');

    final packageEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    expect(
      await runFluoh(
        ['package', 'sync'],
        environment: packageEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final manifest = manifestFile.readAsStringSync();
    expect(manifest, contains('packages:\n  camera:'));
    expect(manifest, contains('    version: 0.2.0'));
    expect(manifest, isNot(contains('status: experimental')));
    expect(manifest, contains('    upstreamVersion: 0.12.0'));
    expect(stderr, isEmpty);
  });

  test('package sync continues after resolved merge conflicts', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamPackageRepository(
      Directory('${environment.homeDirectory.path}/upstream_sync_conflict'),
    );
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_sync_conflict',
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
        'package',
        'create',
        upstream.path,
        '--output',
        packageRepository.path,
        '--sdk',
        '3.35.8-ohos-0.0.3',
      ],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    await commitGeneratedPackageRepository(packageRepository);

    await File(
      '${packageRepository.path}/README.md',
    ).writeAsString('# camera\n\nLocal OHOS notes.\n');
    await runGit(packageRepository, ['add', 'README.md']);
    await runGit(packageRepository, ['commit', '-m', 'Implement README']);
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

    final packageEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    expect(
      await runFluoh(
        ['package', 'sync'],
        environment: packageEnvironment,
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
      '${packageRepository.path}/README.md',
    ).writeAsString('# camera\n\nLocal OHOS notes.\nUpstream notes.\n');
    await runGit(packageRepository, ['add', 'README.md']);
    expect(
      await runFluoh(
        ['package', 'sync', '--continue'],
        environment: packageEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final manifest = File(
      '${packageRepository.path}/fluoh.yaml',
    ).readAsStringSync();
    final subject = await runGit(packageRepository, [
      'log',
      '-1',
      '--format=%s',
    ]);
    expect(manifest, contains('    upstreamVersion: 0.12.0'));
    expect(subject.stdout.toString().trim(), 'Sync upstream packages');
  });

  test(
    'package sync preserves separate upstream and dependency paths',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      final upstream = await createUpstreamWorkspaceRepository(
        Directory('${environment.homeDirectory.path}/upstream_sync_paths'),
        packagePath: 'packages/camera/camera',
      );
      final packageRepository = Directory(
        '${environment.homeDirectory.path}/package_sync_paths',
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
          'package',
          'create',
          upstream.path,
          '--output',
          packageRepository.path,
          '--sdk',
          '3.35.8-ohos-0.0.3',
          '--package-path',
          'packages/camera/camera',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );

      final manifestFile = File('${packageRepository.path}/fluoh.yaml');
      await Directory(
        '${packageRepository.path}/implementation/camera',
      ).create(recursive: true);
      await File(
        '${packageRepository.path}/implementation/camera/pubspec.yaml',
      ).writeAsString('''
name: camera
version: 0.11.0

environment:
  sdk: ^3.0.0
''');
      await manifestFile.writeAsString(
        manifestFile.readAsStringSync().replaceFirst(
          '    path: packages/camera/camera',
          '    path: implementation/camera',
        ),
      );
      await commitGeneratedPackageRepository(
        packageRepository,
        message: 'Use separate dependency path',
      );
      await bumpUpstreamPackageVersion(
        upstream,
        version: '0.12.0',
        packagePath: 'packages/camera/camera',
      );

      final packageEnvironment = FluohEnvironment(
        homeDirectory: environment.homeDirectory,
        workingDirectory: packageRepository,
      );
      expect(
        await runFluoh(
          ['package', 'sync'],
          environment: packageEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final manifest = manifestFile.readAsStringSync();
      expect(manifest, contains('upstreamVersion: 0.12.0'));
      expect(manifest, contains('    path: implementation/camera'));
      expect(manifest, contains('    path: packages/camera/camera'));
      expect(stderr, isEmpty);
    },
  );

  test(
    'package sync does not copy upstream paths to root implementations',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      final upstream = await createUpstreamWorkspaceRepository(
        Directory('${environment.homeDirectory.path}/upstream_sync_root_path'),
        packagePath: 'packages/camera/camera',
      );
      final packageRepository = Directory(
        '${environment.homeDirectory.path}/package_sync_root_path',
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
          'package',
          'create',
          upstream.path,
          '--output',
          packageRepository.path,
          '--sdk',
          '3.35.8-ohos-0.0.3',
          '--package-path',
          'packages/camera/camera',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );

      final manifestFile = File('${packageRepository.path}/fluoh.yaml');
      await manifestFile.writeAsString(
        manifestFile.readAsStringSync().replaceFirst(
          '    repository:\n      path: packages/camera/camera\n',
          '',
        ),
      );
      await commitGeneratedPackageRepository(
        packageRepository,
        message: 'Use root dependency path',
      );
      await bumpUpstreamPackageVersion(
        upstream,
        version: '0.12.0',
        packagePath: 'packages/camera/camera',
      );

      final packageEnvironment = FluohEnvironment(
        homeDirectory: environment.homeDirectory,
        workingDirectory: packageRepository,
      );
      expect(
        await runFluoh(
          ['package', 'sync'],
          environment: packageEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final manifest = manifestFile.readAsStringSync();
      expect(manifest, contains('upstreamVersion: 0.12.0'));
      expect(
        RegExp(
          r'^\s+path: packages/camera/camera$',
          multiLine: true,
        ).allMatches(manifest),
        hasLength(1),
      );
      expect(stderr, isEmpty);
    },
  );

  test(
    'package sync fails when an upstream path points at another package',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      final upstream = await createUpstreamWorkspaceRepository(
        Directory('${environment.homeDirectory.path}/upstream_sync_wrong_path'),
        packagePath: 'packages/camera/camera',
        packageName: 'camera',
      );
      await _addWorkspacePackage(
        upstream,
        path: 'packages/share_plus/share_plus',
        name: 'share_plus',
        version: '9.0.0',
      );
      final packageRepository = Directory(
        '${environment.homeDirectory.path}/package_sync_wrong_path',
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
          'package',
          'create',
          upstream.path,
          '--output',
          packageRepository.path,
          '--sdk',
          '3.35.8-ohos-0.0.3',
          '--package-path',
          'packages/camera/camera',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );

      final manifestFile = File('${packageRepository.path}/fluoh.yaml');
      await manifestFile.writeAsString(
        manifestFile.readAsStringSync().replaceFirst(
          '    upstream:\n      path: packages/camera/camera',
          '    upstream:\n      path: packages/share_plus/share_plus',
        ),
      );
      await commitGeneratedPackageRepository(
        packageRepository,
        message: 'Point camera upstream path at share_plus',
      );

      final packageEnvironment = FluohEnvironment(
        homeDirectory: environment.homeDirectory,
        workingDirectory: packageRepository,
      );
      expect(
        await runFluoh(
          ['package', 'sync'],
          environment: packageEnvironment,
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

Future<void> _addWorkspacePackage(
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
