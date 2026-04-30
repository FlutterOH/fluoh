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
      await runFluoh(
        ['source', 'use', 'fixture'],
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
            '--sdk-line',
            '3.35',
          ],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final branch = await _git(adapter, ['branch', '--show-current']);
      expect(branch.stdout.toString().trim(), 'ohos-3.35');
      expect(
        File('${adapter.path}/fluoh.yaml').readAsStringSync(),
        allOf(
          contains('schema: 1'),
          contains('name: camera'),
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
    await runFluoh(
      ['source', 'use', 'fixture'],
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
          '--sdk-line',
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
    await runFluoh(
      ['source', 'use', 'fixture'],
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
          '--sdk-line',
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

  test(
    'creates a GitHub repository remote and pushes main and adapter branches',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPubSourceFixture(environment.homeDirectory);
      final upstream = await createUpstreamPackageRepository(
        Directory('${environment.homeDirectory.path}/upstream_camera'),
      );
      final adapter = Directory(
        '${environment.homeDirectory.path}/adapter_github',
      );
      final remoteRoot = Directory('${environment.homeDirectory.path}/github');
      await remoteRoot.create(recursive: true);
      final fakeGh = await _createFakeGh(environment.homeDirectory);
      final githubEnvironment = FluohEnvironment(
        homeDirectory: environment.homeDirectory,
        workingDirectory: environment.workingDirectory,
        processEnvironment: {
          'FLUOH_GH': fakeGh.path,
          'FAKE_GH_REMOTE_ROOT': remoteRoot.path,
        },
      );
      final stdout = <String>[];
      final stderr = <String>[];

      await runFluoh(
        ['source', 'add', 'fixture', source.path],
        environment: githubEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      await runFluoh(
        ['source', 'use', 'fixture'],
        environment: githubEnvironment,
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
            '--sdk-line',
            '3.35',
            '--github',
            '--org',
            'FlutterOH',
          ],
          environment: githubEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final origin = await _git(adapter, ['remote', 'get-url', 'origin']);
      final upstreamRemote = await _git(adapter, [
        'remote',
        'get-url',
        'upstream',
      ]);
      final remoteBranches = await Process.run('git', [
        '--git-dir',
        '${remoteRoot.path}/FlutterOH/camera.git',
        'branch',
        '--list',
      ]);

      expect(
        origin.stdout.toString().trim(),
        '${remoteRoot.path}/FlutterOH/camera.git',
      );
      expect(upstreamRemote.stdout.toString().trim(), upstream.path);
      expect(remoteBranches.stdout.toString(), contains('main'));
      expect(remoteBranches.stdout.toString(), contains('ohos-3.35'));
      final manifest = File('${adapter.path}/fluoh.yaml').readAsStringSync();
      expect(manifest, contains('url: https://github.com/FlutterOH/camera'));
      expect(stdout, contains('Published FlutterOH/camera to GitHub.'));
      expect(stderr, isEmpty);
    },
  );

  test('pushes the upstream default branch during GitHub automation', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamPackageRepository(
      Directory('${environment.homeDirectory.path}/upstream_master_camera'),
      initialBranch: 'master',
    );
    final adapter = Directory(
      '${environment.homeDirectory.path}/adapter_github_master',
    );
    final remoteRoot = Directory('${environment.homeDirectory.path}/github');
    await remoteRoot.create(recursive: true);
    final fakeGh = await _createFakeGh(environment.homeDirectory);
    final githubEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: environment.workingDirectory,
      processEnvironment: {
        'FLUOH_GH': fakeGh.path,
        'FAKE_GH_REMOTE_ROOT': remoteRoot.path,
      },
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'add', 'fixture', source.path],
      environment: githubEnvironment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    await runFluoh(
      ['source', 'use', 'fixture'],
      environment: githubEnvironment,
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
          '--sdk-line',
          '3.35',
          '--github',
          '--org',
          'FlutterOH',
        ],
        environment: githubEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final remoteBranches = await Process.run('git', [
      '--git-dir',
      '${remoteRoot.path}/FlutterOH/camera.git',
      'branch',
      '--list',
    ]);
    expect(remoteBranches.stdout.toString(), contains('master'));
    expect(remoteBranches.stdout.toString(), contains('ohos-3.35'));
    expect(stderr, isEmpty);
  });

  test('keeps null FlutterOH URLs when GitHub automation fails', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamPackageRepository(
      Directory('${environment.homeDirectory.path}/upstream_failed_github'),
    );
    final adapter = Directory(
      '${environment.homeDirectory.path}/adapter_failed_github',
    );
    final failingGh = await _createFailingGh(environment.homeDirectory);
    final githubEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: environment.workingDirectory,
      processEnvironment: {'FLUOH_GH': failingGh.path},
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'add', 'fixture', source.path],
      environment: githubEnvironment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    await runFluoh(
      ['source', 'use', 'fixture'],
      environment: githubEnvironment,
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
          '--sdk-line',
          '3.35',
          '--github',
          '--org',
          'FlutterOH',
        ],
        environment: githubEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );

    final manifest = File('${adapter.path}/fluoh.yaml').readAsStringSync();
    expect(manifest, contains('flutteroh:\n  url: null'));
    expect(manifest, contains('replacement:\n  source: git\n  url: null'));
    expect(manifest, isNot(contains('https://github.com/FlutterOH/camera')));
    expect(stderr.join('\n'), contains('GitHub automation failed'));
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

    final packageYaml = File('${pubSource.path}/packages/camera.yaml');
    final indexYaml = File('${pubSource.path}/packages/index.yaml');
    expect(packageYaml.existsSync(), isTrue);
    expect(indexYaml.existsSync(), isTrue);
    expect(packageYaml.readAsStringSync(), contains('name: camera'));
    expect(
      packageYaml.readAsStringSync(),
      contains('tag: camera-v0.11.0-ohos-3.35.8-0.1.0'),
    );
    expect(indexYaml.readAsStringSync(), contains('name: camera'));
    expect(stdout, contains('Wrote pub source update for camera.'));
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
    expect(stderr.join('\n'), contains('was not found in the active source'));

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
    ['source', 'use', 'fixture'],
    environment: environment,
    stdout: stdout.add,
    stderr: stderr.add,
  );
  await runFluoh(
    ['create', upstream.path, '--output', adapter.path, '--sdk-line', '3.35'],
    environment: environment,
    stdout: stdout.add,
    stderr: stderr.add,
  );

  return adapter;
}

