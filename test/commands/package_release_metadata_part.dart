part of 'package_release_command_test.dart';

void _registerPackageReleaseMetadataTests() {
  test(
    'release warns when FlutterOH release notes are still placeholders',
    () async {
      final environment = await createTestEnvironment();
      final packageRepository = await createPackageRepositoryFixture(
        environment,
      );
      final releaseEnvironment = FluohEnvironment(
        homeDirectory: environment.homeDirectory,
        workingDirectory: packageRepository,
      );
      final stdout = <String>[];
      final stderr = <String>[];

      await File('${packageRepository.path}/FLUOH.md').writeAsString('''
# FlutterOH Implementation

## FlutterOH Release History

### camera-0.11.0-ohos-3.35-0.1.0

- TODO: Replace this generated placeholder with actual release notes before release.
''');
      await runGit(packageRepository, ['add', 'FLUOH.md']);
      await runGit(packageRepository, [
        'commit',
        '-m',
        'Restore generated release note placeholder',
      ]);

      expect(
        await runFluoh(
          ['package', 'release'],
          environment: releaseEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );
      expect(
        stderr.join('\n'),
        contains('still contains TODO placeholder release notes'),
      );
      expect(
        stdout,
        contains('Created release tag camera-0.11.0-ohos-3.35-0.1.0'),
      );
    },
  );

  test('release warns when FlutterOH package license is missing', () async {
    final environment = await createTestEnvironment();
    final packageRepository = await createPackageRepositoryFixture(environment);
    final releaseEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await File('${packageRepository.path}/LICENSE').delete();
    await runGit(packageRepository, ['add', 'LICENSE']);
    await runGit(packageRepository, ['commit', '-m', 'Remove license']);

    expect(
      await runFluoh(
        ['package', 'release'],
        environment: releaseEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );
    expect(stderr.join('\n'), contains('Missing LICENSE for camera'));
    expect(
      stdout,
      contains('Created release tag camera-0.11.0-ohos-3.35-0.1.0'),
    );
  });

  test('release accepts release history entries under subsections', () async {
    final environment = await createTestEnvironment();
    final packageRepository = await createPackageRepositoryFixture(environment);
    final releaseEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await File('${packageRepository.path}/FLUOH.md').writeAsString('''
# FlutterOH Implementation

## FlutterOH Release History

### camera-0.11.0-ohos-3.35-0.1.0

#### Fixed

- Fix OHOS permission handling.
''');
    await runGit(packageRepository, ['add', 'FLUOH.md']);
    await runGit(packageRepository, [
      'commit',
      '-m',
      'Group release history entries',
    ]);

    expect(
      await runFluoh(
        ['package', 'release'],
        environment: releaseEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );
    expect(
      stdout,
      contains('Created release tag camera-0.11.0-ohos-3.35-0.1.0'),
    );
    expect(stderr, isEmpty);
  });

  test('release requires a version newer than previous release tags', () async {
    final environment = await createTestEnvironment();
    final packageRepository = await createPackageRepositoryFixture(environment);
    final releaseEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await runGit(packageRepository, ['tag', 'camera-0.11.0-ohos-3.35-0.2.0']);

    expect(
      await runFluoh(
        ['package', 'release'],
        environment: releaseEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );
    expect(
      stderr.join('\n'),
      contains('Release version 0.1.0 must be greater than latest release'),
    );
  });

  test('release rejects --all for package branch manifests', () async {
    final environment = await createTestEnvironment();
    final packageRepository = await createPackageRepositoryFixture(environment);
    final stdout = <String>[];
    final stderr = <String>[];
    final releaseEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );

    expect(
      await runFluoh(
        ['package', 'release', '--all'],
        environment: releaseEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );

    expect(stderr.join('\n'), contains('--all'));
    final tags = await runGit(packageRepository, ['tag', '--list']);
    expect(tags.stdout.toString(), isEmpty);
  });
}
