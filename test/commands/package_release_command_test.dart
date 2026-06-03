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
    expect(report, containsPair('schemaVersion', 1));
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

  test(
    'check validates without creating tags and accepts report alias',
    () async {
      final environment = await createTestEnvironment();
      final packageRepository = await createPackageRepositoryFixture(
        environment,
      );
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
    },
  );

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
        ['package', 'check', '--json', '--certification-report', report.path],
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
    expect(certification, containsPair('commandRows', 2));
    expect(certification, containsPair('passedCommandRows', 2));
    expect(certification, containsPair('interactionRows', 0));
    expect(certification, containsPair('passedInteractionRows', 0));
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
        ['package', 'check', '--json', '--certification-report', report.path],
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
          '--certification-report',
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
        containsPair('message', contains('fluoh run --platform ohos evidence')),
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
          '--certification-report',
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
    expect(certification, containsPair('commandRows', 3));
    expect(certification, containsPair('passedCommandRows', 3));
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

  test('release --all creates one tag per registered package', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamWorkspaceRepository(
      Directory('${environment.homeDirectory.path}/release_all_upstream'),
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
      '${environment.homeDirectory.path}/release_all_pub',
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
    await commitGeneratedPackageRepository(packageRepository);

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
      0,
    );

    final tags = (await runGit(packageRepository, [
      'tag',
      '--list',
    ])).stdout.toString();
    expect(tags, contains('camera-0.11.0-ohos-3.35-0.1.0'));
    expect(tags, contains('share_plus-9.0.0-ohos-3.35-0.1.0'));
    expect(stdout, contains('Released 2 packages'));
    expect(stderr, isEmpty);
  });

  test('release --all --push does not push partial remote tags', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamWorkspaceRepository(
      Directory('${environment.homeDirectory.path}/release_all_push_upstream'),
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
      '${environment.homeDirectory.path}/release_all_push_pub',
    );
    final origin = Directory(
      '${environment.homeDirectory.path}/release_all_push_origin.git',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await origin.create(recursive: true);
    await runGit(origin, ['init', '--bare']);
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
    await commitGeneratedPackageRepository(packageRepository);
    await runGit(packageRepository, [
      'remote',
      'set-url',
      'origin',
      origin.path,
    ]);

    final updateHook = File('${origin.path}/hooks/update');
    await updateHook.writeAsString(r'''#!/bin/sh
case "$1" in
  refs/tags/share_plus-*) exit 1 ;;
esac
exit 0
''');
    final chmod = await Process.run('chmod', ['+x', updateHook.path]);
    expect(chmod.exitCode, 0);

    final releaseEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    expect(
      await runFluoh(
        ['package', 'release', '--all', '--push'],
        environment: releaseEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );

    final remoteTags = (await runGit(origin, [
      'tag',
      '--list',
    ])).stdout.toString();
    expect(remoteTags, isNot(contains('camera-0.11.0-ohos-3.35-0.1.0')));
    expect(remoteTags, isNot(contains('share_plus-9.0.0-ohos-3.35-0.1.0')));
  });

  test(
    'release --all does not create partial tags when a later tag conflicts',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      final upstream = await createUpstreamWorkspaceRepository(
        Directory(
          '${environment.homeDirectory.path}/release_all_conflict_upstream',
        ),
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
        '${environment.homeDirectory.path}/release_all_conflict_pub',
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
      await commitGeneratedPackageRepository(packageRepository);
      await runGit(packageRepository, [
        'tag',
        'share_plus-9.0.0-ohos-3.35-0.1.0',
        'HEAD~1',
      ]);

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

      final tags = (await runGit(packageRepository, [
        'tag',
        '--list',
      ])).stdout.toString();
      expect(tags, isNot(contains('camera-0.11.0-ohos-3.35-0.1.0')));
      expect(tags, contains('share_plus-9.0.0-ohos-3.35-0.1.0'));
      final error = stderr.join('\n');
      expect(error, contains('already exists on a different'));
      expect(error, contains('commit'));
    },
  );

  test('multi-package release notes must identify the package', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamWorkspaceRepository(
      Directory('${environment.homeDirectory.path}/release_notes_upstream'),
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
      '${environment.homeDirectory.path}/release_notes_pub',
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
    await File('${packageRepository.path}/FLUOH_CHANGELOG.md').writeAsString('''
# FlutterOH Changelog

## 0.1.0

- Generic release notes.
''');
    await commitGeneratedPackageRepository(packageRepository);

    final releaseEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    expect(
      await runFluoh(
        ['package', 'release', '--package', 'share_plus'],
        environment: releaseEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(stderr.join('\n'), contains('entry for share_plus release 0.1.0'));
    expect(
      stdout,
      contains('Created release tag share_plus-9.0.0-ohos-3.35-0.1.0'),
    );
  });
}

Future<File> _writeCertificationReport(
  Directory packageRepository, {
  bool includeOhosRun = false,
  int ohosBuildExit = 0,
  String ohosBuildResult = 'passed',
  String recommendation = 'ready',
}) async {
  final reportDirectory = Directory('${packageRepository.path}/.fluoh');
  await reportDirectory.create(recursive: true);
  final report = File('${reportDirectory.path}/ai-report-camera.md');
  final ohosRunRow = includeOhosRun
      ? '| `fluoh run --platform ohos --package camera --json` | 0 | passed | installed, launched, and collected hilog |\n'
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
| `fluoh build --platform ohos --package camera --auto-sign --json` | $ohosBuildExit | $ohosBuildResult | signed HAP was produced |
$ohosRunRow
## Delivery Checklist

- [x] Diff reviewed; unrelated files, local paths, generated caches, credentials, and private tokens excluded.
- [x] Commands table includes exit codes and enough evidence to reproduce the decision.
- [x] OHOS build evidence recorded.
- [x] OHOS run evidence recorded, or the missing device/emulator blocker is explicit.
- [x] Android, iOS, and macOS regression checks recorded when relevant.
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

## Interaction Evidence

No interaction required: fixture package has no device-side interaction flow.

## Diagnostics

- No diagnostics remain.

## Signing

- Mode: automatic debug signing
- Generated HAPs: camera-ohos-debug.hap
- Hilog: no crash marker detected

## Remaining Risks

- None.

## Local State

- Git status summary: clean
- Files intentionally left uncommitted: .fluoh/ai-report-camera.md
- Files that must not be committed: local AI reports and device logs

## Release Decision

Release recommendation: $recommendation

Reason: baseline and OHOS evidence are complete.
''');
  return report;
}

Future<void> _addWorkspacePackage(
  Directory repository, {
  required String path,
  required String name,
  required String version,
}) async {
  final packageDirectory = Directory('${repository.path}/$path');
  await packageDirectory.create(recursive: true);
  await File('${packageDirectory.path}/pubspec.yaml').writeAsString('''
name: $name
version: $version

environment:
  sdk: ^3.0.0
''');
  await runGit(repository, ['add', '.']);
  await runGit(repository, ['commit', '-m', 'Add $name fixture']);
}