Future<File> _createFakeGh(Directory parent) async {
  final script = File('${parent.path}/fake_gh.sh');
  await script.writeAsString(r'''
#!/bin/sh
set -eu
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  exit 0
fi
if [ "$1" != "repo" ] || [ "$2" != "create" ]; then
  echo "unsupported gh command: $*" >&2
  exit 2
fi
repo="$3"
shift 3
source_dir=""
remote_name="origin"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --source)
      source_dir="$2"
      shift 2
      ;;
    --remote)
      remote_name="$2"
      shift 2
      ;;
    --public)
      shift
      ;;
    *)
      shift
      ;;
  esac
done
bare="$FAKE_GH_REMOTE_ROOT/$repo.git"
mkdir -p "$(dirname "$bare")"
git init --bare "$bare" >/dev/null
git -C "$source_dir" remote add "$remote_name" "$bare"
''');
  final chmod = await Process.run('chmod', ['+x', script.path]);
  if (chmod.exitCode != 0) {
    fail('chmod fake gh failed: ${chmod.stderr}');
  }
  return script;
}

Future<File> _createFailingGh(Directory parent) async {
  final script = File('${parent.path}/failing_gh.sh');
  await script.writeAsString('''
#!/bin/sh
echo "forced gh failure" >&2
exit 2
''');
  final chmod = await Process.run('chmod', ['+x', script.path]);
  if (chmod.exitCode != 0) {
    fail('chmod failing gh failed: ${chmod.stderr}');
  }
  return script;
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
