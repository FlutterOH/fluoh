import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:fluoh/fluoh.dart';
import 'package:fluoh/src/cli/terminal_output.dart';
import 'package:fluoh/src/package/commands/package_command.dart';
import 'package:fluoh/src/package/manifest/package_manifest.dart';
import 'package:test/test.dart';

import '../helpers/fluoh_command_context.dart';
import '../helpers/package_test_context.dart';

void main() {
  test(
    'creates a package branch and release tag from an upstream repository',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      final upstream = await createUpstreamPackageRepository(
        Directory('${environment.homeDirectory.path}/upstream_camera'),
      );
      final packageRepository = Directory(
        '${environment.homeDirectory.path}/package_camera',
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
            'package',
            'create',
            upstream.path,
            '--output',
            packageRepository.path,
            '--sdk',
            '3.35.8-ohos-0.0.3',
            '--git-author-name',
            'FlutterOH Adapter',
            '--git-author-email',
            'adapter@example.com',
          ],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final branch = await runGit(packageRepository, [
        'branch',
        '--show-current',
      ]);
      final origin = await runGit(packageRepository, [
        'remote',
        'get-url',
        'origin',
      ]);
      final upstreamRemote = await runGit(packageRepository, [
        'remote',
        'get-url',
        'upstream',
      ]);
      expect(branch.stdout.toString().trim(), 'ohos/3.35');
      expect(
        origin.stdout.toString().trim(),
        'https://github.com/FlutterOH/camera.git',
      );
      expect(upstreamRemote.stdout.toString().trim(), upstream.path);
      final authorName = await runGit(packageRepository, [
        'config',
        '--local',
        '--get',
        'user.name',
      ]);
      final authorEmail = await runGit(packageRepository, [
        'config',
        '--local',
        '--get',
        'user.email',
      ]);
      expect(authorName.stdout.toString().trim(), 'FlutterOH Adapter');
      expect(authorEmail.stdout.toString().trim(), 'adapter@example.com');
      final manifestContent = File(
        '${packageRepository.path}/fluoh.yaml',
      ).readAsStringSync();
      final packageManifest = await readPackageManifest(packageRepository);
      expect(manifestContent, contains('schema: 1'));
      expect(manifestContent, contains('packages:\n  camera:'));
      expect(manifestContent, isNot(contains('implementation:')));
      expect(manifestContent, isNot(contains('dependency:')));
      expect(manifestContent, isNot(contains('dependencyPolicy:')));
      expect(manifestContent, isNot(contains('fluoh:')));
      expect(manifestContent, isNot(contains('flutteroh:')));
      expect(manifestContent, isNot(contains('replacement:')));
      expect(manifestContent, isNot(contains('ref:')));
      expect(manifestContent, isNot(contains('sdkVersion:')));
      expect(manifestContent, isNot(contains('release:')));
      expect(manifestContent, isNot(contains('tag:')));
      expect(packageManifest.name, 'camera');
      expect(packageManifest.sdkVersion, '3.35.8-ohos-0.0.3');
      expect(
        packageManifest.repositoryUrl,
        'https://github.com/FlutterOH/camera.git',
      );
      expect(packageManifest.repositoryBranch, 'ohos/3.35');
      expect(packageManifest.upstreamUrl, upstream.path);
      expect(packageManifest.upstreamBranch, 'main');
      expect(packageManifest.primaryPackage.name, 'camera');
      expect(packageManifest.primaryPackage.version, '0.1.0');
      expect(packageManifest.primaryPackage.upstreamVersion, '0.11.0');
      expect(packageManifest.primaryPackage.status, 'experimental');
      final guide = File('${packageRepository.path}/FLUOH.md');
      expect(guide.existsSync(), isTrue);
      final guideContent = guide.readAsStringSync();
      _expectImplementationGuide(
        guideContent,
        packages: const [
          _GuidancePackage(name: 'camera', version: '0.11.0', path: '.'),
        ],
      );
      final releaseNotes = File('${packageRepository.path}/FLUOH_CHANGELOG.md');
      expect(releaseNotes.existsSync(), isTrue);
      final releaseNotesContent = releaseNotes.readAsStringSync();
      _expectChangelogEntry(
        releaseNotesContent,
        'camera-0.11.0-ohos-3.35-0.1.0',
      );
      final agents = File('${packageRepository.path}/AGENTS.md');
      expect(agents.existsSync(), isTrue);
      final agentsContent = agents.readAsStringSync();
      _expectAgentsInstructions(
        agentsContent,
        packages: const [
          _GuidancePackage(name: 'camera', version: '0.11.0', path: '.'),
        ],
      );
      expect(agentsContent, isNot(contains('Upstream branch at creation')));
      expect(agentsContent, isNot(contains('- FlutterOH branch: `ohos/3.35`')));
      expect(
        agentsContent,
        isNot(contains('Use `fluoh sdk use <version-or-series>`')),
      );
      expect(
        agentsContent,
        isNot(contains('feat(camera): add OHOS platform scaffold')),
      );
      expect(agentsContent, isNot(contains('## Implementation Checklist')));
      final claude = File('${packageRepository.path}/CLAUDE.md');
      expect(claude.existsSync(), isTrue);
      expect(claude.readAsStringSync(), '@AGENTS.md\n');
      expect(
        File('${packageRepository.path}/FLUOH_TODO.md').existsSync(),
        isFalse,
      );
      expect(
        File('${packageRepository.path}/FLUOH_ADAPT.md').existsSync(),
        isFalse,
      );
      expect(File('${packageRepository.path}/.fvmrc').existsSync(), isFalse);
      expect(Directory('${packageRepository.path}/.fvm').existsSync(), isFalse);
      final ideLink = Link('${packageRepository.path}/.fluoh/flutter_sdk');
      expect(ideLink.existsSync(), isTrue);
      expect(
        ideLink.targetSync(),
        '${environment.homeDirectory.path}/sdks/3.35.8-ohos-0.0.3',
      );
      expect(
        File('${packageRepository.path}/.gitignore').readAsStringSync(),
        contains('.fluoh/'),
      );
      expect(
        File('${packageRepository.path}/.gitignore').readAsStringSync(),
        contains('flutter_*.log'),
      );
      final head = await runGit(packageRepository, ['rev-parse', 'HEAD']);
      final upstreamHead = await runGit(packageRepository, [
        'rev-parse',
        'upstream/main',
      ]);
      expect(
        head.stdout.toString().trim(),
        upstreamHead.stdout.toString().trim(),
      );
      final status = await runGit(packageRepository, ['status', '--porcelain']);
      expect(status.stdout.toString(), contains('A  AGENTS.md'));
      expect(status.stdout.toString(), contains('A  CLAUDE.md'));
      expect(status.stdout.toString(), contains('A  FLUOH.md'));
      expect(status.stdout.toString(), contains('A  FLUOH_CHANGELOG.md'));
      expect(status.stdout.toString(), contains('A  .gitignore'));
      expect(status.stdout.toString(), contains('A  fluoh.yaml'));
      expect(status.stdout.toString(), isNot(contains('.fvm')));
      expect(status.stdout.toString(), isNot(contains('.fluoh')));
      final staged = await runGit(packageRepository, [
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
        workingDirectory: packageRepository,
      );
      await commitGeneratedPackageRepository(packageRepository);
      final committedStatus = await runGit(packageRepository, [
        'status',
        '--porcelain',
      ]);
      expect(committedStatus.stdout.toString().trim(), isEmpty);
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
      _expectContainsAll(stdout.join('\n'), [
        'Created package repository at ${packageRepository.path}.',
        'Configured Flutter OHOS SDK 3.35.8-ohos-0.0.3.',
        'Created release tag camera-0.11.0-ohos-3.35-0.1.0.',
      ]);
      expect(stderr, isEmpty);
    },
  );

  test('prints clone once and separates output sections', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamPackageRepository(
      Directory('${environment.homeDirectory.path}/upstream_video_player'),
      packageName: 'video_player',
    );
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_video_player',
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
        PackageCommand(
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
          output: output,
        ),
      );

    expect(
      await runner.run([
        'package',
        'create',
        upstream.path,
        '--output',
        packageRepository.path,
        '--sdk',
        '3.35.8-ohos-0.0.3',
      ]),
      0,
    );

    final cloneMessage =
        'Cloning upstream repository into ${packageRepository.path}...';
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
    expect(sdkLinkIndex, greaterThanOrEqualTo(0));
    expect(stdout[sdkLinkIndex + 1], isNot(isEmpty));
    expect(stdout[sdkLinkIndex + 2], isEmpty);
    final exampleSkipIndex = stdout.indexWhere(
      (line) => line.contains('Skipping example OHOS setup for video_player:'),
    );
    expect(exampleSkipIndex, greaterThan(sdkLinkIndex));
    final summaryIndex = stdout.indexWhere(
      (line) => line.contains(
        'Created package repository at ${packageRepository.path}.',
      ),
    );
    expect(summaryIndex, greaterThan(exampleSkipIndex));
    expect(stderr, isEmpty);
  });

  test(
    'stages generated files even when upstream ignore rules match them',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
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
      final packageRepository = Directory(
        '${environment.homeDirectory.path}/package_ignored_outputs',
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
            'package',
            'create',
            upstream.path,
            '--output',
            packageRepository.path,
            '--sdk',
            '3.35.8-ohos-0.0.3',
          ],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final staged = await runGit(packageRepository, [
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

  test('adds OHOS to an existing Flutter example', () async {
    final environment = await createTestEnvironment();
    final source = await _createPackageCreateSdkSource(
      environment.homeDirectory,
      logName: 'package_create_example_flutter_args.log',
    );
    final upstream = await _createUpstreamFlutterPluginRepository(
      Directory('${environment.homeDirectory.path}/upstream_flutter_camera'),
    );
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_flutter_camera',
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
          'package',
          'create',
          upstream.path,
          '--output',
          packageRepository.path,
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
      Directory('${packageRepository.path}/example/ohos').existsSync(),
      isTrue,
    );
    expect(
      File('${packageRepository.path}/example/fluoh.yaml').existsSync(),
      isTrue,
    );
    final exampleGitignore = File(
      '${packageRepository.path}/example/.gitignore',
    ).readAsStringSync();
    expect(exampleGitignore, contains('.fluoh/'));
    expect(exampleGitignore, contains('flutter_*.log'));
    expect(exampleGitignore, contains('local.properties'));
    final staged = await runGit(packageRepository, [
      'diff',
      '--cached',
      '--name-only',
    ]);
    expect(staged.stdout.toString(), contains('example/ohos'));
    expect(staged.stdout.toString(), contains('example/fluoh.yaml'));
    expect(staged.stdout.toString(), contains('example/.gitignore'));

    final flutterLog = File(
      '${environment.homeDirectory.path}/package_create_example_flutter_args.log',
    ).readAsStringSync();
    expect(
      flutterLog,
      contains(
        '${packageRepository.path}/example::create --no-pub --platforms=ohos .',
      ),
    );
    expect(stdout, contains('Prepared example for camera at example.'));
    expect(stderr, contains('flutter create stderr'));
  });

  test('resolves relative output from the fluoh working directory', () async {
    final environment = await createTestEnvironment();
    final source = await _createPackageCreateSdkSource(
      environment.homeDirectory,
      logName: 'package_create_relative_output_flutter_args.log',
    );
    final upstream = await _createUpstreamFlutterPluginRepository(
      Directory('${environment.homeDirectory.path}/upstream_relative_camera'),
    );
    final packagesRoot = Directory(
      '${environment.workingDirectory.parent.path}/packages',
    );
    await packagesRoot.create(recursive: true);
    final packageRepository = Directory(
      '${packagesRoot.path}/package_relative_camera',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'add', 'fixture', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );

    final process = await Process.run(
      Platform.resolvedExecutable,
      [
        '${Directory.current.path}/bin/fluoh.dart',
        'package',
        'create',
        upstream.path,
        '--output',
        '../packages/package_relative_camera',
        '--sdk',
        '3.35.8-ohos-0.0.3',
      ],
      workingDirectory: environment.workingDirectory.path,
      environment: {
        ...Platform.environment,
        'FLUOH_HOME': environment.homeDirectory.path,
        ...environment.processEnvironment,
      },
    );

    expect(process.exitCode, 0, reason: '${process.stdout}\n${process.stderr}');

    expect(
      Directory('${packageRepository.path}/example/ohos').existsSync(),
      isTrue,
    );
    expect(Directory('${packagesRoot.path}/packages').existsSync(), isFalse);
    final flutterLog = File(
      '${environment.homeDirectory.path}/package_create_relative_output_flutter_args.log',
    ).readAsStringSync();
    expect(
      flutterLog,
      contains('/packages/package_relative_camera/example::create --no-pub'),
    );
    expect(
      process.stdout.toString(),
      contains('/packages/package_relative_camera.'),
    );
    expect(
      process.stdout.toString(),
      isNot(contains('/packages/packages/package_relative_camera')),
    );
    expect(process.stdout.toString(), contains('flutter create stderr'));
  });

  test('warns when upstream license is missing', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamPackageRepository(
      Directory('${environment.homeDirectory.path}/upstream_without_license'),
      licenseContent: null,
    );
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_without_license',
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
          'package',
          'create',
          upstream.path,
          '--output',
          packageRepository.path,
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
      contains('Created package repository at ${packageRepository.path}.'),
    );
  });

  test(
    'warns when upstream license disallows modified redistribution',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      final upstream = await createUpstreamPackageRepository(
        Directory('${environment.homeDirectory.path}/upstream_no_derivatives'),
        licenseContent: '''
Creative Commons Attribution-NoDerivatives 4.0 International

No derivative works are permitted.
''',
      );
      final packageRepository = Directory(
        '${environment.homeDirectory.path}/package_no_derivatives',
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
            'package',
            'create',
            upstream.path,
            '--output',
            packageRepository.path,
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
        contains('Created package repository at ${packageRepository.path}.'),
      );
    },
  );

  test('preserves existing upstream AGENTS.md instructions', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
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
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_existing_agents',
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
          'package',
          'create',
          upstream.path,
          '--output',
          packageRepository.path,
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
      '${packageRepository.path}/AGENTS.md',
    ).readAsStringSync();
    expect(agentsContent, contains('# Upstream Agent Notes'));
    expect(agentsContent, contains('Keep the public Dart API stable.'));
    expect(agentsContent, contains('## FlutterOH Context'));
    expect(agentsContent, contains('## Working Rules'));
    expect(agentsContent, contains('## Adaptation Workflow'));
    expect(agentsContent, contains('## Before Commit'));
    expect(agentsContent, isNot(contains('# AGENTS.md')));
    final claudeContent = File(
      '${packageRepository.path}/CLAUDE.md',
    ).readAsStringSync();
    expect(claudeContent, startsWith('@AGENTS.md\n\n# Upstream Claude Notes'));
    expect(claudeContent, contains('Prefer the upstream release workflow.'));
    final status = await runGit(packageRepository, ['status', '--porcelain']);
    expect(status.stdout.toString(), contains('M  AGENTS.md'));
    expect(status.stdout.toString(), contains('M  CLAUDE.md'));
    final mainAgents = await runGit(packageRepository, [
      'show',
      'main:AGENTS.md',
    ]);
    expect(
      mainAgents.stdout.toString(),
      '# Upstream Agent Notes\n\nKeep the public Dart API stable.\n',
    );
    final mainClaude = await runGit(packageRepository, [
      'show',
      'main:CLAUDE.md',
    ]);
    expect(
      mainClaude.stdout.toString(),
      '# Upstream Claude Notes\n\nPrefer the upstream release workflow.\n',
    );
    expect(stderr, isEmpty);
  });

  test(
    'uses --package-path as a package path inside an upstream repository',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      final upstream = await createUpstreamWorkspaceRepository(
        Directory('${environment.homeDirectory.path}/upstream_workspace'),
      );
      final packageRepository = Directory(
        '${environment.homeDirectory.path}/package_workspace',
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
            'package',
            'create',
            upstream.path,
            '--package-path',
            'packages/camera/camera',
            '--output',
            packageRepository.path,
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
        '${packageRepository.path}/fluoh.yaml',
      ).readAsStringSync();
      expect(manifest, contains('packages:\n  camera:'));
      expect(manifest, contains('path: packages/camera/camera'));
      expect(stderr, isEmpty);
    },
  );

  test(
    'uses the upstream repository name when the root package has siblings',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      final upstream = await createUpstreamPackageRepository(
        Directory('${environment.homeDirectory.path}/flutter-widgets-root'),
      );
      await _addWorkspacePackage(
        upstream,
        path: 'packages/share_plus/share_plus',
        name: 'share_plus',
        version: '9.0.0',
      );
      final packageRepository = Directory(
        '${environment.workingDirectory.path}/flutter-widgets-root',
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
          ['package', 'create', upstream.path, '--sdk', '3.35.8-ohos-0.0.3'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      expect(packageRepository.existsSync(), isTrue);
      final manifest = File(
        '${packageRepository.path}/fluoh.yaml',
      ).readAsStringSync();
      expect(manifest, contains('name: flutter-widgets-root'));
      expect(
        manifest,
        contains('url: https://github.com/FlutterOH/flutter-widgets-root.git'),
      );
      expect(manifest, contains('packages:\n  camera:'));
      expect(manifest, isNot(contains('  share_plus:')));
      final guide = File(
        '${packageRepository.path}/FLUOH.md',
      ).readAsStringSync();
      expect(guide, contains('fluoh package check'));
      expect(guide, contains('`fluoh package release`'));
      expect(
        stdout,
        contains('Created package repository at ${packageRepository.path}.'),
      );
      expect(stderr, isEmpty);
    },
  );

  test(
    'keeps upstream repository default output while selecting a package path',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      final upstream = await createUpstreamWorkspaceRepository(
        Directory('${environment.homeDirectory.path}/flutter-widgets'),
        packagePath: 'packages/syncfusion_flutter_pdf',
        packageName: 'syncfusion_flutter_pdf',
      );
      final packageRepository = Directory(
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
            'package',
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

      expect(packageRepository.existsSync(), isTrue);
      final manifest = File(
        '${packageRepository.path}/fluoh.yaml',
      ).readAsStringSync();
      expect(manifest, contains('packages:\n  syncfusion_flutter_pdf:'));
      expect(manifest, contains('path: packages/syncfusion_flutter_pdf'));
      expect(
        stdout,
        contains('Created package repository at ${packageRepository.path}.'),
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
    'creates a package collection implementation with multiple package paths',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      final upstream = await createUpstreamWorkspaceRepository(
        Directory('${environment.homeDirectory.path}/upstream_multi_package'),
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
        '${environment.homeDirectory.path}/package_multi_package',
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
      expect(createResult, 0);

      final manifest = File(
        '${packageRepository.path}/fluoh.yaml',
      ).readAsStringSync();
      expect(manifest, contains('packages:\n  camera:'));
      expect(manifest, contains('  share_plus:'));
      expect(manifest, contains('path: packages/camera/camera'));
      expect(manifest, contains('path: packages/share_plus/share_plus'));
      const packages = [
        _GuidancePackage(
          name: 'camera',
          version: '0.11.0',
          path: 'packages/camera/camera',
        ),
        _GuidancePackage(
          name: 'share_plus',
          version: '9.0.0',
          path: 'packages/share_plus/share_plus',
        ),
      ];
      final guide = File(
        '${packageRepository.path}/FLUOH.md',
      ).readAsStringSync();
      _expectImplementationGuide(guide, packages: packages);
      final agents = File(
        '${packageRepository.path}/AGENTS.md',
      ).readAsStringSync();
      _expectAgentsInstructions(agents, packages: packages);
      expect(stderr, isEmpty);
    },
  );

  test(
    'adds another package to an existing package collection implementation',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      final upstream = await createUpstreamWorkspaceRepository(
        Directory('${environment.homeDirectory.path}/upstream_add_package'),
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
        '${environment.homeDirectory.path}/package_add_package',
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

      final packageEnvironment = FluohEnvironment(
        homeDirectory: environment.homeDirectory,
        workingDirectory: packageRepository,
      );
      expect(
        await runFluoh(
          ['package', 'add', 'packages/share_plus/share_plus'],
          environment: packageEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final manifest = File(
        '${packageRepository.path}/fluoh.yaml',
      ).readAsStringSync();
      expect(manifest, contains('packages:\n  camera:'));
      expect(manifest, contains('  share_plus:'));
      const packages = [
        _GuidancePackage(
          name: 'camera',
          version: '0.11.0',
          path: 'packages/camera/camera',
        ),
        _GuidancePackage(
          name: 'share_plus',
          version: '9.0.0',
          path: 'packages/share_plus/share_plus',
        ),
      ];
      final guide = File(
        '${packageRepository.path}/FLUOH.md',
      ).readAsStringSync();
      _expectImplementationGuide(guide, packages: packages);
      final agents = File(
        '${packageRepository.path}/AGENTS.md',
      ).readAsStringSync();
      _expectAgentsInstructions(agents, packages: packages);
      expect(agents, isNot(contains('Upstream branch at creation')));
      final changelog = File(
        '${packageRepository.path}/FLUOH_CHANGELOG.md',
      ).readAsStringSync();
      _expectChangelogEntry(changelog, 'share_plus-9.0.0-ohos-3.35-0.1.0');
      final status = await runGit(packageRepository, ['status', '--porcelain']);
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
    },
  );

  test('rolls back example setup when package add fails later', () async {
    final environment = await createTestEnvironment();
    final source = await _createPackageCreateSdkSource(
      environment.homeDirectory,
      logName: 'package_add_rollback_flutter_args.log',
    );
    final upstream = await createUpstreamWorkspaceRepository(
      Directory('${environment.homeDirectory.path}/upstream_add_rollback'),
      packagePath: 'packages/camera/camera',
      packageName: 'camera',
    );
    await _addWorkspaceFlutterPackage(
      upstream,
      path: 'packages/share_plus/share_plus',
      name: 'share_plus',
      version: '9.0.0',
    );
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_add_rollback',
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
    await File('${packageRepository.path}/AGENTS.md').delete();
    await Directory('${packageRepository.path}/AGENTS.md').create();
    await File(
      '${packageRepository.path}/AGENTS.md/README.md',
    ).writeAsString('blocked\n');
    await runGit(packageRepository, ['add', '-A', 'AGENTS.md']);
    await runGit(packageRepository, [
      'commit',
      '-m',
      'Make AGENTS path unwritable',
    ]);

    final packageEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    expect(
      await runFluoh(
        ['package', 'add', 'packages/share_plus/share_plus'],
        environment: packageEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );
    expect(
      stderr.join('\n'),
      contains('Failed to update package repository files'),
    );

    final example = Directory(
      '${packageRepository.path}/packages/share_plus/share_plus/example',
    );
    expect(Directory('${example.path}/ohos').existsSync(), isFalse);
    expect(File('${example.path}/fluoh.yaml').existsSync(), isFalse);
    expect(File('${example.path}/.gitignore').existsSync(), isFalse);
    expect(Directory('${example.path}/.fluoh').existsSync(), isFalse);
    final status = await runGit(packageRepository, ['status', '--porcelain']);
    expect(status.stdout.toString().trim(), isEmpty);
  });

  test('requires a selected package for nested package upstreams', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamWorkspaceRepository(
      Directory(
        '${environment.homeDirectory.path}/upstream_unselected_workspace',
      ),
    );
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_unselected_workspace',
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
          'package',
          'create',
          upstream.path,
          '--output',
          packageRepository.path,
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
      stderr.join('\n'),
      contains('For packages below the root, select package paths'),
    );
    expect(stderr.join('\n'), contains('--package-path <package-path>'));
    expect(packageRepository.existsSync(), isFalse);
  });

  test(
    'uses an explicit package repository URL when provided with --repository',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      final upstream = await createUpstreamPackageRepository(
        Directory('${environment.homeDirectory.path}/upstream_custom_remote'),
      );
      final packageRepository = Directory(
        '${environment.homeDirectory.path}/package_custom_remote',
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
            'package',
            'create',
            upstream.path,
            '--output',
            packageRepository.path,
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

      final origin = await runGit(packageRepository, [
        'remote',
        'get-url',
        'origin',
      ]);
      final manifest = File(
        '${packageRepository.path}/fluoh.yaml',
      ).readAsStringSync();
      expect(
        origin.stdout.toString().trim(),
        'git@github.com:FlutterOH/camera.git',
      );
      expect(manifest, contains('url: git@github.com:FlutterOH/camera.git'));
      expect(stderr, isEmpty);
    },
  );

  test('accepts -r for explicit package repository URLs', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamPackageRepository(
      Directory('${environment.homeDirectory.path}/upstream_repo_aliases'),
    );
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_repo_alias_short',
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
          'package',
          'create',
          upstream.path,
          '--output',
          packageRepository.path,
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

    final origin = await runGit(packageRepository, [
      'remote',
      'get-url',
      'origin',
    ]);
    expect(
      origin.stdout.toString().trim(),
      'git@github.com:FlutterOH/camera-short.git',
    );
    expect(stderr, isEmpty);
  });

  test(
    'package create leaves upstream default branch tree unchanged',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      final upstream = await createUpstreamPackageRepository(
        Directory('${environment.homeDirectory.path}/upstream_clean_main'),
      );
      final packageRepository = Directory(
        '${environment.homeDirectory.path}/package_clean_main',
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
            'package',
            'create',
            upstream.path,
            '--output',
            packageRepository.path,
            '--sdk',
            '3.35.8-ohos-0.0.3',
          ],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final mainFiles = await runGit(packageRepository, [
        'ls-tree',
        '-r',
        '--name-only',
        'main',
      ]);
      expect(mainFiles.stdout.toString(), isNot(contains('fluoh.yaml')));
      expect(mainFiles.stdout.toString(), isNot(contains('FLUOH.md')));
      expect(
        mainFiles.stdout.toString(),
        isNot(contains('FLUOH_CHANGELOG.md')),
      );
      expect(mainFiles.stdout.toString(), isNot(contains('AGENTS.md')));
      expect(stderr, isEmpty);
    },
  );

  test('selects the latest stable SDK when --sdk is omitted', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
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
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_default_sdk',
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
          'package',
          'create',
          upstream.path,
          '--output',
          packageRepository.path,
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final branch = await runGit(packageRepository, [
      'branch',
      '--show-current',
    ]);
    final manifest = File(
      '${packageRepository.path}/fluoh.yaml',
    ).readAsStringSync();
    expect(branch.stdout.toString().trim(), 'ohos/3.35');
    expect(manifest, contains('sdk:\n  version: 3.35.8-ohos-0.0.4'));
    expect(stderr, isEmpty);
  });

  test('fails before cloning when destination already exists', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamPackageRepository(
      Directory('${environment.homeDirectory.path}/upstream_existing_dest'),
    );
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_existing_dest',
    );
    await packageRepository.create(recursive: true);
    await File('${packageRepository.path}/README.md').writeAsString('existing');
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
          'package',
          'create',
          upstream.path,
          '--output',
          packageRepository.path,
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
      File('${packageRepository.path}/README.md').readAsStringSync(),
      'existing',
    );
    expect(stderr.join('\n'), contains('Destination already exists'));
  });

  test('requires Git author name and email together', () async {
    final environment = await createTestEnvironment();
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_missing_author_email',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        [
          'package',
          'create',
          'https://github.com/example/camera.git',
          '--output',
          packageRepository.path,
          '--git-author-name',
          'FlutterOH Adapter',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );

    expect(
      stderr.join('\n'),
      contains('Pass both --git-author-name and --git-author-email'),
    );
    expect(packageRepository.existsSync(), isFalse);
  });

  test('does not accept --package for package create', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamPackageRepository(
      Directory('${environment.homeDirectory.path}/upstream_package_option'),
    );
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_option',
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
          'package',
          'create',
          upstream.path,
          '--package',
          'share_plus',
          '--output',
          packageRepository.path,
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
    expect(Directory('${packageRepository.path}/.git').existsSync(), isFalse);
  });
}

