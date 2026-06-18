part of 'package_upstream_command_test.dart';

void _registerPackageUpstreamSyncDiagnosticTests() {
  test(
    'package upstream sync emits json diagnostics on fetch failure',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      final upstream = await createUpstreamPackageRepository(
        Directory('${environment.homeDirectory.path}/upstream_sync_fetch_json'),
      );
      final packageRepository = Directory(
        '${environment.homeDirectory.path}/package_upstream_fetch_json',
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
      final manifest = File('${packageRepository.path}/fluoh.yaml');
      await manifest.writeAsString(
        (await manifest.readAsString()).replaceFirst(
          upstream.path,
          '${environment.homeDirectory.path}/missing_upstream',
        ),
      );
      await runGit(packageRepository, ['add', 'fluoh.yaml']);
      await runGit(packageRepository, [
        'commit',
        '-m',
        'Point upstream to missing repository',
      ]);

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
        1,
      );

      final report = jsonDecode(stdout.single) as Map<String, Object?>;
      expect(report, containsPair('schema', 1));
      expect(report, containsPair('command', 'package upstream sync'));
      expect(report, containsPair('ok', false));
      expect(report, containsPair('exitCode', 1));
      expect(report, containsPair('status', 'fetch_failed'));
      final diagnostics = report['diagnostics'] as List<Object?>;
      final diagnostic = diagnostics.single as Map<String, Object?>;
      expect(diagnostic, containsPair('code', 'package.upstream.fetch_failed'));
      expect(
        diagnostic,
        containsPair('nextCommand', 'fluoh package upstream sync --json'),
      );
      expect(diagnostic['stderrTail'], isNotNull);
      expect(stderr, isEmpty);
    },
  );

  test(
    'package upstream sync emits json diagnostics on merge conflict',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      final upstream = await createUpstreamPackageRepository(
        Directory(
          '${environment.homeDirectory.path}/upstream_sync_conflict_json',
        ),
      );
      final packageRepository = Directory(
        '${environment.homeDirectory.path}/package_upstream_conflict_json',
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

      // Create divergent changes on both local and upstream.
      await File(
        '${packageRepository.path}/README.md',
      ).writeAsString('# camera\n\nLocal OHOS notes.\n');
      await runGit(packageRepository, ['add', 'README.md']);
      await runGit(packageRepository, ['commit', '-m', 'Local README']);
      await File(
        '${upstream.path}/README.md',
      ).writeAsString('# camera\n\nUpstream notes.\n');
      await runGit(upstream, ['add', 'README.md']);
      await runGit(upstream, ['commit', '-m', 'Upstream README']);

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
        1,
      );

      final report = jsonDecode(stdout.last) as Map<String, Object?>;
      expect(report, containsPair('schema', 1));
      expect(report, containsPair('command', 'package upstream sync'));
      expect(report, containsPair('ok', false));
      expect(report, containsPair('exitCode', 1));
      expect(report, containsPair('status', 'merge_conflict'));
      final diagnostics = report['diagnostics'] as List<Object?>;
      expect(diagnostics, hasLength(1));
      final diagnostic = diagnostics.first as Map<String, Object?>;
      expect(
        diagnostic,
        containsPair('code', 'package.upstream.merge_conflict'),
      );
      expect(
        diagnostic,
        containsPair('nextCommand', 'fluoh package upstream sync --continue'),
      );
      final conflictedFiles = diagnostic['conflictedFiles'] as List<Object?>;
      expect(conflictedFiles, contains('README.md'));
      expect(stderr, isEmpty);

      // Clean up the merge state.
      await runGit(packageRepository, ['merge', '--abort']);
    },
  );

  test(
    'package upstream sync emits json diagnostics on non-conflict merge failure',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      final upstream = await createUpstreamPackageRepository(
        Directory(
          '${environment.homeDirectory.path}/upstream_sync_merge_failed_json',
        ),
      );
      final packageRepository = Directory(
        '${environment.homeDirectory.path}/package_upstream_merge_failed_json',
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
      await runGit(packageRepository, ['checkout', '--orphan', 'orphan-sync']);
      await runGit(packageRepository, ['add', '.']);
      await runGit(packageRepository, [
        'commit',
        '-m',
        'Create unrelated package branch',
      ]);
      await runGit(packageRepository, ['branch', '-M', 'ohos/3.35/camera']);

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
        1,
      );

      final report = jsonDecode(stdout.single) as Map<String, Object?>;
      expect(report, containsPair('schema', 1));
      expect(report, containsPair('command', 'package upstream sync'));
      expect(report, containsPair('ok', false));
      expect(report, containsPair('exitCode', 1));
      expect(report, containsPair('status', 'merge_failed'));
      final diagnostics = report['diagnostics'] as List<Object?>;
      final diagnostic = diagnostics.single as Map<String, Object?>;
      expect(diagnostic, containsPair('code', 'package.upstream.merge_failed'));
      expect(
        diagnostic,
        containsPair('nextCommand', 'fluoh package upstream sync --json'),
      );
      expect(
        diagnostic['stderrTail'].toString(),
        contains('refusing to merge unrelated histories'),
      );
      expect(stderr, isEmpty);
    },
  );

  test(
    'package upstream sync preserves the manifest package path while updating metadata',
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
        '${environment.homeDirectory.path}/package_upstream_paths',
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
          '--package-path',
          'packages/camera/camera',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );

      final manifestFile = File('${packageRepository.path}/fluoh.yaml');
      await commitGeneratedPackageRepository(
        packageRepository,
        message: 'Commit package path fixture',
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
          ['package', 'upstream', 'sync'],
          environment: packageEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final manifest = manifestFile.readAsStringSync();
      expect(manifest, contains('    upstream:\n      version: 0.12.0'));
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

  test('package upstream sync keeps root package path omitted', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamPackageRepository(
      Directory('${environment.homeDirectory.path}/upstream_sync_root_path'),
    );
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_upstream_root_path',
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
    await commitGeneratedPackageRepository(
      packageRepository,
      message: 'Commit root package fixture',
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
    expect(manifest, contains('    upstream:\n      version: 0.12.0'));
    expect(RegExp(r'^\s+path:', multiLine: true).allMatches(manifest), isEmpty);
    expect(stderr, isEmpty);
  });

  test(
    'package upstream sync fails when package path points at another package',
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
        '${environment.homeDirectory.path}/package_upstream_wrong_path',
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
          '  path: packages/camera/camera',
          '  path: packages/share_plus/share_plus',
        ),
      );
      await commitGeneratedPackageRepository(
        packageRepository,
        message: 'Point camera package path at share_plus',
      );

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
        contains(
          'Package path packages/share_plus/share_plus contains share_plus, '
          'expected camera.',
        ),
      );
    },
  );
}
