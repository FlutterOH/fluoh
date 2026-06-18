part of 'source_command_test.dart';

void _registerSourceCommandSyncTests() {
  test('source register adds a created package release', () async {
    final environment = await createTestEnvironment();
    final source = Directory('${environment.homeDirectory.path}/local_source');
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/sensors_ohos',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'init', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    await packageRepository.create(recursive: true);
    await File('${packageRepository.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: package

sdk:
  version: 3.35.8-ohos-0.0.3

repository:
  git:
    url: "https://github.com/FlutterOH/sensors_ohos.git"
    branch: ohos/3.35/sensors_ohos

origin:
  kind: created

package:
  name: sensors_ohos
  path: .
  release:
    version: "0.1.0"
    status: experimental
''');
    stdout.clear();

    expect(
      await runFluoh(
        [
          'source',
          'register',
          packageRepository.path,
          '--source',
          source.path,
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
    expect(payload, containsPair('command', 'source register'));
    expect(payload, containsPair('package', 'sensors_ohos'));
    expect(payload, containsPair('tag', 'sensors_ohos-ohos-3.35-0.1.0'));
    expect(payload, containsPair('status', 'registered'));
    expect(
      File('${source.path}/fluoh.yaml').readAsStringSync(),
      contains('manifests:\n  - name: sensors_ohos'),
    );
    final manifest = File(
      '${source.path}/manifests/sensors_ohos/fluoh.yaml',
    ).readAsStringSync();
    expect(manifest, contains('origin:\n  kind: created'));
    expect(manifest, contains('tag: sensors_ohos-ohos-3.35-0.1.0'));
    expect(manifest, contains('status: experimental'));
    expect(manifest, isNot(contains('\nupstream:')));
  });

  test('source sync imports released package repository manifests', () async {
    final environment = await createTestEnvironment();
    final source = Directory('${environment.homeDirectory.path}/local_source');
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/packages_implementation',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'init', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    await _writePackageManifest(
      packageRepository,
      upstreamRef: 'camera-v0.11.0',
    );
    await _writeSourceSyncManifest(source, packageRepository);
    await initializeGitRepository(packageRepository);
    await _runGit(packageRepository, ['tag', 'camera-0.11.0-ohos-3.35-0.2.0']);
    final packageManifest = File('${packageRepository.path}/fluoh.yaml');
    await packageManifest.writeAsString(
      packageManifest
          .readAsStringSync()
          .replaceFirst('version: "0.2.0"', 'version: "0.3.0"')
          .replaceFirst(
            '    upstream:\n      version: "0.11.0"\n      ref:',
            '    upstream:\n      version: "0.12.0"\n      ref:',
          ),
    );

    expect(
      await runFluoh(
        ['source', 'sync'],
        environment: FluohEnvironment(
          homeDirectory: environment.homeDirectory,
          workingDirectory: source,
        ),
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(
      File('${source.path}/fluoh.yaml').readAsStringSync(),
      contains('manifests:\n  - name: camera'),
    );
    final manifest = File(
      '${source.path}/manifests/camera/fluoh.yaml',
    ).readAsStringSync();
    expect(manifest, contains('name: camera'));
    expect(manifest, contains('url: "file:${packageRepository.path}"'));
    expect(manifest, contains('upstream:\n            version: 0.11.0'));
    expect(manifest, contains('ref: camera-v0.11.0'));
    expect(
      manifest,
      contains('commit: "1111111111111111111111111111111111111111"'),
    );
    expect(manifest, contains('- version: 0.2.0'));
    expect(manifest, isNot(contains('version: 0.12.0')));
    expect(manifest, isNot(contains('- version: 0.3.0')));
    expect(manifest, isNot(contains('status: experimental')));
    expect(
      stdout,
      contains(
        'Synced source metadata for camera from ${packageRepository.path}',
      ),
    );
    expect(stderr, isEmpty);
  });

  test('source sync reads release manifests from fetched tag refs', () async {
    final environment = await createTestEnvironment();
    final source = Directory(
      '${environment.homeDirectory.path}/tag_only_source',
    );
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/tag_only_package',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'init', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    await _writePackageManifest(
      packageRepository,
      upstreamRef: 'camera-v0.11.0',
    );
    await _writeSourceSyncManifest(source, packageRepository);
    await initializeGitRepository(packageRepository);
    await _runGit(packageRepository, [
      'tag',
      '-a',
      'camera-0.11.0-ohos-3.35-0.2.0',
      '-m',
      'Release 0.2.0',
    ]);
    await _writePackageManifest(
      packageRepository,
      releaseVersion: '0.3.0',
      upstreamVersion: '0.12.0',
      upstreamRef: 'camera-v0.12.0',
      upstreamCommit: '2222222222222222222222222222222222222222',
    );
    await commitAll(packageRepository, message: 'Release 0.3.0 metadata');
    await _runGit(packageRepository, ['tag', 'camera-0.12.0-ohos-3.35-0.3.0']);
    await File('${packageRepository.path}/fluoh.yaml').delete();

    expect(
      await runFluoh(
        ['source', 'sync', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final manifest = File(
      '${source.path}/manifests/camera/fluoh.yaml',
    ).readAsStringSync();
    expect(manifest, contains('upstream:\n            version: 0.11.0'));
    expect(manifest, contains('ref: camera-v0.11.0'));
    expect(manifest, contains('- version: 0.2.0'));
    expect(manifest, contains('upstream:\n            version: 0.12.0'));
    expect(manifest, contains('ref: camera-v0.12.0'));
    expect(
      manifest,
      contains('commit: "2222222222222222222222222222222222222222"'),
    );
    expect(manifest, contains('- version: 0.3.0'));
    expect(
      stdout,
      contains(
        'Synced source metadata for camera from ${packageRepository.path}',
      ),
    );
    expect(stderr, isEmpty);
  });

  test('source sync can emit json results', () async {
    final environment = await createTestEnvironment();
    final source = Directory('${environment.homeDirectory.path}/json_source');
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/json_packages_implementation',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'init', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    await _writePackageManifest(packageRepository);
    await _writeSourceSyncManifest(source, packageRepository);
    await initializeGitRepository(packageRepository);
    await _runGit(packageRepository, ['tag', 'camera-0.11.0-ohos-3.35-0.2.0']);
    stdout.clear();

    expect(
      await runFluoh(
        ['source', 'sync', '--json'],
        environment: FluohEnvironment(
          homeDirectory: environment.homeDirectory,
          workingDirectory: source,
        ),
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('schema', 1));
    expect(report, containsPair('command', 'source sync'));
    expect(report, containsPair('ok', true));
    expect(report, containsPair('exitCode', 0));
    expect(report, containsPair('synced', 1));
    final packages = report['packages'] as List<Object?>;
    expect(
      packages,
      contains(
        allOf(
          containsPair('package', 'camera'),
          containsPair('status', 'synced'),
        ),
      ),
    );
    expect(stderr, isEmpty);
  });

  test(
    'source sync skips package tags for SDK lines missing from the source',
    () async {
      final environment = await createTestEnvironment();
      final source = Directory(
        '${environment.homeDirectory.path}/missing_sdk_source',
      );
      final packageRepository = Directory(
        '${environment.homeDirectory.path}/missing_sdk_package',
      );
      final stdout = <String>[];
      final stderr = <String>[];

      await runFluoh(
        ['source', 'init', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      await _writePackageManifest(
        packageRepository,
        sdkVersion: '3.36.1-ohos-0.0.1',
      );
      await _writeSourceSyncManifest(
        source,
        packageRepository,
        sdkVersions: const ['3.35.8-ohos-0.0.3'],
      );
      await initializeGitRepository(packageRepository);
      await _runGit(packageRepository, [
        'tag',
        'camera-0.11.0-ohos-3.36-0.2.0',
      ]);
      stdout.clear();

      expect(
        await runFluoh(
          ['source', 'sync', '--json'],
          environment: FluohEnvironment(
            homeDirectory: environment.homeDirectory,
            workingDirectory: source,
          ),
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final report = jsonDecode(stdout.single) as Map<String, Object?>;
      expect(report, containsPair('synced', 0));
      expect(report, containsPair('skippedTags', 1));
      expect(report['packages'], isEmpty);
      final plan = report['plan'] as List<Object?>;
      final routePlan = plan.single as Map<String, Object?>;
      expect(routePlan, containsPair('status', 'skipped'));
      expect(routePlan, containsPair('tagsToSync', isEmpty));
      final skippedTags = routePlan['skippedTags'] as List<Object?>;
      expect(
        skippedTags.single,
        allOf(
          containsPair('tag', 'camera-0.11.0-ohos-3.36-0.2.0'),
          containsPair('sdkLine', '3.36'),
          containsPair('reason', 'sdk-line-not-in-source'),
        ),
      );
      final manifest = File(
        '${source.path}/manifests/camera/fluoh.yaml',
      ).readAsStringSync();
      expect(manifest, isNot(contains('"3.36"')));
      expect(stderr, isEmpty);
    },
  );

  test('source sync skips invalid package release tag metadata', () async {
    final environment = await createTestEnvironment();
    final source = Directory(
      '${environment.homeDirectory.path}/invalid_tag_source',
    );
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/invalid_tag_package',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'init', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    await _writeSourceSyncManifest(source, packageRepository);
    await packageRepository.create(recursive: true);
    await File('${packageRepository.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: package
''');
    await initializeGitRepository(packageRepository);
    await _runGit(packageRepository, ['tag', 'camera-0.11.0-ohos-3.35-0.2.0']);
    stdout.clear();
    stderr.clear();

    expect(
      await runFluoh(
        ['source', 'sync', '--json', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('synced', 0));
    expect(report, containsPair('skippedTags', 1));
    expect(report['packages'], isEmpty);
    final plan = report['plan'] as List<Object?>;
    final routePlan = plan.single as Map<String, Object?>;
    expect(routePlan, containsPair('status', 'skipped'));
    expect(routePlan, containsPair('tagsToSync', isEmpty));
    final skippedTags = routePlan['skippedTags'] as List<Object?>;
    expect(
      skippedTags.single,
      allOf(
        containsPair('tag', 'camera-0.11.0-ohos-3.35-0.2.0'),
        containsPair('sdkLine', '3.35'),
        containsPair('reason', 'invalid-package-manifest'),
      ),
    );
    expect(stderr, isEmpty);
  });

  test('source sync skips package tags with a different package path', () async {
    final environment = await createTestEnvironment();
    final source = Directory(
      '${environment.homeDirectory.path}/path_mismatch_source',
    );
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/path_mismatch_package',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'init', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    await _writePackageManifest(
      packageRepository,
      packagePath: 'packages/camera/camera_ohos',
    );
    await _writeSourceSyncManifest(source, packageRepository);
    await initializeGitRepository(packageRepository);
    await _runGit(packageRepository, ['tag', 'camera-0.11.0-ohos-3.35-0.2.0']);
    stdout.clear();
    stderr.clear();

    expect(
      await runFluoh(
        ['source', 'sync', '--json', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('synced', 0));
    expect(report, containsPair('skippedTags', 1));
    expect(report['packages'], isEmpty);
    final plan = report['plan'] as List<Object?>;
    final routePlan = plan.single as Map<String, Object?>;
    expect(routePlan, containsPair('status', 'skipped'));
    expect(routePlan, containsPair('tagsToSync', isEmpty));
    final skippedTags = routePlan['skippedTags'] as List<Object?>;
    expect(
      skippedTags.single,
      allOf(
        containsPair('tag', 'camera-0.11.0-ohos-3.35-0.2.0'),
        containsPair('sdkLine', '3.35'),
        containsPair('reason', 'package-path-mismatch'),
        containsPair(
          'message',
          'package.path is packages/camera/camera_ohos, expected packages/camera/camera',
        ),
      ),
    );
    expect(stderr, isEmpty);
  });

  test(
    'source sync does not open repositories when tags are current',
    () async {
      final environment = await createTestEnvironment();
      final source = Directory('${environment.homeDirectory.path}/json_source');
      final packageRepository = Directory(
        '${environment.homeDirectory.path}/current_packages_implementation',
      );
      final stdout = <String>[];
      final stderr = <String>[];

      await runFluoh(
        ['source', 'init', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      await packageRepository.create(recursive: true);
      await File('${packageRepository.path}/README.md').writeAsString('repo');
      await _writeSourceSyncManifest(source, packageRepository);
      await initializeGitRepository(packageRepository);
      await _runGit(packageRepository, [
        'tag',
        'camera-0.10.0-ohos-3.35-0.1.0',
      ]);
      stdout.clear();

      expect(
        await runFluoh(
          ['source', 'sync', '--json', source.path],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final report = jsonDecode(stdout.single) as Map<String, Object?>;
      expect(report, containsPair('command', 'source sync'));
      expect(report, containsPair('synced', 0));
      expect(report, containsPair('skipped', 0));
      expect(report['packages'], isEmpty);
      final plan = report['plan'] as List<Object?>;
      final routePlan = plan.single as Map<String, Object?>;
      expect(routePlan, containsPair('status', 'up-to-date'));
      expect(routePlan, containsPair('tagsToSync', isEmpty));
      expect(routePlan['knownTags'], contains('camera-0.10.0-ohos-3.35-0.1.0'));
      expect(stderr, isEmpty);
    },
  );

  test('source sync json usage errors keep a stable command name', () async {
    final environment = await createTestEnvironment();
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['source', 'sync', 'missing-source', '--json'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('command', 'source sync'));
    expect(report, containsPair('ok', false));
    expect(report, containsPair('exitCode', 64));
    expect(report['error'], isA<Map<String, Object?>>());
    expect(stderr, isEmpty);
  });

  test(
    'source check validates changed manifests and declared package releases',
    () async {
      final environment = await createTestEnvironment();
      final root = environment.homeDirectory;
      final fluoh = await _writeFakeSourceCheckFluoh(root);
      final source = Directory('${root.path}/source');
      final packageRepository = Directory('${root.path}/camera_ohos');
      final checkWorkRoot = Directory('${root.path}/check');
      final stdout = <String>[];
      final stderr = <String>[];

      await _writePackageManifest(
        packageRepository,
        repositoryUrl: packageRepository.path,
        name: 'camera',
        releaseVersion: '1.0.0',
        upstreamVersion: '0.11.0',
      );
      await initializeGitRepository(packageRepository);
      await _runGit(packageRepository, ['checkout', '-b', 'ohos/3.35/camera']);
      await _runGit(packageRepository, [
        'tag',
        'camera-0.11.0-ohos-3.35-1.0.0',
      ]);

      await source.create(recursive: true);
      await File('${source.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: source
name: test-source
manifests: []
''');
      await initializeGitRepository(source);
      await _runGit(source, ['checkout', '-b', 'pr/add-camera']);
      await Directory(
        '${source.path}/manifests/camera',
      ).create(recursive: true);
      await File('${source.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: source
name: test-source

manifests:
  - name: camera
''');
      await File('${source.path}/manifests/camera/fluoh.yaml').writeAsString('''
schema: 1
kind: manifest

repository:
  git:
    url: ${packageRepository.path}

origin:
  kind: ported

upstream:
  git:
    url: https://github.com/flutter/packages

package:
  name: camera
  path: packages/camera/camera
  sdks:
    "3.35":
      releases:
        - version: "1.0.0"
          tag: camera-0.11.0-ohos-3.35-1.0.0
          upstream:
            version: "0.11.0"
            ref: "1111111111111111111111111111111111111111"
            commit: "1111111111111111111111111111111111111111"
''');
      await commitAll(source, message: 'Add camera manifest');

      expect(
        await runFluoh(
          [
            'source',
            'check',
            '--base-ref',
            'main',
            '--fluoh-command',
            fluoh.path,
            '--work-root',
            checkWorkRoot.path,
            '--json',
          ],
          environment: FluohEnvironment(
            homeDirectory: environment.homeDirectory,
            workingDirectory: source,
          ),
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      expect(stderr, isEmpty);
      expect(stdout, hasLength(1));
      final report = jsonDecode(stdout.single) as Map<String, Object?>;
      expect(report, containsPair('schema', 1));
      expect(report, containsPair('command', 'source check'));
      expect(report, containsPair('ok', true));
      expect(report, containsPair('exitCode', 0));
      expect(report, containsPair('recommendation', 'ready'));
      expect(report, containsPair('all', false));
      expect(report, containsPair('checkedManifests', ['camera']));
      expect(report['errors'], isEmpty);
      final checkedManifestDetails = report['manifests'] as List<Object?>;
      final checkedManifest =
          checkedManifestDetails.single as Map<String, Object?>;
      expect(checkedManifest, containsPair('name', 'camera'));
      expect(
        checkedManifest,
        containsPair('packagePath', 'packages/camera/camera'),
      );
      expect(checkedManifest, isNot(contains('repositoryPath')));
      expect(checkedManifest, isNot(contains('upstreamPath')));
      expect(checkedManifest, isNot(contains('packages')));
      expect(checkedManifest['package'], containsPair('name', 'camera'));
      expect(
        checkedManifest['package'],
        containsPair('path', 'packages/camera/camera'),
      );
      final sourceValidation =
          report['sourceValidation'] as Map<String, Object?>;
      expect(sourceValidation, containsPair('ok', true));
      expect(report['sourceCheckout'], containsPair('kind', 'local'));
      final releaseChecks = report['releaseChecks'] as List<Object?>;
      final manifestCheck = releaseChecks.single as Map<String, Object?>;
      expect(manifestCheck, containsPair('manifest', 'camera'));
      expect(manifestCheck, containsPair('ok', true));
      final releaseCheckPlan =
          report['releaseCheckPlan'] as Map<String, Object?>;
      final releaseCheckPlanItems = releaseCheckPlan['items'] as List<Object?>;
      expect(releaseCheckPlanItems, hasLength(1));
      expect(
        releaseCheckPlanItems.single,
        containsPair('reason', 'new-manifest'),
      );
      final checks = manifestCheck['checks'] as List<Object?>;
      final releaseCheck = checks.single as Map<String, Object?>;
      expect(releaseCheck, containsPair('package', 'camera'));
      expect(
        releaseCheck,
        containsPair('tag', 'camera-0.11.0-ohos-3.35-1.0.0'),
      );
      expect(releaseCheck, containsPair('branch', 'ohos/3.35/camera'));
      expect(releaseCheck, containsPair('ok', true));
      final packageCheck = releaseCheck['packageCheck'] as Map<String, Object?>;
      expect(
        packageCheck['command'],
        containsAll([
          fluoh.path,
          'package',
          'check',
          '--package',
          'camera',
          '--json',
        ]),
      );

      stdout.clear();
      stderr.clear();
      expect(
        await runFluoh(
          ['source', 'check', '--all', '--skip-release-checks', '--json'],
          environment: FluohEnvironment(
            homeDirectory: environment.homeDirectory,
            workingDirectory: source,
          ),
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );
      expect(stderr, isEmpty);
      final allReport = jsonDecode(stdout.single) as Map<String, Object?>;
      expect(allReport, containsPair('command', 'source check'));
      expect(allReport, containsPair('all', true));
      expect(allReport, containsPair('changedFiles', isEmpty));
      expect(allReport, containsPair('checkedManifests', ['camera']));
      expect(allReport['warnings'], isEmpty);
      expect(allReport['releaseChecks'], isEmpty);
      final skippedReleaseChecks =
          allReport['skippedReleaseChecks'] as List<Object?>;
      expect(skippedReleaseChecks, hasLength(1));
      expect(
        skippedReleaseChecks.single,
        containsPair('skipReason', 'release-checks-skipped'),
      );
    },
    skip: Platform.isWindows ? 'uses POSIX test executables' : false,
  );

  test(
    'source check verifies only added release records',
    () async {
      final environment = await createTestEnvironment();
      final root = environment.homeDirectory;
      final fluoh = await _writeFakeSourceCheckFluoh(root);
      final source = Directory('${root.path}/source');
      final packageRepository = Directory('${root.path}/camera_ohos');
      final stdout = <String>[];
      final stderr = <String>[];

      await _writePackageManifest(
        packageRepository,
        repositoryUrl: packageRepository.path,
        name: 'camera',
        releaseVersion: '2.0.0',
        upstreamVersion: '0.12.0',
      );
      await initializeGitRepository(packageRepository);
      await _runGit(packageRepository, ['checkout', '-b', 'ohos/3.35/camera']);
      await _runGit(packageRepository, [
        'tag',
        'camera-0.11.0-ohos-3.35-1.0.0',
      ]);
      await _runGit(packageRepository, [
        'tag',
        'camera-0.12.0-ohos-3.35-2.0.0',
      ]);

      await source.create(recursive: true);
      await _writeCameraSourceManifest(
        source,
        packageRepository,
        releases: const [('1.0.0', '0.11.0')],
      );
      await initializeGitRepository(source);
      await _runGit(source, ['checkout', '-b', 'pr/add-camera-release']);
      await _writeCameraSourceManifest(
        source,
        packageRepository,
        releases: const [('1.0.0', '0.11.0'), ('2.0.0', '0.12.0')],
      );
      await commitAll(source, message: 'Add camera release');

      expect(
        await runFluoh(
          [
            'source',
            'check',
            '--base-ref',
            'main',
            '--fluoh-command',
            fluoh.path,
            '--json',
            source.path,
          ],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      expect(stderr, isEmpty);
      final report = jsonDecode(stdout.single) as Map<String, Object?>;
      expect(report, containsPair('checkedManifests', ['camera']));
      final plan = report['releaseCheckPlan'] as Map<String, Object?>;
      final planned = plan['items'] as List<Object?>;
      expect(planned, hasLength(1));
      expect(
        planned.single,
        allOf(
          containsPair('package', 'camera'),
          containsPair('version', '2.0.0'),
          containsPair('upstreamVersion', '0.12.0'),
          containsPair('reason', 'release-added'),
        ),
      );
      final releaseChecks = report['releaseChecks'] as List<Object?>;
      final manifestCheck = releaseChecks.single as Map<String, Object?>;
      final checks = manifestCheck['checks'] as List<Object?>;
      expect(checks, hasLength(1));
      expect(
        checks.single,
        containsPair('tag', 'camera-0.12.0-ohos-3.35-2.0.0'),
      );
    },
    skip: Platform.isWindows ? 'uses POSIX test executables' : false,
  );

  test(
    'source check rejects missing release tag fields',
    () async {
      final environment = await createTestEnvironment();
      final root = environment.homeDirectory;
      final fluoh = await _writeFakeSourceCheckFluoh(root);
      final source = Directory('${root.path}/source');
      final packageRepository = Directory('${root.path}/camera_ohos');
      final stdout = <String>[];
      final stderr = <String>[];

      await _writePackageManifest(
        packageRepository,
        repositoryUrl: packageRepository.path,
        name: 'camera',
        releaseVersion: '1.0.0',
        upstreamVersion: '0.11.0',
      );
      await initializeGitRepository(packageRepository);
      await _runGit(packageRepository, ['checkout', '-b', 'ohos/3.35/camera']);
      await _runGit(packageRepository, [
        'tag',
        'camera-0.11.0-ohos-3.35-1.0.0',
      ]);

      await source.create(recursive: true);
      await File('${source.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: source
name: test-source
manifests: []
''');
      await initializeGitRepository(source);
      await _runGit(source, ['checkout', '-b', 'pr/add-explicit-tag']);
      await _writeCameraSourceManifestRaw(
        source,
        packageRepository,
        releaseYaml: '''
          - version: "1.0.0"
            upstream:
              version: "0.11.0"
              ref: "1111111111111111111111111111111111111111"
              commit: "1111111111111111111111111111111111111111"
''',
      );
      await commitAll(source, message: 'Add camera release without tag');

      expect(
        await runFluoh(
          [
            'source',
            'check',
            '--base-ref',
            'main',
            '--fluoh-command',
            fluoh.path,
            '--json',
            source.path,
          ],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        1,
      );

      expect(stderr, isEmpty);
      final report = jsonDecode(stdout.single) as Map<String, Object?>;
      expect(report, containsPair('recommendation', 'blocked'));
      expect(
        report['errors'],
        contains(contains('Expected "tag" to be a non-empty value.')),
      );
    },
    skip: Platform.isWindows ? 'uses POSIX test executables' : false,
  );
}
