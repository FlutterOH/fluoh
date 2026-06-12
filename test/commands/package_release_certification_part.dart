part of 'package_release_command_test.dart';

void _registerPackageReleaseCertificationTests() {
  test('check accepts a certification report', () async {
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

    final result = jsonDecode(stdout.single) as Map<String, Object?>;
    final packages = result['packages'] as List<Object?>;
    final package = packages.single as Map<String, Object?>;
    final certification = package['certification'] as Map<String, Object?>;

    expect(certification, containsPair('required', true));
    expect(certification, containsPair('certified', true));
    expect(certification, containsPair('ok', true));
    expect(certification, containsPair('recommendation', 'ready'));
    expect(certification, containsPair('commandRows', 3));
    expect(certification, containsPair('passedCommandRows', 3));
    expect(
      certification,
      containsPair('coveragePolicyStatus', 'readyForExecution'),
    );
    expect(certification, containsPair('readyForAutomation', true));
    expect(
      certification,
      containsPair('qualityGateSummary', 'ready=8, notReady=0'),
    );
    expect(certification, containsPair('automationCoverageRows', 8));
    expect(certification, containsPair('readyAutomationCoverageRows', 8));
    expect(certification, containsPair('interactionRows', 0));
    expect(certification, containsPair('passedInteractionRows', 0));
    expect(stderr, isEmpty);
  });

  test('check rejects noncanonical certification report filenames', () async {
    final environment = await createTestEnvironment();
    final packageRepository = await createPackageRepositoryFixture(environment);
    final report = await _writeCertificationReport(packageRepository);
    final legacyReport = File('${report.parent.path}/legacy-report.md');
    await legacyReport.writeAsString(await report.readAsString());
    final releaseEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['package', 'check', '--json', '--report', legacyReport.path],
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
          allOf(
            contains(
              'Certification report filename must match report-<timestamp>.md',
            ),
            contains('integer'),
            contains('timestamp.'),
          ),
        ),
      ),
    );
    expect(stderr, isEmpty);
  });

  test('check rejects maintainer-confirmed interaction evidence', () async {
    final environment = await createTestEnvironment();
    final packageRepository = await createPackageRepositoryFixture(environment);
    final report = await _writeCertificationReport(packageRepository);
    final content = await report.readAsString();
    await report.writeAsString(
      content.replaceFirst(
        'No interaction required: fixture package has no device-side interaction flow.',
        '''
| Scenario | Method | Platform | Target | Result | Evidence / blocker |
| --- | --- | --- | --- | --- | --- |
| camera preview | maintainer-confirmed | OHOS | emulator | passed | maintainer verified preview before release and hilog contained camera.previewReady |
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
    final error = result['error'] as Map<String, Object?>;
    expect(
      error['message'],
      contains('Interaction Evidence must include a concrete row'),
    );
    expect(error['message'], contains('No interaction required:'));
    expect(stderr, isEmpty);
  });

  test('check certification rejects dry-run drive evidence', () async {
    final environment = await createTestEnvironment();
    final packageRepository = await createPackageRepositoryFixture(environment);
    final report = await _writeCertificationReport(packageRepository);
    final content = await report.readAsString();
    await report.writeAsString(
      content.replaceFirst(
        'fluoh drive ohos --package camera --json',
        'fluoh drive ohos --package camera --dry-run --json',
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
          contains('manual-assisted tool-readable interaction evidence'),
        ),
      ),
    );
    expect(stderr, isEmpty);
  });

  test('check certification rejects plain manual interaction rows', () async {
    final environment = await createTestEnvironment();
    final packageRepository = await createPackageRepositoryFixture(environment);
    final report = await _writeCertificationReport(packageRepository);
    final content = await report.readAsString();
    await report.writeAsString(
      content.replaceFirst(
        'No interaction required: fixture package has no device-side interaction flow.',
        '''
| Scenario | Method | Platform | Target | Result | Evidence / blocker |
| --- | --- | --- | --- | --- | --- |
| camera preview | manual | OHOS | emulator | passed | user confirmed preview |
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
    final error = result['error'] as Map<String, Object?>;
    expect(
      error['message'],
      contains('Interaction Evidence must include a concrete row'),
    );
    expect(error['message'], contains('No interaction required:'));
    expect(stderr, isEmpty);
  });

  test(
    'check certification rejects manual-assisted pass without tool evidence',
    () async {
      final environment = await createTestEnvironment();
      final packageRepository = await createPackageRepositoryFixture(
        environment,
      );
      final report = await _writeCertificationReport(packageRepository);
      final content = await report.readAsString();
      await report.writeAsString(
        content.replaceFirst(
          'No interaction required: fixture package has no device-side interaction flow.',
          '''
| Scenario | Method | Platform | Target | Result | Evidence / blocker |
| --- | --- | --- | --- | --- | --- |
| camera preview | manual-assisted | OHOS | emulator | passed | user session confirmed preview |
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

  test('check certification ignores failed command rows as evidence', () async {
    final environment = await createTestEnvironment();
    final packageRepository = await createPackageRepositoryFixture(environment);
    final report = await _writeCertificationReport(
      packageRepository,
      ohosBuildExit: 1,
      ohosBuildResult: 'failed',
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
    expect(
      result['error'],
      allOf(
        isA<Map<String, Object?>>(),
        containsPair('message', contains('passed OHOS build or run evidence')),
      ),
    );
    expect(stderr, isEmpty);
  });

  test(
    'check certification rejects unresolved automation coverage gates',
    () async {
      final environment = await createTestEnvironment();
      final packageRepository = await createPackageRepositoryFixture(
        environment,
      );
      final report = await _writeCertificationReport(packageRepository);
      final content = await report.readAsString();
      await report.writeAsString(
        content.replaceFirst(
          '| capability-inventory-coverage | readyForReview | all package capabilities covered or explicitly notApplicable |',
          '| capability-inventory-coverage | needsCapabilityCoverageRows | open MethodChannel and example flow rows remain |',
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
            allOf(
              contains('Automation Coverage has unresolved gates'),
              contains('capability-inventory-coverage'),
            ),
          ),
        ),
      );
      expect(stderr, isEmpty);
    },
  );

  test('check certification rejects missing automation coverage gates', () async {
    final environment = await createTestEnvironment();
    final packageRepository = await createPackageRepositoryFixture(environment);
    final report = await _writeCertificationReport(packageRepository);
    final content = await report.readAsString();
    await report.writeAsString(
      content.replaceFirst(
        '| manifest-permission-coverage | readyForReview | no selected-platform manifest runtime permissions apply |\n',
        '',
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
          allOf(
            contains('Automation Coverage is missing required gates'),
            contains('manifest-permission-coverage'),
          ),
        ),
      ),
    );
    expect(stderr, isEmpty);
  });

  test(
    'check certification rejects missing automation coverage status',
    () async {
      final environment = await createTestEnvironment();
      final packageRepository = await createPackageRepositoryFixture(
        environment,
      );
      final report = await _writeCertificationReport(packageRepository);
      final content = await report.readAsString();
      await report.writeAsString(
        content
            .split('\n')
            .where((line) => !line.startsWith('- coveragePolicy.status:'))
            .join('\n'),
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
              'Automation Coverage must record coveragePolicy.status: readyForExecution',
            ),
          ),
        ),
      );
      expect(stderr, isEmpty);
    },
  );

  test(
    'check certification rejects nonzero automation coverage summary',
    () async {
      final environment = await createTestEnvironment();
      final packageRepository = await createPackageRepositoryFixture(
        environment,
      );
      final report = await _writeCertificationReport(packageRepository);
      final content = await report.readAsString();
      await report.writeAsString(
        content.replaceFirst(
          '- qualityGateSummary: ready=8, notReady=0',
          '- qualityGateSummary: ready=7, notReady=1',
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
              'Automation Coverage must record qualityGateSummary with zero notReady gates',
            ),
          ),
        ),
      );
      expect(stderr, isEmpty);
    },
  );
}
