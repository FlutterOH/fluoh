import 'dart:convert';
import 'dart:io';

import 'package:fluoh/fluoh.dart';
import 'package:fluoh/src/package/package_repository_docs.dart';
import 'package:test/test.dart';

import '../helpers/fluoh_command_context.dart';
import '../helpers/package_test_context.dart';

void main() {
  test('README release badge handles GitHub URL variants', () {
    const variants = [
      'https://github.com/FlutterOH/camera',
      'https://github.com/FlutterOH/camera.git',
      'https://github.com/FlutterOH/camera/',
      'ssh://git@github.com/FlutterOH/camera.git',
      'git@github.com:FlutterOH/camera.git',
      'git@github.com:FlutterOH/camera.git/',
    ];

    for (final repositoryUrl in variants) {
      final content = packageReadmeAdaptationContent(
        packages: [
          PackageRepositoryDocPackage(
            name: 'camera',
            version: '0.11.0',
            packagePath: '.',
            repositoryUrl: repositoryUrl,
          ),
        ],
      );

      expect(
        content,
        contains(
          '[![Latest release](https://img.shields.io/github/v/tag/FlutterOH/camera?label=release&sort=date&filter=camera-*)](https://github.com/FlutterOH/camera/tags)',
        ),
        reason: repositoryUrl,
      );
    }
  });

  test('README release badge is omitted for non-GitHub repositories', () {
    final content = packageReadmeAdaptationContent(
      packages: const [
        PackageRepositoryDocPackage(
          name: 'camera',
          version: '0.11.0',
          packagePath: '.',
          repositoryUrl: '../camera',
        ),
      ],
    );

    expect(content, contains('## FlutterOH adaptation'));
    expect(content, isNot(contains('img.shields.io')));
    expect(content, isNot(contains('github.com')));
  });

  test(
    'README adaptation content handles missing and titleless README files',
    () {
      final created = updatedPackageReadmeAdaptationContent(
        packages: const [
          PackageRepositoryDocPackage(
            name: 'camera',
            version: '0.11.0',
            packagePath: '.',
          ),
        ],
        existing: null,
      );
      expect(created, startsWith('<!-- fluoh:generated:start'));
      expect(created, contains('## FlutterOH adaptation'));
      expect(created, contains('# camera'));
      expect(created, isNot(contains('0.11.0')));

      final titleless = updatedPackageReadmeAdaptationContent(
        packages: const [
          PackageRepositoryDocPackage(
            name: 'camera',
            version: '0.11.0',
            packagePath: '.',
          ),
        ],
        existing: 'Original upstream README body.\n',
      );
      expect(titleless, startsWith('<!-- fluoh:generated:start'));
      expect(titleless, contains('Original upstream README body.'));
    },
  );

  test('README adaptation content rejects multiple package descriptors', () {
    expect(
      () => packageReadmeAdaptationContent(
        packages: const [
          PackageRepositoryDocPackage(
            name: 'camera',
            version: '0.11.0',
            packagePath: 'packages/camera/camera',
          ),
          PackageRepositoryDocPackage(
            name: 'share_plus',
            version: '9.0.0',
            packagePath: 'packages/share_plus/share_plus',
          ),
        ],
      ),
      throwsStateError,
    );
  });

  test('refresh replaces generated blocks and preserves user content', () async {
    final environment = await createTestEnvironment();
    final packageRepository = await createPackageRepositoryFixture(environment);
    final readme = File('${packageRepository.path}/README.md');
    final guide = File('${packageRepository.path}/FLUOH.md');
    final agents = File('${packageRepository.path}/AGENTS.md');
    await readme.writeAsString('''
# camera

<!-- fluoh:generated:start id=package-readme-adaptation template=1 -->
## Old README Guidance
<!-- fluoh:generated:end id=package-readme-adaptation -->

Original upstream README body.
''');
    await guide.writeAsString('''
# Local Notes

Keep this hand-written note.

<!-- fluoh:generated:start id=package-implementation-guide template=1 -->
# Old Generated Guidance
<!-- fluoh:generated:end id=package-implementation-guide -->

## Maintainer Notes

Keep this footer.
''');
    await agents.writeAsString('''
# Upstream Agent Notes

Keep the public Dart API stable.

<!-- fluoh:generated:start id=package-agents-instructions template=1 -->
## Working Rules

Old generated agent guidance.
<!-- fluoh:generated:end id=package-agents-instructions -->
''');
    await runGit(packageRepository, [
      'add',
      'README.md',
      'FLUOH.md',
      'AGENTS.md',
    ]);
    await runGit(packageRepository, ['commit', '-m', 'Add generated guide']);
    final stdout = <String>[];
    final stderr = <String>[];
    final packageEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );

    final result = await runFluoh(
      ['package', 'docs', 'refresh'],
      environment: packageEnvironment,
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(result, 0);
    final readmeContent = readme.readAsStringSync();
    expect(readmeContent, startsWith('<!-- fluoh:generated:start'));
    expect(readmeContent, contains('## FlutterOH adaptation'));
    expect(readmeContent, contains('# camera'));
    expect(
      readmeContent,
      contains(
        '[![Latest release](https://img.shields.io/github/v/tag/FlutterOH/camera?label=release&sort=date&filter=camera-*)](https://github.com/FlutterOH/camera/tags)',
      ),
    );
    expect(readmeContent, contains('[fluoh.yaml](fluoh.yaml)'));
    expect(readmeContent, contains('[FLUOH.md](FLUOH.md)'));
    expect(readmeContent, contains('[FLUOH_CHANGELOG.md](FLUOH_CHANGELOG.md)'));
    expect(readmeContent, contains('`fluoh package check`'));
    expect(readmeContent, contains('Original upstream README body.'));
    expect(readmeContent, isNot(contains('Old README Guidance')));
    final content = guide.readAsStringSync();
    expect(content, contains('# Local Notes'));
    expect(content, contains('Keep this hand-written note.'));
    expect(content, contains('## Maintainer Notes'));
    expect(content, contains('Keep this footer.'));
    expect(content, isNot(contains('Old Generated Guidance')));
    expect(
      content,
      contains(
        '<!-- fluoh:generated:start id=package-implementation-guide '
        'template=1 -->',
      ),
    );
    expect(
      content,
      contains(
        'This section is generated by fluoh. Do not edit inside this block',
      ),
    );
    expect(
      content,
      contains('<!-- fluoh:generated:end id=package-implementation-guide -->'),
    );
    final agentsContent = agents.readAsStringSync();
    expect(agentsContent, contains('# Upstream Agent Notes'));
    expect(agentsContent, contains('Keep the public Dart API stable.'));
    expect(agentsContent, contains('## FlutterOH/OHOS Adaptation'));
    expect(agentsContent, contains('follow `FLUOH.md`'));
    expect(agentsContent, isNot(contains('## Working Rules')));
    expect(agentsContent, isNot(contains('Old generated agent guidance')));
    expect(agentsContent, isNot(contains('# AGENTS.md')));
    final status = await runGit(packageRepository, ['status', '--porcelain']);
    expect(status.stdout.toString(), contains(' M AGENTS.md'));
    expect(status.stdout.toString(), contains(' M FLUOH.md'));
    expect(status.stdout.toString(), contains(' M README.md'));
    expect(status.stdout.toString(), isNot(contains('M  FLUOH.md')));
    expect(stdout, contains('Refreshed package docs'));
    expect(stderr, isEmpty);
  });

  test('dry-run reports stale docs without requiring a clean tree', () async {
    final environment = await createTestEnvironment();
    final packageRepository = await createPackageRepositoryFixture(environment);
    final guide = File('${packageRepository.path}/FLUOH.md');
    final staleContent = '''
# Stale Guide
''';
    await guide.writeAsString(staleContent);
    final stdout = <String>[];
    final stderr = <String>[];
    final packageEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );

    final result = await runFluoh(
      ['package', 'docs', 'refresh', '--dry-run'],
      environment: packageEnvironment,
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(result, 0);
    expect(stdout, contains('Package docs would be refreshed'));
    expect(stdout.join('\n'), contains('FLUOH.md'));
    expect(guide.readAsStringSync(), staleContent);
    expect(stderr, isEmpty);
  });

  test('dry-run reports stale docs as json', () async {
    final environment = await createTestEnvironment();
    final packageRepository = await createPackageRepositoryFixture(environment);
    final guide = File('${packageRepository.path}/FLUOH.md');
    const staleContent = '''
# Stale Guide
''';
    await guide.writeAsString(staleContent);
    final stdout = <String>[];
    final stderr = <String>[];
    final packageEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );

    final result = await runFluoh(
      ['package', 'docs', 'refresh', '--dry-run', '--json'],
      environment: packageEnvironment,
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(result, 0);
    expect(stdout, hasLength(1));
    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('schema', 1));
    expect(report, containsPair('command', 'package docs refresh'));
    expect(report, containsPair('ok', true));
    expect(report, containsPair('exitCode', 0));
    expect(report, containsPair('dryRun', true));
    expect(report, containsPair('changed', true));
    expect(report, containsPair('applied', false));
    expect(report['files'], contains('FLUOH.md'));
    expect(guide.readAsStringSync(), staleContent);
    expect(stderr, isEmpty);
  });

  test(
    'refresh adds federated implementation route from current checkout',
    () async {
      final environment = await createTestEnvironment();
      final packageRepository = await createPackageRepositoryFixture(
        environment,
      );
      await File('${packageRepository.path}/pubspec.yaml').writeAsString('''
name: camera
version: 0.11.0

environment:
  sdk: ^3.0.0

dependencies:
  flutter:
    sdk: flutter
  camera_android: ^1.0.0
  camera_ios: ^1.0.0

flutter:
  plugin:
    platforms:
      android:
        default_package: camera_android
      ios:
        default_package: camera_ios
''');
      await File('${packageRepository.path}/FLUOH.md').writeAsString('''
# Local Notes

<!-- fluoh:generated:start id=package-implementation-guide template=1 -->
# Legacy Generated Guidance
<!-- fluoh:generated:end id=package-implementation-guide -->
''');
      await runGit(packageRepository, ['add', 'pubspec.yaml', 'FLUOH.md']);
      await runGit(packageRepository, [
        'commit',
        '-m',
        'Add legacy federated docs',
      ]);
      final stdout = <String>[];
      final stderr = <String>[];
      final packageEnvironment = FluohEnvironment(
        homeDirectory: environment.homeDirectory,
        workingDirectory: packageRepository,
      );

      final result = await runFluoh(
        ['package', 'docs', 'refresh'],
        environment: packageEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      );

      expect(result, 0);
      final guide = File(
        '${packageRepository.path}/FLUOH.md',
      ).readAsStringSync();
      expect(guide, contains('## Federated Implementation Route'));
      expect(
        guide,
        contains(
          'Create the OHOS implementation package `camera_ohos` at `camera_ohos`',
        ),
      );
      expect(guide, contains('Add `ohos.default_package: camera_ohos`'));
      expect(
        guide,
        contains(
          'Add dependency `camera_ohos` with relative path `camera_ohos`',
        ),
      );
      expect(stdout, contains('Refreshed package docs'));
      expect(stderr, isEmpty);
    },
  );

  test('refresh can allow a dirty worktree explicitly', () async {
    final environment = await createTestEnvironment();
    final packageRepository = await createPackageRepositoryFixture(environment);
    final manifest = File('${packageRepository.path}/fluoh.yaml');
    await manifest.writeAsString(
      manifest.readAsStringSync().replaceFirst(
        '    upstream:\n      version: 0.11.0',
        '    upstream:\n      version: 0.11.1',
      ),
    );
    await runGit(packageRepository, ['add', 'fluoh.yaml']);
    await runGit(packageRepository, [
      'commit',
      '-m',
      'Update upstream version',
    ]);
    await File(
      '${packageRepository.path}/LOCAL_NOTES.md',
    ).writeAsString('local notes\n');
    final packageEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    final defaultStdout = <String>[];
    final defaultStderr = <String>[];

    expect(
      await runFluoh(
        ['package', 'docs', 'refresh'],
        environment: packageEnvironment,
        stdout: defaultStdout.add,
        stderr: defaultStderr.add,
      ),
      64,
    );
    expect(
      [...defaultStdout, ...defaultStderr].join('\n'),
      contains('Package docs refresh requires a clean working tree.'),
    );

    final stdout = <String>[];
    final stderr = <String>[];
    expect(
      await runFluoh(
        ['package', 'docs', 'refresh', '--allow-dirty', '--json'],
        environment: packageEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('changed', true));
    expect(report, containsPair('applied', true));
    expect(report, containsPair('allowDirty', true));
    expect(report['files'], contains('FLUOH.md'));
    expect(
      File('${packageRepository.path}/FLUOH.md').readAsStringSync(),
      contains('- Upstream version: `0.11.1`'),
    );
    expect(File('${packageRepository.path}/LOCAL_NOTES.md').existsSync(), true);
    expect(stderr, isEmpty);
  });

  test(
    'refresh updates generated docs after upstream version changes',
    () async {
      final environment = await createTestEnvironment();
      final packageRepository = await createPackageRepositoryFixture(
        environment,
      );
      final manifest = File('${packageRepository.path}/fluoh.yaml');
      await manifest.writeAsString(
        manifest.readAsStringSync().replaceFirst(
          '    upstream:\n      version: 0.11.0',
          '    upstream:\n      version: 0.11.1',
        ),
      );
      await runGit(packageRepository, ['add', 'fluoh.yaml']);
      await runGit(packageRepository, [
        'commit',
        '-m',
        'Update upstream version',
      ]);
      final stdout = <String>[];
      final stderr = <String>[];
      final packageEnvironment = FluohEnvironment(
        homeDirectory: environment.homeDirectory,
        workingDirectory: packageRepository,
      );

      final result = await runFluoh(
        ['package', 'docs', 'refresh'],
        environment: packageEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      );

      expect(result, 0);
      expect(stdout, contains('Refreshed package docs'));
      expect(stdout.join('\n'), contains('FLUOH.md'));
      expect(stdout.join('\n'), isNot(contains('AGENTS.md')));
      expect(
        File('${packageRepository.path}/FLUOH.md').readAsStringSync(),
        contains('- Upstream version: `0.11.1`'),
      );
      expect(
        File('${packageRepository.path}/AGENTS.md').readAsStringSync(),
        contains(
          'For FlutterOH/OHOS package adaptation tasks, follow `FLUOH.md`.',
        ),
      );
      expect(stderr, isEmpty);
    },
  );

  test(
    'refresh creates an initial changelog only when it is missing',
    () async {
      final environment = await createTestEnvironment();
      final packageRepository = await createPackageRepositoryFixture(
        environment,
      );
      final changelog = File('${packageRepository.path}/FLUOH_CHANGELOG.md');
      await changelog.delete();
      await runGit(packageRepository, ['add', 'FLUOH_CHANGELOG.md']);
      await runGit(packageRepository, ['commit', '-m', 'Remove changelog']);
      final stdout = <String>[];
      final stderr = <String>[];
      final packageEnvironment = FluohEnvironment(
        homeDirectory: environment.homeDirectory,
        workingDirectory: packageRepository,
      );

      final result = await runFluoh(
        ['package', 'docs', 'refresh'],
        environment: packageEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      );

      expect(result, 0);
      final content = changelog.readAsStringSync();
      expect(content, startsWith('# FlutterOH Changelog'));
      expect(content, contains('## camera-0.11.0-ohos-3.35-0.1.0'));
      expect(content, contains('TODO: Replace this generated placeholder'));
      expect(content, isNot(contains('Initial OHOS implementation')));
      expect(stdout, contains('Refreshed package docs'));
      expect(stderr, isEmpty);
    },
  );
}