class _GuidancePackage {
  const _GuidancePackage({
    required this.name,
    required this.version,
    required this.path,
  });

  final String name;
  final String version;
  final String path;

  String get examplePath => path == '.' ? 'example' : '$path/example';

  String get checkCommand => path == '.'
      ? 'fluoh package check'
      : 'fluoh package check --package $name';

  String get releaseCommand => path == '.'
      ? 'fluoh package release'
      : 'fluoh package release --package $name';
}

void _expectImplementationGuide(
  String content, {
  required List<_GuidancePackage> packages,
}) {
  _expectMarkdownHeadings(content, [
    '# FlutterOH Implementation',
    if (packages.length > 1) '## Packages',
    '## Metadata',
    '## Adaptation Checklist',
    '## Next Steps',
    '## Adaptation Workflow',
    '## Release Readiness',
    '## Before Commit',
  ]);
  _expectContainsAll(content, [
    'fluoh.yaml',
    'repository.git.branch',
    'upstream.git',
    'FLUOH_CHANGELOG.md',
    'fluoh help',
    'fluoh help package',
    'fluoh help package check',
    'fluoh doctor --json --strict',
    'fluoh deps get',
    'fluoh flutter analyze',
    'fluoh flutter build hap --debug',
    '--auto-sign',
    '--run-example',
    '--start-emulator',
    '--json',
    'diagnostics',
    'Device-only behavior',
    'git status --short --ignored=matching',
  ]);
  if (packages.length > 1) {
    _expectContainsAll(content, [
      'packages.<name>',
      'fluoh package check --package <name>',
      'fluoh package release --all',
    ]);
  }

  for (final package in packages) {
    _expectContainsAll(content, [
      package.name,
      package.examplePath,
      package.checkCommand,
      package.releaseCommand,
    ]);
    if (packages.length > 1) {
      expect(content, contains(package.version));
    }
    if (package.path != '.') {
      expect(content, contains(package.path));
    } else {
      expect(content, contains('packages.${package.name}'));
    }
  }
}

