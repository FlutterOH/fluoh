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
      expect(branch.stdout.toString().trim(), 'ohos/3.35');
      expect(
        origin.stdout.toString().trim(),
        'git@github.com:FlutterOH/camera.git',
      );
      expect(upstreamRemote.stdout.toString().trim(), upstream.path);
      final manifest = File(
        '${pubRepository.path}/fluoh.yaml',
      ).readAsStringSync();
      expect(manifest, contains('schema: 1'));
      expect(manifest, contains('name: camera'));
      expect(manifest, contains('sdk:\n  version: 3.35.8-ohos-0.0.3'));
      expect(manifest, contains('package:'));
      expect(manifest, contains('upstream:'));
      expect(manifest, isNot(contains('adapter:')));
      expect(manifest, isNot(contains('dependency:')));
      expect(manifest, isNot(contains('dependencyPolicy:')));
      expect(manifest, isNot(contains('fluoh:')));
      expect(manifest, isNot(contains('flutteroh:')));
      expect(manifest, isNot(contains('replacement:')));
      expect(manifest, contains('url: git@github.com:FlutterOH/camera.git'));
      expect(manifest, contains('ref: ohos/3.35'));
      expect(manifest, isNot(contains('branch: ohos/3.35')));
      expect(manifest, isNot(contains('sdkVersion:')));
      expect(manifest, contains('status: experimental'));
      expect(manifest, isNot(contains('release:')));
      expect(manifest, contains('version: 0.1.0'));
      expect(manifest, contains('version: 0.11.0'));
      expect(manifest, isNot(contains('tag: 0.1.0')));
      expect(manifest, isNot(contains('tag: 0.11.0')));
      expect(
        manifest,
        isNot(contains('tag: camera-v0.11.0-ohos-3.35.8-0.1.0')),
      );
      final guide = File('${pubRepository.path}/FLUOH.md');
      expect(guide.existsSync(), isTrue);
      final guideContent = guide.readAsStringSync();
      expect(guideContent, contains('# FlutterOH Adaptation Guide'));
      expect(guideContent, contains('## Adaptation Workflow'));
      expect(guideContent, contains('fluoh.yaml'));
      expect(guideContent, contains('fluoh pub release'));
      expect(guideContent, contains('The generated files are already staged.'));
      expect(
        guideContent,
        contains('You can continue adapting and commit everything together.'),
      );
      final releaseNotes = File('${pubRepository.path}/FLUOH_CHANGELOG.md');
      expect(releaseNotes.existsSync(), isTrue);
      expect(releaseNotes.readAsStringSync(), contains('## 0.1.0'));
      final agents = File('${pubRepository.path}/AGENTS.md');
      expect(agents.existsSync(), isTrue);
      final agentsContent = agents.readAsStringSync();
      expect(agentsContent, contains('# AGENTS.md'));
      expect(agentsContent, contains('## FlutterOH Agent Instructions'));
      expect(
        agentsContent,
        contains(
          'This repository adapts `camera` 0.11.0 for Flutter OHOS SDK '
          '`3.35.8-ohos-0.0.3`.',
        ),
      );
      expect(agentsContent, contains('- Package path: `.`'));
      expect(agentsContent, contains('- FlutterOH branch: `ohos/3.35`'));
      expect(agentsContent, contains('fluoh.yaml'));
      expect(agentsContent, contains('FLUOH.md'));
      expect(agentsContent, contains('## Use fluoh'));
      expect(
        agentsContent,
        contains(
          'Prefer `fluoh flutter <args>` for Flutter commands so the SDK '
          'selected in `fluoh.yaml` is used.',
        ),
      );
      expect(agentsContent, contains('fluoh flutter pub get'));
      expect(agentsContent, contains('fluoh flutter analyze'));
      expect(agentsContent, contains('fluoh sdk list'));
      expect(agentsContent, contains('## Adaptation Workflow'));
      expect(
        agentsContent,
        contains('Keep the generated `0.1.0` for the first release'),
      );
      expect(
        agentsContent,
        contains('increment it only when releasing after an existing tag'),
      );
      expect(
        agentsContent,
        contains(
          'Record the adapter-facing release notes in `FLUOH_CHANGELOG.md`',
        ),
      );
      expect(
        agentsContent,
        contains('Do not use the upstream package `CHANGELOG.md`'),
      );
      expect(agentsContent, contains('Keep `fluoh_test/example` usable'));
      expect(
        agentsContent,
        contains('Run `fluoh pub release` only after the adapter is ready'),
      );
      expect(
        agentsContent,
        contains('Do not run `fluoh sdk use` in this pub adapter repository'),
      );
      expect(
        agentsContent,
        contains(
          'When intentionally retargeting the adapter SDK, update `fluoh.yaml`',
        ),
      );
      expect(
        agentsContent,
        isNot(contains('Use `fluoh sdk use <version-or-series>`')),
      );
      expect(
        agentsContent,
        contains(
          'Commit local changes before running `fluoh pub sync` '
          'or `fluoh pub release`.',
        ),
      );
      expect(agentsContent, isNot(contains('## Adaptation Checklist')));
      expect(File('${pubRepository.path}/FLUOH_TODO.md').existsSync(), isFalse);
      expect(
        File('${pubRepository.path}/FLUOH_ADAPT.md').existsSync(),
        isFalse,
      );
      expect(File('${pubRepository.path}/.fvmrc').existsSync(), isFalse);
      expect(Directory('${pubRepository.path}/.fvm').existsSync(), isFalse);
      final head = await runGit(pubRepository, ['rev-parse', 'HEAD']);
      final upstreamHead = await runGit(pubRepository, [
        'rev-parse',
        'upstream/main',
      ]);
      expect(
        head.stdout.toString().trim(),
        upstreamHead.stdout.toString().trim(),
      );
      final status = await runGit(pubRepository, ['status', '--porcelain']);
      expect(status.stdout.toString(), contains('A  AGENTS.md'));
      expect(status.stdout.toString(), contains('A  FLUOH.md'));
      expect(status.stdout.toString(), contains('A  FLUOH_CHANGELOG.md'));
      expect(status.stdout.toString(), contains('A  fluoh.yaml'));
      expect(status.stdout.toString(), isNot(contains('.fvm')));
      expect(status.stdout.toString(), isNot(contains('.gitignore')));
      final staged = await runGit(pubRepository, [
        'diff',
        '--cached',
        '--name-only',
      ]);
      expect(
        staged.stdout.toString().split('\n'),
        containsAll([
          'AGENTS.md',
          'FLUOH.md',
          'FLUOH_CHANGELOG.md',
          'fluoh.yaml',
        ]),
      );
      expect(staged.stdout.toString(), isNot(contains('.fvm')));
      expect(staged.stdout.toString(), isNot(contains('.gitignore')));

      final releaseEnvironment = FluohEnvironment(
        homeDirectory: environment.homeDirectory,
        workingDirectory: pubRepository,
      );
      await commitGeneratedPubRepository(pubRepository);
      final committedStatus = await runGit(pubRepository, [
        'status',
        '--porcelain',
      ]);
      expect(committedStatus.stdout.toString().trim(), isEmpty);
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
        contains('camera-v0.11.0-ohos-3.35.8-0.1.0'),
      );
      expect(
        stdout,
        contains('Created pub repository at ${pubRepository.path}.'),
      );
      expect(stdout, contains('Resolving Flutter OHOS SDK.'));
      expect(
        stdout,
        contains('Cloning upstream repository into ${pubRepository.path}.'),
      );
      expect(
        stdout,
        contains(
          'Installing Flutter OHOS SDK 3.35.8-ohos-0.0.3; this may take a while.',
        ),
      );
      expect(
        stdout,
        contains(
          'Flutter OHOS SDK path: '
          '${environment.homeDirectory.path}/sdks/3.35.8-ohos-0.0.3.',
        ),
      );
      expect(stdout, isNot(contains('Generated FLUOH.md')));
      expect(stdout, isNot(contains('Generated files are staged')));
      expect(stdout, isNot(contains('Commit before running fluoh pub sync')));
      expect(
        stdout,
        contains('See FLUOH.md and AGENTS.md for adaptation steps.'),
      );
      expect(
        stdout,
        contains('Configured Flutter OHOS SDK 3.35.8-ohos-0.0.3.'),
      );
      expect(
        stdout,
        contains(
          'Created release tag '
          'camera-v0.11.0-ohos-3.35.8-0.1.0.',
        ),
      );
      expect(stderr, isEmpty);
    },
  );

  test(
    'stages generated files even when upstream ignore rules match them',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPubSourceFixture(environment.homeDirectory);
      final upstream = await createUpstreamPackageRepository(
        Directory('${environment.homeDirectory.path}/upstream_ignored_outputs'),
      );
      await File('${upstream.path}/.gitignore').writeAsString('''
AGENTS.md
FLUOH.md
FLUOH_CHANGELOG.md
fluoh.yaml
''');
      await runGit(upstream, ['add', '.gitignore']);
      await runGit(upstream, ['commit', '-m', 'Ignore local fluoh outputs']);
      final pubRepository = Directory(
        '${environment.homeDirectory.path}/pub_ignored_outputs',
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

      final staged = await runGit(pubRepository, [
        'diff',
        '--cached',
        '--name-only',
      ]);
      expect(
        staged.stdout.toString().split('\n'),
        containsAll([
          'AGENTS.md',
          'FLUOH.md',
          'FLUOH_CHANGELOG.md',
          'fluoh.yaml',
        ]),
      );
      expect(staged.stdout.toString(), isNot(contains('.gitignore')));
      expect(stderr, isEmpty);
    },
  );

  test('preserves existing upstream AGENTS.md instructions', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamPackageRepository(
      Directory('${environment.homeDirectory.path}/upstream_existing_agents'),
    );
    await File('${upstream.path}/AGENTS.md').writeAsString('''
# Upstream Agent Notes

Keep the public Dart API stable.
''');
    await runGit(upstream, ['add', 'AGENTS.md']);
    await runGit(upstream, ['commit', '-m', 'Add upstream agent notes']);
    final pubRepository = Directory(
      '${environment.homeDirectory.path}/pub_existing_agents',
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

    final agentsContent = File(
      '${pubRepository.path}/AGENTS.md',
    ).readAsStringSync();
    expect(agentsContent, contains('# Upstream Agent Notes'));
    expect(agentsContent, contains('Keep the public Dart API stable.'));
    expect(agentsContent, contains('## FlutterOH Agent Instructions'));
    expect(agentsContent, contains('## Use fluoh'));
    expect(agentsContent, contains('## Adaptation Workflow'));
    expect(agentsContent, isNot(contains('# AGENTS.md')));
    final status = await runGit(pubRepository, ['status', '--porcelain']);
    expect(status.stdout.toString(), contains('M  AGENTS.md'));
    final mainAgents = await runGit(pubRepository, ['show', 'main:AGENTS.md']);
    expect(
      mainAgents.stdout.toString(),
      '# Upstream Agent Notes\n\nKeep the public Dart API stable.\n',
    );
    expect(stderr, isEmpty);
  });

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

  test(
    'uses an explicit pub repository URL when provided with --repo',
    () async {
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
            '--repo',
            'git@github.com:FlutterOH/camera.git',
          ],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final origin = await runGit(pubRepository, [
        'remote',
        'get-url',
        'origin',
      ]);
      final manifest = File(
        '${pubRepository.path}/fluoh.yaml',
      ).readAsStringSync();
      expect(
        origin.stdout.toString().trim(),
        'git@github.com:FlutterOH/camera.git',
      );
      expect(manifest, contains('url: git@github.com:FlutterOH/camera.git'));
      expect(stderr, isEmpty);
    },
  );

  test('accepts -r for explicit pub repository URLs', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamPackageRepository(
      Directory('${environment.homeDirectory.path}/upstream_repo_aliases'),
    );
    final pubRepository = Directory(
      '${environment.homeDirectory.path}/pub_repo_alias_short',
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
          '-r',
          'git@github.com:FlutterOH/camera-short.git',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final origin = await runGit(pubRepository, ['remote', 'get-url', 'origin']);
    expect(
      origin.stdout.toString().trim(),
      'git@github.com:FlutterOH/camera-short.git',
    );
    expect(stderr, isEmpty);
  });

  test('pub create leaves upstream default branch tree unchanged', () async {
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

    final mainFiles = await runGit(pubRepository, [
      'ls-tree',
      '-r',
      '--name-only',
      'main',
    ]);
    expect(mainFiles.stdout.toString(), isNot(contains('fluoh.yaml')));
    expect(mainFiles.stdout.toString(), isNot(contains('FLUOH.md')));
    expect(mainFiles.stdout.toString(), isNot(contains('FLUOH_CHANGELOG.md')));
    expect(mainFiles.stdout.toString(), isNot(contains('AGENTS.md')));
    expect(stderr, isEmpty);
  });

  test('selects the latest stable SDK when --sdk is omitted', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    final sdkRepository = Directory(
      '${environment.homeDirectory.path}/flutter-ohos-sdk',
    );
    await runGit(sdkRepository, ['tag', '3.35.8-ohos-0.0.4']);
    await File('${source.path}/sdk/releases.yaml').writeAsString('''
schema: 1
url: ${sdkRepository.path}
releases:
  - version: 3.35.8-ohos-0.0.3
    status: stable
  - version: 3.35.8-ohos-0.0.4
    status: stable
''');
    final upstream = await createUpstreamPackageRepository(
      Directory('${environment.homeDirectory.path}/upstream_default_sdk'),
    );
    final pubRepository = Directory(
      '${environment.homeDirectory.path}/pub_default_sdk',
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
        ['pub', 'create', upstream.path, '--output', pubRepository.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final branch = await runGit(pubRepository, ['branch', '--show-current']);
    final manifest = File(
      '${pubRepository.path}/fluoh.yaml',
    ).readAsStringSync();
    expect(branch.stdout.toString().trim(), 'ohos/3.35');
    expect(manifest, contains('sdk:\n  version: 3.35.8-ohos-0.0.4'));
    expect(stderr, isEmpty);
  });

  test('fails before cloning when destination already exists', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamPackageRepository(
      Directory('${environment.homeDirectory.path}/upstream_existing_dest'),
    );
    final pubRepository = Directory(
      '${environment.homeDirectory.path}/pub_existing_dest',
    );
    await pubRepository.create(recursive: true);
    await File('${pubRepository.path}/README.md').writeAsString('existing');
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
      64,
    );

    expect(
      File('${pubRepository.path}/README.md').readAsStringSync(),
      'existing',
    );
    expect(stderr.join('\n'), contains('Destination already exists'));
  });

  test('fails when --package does not match the selected pubspec', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamPackageRepository(
      Directory('${environment.homeDirectory.path}/upstream_wrong_package'),
    );
    final pubRepository = Directory(
      '${environment.homeDirectory.path}/pub_wrong_package',
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
          'share_plus',
          '--path',
          '.',
          '--output',
          pubRepository.path,
          '--sdk',
          '3.35.8-ohos-0.0.3',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );

    expect(stderr.join('\n'), contains('Package at . is camera'));
    expect(Directory('${pubRepository.path}/.git').existsSync(), isTrue);
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
