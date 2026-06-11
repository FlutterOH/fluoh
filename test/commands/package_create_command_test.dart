import 'dart:convert';
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
            '--repository-name',
            'camera',
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
      expect(branch.stdout.toString().trim(), 'ohos/3.35/camera');
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
      expect(manifestContent, contains('kind: package'));
      expect(manifestContent, contains('package:\n  name: camera'));
      expect(manifestContent, isNot(contains('implementation:')));
      expect(manifestContent, isNot(contains('dependency:')));
      expect(manifestContent, isNot(contains('dependencyPolicy:')));
      expect(manifestContent, isNot(contains('fluoh:')));
      expect(manifestContent, isNot(contains('flutteroh:')));
      expect(manifestContent, isNot(contains('replacement:')));
      expect(manifestContent, isNot(contains('ref:')));
      expect(manifestContent, isNot(contains('sdkVersion:')));
      expect(manifestContent, isNot(contains('tag:')));
      expect(packageManifest.name, 'camera');
      expect(packageManifest.sdkVersion, '3.35.8-ohos-0.0.3');
      expect(
        packageManifest.repositoryUrl,
        'https://github.com/FlutterOH/camera.git',
      );
      expect(packageManifest.repositoryBranch, 'ohos/3.35/camera');
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
      expect(
        releaseNotesContent,
        contains('TODO: Replace this generated placeholder'),
      );
      expect(
        releaseNotesContent,
        isNot(contains('Initial OHOS implementation')),
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
      final readme = File('${packageRepository.path}/README.md');
      expect(readme.existsSync(), isTrue);
      final readmeContent = readme.readAsStringSync();
      expect(readmeContent, startsWith('<!-- fluoh:generated:start'));
      expect(readmeContent, contains('# camera'));
      _expectReadmeAdaptation(
        readmeContent,
        package: const _GuidancePackage(
          name: 'camera',
          version: '0.11.0',
          path: '.',
        ),
      );
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
      expect(status.stdout.toString(), contains('M  README.md'));
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
          'README.md',
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
      _expectWrappedContainsAll(stdout.join('\n'), [
        'Created package repository at ${packageRepository.path}',
        'Configured FlutterOH SDK 3.35.8-ohos-0.0.3',
        'Created release tag camera-0.11.0-ohos-3.35-0.1.0',
      ]);
      expect(
        stderr.join('\n'),
        contains('still contains TODO placeholder release notes'),
      );
    },
  );

  test('uses latest package release tag instead of monorepo HEAD', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamWorkspaceRepository(
      Directory('${environment.homeDirectory.path}/upstream_packages'),
      version: '0.10.0',
    );
    await runGit(upstream, ['tag', 'camera-v0.10.0']);
    await bumpUpstreamPackageVersion(
      upstream,
      packagePath: 'packages/camera/camera',
      version: '0.11.0',
    );
    await runGit(upstream, ['tag', 'camera-v0.11.0']);
    await bumpUpstreamPackageVersion(
      upstream,
      packagePath: 'packages/camera/camera',
      version: '0.12.0',
    );
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_camera_from_tag',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'add', 'fixture', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );

    final exitCode = await runFluoh(
      [
        'package',
        'create',
        upstream.path,
        '--repository-name',
        'camera',
        '--output',
        packageRepository.path,
        '--sdk',
        '3.35.8-ohos-0.0.3',
        '--package-path',
        'packages/camera/camera',
      ],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    if (exitCode != 0) {
      fail(
        'package create exited $exitCode\nstdout:\n${stdout.join('\n')}\n'
        'stderr:\n${stderr.join('\n')}',
      );
    }

    final manifestContent = File(
      '${packageRepository.path}/fluoh.yaml',
    ).readAsStringSync();
    final manifest = await readPackageManifest(packageRepository);
    final packagePubspec = File(
      '${packageRepository.path}/packages/camera/camera/pubspec.yaml',
    ).readAsStringSync();
    final head = await runGit(packageRepository, ['rev-parse', 'HEAD']);
    final releaseHead = await runGit(packageRepository, [
      'rev-parse',
      'camera-v0.11.0^{commit}',
    ]);
    final status = await runGit(packageRepository, ['status', '--porcelain']);

    expect(manifest.primaryPackage.upstreamVersion, '0.11.0');
    expect(manifest.primaryPackage.upstreamRef, 'camera-v0.11.0');
    expect(
      manifestContent,
      contains(
        '    upstream:\n'
        '      version: 0.11.0\n'
        '      ref: camera-v0.11.0',
      ),
    );
    expect(packagePubspec, contains('version: 0.11.0'));
    expect(packagePubspec, isNot(contains('version: 0.12.0')));
    expect(head.stdout.toString().trim(), releaseHead.stdout.toString().trim());
    expect(
      status.stdout.toString().split('\n'),
      isNot(contains(' M packages/camera/camera/pubspec.yaml')),
    );
    expect(stderr, isEmpty);
  });

  test('uses latest underscore package release tag', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamWorkspaceRepository(
      Directory('${environment.homeDirectory.path}/upstream_underscore_tag'),
      version: '0.10.0',
    );
    await runGit(upstream, ['tag', 'camera-v0.10.0']);
    await bumpUpstreamPackageVersion(
      upstream,
      packagePath: 'packages/camera/camera',
      version: '0.11.0',
    );
    await runGit(upstream, ['tag', 'camera-v0.11.0']);
    await bumpUpstreamPackageVersion(
      upstream,
      packagePath: 'packages/camera/camera',
      version: '0.12.0',
    );
    await runGit(upstream, ['tag', 'camera_v0.12.0']);
    await bumpUpstreamPackageVersion(
      upstream,
      packagePath: 'packages/camera/camera',
      version: '0.13.0',
    );
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_underscore_tag',
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
          '--repository-name',
          'camera',
          '--output',
          packageRepository.path,
          '--sdk',
          '3.35.8-ohos-0.0.3',
          '--package-path',
          'packages/camera/camera',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final manifest = await readPackageManifest(packageRepository);
    final packagePubspec = File(
      '${packageRepository.path}/packages/camera/camera/pubspec.yaml',
    ).readAsStringSync();
    final head = await runGit(packageRepository, ['rev-parse', 'HEAD']);
    final releaseHead = await runGit(packageRepository, [
      'rev-parse',
      'camera_v0.12.0^{commit}',
    ]);

    expect(manifest.primaryPackage.upstreamVersion, '0.12.0');
    expect(manifest.primaryPackage.upstreamRef, 'camera_v0.12.0');
    expect(packagePubspec, contains('version: 0.12.0'));
    expect(packagePubspec, isNot(contains('version: 0.13.0')));
    expect(head.stdout.toString().trim(), releaseHead.stdout.toString().trim());
    expect(stderr, isEmpty);
  });

  test('uses explicit upstream package version for package create', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamWorkspaceRepository(
      Directory('${environment.homeDirectory.path}/upstream_explicit_version'),
      version: '0.10.0',
    );
    await runGit(upstream, ['tag', 'camera-v0.10.0']);
    await bumpUpstreamPackageVersion(
      upstream,
      packagePath: 'packages/camera/camera',
      version: '0.11.0',
    );
    await runGit(upstream, ['tag', 'camera-v0.11.0']);
    await bumpUpstreamPackageVersion(
      upstream,
      packagePath: 'packages/camera/camera',
      version: '0.12.0',
    );
    await Directory(
      '${upstream.path}/packages/camera/camera',
    ).delete(recursive: true);
    await runGit(upstream, ['add', '-A', 'packages/camera/camera']);
    await runGit(upstream, ['commit', '-m', 'Remove camera package']);
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_explicit_version',
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
          '--repository-name',
          'camera',
          '--output',
          packageRepository.path,
          '--sdk',
          '3.35.8-ohos-0.0.3',
          '--package-path',
          'packages/camera/camera',
          '--upstream-version',
          '0.10.0',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final manifest = await readPackageManifest(packageRepository);
    final packagePubspec = File(
      '${packageRepository.path}/packages/camera/camera/pubspec.yaml',
    ).readAsStringSync();
    final head = await runGit(packageRepository, ['rev-parse', 'HEAD']);
    final releaseHead = await runGit(packageRepository, [
      'rev-parse',
      'camera-v0.10.0^{commit}',
    ]);
    expect(manifest.primaryPackage.upstreamVersion, '0.10.0');
    expect(manifest.primaryPackage.upstreamRef, 'camera-v0.10.0');
    expect(packagePubspec, contains('version: 0.10.0'));
    expect(packagePubspec, isNot(contains('version: 0.12.0')));
    expect(head.stdout.toString().trim(), releaseHead.stdout.toString().trim());
    expect(stderr, isEmpty);
  });

  test('uses latest upstream package tag removed from main', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamWorkspaceRepository(
      Directory(
        '${environment.homeDirectory.path}/upstream_removed_latest_tag',
      ),
      version: '0.10.0',
    );
    await runGit(upstream, ['tag', 'camera-v0.10.0']);
    await bumpUpstreamPackageVersion(
      upstream,
      packagePath: 'packages/camera/camera',
      version: '0.11.0',
    );
    await runGit(upstream, ['tag', 'camera-v0.11.0']);
    await Directory(
      '${upstream.path}/packages/camera/camera',
    ).delete(recursive: true);
    await runGit(upstream, ['add', '-A', 'packages/camera/camera']);
    await runGit(upstream, ['commit', '-m', 'Remove camera package']);
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_removed_latest_tag',
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
          '--repository-name',
          'camera',
          '--output',
          packageRepository.path,
          '--sdk',
          '3.35.8-ohos-0.0.3',
          '--package-path',
          'packages/camera/camera',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final manifest = await readPackageManifest(packageRepository);
    final packagePubspec = File(
      '${packageRepository.path}/packages/camera/camera/pubspec.yaml',
    ).readAsStringSync();
    final head = await runGit(packageRepository, ['rev-parse', 'HEAD']);
    final releaseHead = await runGit(packageRepository, [
      'rev-parse',
      'camera-v0.11.0^{commit}',
    ]);
    expect(manifest.primaryPackage.upstreamVersion, '0.11.0');
    expect(manifest.primaryPackage.upstreamRef, 'camera-v0.11.0');
    expect(packagePubspec, contains('version: 0.11.0'));
    expect(head.stdout.toString().trim(), releaseHead.stdout.toString().trim());
    expect(stderr, isEmpty);
  });

  test('keeps ignored files from upstream release tags', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamWorkspaceRepository(
      Directory('${environment.homeDirectory.path}/upstream_ignored_tag_file'),
      version: '0.11.0',
    );
    await File(
      '${upstream.path}/packages/camera/camera/generated.txt',
    ).writeAsString('release generated file\n');
    await runGit(upstream, ['add', 'packages/camera/camera/generated.txt']);
    await runGit(upstream, ['commit', '-m', 'Add release generated file']);
    await runGit(upstream, ['tag', 'camera-v0.11.0']);
    await File('${upstream.path}/.gitignore').writeAsString('''
packages/camera/camera/generated.txt
''');
    await File(
      '${upstream.path}/packages/camera/camera/generated.txt',
    ).delete();
    await runGit(upstream, ['add', '-A']);
    await runGit(upstream, ['commit', '-m', 'Ignore generated package file']);
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_ignored_tag_file',
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
          '--repository-name',
          'camera',
          '--output',
          packageRepository.path,
          '--sdk',
          '3.35.8-ohos-0.0.3',
          '--package-path',
          'packages/camera/camera',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final restored = File(
      '${packageRepository.path}/packages/camera/camera/generated.txt',
    );
    final tracked = await runGit(packageRepository, [
      'ls-files',
      'packages/camera/camera/generated.txt',
    ]);

    expect(restored.readAsStringSync(), 'release generated file\n');
    expect(
      tracked.stdout.toString().split('\n'),
      contains('packages/camera/camera/generated.txt'),
    );
    expect(stderr, isEmpty);
  });

  test(
    'rejects per-package release tags from different monorepo commits',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      final upstream = await createUpstreamWorkspaceRepository(
        Directory(
          '${environment.homeDirectory.path}/upstream_per_package_tags',
        ),
        version: '0.11.0',
      );
      await runGit(upstream, ['tag', 'camera-v0.11.0']);
      await _addWorkspacePackage(
        upstream,
        path: 'packages/share_plus/share_plus',
        name: 'share_plus',
        version: '9.0.0',
      );
      await runGit(upstream, ['tag', 'share_plus-v9.0.0']);
      await bumpUpstreamPackageVersion(
        upstream,
        packagePath: 'packages/camera/camera',
        version: '0.12.0',
      );
      final packageRepository = Directory(
        '${environment.homeDirectory.path}/package_per_package_tags',
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
            '--repository-name',
            'camera',
            '--output',
            packageRepository.path,
            '--sdk',
            '3.35.8-ohos-0.0.3',
            '--package-path',
            'packages/camera/camera',
            '--package-path',
            'packages/share_plus/share_plus',
          ],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        64,
      );

      final error = stderr.join('\n');
      expect(error, contains('package create creates one package branch'));
      expect(error, contains('fluoh package add <package-path>'));
      expect(packageRepository.existsSync(), isFalse);
    },
  );

  test('warns when latest upstream tag needs a newer Dart SDK', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamWorkspaceRepository(
      Directory('${environment.homeDirectory.path}/upstream_packages_sdk'),
      version: '0.11.4',
      sdkConstraint: '>=3.0.0 <4.0.0',
    );
    await runGit(upstream, ['tag', 'camera-v0.11.4']);
    await bumpUpstreamPackageVersion(
      upstream,
      packagePath: 'packages/camera/camera',
      version: '0.12.0+1',
      sdkConstraint: '>=3.10.0 <4.0.0',
    );
    await runGit(upstream, ['tag', 'camera-v0.12.0+1']);
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_camera_sdk_warning',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'add', 'fixture', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );

    final exitCode = await runFluoh(
      [
        'package',
        'create',
        upstream.absolute.uri.toString(),
        '--repository-name',
        'camera',
        '--output',
        packageRepository.path,
        '--sdk',
        '3.35.8-ohos-0.0.3',
        '--package-path',
        'packages/camera/camera',
      ],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    if (exitCode != 0) {
      fail(
        'package create exited $exitCode\nstdout:\n${stdout.join('\n')}\n'
        'stderr:\n${stderr.join('\n')}',
      );
    }

    final manifest = await readPackageManifest(packageRepository);
    final output = stdout.join('\n');

    expect(manifest.primaryPackage.upstreamVersion, '0.12.0+1');
    expect(manifest.primaryPackage.upstreamRef, 'camera-v0.12.0+1');
    expect(
      output,
      contains(
        'requires Dart >=3.10.0 <4.0.0, but the selected FlutterOH SDK '
        'provides Dart 3.9.2',
      ),
    );
    expect(
      output,
      contains(
        'Keep adapting the selected upstream target camera-v0.12.0+1. '
        'Adapt the package pubspec, example config, and Dart code to the '
        'selected FlutterOH SDK Dart 3.9.2',
      ),
    );
    expect(
      output,
      contains(
        'must not be used unless maintainers explicitly approve an older baseline',
      ),
    );
    expect(stderr, isEmpty);

    stdout.clear();
    stderr.clear();
    final planRepository = Directory(
      '${environment.homeDirectory.path}/package_camera_sdk_warning_plan',
    );
    final planExitCode = await runFluoh(
      [
        'package',
        'create',
        upstream.path,
        '--repository-name',
        'camera',
        '--output',
        planRepository.path,
        '--sdk',
        '3.35.8-ohos-0.0.3',
        '--package-path',
        'packages/camera/camera',
        '--plan',
        '--json',
      ],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    if (planExitCode != 0) {
      fail(
        'package create plan exited $planExitCode\n'
        'stdout:\n${stdout.join('\n')}\nstderr:\n${stderr.join('\n')}',
      );
    }

    final payload = jsonDecode(stdout.single) as Map<String, Object?>;
    final plan = payload['plan'] as Map<String, Object?>;
    final warnings = (plan['warnings'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(warnings, hasLength(1));
    expect(warnings.single['code'], 'package.dart_sdk_incompatible');
    expect(warnings.single['severity'], 'warning');
    expect(warnings.single['package'], {
      'name': 'camera',
      'path': 'packages/camera/camera',
    });
    expect(warnings.single['selected'], {
      'ref': 'camera-v0.12.0+1',
      'version': '0.12.0+1',
      'dartConstraint': '>=3.10.0 <4.0.0',
    });
    expect(warnings.single['sdk'], {'dartVersion': '3.9.2'});
    expect(warnings.single['policy'], {
      'defaultAction': 'adapt-selected-upstream-to-selected-sdk',
      'keepSelectedUpstream': true,
      'adjustPackageForSelectedSdk': true,
      'suggestedEnvironmentSdkConstraint': '>=3.9.0 <4.0.0',
      'olderBaselineRequiresApproval': true,
      'sdkUpgradeOptional': true,
    });
    expect(warnings.single['latestCompatible'], {
      'ref': 'camera-v0.11.4',
      'version': '0.11.4',
    });
  });

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
        '--repository-name',
        'camera',
        '--output',
        packageRepository.path,
        '--sdk',
        '3.35.8-ohos-0.0.3',
      ]),
      0,
    );

    final cloneMessage =
        'Cloning upstream repository into ${packageRepository.path}...';
    expect(
      _normalizeOutput(stdout.join('\n')).split(_normalizeOutput(cloneMessage)),
      hasLength(2),
    );
    expect(transient.join(), isNot(contains(cloneMessage)));
    expect(transient.join(), isNot(contains('Receiving objects')));
    final cloneIndex = stdout.indexWhere(
      (line) => line.contains('Cloning upstream repository into '),
    );
    final firstBlank = stdout.indexWhere(
      (line) => line.isEmpty,
      cloneIndex + 1,
    );
    expect(firstBlank, greaterThanOrEqualTo(0));
    final sdkMessageIndex = stdout.indexWhere(
      (line) =>
          line.contains('Using installed FlutterOH SDK') ||
          line.contains('FlutterOH SDK path:'),
    );
    expect(sdkMessageIndex, greaterThan(firstBlank));
    final sdkLinkIndex = stdout.indexWhere(
      (line) => line.contains('IDE Flutter SDK link:'),
    );
    expect(sdkLinkIndex, greaterThanOrEqualTo(0));
    expect(stdout[sdkLinkIndex + 1], isNot(isEmpty));
    final blankAfterSdkLink = stdout.indexWhere(
      (line) => line.isEmpty,
      sdkLinkIndex + 1,
    );
    expect(blankAfterSdkLink, greaterThan(sdkLinkIndex));
    final exampleSkipIndex = stdout.indexWhere(
      (line) => line.contains('Skipping example OHOS setup for video_player:'),
    );
    expect(exampleSkipIndex, greaterThan(blankAfterSdkLink));
    final summaryIndex = stdout.indexWhere(
      (line) => line.contains('Package branch:'),
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
            '--repository-name',
            'camera',
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
          'README.md',
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
          '--repository-name',
          'camera',
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
    expect(exampleGitignore, contains('# fluoh local state'));
    expect(exampleGitignore, contains('.fluoh/'));
    expect(exampleGitignore, contains('flutter_*.log'));
    expect(exampleGitignore, contains('# Flutter local files'));
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
    expect(stdout, contains('Prepared example for camera at example'));
    expect(stderr, contains('flutter create stderr'));
  });

  test(
    'infers flutter create organization from existing example platforms',
    () async {
      final environment = await createTestEnvironment();
      final source = await _createPackageCreateSdkSource(
        environment.homeDirectory,
        logName: 'package_create_example_org_flutter_args.log',
        requiredCreateOrg: 'dev.flutter.plugins',
      );
      final upstream = await _createUpstreamFlutterPluginRepository(
        Directory('${environment.homeDirectory.path}/upstream_org_camera'),
      );
      await _addAmbiguousExampleOrganizations(upstream);
      final packageRepository = Directory(
        '${environment.homeDirectory.path}/package_org_camera',
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
            '--repository-name',
            'camera',
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

      final flutterLog = File(
        '${environment.homeDirectory.path}/package_create_example_org_flutter_args.log',
      ).readAsStringSync();
      expect(
        flutterLog,
        contains(
          '${packageRepository.path}/example::create --no-pub --platforms=ohos --org dev.flutter.plugins .',
        ),
      );
      expect(
        stdout,
        contains('Using organization dev.flutter.plugins for OHOS platform'),
      );
      expect(stderr, contains('flutter create stderr'));
    },
  );

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
        '--repository-name',
        'camera',
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
      _normalizeOutput(process.stdout.toString()),
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
          '--repository-name',
          'camera',
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
      _normalizeOutput(stdout.join('\n')),
      contains(
        _normalizeOutput(
          'Created package repository at ${packageRepository.path}',
        ),
      ),
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
            '--repository-name',
            'camera',
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
        _normalizeOutput(stdout.join('\n')),
        contains(
          _normalizeOutput(
            'Created package repository at ${packageRepository.path}',
          ),
        ),
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
    await File('${upstream.path}/README.md').writeAsString('''
# camera

Original upstream README body.
''');
    await runGit(upstream, ['add', 'AGENTS.md', 'CLAUDE.md', 'README.md']);
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
          '--repository-name',
          'camera',
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
    expect(agentsContent, contains('## FlutterOH/OHOS Adaptation'));
    expect(agentsContent, contains('follow `FLUOH.md`'));
    expect(agentsContent, contains('primary repository rules'));
    expect(agentsContent, contains('- Current package: `camera`.'));
    expect(agentsContent, isNot(contains('## Working Rules')));
    expect(agentsContent, isNot(contains('## Adaptation Workflow')));
    expect(agentsContent, isNot(contains('## Completion Report')));
    expect(agentsContent, isNot(contains('# AGENTS.md')));
    final claudeContent = File(
      '${packageRepository.path}/CLAUDE.md',
    ).readAsStringSync();
    expect(claudeContent, startsWith('@AGENTS.md\n\n# Upstream Claude Notes'));
    expect(claudeContent, contains('Prefer the upstream release workflow.'));
    final readmeContent = File(
      '${packageRepository.path}/README.md',
    ).readAsStringSync();
    expect(readmeContent, startsWith('<!-- fluoh:generated:start'));
    expect(readmeContent, contains('# camera'));
    _expectReadmeAdaptation(
      readmeContent,
      package: const _GuidancePackage(
        name: 'camera',
        version: '0.11.0',
        path: '.',
      ),
    );
    expect(readmeContent, contains('Original upstream README body.'));
    final status = await runGit(packageRepository, ['status', '--porcelain']);
    expect(status.stdout.toString(), contains('M  AGENTS.md'));
    expect(status.stdout.toString(), contains('M  CLAUDE.md'));
    expect(status.stdout.toString(), contains('M  README.md'));
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
    final mainReadme = await runGit(packageRepository, [
      'show',
      'main:README.md',
    ]);
    expect(
      mainReadme.stdout.toString(),
      '# camera\n\nOriginal upstream README body.\n',
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
            '--repository-name',
            'camera',
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
      expect(manifest, contains('package:\n  name: camera'));
      expect(manifest, contains('path: packages/camera/camera'));
      expect(stderr, isEmpty);
    },
  );

  test('prints a read-only package create plan as JSON', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamPackageRepository(
      Directory('${environment.homeDirectory.path}/upstream_plan'),
    );
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_plan',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'add', 'fixture', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    stdout.clear();
    stderr.clear();

    final exitCode = await runFluoh(
      [
        'package',
        'create',
        upstream.path,
        '--repository-name',
        'camera',
        '--output',
        packageRepository.path,
        '--sdk',
        '3.35.8-ohos-0.0.3',
        '--org',
        'dev.flutter.plugins',
        '--git-author-name',
        'FlutterOH Adapter',
        '--git-author-email',
        'adapter@example.com',
        '--plan',
        '--json',
      ],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    if (exitCode != 0) {
      fail(
        'package create plan exited $exitCode\nstdout:\n${stdout.join('\n')}\n'
        'stderr:\n${stderr.join('\n')}',
      );
    }

    expect(stderr, isEmpty);
    expect(stdout, hasLength(1));
    final payload = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(payload['schema'], 1);
    expect(payload['command'], 'package create');
    expect(payload['ok'], isTrue);
    expect(payload['exitCode'], 0);
    expect(payload['changed'], isFalse);
    expect(payload['applied'], isFalse);
    final plan = payload['plan'] as Map<String, Object?>;
    expect(plan['adaptationKind'], 'package');
    expect(plan['repository'], {
      'name': 'camera',
      'url': 'https://github.com/FlutterOH/camera.git',
      'outputPath': packageRepository.path,
      'branch': 'ohos/3.35/camera',
    });
    expect(plan['sdk'], {'version': '3.35.8-ohos-0.0.3', 'line': '3.35'});
    expect(plan['package'], {
      'name': 'camera',
      'path': '.',
      'upstreamVersion': '0.11.0',
      'releaseVersion': '0.1.0',
      'status': 'experimental',
    });
    expect(plan['gitAuthor'], {
      'name': 'FlutterOH Adapter',
      'email': 'adapter@example.com',
    });
    expect(plan['flutterCreateOrg'], 'dev.flutter.plugins');
    expect(
      plan['willNotRunWithoutSeparateApproval'],
      contains('git push --force'),
    );
    expect(packageRepository.existsSync(), isFalse);
  });

  test(
    'package create plan warns about newer default branch package version',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      final upstream = await createUpstreamWorkspaceRepository(
        Directory('${environment.homeDirectory.path}/upstream_unreleased_plan'),
        version: '0.11.0',
      );
      await runGit(upstream, ['tag', 'camera-v0.11.0']);
      await bumpUpstreamPackageVersion(
        upstream,
        packagePath: 'packages/camera/camera',
        version: '0.12.0',
      );
      final packageRepository = Directory(
        '${environment.homeDirectory.path}/package_unreleased_plan',
      );
      final stdout = <String>[];
      final stderr = <String>[];

      await runFluoh(
        ['source', 'add', 'fixture', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      stdout.clear();
      stderr.clear();

      expect(
        await runFluoh(
          [
            'package',
            'create',
            upstream.path,
            '--repository-name',
            'camera',
            '--package-path',
            'packages/camera/camera',
            '--output',
            packageRepository.path,
            '--sdk',
            '3.35.8-ohos-0.0.3',
            '--plan',
            '--json',
          ],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      expect(stderr, isEmpty);
      final payload = jsonDecode(stdout.single) as Map<String, Object?>;
      final plan = payload['plan'] as Map<String, Object?>;
      expect(plan['package'], {
        'name': 'camera',
        'path': 'packages/camera/camera',
        'upstreamVersion': '0.11.0',
        'releaseVersion': '0.1.0',
        'status': 'experimental',
      });
      final upstreamPlan = plan['upstream'] as Map<String, Object?>;
      expect(upstreamPlan['branch'], 'main');
      expect(upstreamPlan['selectedRef'], 'camera-v0.11.0');
      final warnings = (plan['warnings'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(warnings, hasLength(1));
      expect(
        warnings.single['code'],
        'package.default_branch_version_unreleased',
      );
      expect(warnings.single['severity'], 'warning');
      expect(warnings.single['package'], {
        'name': 'camera',
        'path': 'packages/camera/camera',
      });
      expect(warnings.single['selected'], {
        'ref': 'camera-v0.11.0',
        'version': '0.11.0',
      });
      expect(warnings.single['defaultBranch'], {
        'branch': 'main',
        'version': '0.12.0',
      });
      expect(warnings.single['policy'], {
        'defaultAction': 'adapt-selected-release-tag',
        'defaultBranchSnapshotRequiresApproval': true,
      });
      expect(
        warnings.single['nextStep'],
        contains(
          'Use --upstream-ref main only if maintainers explicitly approve',
        ),
      );
      expect(packageRepository.existsSync(), isFalse);
    },
  );

  test(
    'package create plan ignores unrelated broken tags in shallow mode',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      final upstream = await createUpstreamWorkspaceRepository(
        Directory('${environment.homeDirectory.path}/upstream_broken_tags'),
        version: '0.11.0',
      );
      await runGit(upstream, ['tag', 'camera-v0.11.0']);
      final tagsDirectory = Directory('${upstream.path}/.git/refs/tags');
      await tagsDirectory.create(recursive: true);
      await File(
        '${tagsDirectory.path}/unrelated-v999.0.0',
      ).writeAsString('1111111111111111111111111111111111111111\n');
      final packageRepository = Directory(
        '${environment.homeDirectory.path}/package_broken_tags_plan',
      );
      final stdout = <String>[];
      final stderr = <String>[];

      await runFluoh(
        ['source', 'add', 'fixture', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      stdout.clear();
      stderr.clear();

      final exitCode = await runFluoh(
        [
          'package',
          'create',
          upstream.path,
          '--repository-name',
          'camera',
          '--package-path',
          'packages/camera/camera',
          '--output',
          packageRepository.path,
          '--sdk',
          '3.35.8-ohos-0.0.3',
          '--plan',
          '--json',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      if (exitCode != 0) {
        fail(
          'package create plan exited $exitCode\nstdout:\n${stdout.join('\n')}\n'
          'stderr:\n${stderr.join('\n')}',
        );
      }

      expect(stderr, isEmpty);
      final payload = jsonDecode(stdout.single) as Map<String, Object?>;
      final plan = payload['plan'] as Map<String, Object?>;
      final upstreamPlan = plan['upstream'] as Map<String, Object?>;
      expect(upstreamPlan['selectedRef'], 'camera-v0.11.0');
      expect(packageRepository.existsSync(), isFalse);
    },
  );

  test(
    'package create plan recommends federated implementation package',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      final upstream = await _createFederatedWorkspaceRepository(
        Directory('${environment.homeDirectory.path}/upstream_federated_plan'),
      );
      final packageRepository = Directory(
        '${environment.homeDirectory.path}/path_provider_plan',
      );
      final stdout = <String>[];
      final stderr = <String>[];

      await runFluoh(
        ['source', 'add', 'fixture', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      stdout.clear();
      stderr.clear();

      expect(
        await runFluoh(
          [
            'package',
            'create',
            upstream.path,
            '--repository-name',
            'path_provider',
            '--package-path',
            'packages/path_provider/path_provider',
            '--output',
            packageRepository.path,
            '--sdk',
            '3.35.8-ohos-0.0.3',
            '--plan',
            '--json',
          ],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      expect(stderr, isEmpty);
      final payload = jsonDecode(stdout.single) as Map<String, Object?>;
      final plan = payload['plan'] as Map<String, Object?>;
      expect(plan['package'], {
        'name': 'path_provider',
        'path': 'packages/path_provider/path_provider',
        'upstreamVersion': '2.1.0',
        'releaseVersion': '0.1.0',
        'status': 'experimental',
      });
      final recommendation =
          plan['implementationRecommendation'] as Map<String, Object?>;
      expect(recommendation['kind'], 'federated_platform_package');
      expect(
        recommendation['reason'],
        'federated_plugin_missing_platform_package',
      );
      expect(recommendation['platform'], 'ohos');
      expect(recommendation['sourceRoute'], {
        'packageName': 'path_provider',
        'packagePath': 'packages/path_provider/path_provider',
      });
      expect(recommendation['implementationPackageName'], 'path_provider_ohos');
      expect(
        recommendation['implementationPackagePath'],
        'packages/path_provider/path_provider_ohos',
      );
      expect(recommendation['implementationDependency'], {
        'package': 'path_provider_ohos',
        'path': '../path_provider_ohos',
      });
      expect(recommendation['existingDefaultPackages'], {
        'android': 'path_provider_android',
        'ios': 'path_provider_foundation',
      });
      final requiredEdits = recommendation['requiredEdits'] as List<Object?>;
      expect(
        requiredEdits,
        contains(containsPair('defaultPackage', 'path_provider_ohos')),
      );
      expect(
        requiredEdits,
        contains(containsPair('path', '../path_provider_ohos')),
      );
      expect(packageRepository.existsSync(), isFalse);
    },
  );

  test('package create writes federated implementation recommendation', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    final upstream = await _createFederatedWorkspaceRepository(
      Directory('${environment.homeDirectory.path}/upstream_federated_create'),
    );
    await runGit(upstream, ['tag', 'path_provider-v2.1.0']);
    await _writeFederatedPackage(
      upstream,
      path: 'packages/path_provider/path_provider',
      name: 'path_provider',
      version: '2.1.0',
      defaultPackages: const {
        'android': 'path_provider_android',
        'ios': 'path_provider_foundation',
        'ohos': 'path_provider_ohos',
      },
    );
    await runGit(upstream, ['add', '.']);
    await runGit(upstream, ['commit', '-m', 'Declare OHOS on default branch']);
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/path_provider_create',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'add', 'fixture', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    stdout.clear();
    stderr.clear();

    expect(
      await runFluoh(
        [
          'package',
          'create',
          upstream.path,
          '--repository-name',
          'path_provider',
          '--package-path',
          'packages/path_provider/path_provider',
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

    final output = stdout.join('\n');
    expect(output, contains('Create path_provider_ohos'));
    expect(output, contains('packages/path_provider/path_provider_ohos'));
    final guide = File('${packageRepository.path}/FLUOH.md').readAsStringSync();
    expect(guide, contains('## Federated Implementation Route'));
    expect(
      guide,
      contains(
        'Create the OHOS implementation package `path_provider_ohos` at '
        '`packages/path_provider/path_provider_ohos`',
      ),
    );
    expect(guide, contains('Add `ohos.default_package: path_provider_ohos`'));
    expect(
      guide,
      contains(
        'Add dependency `path_provider_ohos` with relative path `../path_provider_ohos`',
      ),
    );
    expect(guide, contains('## Platform Implementation Template'));
    expect(guide, contains('Federated packages: keep `path_provider`'));
    expect(stderr, isEmpty);
  });

  test('rejects package create --json without --plan', () async {
    final environment = await createTestEnvironment();
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        [
          'package',
          'create',
          'https://github.com/example/camera.git',
          '--repository-name',
          'camera',
          '--json',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );

    expect(stderr, isEmpty);
    expect(stdout, hasLength(1));
    final payload = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(payload['command'], 'package create');
    expect(payload['ok'], isFalse);
    expect(payload['exitCode'], 64);
    expect(payload['error'], {
      'type': 'usage',
      'message': '--json is supported only with --plan for package create.',
    });
  });

  test('uses explicit name when the root package has siblings', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
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
        [
          'package',
          'create',
          upstream.path,
          '--repository-name',
          'flutter-widgets-root',
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
    expect(manifest, isNot(contains('\nname: flutter-widgets-root\n')));
    expect(
      manifest,
      contains('url: https://github.com/FlutterOH/flutter-widgets-root.git'),
    );
    expect(manifest, contains('package:\n  name: camera'));
    expect(manifest, isNot(contains('  share_plus:')));
    final guide = File('${packageRepository.path}/FLUOH.md').readAsStringSync();
    expect(guide, contains('fluoh verify'));
    expect(guide, contains('`fluoh package check`'));
    expect(guide, contains('`fluoh package release`'));
    expect(
      _normalizeOutput(stdout.join('\n')),
      contains(
        _normalizeOutput(
          'Created package repository at ${packageRepository.path}',
        ),
      ),
    );
    expect(stderr, isEmpty);
  });

  test(
    'uses explicit name as default output for a single monorepo package',
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
        '${environment.workingDirectory.path}/syncfusion_flutter_pdf',
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
            '--repository-name',
            'syncfusion_flutter_pdf',
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
      final origin = await runGit(packageRepository, [
        'remote',
        'get-url',
        'origin',
      ]);
      expect(manifest, contains('name: syncfusion_flutter_pdf'));
      expect(
        manifest,
        contains(
          'url: https://github.com/FlutterOH/syncfusion_flutter_pdf.git',
        ),
      );
      expect(manifest, contains('package:\n  name: syncfusion_flutter_pdf'));
      expect(manifest, contains('path: packages/syncfusion_flutter_pdf'));
      expect(
        origin.stdout.toString().trim(),
        'https://github.com/FlutterOH/syncfusion_flutter_pdf.git',
      );
      expect(
        _normalizeOutput(stdout.join('\n')),
        contains(
          _normalizeOutput(
            'Created package repository at ${packageRepository.path}',
          ),
        ),
      );
      expect(
        stdout,
        contains(
          'Selected package syncfusion_flutter_pdf at '
          'packages/syncfusion_flutter_pdf',
        ),
      );
      expect(stderr, isEmpty);
    },
  );

  test(
    'requires name for a single monorepo package and suggests the path name',
    () async {
      final environment = await createTestEnvironment();
      final stdout = <String>[];
      final stderr = <String>[];

      expect(
        await runFluoh(
          [
            'package',
            'create',
            'https://github.com/flutter/packages.git',
            '--package-path',
            'packages/syncfusion_flutter_pdf',
          ],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        64,
      );

      expect(
        stderr.join('\n'),
        contains('Pass --repository-name <repository-name>'),
      );
      expect(
        stderr.join('\n'),
        contains('Suggested name: syncfusion_flutter_pdf'),
      );
      expect(stdout, isEmpty);
    },
  );

  test('rejects package create with multiple package paths', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
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
        '--repository-name',
        'camera',
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
    expect(createResult, 64);
    expect(
      stderr.join('\n'),
      contains('package create creates one package branch'),
    );
    expect(packageRepository.existsSync(), isFalse);
  });

  test(
    'requires an explicit name for generic monorepo package collections',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      final upstream = await createUpstreamWorkspaceRepository(
        Directory('${environment.homeDirectory.path}/packages'),
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
        '${environment.workingDirectory.path}/packages',
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
        contains('Pass --repository-name <repository-name>'),
      );
      expect(stderr.join('\n'), isNot(contains('Selected packages:')));
      expect(packageRepository.existsSync(), isFalse);
    },
  );

  test(
    'rejects explicit name for generic monorepo package collections',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      final upstream = await createUpstreamWorkspaceRepository(
        Directory('${environment.homeDirectory.path}/packages'),
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
        '${environment.workingDirectory.path}/flutter_packages',
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
            '--repository-name',
            'camera',
            '--package-path',
            'packages/camera/camera',
            '--package-path',
            'packages/share_plus/share_plus',
            '--repository-name',
            'flutter_packages',
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
        contains('package create creates one package branch'),
      );
      expect(packageRepository.existsSync(), isFalse);
    },
  );

  test('adds another package by creating a package branch', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
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
    await runGit(upstream, ['tag', 'share_plus-v9.0.0']);
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
        '--repository-name',
        'camera',
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
    await bumpUpstreamPackageVersion(
      upstream,
      packagePath: 'packages/share_plus/share_plus',
      version: '9.1.0',
    );
    await runGit(upstream, ['tag', 'share_plus-v9.1.0']);
    await bumpUpstreamPackageVersion(
      upstream,
      packagePath: 'packages/share_plus/share_plus',
      version: '10.0.0',
    );

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
    final pubspec = File(
      '${packageRepository.path}/packages/share_plus/share_plus/pubspec.yaml',
    ).readAsStringSync();
    expect(manifest, contains('package:\n  name: share_plus'));
    expect(manifest, contains('path: packages/share_plus/share_plus'));
    expect(manifest, contains('      version: 9.1.0'));
    expect(manifest, contains('      ref: share_plus-v9.1.0'));
    expect(pubspec, contains('version: 9.1.0'));
    expect(pubspec, isNot(contains('version: 10.0.0')));
    const packages = [
      _GuidancePackage(
        name: 'share_plus',
        version: '9.1.0',
        path: 'packages/share_plus/share_plus',
      ),
    ];
    final guide = File('${packageRepository.path}/FLUOH.md').readAsStringSync();
    _expectImplementationGuide(guide, packages: packages);
    final agents = File(
      '${packageRepository.path}/AGENTS.md',
    ).readAsStringSync();
    _expectAgentsInstructions(agents, packages: packages);
    expect(agents, isNot(contains('Upstream branch at creation')));
    final readme = File(
      '${packageRepository.path}/README.md',
    ).readAsStringSync();
    _expectReadmeAdaptation(readme, package: packages.single);
    final changelog = File(
      '${packageRepository.path}/FLUOH_CHANGELOG.md',
    ).readAsStringSync();
    _expectChangelogEntry(changelog, 'share_plus-9.1.0-ohos-3.35-0.1.0');
    final status = await runGit(packageRepository, ['status', '--porcelain']);
    expect(status.stdout.toString(), contains('A  .gitignore'));
    expect(status.stdout.toString(), contains('A  fluoh.yaml'));
    expect(status.stdout.toString(), contains('A  AGENTS.md'));
    expect(status.stdout.toString(), contains('A  FLUOH.md'));
    expect(status.stdout.toString(), contains('A  FLUOH_CHANGELOG.md'));
    expect(status.stdout.toString(), contains('M  README.md'));
    expect(status.stdout.toString(), isNot(contains('.fluoh')));
    expect(
      File('${packageRepository.path}/.gitignore').readAsStringSync(),
      contains('.fluoh/'),
    );
    expect(
      stdout.join('\n'),
      contains('Created package branch ohos/3.35/share_plus'),
    );
    expect(stderr, isEmpty);
  });

  test('package add creates a clean package branch from upstream', () async {
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
    await runGit(upstream, ['tag', 'share_plus-v9.0.0']);
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
        '--repository-name',
        'camera',
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

    final branch = await runGit(packageRepository, [
      'branch',
      '--show-current',
    ]);
    final example = Directory(
      '${packageRepository.path}/packages/share_plus/share_plus/example',
    );
    expect(branch.stdout.toString().trim(), 'ohos/3.35/share_plus');
    expect(Directory('${example.path}/ohos').existsSync(), isTrue);
    expect(File('${example.path}/fluoh.yaml').existsSync(), isTrue);
    final status = await runGit(packageRepository, ['status', '--porcelain']);
    expect(status.stdout.toString(), contains('A  fluoh.yaml'));
  });

  test('package add prints a read-only plan as JSON', () async {
    final environment = await createTestEnvironment();
    final source = await _createPackageCreateSdkSource(
      environment.homeDirectory,
      logName: 'package_add_plan_flutter_args.log',
    );
    final upstream = await createUpstreamWorkspaceRepository(
      Directory('${environment.homeDirectory.path}/upstream_add_plan'),
      packagePath: 'packages/camera/camera',
      packageName: 'camera',
    );
    await _addWorkspaceFlutterPackage(
      upstream,
      path: 'packages/share_plus/share_plus',
      name: 'share_plus',
      version: '9.0.0',
    );
    await runGit(upstream, ['tag', 'share_plus-v9.0.0']);
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_add_plan',
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
        '--repository-name',
        'camera',
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
    stdout.clear();
    stderr.clear();

    final packageEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    expect(
      await runFluoh(
        [
          'package',
          'add',
          'packages/share_plus/share_plus',
          '--upstream-version',
          '9.0.0',
          '--org',
          'dev.flutter.plugins',
          '--plan',
          '--json',
        ],
        environment: packageEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(stderr, isEmpty);
    expect(stdout, hasLength(1));
    final payload = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(payload['command'], 'package add');
    expect(payload['ok'], isTrue);
    expect(payload['changed'], isFalse);
    expect(payload['applied'], isFalse);
    final plan = payload['plan'] as Map<String, Object?>;
    final repository = plan['repository'] as Map<String, Object?>;
    expect(repository['sourceBranch'], 'ohos/3.35/camera');
    expect(repository['newBranch'], 'ohos/3.35/share_plus');
    expect(repository['branchExists'], isFalse);
    expect(repository['workingTreeClean'], isTrue);
    expect(plan['sdk'], {'version': '3.35.8-ohos-0.0.3', 'line': '3.35'});
    expect(plan['package'], {
      'name': 'share_plus',
      'path': 'packages/share_plus/share_plus',
      'upstreamVersion': '9.0.0',
      'releaseVersion': '0.1.0',
      'status': 'experimental',
    });
    expect(
      plan['nextCommand'],
      'fluoh package add packages/share_plus/share_plus --upstream-version 9.0.0 --org dev.flutter.plugins',
    );
    final branch = await runGit(packageRepository, [
      'branch',
      '--show-current',
    ]);
    expect(branch.stdout.toString().trim(), 'ohos/3.35/camera');
    final status = await runGit(packageRepository, ['status', '--porcelain']);
    expect(status.stdout.toString().trim(), isEmpty);
  });

  test('package queue resolves multiple package add commands as JSON', () async {
    final environment = await createTestEnvironment();
    final source = await _createPackageCreateSdkSource(
      environment.homeDirectory,
      logName: 'package_queue_flutter_args.log',
    );
    final upstream = await createUpstreamWorkspaceRepository(
      Directory('${environment.homeDirectory.path}/upstream_queue'),
      packagePath: 'packages/camera/camera',
      packageName: 'camera',
    );
    await _addWorkspaceFlutterPackage(
      upstream,
      path: 'packages/share_plus/share_plus',
      name: 'share_plus',
      version: '9.0.0',
    );
    await _addWorkspaceFlutterPackage(
      upstream,
      path: 'packages/path_provider/path_provider',
      name: 'path_provider',
      version: '2.1.0',
    );
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_queue',
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
        '--repository-name',
        'camera',
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
    stdout.clear();
    stderr.clear();

    final packageEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    expect(
      await runFluoh(
        [
          'package',
          'queue',
          'packages/share_plus/share_plus',
          'packages/path_provider/path_provider',
          '--org',
          'dev.flutter.plugins',
          '--json',
        ],
        environment: packageEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(stderr, isEmpty);
    final payload = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(payload['command'], 'package queue');
    expect(payload['changed'], isFalse);
    final queue = payload['queue'] as Map<String, Object?>;
    expect(queue['sdk'], {'version': '3.35.8-ohos-0.0.3', 'line': '3.35'});
    final packages = queue['packages'] as List<Object?>;
    expect(packages, hasLength(2));
    final sharePlus = packages.first as Map<String, Object?>;
    expect(sharePlus['name'], 'share_plus');
    expect(sharePlus['branch'], 'ohos/3.35/share_plus');
    expect(sharePlus['branchExists'], isFalse);
    expect(
      sharePlus['nextCommand'],
      'fluoh package add packages/share_plus/share_plus --org dev.flutter.plugins',
    );
    final pathProvider = packages.last as Map<String, Object?>;
    expect(pathProvider['name'], 'path_provider');
    expect(pathProvider['branch'], 'ohos/3.35/path_provider');
  });

  test('package add can use an explicit version removed from main', () async {
    final environment = await createTestEnvironment();
    final source = await _createPackageCreateSdkSource(
      environment.homeDirectory,
      logName: 'package_add_removed_flutter_args.log',
    );
    final upstream = await createUpstreamWorkspaceRepository(
      Directory('${environment.homeDirectory.path}/upstream_add_removed'),
      packagePath: 'packages/camera/camera',
      packageName: 'camera',
    );
    await _addWorkspaceFlutterPackage(
      upstream,
      path: 'packages/share_plus/share_plus',
      name: 'share_plus',
      version: '9.0.0',
    );
    await runGit(upstream, ['tag', 'share_plus-v9.0.0']);
    await Directory(
      '${upstream.path}/packages/share_plus/share_plus',
    ).delete(recursive: true);
    await runGit(upstream, ['add', '-A', 'packages/share_plus/share_plus']);
    await runGit(upstream, ['commit', '-m', 'Remove share_plus fixture']);
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_add_removed',
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
        '--repository-name',
        'camera',
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
    stdout.clear();
    stderr.clear();

    final packageEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    expect(
      await runFluoh(
        [
          'package',
          'add',
          'packages/share_plus/share_plus',
          '--upstream-version',
          '9.0.0',
        ],
        environment: packageEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final manifest = File(
      '${packageRepository.path}/fluoh.yaml',
    ).readAsStringSync();
    final pubspec = File(
      '${packageRepository.path}/packages/share_plus/share_plus/pubspec.yaml',
    ).readAsStringSync();
    expect(manifest, contains('package:\n  name: share_plus'));
    expect(manifest, contains('      version: 9.0.0'));
    expect(manifest, contains('      ref: share_plus-v9.0.0'));
    expect(pubspec, contains('version: 9.0.0'));
  });

  test('package add uses latest package tag removed from main', () async {
    final environment = await createTestEnvironment();
    final source = await _createPackageCreateSdkSource(
      environment.homeDirectory,
      logName: 'package_add_removed_latest_flutter_args.log',
    );
    final upstream = await createUpstreamWorkspaceRepository(
      Directory(
        '${environment.homeDirectory.path}/upstream_add_removed_latest',
      ),
      packagePath: 'packages/camera/camera',
      packageName: 'camera',
    );
    await _addWorkspaceFlutterPackage(
      upstream,
      path: 'packages/share_plus/share_plus',
      name: 'share_plus',
      version: '9.0.0',
    );
    await runGit(upstream, ['tag', 'share_plus-v9.0.0']);
    await bumpUpstreamPackageVersion(
      upstream,
      packagePath: 'packages/share_plus/share_plus',
      version: '9.1.0',
    );
    await runGit(upstream, ['tag', 'share_plus-v9.1.0']);
    await Directory(
      '${upstream.path}/packages/share_plus/share_plus',
    ).delete(recursive: true);
    await runGit(upstream, ['add', '-A', 'packages/share_plus/share_plus']);
    await runGit(upstream, ['commit', '-m', 'Remove share_plus fixture']);
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_add_removed_latest',
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
        '--repository-name',
        'camera',
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
    final pubspec = File(
      '${packageRepository.path}/packages/share_plus/share_plus/pubspec.yaml',
    ).readAsStringSync();
    expect(manifest, contains('package:\n  name: share_plus'));
    expect(manifest, contains('      version: 9.1.0'));
    expect(manifest, contains('      ref: share_plus-v9.1.0'));
    expect(pubspec, contains('version: 9.1.0'));
  });

  test('package add points existing package branches to sync', () async {
    final environment = await createTestEnvironment();
    final source = await _createPackageCreateSdkSource(
      environment.homeDirectory,
      logName: 'package_add_existing_branch_flutter_args.log',
    );
    final upstream = await createUpstreamWorkspaceRepository(
      Directory('${environment.homeDirectory.path}/upstream_add_existing'),
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
      '${environment.homeDirectory.path}/package_add_existing',
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
        '--repository-name',
        'camera',
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
      reason: [...stderr, ...stdout].join('\n'),
    );
    await commitGeneratedPackageRepository(packageRepository);
    stdout.clear();
    stderr.clear();

    expect(
      await runFluoh(
        ['package', 'add', 'packages/share_plus/share_plus'],
        environment: packageEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );

    final branch = await runGit(packageRepository, [
      'branch',
      '--show-current',
    ]);
    expect(branch.stdout.toString().trim(), 'ohos/3.35/share_plus');
    expect(
      stderr.join('\n'),
      contains('Package branch ohos/3.35/share_plus already exists.'),
    );
    expect(stderr.join('\n'), contains('package status --package share_plus'));
    expect(stderr.join('\n'), contains('fluoh package sync'));
  });

  test('package add and queue detect remote-only package branches', () async {
    final environment = await createTestEnvironment();
    final source = await _createPackageCreateSdkSource(
      environment.homeDirectory,
      logName: 'package_add_remote_existing_branch_flutter_args.log',
    );
    final upstream = await createUpstreamWorkspaceRepository(
      Directory('${environment.homeDirectory.path}/upstream_add_remote'),
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
      '${environment.homeDirectory.path}/package_add_remote_origin',
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
        '--repository-name',
        'camera',
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
    await runFluoh(
      ['package', 'add', 'packages/share_plus/share_plus'],
      environment: packageEnvironment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    await commitGeneratedPackageRepository(packageRepository);

    final clonedRepository = Directory(
      '${environment.homeDirectory.path}/package_add_remote_clone',
    );
    await runGit(environment.homeDirectory, [
      'clone',
      '--branch',
      'ohos/3.35/camera',
      packageRepository.path,
      clonedRepository.path,
    ]);
    final clonedEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: clonedRepository,
    );
    stdout.clear();
    stderr.clear();

    expect(
      await runFluoh(
        ['package', 'queue', 'packages/share_plus/share_plus', '--json'],
        environment: clonedEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
      reason: stderr.join('\n'),
    );

    expect(stderr, isEmpty);
    final queuePayload = jsonDecode(stdout.single) as Map<String, Object?>;
    final queue = queuePayload['queue'] as Map<String, Object?>;
    final packages = queue['packages'] as List<Object?>;
    final sharePlus = packages.single as Map<String, Object?>;
    expect(sharePlus['branch'], 'ohos/3.35/share_plus');
    expect(sharePlus['branchExists'], isTrue);
    expect(
      sharePlus['nextCommand'],
      'git checkout ohos/3.35/share_plus && fluoh package status --package share_plus',
    );
    final remotesAfterQueue = await runGit(clonedRepository, ['remote']);
    expect(remotesAfterQueue.stdout.toString().trim(), 'origin');
    stdout.clear();
    stderr.clear();

    expect(
      await runFluoh(
        [
          'package',
          'add',
          'packages/share_plus/share_plus',
          '--plan',
          '--json',
        ],
        environment: clonedEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(stderr, isEmpty);
    final addPayload = jsonDecode(stdout.single) as Map<String, Object?>;
    final plan = addPayload['plan'] as Map<String, Object?>;
    final repository = plan['repository'] as Map<String, Object?>;
    expect(repository['branchExists'], isTrue);
    expect(
      plan['nextCommand'],
      'git checkout ohos/3.35/share_plus && fluoh package status --package share_plus',
    );
    final willRun = (plan['willRun'] as List<Object?>).join('\n');
    expect(willRun, contains('checkout existing package branch'));
    expect(willRun, contains('inspect package status for share_plus'));
    expect(willRun, isNot(contains('write README.md')));
    expect(willRun, isNot(contains('stage generated files')));
    final remotesAfterPlan = await runGit(clonedRepository, ['remote']);
    expect(remotesAfterPlan.stdout.toString().trim(), 'origin');
    stdout.clear();
    stderr.clear();

    expect(
      await runFluoh(
        ['package', 'add', 'packages/share_plus/share_plus'],
        environment: clonedEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );

    final branch = await runGit(clonedRepository, ['branch', '--show-current']);
    expect(branch.stdout.toString().trim(), 'ohos/3.35/camera');
    expect(
      stderr.join('\n'),
      contains('Package branch ohos/3.35/share_plus already exists.'),
    );
    expect(stderr.join('\n'), contains('package status --package share_plus'));
  });

  test('package add restores the starting branch when setup fails', () async {
    final environment = await createTestEnvironment();
    final source = await _createPackageCreateSdkSource(
      environment.homeDirectory,
      logName: 'package_add_failure_flutter_args.log',
    );
    final upstream = await createUpstreamWorkspaceRepository(
      Directory('${environment.homeDirectory.path}/upstream_add_failure'),
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
      '${environment.homeDirectory.path}/package_add_failure',
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
        '--repository-name',
        'camera',
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
    final flutter = File(
      '${environment.homeDirectory.path}/sdks/3.35.8-ohos-0.0.3/bin/flutter',
    );
    await flutter.writeAsString('''
#!/bin/sh
exit 1
''');
    await _runProcess('chmod', ['+x', flutter.path], flutter.parent);

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

    final branch = await runGit(packageRepository, [
      'branch',
      '--show-current',
    ]);
    final addedBranch = await runGit(packageRepository, [
      'branch',
      '--list',
      'ohos/3.35/share_plus',
    ]);
    final status = await runGit(packageRepository, ['status', '--porcelain']);
    final manifest = File(
      '${packageRepository.path}/fluoh.yaml',
    ).readAsStringSync();
    expect(branch.stdout.toString().trim(), 'ohos/3.35/camera');
    expect(addedBranch.stdout.toString().trim(), isEmpty);
    expect(status.stdout.toString().trim(), isEmpty);
    expect(manifest, contains('package:\n  name: camera'));
    expect(manifest, isNot(contains('name: share_plus')));
    expect(stderr.join('\n'), contains('flutter create failed'));
  });

  test('requires a selected package for nested package upstreams', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamWorkspaceRepository(
      Directory(
        '${environment.homeDirectory.path}/upstream_unselected_workspace',
      ),
    );
    await runGit(upstream, ['tag', 'camera-v0.11.0']);
    final example = Directory(
      '${upstream.path}/packages/camera/camera/example',
    );
    await example.create(recursive: true);
    await File('${example.path}/pubspec.yaml').writeAsString('''
name: camera_example
version: 1.0.0

environment:
  sdk: ^3.0.0
''');
    await runGit(upstream, ['add', 'packages/camera/camera/example']);
    await runGit(upstream, ['commit', '-m', 'Add camera example']);
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
          '--repository-name',
          'camera',
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
      _normalizeOutput(stderr.join('\n')),
      contains('For packages below the root, select package paths'),
    );
    expect(stderr.join('\n'), contains('--package-path <package-path>'));
    expect(stderr.join('\n'), contains('Candidate packages:'));
    expect(
      stderr.join('\n'),
      contains(
        'camera 0.11.0 at packages/camera/camera (Dart ^3.0.0)'
        ' [latest tag camera-v0.11.0]: --package-path '
        'packages/camera/camera --repository-name camera',
      ),
    );
    expect(stderr.join('\n'), isNot(contains('camera_example')));
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
            '--repository-name',
            'camera',
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
          '--repository-name',
          'camera',
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
            '--repository-name',
            'camera',
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
          '--repository-name',
          'camera',
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
    expect(branch.stdout.toString().trim(), 'ohos/3.35/camera');
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
          '--repository-name',
          'camera',
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
          '--repository-name',
          'camera',
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

  test(
    'requires package repository name to be a name instead of a path',
    () async {
      final environment = await createTestEnvironment();
      final packageRepository = Directory(
        '${environment.homeDirectory.path}/package_invalid_name',
      );
      final stdout = <String>[];
      final stderr = <String>[];

      expect(
        await runFluoh(
          [
            'package',
            'create',
            'https://github.com/example/packages.git',
            '--repository-name',
            '../camera',
            '--output',
            packageRepository.path,
          ],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        64,
      );

      expect(
        stderr.join('\n'),
        contains('--repository-name must be a repository name'),
      );
      expect(packageRepository.existsSync(), isFalse);
    },
  );

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

  String get verifyCommand =>
      path == '.' ? 'fluoh verify' : 'fluoh verify --package $name';

  String get releaseCommand => path == '.'
      ? 'fluoh package release'
      : 'fluoh package release --package $name';

  String get releaseCheckCommand => path == '.'
      ? 'fluoh package check'
      : 'fluoh package check --package $name';

  String get versionCommand => path == '.'
      ? 'fluoh package version'
      : 'fluoh package version --package $name';
}

void _expectReadmeAdaptation(
  String content, {
  required _GuidancePackage package,
}) {
  _expectContainsAll(content, [
    '<!-- fluoh:generated:start id=package-readme-adaptation template=1 -->',
    'This section is generated by fluoh. Do not edit inside this block',
    '## FlutterOH adaptation',
    '[![Latest release](https://img.shields.io/github/v/tag/FlutterOH/',
    '?label=release&sort=date&filter=${package.name}-*)](https://github.com/FlutterOH/',
    'This branch maintains the FlutterOH adaptation for this package.',
    'The original README continues below.',
    '- Metadata: [fluoh.yaml](fluoh.yaml)',
    '- Maintainer guide: [FLUOH.md](FLUOH.md)',
    '- Release notes: [FLUOH_CHANGELOG.md](FLUOH_CHANGELOG.md)',
    '- Validation: `${package.releaseCheckCommand}`',
    '<!-- fluoh:generated:end id=package-readme-adaptation -->',
  ]);
  if (package.path == '.') {
    expect(content, isNot(contains('- Package path:')));
  } else {
    expect(
      content,
      contains('- Package path: [${package.path}](${package.path})'),
    );
  }
  expect(content, isNot(contains(package.version)));
  expect(content, isNot(contains('3.35.8-ohos')));
  expect(content, isNot(contains('0.1.0')));
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
    '## Guardrails',
    '## Automatic Adaptation Command Flow',
    '## Platform Verification Matrix',
    '## Diagnostics Routing',
    '## Next Steps',
    '## Adaptation Workflow',
    '## Release Readiness',
    '## Completion Report',
    '## Local Commit Checkpoints',
    '## Before Commit',
  ]);
  _expectContainsAll(content, [
    'fluoh.yaml',
    'repository.git.url',
    'repository.git.branch',
    'upstream.git',
    'FLUOH_CHANGELOG.md',
    'fluoh help',
    'fluoh help package',
    'fluoh help verify',
    'Do not invent OHOS APIs',
    'destructive Git commands',
    'Preserve the local worktree',
    'fluoh doctor --project --json --strict',
    'fluoh deps get',
    'fluoh flutter analyze',
    'fluoh run ohos',
    'fluoh run android',
    'fluoh run ios',
    'fluoh run macos',
    'fluoh build linux',
    'fluoh run web',
    'fluoh build windows',
    'fluoh build ohos',
    '--no-codesign',
    '--device-id <id>',
    'integration_test/',
    'AI-assisted interaction evidence',
    '.fluoh/scenarios',
    'Flutter debug',
    'details.vmServiceUri',
    '--session-file <path>',
    'flutterRunSession',
    'inspect_session.py',
    'widget/component',
    'semantic',
    'screenshot recognition',
    'UI appearance',
    'No interaction required',
    'permission grant and denial',
    'Run smoke is not enough',
    'does not currently automate page traversal',
    '\$FLUOH_HOME/cache/package-runs',
    '--auto-sign',
    '--json',
    'nextCommand',
    'diagnostics',
    'Final report and release gate',
    'python3 <skill-dir>/scripts/check_report.py <report-path>',
    'Device-only behavior',
    'skipped with blocker',
    'maintainer-decision blocker',
    'stdoutTail',
    'ohos.signing_profile_failed',
    'ohos.direct_sign_failed',
    'android.apk_build_failed',
    'android.device_missing',
    'android.run_failed',
    'android.runtime_crash',
    'android.integration_test_failed',
    'ios.build_failed',
    'ios.device_missing',
    'ios.run_failed',
    'ios.runtime_crash',
    'ios.integration_test_failed',
    'macos.build_failed',
    'macos.device_missing',
    'macos.run_failed',
    'macos.runtime_crash',
    'macos.integration_test_failed',
    'linux.build_failed',
    'web.build_failed',
    'windows.build_failed',
    'ohos.runtime_crash',
    'ohos.install_failed',
    '.fluoh/reports/',
    'YYYYMMDD-HHMMSS',
    'Release recommendation:',
    'changed files',
    'build, run, integration-test',
    'ignored local state',
    'git status --short --ignored=matching',
    'git config --local --get user.name',
    '--git-author-name',
    'implementation checkpoint',
    'release metadata checkpoint',
    'staged paths, commit message',
    'self-review',
  ]);
  if (packages.length > 1) {
    _expectContainsAll(content, [
      'package',
      'fluoh verify --package <name>',
      'fluoh package release --package <name>',
    ]);
  }

  for (final package in packages) {
    _expectContainsAll(content, [
      package.name,
      package.examplePath,
      package.verifyCommand,
      package.versionCommand,
      package.releaseCommand,
    ]);
    if (packages.length > 1) {
      expect(content, contains(package.version));
    }
    if (package.path != '.') {
      expect(content, contains(package.path));
    } else {
      expect(content, contains('package'));
    }
  }
}

void _expectAgentsInstructions(
  String content, {
  required List<_GuidancePackage> packages,
}) {
  _expectMarkdownHeadings(content, [
    '# AGENTS.md',
    '## FlutterOH/OHOS Adaptation',
  ]);
  _expectContainsAll(content, [
    'For FlutterOH/OHOS package adaptation tasks, follow `FLUOH.md`.',
    'primary repository rules',
    'workflow, verification, release evidence, and handoff',
  ]);
  if (packages.length > 1) {
    _expectContainsAll(content, [
      '- Current packages:',
      for (final package in packages) '`${package.name}`',
    ]);
  } else {
    expect(content, contains('- Current package: `${packages.single.name}`.'));
  }

  expect(content, isNot(contains('## Working Rules')));
  expect(content, isNot(contains('## Automatic Adaptation Command Flow')));
  expect(content, isNot(contains('## Platform Verification Matrix')));
  expect(content, isNot(contains('## Diagnostics Routing')));
  expect(content, isNot(contains('## Completion Report')));
  expect(content, isNot(contains('## Local Commit Checkpoints')));
  expect(content, isNot(contains('fluoh doctor --project --json --strict')));
  expect(content, isNot(contains('fluoh run ohos')));
  expect(content, isNot(contains('.fluoh/reports/')));
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

void _expectWrappedContainsAll(String content, Iterable<String> expected) {
  final normalizedContent = _normalizeOutput(content);
  for (final value in expected) {
    expect(
      normalizedContent,
      contains(_normalizeOutput(value)),
      reason: 'Expected to find "$value".',
    );
  }
}

String _normalizeOutput(String value) {
  return value
      .replaceAll(RegExp(r'(?<=[/-])\s+'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
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
  String? requiredCreateOrg,
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
  await flutter.writeAsString(
    _fakeFlutterScript(
      '${parent.path}/$logName',
      requiredCreateOrg: requiredCreateOrg,
    ),
  );
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

String _fakeFlutterScript(String logPath, {String? requiredCreateOrg}) {
  final requiredOrg = requiredCreateOrg ?? '';
  return '''
#!/bin/sh
printf "%s::%s\\n" "\$(pwd)" "\$*" >> "$logPath"
if [ "\$1" = "create" ]; then
  printf "flutter create stdout\\n"
  printf "flutter create stderr\\n" >&2
  target=""
  platforms=""
  org=""
  while [ "\$#" -gt 0 ]; do
    case "\$1" in
      --platforms=*) platforms="\${1#--platforms=}" ;;
      --org=*) org="\${1#--org=}" ;;
      --org) shift; org="\$1" ;;
      --project-name) shift ;;
      --no-pub) ;;
      create) ;;
      *) target="\$1" ;;
    esac
    shift
  done
  if [ "$requiredOrg" != "" ] && [ "\$org" != "$requiredOrg" ]; then
    printf "expected --org $requiredOrg, got %s\\n" "\$org" >&2
    exit 64
  fi
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

Future<void> _addAmbiguousExampleOrganizations(Directory repo) async {
  await Directory(
    '${repo.path}/example/android/app/src/main',
  ).create(recursive: true);
  await File(
    '${repo.path}/example/android/app/src/main/AndroidManifest.xml',
  ).writeAsString('''
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="io.flutter.plugins.cameraExample">
</manifest>
''');
  await Directory(
    '${repo.path}/example/ios/Runner.xcodeproj',
  ).create(recursive: true);
  await File(
    '${repo.path}/example/ios/Runner.xcodeproj/project.pbxproj',
  ).writeAsString('''
{
  PRODUCT_BUNDLE_IDENTIFIER = dev.flutter.plugins.cameraExample;
}
''');
  await _runProcess('git', ['add', '.'], repo);
  await _runProcess('git', [
    'commit',
    '-m',
    'Add example platform metadata',
  ], repo);
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

Future<Directory> _createFederatedWorkspaceRepository(Directory repo) async {
  await repo.create(recursive: true);
  await _runProcess('git', ['init', '--initial-branch=main'], repo);
  await _runProcess('git', [
    'config',
    'user.email',
    'fixture@example.com',
  ], repo);
  await _runProcess('git', ['config', 'user.name', 'Fixture'], repo);
  await _writeFederatedPackage(
    repo,
    path: 'packages/path_provider/path_provider',
    name: 'path_provider',
    version: '2.1.0',
    defaultPackages: const {
      'android': 'path_provider_android',
      'ios': 'path_provider_foundation',
    },
  );
  await _writePlainPackage(
    repo,
    path: 'packages/path_provider/path_provider_android',
    name: 'path_provider_android',
    version: '2.1.0',
  );
  await _writePlainPackage(
    repo,
    path: 'packages/path_provider/path_provider_foundation',
    name: 'path_provider_foundation',
    version: '2.1.0',
  );
  await File('${repo.path}/README.md').writeAsString('# federated workspace\n');
  await File('${repo.path}/LICENSE').writeAsString(_testLicenseContent);
  await _runProcess('git', ['add', '.'], repo);
  await _runProcess('git', [
    'commit',
    '-m',
    'Initial federated workspace',
  ], repo);
  return repo;
}

Future<void> _writeFederatedPackage(
  Directory repo, {
  required String path,
  required String name,
  required String version,
  required Map<String, String> defaultPackages,
}) async {
  final directory = Directory('${repo.path}/$path');
  await Directory('${directory.path}/lib').create(recursive: true);
  final platforms = defaultPackages.entries.map((entry) {
    return '''
      ${entry.key}:
        default_package: ${entry.value}
''';
  }).join();
  await File('${directory.path}/pubspec.yaml').writeAsString('''
name: $name
version: $version

environment:
  sdk: ^3.0.0

dependencies:
  flutter:
    sdk: flutter

flutter:
  plugin:
    platforms:
$platforms
''');
  await File(
    '${directory.path}/lib/$name.dart',
  ).writeAsString('library $name;\n');
}

Future<void> _writePlainPackage(
  Directory repo, {
  required String path,
  required String name,
  required String version,
}) async {
  final directory = Directory('${repo.path}/$path');
  await Directory('${directory.path}/lib').create(recursive: true);
  await File('${directory.path}/pubspec.yaml').writeAsString('''
name: $name
version: $version

environment:
  sdk: ^3.0.0
''');
  await File(
    '${directory.path}/lib/$name.dart',
  ).writeAsString('library $name;\n');
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
