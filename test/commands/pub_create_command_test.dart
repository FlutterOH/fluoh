import 'dart:io';

import 'package:fluoh/fluoh.dart';
import 'package:test/test.dart';

import '../helpers/fluoh_test_context.dart';
import '../helpers/pub_test_context.dart';

void main() {
  test(
    'creates a pub branch and release tag from an upstream repository',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPubSourceFixture(environment.homeDirectory);
      final upstream = await createUpstreamPackageRepository(
        Directory('${environment.homeDirectory.path}/upstream_camera'),
      );
      final pubRepository = Directory(
        '${environment.homeDirectory.path}/pub_camera',
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
            'pub',
            'create',
            upstream.path,
            '--output',
            pubRepository.path,
            '--sdk',
            '3.35.8-ohos-0.0.3',
          ],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final branch = await runGit(pubRepository, ['branch', '--show-current']);
      final origin = await runGit(pubRepository, [
        'remote',
        'get-url',
        'origin',
      ]);
      final upstreamRemote = await runGit(pubRepository, [
        'remote',
        'get-url',
        'upstream',
      ]);
      expect(branch.stdout.toString().trim(), 'ohos/3.35.8-ohos-0.0.3');
      expect(
        origin.stdout.toString().trim(),
        'git@github.com:FlutterOH/camera.git',
      );
      expect(upstreamRemote.stdout.toString().trim(), upstream.path);
      expect(
        File('${pubRepository.path}/fluoh.yaml').readAsStringSync(),
        allOf(
          contains('schema: 1'),
          contains('name: camera'),
          contains('url: git@github.com:FlutterOH/camera.git'),
          contains('branch: ohos/3.35.8-ohos-0.0.3'),
          contains('3.35.8-ohos-0.0.3'),
          contains('status: experimental'),
          contains('ref: camera-v0.11.0-ohos-3.35.8-ohos-0.0.3-0.1.0'),
        ),
      );
      expect(File('${pubRepository.path}/FLUOH_ADAPT.md').existsSync(), isTrue);

      final releaseEnvironment = FluohEnvironment(
        homeDirectory: environment.homeDirectory,
        workingDirectory: pubRepository,
      );
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
        contains('camera-v0.11.0-ohos-3.35.8-ohos-0.0.3-0.1.0'),
      );
      expect(
        stdout,
        contains('Created pub repository at ${pubRepository.path}.'),
      );
      expect(
        stdout,
        contains(
          'Created release tag '
          'camera-v0.11.0-ohos-3.35.8-ohos-0.0.3-0.1.0.',
        ),
      );
      expect(stderr, isEmpty);
    },
  );

  test('uses --path as a package path inside a monorepo upstream', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamMonorepoRepository(
      Directory('${environment.homeDirectory.path}/upstream_monorepo'),
    );
    final pubRepository = Directory(
      '${environment.homeDirectory.path}/pub_monorepo',
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
          'pub',
          'create',
          upstream.path,
          '--path',
          'packages/camera/camera',
          '--output',
          pubRepository.path,
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
      '${pubRepository.path}/fluoh.yaml',
    ).readAsStringSync();
    expect(manifest, contains('name: camera'));
    expect(manifest, contains('path: packages/camera/camera'));
    expect(stderr, isEmpty);
  });

  test('finds a monorepo package by --package', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamMonorepoRepository(
      Directory('${environment.homeDirectory.path}/upstream_by_package'),
    );
    final pubRepository = Directory(
      '${environment.homeDirectory.path}/pub_by_package',
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
          'pub',
          'create',
          upstream.path,
          '--package',
          'camera',
          '--output',
          pubRepository.path,
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
      '${pubRepository.path}/fluoh.yaml',
    ).readAsStringSync();
    expect(manifest, contains('name: camera'));
    expect(manifest, contains('path: packages/camera/camera'));
    expect(stderr, isEmpty);
  });

  test('uses an explicit pub repository URL when provided', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamPackageRepository(
      Directory('${environment.homeDirectory.path}/upstream_custom_remote'),
    );
    final pubRepository = Directory(
      '${environment.homeDirectory.path}/pub_custom_remote',
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
          'pub',
          'create',
          upstream.path,
          '--output',
          pubRepository.path,
          '--sdk',
          '3.35.8-ohos-0.0.3',
          '--repository',
          'git@github.com:FlutterOH/camera.git',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final origin = await runGit(pubRepository, ['remote', 'get-url', 'origin']);
    final manifest = File(
      '${pubRepository.path}/fluoh.yaml',
    ).readAsStringSync();
    expect(
      origin.stdout.toString().trim(),
      'git@github.com:FlutterOH/camera.git',
    );
    expect(manifest, contains('url: git@github.com:FlutterOH/camera.git'));
    expect(stderr, isEmpty);
  });

  test('pub create leaves upstream default branch unchanged', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamPackageRepository(
      Directory('${environment.homeDirectory.path}/upstream_clean_main'),
    );
    final pubRepository = Directory(
      '${environment.homeDirectory.path}/pub_clean_main',
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
          'pub',
          'create',
          upstream.path,
          '--output',
          pubRepository.path,
          '--sdk',
          '3.35.8-ohos-0.0.3',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    await runGit(pubRepository, ['checkout', 'main']);
    expect(File('${pubRepository.path}/fluoh.yaml').existsSync(), isFalse);
    expect(File('${pubRepository.path}/FLUOH_ADAPT.md').existsSync(), isFalse);
    final status = await runGit(pubRepository, ['status', '--porcelain']);
    expect(status.stdout.toString().trim(), isEmpty);
    expect(stderr, isEmpty);
  });

  test('does not accept removed GitHub automation flags', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamPackageRepository(
      Directory('${environment.homeDirectory.path}/upstream_github_flags'),
    );
    final pubRepository = Directory(
      '${environment.homeDirectory.path}/pub_github_flags',
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
          'pub',
          'create',
          upstream.path,
          '--output',
          pubRepository.path,
          '--sdk',
          '3.35.8-ohos-0.0.3',
          '--github',
          '--org',
          'FlutterOH',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );
    expect(stderr.join('\n'), contains('Could not find an option named'));
  });
}
