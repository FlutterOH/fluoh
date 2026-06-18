part of 'package_repository_command_test.dart';

void _registerPackageRepositoryCoreTests() {
  test('package new creates a spec-first FlutterOH repository', () async {
    final environment = await createTestEnvironment();
    final source = await _createPackageRepositorySdkSource(
      environment.homeDirectory,
      logName: 'package_new_flutter_args.log',
    );
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/sensors_ohos_repo',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'enable', 'fixture', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(
      await runFluoh(
        [
          'package',
          'new',
          'sensors_ohos',
          '--repository-name',
          'sensors_ohos_repo',
          '--output',
          packageRepository.path,
          '--sdk',
          '3.35.8-ohos-0.0.3',
          '--org',
          'dev.flutteroh',
          '--git-author-name',
          'FlutterOH Maintainer',
          '--git-author-email',
          'maintainer@example.com',
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
    final origin = await runGit(packageRepository, [
      'remote',
      'get-url',
      'origin',
    ]);
    expect(branch.stdout.toString().trim(), 'ohos/3.35/sensors_ohos');
    expect(
      origin.stdout.toString().trim(),
      'https://github.com/FlutterOH/sensors_ohos_repo.git',
    );
    final manifestContent = File(
      '${packageRepository.path}/fluoh.yaml',
    ).readAsStringSync();
    final manifest = await readPackageManifest(packageRepository);
    expect(manifest.isCreated, isTrue);
    expect(manifestContent, contains('origin:\n  kind: created'));
    expect(manifestContent, isNot(contains('\nupstream:')));
    expect(
      manifest.package.releaseTag(manifest.sdkVersion),
      'sensors_ohos-ohos-3.35-0.1.0',
    );
    expect(File('${packageRepository.path}/FLUOH.md').existsSync(), isTrue);
    final spec = File(
      '${packageRepository.path}/doc/fluoh/sensors_ohos/spec.md',
    );
    expect(spec.existsSync(), isTrue);
    final specContent = spec.readAsStringSync();
    expect(specContent, contains('Origin: `created`'));
    expect(specContent, contains('## Requirements Notes'));
    expect(specContent, isNot(contains('## Upstream Review Notes')));
    expect(specContent, isNot(contains('fluoh package upstream sync')));
    expect(
      File('${packageRepository.path}/FLUOH.md').readAsStringSync(),
      contains('Spec: `doc/fluoh/sensors_ohos/spec.md`'),
    );
    expect(
      Link('${packageRepository.path}/.fluoh/flutter_sdk').existsSync(),
      isTrue,
    );

    final staged = await runGit(packageRepository, [
      'diff',
      '--cached',
      '--name-only',
    ]);
    expect(staged.stdout.toString(), contains('FLUOH.md'));
    expect(
      staged.stdout.toString(),
      contains('doc/fluoh/sensors_ohos/spec.md'),
    );
    expect(staged.stdout.toString(), contains('fluoh.yaml'));
    expect(staged.stdout.toString(), contains('pubspec.yaml'));

    final mainReadme = await runGit(packageRepository, [
      'show',
      'main:README.md',
    ]);
    expect(mainReadme.stdout.toString(), contains('# sensors_ohos_repo'));
    final mainFiles = await runGit(packageRepository, [
      'ls-tree',
      '--name-only',
      'main',
    ]);
    expect(
      mainFiles.stdout.toString().split('\n'),
      isNot(contains('pubspec.yaml')),
    );

    final flutterArgs = File(
      '${environment.homeDirectory.path}/package_new_flutter_args.log',
    ).readAsStringSync();
    expect(flutterArgs, contains('--template=plugin'));
    expect(flutterArgs, contains('--platforms=ohos'));
    expect(flutterArgs, contains('--project-name sensors_ohos'));
    expect(flutterArgs, contains('--org dev.flutteroh'));
    expect(stderr.join('\n'), contains('flutter create stderr'));
    expect(
      _normalizeOutput(stdout.join('\n')),
      contains(
        _normalizeOutput(
          'Created FlutterOH package repository at ${packageRepository.path}',
        ),
      ),
    );
    stdout.clear();
    stderr.clear();
    expect(
      await runFluoh(
        ['package', 'upstream', 'check'],
        environment: FluohEnvironment(
          homeDirectory: environment.homeDirectory,
          workingDirectory: packageRepository,
        ),
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );
    expect(
      stderr.join('\n'),
      contains('package upstream is only available for ported packages.'),
    );
  });

  test('package new validates requested platforms', () async {
    final environment = await createTestEnvironment();
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        [
          'package',
          'new',
          'bad_platforms',
          '--sdk',
          '3.35.8-ohos-0.0.3',
          '--platforms',
          'ohos,android,bad',
          '--plan',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );
    expect(stdout, isEmpty);
    expect(stderr.join('\n'), contains('Unsupported --platforms value "bad"'));
    expect(stderr.join('\n'), contains('ohos, android, ios'));

    stdout.clear();
    stderr.clear();
    expect(
      await runFluoh(
        [
          'package',
          'new',
          'duplicate_platforms',
          '--sdk',
          '3.35.8-ohos-0.0.3',
          '--platforms',
          'ohos, android,ohos',
          '--plan',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );
    expect(stdout, isEmpty);
    expect(stderr.join('\n'), contains('Duplicate --platforms value "ohos"'));
  });

  test(
    'creates a package branch and release tag from an upstream repository',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      final upstream = await createUpstreamPackageRepository(
        Directory('${environment.homeDirectory.path}/upstream_camera'),
      );
      final packageRepository = Directory(
        '${environment.homeDirectory.path}/package_camera',
      );
      final stdout = <String>[];
      final stderr = <String>[];

      await runFluoh(
        ['source', 'enable', 'fixture', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );

      expect(
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
            '--git-author-name',
            'FlutterOH Maintainer',
            '--git-author-email',
            'maintainer@example.com',
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
      final origin = await runGit(packageRepository, [
        'remote',
        'get-url',
        'origin',
      ]);
      final upstreamRemote = await runGit(packageRepository, [
        'remote',
        'get-url',
        'upstream',
      ]);
      expect(branch.stdout.toString().trim(), 'ohos/3.35/camera');
      expect(
        origin.stdout.toString().trim(),
        'https://github.com/FlutterOH/camera.git',
      );
      expect(upstreamRemote.stdout.toString().trim(), upstream.path);
      final authorName = await runGit(packageRepository, [
        'config',
        '--local',
        '--get',
        'user.name',
      ]);
      final authorEmail = await runGit(packageRepository, [
        'config',
        '--local',
        '--get',
        'user.email',
      ]);
      expect(authorName.stdout.toString().trim(), 'FlutterOH Maintainer');
      expect(authorEmail.stdout.toString().trim(), 'maintainer@example.com');
      final manifestContent = File(
        '${packageRepository.path}/fluoh.yaml',
      ).readAsStringSync();
      final packageManifest = await readPackageManifest(packageRepository);
      expect(manifestContent, contains('schema: 1'));
      expect(manifestContent, contains('kind: package'));
      expect(manifestContent, contains('package:\n  name: camera'));
      expect(manifestContent, isNot(contains('implementation:')));
      expect(manifestContent, isNot(contains('dependency:')));
      expect(manifestContent, isNot(contains('dependencyPolicy:')));
      expect(manifestContent, isNot(contains('fluoh:')));
      expect(manifestContent, isNot(contains('flutteroh:')));
      expect(manifestContent, isNot(contains('replacement:')));
      expect(manifestContent, isNot(contains('ref:')));
      expect(manifestContent, isNot(contains('sdkVersion:')));
      expect(manifestContent, isNot(contains('tag:')));
      expect(packageManifest.name, 'camera');
      expect(packageManifest.sdkVersion, '3.35.8-ohos-0.0.3');
      expect(
        packageManifest.repositoryUrl,
        'https://github.com/FlutterOH/camera.git',
      );
      expect(packageManifest.repositoryBranch, 'ohos/3.35/camera');
      expect(packageManifest.upstreamUrl, upstream.path);
      expect(packageManifest.upstreamBranch, 'main');
      expect(packageManifest.primaryPackage.name, 'camera');
      expect(packageManifest.primaryPackage.version, '0.1.0');
      expect(packageManifest.primaryPackage.upstreamVersion, '0.11.0');
      expect(packageManifest.primaryPackage.status, 'experimental');
      final guide = File('${packageRepository.path}/FLUOH.md');
      expect(guide.existsSync(), isTrue);
      final guideContent = guide.readAsStringSync();
      _expectPackageContext(
        guideContent,
        packages: const [
          _ContextPackage(name: 'camera', version: '0.11.0', path: '.'),
        ],
      );
      final releaseNotesContent = guideContent;
      _expectChangelogEntry(
        releaseNotesContent,
        'camera-0.11.0-ohos-3.35-0.1.0',
      );
      expect(
        releaseNotesContent,
        contains('TODO: Replace this generated placeholder'),
      );
      expect(
        releaseNotesContent,
        isNot(contains('Initial FlutterOH implementation')),
      );
      final spec = File('${packageRepository.path}/doc/fluoh/camera/spec.md');
      expect(spec.existsSync(), isTrue);
      final specContent = spec.readAsStringSync();
      expect(specContent, contains('Origin: `ported`'));
      expect(specContent, contains('Upstream version: `0.11.0`'));
      expect(guideContent, contains('Spec: `doc/fluoh/camera/spec.md`'));
      expect(File('${packageRepository.path}/AGENTS.md').existsSync(), isFalse);
      final readme = File('${packageRepository.path}/README.md');
      expect(readme.existsSync(), isTrue);
      final readmeContent = readme.readAsStringSync();
      expect(readmeContent, '# camera\n');
      expect(File('${packageRepository.path}/CLAUDE.md').existsSync(), isFalse);
      expect(
        File('${packageRepository.path}/FLUOH_TODO.md').existsSync(),
        isFalse,
      );
      expect(
        File('${packageRepository.path}/FLUOH_SUPPORT.md').existsSync(),
        isFalse,
      );
      expect(File('${packageRepository.path}/.fvmrc').existsSync(), isFalse);
      expect(Directory('${packageRepository.path}/.fvm').existsSync(), isFalse);
      final ideLink = Link('${packageRepository.path}/.fluoh/flutter_sdk');
      expect(ideLink.existsSync(), isTrue);
      expect(
        ideLink.targetSync(),
        '${environment.homeDirectory.path}/sdks/3.35.8-ohos-0.0.3',
      );
      expect(
        File('${packageRepository.path}/.gitignore').readAsStringSync(),
        contains('.fluoh/'),
      );
      expect(
        File('${packageRepository.path}/.gitignore').readAsStringSync(),
        contains('flutter_*.log'),
      );
      final head = await runGit(packageRepository, ['rev-parse', 'HEAD']);
      final upstreamHead = await runGit(packageRepository, [
        'rev-parse',
        'upstream/main',
      ]);
      expect(
        head.stdout.toString().trim(),
        upstreamHead.stdout.toString().trim(),
      );
      final status = await runGit(packageRepository, ['status', '--porcelain']);
      expect(status.stdout.toString(), contains('A  FLUOH.md'));
      expect(status.stdout.toString(), contains('A  doc/fluoh/camera/spec.md'));
      expect(status.stdout.toString(), isNot(contains('AGENTS.md')));
      expect(status.stdout.toString(), isNot(contains('CLAUDE.md')));
      expect(status.stdout.toString(), isNot(contains('README.md')));
      expect(status.stdout.toString(), contains('A  .gitignore'));
      expect(status.stdout.toString(), contains('A  fluoh.yaml'));
      expect(status.stdout.toString(), isNot(contains('.fvm')));
      expect(status.stdout.toString(), isNot(contains('.fluoh')));
      final staged = await runGit(packageRepository, [
        'diff',
        '--cached',
        '--name-only',
      ]);
      expect(
        staged.stdout.toString().split('\n'),
        containsAll([
          'FLUOH.md',
          '.gitignore',
          'fluoh.yaml',
          'doc/fluoh/camera/spec.md',
        ]),
      );
      expect(staged.stdout.toString(), isNot(contains('AGENTS.md')));
      expect(staged.stdout.toString(), isNot(contains('CLAUDE.md')));
      expect(staged.stdout.toString(), isNot(contains('README.md')));
      expect(staged.stdout.toString(), isNot(contains('.fvm')));
      expect(staged.stdout.toString(), isNot(contains('.fluoh')));

      final releaseEnvironment = FluohEnvironment(
        homeDirectory: environment.homeDirectory,
        workingDirectory: packageRepository,
      );
      await commitGeneratedPackageRepository(packageRepository);
      final committedStatus = await runGit(packageRepository, [
        'status',
        '--porcelain',
      ]);
      expect(committedStatus.stdout.toString().trim(), isEmpty);
      expect(
        await runFluoh(
          ['package', 'release'],
          environment: releaseEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final tags = await runGit(packageRepository, ['tag', '--list']);
      expect(
        tags.stdout.toString().split('\n'),
        contains('camera-0.11.0-ohos-3.35-0.1.0'),
      );
      _expectWrappedContainsAll(stdout.join('\n'), [
        'Created package repository at ${packageRepository.path}',
        'Configured FlutterOH SDK 3.35.8-ohos-0.0.3',
        'Created release tag camera-0.11.0-ohos-3.35-0.1.0',
      ]);
      expect(
        stderr.join('\n'),
        contains('still contains TODO placeholder release notes'),
      );
    },
  );

  test('uses latest package release tag instead of monorepo HEAD', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamWorkspaceRepository(
      Directory('${environment.homeDirectory.path}/upstream_packages'),
      version: '0.10.0',
    );
    await runGit(upstream, ['tag', 'camera-v0.10.0']);
    await bumpUpstreamPackageVersion(
      upstream,
      packagePath: 'packages/camera/camera',
      version: '0.11.0',
    );
    await runGit(upstream, ['tag', 'camera-v0.11.0']);
    await bumpUpstreamPackageVersion(
      upstream,
      packagePath: 'packages/camera/camera',
      version: '0.12.0',
    );
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_camera_from_tag',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'enable', 'fixture', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );

    final exitCode = await runFluoh(
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
    if (exitCode != 0) {
      fail(
        'package port exited $exitCode\nstdout:\n${stdout.join('\n')}\n'
        'stderr:\n${stderr.join('\n')}',
      );
    }

    final manifestContent = File(
      '${packageRepository.path}/fluoh.yaml',
    ).readAsStringSync();
    final manifest = await readPackageManifest(packageRepository);
    final packagePubspec = File(
      '${packageRepository.path}/packages/camera/camera/pubspec.yaml',
    ).readAsStringSync();
    final head = await runGit(packageRepository, ['rev-parse', 'HEAD']);
    final releaseHead = await runGit(packageRepository, [
      'rev-parse',
      'camera-v0.11.0^{commit}',
    ]);
    final status = await runGit(packageRepository, ['status', '--porcelain']);

    expect(manifest.primaryPackage.upstreamVersion, '0.11.0');
    expect(manifest.primaryPackage.upstreamRef, 'camera-v0.11.0');
    expect(
      manifestContent,
      contains(
        '    upstream:\n'
        '      version: 0.11.0\n'
        '      ref: camera-v0.11.0',
      ),
    );
    expect(packagePubspec, contains('version: 0.11.0'));
    expect(packagePubspec, isNot(contains('version: 0.12.0')));
    expect(head.stdout.toString().trim(), releaseHead.stdout.toString().trim());
    expect(
      status.stdout.toString().split('\n'),
      isNot(contains(' M packages/camera/camera/pubspec.yaml')),
    );
    expect(stderr, isEmpty);
  });

  test('uses latest underscore package release tag', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamWorkspaceRepository(
      Directory('${environment.homeDirectory.path}/upstream_underscore_tag'),
      version: '0.10.0',
    );
    await runGit(upstream, ['tag', 'camera-v0.10.0']);
    await bumpUpstreamPackageVersion(
      upstream,
      packagePath: 'packages/camera/camera',
      version: '0.11.0',
    );
    await runGit(upstream, ['tag', 'camera-v0.11.0']);
    await bumpUpstreamPackageVersion(
      upstream,
      packagePath: 'packages/camera/camera',
      version: '0.12.0',
    );
    await runGit(upstream, ['tag', 'camera_v0.12.0']);
    await bumpUpstreamPackageVersion(
      upstream,
      packagePath: 'packages/camera/camera',
      version: '0.13.0',
    );
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_underscore_tag',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'enable', 'fixture', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(
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
      ),
      0,
    );

    final manifest = await readPackageManifest(packageRepository);
    final packagePubspec = File(
      '${packageRepository.path}/packages/camera/camera/pubspec.yaml',
    ).readAsStringSync();
    final head = await runGit(packageRepository, ['rev-parse', 'HEAD']);
    final releaseHead = await runGit(packageRepository, [
      'rev-parse',
      'camera_v0.12.0^{commit}',
    ]);

    expect(manifest.primaryPackage.upstreamVersion, '0.12.0');
    expect(manifest.primaryPackage.upstreamRef, 'camera_v0.12.0');
    expect(packagePubspec, contains('version: 0.12.0'));
    expect(packagePubspec, isNot(contains('version: 0.13.0')));
    expect(head.stdout.toString().trim(), releaseHead.stdout.toString().trim());
    expect(stderr, isEmpty);
  });

  test('uses explicit upstream package version for package port', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamWorkspaceRepository(
      Directory('${environment.homeDirectory.path}/upstream_explicit_version'),
      version: '0.10.0',
    );
    await runGit(upstream, ['tag', 'camera-v0.10.0']);
    await bumpUpstreamPackageVersion(
      upstream,
      packagePath: 'packages/camera/camera',
      version: '0.11.0',
    );
    await runGit(upstream, ['tag', 'camera-v0.11.0']);
    await bumpUpstreamPackageVersion(
      upstream,
      packagePath: 'packages/camera/camera',
      version: '0.12.0',
    );
    await Directory(
      '${upstream.path}/packages/camera/camera',
    ).delete(recursive: true);
    await runGit(upstream, ['add', '-A', 'packages/camera/camera']);
    await runGit(upstream, ['commit', '-m', 'Remove camera package']);
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_explicit_version',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'enable', 'fixture', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    expect(
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
          '--upstream-version',
          '0.10.0',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final manifest = await readPackageManifest(packageRepository);
    final packagePubspec = File(
      '${packageRepository.path}/packages/camera/camera/pubspec.yaml',
    ).readAsStringSync();
    final head = await runGit(packageRepository, ['rev-parse', 'HEAD']);
    final releaseHead = await runGit(packageRepository, [
      'rev-parse',
      'camera-v0.10.0^{commit}',
    ]);
    expect(manifest.primaryPackage.upstreamVersion, '0.10.0');
    expect(manifest.primaryPackage.upstreamRef, 'camera-v0.10.0');
    expect(packagePubspec, contains('version: 0.10.0'));
    expect(packagePubspec, isNot(contains('version: 0.12.0')));
    expect(head.stdout.toString().trim(), releaseHead.stdout.toString().trim());
    expect(stderr, isEmpty);
  });

  test('uses latest upstream package tag removed from main', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamWorkspaceRepository(
      Directory(
        '${environment.homeDirectory.path}/upstream_removed_latest_tag',
      ),
      version: '0.10.0',
    );
    await runGit(upstream, ['tag', 'camera-v0.10.0']);
    await bumpUpstreamPackageVersion(
      upstream,
      packagePath: 'packages/camera/camera',
      version: '0.11.0',
    );
    await runGit(upstream, ['tag', 'camera-v0.11.0']);
    await Directory(
      '${upstream.path}/packages/camera/camera',
    ).delete(recursive: true);
    await runGit(upstream, ['add', '-A', 'packages/camera/camera']);
    await runGit(upstream, ['commit', '-m', 'Remove camera package']);
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_removed_latest_tag',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'enable', 'fixture', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    expect(
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
      ),
      0,
    );

    final manifest = await readPackageManifest(packageRepository);
    final packagePubspec = File(
      '${packageRepository.path}/packages/camera/camera/pubspec.yaml',
    ).readAsStringSync();
    final head = await runGit(packageRepository, ['rev-parse', 'HEAD']);
    final releaseHead = await runGit(packageRepository, [
      'rev-parse',
      'camera-v0.11.0^{commit}',
    ]);
    expect(manifest.primaryPackage.upstreamVersion, '0.11.0');
    expect(manifest.primaryPackage.upstreamRef, 'camera-v0.11.0');
    expect(packagePubspec, contains('version: 0.11.0'));
    expect(head.stdout.toString().trim(), releaseHead.stdout.toString().trim());
    expect(stderr, isEmpty);
  });

  test('keeps ignored files from upstream release tags', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamWorkspaceRepository(
      Directory('${environment.homeDirectory.path}/upstream_ignored_tag_file'),
      version: '0.11.0',
    );
    await File(
      '${upstream.path}/packages/camera/camera/generated.txt',
    ).writeAsString('release generated file\n');
    await runGit(upstream, ['add', 'packages/camera/camera/generated.txt']);
    await runGit(upstream, ['commit', '-m', 'Add release generated file']);
    await runGit(upstream, ['tag', 'camera-v0.11.0']);
    await File('${upstream.path}/.gitignore').writeAsString('''
packages/camera/camera/generated.txt
''');
    await File(
      '${upstream.path}/packages/camera/camera/generated.txt',
    ).delete();
    await runGit(upstream, ['add', '-A']);
    await runGit(upstream, ['commit', '-m', 'Ignore generated package file']);
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_ignored_tag_file',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'enable', 'fixture', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(
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
      ),
      0,
    );

    final restored = File(
      '${packageRepository.path}/packages/camera/camera/generated.txt',
    );
    final tracked = await runGit(packageRepository, [
      'ls-files',
      'packages/camera/camera/generated.txt',
    ]);

    expect(restored.readAsStringSync(), 'release generated file\n');
    expect(
      tracked.stdout.toString().split('\n'),
      contains('packages/camera/camera/generated.txt'),
    );
    expect(stderr, isEmpty);
  });
}
