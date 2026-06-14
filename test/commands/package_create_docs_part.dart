part of 'package_create_command_test.dart';

void _registerPackageCreateDocsTests() {
  test('adds OHOS to an existing Flutter example', () async {
    final environment = await createTestEnvironment();
    final source = await _createPackageCreateSdkSource(
      environment.homeDirectory,
      logName: 'package_create_example_flutter_args.log',
    );
    final upstream = await _createUpstreamFlutterPluginRepository(
      Directory('${environment.homeDirectory.path}/upstream_flutter_camera'),
    );
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_flutter_camera',
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

    expect(
      Directory('${packageRepository.path}/example/ohos').existsSync(),
      isTrue,
    );
    expect(
      File('${packageRepository.path}/example/fluoh.yaml').existsSync(),
      isTrue,
    );
    final exampleGitignore = File(
      '${packageRepository.path}/example/.gitignore',
    ).readAsStringSync();
    expect(exampleGitignore, contains('# fluoh local state'));
    expect(exampleGitignore, contains('.fluoh/'));
    expect(exampleGitignore, contains('flutter_*.log'));
    expect(exampleGitignore, contains('# Flutter local files'));
    expect(exampleGitignore, contains('local.properties'));
    final staged = await runGit(packageRepository, [
      'diff',
      '--cached',
      '--name-only',
    ]);
    expect(staged.stdout.toString(), contains('example/ohos'));
    expect(staged.stdout.toString(), contains('example/fluoh.yaml'));
    expect(staged.stdout.toString(), contains('example/.gitignore'));

    final flutterLog = File(
      '${environment.homeDirectory.path}/package_create_example_flutter_args.log',
    ).readAsStringSync();
    expect(
      flutterLog,
      contains(
        '${packageRepository.path}/example::create --no-pub --platforms=ohos .',
      ),
    );
    expect(stdout, contains('Prepared example for camera at example'));
    expect(stderr, contains('flutter create stderr'));
  });

  test(
    'infers flutter create organization from existing example platforms',
    () async {
      final environment = await createTestEnvironment();
      final source = await _createPackageCreateSdkSource(
        environment.homeDirectory,
        logName: 'package_create_example_org_flutter_args.log',
        requiredCreateOrg: 'dev.flutter.plugins',
      );
      final upstream = await _createUpstreamFlutterPluginRepository(
        Directory('${environment.homeDirectory.path}/upstream_org_camera'),
      );
      await _addAmbiguousExampleOrganizations(upstream);
      final packageRepository = Directory(
        '${environment.homeDirectory.path}/package_org_camera',
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

      final flutterLog = File(
        '${environment.homeDirectory.path}/package_create_example_org_flutter_args.log',
      ).readAsStringSync();
      expect(
        flutterLog,
        contains(
          '${packageRepository.path}/example::create --no-pub --platforms=ohos --org dev.flutter.plugins .',
        ),
      );
      expect(
        stdout,
        contains('Using organization dev.flutter.plugins for OHOS platform'),
      );
      expect(stderr, contains('flutter create stderr'));
    },
  );

  test('resolves relative output from the fluoh working directory', () async {
    final environment = await createTestEnvironment();
    final source = await _createPackageCreateSdkSource(
      environment.homeDirectory,
      logName: 'package_create_relative_output_flutter_args.log',
    );
    final upstream = await _createUpstreamFlutterPluginRepository(
      Directory('${environment.homeDirectory.path}/upstream_relative_camera'),
    );
    final packagesRoot = Directory(
      '${environment.workingDirectory.parent.path}/packages',
    );
    await packagesRoot.create(recursive: true);
    final packageRepository = Directory(
      '${packagesRoot.path}/package_relative_camera',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'add', 'fixture', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );

    final process = await Process.run(
      Platform.resolvedExecutable,
      [
        '${Directory.current.path}/bin/fluoh.dart',
        'package',
        'create',
        upstream.path,
        '--repository-name',
        'camera',
        '--output',
        '../packages/package_relative_camera',
        '--sdk',
        '3.35.8-ohos-0.0.3',
      ],
      workingDirectory: environment.workingDirectory.path,
      environment: {
        ...Platform.environment,
        'FLUOH_HOME': environment.homeDirectory.path,
        ...environment.processEnvironment,
      },
    );

    expect(process.exitCode, 0, reason: '${process.stdout}\n${process.stderr}');

    expect(
      Directory('${packageRepository.path}/example/ohos').existsSync(),
      isTrue,
    );
    expect(Directory('${packagesRoot.path}/packages').existsSync(), isFalse);
    final flutterLog = File(
      '${environment.homeDirectory.path}/package_create_relative_output_flutter_args.log',
    ).readAsStringSync();
    expect(
      flutterLog,
      contains('/packages/package_relative_camera/example::create --no-pub'),
    );
    expect(
      _normalizeOutput(process.stdout.toString()),
      contains('/packages/package_relative_camera.'),
    );
    expect(
      process.stdout.toString(),
      isNot(contains('/packages/packages/package_relative_camera')),
    );
    expect(process.stdout.toString(), contains('flutter create stderr'));
  });

  test('warns when upstream license is missing', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamPackageRepository(
      Directory('${environment.homeDirectory.path}/upstream_without_license'),
      licenseContent: null,
    );
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_without_license',
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

    expect(stderr.join('\n'), contains('Missing LICENSE for camera'));
    expect(
      _normalizeOutput(stdout.join('\n')),
      contains(
        _normalizeOutput(
          'Created package repository at ${packageRepository.path}',
        ),
      ),
    );
  });

  test(
    'warns when upstream license disallows modified redistribution',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      final upstream = await createUpstreamPackageRepository(
        Directory('${environment.homeDirectory.path}/upstream_no_derivatives'),
        licenseContent: '''
Creative Commons Attribution-NoDerivatives 4.0 International

No derivative works are permitted.
''',
      );
      final packageRepository = Directory(
        '${environment.homeDirectory.path}/package_no_derivatives',
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

      expect(
        stderr.join('\n'),
        contains('LICENSE appears to disallow modified redistribution'),
      );
      expect(
        _normalizeOutput(stdout.join('\n')),
        contains(
          _normalizeOutput(
            'Created package repository at ${packageRepository.path}',
          ),
        ),
      );
    },
  );

  test('preserves existing upstream AGENTS.md instructions', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamPackageRepository(
      Directory('${environment.homeDirectory.path}/upstream_existing_agents'),
    );
    await File('${upstream.path}/AGENTS.md').writeAsString('''
# Upstream Agent Notes

Keep the public Dart API stable.
''');
    await File('${upstream.path}/CLAUDE.md').writeAsString('''
# Upstream Claude Notes

Prefer the upstream release workflow.
''');
    await File('${upstream.path}/README.md').writeAsString('''
# camera

Original upstream README body.
''');
    await runGit(upstream, ['add', 'AGENTS.md', 'CLAUDE.md', 'README.md']);
    await runGit(upstream, ['commit', '-m', 'Add upstream agent notes']);
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_existing_agents',
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

    final agentsContent = File(
      '${packageRepository.path}/AGENTS.md',
    ).readAsStringSync();
    expect(agentsContent, contains('# Upstream Agent Notes'));
    expect(agentsContent, contains('Keep the public Dart API stable.'));
    expect(agentsContent, contains('## FlutterOH/OHOS Adaptation'));
    expect(agentsContent, contains('follow `FLUOH.md`'));
    expect(agentsContent, contains('primary repository rules'));
    expect(agentsContent, contains('- Current package: `camera`.'));
    expect(agentsContent, isNot(contains('## Working Rules')));
    expect(agentsContent, isNot(contains('## Adaptation Workflow')));
    expect(agentsContent, isNot(contains('## Completion Report')));
    expect(agentsContent, isNot(contains('# AGENTS.md')));
    final claudeContent = File(
      '${packageRepository.path}/CLAUDE.md',
    ).readAsStringSync();
    expect(claudeContent, startsWith('@AGENTS.md\n\n# Upstream Claude Notes'));
    expect(claudeContent, contains('Prefer the upstream release workflow.'));
    final readmeContent = File(
      '${packageRepository.path}/README.md',
    ).readAsStringSync();
    expect(readmeContent, startsWith('<!-- fluoh:generated:start'));
    expect(readmeContent, contains('# camera'));
    _expectReadmeAdaptation(
      readmeContent,
      package: const _GuidancePackage(
        name: 'camera',
        version: '0.11.0',
        path: '.',
      ),
    );
    expect(readmeContent, contains('Original upstream README body.'));
    final status = await runGit(packageRepository, ['status', '--porcelain']);
    expect(status.stdout.toString(), contains('M  AGENTS.md'));
    expect(status.stdout.toString(), contains('M  CLAUDE.md'));
    expect(status.stdout.toString(), contains('M  README.md'));
    final mainAgents = await runGit(packageRepository, [
      'show',
      'main:AGENTS.md',
    ]);
    expect(
      mainAgents.stdout.toString(),
      '# Upstream Agent Notes\n\nKeep the public Dart API stable.\n',
    );
    final mainClaude = await runGit(packageRepository, [
      'show',
      'main:CLAUDE.md',
    ]);
    expect(
      mainClaude.stdout.toString(),
      '# Upstream Claude Notes\n\nPrefer the upstream release workflow.\n',
    );
    final mainReadme = await runGit(packageRepository, [
      'show',
      'main:README.md',
    ]);
    expect(
      mainReadme.stdout.toString(),
      '# camera\n\nOriginal upstream README body.\n',
    );
    expect(stderr, isEmpty);
  });

  test(
    'uses --package-path as a package path inside an upstream repository',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      final upstream = await createUpstreamWorkspaceRepository(
        Directory('${environment.homeDirectory.path}/upstream_workspace'),
      );
      final packageRepository = Directory(
        '${environment.homeDirectory.path}/package_workspace',
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

      final manifest = File(
        '${packageRepository.path}/fluoh.yaml',
      ).readAsStringSync();
      expect(manifest, contains('package:\n  name: camera'));
      expect(manifest, contains('path: packages/camera/camera'));
      expect(stderr, isEmpty);
    },
  );

  test('prints a read-only package create plan as JSON', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamPackageRepository(
      Directory('${environment.homeDirectory.path}/upstream_plan'),
    );
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_plan',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'add', 'fixture', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    stdout.clear();
    stderr.clear();

    final exitCode = await runFluoh(
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
        '--org',
        'dev.flutter.plugins',
        '--git-author-name',
        'FlutterOH Adapter',
        '--git-author-email',
        'adapter@example.com',
        '--plan',
        '--json',
      ],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    if (exitCode != 0) {
      fail(
        'package create plan exited $exitCode\nstdout:\n${stdout.join('\n')}\n'
        'stderr:\n${stderr.join('\n')}',
      );
    }

    expect(stderr, isEmpty);
    expect(stdout, hasLength(1));
    final payload = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(payload['schema'], 1);
    expect(payload['command'], 'package create');
    expect(payload['ok'], isTrue);
    expect(payload['exitCode'], 0);
    expect(payload['changed'], isFalse);
    expect(payload['applied'], isFalse);
    final plan = payload['plan'] as Map<String, Object?>;
    expect(plan['adaptationKind'], 'package');
    expect(plan['repository'], {
      'name': 'camera',
      'url': 'https://github.com/FlutterOH/camera.git',
      'outputPath': packageRepository.path,
      'branch': 'ohos/3.35/camera',
    });
    expect(plan['sdk'], {'version': '3.35.8-ohos-0.0.3', 'line': '3.35'});
    expect(plan['package'], {
      'name': 'camera',
      'path': '.',
      'upstreamVersion': '0.11.0',
      'releaseVersion': '0.1.0',
      'status': 'experimental',
    });
    expect(plan['gitAuthor'], {
      'name': 'FlutterOH Adapter',
      'email': 'adapter@example.com',
    });
    expect(plan['flutterCreateOrg'], 'dev.flutter.plugins');
    expect(
      plan['willNotRunWithoutSeparateApproval'],
      contains('git push --force'),
    );
    expect(packageRepository.existsSync(), isFalse);
  });

  test(
    'package create plan warns about newer default branch package version',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      final upstream = await createUpstreamWorkspaceRepository(
        Directory('${environment.homeDirectory.path}/upstream_unreleased_plan'),
        version: '0.11.0',
      );
      await runGit(upstream, ['tag', 'camera-v0.11.0']);
      await bumpUpstreamPackageVersion(
        upstream,
        packagePath: 'packages/camera/camera',
        version: '0.12.0',
      );
      final packageRepository = Directory(
        '${environment.homeDirectory.path}/package_unreleased_plan',
      );
      final stdout = <String>[];
      final stderr = <String>[];

      await runFluoh(
        ['source', 'add', 'fixture', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      stdout.clear();
      stderr.clear();

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
            '--output',
            packageRepository.path,
            '--sdk',
            '3.35.8-ohos-0.0.3',
            '--plan',
            '--json',
          ],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      expect(stderr, isEmpty);
      final payload = jsonDecode(stdout.single) as Map<String, Object?>;
      final plan = payload['plan'] as Map<String, Object?>;
      expect(plan['package'], {
        'name': 'camera',
        'path': 'packages/camera/camera',
        'upstreamVersion': '0.11.0',
        'releaseVersion': '0.1.0',
        'status': 'experimental',
      });
      final upstreamPlan = plan['upstream'] as Map<String, Object?>;
      expect(upstreamPlan['branch'], 'main');
      expect(upstreamPlan['selectedRef'], 'camera-v0.11.0');
      final warnings = (plan['warnings'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(warnings, hasLength(1));
      expect(
        warnings.single['code'],
        'package.default_branch_version_unreleased',
      );
      expect(warnings.single['severity'], 'warning');
      expect(warnings.single['package'], {
        'name': 'camera',
        'path': 'packages/camera/camera',
      });
      expect(warnings.single['selected'], {
        'ref': 'camera-v0.11.0',
        'version': '0.11.0',
      });
      expect(warnings.single['defaultBranch'], {
        'branch': 'main',
        'version': '0.12.0',
      });
      expect(warnings.single['policy'], {
        'defaultAction': 'adapt-selected-release-tag',
        'defaultBranchSnapshotRequiresApproval': true,
      });
      expect(
        warnings.single['nextStep'],
        contains(
          'Use --upstream-ref main only if maintainers explicitly approve',
        ),
      );
      expect(packageRepository.existsSync(), isFalse);
    },
  );

  test(
    'package create plan ignores unrelated broken tags in shallow mode',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      final upstream = await createUpstreamWorkspaceRepository(
        Directory('${environment.homeDirectory.path}/upstream_broken_tags'),
        version: '0.11.0',
      );
      await runGit(upstream, ['tag', 'camera-v0.11.0']);
      final tagsDirectory = Directory('${upstream.path}/.git/refs/tags');
      await tagsDirectory.create(recursive: true);
      await File(
        '${tagsDirectory.path}/unrelated-v999.0.0',
      ).writeAsString('1111111111111111111111111111111111111111\n');
      final packageRepository = Directory(
        '${environment.homeDirectory.path}/package_broken_tags_plan',
      );
      final stdout = <String>[];
      final stderr = <String>[];

      await runFluoh(
        ['source', 'add', 'fixture', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      stdout.clear();
      stderr.clear();

      final exitCode = await runFluoh(
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
          '--plan',
          '--json',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      if (exitCode != 0) {
        fail(
          'package create plan exited $exitCode\nstdout:\n${stdout.join('\n')}\n'
          'stderr:\n${stderr.join('\n')}',
        );
      }

      expect(stderr, isEmpty);
      final payload = jsonDecode(stdout.single) as Map<String, Object?>;
      final plan = payload['plan'] as Map<String, Object?>;
      final upstreamPlan = plan['upstream'] as Map<String, Object?>;
      expect(upstreamPlan['selectedRef'], 'camera-v0.11.0');
      expect(packageRepository.existsSync(), isFalse);
    },
  );

  test(
    'package create plan recommends federated implementation package',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      final upstream = await _createFederatedWorkspaceRepository(
        Directory('${environment.homeDirectory.path}/upstream_federated_plan'),
      );
      final packageRepository = Directory(
        '${environment.homeDirectory.path}/path_provider_plan',
      );
      final stdout = <String>[];
      final stderr = <String>[];

      await runFluoh(
        ['source', 'add', 'fixture', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      stdout.clear();
      stderr.clear();

      expect(
        await runFluoh(
          [
            'package',
            'create',
            upstream.path,
            '--repository-name',
            'path_provider',
            '--package-path',
            'packages/path_provider/path_provider',
            '--output',
            packageRepository.path,
            '--sdk',
            '3.35.8-ohos-0.0.3',
            '--plan',
            '--json',
          ],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      expect(stderr, isEmpty);
      final payload = jsonDecode(stdout.single) as Map<String, Object?>;
      final plan = payload['plan'] as Map<String, Object?>;
      expect(plan['package'], {
        'name': 'path_provider',
        'path': 'packages/path_provider/path_provider',
        'upstreamVersion': '2.1.0',
        'releaseVersion': '0.1.0',
        'status': 'experimental',
      });
      final recommendation =
          plan['implementationRecommendation'] as Map<String, Object?>;
      expect(recommendation['kind'], 'federated_platform_package');
      expect(
        recommendation['reason'],
        'federated_plugin_missing_platform_package',
      );
      expect(recommendation['platform'], 'ohos');
      expect(recommendation['sourceRoute'], {
        'packageName': 'path_provider',
        'packagePath': 'packages/path_provider/path_provider',
      });
      expect(recommendation['implementationPackageName'], 'path_provider_ohos');
      expect(
        recommendation['implementationPackagePath'],
        'packages/path_provider/path_provider_ohos',
      );
      expect(recommendation['implementationDependency'], {
        'package': 'path_provider_ohos',
        'path': '../path_provider_ohos',
      });
      expect(recommendation['existingDefaultPackages'], {
        'android': 'path_provider_android',
        'ios': 'path_provider_foundation',
      });
      final requiredEdits = recommendation['requiredEdits'] as List<Object?>;
      expect(
        requiredEdits,
        contains(containsPair('defaultPackage', 'path_provider_ohos')),
      );
      expect(
        requiredEdits,
        contains(containsPair('path', '../path_provider_ohos')),
      );
      expect(packageRepository.existsSync(), isFalse);
    },
  );

  test('package create writes federated implementation recommendation', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    final upstream = await _createFederatedWorkspaceRepository(
      Directory('${environment.homeDirectory.path}/upstream_federated_create'),
    );
    await runGit(upstream, ['tag', 'path_provider-v2.1.0']);
    await _writeFederatedPackage(
      upstream,
      path: 'packages/path_provider/path_provider',
      name: 'path_provider',
      version: '2.1.0',
      defaultPackages: const {
        'android': 'path_provider_android',
        'ios': 'path_provider_foundation',
        'ohos': 'path_provider_ohos',
      },
    );
    await runGit(upstream, ['add', '.']);
    await runGit(upstream, ['commit', '-m', 'Declare OHOS on default branch']);
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/path_provider_create',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'add', 'fixture', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    stdout.clear();
    stderr.clear();

    expect(
      await runFluoh(
        [
          'package',
          'create',
          upstream.path,
          '--repository-name',
          'path_provider',
          '--package-path',
          'packages/path_provider/path_provider',
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

    final output = stdout.join('\n');
    expect(output, contains('Create path_provider_ohos'));
    expect(output, contains('packages/path_provider/path_provider_ohos'));
    final guide = File('${packageRepository.path}/FLUOH.md').readAsStringSync();
    expect(guide, contains('## Federated Implementation Route'));
    expect(
      guide,
      contains(
        'Create the OHOS implementation package `path_provider_ohos` at '
        '`packages/path_provider/path_provider_ohos`',
      ),
    );
    expect(guide, contains('Add `ohos.default_package: path_provider_ohos`'));
    expect(
      guide,
      contains(
        'Add dependency `path_provider_ohos` with relative path `../path_provider_ohos`',
      ),
    );
    expect(guide, contains('## Platform Implementation Template'));
    expect(guide, contains('Federated packages: keep `path_provider`'));
    expect(guide, contains('postLaunchScreenshot'));
    expect(guide, contains('visualPageReadiness'));
    expect(guide, contains('post-launch screenshots or UI-state captures'));
    expect(stderr, isEmpty);
  });
}
