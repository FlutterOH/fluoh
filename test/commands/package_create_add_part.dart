part of 'package_create_command_test.dart';

void _registerPackageCreateAddTests() {
  test('rejects package create --json without --plan', () async {
    final environment = await createTestEnvironment();
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        [
          'package',
          'create',
          'https://github.com/example/camera.git',
          '--repository-name',
          'camera',
          '--json',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );

    expect(stderr, isEmpty);
    expect(stdout, hasLength(1));
    final payload = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(payload['command'], 'package create');
    expect(payload['ok'], isFalse);
    expect(payload['exitCode'], 64);
    expect(payload['error'], {
      'type': 'usage',
      'message': '--json is supported only with --plan for package create.',
    });
  });

  test('uses explicit name when the root package has siblings', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamPackageRepository(
      Directory('${environment.homeDirectory.path}/flutter-widgets-root'),
    );
    await _addWorkspacePackage(
      upstream,
      path: 'packages/share_plus/share_plus',
      name: 'share_plus',
      version: '9.0.0',
    );
    final packageRepository = Directory(
      '${environment.workingDirectory.path}/flutter-widgets-root',
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
          'package',
          'create',
          upstream.path,
          '--repository-name',
          'flutter-widgets-root',
          '--sdk',
          '3.35.8-ohos-0.0.3',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(packageRepository.existsSync(), isTrue);
    final manifest = File(
      '${packageRepository.path}/fluoh.yaml',
    ).readAsStringSync();
    expect(manifest, isNot(contains('\nname: flutter-widgets-root\n')));
    expect(
      manifest,
      contains('url: https://github.com/FlutterOH/flutter-widgets-root.git'),
    );
    expect(manifest, contains('package:\n  name: camera'));
    expect(manifest, isNot(contains('  share_plus:')));
    final guide = File('${packageRepository.path}/FLUOH.md').readAsStringSync();
    expect(guide, contains('fluoh verify'));
    expect(guide, contains('`fluoh package check`'));
    expect(guide, contains('`fluoh package release`'));
    expect(
      _normalizeOutput(stdout.join('\n')),
      contains(
        _normalizeOutput(
          'Created package repository at ${packageRepository.path}',
        ),
      ),
    );
    expect(stderr, isEmpty);
  });

  test(
    'uses explicit name as default output for a single monorepo package',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      final upstream = await createUpstreamWorkspaceRepository(
        Directory('${environment.homeDirectory.path}/flutter-widgets'),
        packagePath: 'packages/syncfusion_flutter_pdf',
        packageName: 'syncfusion_flutter_pdf',
      );
      final packageRepository = Directory(
        '${environment.workingDirectory.path}/syncfusion_flutter_pdf',
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
            'package',
            'create',
            upstream.path,
            '--repository-name',
            'syncfusion_flutter_pdf',
            '--package-path',
            'packages/syncfusion_flutter_pdf',
            '--sdk',
            '3.35.8-ohos-0.0.3',
          ],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      expect(packageRepository.existsSync(), isTrue);
      final manifest = File(
        '${packageRepository.path}/fluoh.yaml',
      ).readAsStringSync();
      final origin = await runGit(packageRepository, [
        'remote',
        'get-url',
        'origin',
      ]);
      expect(manifest, contains('name: syncfusion_flutter_pdf'));
      expect(
        manifest,
        contains(
          'url: https://github.com/FlutterOH/syncfusion_flutter_pdf.git',
        ),
      );
      expect(manifest, contains('package:\n  name: syncfusion_flutter_pdf'));
      expect(manifest, contains('path: packages/syncfusion_flutter_pdf'));
      expect(
        origin.stdout.toString().trim(),
        'https://github.com/FlutterOH/syncfusion_flutter_pdf.git',
      );
      expect(
        _normalizeOutput(stdout.join('\n')),
        contains(
          _normalizeOutput(
            'Created package repository at ${packageRepository.path}',
          ),
        ),
      );
      expect(
        stdout,
        contains(
          'Selected package syncfusion_flutter_pdf at '
          'packages/syncfusion_flutter_pdf',
        ),
      );
      expect(stderr, isEmpty);
    },
  );

  test(
    'requires name for a single monorepo package and suggests the path name',
    () async {
      final environment = await createTestEnvironment();
      final stdout = <String>[];
      final stderr = <String>[];

      expect(
        await runFluoh(
          [
            'package',
            'create',
            'https://github.com/flutter/packages.git',
            '--package-path',
            'packages/syncfusion_flutter_pdf',
          ],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        64,
      );

      expect(
        stderr.join('\n'),
        contains('Pass --repository-name <repository-name>'),
      );
      expect(
        stderr.join('\n'),
        contains('Suggested name: syncfusion_flutter_pdf'),
      );
      expect(stdout, isEmpty);
    },
  );

  test('rejects package create with multiple package paths', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamWorkspaceRepository(
      Directory('${environment.homeDirectory.path}/upstream_multi_package'),
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
      '${environment.homeDirectory.path}/package_multi_package',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'add', 'fixture', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );

    final createResult = await runFluoh(
      [
        'package',
        'create',
        upstream.path,
        '--repository-name',
        'camera',
        '--package-path',
        'packages/camera/camera',
        '--package-path',
        'packages/share_plus/share_plus',
        '--output',
        packageRepository.path,
        '--sdk',
        '3.35.8-ohos-0.0.3',
      ],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    expect(createResult, 64);
    expect(
      stderr.join('\n'),
      contains('package create creates one package branch'),
    );
    expect(packageRepository.existsSync(), isFalse);
  });

  test(
    'requires an explicit name for generic monorepo package collections',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      final upstream = await createUpstreamWorkspaceRepository(
        Directory('${environment.homeDirectory.path}/packages'),
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
        '${environment.workingDirectory.path}/packages',
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
            'package',
            'create',
            upstream.path,
            '--package-path',
            'packages/camera/camera',
            '--sdk',
            '3.35.8-ohos-0.0.3',
          ],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        64,
      );

      expect(
        stderr.join('\n'),
        contains('Pass --repository-name <repository-name>'),
      );
      expect(stderr.join('\n'), isNot(contains('Selected packages:')));
      expect(packageRepository.existsSync(), isFalse);
    },
  );

  test(
    'rejects explicit name for generic monorepo package collections',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      final upstream = await createUpstreamWorkspaceRepository(
        Directory('${environment.homeDirectory.path}/packages'),
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
        '${environment.workingDirectory.path}/flutter_packages',
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
            'package',
            'create',
            upstream.path,
            '--repository-name',
            'camera',
            '--package-path',
            'packages/camera/camera',
            '--package-path',
            'packages/share_plus/share_plus',
            '--repository-name',
            'flutter_packages',
            '--sdk',
            '3.35.8-ohos-0.0.3',
          ],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        64,
      );
      expect(
        stderr.join('\n'),
        contains('package create creates one package branch'),
      );
      expect(packageRepository.existsSync(), isFalse);
    },
  );

  test('adds another package by creating a package branch', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamWorkspaceRepository(
      Directory('${environment.homeDirectory.path}/upstream_add_package'),
      packagePath: 'packages/camera/camera',
      packageName: 'camera',
    );
    await _addWorkspacePackage(
      upstream,
      path: 'packages/share_plus/share_plus',
      name: 'share_plus',
      version: '9.0.0',
    );
    await runGit(upstream, ['tag', 'share_plus-v9.0.0']);
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_add_package',
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
        '--package-path',
        'packages/camera/camera',
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
    await bumpUpstreamPackageVersion(
      upstream,
      packagePath: 'packages/share_plus/share_plus',
      version: '9.1.0',
    );
    await runGit(upstream, ['tag', 'share_plus-v9.1.0']);
    await bumpUpstreamPackageVersion(
      upstream,
      packagePath: 'packages/share_plus/share_plus',
      version: '10.0.0',
    );

    final packageEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    expect(
      await runFluoh(
        ['package', 'add', 'packages/share_plus/share_plus'],
        environment: packageEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final manifest = File(
      '${packageRepository.path}/fluoh.yaml',
    ).readAsStringSync();
    final pubspec = File(
      '${packageRepository.path}/packages/share_plus/share_plus/pubspec.yaml',
    ).readAsStringSync();
    expect(manifest, contains('package:\n  name: share_plus'));
    expect(manifest, contains('path: packages/share_plus/share_plus'));
    expect(manifest, contains('      version: 9.1.0'));
    expect(manifest, contains('      ref: share_plus-v9.1.0'));
    expect(pubspec, contains('version: 9.1.0'));
    expect(pubspec, isNot(contains('version: 10.0.0')));
    const packages = [
      _GuidancePackage(
        name: 'share_plus',
        version: '9.1.0',
        path: 'packages/share_plus/share_plus',
      ),
    ];
    final guide = File('${packageRepository.path}/FLUOH.md').readAsStringSync();
    _expectImplementationGuide(guide, packages: packages);
    final agents = File(
      '${packageRepository.path}/AGENTS.md',
    ).readAsStringSync();
    _expectAgentsInstructions(agents, packages: packages);
    expect(agents, isNot(contains('Upstream branch at creation')));
    final readme = File(
      '${packageRepository.path}/README.md',
    ).readAsStringSync();
    _expectReadmeAdaptation(readme, package: packages.single);
    final changelog = File(
      '${packageRepository.path}/FLUOH_CHANGELOG.md',
    ).readAsStringSync();
    _expectChangelogEntry(changelog, 'share_plus-9.1.0-ohos-3.35-0.1.0');
    final status = await runGit(packageRepository, ['status', '--porcelain']);
    expect(status.stdout.toString(), contains('A  .gitignore'));
    expect(status.stdout.toString(), contains('A  fluoh.yaml'));
    expect(status.stdout.toString(), contains('A  AGENTS.md'));
    expect(status.stdout.toString(), contains('A  FLUOH.md'));
    expect(status.stdout.toString(), contains('A  FLUOH_CHANGELOG.md'));
    expect(status.stdout.toString(), contains('M  README.md'));
    expect(status.stdout.toString(), isNot(contains('.fluoh')));
    expect(
      File('${packageRepository.path}/.gitignore').readAsStringSync(),
      contains('.fluoh/'),
    );
    expect(
      stdout.join('\n'),
      contains('Created package branch ohos/3.35/share_plus'),
    );
    expect(stderr, isEmpty);
  });

  test('package add creates a clean package branch from upstream', () async {
    final environment = await createTestEnvironment();
    final source = await _createPackageCreateSdkSource(
      environment.homeDirectory,
      logName: 'package_add_rollback_flutter_args.log',
    );
    final upstream = await createUpstreamWorkspaceRepository(
      Directory('${environment.homeDirectory.path}/upstream_add_rollback'),
      packagePath: 'packages/camera/camera',
      packageName: 'camera',
    );
    await _addWorkspaceFlutterPackage(
      upstream,
      path: 'packages/share_plus/share_plus',
      name: 'share_plus',
      version: '9.0.0',
    );
    await runGit(upstream, ['tag', 'share_plus-v9.0.0']);
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_add_rollback',
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
        '--package-path',
        'packages/camera/camera',
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
        ['package', 'add', 'packages/share_plus/share_plus'],
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
    final example = Directory(
      '${packageRepository.path}/packages/share_plus/share_plus/example',
    );
    expect(branch.stdout.toString().trim(), 'ohos/3.35/share_plus');
    expect(Directory('${example.path}/ohos').existsSync(), isTrue);
    expect(File('${example.path}/fluoh.yaml').existsSync(), isTrue);
    final status = await runGit(packageRepository, ['status', '--porcelain']);
    expect(status.stdout.toString(), contains('A  fluoh.yaml'));
  });

  test('package add prints a read-only plan as JSON', () async {
    final environment = await createTestEnvironment();
    final source = await _createPackageCreateSdkSource(
      environment.homeDirectory,
      logName: 'package_add_plan_flutter_args.log',
    );
    final upstream = await createUpstreamWorkspaceRepository(
      Directory('${environment.homeDirectory.path}/upstream_add_plan'),
      packagePath: 'packages/camera/camera',
      packageName: 'camera',
    );
    await _addWorkspaceFlutterPackage(
      upstream,
      path: 'packages/share_plus/share_plus',
      name: 'share_plus',
      version: '9.0.0',
    );
    await runGit(upstream, ['tag', 'share_plus-v9.0.0']);
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_add_plan',
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
        '--package-path',
        'packages/camera/camera',
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
        [
          'package',
          'add',
          'packages/share_plus/share_plus',
          '--upstream-version',
          '9.0.0',
          '--org',
          'dev.flutter.plugins',
          '--plan',
          '--json',
        ],
        environment: packageEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(stderr, isEmpty);
    expect(stdout, hasLength(1));
    final payload = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(payload['command'], 'package add');
    expect(payload['ok'], isTrue);
    expect(payload['changed'], isFalse);
    expect(payload['applied'], isFalse);
    final plan = payload['plan'] as Map<String, Object?>;
    final repository = plan['repository'] as Map<String, Object?>;
    expect(repository['sourceBranch'], 'ohos/3.35/camera');
    expect(repository['newBranch'], 'ohos/3.35/share_plus');
    expect(repository['branchExists'], isFalse);
    expect(repository['workingTreeClean'], isTrue);
    expect(plan['sdk'], {'version': '3.35.8-ohos-0.0.3', 'line': '3.35'});
    expect(plan['package'], {
      'name': 'share_plus',
      'path': 'packages/share_plus/share_plus',
      'upstreamVersion': '9.0.0',
      'releaseVersion': '0.1.0',
      'status': 'experimental',
    });
    expect(
      plan['nextCommand'],
      'fluoh package add packages/share_plus/share_plus --upstream-version 9.0.0 --org dev.flutter.plugins',
    );
    final branch = await runGit(packageRepository, [
      'branch',
      '--show-current',
    ]);
    expect(branch.stdout.toString().trim(), 'ohos/3.35/camera');
    final status = await runGit(packageRepository, ['status', '--porcelain']);
    expect(status.stdout.toString().trim(), isEmpty);
  });

  test('package queue resolves multiple package add commands as JSON', () async {
    final environment = await createTestEnvironment();
    final source = await _createPackageCreateSdkSource(
      environment.homeDirectory,
      logName: 'package_queue_flutter_args.log',
    );
    final upstream = await createUpstreamWorkspaceRepository(
      Directory('${environment.homeDirectory.path}/upstream_queue'),
      packagePath: 'packages/camera/camera',
      packageName: 'camera',
    );
    await _addWorkspaceFlutterPackage(
      upstream,
      path: 'packages/share_plus/share_plus',
      name: 'share_plus',
      version: '9.0.0',
    );
    await _addWorkspaceFlutterPackage(
      upstream,
      path: 'packages/path_provider/path_provider',
      name: 'path_provider',
      version: '2.1.0',
    );
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_queue',
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
        '--package-path',
        'packages/camera/camera',
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
        [
          'package',
          'queue',
          'packages/share_plus/share_plus',
          'packages/path_provider/path_provider',
          '--org',
          'dev.flutter.plugins',
          '--json',
        ],
        environment: packageEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(stderr, isEmpty);
    final payload = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(payload['command'], 'package queue');
    expect(payload['changed'], isFalse);
    final queue = payload['queue'] as Map<String, Object?>;
    expect(queue['sdk'], {'version': '3.35.8-ohos-0.0.3', 'line': '3.35'});
    final packages = queue['packages'] as List<Object?>;
    expect(packages, hasLength(2));
    final sharePlus = packages.first as Map<String, Object?>;
    expect(sharePlus['name'], 'share_plus');
    expect(sharePlus['branch'], 'ohos/3.35/share_plus');
    expect(sharePlus['branchExists'], isFalse);
    expect(
      sharePlus['nextCommand'],
      'fluoh package add packages/share_plus/share_plus --org dev.flutter.plugins',
    );
    final pathProvider = packages.last as Map<String, Object?>;
    expect(pathProvider['name'], 'path_provider');
    expect(pathProvider['branch'], 'ohos/3.35/path_provider');
  });

  test('package add can use an explicit version removed from main', () async {
    final environment = await createTestEnvironment();
    final source = await _createPackageCreateSdkSource(
      environment.homeDirectory,
      logName: 'package_add_removed_flutter_args.log',
    );
    final upstream = await createUpstreamWorkspaceRepository(
      Directory('${environment.homeDirectory.path}/upstream_add_removed'),
      packagePath: 'packages/camera/camera',
      packageName: 'camera',
    );
    await _addWorkspaceFlutterPackage(
      upstream,
      path: 'packages/share_plus/share_plus',
      name: 'share_plus',
      version: '9.0.0',
    );
    await runGit(upstream, ['tag', 'share_plus-v9.0.0']);
    await Directory(
      '${upstream.path}/packages/share_plus/share_plus',
    ).delete(recursive: true);
    await runGit(upstream, ['add', '-A', 'packages/share_plus/share_plus']);
    await runGit(upstream, ['commit', '-m', 'Remove share_plus fixture']);
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_add_removed',
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
        '--package-path',
        'packages/camera/camera',
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
        [
          'package',
          'add',
          'packages/share_plus/share_plus',
          '--upstream-version',
          '9.0.0',
        ],
        environment: packageEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final manifest = File(
      '${packageRepository.path}/fluoh.yaml',
    ).readAsStringSync();
    final pubspec = File(
      '${packageRepository.path}/packages/share_plus/share_plus/pubspec.yaml',
    ).readAsStringSync();
    expect(manifest, contains('package:\n  name: share_plus'));
    expect(manifest, contains('      version: 9.0.0'));
    expect(manifest, contains('      ref: share_plus-v9.0.0'));
    expect(pubspec, contains('version: 9.0.0'));
  });

  test('package add uses latest package tag removed from main', () async {
    final environment = await createTestEnvironment();
    final source = await _createPackageCreateSdkSource(
      environment.homeDirectory,
      logName: 'package_add_removed_latest_flutter_args.log',
    );
    final upstream = await createUpstreamWorkspaceRepository(
      Directory(
        '${environment.homeDirectory.path}/upstream_add_removed_latest',
      ),
      packagePath: 'packages/camera/camera',
      packageName: 'camera',
    );
    await _addWorkspaceFlutterPackage(
      upstream,
      path: 'packages/share_plus/share_plus',
      name: 'share_plus',
      version: '9.0.0',
    );
    await runGit(upstream, ['tag', 'share_plus-v9.0.0']);
    await bumpUpstreamPackageVersion(
      upstream,
      packagePath: 'packages/share_plus/share_plus',
      version: '9.1.0',
    );
    await runGit(upstream, ['tag', 'share_plus-v9.1.0']);
    await Directory(
      '${upstream.path}/packages/share_plus/share_plus',
    ).delete(recursive: true);
    await runGit(upstream, ['add', '-A', 'packages/share_plus/share_plus']);
    await runGit(upstream, ['commit', '-m', 'Remove share_plus fixture']);
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_add_removed_latest',
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
        '--package-path',
        'packages/camera/camera',
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
        ['package', 'add', 'packages/share_plus/share_plus'],
        environment: packageEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final manifest = File(
      '${packageRepository.path}/fluoh.yaml',
    ).readAsStringSync();
    final pubspec = File(
      '${packageRepository.path}/packages/share_plus/share_plus/pubspec.yaml',
    ).readAsStringSync();
    expect(manifest, contains('package:\n  name: share_plus'));
    expect(manifest, contains('      version: 9.1.0'));
    expect(manifest, contains('      ref: share_plus-v9.1.0'));
    expect(pubspec, contains('version: 9.1.0'));
  });
}
