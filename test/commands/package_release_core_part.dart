part of 'package_release_command_test.dart';

void _registerPackageReleaseCoreTests() {
  test('release creates a tag', () async {
    final environment = await createTestEnvironment();
    final packageRepository = await createPackageRepositoryFixture(environment);
    final releaseEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    final stdout = <String>[];
    final stderr = <String>[];

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
    expect(
      stdout,
      contains('Created release tag camera-0.11.0-ohos-3.35-0.1.0'),
    );
    expect(
      stdout,
      contains(
        'No certification report provided; release will use baseline checks only.',
      ),
    );
    expect(stderr, isEmpty);
  });

  test('check validates without creating tags and can emit json', () async {
    final environment = await createTestEnvironment();
    final packageRepository = await createPackageRepositoryFixture(environment);
    final releaseEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['package', 'check', '--json'],
        environment: releaseEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final tags = await runGit(packageRepository, ['tag', '--list']);
    expect(
      tags.stdout.toString(),
      isNot(contains('camera-0.11.0-ohos-3.35-0.1.0')),
    );
    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('schema', 1));
    expect(report, containsPair('command', 'package check'));
    expect(report, containsPair('ok', true));
    expect(report, containsPair('exitCode', 0));
    expect(report, containsPair('passed', true));
    expect(report, containsPair('dryRun', true));
    expect(report, containsPair('tags', ['camera-0.11.0-ohos-3.35-0.1.0']));
    final packages = report['packages'] as List<Object?>;
    final package = packages.single as Map<String, Object?>;
    final verification = package['verification'] as Map<String, Object?>;
    final target = verification['target'] as Map<String, Object?>;
    expect(target, containsPair('kind', 'package'));
    expect(target, containsPair('name', 'camera'));
    expect(stderr, isEmpty);
  });

  test('check validates without creating tags and accepts a report', () async {
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
        ['package', 'check', '--json', '--report', report.path],
        environment: releaseEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final tags = await runGit(packageRepository, ['tag', '--list']);
    expect(
      tags.stdout.toString(),
      isNot(contains('camera-0.11.0-ohos-3.35-0.1.0')),
    );
    final result = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(result, containsPair('command', 'package check'));
    expect(result, containsPair('ok', true));
    expect(result, containsPair('dryRun', true));
    expect(result, containsPair('tags', ['camera-0.11.0-ohos-3.35-0.1.0']));
    final packages = result['packages'] as List<Object?>;
    final package = packages.single as Map<String, Object?>;
    final certification = package['certification'] as Map<String, Object?>;
    expect(certification, containsPair('required', true));
    expect(certification, containsPair('ok', true));
    expect(stderr, isEmpty);
  });

  test('check accepts integration test evidence without drive command', () async {
    final environment = await createTestEnvironment();
    final packageRepository = await createPackageRepositoryFixture(environment);
    final report = await _writeCertificationReport(
      packageRepository,
      includeOhosRun: true,
    );
    final content = await report.readAsString();
    await report.writeAsString(
      content
          .replaceFirst(
            '| `fluoh drive ohos --package camera --json` | 0 | passed | automation scenarios executed |\n',
            '| `flutter test integration_test -d emulator` | 0 | passed | integration_test exercised camera preview on OHOS emulator |\n',
          )
          .replaceFirst(
            'No interaction required: fixture package has no device-side interaction flow.',
            '''
| Scenario | Method | Platform | Target | Result | Evidence / blocker |
| --- | --- | --- | --- | --- | --- |
| camera preview | integration_test | OHOS | emulator | passed | flutter test integration_test -d emulator passed after fluoh run ohos prepared the target |
''',
          )
          .replaceFirst(
            '| OHOS | passed | passed | not required | emulator | build evidence recorded |',
            '| OHOS | passed | passed | passed | emulator | integration_test passed through flutter test integration_test |',
          ),
    );
    final releaseEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['package', 'check', '--json', '--report', report.path],
        environment: releaseEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final result = jsonDecode(stdout.single) as Map<String, Object?>;
    final packages = result['packages'] as List<Object?>;
    final package = packages.single as Map<String, Object?>;
    final certification = package['certification'] as Map<String, Object?>;
    expect(certification, containsPair('ok', true));
    expect(certification, containsPair('interactionRows', 1));
    expect(certification, containsPair('passedInteractionRows', 1));
    expect(stderr, isEmpty);
  });

  test('check rejects unbacked integration test evidence', () async {
    final environment = await createTestEnvironment();
    final packageRepository = await createPackageRepositoryFixture(environment);
    final report = await _writeCertificationReport(
      packageRepository,
      includeOhosRun: true,
    );
    final content = await report.readAsString();
    await report.writeAsString(
      content
          .replaceFirst(
            '| `fluoh drive ohos --package camera --json` | 0 | passed | automation scenarios executed |\n',
            '',
          )
          .replaceFirst(
            'No interaction required: fixture package has no device-side interaction flow.',
            '''
| Scenario | Method | Platform | Target | Result | Evidence / blocker |
| --- | --- | --- | --- | --- | --- |
| camera preview | integration_test | OHOS | emulator | passed | fluoh run ohos executed flutter test integration_test -d emulator |
''',
          )
          .replaceFirst(
            '| OHOS | passed | passed | not required | emulator | build evidence recorded |',
            '| OHOS | passed | passed | passed | emulator | claimed integration_test evidence from fluoh run only |',
          ),
    );
    final releaseEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['package', 'check', '--json', '--report', report.path],
        environment: releaseEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );

    final result = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(result, containsPair('ok', false));
    expect(
      result['error'],
      allOf(
        isA<Map<String, Object?>>(),
        containsPair(
          'message',
          contains('integration_test interaction evidence must cite'),
        ),
      ),
    );
    expect(stderr, isEmpty);
  });

  test(
    'check certification accepts manual-assisted tool evidence without drive',
    () async {
      final environment = await createTestEnvironment();
      final packageRepository = await createPackageRepositoryFixture(
        environment,
      );
      final report = await _writeCertificationReport(packageRepository);
      final content = await report.readAsString();
      await report.writeAsString(
        content
            .replaceFirst(
              '| `fluoh drive ohos --package camera --json` | 0 | passed | automation scenarios executed |',
              '| `dart test` | 0 | passed | package tests passed |',
            )
            .replaceFirst(
              'No interaction required: fixture package has no device-side interaction flow.',
              '''
| Scenario | Method | Platform | Target | Result | Evidence / blocker |
| --- | --- | --- | --- | --- | --- |
| camera preview | manual-assisted | OHOS | emulator | passed | flutterRunSession session file showed launched=true and hilog marker camera.previewReady |
''',
            ),
      );
      final releaseEnvironment = FluohEnvironment(
        homeDirectory: environment.homeDirectory,
        workingDirectory: packageRepository,
      );
      final stdout = <String>[];
      final stderr = <String>[];

      expect(
        await runFluoh(
          ['package', 'check', '--json', '--report', report.path],
          environment: releaseEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final result = jsonDecode(stdout.single) as Map<String, Object?>;
      expect(result, containsPair('ok', true));
      expect(stderr, isEmpty);
    },
  );

  test(
    'check certification rejects launch-only manual-assisted evidence',
    () async {
      final environment = await createTestEnvironment();
      final packageRepository = await createPackageRepositoryFixture(
        environment,
      );
      final report = await _writeCertificationReport(packageRepository);
      final content = await report.readAsString();
      await report.writeAsString(
        content
            .replaceFirst(
              '| `fluoh drive ohos --package camera --json` | 0 | passed | automation scenarios executed |',
              '| `dart test` | 0 | passed | package tests passed |',
            )
            .replaceFirst(
              'No interaction required: fixture package has no device-side interaction flow.',
              '''
| Scenario | Method | Platform | Target | Result | Evidence / blocker |
| --- | --- | --- | --- | --- | --- |
| camera preview | manual-assisted | OHOS | emulator | passed | fluoh run ohos launched the example |
''',
            ),
      );
      final releaseEnvironment = FluohEnvironment(
        homeDirectory: environment.homeDirectory,
        workingDirectory: packageRepository,
      );
      final stdout = <String>[];
      final stderr = <String>[];

      expect(
        await runFluoh(
          ['package', 'check', '--json', '--report', report.path],
          environment: releaseEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        64,
      );

      final result = jsonDecode(stdout.single) as Map<String, Object?>;
      expect(result, containsPair('ok', false));
      expect(
        result['error'],
        allOf(
          isA<Map<String, Object?>>(),
          containsPair(
            'message',
            contains(
              'manual-assisted interaction evidence must include tool-readable',
            ),
          ),
        ),
      );
      expect(stderr, isEmpty);
    },
  );

  test('check certification rejects launch-only session evidence', () async {
    final environment = await createTestEnvironment();
    final packageRepository = await createPackageRepositoryFixture(environment);
    final report = await _writeCertificationReport(packageRepository);
    final content = await report.readAsString();
    await report.writeAsString(
      content
          .replaceFirst(
            '| `fluoh drive ohos --package camera --json` | 0 | passed | automation scenarios executed |',
            '| `dart test` | 0 | passed | package tests passed |',
          )
          .replaceFirst(
            'No interaction required: fixture package has no device-side interaction flow.',
            '''
| Scenario | Method | Platform | Target | Result | Evidence / blocker |
| --- | --- | --- | --- | --- | --- |
| camera preview | manual-assisted | OHOS | emulator | passed | flutterRunSession session file showed launched=true |
''',
          ),
    );
    final releaseEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['package', 'check', '--json', '--report', report.path],
        environment: releaseEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );

    final result = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(result, containsPair('ok', false));
    expect(
      result['error'],
      allOf(
        isA<Map<String, Object?>>(),
        containsPair(
          'message',
          contains(
            'manual-assisted interaction evidence must include tool-readable',
          ),
        ),
      ),
    );
    expect(stderr, isEmpty);
  });

  test('check explains non-ready reports are handoff evidence', () async {
    final environment = await createTestEnvironment();
    final packageRepository = await createPackageRepositoryFixture(environment);
    final report = await _writeCertificationReport(
      packageRepository,
      recommendation: 'blocked',
    );
    final releaseEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['package', 'check', '--json', '--report', report.path],
        environment: releaseEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );

    final result = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(result, containsPair('command', 'package check'));
    expect(result, containsPair('ok', false));
    final error = result['error'] as Map<String, Object?>;
    expect(error['message'], contains('can be kept as handoff evidence'));
    expect(error['message'], contains('be used as release certification'));
    expect(stderr, isEmpty);
  });
}
