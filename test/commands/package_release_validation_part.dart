part of 'package_release_command_test.dart';

void _registerPackageReleaseValidationTests() {
  test('check certification can require OHOS run evidence', () async {
    final environment = await createTestEnvironment();
    final packageRepository = await createPackageRepositoryFixture(environment);
    final report = await _writeCertificationReport(packageRepository);
    final releaseEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        [
          'package',
          'check',
          '--json',
          '--report',
          report.path,
          '--require-ohos-run',
        ],
        environment: releaseEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );
    var result = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(
      result['error'],
      allOf(
        isA<Map<String, Object?>>(),
        containsPair('message', contains('fluoh run ohos')),
        containsPair('message', contains('evidence')),
      ),
    );

    stdout.clear();
    await _writeCertificationReport(packageRepository, includeOhosRun: true);
    expect(
      await runFluoh(
        [
          'package',
          'check',
          '--json',
          '--report',
          report.path,
          '--require-ohos-run',
        ],
        environment: releaseEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );
    result = jsonDecode(stdout.single) as Map<String, Object?>;
    final packages = result['packages'] as List<Object?>;
    final package = packages.single as Map<String, Object?>;
    final certification = package['certification'] as Map<String, Object?>;
    expect(certification, containsPair('required', true));
    expect(certification, containsPair('certified', true));
    expect(certification, containsPair('ok', true));
    expect(certification, containsPair('commandRows', 4));
    expect(certification, containsPair('passedCommandRows', 4));
    expect(certification, containsPair('automationCoverageRows', 10));
    expect(certification, containsPair('readyAutomationCoverageRows', 10));
    expect(certification, containsPair('interactionRows', 0));
    expect(certification, containsPair('passedInteractionRows', 0));
    expect(stderr, isEmpty);
  });

  test('check json reports validation failures as json', () async {
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
        ['package', 'check', '--json'],
        environment: releaseEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('passed', false));
    expect(report, containsPair('exitCode', 64));
    expect(report, containsPair('dryRun', true));
    expect(report, containsPair('tags', isEmpty));
    expect(
      report['error'],
      allOf(
        isA<Map<String, Object?>>(),
        containsPair('type', 'usage'),
        containsPair(
          'message',
          contains('must be greater than latest release version 0.2.0'),
        ),
      ),
    );
    expect(stderr, isEmpty);
  });

  test(
    'release fails for dirty pub worktrees and mismatched branches',
    () async {
      final environment = await createTestEnvironment();
      final packageRepository = await createPackageRepositoryFixture(
        environment,
      );
      final stdout = <String>[];
      final stderr = <String>[];

      await File(
        '${packageRepository.path}/README.md',
      ).writeAsString('# dirty\n');
      final dirtyEnvironment = FluohEnvironment(
        homeDirectory: environment.homeDirectory,
        workingDirectory: packageRepository,
      );
      expect(
        await runFluoh(
          ['package', 'release'],
          environment: dirtyEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        64,
      );
      expect(
        stderr.join('\n'),
        contains('Release requires a clean working tree'),
      );

      await runGit(packageRepository, ['checkout', '--', 'README.md']);
      await runGit(packageRepository, ['checkout', '-b', '3.34.0-ohos']);
      stderr.clear();
      expect(
        await runFluoh(
          ['package', 'release'],
          environment: dirtyEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        64,
      );
      expect(
        stderr.join('\n'),
        contains('does not match package branch ohos/3.35'),
      );
    },
  );

  test(
    'release validates SDK version and existing release tag commit',
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

      var manifest = File(
        '${packageRepository.path}/fluoh.yaml',
      ).readAsStringSync();
      await File('${packageRepository.path}/fluoh.yaml').writeAsString(
        manifest.replaceFirst(
          '  version: 3.35.8-ohos-0.0.3',
          '  version: 3.35.8-ohos-9.9.9',
        ),
      );
      await runGit(packageRepository, ['add', 'fluoh.yaml']);
      await runGit(packageRepository, [
        'commit',
        '-m',
        'Use invalid SDK version',
      ]);

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
        contains('was not found in configured sources'),
      );

      manifest = File(
        '${packageRepository.path}/fluoh.yaml',
      ).readAsStringSync();
      await File('${packageRepository.path}/fluoh.yaml').writeAsString(
        manifest.replaceFirst(
          '  version: 3.35.8-ohos-9.9.9',
          '  version: 3.35.8-ohos-0.0.3',
        ),
      );
      await runGit(packageRepository, ['add', 'fluoh.yaml']);
      await runGit(packageRepository, [
        'commit',
        '-m',
        'Restore valid SDK version',
      ]);
      await runGit(packageRepository, [
        'tag',
        'camera-0.11.0-ohos-3.35-0.1.0',
        'HEAD~1',
      ]);

      stderr.clear();
      expect(
        await runFluoh(
          ['package', 'release'],
          environment: releaseEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        64,
      );
      final error = stderr.join('\n');
      expect(error, contains('already exists on a different'));
      expect(error, contains('commit'));
    },
  );

  test('release warns when FlutterOH release notes are missing', () async {
    final environment = await createTestEnvironment();
    final packageRepository = await createPackageRepositoryFixture(environment);
    final releaseEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await File('${packageRepository.path}/FLUOH.md').delete();
    await runGit(packageRepository, ['add', 'FLUOH.md']);
    await runGit(packageRepository, ['commit', '-m', 'Remove release notes']);

    expect(
      await runFluoh(
        ['package', 'release'],
        environment: releaseEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );
    expect(stderr.join('\n'), contains('Missing FLUOH.md release history'));
    expect(
      stdout,
      contains('Created release tag camera-0.11.0-ohos-3.35-0.1.0'),
    );
  });

  test('release warns when FlutterOH release notes lack an entry', () async {
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

### 0.2.0

- Other release notes.
''');
    await runGit(packageRepository, ['add', 'FLUOH.md']);
    await runGit(packageRepository, ['commit', '-m', 'Change release notes']);

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
      contains('FLUOH.md FlutterOH Release History does not contain'),
    );
    expect(
      stdout,
      contains('Created release tag camera-0.11.0-ohos-3.35-0.1.0'),
    );
  });
}
