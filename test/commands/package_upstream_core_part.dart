part of 'package_upstream_command_test.dart';

void _registerPackageUpstreamSyncCoreTests() {
  test(
    'package upstream sync fast-forwards upstream, merges the package branch, and refreshes upstream metadata',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      final upstream = await createUpstreamPackageRepository(
        Directory('${environment.homeDirectory.path}/upstream_sync'),
      );
      final packageRepository = Directory(
        '${environment.homeDirectory.path}/package_upstream',
      );
      final stdout = <String>[];
      final stderr = <String>[];

      await runFluoh(
        ['source', 'enable', 'fixture', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      await runFluoh(
        [
          'package',
          'port',
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
          ['package', 'upstream', 'sync'],
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
      final syncOutput = List<String>.from(stdout);
      stdout.clear();
      stderr.clear();
      expect(
        await runFluoh(
          ['package', 'next', '--package', 'camera', '--json'],
          environment: packageEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );
      final next = jsonDecode(stdout.single) as Map<String, Object?>;
      final nextAction = next['nextAction'] as Map<String, Object?>;
      expect(nextAction, containsPair('phase', 'spec-review'));
      final spec = next['spec'] as Map<String, Object?>;
      expect(spec, containsPair('reviewRequired', true));

      await runGit(packageRepository, ['checkout', 'main']);
      final upstreamPubspec = File(
        '${packageRepository.path}/pubspec.yaml',
      ).readAsStringSync();
      expect(upstreamPubspec, contains('version: 0.12.0'));
      expect(
        File('${packageRepository.path}/fluoh.yaml').existsSync(),
        isFalse,
      );
      expect(syncOutput, contains('Synchronized main from upstream/main'));
      expect(syncOutput, contains('Merged main into ohos/3.35/camera'));
      expect(
        syncOutput,
        contains('Updated upstream metadata for package branch'),
      );
      expect(stderr, isEmpty);
    },
  );

  test(
    'package upstream sync merges latest release tag instead of upstream HEAD',
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
        '${environment.homeDirectory.path}/package_upstream_tag',
      );
      final stdout = <String>[];
      final stderr = <String>[];

      await runFluoh(
        ['source', 'enable', 'fixture', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      await runFluoh(
        [
          'package',
          'port',
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
          ['package', 'upstream', 'sync'],
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

  test('package upstream check reports an available upstream target', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamPackageRepository(
      Directory('${environment.homeDirectory.path}/upstream_check'),
    );
    await runGit(upstream, ['tag', 'v0.11.0']);
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_upstream_check',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'enable', 'fixture', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    await runFluoh(
      [
        'package',
        'port',
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
    stdout.clear();
    stderr.clear();

    expect(
      await runFluoh(
        ['package', 'upstream', 'check', '--json'],
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
    expect(report, containsPair('command', 'package upstream check'));
    expect(report, containsPair('status', 'update_available'));
    expect(report, containsPair('targetUpstreamVersion', '0.12.0'));
    expect(report, containsPair('targetUpstreamRef', 'v0.12.0'));
    expect(report, containsPair('specReviewRequiredAfterSync', true));
    expect(stderr, isEmpty);
  });

  test(
    'package upstream sync reports when the latest release is already targeted',
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
        '${environment.homeDirectory.path}/package_upstream_current',
      );
      final stdout = <String>[];
      final stderr = <String>[];

      await runFluoh(
        ['source', 'enable', 'fixture', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      await runFluoh(
        [
          'package',
          'port',
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
          ['package', 'upstream', 'sync'],
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
          'Package branch ohos/3.35/camera already targets upstream 0.11.0 (v0.11.0)',
        ),
      );
      expect(status.stdout.toString(), isEmpty);
      expect(stderr, isEmpty);
    },
  );

  test('package upstream sync accepts an explicit upstream version', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamPackageRepository(
      Directory('${environment.homeDirectory.path}/upstream_sync_version'),
      version: '0.10.0',
    );
    await runGit(upstream, ['tag', 'v0.10.0']);
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_upstream_version',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'enable', 'fixture', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    await runFluoh(
      [
        'package',
        'port',
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
        ['package', 'upstream', 'sync', '--upstream-version', '0.11.0'],
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

  test('package upstream sync refuses an explicit upstream downgrade', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamPackageRepository(
      Directory('${environment.homeDirectory.path}/upstream_sync_downgrade'),
      version: '0.10.0',
    );
    await runGit(upstream, ['tag', 'v0.10.0']);
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_upstream_downgrade',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'enable', 'fixture', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    await runFluoh(
      [
        'package',
        'port',
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
        ['package', 'upstream', 'sync'],
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
        ['package', 'upstream', 'sync', '--upstream-version', '0.10.0'],
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
        'package upstream sync does not downgrade camera upstream version 0.11.0 -> 0.10.0',
      ),
    );
    expect(
      stderr.join('\n'),
      contains('fluoh package version --status broken'),
    );
  });

  test('package upstream sync can emit json results', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamPackageRepository(
      Directory('${environment.homeDirectory.path}/upstream_sync_json'),
    );
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_upstream_json',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'enable', 'fixture', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    await runFluoh(
      [
        'package',
        'port',
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
        ['package', 'upstream', 'sync', '--json'],
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
    expect(report, containsPair('command', 'package upstream sync'));
    expect(report, containsPair('ok', true));
    expect(report, containsPair('exitCode', 0));
    expect(report, containsPair('status', 'synced'));
    expect(report, containsPair('committed', true));
    expect(report, containsPair('packageBranch', 'ohos/3.35/camera'));
    expect(stderr, isEmpty);
  });

  test(
    'package upstream sync restores the starting branch when fast-forward fails',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      final upstream = await createUpstreamPackageRepository(
        Directory('${environment.homeDirectory.path}/upstream_sync_diverged'),
      );
      final packageRepository = Directory(
        '${environment.homeDirectory.path}/package_upstream_diverged',
      );
      final stdout = <String>[];
      final stderr = <String>[];

      await runFluoh(
        ['source', 'enable', 'fixture', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      await runFluoh(
        [
          'package',
          'port',
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
          ['package', 'upstream', 'sync'],
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
    'package upstream sync refuses dirty package branches before switching branches',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      final upstream = await createUpstreamPackageRepository(
        Directory('${environment.homeDirectory.path}/upstream_sync_dirty'),
      );
      final packageRepository = Directory(
        '${environment.homeDirectory.path}/package_upstream_dirty',
      );
      final stdout = <String>[];
      final stderr = <String>[];

      await runFluoh(
        ['source', 'enable', 'fixture', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      await runFluoh(
        [
          'package',
          'port',
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
          ['package', 'upstream', 'sync'],
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

  test(
    'package upstream sync continuation commands require an active merge',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      final upstream = await createUpstreamPackageRepository(
        Directory('${environment.homeDirectory.path}/upstream_sync_no_merge'),
      );
      final packageRepository = Directory(
        '${environment.homeDirectory.path}/package_upstream_no_merge',
      );
      final stdout = <String>[];
      final stderr = <String>[];

      await runFluoh(
        ['source', 'enable', 'fixture', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      await runFluoh(
        [
          'package',
          'port',
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
          ['package', 'upstream', 'sync', '--continue'],
          environment: packageEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        64,
      );
      expect(
        await runFluoh(
          ['package', 'upstream', 'sync', '--abort'],
          environment: packageEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        64,
      );
      expect(
        stderr.where(
          (message) =>
              message == 'No package upstream sync merge is in progress.',
        ),
        hasLength(2),
      );
    },
  );

  test(
    'package upstream sync abort validates the current package branch',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      final upstream = await createUpstreamPackageRepository(
        Directory(
          '${environment.homeDirectory.path}/upstream_sync_abort_branch',
        ),
      );
      final packageRepository = Directory(
        '${environment.homeDirectory.path}/package_upstream_abort_branch',
      );
      final stdout = <String>[];
      final stderr = <String>[];

      await runFluoh(
        ['source', 'enable', 'fixture', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      await runFluoh(
        [
          'package',
          'port',
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

      await runGit(packageRepository, [
        'checkout',
        '-b',
        'feature/manual-merge',
      ]);
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
          ['package', 'upstream', 'sync', '--abort'],
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
    },
  );
}
