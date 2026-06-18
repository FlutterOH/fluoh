part of 'package_upstream_command_test.dart';

void _registerPackageUpstreamSyncContinuationTests() {
  test('package upstream sync preserves package release metadata', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamPackageRepository(
      Directory('${environment.homeDirectory.path}/upstream_sync_metadata'),
    );
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_upstream_metadata',
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
        ['package', 'upstream', 'sync'],
        environment: packageEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final manifest = manifestFile.readAsStringSync();
    expect(manifest, contains('package:\n  name: camera'));
    expect(manifest, contains('    version: 0.2.0'));
    expect(manifest, isNot(contains('status: experimental')));
    expect(manifest, contains('    upstream:\n      version: 0.12.0'));
    expect(stderr, isEmpty);
  });

  test(
    'package upstream sync continues after resolved merge conflicts',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      final upstream = await createUpstreamPackageRepository(
        Directory('${environment.homeDirectory.path}/upstream_sync_conflict'),
      );
      final packageRepository = Directory(
        '${environment.homeDirectory.path}/package_upstream_conflict',
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
          ['package', 'upstream', 'sync'],
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
          ['package', 'upstream', 'sync', '--continue'],
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
      expect(manifest, contains('    upstream:\n      version: 0.12.0'));
      expect(subject.stdout.toString().trim(), 'Sync upstream package');
    },
  );

  test(
    'package upstream sync continue requires the interrupted non-tag upstream ref',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      final upstream = await createUpstreamPackageRepository(
        Directory('${environment.homeDirectory.path}/upstream_sync_custom_ref'),
      );
      final packageRepository = Directory(
        '${environment.homeDirectory.path}/package_upstream_custom_ref',
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

      await File(
        '${packageRepository.path}/README.md',
      ).writeAsString('# camera\n\nLocal OHOS notes.\n');
      await runGit(packageRepository, ['add', 'README.md']);
      await runGit(packageRepository, ['commit', '-m', 'Implement README']);
      await runGit(upstream, ['checkout', '-b', 'custom-target']);
      await File(
        '${upstream.path}/README.md',
      ).writeAsString('# camera\n\nCustom upstream notes.\n');
      await File('${upstream.path}/pubspec.yaml').writeAsString('''
name: camera
version: 0.12.0

environment:
  sdk: ^3.0.0
''');
      await runGit(upstream, ['add', 'README.md', 'pubspec.yaml']);
      await runGit(upstream, ['commit', '-m', 'Custom upstream target']);

      final packageEnvironment = FluohEnvironment(
        homeDirectory: environment.homeDirectory,
        workingDirectory: packageRepository,
      );
      expect(
        await runFluoh(
          [
            'package',
            'upstream',
            'sync',
            '--upstream-ref',
            'upstream/custom-target',
          ],
          environment: packageEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        64,
      );

      await File('${packageRepository.path}/README.md').writeAsString(
        '# camera\n\nLocal OHOS notes.\nCustom upstream notes.\n',
      );
      await runGit(packageRepository, ['add', 'README.md']);
      stdout.clear();
      stderr.clear();
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
        stderr.join('\n'),
        contains('Could not infer an upstream release tag for MERGE_HEAD.'),
      );

      stdout.clear();
      stderr.clear();
      expect(
        await runFluoh(
          [
            'package',
            'upstream',
            'sync',
            '--continue',
            '--upstream-ref',
            'upstream/custom-target',
          ],
          environment: packageEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final manifest = await readPackageManifest(packageRepository);
      final subject = await runGit(packageRepository, [
        'log',
        '-1',
        '--format=%s',
      ]);
      expect(manifest.primaryPackage.upstreamVersion, '0.12.0');
      expect(manifest.primaryPackage.upstreamRef, 'upstream/custom-target');
      expect(subject.stdout.toString().trim(), 'Sync upstream package');
      expect(stderr, isEmpty);
    },
  );

  test(
    'package upstream sync continue rejects mismatched resolved package version',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      final upstream = await createUpstreamPackageRepository(
        Directory(
          '${environment.homeDirectory.path}/upstream_sync_bad_continue',
        ),
      );
      final packageRepository = Directory(
        '${environment.homeDirectory.path}/package_upstream_bad_continue',
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
          ['package', 'upstream', 'sync'],
          environment: packageEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        64,
      );

      await File(
        '${packageRepository.path}/README.md',
      ).writeAsString('# camera\n\nLocal OHOS notes.\nUpstream notes.\n');
      await File('${packageRepository.path}/pubspec.yaml').writeAsString('''
name: camera
version: 0.11.0

environment:
  sdk: ^3.0.0
''');
      await runGit(packageRepository, ['add', 'README.md', 'pubspec.yaml']);
      stdout.clear();
      stderr.clear();

      expect(
        await runFluoh(
          ['package', 'upstream', 'sync', '--continue'],
          environment: packageEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        64,
      );

      final manifest = File(
        '${packageRepository.path}/fluoh.yaml',
      ).readAsStringSync();
      expect(manifest, contains('    upstream:\n      version: 0.11.0'));
      expect(
        stderr.join('\n'),
        contains(
          'Resolved package version 0.11.0 does not match selected upstream version 0.12.0',
        ),
      );
    },
  );

  test(
    'package upstream sync continue rejects an explicit ref that is not MERGE_HEAD',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      final upstream = await createUpstreamPackageRepository(
        Directory(
          '${environment.homeDirectory.path}/upstream_sync_wrong_continue_ref',
        ),
      );
      final packageRepository = Directory(
        '${environment.homeDirectory.path}/package_upstream_wrong_continue_ref',
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

      await File(
        '${packageRepository.path}/README.md',
      ).writeAsString('# camera\n\nLocal OHOS notes.\n');
      await runGit(packageRepository, ['add', 'README.md']);
      await runGit(packageRepository, ['commit', '-m', 'Implement README']);

      await runGit(upstream, ['checkout', '-b', 'custom-a']);
      await File(
        '${upstream.path}/README.md',
      ).writeAsString('# camera\n\nCustom A notes.\n');
      await File('${upstream.path}/pubspec.yaml').writeAsString('''
name: camera
version: 0.12.0

environment:
  sdk: ^3.0.0
''');
      await runGit(upstream, ['add', 'README.md', 'pubspec.yaml']);
      await runGit(upstream, ['commit', '-m', 'Custom upstream target A']);

      await runGit(upstream, ['checkout', 'main']);
      await runGit(upstream, ['checkout', '-b', 'custom-b']);
      await File(
        '${upstream.path}/README.md',
      ).writeAsString('# camera\n\nCustom B notes.\n');
      await File('${upstream.path}/pubspec.yaml').writeAsString('''
name: camera
version: 0.12.0

environment:
  sdk: ^3.0.0
''');
      await runGit(upstream, ['add', 'README.md', 'pubspec.yaml']);
      await runGit(upstream, ['commit', '-m', 'Custom upstream target B']);

      final packageEnvironment = FluohEnvironment(
        homeDirectory: environment.homeDirectory,
        workingDirectory: packageRepository,
      );
      expect(
        await runFluoh(
          [
            'package',
            'upstream',
            'sync',
            '--upstream-ref',
            'upstream/custom-a',
          ],
          environment: packageEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        64,
      );

      await File(
        '${packageRepository.path}/README.md',
      ).writeAsString('# camera\n\nLocal OHOS notes.\nCustom A notes.\n');
      await runGit(packageRepository, ['add', 'README.md']);
      stdout.clear();
      stderr.clear();

      expect(
        await runFluoh(
          [
            'package',
            'upstream',
            'sync',
            '--continue',
            '--upstream-ref',
            'upstream/custom-b',
          ],
          environment: packageEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        64,
      );

      var manifest = await readPackageManifest(packageRepository);
      expect(manifest.primaryPackage.upstreamVersion, '0.11.0');
      expect(manifest.primaryPackage.upstreamRef, isNull);
      expect(
        stderr.join('\n'),
        contains('Selected upstream target upstream/custom-b'),
      );
      expect(
        stderr.join('\n'),
        contains('does not match the in-progress merge'),
      );

      stdout.clear();
      stderr.clear();
      expect(
        await runFluoh(
          [
            'package',
            'upstream',
            'sync',
            '--continue',
            '--upstream-ref',
            'upstream/custom-a',
          ],
          environment: packageEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      manifest = await readPackageManifest(packageRepository);
      expect(manifest.primaryPackage.upstreamVersion, '0.12.0');
      expect(manifest.primaryPackage.upstreamRef, 'upstream/custom-a');
      expect(stderr, isEmpty);
    },
  );
}
