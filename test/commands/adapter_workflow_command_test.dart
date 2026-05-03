import 'dart:io';

import 'package:fluoh/fluoh.dart';
import 'package:test/test.dart';

import '../helpers/fluoh_test_context.dart';

void main() {
  test(
    'creates an adapter branch and release tag from an upstream repository',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPubSourceFixture(environment.homeDirectory);
      final upstream = await createUpstreamPackageRepository(
        Directory('${environment.homeDirectory.path}/upstream_camera'),
      );
      final adapter = Directory(
        '${environment.homeDirectory.path}/adapter_camera',
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
            'create',
            upstream.path,
            '--output',
            adapter.path,
            '--sdk-series',
            '3.35',
          ],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final branch = await _git(adapter, ['branch', '--show-current']);
      final origin = await _git(adapter, ['remote', 'get-url', 'origin']);
      final upstreamRemote = await _git(adapter, [
        'remote',
        'get-url',
        'upstream',
      ]);
      expect(branch.stdout.toString().trim(), 'ohos-3.35');
      expect(
        origin.stdout.toString().trim(),
        'git@github.com:FlutterOH/fluoh.git',
      );
      expect(upstreamRemote.stdout.toString().trim(), upstream.path);
      expect(
        File('${adapter.path}/fluoh.yaml').readAsStringSync(),
        allOf(
          contains('schema: 1'),
          contains('name: camera'),
          contains('url: git@github.com:FlutterOH/fluoh.git'),
          contains('branch: ohos-3.35'),
          contains('3.35.8-ohos-0.0.3'),
          contains('status: experimental'),
          contains('ref: camera-v0.11.0-ohos-3.35.8-0.1.0'),
        ),
      );
      expect(File('${adapter.path}/FLUOH_ADAPT.md').existsSync(), isTrue);

      final releaseEnvironment = FluohEnvironment(
        homeDirectory: environment.homeDirectory,
        workingDirectory: adapter,
      );
      expect(
        await runFluoh(
          ['release'],
          environment: releaseEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final tags = await _git(adapter, ['tag', '--list']);
      expect(
        tags.stdout.toString().split('\n'),
        contains('camera-v0.11.0-ohos-3.35.8-0.1.0'),
      );
      expect(
        stdout,
        contains('Created adapter repository at ${adapter.path}.'),
      );
      expect(
        stdout,
        contains('Created release tag camera-v0.11.0-ohos-3.35.8-0.1.0.'),
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
    final adapter = Directory(
      '${environment.homeDirectory.path}/adapter_monorepo',
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
          'create',
          upstream.path,
          '--path',
          'packages/camera/camera',
          '--output',
          adapter.path,
          '--sdk-series',
          '3.35',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final manifest = File('${adapter.path}/fluoh.yaml').readAsStringSync();
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
    final adapter = Directory(
      '${environment.homeDirectory.path}/adapter_by_package',
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
          'create',
          upstream.path,
          '--package',
          'camera',
          '--output',
          adapter.path,
          '--sdk-series',
          '3.35',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final manifest = File('${adapter.path}/fluoh.yaml').readAsStringSync();
    expect(manifest, contains('name: camera'));
    expect(manifest, contains('path: packages/camera/camera'));
    expect(stderr, isEmpty);
  });

  test('uses an explicit adapter repository URL when provided', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamPackageRepository(
      Directory('${environment.homeDirectory.path}/upstream_custom_remote'),
    );
    final adapter = Directory(
      '${environment.homeDirectory.path}/adapter_custom_remote',
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
          'create',
          upstream.path,
          '--output',
          adapter.path,
          '--sdk-series',
          '3.35',
          '--repository',
          'git@github.com:FlutterOH/camera.git',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final origin = await _git(adapter, ['remote', 'get-url', 'origin']);
    final manifest = File('${adapter.path}/fluoh.yaml').readAsStringSync();
    expect(
      origin.stdout.toString().trim(),
      'git@github.com:FlutterOH/camera.git',
    );
    expect(manifest, contains('url: git@github.com:FlutterOH/camera.git'));
    expect(stderr, isEmpty);
  });

  test('does not accept removed GitHub automation flags', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamPackageRepository(
      Directory('${environment.homeDirectory.path}/upstream_github_flags'),
    );
    final adapter = Directory(
      '${environment.homeDirectory.path}/adapter_github_flags',
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
          'create',
          upstream.path,
          '--output',
          adapter.path,
          '--sdk-series',
          '3.35',
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
  test('release writes a pub source package update', () async {
    final environment = await createTestEnvironment();
    final adapter = await _createAdapterFixture(environment);
    final pubSource = Directory('${environment.homeDirectory.path}/pub_update');
    final releaseEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: adapter,
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['release', '--source-update', pubSource.path],
        environment: releaseEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final registryYaml = File('${pubSource.path}/packages/registry.yaml');
    final manifestYaml = File(
      '${pubSource.path}/packages/manifests/camera.yaml',
    );
    expect(registryYaml.existsSync(), isTrue);
    expect(manifestYaml.existsSync(), isTrue);
    expect(registryYaml.readAsStringSync(), contains('name: camera'));
    expect(manifestYaml.readAsStringSync(), contains('versionSeries: "3.35"'));
    expect(
      manifestYaml.readAsStringSync(),
      contains('tag: camera-v0.11.0-ohos-3.35.8-0.1.0'),
    );
    expect(File('${pubSource.path}/packages/index.yaml').existsSync(), isFalse);
    expect(
      File('${pubSource.path}/packages/camera.yaml').existsSync(),
      isFalse,
    );
    expect(
      await runFluoh(
        ['source', 'add', 'generated', pubSource.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );
    expect(stdout, contains('Wrote pub source update for camera.'));
    expect(stdout, contains('Added source generated: ${pubSource.path}'));
    expect(stderr, isEmpty);
  });

  test(
    'release fails for dirty adapter worktrees and mismatched branches',
    () async {
      final environment = await createTestEnvironment();
      final adapter = await _createAdapterFixture(environment);
      final stdout = <String>[];
      final stderr = <String>[];

      await File('${adapter.path}/README.md').writeAsString('# dirty\n');
      final dirtyEnvironment = FluohEnvironment(
        homeDirectory: environment.homeDirectory,
        workingDirectory: adapter,
      );
      expect(
        await runFluoh(
          ['release'],
          environment: dirtyEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        64,
      );
      expect(stderr.join('\n'), contains('working tree must be clean'));

      await _git(adapter, ['checkout', '--', 'README.md']);
      await _git(adapter, ['checkout', '-b', 'ohos-3.36']);
      stderr.clear();
      expect(
        await runFluoh(
          ['release'],
          environment: dirtyEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        64,
      );
      expect(stderr.join('\n'), contains('does not match sdkLine 3.35'));
    },
  );

  test('release validates SDK tag and existing release tag commit', () async {
    final environment = await createTestEnvironment();
    final adapter = await _createAdapterFixture(environment);
    final releaseEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: adapter,
    );
    final stdout = <String>[];
    final stderr = <String>[];

    var manifest = File('${adapter.path}/fluoh.yaml').readAsStringSync();
    await File('${adapter.path}/fluoh.yaml').writeAsString(
      manifest.replaceFirst('- 3.35.8-ohos-0.0.3', '- 3.35.8-ohos-9.9.9'),
    );
    await _git(adapter, ['add', 'fluoh.yaml']);
    await _git(adapter, ['commit', '-m', 'Use invalid SDK tag']);

    expect(
      await runFluoh(
        ['release'],
        environment: releaseEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );
    expect(stderr.join('\n'), contains('was not found in configured sources'));

    manifest = File('${adapter.path}/fluoh.yaml').readAsStringSync();
    await File('${adapter.path}/fluoh.yaml').writeAsString(
      manifest.replaceFirst('- 3.35.8-ohos-9.9.9', '- 3.35.8-ohos-0.0.3'),
    );
    await _git(adapter, ['add', 'fluoh.yaml']);
    await _git(adapter, ['commit', '-m', 'Restore valid SDK tag']);
    await _git(adapter, ['tag', 'camera-v0.11.0-ohos-3.35.8-0.1.0', 'HEAD~1']);

    stderr.clear();
    expect(
      await runFluoh(
        ['release'],
        environment: releaseEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );
    expect(stderr.join('\n'), contains('already exists on a different commit'));
  });
}

Future<Directory> _createAdapterFixture(FluohEnvironment environment) async {
  final source = await createPubSourceFixture(environment.homeDirectory);
  final upstream = await createUpstreamPackageRepository(
    Directory('${environment.homeDirectory.path}/upstream_camera'),
  );
  final adapter = Directory(
    '${environment.homeDirectory.path}/adapter_release',
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
    ['create', upstream.path, '--output', adapter.path, '--sdk-series', '3.35'],
    environment: environment,
    stdout: stdout.add,
    stderr: stderr.add,
  );

  return adapter;
}

Future<ProcessResult> _git(Directory repo, List<String> arguments) async {
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: repo.path,
  );
  if (result.exitCode != 0) {
    fail('git ${arguments.join(' ')} failed:\n${result.stderr}');
  }
  return result;
}
