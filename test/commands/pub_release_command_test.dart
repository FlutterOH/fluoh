import 'dart:io';

import 'package:fluoh/fluoh.dart';
import 'package:test/test.dart';

import '../helpers/fluoh_test_context.dart';
import '../helpers/pub_test_context.dart';

void main() {
  test('release creates a tag', () async {
    final environment = await createTestEnvironment();
    final pubRepository = await createPubRepositoryFixture(environment);
    final releaseEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: pubRepository,
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['pub', 'release'],
        environment: releaseEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final tags = await runGit(pubRepository, ['tag', '--list']);
    expect(
      tags.stdout.toString().split('\n'),
      contains('camera-0.11.0-ohos-3.35-0.1.0'),
    );
    expect(
      stdout,
      contains('Created release tag camera-0.11.0-ohos-3.35-0.1.0.'),
    );
    expect(stderr, isEmpty);
  });

  test(
    'release fails for dirty pub worktrees and mismatched branches',
    () async {
      final environment = await createTestEnvironment();
      final pubRepository = await createPubRepositoryFixture(environment);
      final stdout = <String>[];
      final stderr = <String>[];

      await File('${pubRepository.path}/README.md').writeAsString('# dirty\n');
      final dirtyEnvironment = FluohEnvironment(
        homeDirectory: environment.homeDirectory,
        workingDirectory: pubRepository,
      );
      expect(
        await runFluoh(
          ['pub', 'release'],
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

      await runGit(pubRepository, ['checkout', '--', 'README.md']);
      await runGit(pubRepository, ['checkout', '-b', '3.34.0-ohos']);
      stderr.clear();
      expect(
        await runFluoh(
          ['pub', 'release'],
          environment: dirtyEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        64,
      );
      expect(
        stderr.join('\n'),
        contains('does not match pub branch ohos/3.35'),
      );
    },
  );

  test(
    'release validates SDK version and existing release tag commit',
    () async {
      final environment = await createTestEnvironment();
      final pubRepository = await createPubRepositoryFixture(environment);
      final releaseEnvironment = FluohEnvironment(
        homeDirectory: environment.homeDirectory,
        workingDirectory: pubRepository,
      );
      final stdout = <String>[];
      final stderr = <String>[];

      var manifest = File(
        '${pubRepository.path}/fluoh.yaml',
      ).readAsStringSync();
      await File('${pubRepository.path}/fluoh.yaml').writeAsString(
        manifest.replaceFirst(
          'sdk:\n  version: 3.35.8-ohos-0.0.3',
          'sdk:\n  version: 3.35.8-ohos-9.9.9',
        ),
      );
      await runGit(pubRepository, ['add', 'fluoh.yaml']);
      await runGit(pubRepository, ['commit', '-m', 'Use invalid SDK version']);

      expect(
        await runFluoh(
          ['pub', 'release'],
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

      manifest = File('${pubRepository.path}/fluoh.yaml').readAsStringSync();
      await File('${pubRepository.path}/fluoh.yaml').writeAsString(
        manifest.replaceFirst(
          'sdk:\n  version: 3.35.8-ohos-9.9.9',
          'sdk:\n  version: 3.35.8-ohos-0.0.3',
        ),
      );
      await runGit(pubRepository, ['add', 'fluoh.yaml']);
      await runGit(pubRepository, [
        'commit',
        '-m',
        'Restore valid SDK version',
      ]);
      await runGit(pubRepository, [
        'tag',
        'camera-0.11.0-ohos-3.35-0.1.0',
        'HEAD~1',
      ]);

      stderr.clear();
      expect(
        await runFluoh(
          ['pub', 'release'],
          environment: releaseEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        64,
      );
      expect(
        stderr.join('\n'),
        contains('already exists on a different commit'),
      );
    },
  );

  test('release warns when FlutterOH release notes are missing', () async {
    final environment = await createTestEnvironment();
    final pubRepository = await createPubRepositoryFixture(environment);
    final releaseEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: pubRepository,
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await File('${pubRepository.path}/FLUOH_CHANGELOG.md').delete();
    await runGit(pubRepository, ['add', 'FLUOH_CHANGELOG.md']);
    await runGit(pubRepository, ['commit', '-m', 'Remove release notes']);

    expect(
      await runFluoh(
        ['pub', 'release'],
        environment: releaseEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );
    expect(stderr.join('\n'), contains('Missing FLUOH_CHANGELOG.md'));
    expect(
      stdout,
      contains('Created release tag camera-0.11.0-ohos-3.35-0.1.0.'),
    );
  });

  test('release warns when FlutterOH release notes lack an entry', () async {
    final environment = await createTestEnvironment();
    final pubRepository = await createPubRepositoryFixture(environment);
    final releaseEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: pubRepository,
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await File('${pubRepository.path}/FLUOH_CHANGELOG.md').writeAsString('''
# FlutterOH Changelog

## 0.2.0

- Other release notes.
''');
    await runGit(pubRepository, ['add', 'FLUOH_CHANGELOG.md']);
    await runGit(pubRepository, ['commit', '-m', 'Change release notes']);

    expect(
      await runFluoh(
        ['pub', 'release'],
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
      contains('Created release tag camera-0.11.0-ohos-3.35-0.1.0.'),
    );
  });

  test('release warns when FlutterOH package license is missing', () async {
    final environment = await createTestEnvironment();
    final pubRepository = await createPubRepositoryFixture(environment);
    final releaseEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: pubRepository,
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await File('${pubRepository.path}/LICENSE').delete();
    await runGit(pubRepository, ['add', 'LICENSE']);
    await runGit(pubRepository, ['commit', '-m', 'Remove license']);

    expect(
      await runFluoh(
        ['pub', 'release'],
        environment: releaseEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );
    expect(stderr.join('\n'), contains('Missing LICENSE for camera'));
    expect(
      stdout,
      contains('Created release tag camera-0.11.0-ohos-3.35-0.1.0.'),
    );
  });

  test('release accepts changelog entries under subsections', () async {
    final environment = await createTestEnvironment();
    final pubRepository = await createPubRepositoryFixture(environment);
    final releaseEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: pubRepository,
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await File('${pubRepository.path}/FLUOH_CHANGELOG.md').writeAsString('''
# FlutterOH Changelog

## 0.1.0

### Fixed

- Fix OHOS permission handling.
''');
    await runGit(pubRepository, ['add', 'FLUOH_CHANGELOG.md']);
    await runGit(pubRepository, ['commit', '-m', 'Group changelog entries']);

    expect(
      await runFluoh(
        ['pub', 'release'],
        environment: releaseEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );
    expect(
      stdout,
      contains('Created release tag camera-0.11.0-ohos-3.35-0.1.0.'),
    );
    expect(stderr, isEmpty);
  });

  test('release requires a version newer than previous release tags', () async {
    final environment = await createTestEnvironment();
    final pubRepository = await createPubRepositoryFixture(environment);
    final releaseEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: pubRepository,
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await runGit(pubRepository, ['tag', 'camera-0.11.0-ohos-3.35-0.2.0']);

    expect(
      await runFluoh(
        ['pub', 'release'],
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
    final source = await createPubSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamMonorepoRepository(
      Directory('${environment.homeDirectory.path}/release_all_upstream'),
      packagePath: 'packages/camera/camera',
      packageName: 'camera',
    );
    await _addMonorepoPackage(
      upstream,
      path: 'packages/share_plus/share_plus',
      name: 'share_plus',
      version: '9.0.0',
    );
    final pubRepository = Directory(
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
        'pub',
        'create',
        upstream.path,
        '--package-path',
        'packages/camera/camera',
        '--package-path',
        'packages/share_plus/share_plus',
        '--output',
        pubRepository.path,
        '--sdk',
        '3.35.8-ohos-0.0.3',
      ],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    await commitGeneratedPubRepository(pubRepository);

    final releaseEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: pubRepository,
    );
    expect(
      await runFluoh(
        ['pub', 'release', '--all'],
        environment: releaseEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final tags = (await runGit(pubRepository, [
      'tag',
      '--list',
    ])).stdout.toString();
    expect(tags, contains('camera-0.11.0-ohos-3.35-0.1.0'));
    expect(tags, contains('share_plus-9.0.0-ohos-3.35-0.1.0'));
    expect(stdout, contains('Released 2 packages.'));
    expect(stderr, isEmpty);
  });

  test('release --all --push does not push partial remote tags', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamMonorepoRepository(
      Directory('${environment.homeDirectory.path}/release_all_push_upstream'),
      packagePath: 'packages/camera/camera',
      packageName: 'camera',
    );
    await _addMonorepoPackage(
      upstream,
      path: 'packages/share_plus/share_plus',
      name: 'share_plus',
      version: '9.0.0',
    );
    final pubRepository = Directory(
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
        'pub',
        'create',
        upstream.path,
        '--package-path',
        'packages/camera/camera',
        '--package-path',
        'packages/share_plus/share_plus',
        '--output',
        pubRepository.path,
        '--sdk',
        '3.35.8-ohos-0.0.3',
      ],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    await commitGeneratedPubRepository(pubRepository);
    await runGit(pubRepository, ['remote', 'set-url', 'origin', origin.path]);

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
      workingDirectory: pubRepository,
    );
    expect(
      await runFluoh(
        ['pub', 'release', '--all', '--push'],
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
      final source = await createPubSourceFixture(environment.homeDirectory);
      final upstream = await createUpstreamMonorepoRepository(
        Directory(
          '${environment.homeDirectory.path}/release_all_conflict_upstream',
        ),
        packagePath: 'packages/camera/camera',
        packageName: 'camera',
      );
      await _addMonorepoPackage(
        upstream,
        path: 'packages/share_plus/share_plus',
        name: 'share_plus',
        version: '9.0.0',
      );
      final pubRepository = Directory(
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
          'pub',
          'create',
          upstream.path,
          '--package-path',
          'packages/camera/camera',
          '--package-path',
          'packages/share_plus/share_plus',
          '--output',
          pubRepository.path,
          '--sdk',
          '3.35.8-ohos-0.0.3',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      await commitGeneratedPubRepository(pubRepository);
      await runGit(pubRepository, [
        'tag',
        'share_plus-9.0.0-ohos-3.35-0.1.0',
        'HEAD~1',
      ]);

      final releaseEnvironment = FluohEnvironment(
        homeDirectory: environment.homeDirectory,
        workingDirectory: pubRepository,
      );
      expect(
        await runFluoh(
          ['pub', 'release', '--all'],
          environment: releaseEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        64,
      );

      final tags = (await runGit(pubRepository, [
        'tag',
        '--list',
      ])).stdout.toString();
      expect(tags, isNot(contains('camera-0.11.0-ohos-3.35-0.1.0')));
      expect(tags, contains('share_plus-9.0.0-ohos-3.35-0.1.0'));
      expect(
        stderr.join('\n'),
        contains('already exists on a different commit'),
      );
    },
  );

  test('multi-package release notes must identify the package', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamMonorepoRepository(
      Directory('${environment.homeDirectory.path}/release_notes_upstream'),
      packagePath: 'packages/camera/camera',
      packageName: 'camera',
    );
    await _addMonorepoPackage(
      upstream,
      path: 'packages/share_plus/share_plus',
      name: 'share_plus',
      version: '9.0.0',
    );
    final pubRepository = Directory(
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
        'pub',
        'create',
        upstream.path,
        '--package-path',
        'packages/camera/camera',
        '--package-path',
        'packages/share_plus/share_plus',
        '--output',
        pubRepository.path,
        '--sdk',
        '3.35.8-ohos-0.0.3',
      ],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    await File('${pubRepository.path}/FLUOH_CHANGELOG.md').writeAsString('''
# FlutterOH Changelog

## 0.1.0

- Generic release notes.
''');
    await commitGeneratedPubRepository(pubRepository);

    final releaseEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: pubRepository,
    );
    expect(
      await runFluoh(
        ['pub', 'release', '--package', 'share_plus'],
        environment: releaseEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(stderr.join('\n'), contains('entry for share_plus release 0.1.0'));
    expect(
      stdout,
      contains('Created release tag share_plus-9.0.0-ohos-3.35-0.1.0.'),
    );
  });
}

Future<void> _addMonorepoPackage(
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