void _expectAgentsInstructions(
  String content, {
  required List<_GuidancePackage> packages,
}) {
  _expectMarkdownHeadings(content, [
    '# AGENTS.md',
    '## FlutterOH Context',
    if (packages.length > 1) '## Packages',
    '## Working Rules',
    '## Stop and Ask',
    '## Diagnostics Routing',
    '## Adaptation Workflow',
    '## Definition of Done',
    '## Completion Report',
    '## Final Response',
    '## Local Commit Checkpoints',
    '## Before Commit',
  ]);
  _expectContainsAll(content, [
    'fluoh.yaml',
    'repository.git.branch',
    'upstream.git',
    'FLUOH_CHANGELOG.md',
    'fluoh help',
    'fluoh help package',
    'fluoh help package check',
    'fluoh doctor --json --strict',
    'fluoh deps get',
    'fluoh flutter analyze',
    '--auto-sign',
    '--run-example',
    '--start-emulator',
    '--json',
    'diagnostics',
    'stdoutTail',
    'ohos.signing_profile_failed',
    'ohos.direct_sign_failed',
    '.fluoh/ai-report-',
    'YYYYMMDD-HHMMSS',
    'Release recommendation:',
    'ohos.runtime_crash',
    'ohos.install_failed',
    'Do not invent OHOS APIs',
    'changed files',
    'device-only verification',
    'git status --short --ignored=matching',
    'git config --local --get user.name',
    '--git-author-name',
    'DEVELOPMENT_TEAM',
    'PROVISIONING_PROFILE_SPECIFIER',
  ]);
  if (packages.length > 1) {
    _expectContainsAll(content, [
      'packages.<name>',
      'fluoh package check --package <name>',
      'fluoh package release --all',
    ]);
  }

  for (final package in packages) {
    _expectContainsAll(content, [
      package.name,
      package.examplePath,
      package.checkCommand,
      package.releaseCommand,
    ]);
    if (packages.length > 1) {
      expect(content, contains(package.version));
    }
    if (package.path != '.') {
      expect(content, contains(package.path));
    } else {
      expect(content, contains('packages.${package.name}'));
    }
  }
}

