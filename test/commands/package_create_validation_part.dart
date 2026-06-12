part of 'package_create_command_test.dart';

void _registerPackageCreateValidationTests() {
  test('package add points existing package branches to sync', () async {
    final environment = await createTestEnvironment();
    final source = await _createPackageCreateSdkSource(
      environment.homeDirectory,
      logName: 'package_add_existing_branch_flutter_args.log',
    );
    final upstream = await createUpstreamWorkspaceRepository(
      Directory('${environment.homeDirectory.path}/upstream_add_existing'),
      packagePath: 'packages/camera/camera',
      packageName: 'camera',
    );
    await _addWorkspaceFlutterPackage(
      upstream,
      path: 'packages/share_plus/share_plus',
      name: 'share_plus',
      version: '9.0.0',
    );
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_add_existing',
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
      reason: [...stderr, ...stdout].join('\n'),
    );
    await commitGeneratedPackageRepository(packageRepository);
    stdout.clear();
    stderr.clear();

    expect(
      await runFluoh(
        ['package', 'add', 'packages/share_plus/share_plus'],
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
    expect(branch.stdout.toString().trim(), 'ohos/3.35/share_plus');
    expect(
      stderr.join('\n'),
      contains('Package branch ohos/3.35/share_plus already exists.'),
    );
    expect(stderr.join('\n'), contains('package status --package share_plus'));
    expect(stderr.join('\n'), contains('fluoh package sync'));
  });

  test('package add and queue detect remote-only package branches', () async {
    final environment = await createTestEnvironment();
    final source = await _createPackageCreateSdkSource(
      environment.homeDirectory,
      logName: 'package_add_remote_existing_branch_flutter_args.log',
    );
    final upstream = await createUpstreamWorkspaceRepository(
      Directory('${environment.homeDirectory.path}/upstream_add_remote'),
      packagePath: 'packages/camera/camera',
      packageName: 'camera',
    );
    await _addWorkspaceFlutterPackage(
      upstream,
      path: 'packages/share_plus/share_plus',
      name: 'share_plus',
      version: '9.0.0',
    );
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_add_remote_origin',
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
    await runFluoh(
      ['package', 'add', 'packages/share_plus/share_plus'],
      environment: packageEnvironment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    await commitGeneratedPackageRepository(packageRepository);

    final clonedRepository = Directory(
      '${environment.homeDirectory.path}/package_add_remote_clone',
    );
    await runGit(environment.homeDirectory, [
      'clone',
      '--branch',
      'ohos/3.35/camera',
      packageRepository.path,
      clonedRepository.path,
    ]);
    final clonedEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: clonedRepository,
    );
    stdout.clear();
    stderr.clear();

    expect(
      await runFluoh(
        ['package', 'queue', 'packages/share_plus/share_plus', '--json'],
        environment: clonedEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
      reason: stderr.join('\n'),
    );

    expect(stderr, isEmpty);
    final queuePayload = jsonDecode(stdout.single) as Map<String, Object?>;
    final queue = queuePayload['queue'] as Map<String, Object?>;
    final packages = queue['packages'] as List<Object?>;
    final sharePlus = packages.single as Map<String, Object?>;
    expect(sharePlus['branch'], 'ohos/3.35/share_plus');
    expect(sharePlus['branchExists'], isTrue);
    expect(
      sharePlus['nextCommand'],
      'git checkout ohos/3.35/share_plus && fluoh package status --package share_plus',
    );
    final remotesAfterQueue = await runGit(clonedRepository, ['remote']);
    expect(remotesAfterQueue.stdout.toString().trim(), 'origin');
    stdout.clear();
    stderr.clear();

    expect(
      await runFluoh(
        [
          'package',
          'add',
          'packages/share_plus/share_plus',
          '--plan',
          '--json',
        ],
        environment: clonedEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(stderr, isEmpty);
    final addPayload = jsonDecode(stdout.single) as Map<String, Object?>;
    final plan = addPayload['plan'] as Map<String, Object?>;
    final repository = plan['repository'] as Map<String, Object?>;
    expect(repository['branchExists'], isTrue);
    expect(
      plan['nextCommand'],
      'git checkout ohos/3.35/share_plus && fluoh package status --package share_plus',
    );
    final willRun = (plan['willRun'] as List<Object?>).join('\n');
    expect(willRun, contains('checkout existing package branch'));
    expect(willRun, contains('inspect package status for share_plus'));
    expect(willRun, isNot(contains('write README.md')));
    expect(willRun, isNot(contains('stage generated files')));
    final remotesAfterPlan = await runGit(clonedRepository, ['remote']);
    expect(remotesAfterPlan.stdout.toString().trim(), 'origin');
    stdout.clear();
    stderr.clear();

    expect(
      await runFluoh(
        ['package', 'add', 'packages/share_plus/share_plus'],
        environment: clonedEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );

    final branch = await runGit(clonedRepository, ['branch', '--show-current']);
    expect(branch.stdout.toString().trim(), 'ohos/3.35/camera');
    expect(
      stderr.join('\n'),
      contains('Package branch ohos/3.35/share_plus already exists.'),
    );
    expect(stderr.join('\n'), contains('package status --package share_plus'));
  });

  test('package add restores the starting branch when setup fails', () async {
    final environment = await createTestEnvironment();
    final source = await _createPackageCreateSdkSource(
      environment.homeDirectory,
      logName: 'package_add_failure_flutter_args.log',
    );
    final upstream = await createUpstreamWorkspaceRepository(
      Directory('${environment.homeDirectory.path}/upstream_add_failure'),
      packagePath: 'packages/camera/camera',
      packageName: 'camera',
    );
    await _addWorkspaceFlutterPackage(
      upstream,
      path: 'packages/share_plus/share_plus',
      name: 'share_plus',
      version: '9.0.0',
    );
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_add_failure',
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
    final flutter = File(
      '${environment.homeDirectory.path}/sdks/3.35.8-ohos-0.0.3/bin/flutter',
    );
    await flutter.writeAsString('''
#!/bin/sh
exit 1
''');
    await _runProcess('chmod', ['+x', flutter.path], flutter.parent);

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
      64,
    );

    final branch = await runGit(packageRepository, [
      'branch',
      '--show-current',
    ]);
    final addedBranch = await runGit(packageRepository, [
      'branch',
      '--list',
      'ohos/3.35/share_plus',
    ]);
    final status = await runGit(packageRepository, ['status', '--porcelain']);
    final manifest = File(
      '${packageRepository.path}/fluoh.yaml',
    ).readAsStringSync();
    expect(branch.stdout.toString().trim(), 'ohos/3.35/camera');
    expect(addedBranch.stdout.toString().trim(), isEmpty);
    expect(status.stdout.toString().trim(), isEmpty);
    expect(manifest, contains('package:\n  name: camera'));
    expect(manifest, isNot(contains('name: share_plus')));
    expect(stderr.join('\n'), contains('flutter create failed'));
  });

  test('requires a selected package for nested package upstreams', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamWorkspaceRepository(
      Directory(
        '${environment.homeDirectory.path}/upstream_unselected_workspace',
      ),
    );
    await runGit(upstream, ['tag', 'camera-v0.11.0']);
    final example = Directory(
      '${upstream.path}/packages/camera/camera/example',
    );
    await example.create(recursive: true);
    await File('${example.path}/pubspec.yaml').writeAsString('''
name: camera_example
version: 1.0.0

environment:
  sdk: ^3.0.0
''');
    await runGit(upstream, ['add', 'packages/camera/camera/example']);
    await runGit(upstream, ['commit', '-m', 'Add camera example']);
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_unselected_workspace',
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
          '--output',
          packageRepository.path,
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
      _normalizeOutput(stderr.join('\n')),
      contains('For packages below the root, select package paths'),
    );
    expect(stderr.join('\n'), contains('--package-path <package-path>'));
    expect(stderr.join('\n'), contains('Candidate packages:'));
    expect(
      stderr.join('\n'),
      contains(
        'camera 0.11.0 at packages/camera/camera (Dart ^3.0.0)'
        ' [latest tag camera-v0.11.0]: --package-path '
        'packages/camera/camera --repository-name camera',
      ),
    );
    expect(stderr.join('\n'), isNot(contains('camera_example')));
    expect(packageRepository.existsSync(), isFalse);
  });

  test(
    'uses an explicit package repository URL when provided with --repository',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      final upstream = await createUpstreamPackageRepository(
        Directory('${environment.homeDirectory.path}/upstream_custom_remote'),
      );
      final packageRepository = Directory(
        '${environment.homeDirectory.path}/package_custom_remote',
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
            '--output',
            packageRepository.path,
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

      final origin = await runGit(packageRepository, [
        'remote',
        'get-url',
        'origin',
      ]);
      final manifest = File(
        '${packageRepository.path}/fluoh.yaml',
      ).readAsStringSync();
      expect(
        origin.stdout.toString().trim(),
        'git@github.com:FlutterOH/camera.git',
      );
      expect(manifest, contains('url: git@github.com:FlutterOH/camera.git'));
      expect(stderr, isEmpty);
    },
  );

  test('accepts -r for explicit package repository URLs', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamPackageRepository(
      Directory('${environment.homeDirectory.path}/upstream_repo_aliases'),
    );
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_repo_alias_short',
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
          '--output',
          packageRepository.path,
          '--sdk',
          '3.35.8-ohos-0.0.3',
          '-r',
          'git@github.com:FlutterOH/camera-short.git',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final origin = await runGit(packageRepository, [
      'remote',
      'get-url',
      'origin',
    ]);
    expect(
      origin.stdout.toString().trim(),
      'git@github.com:FlutterOH/camera-short.git',
    );
    expect(stderr, isEmpty);
  });

  test(
    'package create leaves upstream default branch tree unchanged',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      final upstream = await createUpstreamPackageRepository(
        Directory('${environment.homeDirectory.path}/upstream_clean_main'),
      );
      final packageRepository = Directory(
        '${environment.homeDirectory.path}/package_clean_main',
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
            '--output',
            packageRepository.path,
            '--sdk',
            '3.35.8-ohos-0.0.3',
          ],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final mainFiles = await runGit(packageRepository, [
        'ls-tree',
        '-r',
        '--name-only',
        'main',
      ]);
      expect(mainFiles.stdout.toString(), isNot(contains('fluoh.yaml')));
      expect(mainFiles.stdout.toString(), isNot(contains('FLUOH.md')));
      expect(
        mainFiles.stdout.toString(),
        isNot(contains('FLUOH_CHANGELOG.md')),
      );
      expect(mainFiles.stdout.toString(), isNot(contains('AGENTS.md')));
      expect(stderr, isEmpty);
    },
  );

  test('selects the latest stable SDK when --sdk is omitted', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    final sdkRepository = Directory(
      '${environment.homeDirectory.path}/flutter-ohos-sdk',
    );
    await runGit(sdkRepository, ['tag', '3.35.8-ohos-0.0.4']);
    await writeSdkSourceFixture(
      source,
      sdkRepository: sdkRepository.path,
      releases: {'3.35.8-ohos-0.0.3': 'stable', '3.35.8-ohos-0.0.4': 'stable'},
    );
    final upstream = await createUpstreamPackageRepository(
      Directory('${environment.homeDirectory.path}/upstream_default_sdk'),
    );
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_default_sdk',
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
          '--output',
          packageRepository.path,
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final branch = await runGit(packageRepository, [
      'branch',
      '--show-current',
    ]);
    final manifest = File(
      '${packageRepository.path}/fluoh.yaml',
    ).readAsStringSync();
    expect(branch.stdout.toString().trim(), 'ohos/3.35/camera');
    expect(manifest, contains('sdk:\n  version: 3.35.8-ohos-0.0.4'));
    expect(stderr, isEmpty);
  });

  test('fails before cloning when destination already exists', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamPackageRepository(
      Directory('${environment.homeDirectory.path}/upstream_existing_dest'),
    );
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_existing_dest',
    );
    await packageRepository.create(recursive: true);
    await File('${packageRepository.path}/README.md').writeAsString('existing');
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
          '--output',
          packageRepository.path,
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
      File('${packageRepository.path}/README.md').readAsStringSync(),
      'existing',
    );
    expect(stderr.join('\n'), contains('Destination already exists'));
  });

  test('requires Git author name and email together', () async {
    final environment = await createTestEnvironment();
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_missing_author_email',
    );
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
          '--output',
          packageRepository.path,
          '--git-author-name',
          'FlutterOH Adapter',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );

    expect(
      stderr.join('\n'),
      contains('Pass both --git-author-name and --git-author-email'),
    );
    expect(packageRepository.existsSync(), isFalse);
  });

  test(
    'requires package repository name to be a name instead of a path',
    () async {
      final environment = await createTestEnvironment();
      final packageRepository = Directory(
        '${environment.homeDirectory.path}/package_invalid_name',
      );
      final stdout = <String>[];
      final stderr = <String>[];

      expect(
        await runFluoh(
          [
            'package',
            'create',
            'https://github.com/example/packages.git',
            '--repository-name',
            '../camera',
            '--output',
            packageRepository.path,
          ],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        64,
      );

      expect(
        stderr.join('\n'),
        contains('--repository-name must be a repository name'),
      );
      expect(packageRepository.existsSync(), isFalse);
    },
  );

  test('does not accept --package for package create', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamPackageRepository(
      Directory('${environment.homeDirectory.path}/upstream_package_option'),
    );
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_option',
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
          '--package',
          'share_plus',
          '--output',
          packageRepository.path,
          '--sdk',
          '3.35.8-ohos-0.0.3',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );

    expect(stderr.join('\n'), contains('Could not find an option named'));
    expect(Directory('${packageRepository.path}/.git').existsSync(), isFalse);
  });
}
