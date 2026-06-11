import 'dart:io';
import 'dart:convert';

import 'package:fluoh/fluoh.dart';
import 'package:test/test.dart';

import '../helpers/fluoh_command_context.dart';
import '../helpers/package_test_context.dart';

void main() {
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
        containsPair('message', contains('passed fluoh drive --json evidence')),
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
    expect(certification, containsPair('automationCoverageRows', 8));
    expect(certification, containsPair('readyAutomationCoverageRows', 8));
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
          'sdk:\n  version: 3.35.8-ohos-0.0.3',
          'sdk:\n  version: 3.35.8-ohos-9.9.9',
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
          'sdk:\n  version: 3.35.8-ohos-9.9.9',
          'sdk:\n  version: 3.35.8-ohos-0.0.3',
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

    await File('${packageRepository.path}/FLUOH_CHANGELOG.md').delete();
    await runGit(packageRepository, ['add', 'FLUOH_CHANGELOG.md']);
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
    expect(stderr.join('\n'), contains('Missing FLUOH_CHANGELOG.md'));
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

    await File('${packageRepository.path}/FLUOH_CHANGELOG.md').writeAsString('''
# FlutterOH Changelog

## 0.2.0

- Other release notes.
''');
    await runGit(packageRepository, ['add', 'FLUOH_CHANGELOG.md']);
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
      contains('FLUOH_CHANGELOG.md does not contain a non-empty entry'),
    );
    expect(
      stdout,
      contains('Created release tag camera-0.11.0-ohos-3.35-0.1.0'),
    );
  });

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

      await File('${packageRepository.path}/FLUOH_CHANGELOG.md').writeAsString(
        '''
# FlutterOH Changelog

## camera-0.11.0-ohos-3.35-0.1.0

- TODO: Replace this generated placeholder with actual release notes before release.
''',
      );
      await runGit(packageRepository, ['add', 'FLUOH_CHANGELOG.md']);
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

  test('release accepts changelog entries under subsections', () async {
    final environment = await createTestEnvironment();
    final packageRepository = await createPackageRepositoryFixture(environment);
    final releaseEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await File('${packageRepository.path}/FLUOH_CHANGELOG.md').writeAsString('''
# FlutterOH Changelog

## 0.1.0

### Fixed

- Fix OHOS permission handling.
''');
    await runGit(packageRepository, ['add', 'FLUOH_CHANGELOG.md']);
    await runGit(packageRepository, [
      'commit',
      '-m',
      'Group changelog entries',
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

Future<File> _writeCertificationReport(
  Directory packageRepository, {
  bool includeOhosRun = false,
  int ohosBuildExit = 0,
  String ohosBuildResult = 'passed',
  String recommendation = 'ready',
}) async {
  final reportDirectory = Directory(
    '${packageRepository.path}/.fluoh/reports/camera',
  );
  await reportDirectory.create(recursive: true);
  final report = File('${reportDirectory.path}/ai-report-20260602-120000.md');
  final ohosRunRow = includeOhosRun
      ? '| `fluoh run ohos --package camera --json` | 0 | passed | installed, launched, and collected hilog |\n'
      : '';
  await report.writeAsString('''
# fluoh AI Report

- Scope: camera
- Repository: package_release
- Package: camera
- Upstream version: 0.11.0
- FlutterOH SDK: 3.35.8-ohos-0.0.3
- Date: 2026-06-02
- Recommendation: $recommendation

## Summary

- camera is certified for release.

## Changes

- Added OHOS package adaptation evidence.

## Public API / Compatibility

- Public Dart API changes: none
- Dependency constraint changes: none
- Non-OHOS regression risk: no existing non-OHOS example platform in fixture

## Commands

| Command | Exit | Result | Notes |
| --- | --- | --- | --- |
| `fluoh verify --package camera --json` | 0 | passed | package and example baseline passed |
| `fluoh build ohos --package camera --auto-sign --json` | $ohosBuildExit | $ohosBuildResult | signed HAP was produced |
| `fluoh drive ohos --package camera --json` | 0 | passed | automation scenarios executed |
$ohosRunRow
## Delivery Checklist

- [x] Diff reviewed; unrelated files, local paths, generated caches, credentials, and private tokens excluded.
- [x] Commands table includes exit codes and enough evidence to reproduce the decision.
- [x] OHOS build evidence recorded.
- [x] OHOS run evidence recorded, or the missing device/emulator blocker is explicit.
- [x] Android, iOS, macOS, Linux, Web, and Windows regression checks recorded when relevant.
- [x] Real `fluoh drive --json` evidence recorded, with no unresolved ready-blocking gates.
- [x] Functional interaction evidence recorded for permission, file, camera, location, media, deep link, external-app, or other device workflows.
- [x] Public API, dependency constraints, and non-OHOS regression risk reviewed.
- [x] Remaining risks and release decision are explicit.

## Platform Matrix

| Platform | Build | Run | Integration test | Target | Evidence / blocker |
| --- | --- | --- | --- | --- | --- |
| OHOS | passed | ${includeOhosRun ? 'passed' : 'skipped with blocker'} | not required | ${includeOhosRun ? 'emulator' : 'none'} | build evidence recorded |
| Android | not present | not present | not required | none | no Android example platform |
| iOS | not present | not present | not required | none | no iOS example platform |
| macOS | not present | not present | not required | none | no macOS example platform |

## Automation Coverage

- coveragePolicy.status: readyForExecution
- readyForAutomation: true
- qualityGateSummary: ready=8, notReady=0

| Gate | Status | Evidence / blocker |
| --- | --- | --- |
| coverage-inventory | readyForReview | package API and example inventory reviewed |
| coverage-metadata | readyForReview | every scenario has coverage metadata or no interaction is required |
| coverage-items | readyForReview | all applicable capability rows reviewed |
| capability-inventory-coverage | readyForReview | all package capabilities covered or explicitly notApplicable |
| scenario-evidence-assertions | readyForReview | no interaction scenario required for fixture |
| existing-test-baseline | readyForReview | package tests present for fixture library |
| manifest-permission-coverage | readyForReview | no selected-platform manifest runtime permissions apply |
| behavior-paths | readyForReview | no device-side behavior path applies to fixture |

## Interaction Evidence

No interaction required: fixture package has no device-side interaction flow.

## Diagnostics

- No diagnostics remain.

## Fluoh Feedback

No fluoh feedback: diagnostics were actionable and no tool or Source gap was found.

## Signing

- Mode: automatic debug signing
- Generated HAPs: camera-ohos-debug.hap
- Hilog: no crash marker detected

## Remaining Risks

- None.

## Local State

- Git status summary: clean
- Files intentionally left uncommitted: .fluoh/reports/camera/ai-report-20260602-120000.md
- Files that must not be committed: local AI reports and device logs

## Release Decision

Release recommendation: $recommendation

Reason: baseline and OHOS evidence are complete.
''');
  return report;
}