void _expectChangelogEntry(String content, String tag) {
  final heading = '## $tag';
  final start = content.indexOf(heading);
  expect(start, isNot(-1), reason: 'Expected changelog entry $heading.');

  final next = content.indexOf('\n## ', start + heading.length);
  final entry = content
      .substring(start + heading.length, next == -1 ? content.length : next)
      .trim();
  expect(entry, isNotEmpty);
  expect(entry.split('\n').any((line) => line.trim().startsWith('- ')), isTrue);
}

void _expectMarkdownHeadings(String content, Iterable<String> expected) {
  final headings = content
      .split('\n')
      .where((line) => line.startsWith('#'))
      .toSet();
  for (final heading in expected) {
    expect(headings, contains(heading), reason: 'Missing heading $heading.');
  }
}

void _expectContainsAll(String content, Iterable<String> expected) {
  for (final value in expected) {
    expect(content, contains(value), reason: 'Expected to find "$value".');
  }
}

Future<void> _addWorkspacePackage(
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

Future<void> _addWorkspaceFlutterPackage(
  Directory repository, {
  required String path,
  required String name,
  required String version,
}) async {
  final package = Directory('${repository.path}/$path');
  await Directory('${package.path}/lib').create(recursive: true);
  await Directory('${package.path}/example/lib').create(recursive: true);
  await File('${package.path}/pubspec.yaml').writeAsString('''
name: $name
version: $version

environment:
  sdk: ^3.0.0

dependencies:
  flutter:
    sdk: flutter
''');
  await File(
    '${package.path}/lib/$name.dart',
  ).writeAsString('library $name;\n');
  await File('${package.path}/example/pubspec.yaml').writeAsString('''
name: ${name}_example

environment:
  sdk: ^3.0.0

dependencies:
  flutter:
    sdk: flutter
  $name:
    path: ..

dev_dependencies:
  flutter_test:
    sdk: flutter
''');
  await File('${package.path}/example/lib/main.dart').writeAsString('''
import 'package:flutter/widgets.dart';

void main() {
  runApp(const Placeholder());
}
''');
  await runGit(repository, ['add', path]);
  await runGit(repository, ['commit', '-m', 'Add $name Flutter fixture']);
}

Future<Directory> _createPackageCreateSdkSource(
  Directory parent, {
  required String logName,
}) async {
  final source = Directory('${parent.path}/flutter_sdk_source_$logName');
  final sdkRepository = Directory('${parent.path}/flutter_sdk_$logName');
  await sdkRepository.create(recursive: true);
  await _runProcess('git', ['init', '--initial-branch=main'], sdkRepository);
  await _runProcess('git', [
    'config',
    'user.email',
    'fixture@example.com',
  ], sdkRepository);
  await _runProcess('git', ['config', 'user.name', 'Fixture'], sdkRepository);
  final flutter = File('${sdkRepository.path}/bin/flutter');
  await flutter.parent.create(recursive: true);
  await flutter.writeAsString(_fakeFlutterScript('${parent.path}/$logName'));
  await _runProcess('chmod', ['+x', flutter.path], sdkRepository);
  await File('${sdkRepository.path}/README.md').writeAsString('# SDK\n');
  await _runProcess('git', ['add', '.'], sdkRepository);
  await _runProcess('git', ['commit', '-m', 'Initial SDK'], sdkRepository);
  await _runProcess('git', ['tag', '3.35.8-ohos-0.0.3'], sdkRepository);
  await writeSdkSourceFixture(
    source,
    sdkRepository: sdkRepository.path,
    releases: {'3.35.8-ohos-0.0.3': 'stable'},
  );
  return source;
}

String _fakeFlutterScript(String logPath) {
  return '''
#!/bin/sh
printf "%s::%s\\n" "\$(pwd)" "\$*" >> "$logPath"
if [ "\$1" = "create" ]; then
  printf "flutter create stdout\\n"
  printf "flutter create stderr\\n" >&2
  target=""
  platforms=""
  while [ "\$#" -gt 0 ]; do
    case "\$1" in
      --platforms=*) platforms="\${1#--platforms=}" ;;
      --project-name) shift ;;
      --no-pub) ;;
      create) ;;
      *) target="\$1" ;;
    esac
    shift
  done
  mkdir -p "\$target/lib"
  old_ifs="\$IFS"
  IFS=,
  for platform in \$platforms; do
    mkdir -p "\$target/\$platform"
    printf "{}\\n" > "\$target/\$platform/build-profile.json5"
  done
  IFS="\$old_ifs"
fi
exit 0
''';
}

Future<Directory> _createUpstreamFlutterPluginRepository(Directory repo) async {
  await repo.create(recursive: true);
  await _runProcess('git', ['init', '--initial-branch=main'], repo);
  await _runProcess('git', [
    'config',
    'user.email',
    'fixture@example.com',
  ], repo);
  await _runProcess('git', ['config', 'user.name', 'Fixture'], repo);
  await Directory('${repo.path}/lib').create(recursive: true);
  await Directory('${repo.path}/example/lib').create(recursive: true);
  await File('${repo.path}/lib/camera.dart').writeAsString('library camera;\n');
  await File('${repo.path}/pubspec.yaml').writeAsString('''
name: camera
version: 0.11.0

environment:
  sdk: ^3.0.0

dependencies:
  flutter:
    sdk: flutter

flutter:
  plugin:
    platforms:
      android:
        package: dev.flutter.camera
        pluginClass: CameraPlugin
      ios:
        pluginClass: CameraPlugin
''');
  await File('${repo.path}/example/pubspec.yaml').writeAsString('''
name: camera_example

environment:
  sdk: ^3.0.0

dependencies:
  flutter:
    sdk: flutter
  camera:
    path: ..

dev_dependencies:
  flutter_test:
    sdk: flutter
''');
  await File('${repo.path}/example/lib/main.dart').writeAsString('''
import 'package:flutter/widgets.dart';

void main() {
  runApp(const Placeholder());
}
''');
  await File('${repo.path}/LICENSE').writeAsString(_testLicenseContent);
  await _runProcess('git', ['add', '.'], repo);
  await _runProcess('git', ['commit', '-m', 'Initial Flutter plugin'], repo);
  return repo;
}

const _testLicenseContent = '''
MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software.
''';

Future<void> _runProcess(
  String executable,
  List<String> arguments,
  Directory workingDirectory,
) async {
  final result = await Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory.path,
  );
  if (result.exitCode != 0) {
    fail('$executable ${arguments.join(' ')} failed:\n${result.stderr}');
  }
}
