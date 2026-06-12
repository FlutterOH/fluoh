part of 'source_command_test.dart';

void _registerSourceCommandCheckTests() {
  test(
    'source check rejects release metadata that does not match tag metadata',
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
        'camera-0.12.0-ohos-3.35-1.0.0',
      ]);

      await source.create(recursive: true);
      await _writeCameraSourceManifest(
        source,
        packageRepository,
        releases: const [('1.0.0', '0.11.0')],
      );
      await initializeGitRepository(source);
      await _runGit(source, ['checkout', '-b', 'pr/bad-release-metadata']);
      await _writeCameraSourceManifestRaw(
        source,
        packageRepository,
        releaseYaml: '''
          - version: "1.0.0"
            upstream:
              version: "0.12.0"
              ref: camera-v0.12.0
              commit: "2222222222222222222222222222222222222222"
''',
      );
      await commitAll(source, message: 'Break camera release metadata');

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
        contains(
          contains(
            'Declared release check failed for camera at '
            'camera-0.12.0-ohos-3.35-1.0.0',
          ),
        ),
      );
      expect(
        report['errors'],
        contains(
          contains(
            'upstream ref is 1111111111111111111111111111111111111111, expected camera-v0.12.0',
          ),
        ),
      );
      expect(
        report['errors'],
        contains(
          contains(
            'upstream commit is 1111111111111111111111111111111111111111, expected 2222222222222222222222222222222222222222',
          ),
        ),
      );
      final releaseChecks = report['releaseChecks'] as List<Object?>;
      final manifestCheck = releaseChecks.single as Map<String, Object?>;
      final checks = manifestCheck['checks'] as List<Object?>;
      final check = checks.single as Map<String, Object?>;
      expect(check.containsKey('checkout'), false);
      expect(check.containsKey('packageCheck'), false);
      final metadataCheck = check['metadataCheck'] as Map<String, Object?>;
      expect(metadataCheck, containsPair('ok', false));
      expect(
        metadataCheck['message'],
        contains('upstream version is 0.11.0, expected 0.12.0'),
      );
      expect(
        metadataCheck['message'],
        contains(
          'upstream ref is 1111111111111111111111111111111111111111, expected camera-v0.12.0',
        ),
      );
      expect(
        metadataCheck['message'],
        contains(
          'upstream commit is 1111111111111111111111111111111111111111, expected 2222222222222222222222222222222222222222',
        ),
      );
    },
    skip: Platform.isWindows ? 'uses POSIX test executables' : false,
  );

  test(
    'source check verifies package path changes against tag metadata',
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
      await _writeCameraSourceManifest(
        source,
        packageRepository,
        releases: const [('1.0.0', '0.11.0')],
      );
      await initializeGitRepository(source);
      await _runGit(source, ['checkout', '-b', 'pr/change-upstream-path']);
      await _writeCameraSourceManifest(
        source,
        packageRepository,
        releases: const [('1.0.0', '0.11.0')],
        packagePath: 'packages/camera/camera_android',
      );
      await commitAll(source, message: 'Change camera package path');

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
      final plan = report['releaseCheckPlan'] as Map<String, Object?>;
      final planned = plan['items'] as List<Object?>;
      expect(planned.single, containsPair('reason', 'package-path-changed'));
      expect(
        report['errors'],
        contains(
          contains(
            'package.path is packages/camera/camera, expected '
            'packages/camera/camera_android',
          ),
        ),
      );
      final releaseChecks = report['releaseChecks'] as List<Object?>;
      final manifestCheck = releaseChecks.single as Map<String, Object?>;
      final checks = manifestCheck['checks'] as List<Object?>;
      final check = checks.single as Map<String, Object?>;
      expect(check.containsKey('checkout'), false);
      final metadataCheck = check['metadataCheck'] as Map<String, Object?>;
      expect(metadataCheck, containsPair('ok', false));
    },
    skip: Platform.isWindows ? 'uses POSIX test executables' : false,
  );

  test('source check skips advisory-only manifest changes', () async {
    final environment = await createTestEnvironment();
    final source = Directory('${environment.homeDirectory.path}/source');
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/missing_camera_ohos',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await source.create(recursive: true);
    await _writeCameraSourceManifest(
      source,
      packageRepository,
      releases: const [('1.0.0', '0.11.0')],
    );
    await initializeGitRepository(source);

    await _runGit(source, ['checkout', '-b', 'pr/advisory']);
    await _writeCameraSourceManifest(
      source,
      packageRepository,
      releases: const [('1.0.0', '0.11.0')],
      advisory: 'Known migration note.',
    );
    await commitAll(source, message: 'Add advisory');

    expect(
      await runFluoh(
        ['source', 'check', '--base-ref', 'main', '--json', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(stderr, isEmpty);
    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('recommendation', 'ready'));
    expect(report, containsPair('checkedManifests', ['camera']));
    final plan = report['releaseCheckPlan'] as Map<String, Object?>;
    expect(plan['items'], isEmpty);
    expect(report['releaseChecks'], isEmpty);
  });

  test(
    'source check reports deleted release records without cloning',
    () async {
      final environment = await createTestEnvironment();
      final source = Directory('${environment.homeDirectory.path}/source');
      final packageRepository = Directory(
        '${environment.homeDirectory.path}/missing_camera_ohos',
      );
      final stdout = <String>[];
      final stderr = <String>[];

      await source.create(recursive: true);
      await _writeCameraSourceManifest(
        source,
        packageRepository,
        releases: const [('1.0.0', '0.11.0'), ('2.0.0', '0.12.0')],
      );
      await initializeGitRepository(source);

      await _runGit(source, ['checkout', '-b', 'pr/delete-release']);
      await _writeCameraSourceManifest(
        source,
        packageRepository,
        releases: const [('2.0.0', '0.12.0')],
      );
      await commitAll(source, message: 'Delete old camera release');

      expect(
        await runFluoh(
          ['source', 'check', '--base-ref', 'main', '--json', source.path],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      expect(stderr, isEmpty);
      final report = jsonDecode(stdout.single) as Map<String, Object?>;
      expect(report, containsPair('recommendation', 'ready'));
      expect(report['releaseChecks'], isEmpty);
      expect(report['changeTypes'], contains('release-record-deleted'));
      final skippedReleaseChecks =
          report['skippedReleaseChecks'] as List<Object?>;
      expect(skippedReleaseChecks, hasLength(1));
      expect(
        skippedReleaseChecks.single,
        allOf(
          containsPair('version', '1.0.0'),
          containsPair('tag', 'camera-0.11.0-ohos-3.35-1.0.0'),
          containsPair('skipReason', 'release-deleted'),
        ),
      );
    },
  );

  test(
    'source check supports manifest filters and skipped release plans',
    () async {
      final environment = await createTestEnvironment();
      final source = Directory('${environment.homeDirectory.path}/source');
      final stdout = <String>[];
      final stderr = <String>[];

      await source.create(recursive: true);
      await File('${source.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: source
name: test-source

manifests:
  - name: camera
  - name: path_provider
''');
      await _writeSimpleSourceManifest(source, 'camera');
      await _writeSimpleSourceManifest(source, 'path_provider');

      expect(
        await runFluoh(
          [
            'source',
            'check',
            '--all',
            '--skip-release-checks',
            '--manifest',
            'camera',
            '--package',
            'camera',
            '--shard',
            '1/1',
            '--concurrency',
            '2',
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
      expect(report, containsPair('affectedManifests', ['camera']));
      expect(report['releaseChecks'], isEmpty);
      final skippedReleaseChecks =
          report['skippedReleaseChecks'] as List<Object?>;
      expect(skippedReleaseChecks, hasLength(1));
      expect(
        skippedReleaseChecks.single,
        allOf(
          containsPair('manifest', 'camera'),
          containsPair('package', 'camera'),
          containsPair('skipReason', 'release-checks-skipped'),
        ),
      );
    },
  );

  test(
    'source check rejects mutually exclusive diff options as json',
    () async {
      final environment = await createTestEnvironment();
      final stdout = <String>[];
      final stderr = <String>[];

      expect(
        await runFluoh(
          ['source', 'check', '--all', '--base-ref', 'main', '--json'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        64,
      );

      expect(stderr, isEmpty);
      final report = jsonDecode(stdout.single) as Map<String, Object?>;
      expect(report, containsPair('command', 'source check'));
      expect(report, containsPair('ok', false));
      expect(
        report['errors'],
        contains('--all cannot be used with --base-ref.'),
      );
    },
  );

  test(
    'source check schema-only rejects release and diff options as json',
    () async {
      final environment = await createTestEnvironment();
      final stdout = <String>[];
      final stderr = <String>[];

      expect(
        await runFluoh(
          [
            'source',
            'check',
            '--schema-only',
            '--skip-release-checks',
            '--json',
          ],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        64,
      );

      expect(stderr, isEmpty);
      final report = jsonDecode(stdout.single) as Map<String, Object?>;
      expect(report, containsPair('command', 'source check'));
      expect(report, containsPair('ok', false));
      expect(
        report['errors'],
        contains('--schema-only cannot be used with --skip-release-checks.'),
      );
    },
  );

  test('source check limits root route changes to added manifests', () async {
    final environment = await createTestEnvironment();
    final source = Directory('${environment.homeDirectory.path}/source');
    final stdout = <String>[];
    final stderr = <String>[];

    await source.create(recursive: true);
    await File('${source.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: source
name: test-source

manifests:
  - name: path_provider
  - name: shared_preferences
''');
    await _writeSimpleSourceManifest(source, 'path_provider');
    await _writeSimpleSourceManifest(source, 'shared_preferences');
    await initializeGitRepository(source);

    await _runGit(source, ['checkout', '-b', 'pr/add-camera']);
    await File('${source.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: source
name: test-source

manifests:
  - name: camera
  - name: path_provider
  - name: shared_preferences
''');
    await _writeSimpleSourceManifest(source, 'camera');
    await commitAll(source, message: 'Add camera manifest');

    expect(
      await runFluoh(
        [
          'source',
          'check',
          '--base-ref',
          'main',
          '--skip-release-checks',
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
    expect(report, containsPair('command', 'source check'));
    expect(report, containsPair('ok', true));
    expect(report, containsPair('checkedManifests', ['camera']));
    expect(report['changedFiles'], contains('fluoh.yaml'));
    expect(report['changedFiles'], contains('manifests/camera/fluoh.yaml'));
    expect(report['releaseChecks'], isEmpty);
  });

  test(
    'source check does not expand sdk-only root changes to manifests',
    () async {
      final environment = await createTestEnvironment();
      final source = Directory('${environment.homeDirectory.path}/source');
      final sdkRepository = Directory(
        '${environment.homeDirectory.path}/flutter_ohos_sdk',
      );
      final stdout = <String>[];
      final stderr = <String>[];

      await sdkRepository.create(recursive: true);
      await File('${sdkRepository.path}/README.md').writeAsString('sdk');
      await initializeGitRepository(sdkRepository);
      await _runGit(sdkRepository, ['tag', '3.35.8-ohos-0.0.3']);
      await _runGit(sdkRepository, ['tag', '3.35.8-ohos-1.0.1']);

      await source.create(recursive: true);
      await File('${source.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: source
name: test-source

sdk:
  git:
    url: ${sdkRepository.path}
  versions:
    - 3.35.8-ohos-0.0.3

manifests:
  - name: path_provider
  - name: shared_preferences
''');
      await _writeSimpleSourceManifest(source, 'path_provider');
      await _writeSimpleSourceManifest(source, 'shared_preferences');
      await initializeGitRepository(source);

      await _runGit(source, ['checkout', '-b', 'pr/add-sdk']);
      await File('${source.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: source
name: test-source

sdk:
  git:
    url: ${sdkRepository.path}
  versions:
    - 3.35.8-ohos-0.0.3
    - 3.35.8-ohos-1.0.1

manifests:
  - name: path_provider
  - name: shared_preferences
''');
      await commitAll(source, message: 'Add SDK release');

      expect(
        await runFluoh(
          ['source', 'check', '--base-ref', 'main', '--json', source.path],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      expect(stderr, isEmpty);
      final report = jsonDecode(stdout.single) as Map<String, Object?>;
      expect(report, containsPair('command', 'source check'));
      expect(report, containsPair('ok', true));
      expect(report, containsPair('checkedManifests', isEmpty));
      expect(report['changedFiles'], contains('fluoh.yaml'));
      expect(report['releaseChecks'], isEmpty);
      final sdkChecks = report['sdkChecks'] as List<Object?>;
      expect(sdkChecks, hasLength(1));
      expect(
        sdkChecks.single,
        allOf(
          containsPair('version', '3.35.8-ohos-1.0.1'),
          containsPair('ok', true),
          containsPair('reason', 'added-sdk-release'),
        ),
      );
      expect(report, containsPair('recommendation', 'ready'));
      expect(report['warnings'], isEmpty);
    },
  );

  test(
    'source check scopes source validation for sdk-only pull requests',
    () async {
      final environment = await createTestEnvironment();
      final source = Directory('${environment.homeDirectory.path}/source');
      final sdkRepository = Directory(
        '${environment.homeDirectory.path}/flutter_ohos_sdk',
      );
      final stdout = <String>[];
      final stderr = <String>[];

      await sdkRepository.create(recursive: true);
      await File('${sdkRepository.path}/README.md').writeAsString('sdk');
      await initializeGitRepository(sdkRepository);
      await _runGit(sdkRepository, ['tag', '3.35.8-ohos-0.0.3']);
      await _runGit(sdkRepository, ['tag', '3.35.8-ohos-1.0.1']);

      await source.create(recursive: true);
      await File('${source.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: source
name: test-source

sdk:
  git:
    url: ${sdkRepository.path}
  versions:
    - 3.35.8-ohos-0.0.3

manifests:
  - name: path_provider
  - name: shared_preferences
''');
      await _writeSimpleSourceManifest(source, 'path_provider');
      await _writeSimpleSourceManifest(source, 'shared_preferences');
      await File(
        '${source.path}/manifests/path_provider/fluoh.yaml',
      ).writeAsString('''
schema: 1
kind: manifest

repository:
  git:
    url: file:${source.path}/../path_provider_repo

upstream:
  git:
    url: https://github.com/flutter/packages

package:
  name:
''');
      await initializeGitRepository(source);

      await _runGit(source, ['checkout', '-b', 'pr/add-sdk']);
      await File('${source.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: source
name: test-source

sdk:
  git:
    url: ${sdkRepository.path}
  versions:
    - 3.35.8-ohos-0.0.3
    - 3.35.8-ohos-1.0.1

manifests:
  - name: path_provider
  - name: shared_preferences
''');
      await commitAll(source, message: 'Add SDK release');

      expect(
        await runFluoh(
          ['source', 'check', '--base-ref', 'main', '--json', source.path],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      expect(stderr, isEmpty);
      final prReport = jsonDecode(stdout.single) as Map<String, Object?>;
      expect(prReport, containsPair('recommendation', 'ready'));
      expect(prReport, containsPair('checkedManifests', isEmpty));
      expect(prReport['warnings'], isEmpty);
      final prValidation = prReport['sourceValidation'] as Map<String, Object?>;
      expect(prValidation, containsPair('ok', true));

      stdout.clear();
      stderr.clear();
      expect(
        await runFluoh(
          ['source', 'check', '--skip-release-checks', '--json', source.path],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        1,
      );

      expect(stderr, isEmpty);
      final fullReport = jsonDecode(stdout.single) as Map<String, Object?>;
      expect(fullReport, containsPair('recommendation', 'blocked'));
      final fullValidation =
          fullReport['sourceValidation'] as Map<String, Object?>;
      expect(fullValidation, containsPair('ok', false));
      expect(
        fullReport['errors'],
        contains(contains('Expected "name" to be a non-empty string')),
      );
    },
  );

  test('source check reports missing changed SDK tags', () async {
    final environment = await createTestEnvironment();
    final source = Directory('${environment.homeDirectory.path}/source');
    final sdkRepository = Directory(
      '${environment.homeDirectory.path}/flutter_ohos_sdk',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await sdkRepository.create(recursive: true);
    await File('${sdkRepository.path}/README.md').writeAsString('sdk');
    await initializeGitRepository(sdkRepository);
    await _runGit(sdkRepository, ['tag', '3.35.8-ohos-0.0.3']);

    await source.create(recursive: true);
    await File('${source.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: source
name: test-source

sdk:
  git:
    url: ${sdkRepository.path}
  versions:
    - 3.35.8-ohos-0.0.3
''');
    await initializeGitRepository(source);

    await _runGit(source, ['checkout', '-b', 'pr/add-missing-sdk']);
    await File('${source.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: source
name: test-source

sdk:
  git:
    url: ${sdkRepository.path}
  versions:
    - 3.35.8-ohos-0.0.3
    - 3.35.8-ohos-1.0.1
''');
    await commitAll(source, message: 'Add missing SDK release');

    expect(
      await runFluoh(
        ['source', 'check', '--base-ref', 'main', '--json', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      1,
    );

    expect(stderr, isEmpty);
    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('recommendation', 'blocked'));
    final sdkChecks = report['sdkChecks'] as List<Object?>;
    expect(sdkChecks, hasLength(1));
    expect(
      sdkChecks.single,
      allOf(
        containsPair('version', '3.35.8-ohos-1.0.1'),
        containsPair('ok', false),
      ),
    );
    expect(
      report['errors'],
      contains(startsWith('SDK tag check failed for 3.35.8-ohos-1.0.1:')),
    );
  });

  test('source check reports source validation failures as json', () async {
    final environment = await createTestEnvironment();
    final source = Directory('${environment.homeDirectory.path}/source');
    final stdout = <String>[];
    final stderr = <String>[];

    await source.create(recursive: true);
    await File('${source.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: source
name: broken-source
manifests:
  - name: camera
''');
    await Directory('${source.path}/manifests/camera').create(recursive: true);
    await File('${source.path}/manifests/camera/fluoh.yaml').writeAsString('''
schema: 1
kind: manifest
name:
''');

    expect(
      await runFluoh(
        ['source', 'check', source.path, '--json'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      1,
    );

    expect(stderr, isEmpty);
    expect(stdout, hasLength(1));
    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('command', 'source check'));
    expect(report, containsPair('ok', false));
    expect(report, containsPair('exitCode', 1));
    expect(report, containsPair('recommendation', 'blocked'));
    expect(report, containsPair('checkedManifests', ['camera']));
    expect(report, containsPair('releaseChecks', isEmpty));
    final sourceValidation = report['sourceValidation'] as Map<String, Object?>;
    expect(sourceValidation, containsPair('ok', false));
    expect(report['errors'], contains(startsWith('Source validation failed:')));
  });
}
