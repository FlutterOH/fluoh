part of 'package_create_command_test.dart';

void _registerPackageCreateCoreSelectionTests() {
  test(
    'rejects per-package release tags from different monorepo commits',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      final upstream = await createUpstreamWorkspaceRepository(
        Directory(
          '${environment.homeDirectory.path}/upstream_per_package_tags',
        ),
        version: '0.11.0',
      );
      await runGit(upstream, ['tag', 'camera-v0.11.0']);
      await _addWorkspacePackage(
        upstream,
        path: 'packages/share_plus/share_plus',
        name: 'share_plus',
        version: '9.0.0',
      );
      await runGit(upstream, ['tag', 'share_plus-v9.0.0']);
      await bumpUpstreamPackageVersion(
        upstream,
        packagePath: 'packages/camera/camera',
        version: '0.12.0',
      );
      final packageRepository = Directory(
        '${environment.homeDirectory.path}/package_per_package_tags',
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
            '--package-path',
            'packages/camera/camera',
            '--package-path',
            'packages/share_plus/share_plus',
          ],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        64,
      );

      final error = stderr.join('\n');
      expect(error, contains('package create creates one package branch'));
      expect(error, contains('fluoh package add <package-path>'));
      expect(packageRepository.existsSync(), isFalse);
    },
  );

  test('warns when latest upstream tag needs a newer Dart SDK', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamWorkspaceRepository(
      Directory('${environment.homeDirectory.path}/upstream_packages_sdk'),
      version: '0.11.4',
      sdkConstraint: '>=3.0.0 <4.0.0',
    );
    await runGit(upstream, ['tag', 'camera-v0.11.4']);
    await bumpUpstreamPackageVersion(
      upstream,
      packagePath: 'packages/camera/camera',
      version: '0.12.0+1',
      sdkConstraint: '>=3.10.0 <4.0.0',
    );
    await runGit(upstream, ['tag', 'camera-v0.12.0+1']);
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_camera_sdk_warning',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'add', 'fixture', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );

    final exitCode = await runFluoh(
      [
        'package',
        'create',
        upstream.absolute.uri.toString(),
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
        'package create exited $exitCode\nstdout:\n${stdout.join('\n')}\n'
        'stderr:\n${stderr.join('\n')}',
      );
    }

    final manifest = await readPackageManifest(packageRepository);
    final output = stdout.join('\n');

    expect(manifest.primaryPackage.upstreamVersion, '0.12.0+1');
    expect(manifest.primaryPackage.upstreamRef, 'camera-v0.12.0+1');
    expect(
      output,
      contains(
        'requires Dart >=3.10.0 <4.0.0, but the selected FlutterOH SDK '
        'provides Dart 3.9.2',
      ),
    );
    expect(
      output,
      contains(
        'Keep adapting the selected upstream target camera-v0.12.0+1. '
        'Adapt the package pubspec, example config, and Dart code to the '
        'selected FlutterOH SDK Dart 3.9.2',
      ),
    );
    expect(
      output,
      contains(
        'must not be used unless maintainers explicitly approve an older baseline',
      ),
    );
    expect(stderr, isEmpty);

    stdout.clear();
    stderr.clear();
    final planRepository = Directory(
      '${environment.homeDirectory.path}/package_camera_sdk_warning_plan',
    );
    final planExitCode = await runFluoh(
      [
        'package',
        'create',
        upstream.path,
        '--repository-name',
        'camera',
        '--output',
        planRepository.path,
        '--sdk',
        '3.35.8-ohos-0.0.3',
        '--package-path',
        'packages/camera/camera',
        '--plan',
        '--json',
      ],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    if (planExitCode != 0) {
      fail(
        'package create plan exited $planExitCode\n'
        'stdout:\n${stdout.join('\n')}\nstderr:\n${stderr.join('\n')}',
      );
    }

    final payload = jsonDecode(stdout.single) as Map<String, Object?>;
    final plan = payload['plan'] as Map<String, Object?>;
    final warnings = (plan['warnings'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(warnings, hasLength(1));
    expect(warnings.single['code'], 'package.dart_sdk_incompatible');
    expect(warnings.single['severity'], 'warning');
    expect(warnings.single['package'], {
      'name': 'camera',
      'path': 'packages/camera/camera',
    });
    expect(warnings.single['selected'], {
      'ref': 'camera-v0.12.0+1',
      'version': '0.12.0+1',
      'dartConstraint': '>=3.10.0 <4.0.0',
    });
    expect(warnings.single['sdk'], {'dartVersion': '3.9.2'});
    expect(warnings.single['policy'], {
      'defaultAction': 'adapt-selected-upstream-to-selected-sdk',
      'keepSelectedUpstream': true,
      'adjustPackageForSelectedSdk': true,
      'suggestedEnvironmentSdkConstraint': '>=3.9.0 <4.0.0',
      'olderBaselineRequiresApproval': true,
      'sdkUpgradeOptional': true,
    });
    expect(warnings.single['latestCompatible'], {
      'ref': 'camera-v0.11.4',
      'version': '0.11.4',
    });
  });

  test('prints clone once and separates output sections', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamPackageRepository(
      Directory('${environment.homeDirectory.path}/upstream_video_player'),
      packageName: 'video_player',
    );
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_video_player',
    );
    final stdout = <String>[];
    final stderr = <String>[];
    final transient = <String>[];

    await runFluoh(
      ['source', 'add', 'fixture', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    stdout.clear();

    final output = TerminalOutput(
      stdout: stdout.add,
      stderr: stderr.add,
      transient: transient.add,
      style: const TerminalStyle(
        capabilities: TerminalCapabilities(
          ansi: false,
          decorated: true,
          unicode: true,
        ),
      ),
    );
    final runner = CommandRunner<int>('fluoh', 'test')
      ..addCommand(
        PackageCommand(
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
          output: output,
        ),
      );

    expect(
      await runner.run([
        'package',
        'create',
        upstream.path,
        '--repository-name',
        'camera',
        '--output',
        packageRepository.path,
        '--sdk',
        '3.35.8-ohos-0.0.3',
      ]),
      0,
    );

    final cloneMessage =
        'Cloning upstream repository into ${packageRepository.path}...';
    expect(
      _normalizeOutput(stdout.join('\n')).split(_normalizeOutput(cloneMessage)),
      hasLength(2),
    );
    expect(transient.join(), isNot(contains(cloneMessage)));
    expect(transient.join(), isNot(contains('Receiving objects')));
    final cloneIndex = stdout.indexWhere(
      (line) => line.contains('Cloning upstream repository into '),
    );
    final firstBlank = stdout.indexWhere(
      (line) => line.isEmpty,
      cloneIndex + 1,
    );
    expect(firstBlank, greaterThanOrEqualTo(0));
    final sdkMessageIndex = stdout.indexWhere(
      (line) =>
          line.contains('Using installed FlutterOH SDK') ||
          line.contains('FlutterOH SDK path:'),
    );
    expect(sdkMessageIndex, greaterThan(firstBlank));
    final sdkLinkIndex = stdout.indexWhere(
      (line) => line.contains('IDE Flutter SDK link:'),
    );
    expect(sdkLinkIndex, greaterThanOrEqualTo(0));
    expect(stdout[sdkLinkIndex + 1], isNot(isEmpty));
    final blankAfterSdkLink = stdout.indexWhere(
      (line) => line.isEmpty,
      sdkLinkIndex + 1,
    );
    expect(blankAfterSdkLink, greaterThan(sdkLinkIndex));
    final exampleSkipIndex = stdout.indexWhere(
      (line) => line.contains('Skipping example OHOS setup for video_player:'),
    );
    expect(exampleSkipIndex, greaterThan(blankAfterSdkLink));
    final summaryIndex = stdout.indexWhere(
      (line) => line.contains('Package branch:'),
    );
    expect(summaryIndex, greaterThan(exampleSkipIndex));
    expect(stderr, isEmpty);
  });

  test(
    'stages generated files even when upstream ignore rules match them',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      final upstream = await createUpstreamPackageRepository(
        Directory('${environment.homeDirectory.path}/upstream_ignored_outputs'),
      );
      await File('${upstream.path}/.gitignore').writeAsString('''
AGENTS.md
CLAUDE.md
FLUOH.md
FLUOH_CHANGELOG.md
fluoh.yaml
''');
      await runGit(upstream, ['add', '.gitignore']);
      await runGit(upstream, ['commit', '-m', 'Ignore local fluoh outputs']);
      final packageRepository = Directory(
        '${environment.homeDirectory.path}/package_ignored_outputs',
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

      final staged = await runGit(packageRepository, [
        'diff',
        '--cached',
        '--name-only',
      ]);
      expect(
        staged.stdout.toString().split('\n'),
        containsAll([
          'AGENTS.md',
          'CLAUDE.md',
          'FLUOH.md',
          'FLUOH_CHANGELOG.md',
          'README.md',
          '.gitignore',
          'fluoh.yaml',
        ]),
      );
      expect(staged.stdout.toString(), isNot(contains('.fluoh')));
      expect(stderr, isEmpty);
    },
  );
}
