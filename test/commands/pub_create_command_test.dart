import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:fluoh/fluoh.dart';
import 'package:fluoh/src/cli/terminal_output.dart';
import 'package:fluoh/src/pub/commands/pub_command.dart';
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
      expect(
        manifest,
        contains(
          '# Complete Flutter OHOS SDK tag used by this adaptation branch.',
        ),
      );
      expect(
        manifest,
        contains('# Upstream package repository tracked by fluoh pub sync.'),
      );
      expect(manifest, contains('packages:\n  camera:'));
      expect(manifest, contains('sdk:\n  version: 3.35.8-ohos-0.0.3'));
      expect(manifest, contains('repository:\n  git:'));
      expect(manifest, contains('upstream:\n  git:'));
      expect(manifest, isNot(contains('implementation:')));
      expect(manifest, isNot(contains('dependency:')));
      expect(manifest, isNot(contains('dependencyPolicy:')));
      expect(manifest, isNot(contains('fluoh:')));
      expect(manifest, isNot(contains('flutteroh:')));
      expect(manifest, isNot(contains('replacement:')));
      expect(manifest, contains('url: "git@github.com:FlutterOH/camera.git"'));
      expect(manifest, contains('branch: ohos/3.35'));
      expect(manifest, isNot(contains('ref: ohos/3.35')));
      expect(manifest, isNot(contains('sdkVersion:')));
      expect(manifest, contains('status: experimental'));
      expect(manifest, isNot(contains('release:')));
      expect(manifest, contains('version: 0.1.0'));
      expect(manifest, contains('upstreamVersion: 0.11.0'));
      expect(manifest, isNot(contains('tag: 0.1.0')));
      expect(manifest, isNot(contains('tag: 0.11.0')));
      expect(manifest, isNot(contains('tag: camera-0.11.0-ohos-3.35-0.1.0')));
      final guide = File('${pubRepository.path}/FLUOH.md');
      expect(guide.existsSync(), isTrue);
      final guideContent = guide.readAsStringSync();
      expect(guideContent, contains('# FlutterOH Implementation'));
      expect(guideContent, contains('## Next Steps'));
      expect(guideContent, contains('## Before Commit'));
      expect(guideContent, contains('fluoh.yaml'));
      expect(guideContent, contains('fluoh pub release'));
      expect(guideContent, contains('iOS team/profile signing values'));
      expect(
        guideContent,
        contains('OHOS `signingConfigs` can be used locally'),
      );
      final releaseNotes = File('${pubRepository.path}/FLUOH_CHANGELOG.md');
      expect(releaseNotes.existsSync(), isTrue);
      final releaseNotesContent = releaseNotes.readAsStringSync();
      expect(releaseNotesContent, contains('## camera-0.11.0-ohos-3.35-0.1.0'));
      expect(
        releaseNotesContent,
        contains(
          'Initial OHOS implementation for `camera` 0.11.0 on Flutter OHOS SDK '
          '`3.35.8-ohos-0.0.3`.',
        ),
      );
      final agents = File('${pubRepository.path}/AGENTS.md');
      expect(agents.existsSync(), isTrue);
      final agentsContent = agents.readAsStringSync();
      expect(agentsContent, contains('# AGENTS.md'));
      expect(agentsContent, contains('## FlutterOH Context'));
      expect(
        agentsContent,
        contains(
          'This repository provides an OHOS implementation for `camera` 0.11.0 on Flutter OHOS SDK '
          '`3.35.8-ohos-0.0.3`.',
        ),
      );
      expect(agentsContent, contains('- Package path: `.`'));
      expect(agentsContent, contains('- FlutterOH branch: `ohos/3.35`'));
      expect(agentsContent, contains('fluoh.yaml'));
      expect(agentsContent, contains('FLUOH_CHANGELOG.md'));
      expect(agentsContent, contains('## Working Rules'));
      expect(agentsContent, contains('## Before Commit'));
      expect(
        agentsContent,
        contains(
          'Use `fluoh flutter <args>` so commands use the SDK selected in '
          '`fluoh.yaml`',
        ),
      );
      expect(agentsContent, contains('fluoh pub get'));
      expect(agentsContent, contains('fluoh_test/example'));
      expect(
        agentsContent,
        contains('assert stable commands, files, schema keys'),
      );
      expect(agentsContent, contains('Run `fluoh test run` before release.'));
      expect(
        agentsContent,
        isNot(contains('Use `fluoh sdk use <version-or-series>`')),
      );
      expect(
        agentsContent,
        contains('Commit before `fluoh pub sync` or `fluoh pub release`'),
      );
      expect(agentsContent, contains('git status --short --ignored=matching'));
      expect(agentsContent, contains('DEVELOPMENT_TEAM'));
      expect(agentsContent, contains('PROVISIONING_PROFILE_SPECIFIER'));
      expect(
        agentsContent,
        contains('OHOS `signingConfigs` may exist for local testing'),
      );
      expect(agentsContent, isNot(contains('## Implementation Checklist')));
      final claude = File('${pubRepository.path}/CLAUDE.md');
      expect(claude.existsSync(), isTrue);
      expect(claude.readAsStringSync(), '@AGENTS.md\n');
      expect(File('${pubRepository.path}/FLUOH_TODO.md').existsSync(), isFalse);
      expect(
        File('${pubRepository.path}/FLUOH_ADAPT.md').existsSync(),
        isFalse,
      );
      expect(File('${pubRepository.path}/.fvmrc').existsSync(), isFalse);
      expect(Directory('${pubRepository.path}/.fvm').existsSync(), isFalse);
      final ideLink = Link('${pubRepository.path}/.fluoh/flutter_sdk');
      expect(ideLink.existsSync(), isTrue);
      expect(
        ideLink.targetSync(),
        '${environment.homeDirectory.path}/sdks/3.35.8-ohos-0.0.3',
      );
      expect(
        File('${pubRepository.path}/.gitignore').readAsStringSync(),
        contains('.fluoh/'),
      );
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
      expect(status.stdout.toString(), contains('A  CLAUDE.md'));
      expect(status.stdout.toString(), contains('A  FLUOH.md'));
      expect(status.stdout.toString(), contains('A  FLUOH_CHANGELOG.md'));
      expect(status.stdout.toString(), contains('A  .gitignore'));
      expect(status.stdout.toString(), contains('A  fluoh.yaml'));
      expect(status.stdout.toString(), isNot(contains('.fvm')));
      expect(status.stdout.toString(), isNot(contains('.fluoh')));
      final staged = await runGit(pubRepository, [
        'diff',
        '--cached',
        '--name-only',
      ]);
      expect(
        staged.stdout.toString().split('\n'),
        containsAll([
          'AGENTS.md',
          'CLAUDE.md',
          'FLUOH.md',
          'FLUOH_CHANGELOG.md',
          '.gitignore',
          'fluoh.yaml',
        ]),
      );
      expect(staged.stdout.toString(), isNot(contains('.fvm')));
      expect(staged.stdout.toString(), isNot(contains('.fluoh')));

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
        contains('camera-0.11.0-ohos-3.35-0.1.0'),
      );
      expect(
        stdout,
        contains('Created pub repository at ${pubRepository.path}.'),
      );
      expect(stdout, contains('Resolving Flutter OHOS SDK.'));
      expect(
        stdout,
        contains('Cloning upstream repository into ${pubRepository.path}...'),
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
      expect(
        stdout,
        contains(
          'IDE Flutter SDK link: ${pubRepository.path}/.fluoh/flutter_sdk.',
        ),
      );
      expect(stdout, contains('Use this link as your IDE Flutter SDK path.'));
      expect(stdout, isNot(contains('Generated FLUOH.md')));
      expect(stdout, isNot(contains('Generated files are staged')));
      expect(stdout, isNot(contains('Commit before running fluoh pub sync')));
      expect(
        stdout,
        contains('See FLUOH.md and AGENTS.md for implementation steps.'),
      );
      expect(
        stdout,
        contains('Configured Flutter OHOS SDK 3.35.8-ohos-0.0.3.'),
      );
      expect(
        stdout,
        contains(
          'Created release tag '
          'camera-0.11.0-ohos-3.35-0.1.0.',
        ),
      );
      expect(stderr, isEmpty);
    },
  );

  test('prints clone once and separates output sections', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamPackageRepository(
      Directory('${environment.homeDirectory.path}/upstream_video_player'),
      packageName: 'video_player',
    );
    final pubRepository = Directory(
      '${environment.homeDirectory.path}/pub_video_player',
    );
    final stdout = <String>[];
    final stderr = <String>[];
    final transient = <String>[];

    await runFluoh(
      ['source', 'add', 'fixture', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    stdout.clear();

    final output = TerminalOutput(
      stdout: stdout.add,
      stderr: stderr.add,
      transient: transient.add,
      style: const TerminalStyle(
        capabilities: TerminalCapabilities(
          ansi: false,
          decorated: true,
          unicode: true,
        ),
      ),
    );
    final runner = CommandRunner<int>('fluoh', 'test')
      ..addCommand(
        PubCommand(
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
          output: output,
        ),
      );

    expect(
      await runner.run([
        'pub',
        'create',
        upstream.path,
        '--output',
        pubRepository.path,
        '--sdk',
        '3.35.8-ohos-0.0.3',
      ]),
      0,
    );

    final cloneMessage =
        'Cloning upstream repository into ${pubRepository.path}...';
    expect(stdout.where((line) => line.contains(cloneMessage)), hasLength(1));
    expect(transient.join(), isNot(contains(cloneMessage)));
    expect(transient.join(), isNot(contains('Receiving objects')));
    final cloneIndex = stdout.indexWhere((line) => line.contains(cloneMessage));
    final firstBlank = stdout.indexWhere(
      (line) => line.isEmpty,
      cloneIndex + 1,
    );
    expect(firstBlank, greaterThanOrEqualTo(0));
    final sdkMessageIndex = stdout.indexWhere(
      (line) =>
          line.contains('Using installed Flutter OHOS SDK') ||
          line.contains('Flutter OHOS SDK path:'),
    );
    expect(sdkMessageIndex, greaterThan(firstBlank));
    final sdkLinkIndex = stdout.indexWhere(
      (line) => line.contains('IDE Flutter SDK link:'),
    );
    expect(
      stdout[sdkLinkIndex + 1],
      contains('Use this link as your IDE Flutter SDK path.'),
    );
    expect(stdout[sdkLinkIndex + 2], isEmpty);
    final testInitIndex = stdout.indexWhere(
      (line) => line.contains('Skipping fluoh test init:'),
    );
    expect(stdout[testInitIndex + 1], isEmpty);
    final summaryIndex = stdout.indexWhere(
      (line) =>
          line.contains('Created pub repository at ${pubRepository.path}.'),
    );
    expect(summaryIndex, greaterThan(testInitIndex));
    expect(stderr, isEmpty);
  });

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
CLAUDE.md
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
          'CLAUDE.md',
          'FLUOH.md',
          'FLUOH_CHANGELOG.md',
          '.gitignore',
          'fluoh.yaml',
        ]),
      );
      expect(staged.stdout.toString(), isNot(contains('.fluoh')));
      expect(stderr, isEmpty);
    },
  );

  test('warns when upstream license is missing', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamPackageRepository(
      Directory('${environment.homeDirectory.path}/upstream_without_license'),
      licenseContent: null,
    );
    final pubRepository = Directory(
      '${environment.homeDirectory.path}/pub_without_license',
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

    expect(stderr.join('\n'), contains('Missing LICENSE for camera'));
    expect(
      stdout,
      contains('Created pub repository at ${pubRepository.path}.'),
    );
  });

  test(
    'warns when upstream license disallows modified redistribution',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPubSourceFixture(environment.homeDirectory);
      final upstream = await createUpstreamPackageRepository(
        Directory('${environment.homeDirectory.path}/upstream_no_derivatives'),
        licenseContent: '''
Creative Commons Attribution-NoDerivatives 4.0 International

No derivative works are permitted.
''',
      );
      final pubRepository = Directory(
        '${environment.homeDirectory.path}/pub_no_derivatives',
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

      expect(
        stderr.join('\n'),
        contains('LICENSE appears to disallow modified redistribution'),
      );
      expect(
        stdout,
        contains('Created pub repository at ${pubRepository.path}.'),
      );
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
    await File('${upstream.path}/CLAUDE.md').writeAsString('''
# Upstream Claude Notes

Prefer the upstream release workflow.
''');
    await runGit(upstream, ['add', 'AGENTS.md', 'CLAUDE.md']);
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
    expect(agentsContent, contains('## FlutterOH Context'));
    expect(agentsContent, contains('## Working Rules'));
    expect(agentsContent, contains('## Before Commit'));
    expect(agentsContent, isNot(contains('# AGENTS.md')));
    final claudeContent = File(
      '${pubRepository.path}/CLAUDE.md',
    ).readAsStringSync();
    expect(claudeContent, startsWith('@AGENTS.md\n\n# Upstream Claude Notes'));
    expect(claudeContent, contains('Prefer the upstream release workflow.'));
    final status = await runGit(pubRepository, ['status', '--porcelain']);
    expect(status.stdout.toString(), contains('M  AGENTS.md'));
    expect(status.stdout.toString(), contains('M  CLAUDE.md'));
    final mainAgents = await runGit(pubRepository, ['show', 'main:AGENTS.md']);
    expect(
      mainAgents.stdout.toString(),
      '# Upstream Agent Notes\n\nKeep the public Dart API stable.\n',
    );
    final mainClaude = await runGit(pubRepository, ['show', 'main:CLAUDE.md']);
    expect(
      mainClaude.stdout.toString(),
      '# Upstream Claude Notes\n\nPrefer the upstream release workflow.\n',
    );
    expect(stderr, isEmpty);
  });

  test(
    'uses --package-path as a package path inside a monorepo upstream',
    () async {
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
            '--package-path',
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
      expect(manifest, contains('packages:\n  camera:'));
      expect(manifest, contains('path: packages/camera/camera'));
      expect(stderr, isEmpty);
    },
  );

  test(
    'keeps monorepo default output while selecting a package path',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPubSourceFixture(environment.homeDirectory);
      final upstream = await createUpstreamMonorepoRepository(
        Directory('${environment.homeDirectory.path}/flutter-widgets'),
        packagePath: 'packages/syncfusion_flutter_pdf',
        packageName: 'syncfusion_flutter_pdf',
      );
      final pubRepository = Directory(
        '${environment.workingDirectory.path}/flutter-widgets',
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
            '--package-path',
            'packages/syncfusion_flutter_pdf',
            '--sdk',
            '3.35.8-ohos-0.0.3',
          ],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      expect(pubRepository.existsSync(), isTrue);
      final manifest = File(
        '${pubRepository.path}/fluoh.yaml',
      ).readAsStringSync();
      expect(manifest, contains('packages:\n  syncfusion_flutter_pdf:'));
      expect(manifest, contains('path: packages/syncfusion_flutter_pdf'));
      expect(
        stdout,
        contains('Created pub repository at ${pubRepository.path}.'),
      );
      expect(
        stdout,
        contains(
          'Selected package syncfusion_flutter_pdf at '
          'packages/syncfusion_flutter_pdf.',
        ),
      );
      expect(stderr, isEmpty);
    },
  );

  test(
    'creates a monorepo implementation with multiple package paths',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPubSourceFixture(environment.homeDirectory);
      final upstream = await createUpstreamMonorepoRepository(
        Directory('${environment.homeDirectory.path}/upstream_multi_package'),
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
        '${environment.homeDirectory.path}/pub_multi_package',
      );
      final stdout = <String>[];
      final stderr = <String>[];

      await runFluoh(
        ['source', 'add', 'fixture', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );

      final createResult = await runFluoh(
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
      expect(createResult, 0);

      final manifest = File(
        '${pubRepository.path}/fluoh.yaml',
      ).readAsStringSync();
      expect(manifest, contains('packages:\n  camera:'));
      expect(manifest, contains('  share_plus:'));
      expect(manifest, contains('path: packages/camera/camera'));
      expect(manifest, contains('path: packages/share_plus/share_plus'));
      final guide = File('${pubRepository.path}/FLUOH.md').readAsStringSync();
      expect(
        guide,
        contains('provides OHOS implementations for multiple packages'),
      );
      expect(
        guide,
        contains(
          '`camera` 0.11.0: package path `packages/camera/camera`, '
          'tests `fluoh_test/camera`',
        ),
      );
      expect(
        guide,
        contains(
          '`share_plus` 9.0.0: package path '
          '`packages/share_plus/share_plus`, tests `fluoh_test/share_plus`',
        ),
      );
      expect(guide, contains('`fluoh pub release --package share_plus`'));
      final agents = File('${pubRepository.path}/AGENTS.md').readAsStringSync();
      expect(
        agents,
        contains('provides OHOS implementations for multiple packages'),
      );
      expect(agents, contains('assert stable commands, files, schema keys'));
      expect(agents, contains('`fluoh test run --package <name>`'));
      expect(agents, contains('`fluoh pub release --package camera`'));
      expect(agents, contains('`fluoh pub release --package share_plus`'));
      expect(stderr, isEmpty);
    },
  );

  test('adds another package to an existing monorepo implementation', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamMonorepoRepository(
      Directory('${environment.homeDirectory.path}/upstream_add_package'),
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
      '${environment.homeDirectory.path}/pub_add_package',
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

    final pubEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: pubRepository,
    );
    expect(
      await runFluoh(
        ['pub', 'add', 'packages/share_plus/share_plus'],
        environment: pubEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final manifest = File(
      '${pubRepository.path}/fluoh.yaml',
    ).readAsStringSync();
    expect(manifest, contains('packages:\n  camera:'));
    expect(manifest, contains('  share_plus:'));
    final guide = File('${pubRepository.path}/FLUOH.md').readAsStringSync();
    expect(
      guide,
      contains(
        'This repository provides an OHOS implementation for `camera` 0.11.0',
      ),
    );
    expect(
      guide,
      contains(
        'This repository provides an OHOS implementation for `share_plus` 9.0.0',
      ),
    );
    expect(guide, contains('Package path: `packages/share_plus/share_plus`'));
    expect(guide, contains('fluoh_test/share_plus/example'));
    final agents = File('${pubRepository.path}/AGENTS.md').readAsStringSync();
    expect(
      agents,
      contains(
        'This repository provides an OHOS implementation for `share_plus` 9.0.0',
      ),
    );
    expect(
      agents,
      contains('Run `fluoh test run --package share_plus` before release.'),
    );
    final changelog = File(
      '${pubRepository.path}/FLUOH_CHANGELOG.md',
    ).readAsStringSync();
    expect(changelog, contains('## share_plus-9.0.0-ohos-3.35-0.1.0'));
    final status = await runGit(pubRepository, ['status', '--porcelain']);
    expect(status.stdout.toString(), contains('M  fluoh.yaml'));
    expect(status.stdout.toString(), contains('M  AGENTS.md'));
    expect(status.stdout.toString(), contains('M  FLUOH.md'));
    expect(status.stdout.toString(), contains('M  FLUOH_CHANGELOG.md'));
    expect(
      stdout,
      contains(
        'Registered package share_plus at packages/share_plus/share_plus.',
      ),
    );
    expect(stderr, isEmpty);
  });

  test('requires a selected package for monorepo upstreams', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamMonorepoRepository(
      Directory(
        '${environment.homeDirectory.path}/upstream_unselected_monorepo',
      ),
    );
    final pubRepository = Directory(
      '${environment.homeDirectory.path}/pub_unselected_monorepo',
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
      64,
    );

    expect(stderr.join('\n'), contains('For a monorepo, select package paths'));
    expect(stderr.join('\n'), contains('--package-path <package-path>'));
    expect(pubRepository.existsSync(), isFalse);
  });

  test(
    'uses an explicit pub repository URL when provided with --repository',
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
            '--repository',
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
      expect(manifest, contains('url: "git@github.com:FlutterOH/camera.git"'));
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
    await writeSdkSourceFixture(
      source,
      sdkRepository: sdkRepository.path,
      releases: {'3.35.8-ohos-0.0.3': 'stable', '3.35.8-ohos-0.0.4': 'stable'},
    );
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

  test('does not accept --package for pub create', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamPackageRepository(
      Directory('${environment.homeDirectory.path}/upstream_package_option'),
    );
    final pubRepository = Directory(
      '${environment.homeDirectory.path}/pub_package_option',
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

    expect(stderr.join('\n'), contains('Could not find an option named'));
    expect(Directory('${pubRepository.path}/.git').existsSync(), isFalse);
  });

  test('does not accept removed pub create option names', () async {
    final environment = await createTestEnvironment();
    final upstream = await createUpstreamPackageRepository(
      Directory('${environment.homeDirectory.path}/upstream_removed_options'),
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['pub', 'create', upstream.path, '--path', '.', '--repo', 'origin'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );

    expect(stdout, isEmpty);
    expect(stderr.join('\n'), contains('Could not find an option named'));
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

Future<void> _addMonorepoPackage(
  Directory repository, {
  required String path,
  required String name,
  required String version,
}) async {
  final package = Directory('${repository.path}/$path');
  await package.create(recursive: true);
  await File('${package.path}/pubspec.yaml').writeAsString('''
name: $name
version: $version

environment:
  sdk: ^3.0.0
''');
  await runGit(repository, ['add', path]);
  await runGit(repository, ['commit', '-m', 'Add $name fixture']);
}
