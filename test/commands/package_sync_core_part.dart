part of 'package_sync_command_test.dart';

void _registerPackageSyncCoreTests() {
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
          '--repository-name',
          'camera',
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
      expect(branch.stdout.toString().trim(), 'ohos/3.35/camera');
      expect(pubspec, contains('version: 0.12.0'));
      expect(manifest, contains('package:\n  name: camera'));
      expect(manifest, contains('    version: 0.1.0'));
      expect(manifest, contains('    upstream:\n      version: 0.12.0'));
      expect(subject.stdout.toString().trim(), 'Sync upstream package');

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
      expect(stdout, contains('Merged main into ohos/3.35/camera'));
      expect(stdout, contains('Updated upstream metadata for package branch'));
      expect(stderr, isEmpty);
    },
  );

  test(
    'package sync merges latest release tag instead of upstream HEAD',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      final upstream = await createUpstreamPackageRepository(
        Directory('${environment.homeDirectory.path}/upstream_sync_tag'),
      );
      await runGit(upstream, ['tag', 'v0.11.0']);
      final packageRepository = Directory(
        '${environment.homeDirectory.path}/package_sync_tag',
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
          '--repository-name',
          'camera',
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
      await runGit(upstream, ['tag', 'v0.12.0']);
      await bumpUpstreamPackageVersion(upstream, version: '0.13.0');

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

      final packagePubspec = File(
        '${packageRepository.path}/pubspec.yaml',
      ).readAsStringSync();
      final manifest = await readPackageManifest(packageRepository);
      expect(packagePubspec, contains('version: 0.12.0'));
      expect(packagePubspec, isNot(contains('version: 0.13.0')));
      expect(manifest.primaryPackage.upstreamVersion, '0.12.0');
      expect(manifest.primaryPackage.upstreamRef, 'v0.12.0');
      expect(stdout, contains('Merged v0.12.0 into ohos/3.35/camera'));

      await runGit(packageRepository, ['checkout', 'main']);
      final upstreamPubspec = File(
        '${packageRepository.path}/pubspec.yaml',
      ).readAsStringSync();
      expect(upstreamPubspec, contains('version: 0.13.0'));
      expect(stderr, isEmpty);
    },
  );

  test(
    'package sync reports when the latest release is already adapted',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      final upstream = await createUpstreamPackageRepository(
        Directory('${environment.homeDirectory.path}/upstream_sync_current'),
      );
      await runGit(upstream, ['tag', 'v0.11.0']);
      final packageRepository = Directory(
        '${environment.homeDirectory.path}/package_sync_current',
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
          '--repository-name',
          'camera',
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
      stdout.clear();
      stderr.clear();

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

      final status = await runGit(packageRepository, ['status', '--porcelain']);
      expect(
        stdout,
        contains(
          'Package branch ohos/3.35/camera already adapts upstream 0.11.0 (v0.11.0)',
        ),
      );
      expect(status.stdout.toString(), isEmpty);
      expect(stderr, isEmpty);
    },
  );

  test('package sync accepts an explicit upstream version', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamPackageRepository(
      Directory('${environment.homeDirectory.path}/upstream_sync_version'),
      version: '0.10.0',
    );
    await runGit(upstream, ['tag', 'v0.10.0']);
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_sync_version',
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
        '--repository-name',
        'camera',
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
    await bumpUpstreamPackageVersion(upstream, version: '0.11.0');
    await runGit(upstream, ['tag', 'v0.11.0']);
    await bumpUpstreamPackageVersion(upstream, version: '0.12.0');
    await runGit(upstream, ['tag', 'v0.12.0']);

    final packageEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    expect(
      await runFluoh(
        ['package', 'sync', '--upstream-version', '0.11.0'],
        environment: packageEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final manifest = await readPackageManifest(packageRepository);
    final packagePubspec = File(
      '${packageRepository.path}/pubspec.yaml',
    ).readAsStringSync();
    expect(manifest.primaryPackage.upstreamVersion, '0.11.0');
    expect(manifest.primaryPackage.upstreamRef, 'v0.11.0');
    expect(packagePubspec, contains('version: 0.11.0'));
    expect(packagePubspec, isNot(contains('version: 0.12.0')));
    expect(stderr, isEmpty);
  });

  test('package sync refuses an explicit upstream downgrade', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamPackageRepository(
      Directory('${environment.homeDirectory.path}/upstream_sync_downgrade'),
      version: '0.10.0',
    );
    await runGit(upstream, ['tag', 'v0.10.0']);
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_sync_downgrade',
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
        '--repository-name',
        'camera',
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
    await bumpUpstreamPackageVersion(upstream, version: '0.11.0');
    await runGit(upstream, ['tag', 'v0.11.0']);

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
    stdout.clear();
    stderr.clear();

    expect(
      await runFluoh(
        ['package', 'sync', '--upstream-version', '0.10.0'],
        environment: packageEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );

    final manifest = await readPackageManifest(packageRepository);
    expect(manifest.primaryPackage.upstreamVersion, '0.11.0');
    expect(
      stderr.join('\n'),
      contains(
        'package sync does not downgrade camera upstream version 0.11.0 -> 0.10.0',
      ),
    );
    expect(
      stderr.join('\n'),
      contains('fluoh package version --status broken'),
    );
  });

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
        '--repository-name',
        'camera',
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
    expect(report, containsPair('schema', 1));
    expect(report, containsPair('command', 'package sync'));
    expect(report, containsPair('ok', true));
    expect(report, containsPair('exitCode', 0));
    expect(report, containsPair('status', 'synced'));
    expect(report, containsPair('committed', true));
    expect(report, containsPair('packageBranch', 'ohos/3.35/camera'));
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
          '--repository-name',
          'camera',
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
      await runGit(packageRepository, ['checkout', 'ohos/3.35/camera']);
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
      expect(branch.stdout.toString().trim(), 'ohos/3.35/camera');
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
          '--repository-name',
          'camera',
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
      expect(branch.stdout.toString().trim(), 'ohos/3.35/camera');
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
        '--repository-name',
        'camera',
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
        '--repository-name',
        'camera',
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
    await runGit(packageRepository, ['checkout', 'ohos/3.35/camera']);
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
      'ohos/3.35/camera',
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
        'ohos/3.35/camera.',
      ),
    );
    await runGit(packageRepository, ['merge', '--abort']);
  });
}
