import 'dart:io';

import 'package:fluoh/fluoh.dart';
import 'package:test/test.dart';

import '../helpers/fluoh_test_context.dart';
import '../helpers/package_test_context.dart';

void main() {
  test('test init creates automated tests and an example app', () async {
    final environment = await createTestEnvironment();
    final source = await _createFlutterSdkSource(
      environment.homeDirectory,
      logName: 'flutter_args.log',
    );
    await _writeFlutterPluginPackage(environment.workingDirectory);
    await _writePackageManifest(environment.workingDirectory);
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
        ['test', 'init'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final testPubspec = File(
      '${environment.workingDirectory.path}/fluoh_test/camera/pubspec.yaml',
    ).readAsStringSync();
    expect(testPubspec, contains('name: camera_fluoh_test'));
    expect(testPubspec, contains('camera:\n    path: ../..'));
    final gitignore = File(
      '${environment.workingDirectory.path}/fluoh_test/camera/.gitignore',
    ).readAsStringSync();
    expect(gitignore, contains('.flutter-plugins'));
    expect(gitignore, contains('.flutter-plugins-dependencies'));
    expect(gitignore, contains('.packages'));
    expect(gitignore, contains('.pub/'));
    expect(gitignore, contains('.pub-cache/'));
    expect(gitignore, contains('coverage/'));
    expect(gitignore, contains('local.properties'));
    expect(gitignore, contains('example/.flutter-plugins'));
    expect(gitignore, contains('example/.flutter-plugins-dependencies'));
    expect(gitignore, contains('example/.packages'));
    expect(gitignore, contains('example/.pub/'));
    expect(gitignore, contains('example/.pub-cache/'));
    expect(gitignore, contains('example/coverage/'));
    expect(gitignore, contains('example/local.properties'));
    final contractTest = File(
      '${environment.workingDirectory.path}/fluoh_test/camera/test/contract_test.dart',
    ).readAsStringSync();
    expect(contractTest, contains("package:camera/camera.dart"));
    expect(
      contractTest,
      contains('camera public API imports with the FlutterOH SDK'),
    );
    final testReadme = File(
      '${environment.workingDirectory.path}/fluoh_test/camera/README.md',
    ).readAsStringSync();
    expect(testReadme, contains('## Definition Of Done'));
    expect(
      testReadme,
      contains('one visible action per important package workflow'),
    );
    expect(testReadme, contains('pass/fail status'));
    expect(testReadme, contains('fluoh flutter build hap --debug'));
    expect(testReadme, contains('reason`, and `usedScene`'));
    expect(testReadme, contains('## Baseline Before OHOS Work'));
    expect(testReadme, contains('fluoh flutter analyze'));
    expect(testReadme, contains('non-OHOS platform regressions first'));
    expect(testReadme, contains('## What To Edit'));
    expect(testReadme, contains('fluoh_test/camera/test'));
    expect(testReadme, contains('fluoh_test/camera/example/lib/main.dart'));
    expect(testReadme, contains('fluoh deps get'));
    expect(testReadme, contains('then run `fluoh test run --package camera`'));
    final examplePubspec = File(
      '${environment.workingDirectory.path}/fluoh_test/camera/example/pubspec.yaml',
    ).readAsStringSync();
    expect(examplePubspec, contains('camera:\n    path: ../../..'));
    expect(examplePubspec, contains('flutter_lints: ^6.0.0'));
    final exampleFluohYaml = File(
      '${environment.workingDirectory.path}/fluoh_test/camera/example/fluoh.yaml',
    ).readAsStringSync();
    expect(exampleFluohYaml, contains('version: 3.35.8-ohos-0.0.3'));
    final exampleGitignore = File(
      '${environment.workingDirectory.path}/fluoh_test/camera/example/.gitignore',
    ).readAsStringSync();
    expect(exampleGitignore, contains('.fluoh/'));
    final exampleMain = File(
      '${environment.workingDirectory.path}/fluoh_test/camera/example/lib/main.dart',
    ).readAsStringSync();
    expect(exampleMain, contains('Run package import smoke check'));
    expect(exampleMain, contains('Add package-specific OHOS behavior check'));
    expect(exampleMain, contains('expected'));
    expect(exampleMain, contains('VerificationStatus'));
    expect(exampleMain, contains('failure hint'));
    expect(exampleMain, contains('Platforms: android, ios, ohos'));
    final exampleTest = File(
      '${environment.workingDirectory.path}/fluoh_test/camera/example/test/widget_test.dart',
    ).readAsStringSync();
    expect(exampleTest, contains("find.text('Platforms: android, ios, ohos')"));
    expect(exampleTest, contains('reports import smoke success'));
    expect(
      exampleTest,
      contains(
        "find.widgetWithText(FilledButton, 'Run package import smoke check')",
      ),
    );
    expect(
      Directory(
        '${environment.workingDirectory.path}/fluoh_test/camera/example/ohos',
      ).existsSync(),
      isTrue,
    );
    final flutterLog = File(
      '${environment.homeDirectory.path}/flutter_args.log',
    ).readAsStringSync();
    expect(flutterLog, contains('create --no-pub --project-name'));
    expect(flutterLog, contains('--platforms=android,ios,ohos'));
    expect(stdout, contains('Created fluoh_test/camera for camera.'));
    expect(stderr, isEmpty);
  });

  test(
    'test commands use package-scoped workspaces for package manifests',
    () async {
      final environment = await createTestEnvironment();
      final source = await _createFlutterSdkSource(
        environment.homeDirectory,
        logName: 'workspace_root_flutter_args.log',
      );
      await _writeFlutterPluginPackage(environment.workingDirectory);
      await _writePackageManifest(environment.workingDirectory);
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
          ['test', 'init'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      expect(
        File(
          '${environment.workingDirectory.path}/fluoh_test/camera/pubspec.yaml',
        ).existsSync(),
        isTrue,
      );
      expect(stdout, contains('Created fluoh_test/camera for camera.'));

      await File(
        '${environment.homeDirectory.path}/workspace_root_flutter_args.log',
      ).writeAsString('');
      expect(
        await runFluoh(
          ['test', 'run'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final flutterLog = File(
        '${environment.homeDirectory.path}/workspace_root_flutter_args.log',
      ).readAsStringSync();
      _expectInOrder(flutterLog, [
        '${environment.workingDirectory.path}::pub get',
        '${environment.workingDirectory.path}::test',
        '${environment.workingDirectory.path}/fluoh_test/camera::pub get',
        '${environment.workingDirectory.path}/fluoh_test/camera::test',
        '${environment.workingDirectory.path}/fluoh_test/camera/example::pub get',
        '${environment.workingDirectory.path}/fluoh_test/camera/example::test',
      ]);
      expect(stdout, contains('fluoh_test/camera passed.'));
      expect(stdout, contains('fluoh_test/camera/example passed.'));
      expect(stderr, isEmpty);
    },
  );

  test(
    'test init uses package-scoped tests for root package manifests',
    () async {
      final environment = await createTestEnvironment();
      final source = await _createFlutterSdkSource(
        environment.homeDirectory,
        logName: 'root_manifest_flutter_args.log',
      );
      await _writeFlutterPluginPackage(environment.workingDirectory);
      await File(
        '${environment.workingDirectory.path}/fluoh.yaml',
      ).writeAsString('''
schema: 1
name: camera

sdk:
  version: 3.35.8-ohos-0.0.3

repository:
  git:
    url: git@github.com:FlutterOH/camera.git
    branch: ohos/3.35

upstream:
  git:
    url: https://github.com/flutter/packages.git
    branch: main

packages:
  camera:
    version: 0.1.0
    upstreamVersion: 0.11.0
    status: experimental
''');
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
          ['test', 'init'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      expect(
        File(
          '${environment.workingDirectory.path}/fluoh_test/camera/pubspec.yaml',
        ).existsSync(),
        isTrue,
      );
      expect(
        File(
          '${environment.workingDirectory.path}/fluoh_test/pubspec.yaml',
        ).existsSync(),
        isFalse,
      );
      expect(stdout, contains('Created fluoh_test/camera for camera.'));
      expect(stderr, isEmpty);
    },
  );

  test(
    'test init uses package-scoped tests for package path manifests',
    () async {
      final environment = await createTestEnvironment();
      final source = await _createFlutterSdkSource(
        environment.homeDirectory,
        logName: 'path_manifest_flutter_args.log',
      );
      await _writeFlutterPluginPackage(
        Directory('${environment.workingDirectory.path}/packages/camera'),
      );
      await File(
        '${environment.workingDirectory.path}/fluoh.yaml',
      ).writeAsString('''
schema: 1
name: camera

sdk:
  version: 3.35.8-ohos-0.0.3

repository:
  git:
    url: git@github.com:FlutterOH/camera.git
    branch: ohos/3.35

upstream:
  git:
    url: https://github.com/flutter/packages.git
    branch: main

packages:
  camera:
    repository:
      path: packages/camera
    upstream:
      path: packages/camera
    version: 0.1.0
    upstreamVersion: 0.11.0
    status: experimental
''');
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
          ['test', 'init'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      expect(
        File(
          '${environment.workingDirectory.path}/fluoh_test/camera/pubspec.yaml',
        ).existsSync(),
        isTrue,
      );
      expect(
        File(
          '${environment.workingDirectory.path}/fluoh_test/pubspec.yaml',
        ).existsSync(),
        isFalse,
      );
      final testPubspec = File(
        '${environment.workingDirectory.path}/fluoh_test/camera/pubspec.yaml',
      ).readAsStringSync();
      expect(testPubspec, contains('path: ../../packages/camera'));
      expect(stdout, contains('Created fluoh_test/camera for camera.'));
      expect(stderr, isEmpty);
    },
  );

  test('test commands honor repository git path defaults', () async {
    final environment = await createTestEnvironment();
    final source = await _createFlutterSdkSource(
      environment.homeDirectory,
      logName: 'default_path_manifest_flutter_args.log',
    );
    final packageDirectory = Directory(
      '${environment.workingDirectory.path}/packages/camera',
    );
    await _writeFlutterPluginPackage(packageDirectory);
    await File('${environment.workingDirectory.path}/fluoh.yaml').writeAsString(
      '''
schema: 1
name: camera

sdk:
  version: 3.35.8-ohos-0.0.3

repository:
  git:
    url: git@github.com:FlutterOH/camera.git
    branch: ohos/3.35
    path: packages/camera

upstream:
  git:
    url: https://github.com/flutter/packages.git
    branch: main
    path: packages/camera

packages:
  camera:
    version: 0.1.0
    upstreamVersion: 0.11.0
    status: experimental
''',
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
        ['test', 'init'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final testPubspec = File(
      '${environment.workingDirectory.path}/fluoh_test/camera/pubspec.yaml',
    ).readAsStringSync();
    expect(testPubspec, contains('path: ../../packages/camera'));
    await File(
      '${environment.homeDirectory.path}/default_path_manifest_flutter_args.log',
    ).writeAsString('');

    expect(
      await runFluoh(
        ['test', 'run'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final flutterLog = File(
      '${environment.homeDirectory.path}/default_path_manifest_flutter_args.log',
    ).readAsStringSync();
    _expectInOrder(flutterLog, [
      '${packageDirectory.path}::pub get',
      '${packageDirectory.path}::test',
      '${environment.workingDirectory.path}/fluoh_test/camera::pub get',
      '${environment.workingDirectory.path}/fluoh_test/camera::test',
      '${environment.workingDirectory.path}/fluoh_test/camera/example::pub get',
      '${environment.workingDirectory.path}/fluoh_test/camera/example::test',
    ]);
    expect(stdout, contains('Created fluoh_test/camera for camera.'));
    expect(stdout, contains('fluoh_test/camera passed.'));
    expect(stdout, contains('fluoh_test/camera/example passed.'));
    expect(stderr, isEmpty);
  });

  test('test run executes package tests before fluoh_test tests', () async {
    final environment = await createTestEnvironment();
    final source = await _createFlutterSdkSource(
      environment.homeDirectory,
      logName: 'flutter_run_args.log',
    );
    await _writeFlutterPluginPackage(environment.workingDirectory);
    await _writePackageManifest(environment.workingDirectory);
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'add', 'fixture', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    await runFluoh(
      ['test', 'init'],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    await File(
      '${environment.homeDirectory.path}/flutter_run_args.log',
    ).writeAsString('');

    expect(
      await runFluoh(
        ['test', 'run'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final flutterLog = File(
      '${environment.homeDirectory.path}/flutter_run_args.log',
    ).readAsStringSync();
    _expectInOrder(flutterLog, [
      '${environment.workingDirectory.path}::pub get',
      '${environment.workingDirectory.path}::test',
      '${environment.workingDirectory.path}/fluoh_test/camera::pub get',
      '${environment.workingDirectory.path}/fluoh_test/camera::test',
      '${environment.workingDirectory.path}/fluoh_test/camera/example::pub get',
      '${environment.workingDirectory.path}/fluoh_test/camera/example::test',
    ]);
    expect(stdout, contains('Running camera package Flutter tests.'));
    expect(stdout, contains('camera package tests passed.'));
    expect(stdout, contains('fluoh_test/camera passed.'));
    expect(stdout, contains('fluoh_test/camera/example passed.'));
    expect(stderr, isEmpty);
  });

  test('test run skips package tests when the package has none', () async {
    final environment = await createTestEnvironment();
    final source = await _createFlutterSdkSource(
      environment.homeDirectory,
      logName: 'no_package_tests_flutter_run_args.log',
    );
    await _writeFlutterPluginPackage(environment.workingDirectory);
    await File(
      '${environment.workingDirectory.path}/test/camera_test.dart',
    ).delete();
    await _writePackageManifest(environment.workingDirectory);
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'add', 'fixture', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    await runFluoh(
      ['test', 'init'],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    await File(
      '${environment.homeDirectory.path}/no_package_tests_flutter_run_args.log',
    ).writeAsString('');

    expect(
      await runFluoh(
        ['test', 'run'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final flutterLog = File(
      '${environment.homeDirectory.path}/no_package_tests_flutter_run_args.log',
    ).readAsStringSync();
    expect(
      flutterLog,
      isNot(contains('${environment.workingDirectory.path}::test')),
    );
    _expectInOrder(flutterLog, [
      '${environment.workingDirectory.path}/fluoh_test/camera::pub get',
      '${environment.workingDirectory.path}/fluoh_test/camera::test',
      '${environment.workingDirectory.path}/fluoh_test/camera/example::pub get',
      '${environment.workingDirectory.path}/fluoh_test/camera/example::test',
    ]);
    expect(
      stdout,
      contains('Skipping camera package tests: no test files found.'),
    );
    expect(stdout, contains('fluoh_test/camera passed.'));
    expect(stdout, contains('fluoh_test/camera/example passed.'));
    expect(stderr, isEmpty);
  });

  test('test run executes package tests from package manifest path', () async {
    final environment = await createTestEnvironment();
    final source = await _createFlutterSdkSource(
      environment.homeDirectory,
      logName: 'workspace_flutter_run_args.log',
    );
    final packageDirectory = Directory(
      '${environment.workingDirectory.path}/packages/camera/camera',
    );
    await _writeFlutterPluginPackage(packageDirectory);
    await _writePackageManifest(
      environment.workingDirectory,
      packagePath: 'packages/camera/camera',
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
      ['test', 'init'],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    expect(
      File(
        '${environment.workingDirectory.path}/fluoh_test/camera/pubspec.yaml',
      ).existsSync(),
      isTrue,
    );
    expect(
      Directory(
        '${environment.workingDirectory.path}/fluoh_test/example',
      ).existsSync(),
      isFalse,
    );
    await File(
      '${environment.homeDirectory.path}/workspace_flutter_run_args.log',
    ).writeAsString('');

    expect(
      await runFluoh(
        ['test', 'run'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final flutterLog = File(
      '${environment.homeDirectory.path}/workspace_flutter_run_args.log',
    ).readAsStringSync();
    _expectInOrder(flutterLog, [
      '${packageDirectory.path}::pub get',
      '${packageDirectory.path}::test',
      '${environment.workingDirectory.path}/fluoh_test/camera::pub get',
      '${environment.workingDirectory.path}/fluoh_test/camera::test',
      '${environment.workingDirectory.path}/fluoh_test/camera/example::pub get',
      '${environment.workingDirectory.path}/fluoh_test/camera/example::test',
    ]);
    expect(stdout, contains('Created fluoh_test/camera for camera.'));
    expect(stdout, contains('Running camera package Flutter tests.'));
    expect(stdout, contains('camera package tests passed.'));
    expect(stdout, contains('fluoh_test/camera passed.'));
    expect(stdout, contains('fluoh_test/camera/example passed.'));
    expect(stderr, isEmpty);
  });

  test('test init skips packages that do not use Flutter', () async {
    final environment = await createTestEnvironment();
    await File(
      '${environment.workingDirectory.path}/pubspec.yaml',
    ).writeAsString('''
name: dart_only
version: 1.0.0

environment:
  sdk: ^3.0.0
''');
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['test', 'init'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(
      Directory('${environment.workingDirectory.path}/fluoh_test').existsSync(),
      isFalse,
    );
    expect(
      stdout,
      contains('Skipping fluoh test init: dart_only is not a Flutter package.'),
    );
    expect(stderr, isEmpty);
  });

  test(
    'package create initializes and stages fluoh_test for Flutter implementations',
    () async {
      final environment = await createTestEnvironment();
      final source = await _createFlutterSdkSource(
        environment.homeDirectory,
        logName: 'package_create_flutter_args.log',
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
        File(
          '${packageRepository.path}/fluoh_test/camera/pubspec.yaml',
        ).existsSync(),
        isTrue,
      );
      expect(
        File(
          '${packageRepository.path}/fluoh_test/camera/example/lib/main.dart',
        ).existsSync(),
        isTrue,
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
          '.gitignore',
          'FLUOH.md',
          'FLUOH_CHANGELOG.md',
          'fluoh.yaml',
          'fluoh_test/camera/pubspec.yaml',
          'fluoh_test/camera/example/fluoh.yaml',
          'fluoh_test/camera/test/contract_test.dart',
          'fluoh_test/camera/example/test/widget_test.dart',
        ]),
      );
      expect(staged.stdout.toString(), isNot(contains('local.properties')));
      expect(
        staged.stdout.toString(),
        isNot(contains('.flutter-plugins-dependencies')),
      );
      expect(staged.stdout.toString(), isNot(contains('.fluoh')));
      expect(stdout, contains('Created fluoh_test/camera for camera.'));
      expect(
        stdout,
        contains('Creating fluoh_test/camera/example for android,ios,ohos.'),
      );
      expect(stdout.join('\n'), isNot(contains('fluoh flutter create')));
      expect(stdout, isNot(contains('flutter create stdout')));
      expect(stderr, isEmpty);
    },
  );

  test(
    'package create initializes root and nested Flutter packages when selected',
    () async {
      final environment = await createTestEnvironment();
      final source = await _createFlutterSdkSource(
        environment.homeDirectory,
        logName: 'package_create_root_nested_flutter_args.log',
      );
      final upstream = await _createUpstreamFlutterPluginRepository(
        Directory('${environment.homeDirectory.path}/upstream_root_nested'),
      );
      await _writeFlutterPluginPackage(
        Directory('${upstream.path}/packages/share_plus/share_plus'),
        packageName: 'share_plus',
      );
      await _runProcess('git', ['add', '.'], upstream);
      await _runProcess('git', [
        'commit',
        '-m',
        'Add nested Flutter package',
      ], upstream);
      final packageRepository = Directory(
        '${environment.homeDirectory.path}/package_root_nested',
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
            '.',
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
        ),
        0,
      );

      final manifest = File(
        '${packageRepository.path}/fluoh.yaml',
      ).readAsStringSync();
      expect(manifest, contains('packages:\n  camera:'));
      expect(manifest, contains('  share_plus:'));
      expect(manifest, contains('path: packages/share_plus/share_plus'));
      expect(
        File(
          '${packageRepository.path}/fluoh_test/camera/pubspec.yaml',
        ).existsSync(),
        isTrue,
      );
      expect(
        File(
          '${packageRepository.path}/fluoh_test/share_plus/pubspec.yaml',
        ).existsSync(),
        isTrue,
      );
      expect(stdout, contains('Created fluoh_test/camera for camera.'));
      expect(stdout, contains('Created fluoh_test/share_plus for share_plus.'));
      expect(
        stdout,
        contains(
          'Selected package share_plus at packages/share_plus/share_plus.',
        ),
      );
      expect(stderr, isEmpty);
    },
  );

  test(
    'package create replays flutter create output when example creation fails',
    () async {
      final environment = await createTestEnvironment();
      final source = await _createFlutterSdkSource(
        environment.homeDirectory,
        logName: 'package_create_flutter_create_failure.log',
        failCreate: true,
      );
      final upstream = await _createUpstreamFlutterPluginRepository(
        Directory('${environment.homeDirectory.path}/upstream_failed_camera'),
      );
      final packageRepository = Directory(
        '${environment.homeDirectory.path}/package_failed_camera',
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

      expect(stdout, contains('flutter create stdout'));
      expect(stderr, contains('flutter create stderr'));
      expect(
        stderr.join('\n'),
        contains('flutter create failed for fluoh_test/camera/example.'),
      );
    },
  );

  test('package add creates a package-scoped fluoh_test workspace', () async {
    final environment = await createTestEnvironment();
    final source = await _createFlutterSdkSource(
      environment.homeDirectory,
      logName: 'package_add_flutter_args.log',
    );
    await _writeFlutterPluginPackage(
      Directory('${environment.workingDirectory.path}/packages/camera/camera'),
    );
    await _writePackageManifest(
      environment.workingDirectory,
      packagePath: 'packages/camera/camera',
    );
    await _writeFlutterPluginPackage(
      Directory(
        '${environment.workingDirectory.path}/packages/share_plus/share_plus',
      ),
      packageName: 'share_plus',
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
      ['test', 'init'],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    await initializeGitRepository(environment.workingDirectory);
    await runGit(environment.workingDirectory, ['checkout', '-b', 'ohos/3.35']);
    stdout.clear();
    stderr.clear();

    expect(
      await runFluoh(
        [
          'package',
          'add',
          'packages/share_plus/share_plus',
          '--expected-package',
          'share_plus',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(
      File(
        '${environment.workingDirectory.path}/fluoh_test/pubspec.yaml',
      ).existsSync(),
      isFalse,
    );
    expect(
      File(
        '${environment.workingDirectory.path}/fluoh_test/camera/pubspec.yaml',
      ).existsSync(),
      isTrue,
    );
    final cameraReadme = File(
      '${environment.workingDirectory.path}/fluoh_test/camera/README.md',
    ).readAsStringSync();
    expect(cameraReadme, contains('\nfluoh test run --package camera\n'));
    expect(
      cameraReadme,
      contains('runs the tests in this `fluoh_test/camera` package'),
    );
    expect(cameraReadme, isNot(contains('\nfluoh test run\n')));
    expect(
      File(
        '${environment.workingDirectory.path}/fluoh_test/share_plus/pubspec.yaml',
      ).existsSync(),
      isTrue,
    );
    final status = await runGit(environment.workingDirectory, [
      'status',
      '--short',
    ]);
    expect(
      status.stdout.toString(),
      contains('fluoh_test/share_plus/pubspec.yaml'),
    );
    expect(stdout, contains('Created fluoh_test/share_plus for share_plus.'));
    expect(stderr, isEmpty);
  });

  test(
    'package add rolls back added fluoh_test workspace when test init fails',
    () async {
      final environment = await createTestEnvironment();
      final source = await _createFlutterSdkSource(
        environment.homeDirectory,
        logName: 'package_add_rollback_flutter_args.log',
      );
      await _writeFlutterPluginPackage(
        Directory(
          '${environment.workingDirectory.path}/packages/camera/camera',
        ),
      );
      await _writePackageManifest(
        environment.workingDirectory,
        packagePath: 'packages/camera/camera',
      );
      await _writeFlutterPluginPackage(
        Directory(
          '${environment.workingDirectory.path}/packages/share_plus/share_plus',
        ),
        packageName: 'share_plus',
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
        ['test', 'init'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      await initializeGitRepository(environment.workingDirectory);
      await runGit(environment.workingDirectory, [
        'checkout',
        '-b',
        'ohos/3.35',
      ]);
      await File(
        '${environment.homeDirectory.path}/sdks/3.35.8-ohos-0.0.3/bin/flutter',
      ).writeAsString(_fakeFlutterScript('unused', failCreate: true));
      stdout.clear();
      stderr.clear();

      expect(
        await runFluoh(
          [
            'package',
            'add',
            'packages/share_plus/share_plus',
            '--expected-package',
            'share_plus',
          ],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        64,
      );

      final manifest = File(
        '${environment.workingDirectory.path}/fluoh.yaml',
      ).readAsStringSync();
      expect(manifest, isNot(contains('share_plus:')));
      expect(
        File(
          '${environment.workingDirectory.path}/fluoh_test/camera/pubspec.yaml',
        ).existsSync(),
        isTrue,
      );
      expect(
        Directory(
          '${environment.workingDirectory.path}/fluoh_test/share_plus',
        ).existsSync(),
        isFalse,
      );
      expect(stderr.join('\n'), contains('flutter create failed'));
    },
  );

  test('package add extends a single-package manifest', () async {
    final environment = await createTestEnvironment();
    final source = await _createFlutterSdkSource(
      environment.homeDirectory,
      logName: 'package_add_single_package_args.log',
    );
    await _writeFlutterPluginPackage(environment.workingDirectory);
    await _writePackageManifest(environment.workingDirectory);
    await _writeFlutterPluginPackage(
      Directory(
        '${environment.workingDirectory.path}/packages/share_plus/share_plus',
      ),
      packageName: 'share_plus',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'add', 'fixture', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    await initializeGitRepository(environment.workingDirectory);
    await runGit(environment.workingDirectory, ['checkout', '-b', 'ohos/3.35']);
    stdout.clear();
    stderr.clear();

    expect(
      await runFluoh(
        [
          'package',
          'add',
          'packages/share_plus/share_plus',
          '--expected-package',
          'share_plus',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final manifest = File(
      '${environment.workingDirectory.path}/fluoh.yaml',
    ).readAsStringSync();
    expect(manifest, contains('share_plus:'));
    expect(
      File(
        '${environment.workingDirectory.path}/fluoh_test/share_plus/pubspec.yaml',
      ).existsSync(),
      isTrue,
    );
    expect(
      stdout,
      contains(
        'Registered package share_plus at packages/share_plus/share_plus.',
      ),
    );
    expect(stderr, isEmpty);
  });

  test(
    'package release runs package tests, fluoh_test, and example tests before tagging',
    () async {
      final environment = await createTestEnvironment();
      final source = await _createFlutterSdkSource(
        environment.homeDirectory,
        logName: 'package_release_flutter_args.log',
      );
      final upstream = await _createUpstreamFlutterPluginRepository(
        Directory('${environment.homeDirectory.path}/upstream_release_camera'),
      );
      final packageRepository = Directory(
        '${environment.homeDirectory.path}/package_release_camera',
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
      await File(
        '${environment.homeDirectory.path}/package_release_flutter_args.log',
      ).writeAsString('');
      final releaseEnvironment = FluohEnvironment(
        homeDirectory: environment.homeDirectory,
        workingDirectory: packageRepository,
      );

      expect(
        await runFluoh(
          ['package', 'release'],
          environment: releaseEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final flutterLog = File(
        '${environment.homeDirectory.path}/package_release_flutter_args.log',
      ).readAsStringSync();
      _expectInOrder(flutterLog, [
        '${packageRepository.path}::pub get',
        '${packageRepository.path}::test',
        '${packageRepository.path}/fluoh_test/camera::pub get',
        '${packageRepository.path}/fluoh_test/camera::test',
        '${packageRepository.path}/fluoh_test/camera/example::pub get',
        '${packageRepository.path}/fluoh_test/camera/example::test',
      ]);
      final tags = await runGit(packageRepository, ['tag', '--list']);
      expect(
        tags.stdout.toString().split('\n'),
        contains('camera-0.11.0-ohos-3.35-0.1.0'),
      );
      expect(stdout, contains('Running fluoh test run before release.'));
      expect(stdout, contains('Running camera package Flutter tests.'));
      expect(stdout, contains('camera package tests passed.'));
      expect(stdout, contains('fluoh_test/camera passed.'));
      expect(stdout, contains('fluoh_test/camera/example passed.'));
      expect(stderr, isEmpty);
    },
  );
}

Future<Directory> _createFlutterSdkSource(
  Directory parent, {
  required String logName,
  bool failCreate = false,
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
    _fakeFlutterScript('${parent.path}/$logName', failCreate: failCreate),
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

String _fakeFlutterScript(String logPath, {bool failCreate = false}) {
  final failCreateValue = failCreate ? 'true' : 'false';
  return '''
#!/bin/sh
printf "%s::%s\\n" "\$(pwd)" "\$*" >> "$logPath"
if [ "\$1" = "create" ]; then
  printf "flutter create stdout\\n"
  printf "flutter create stderr\\n" >&2
  if [ "$failCreateValue" = "true" ]; then
    exit 42
  fi
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
  printf "name: generated\\n" > "\$target/pubspec.yaml"
  printf "sdk.dir=/fixture/flutter\\n" > "\$target/local.properties"
  printf "{}\\n" > "\$target/.flutter-plugins-dependencies"
  old_ifs="\$IFS"
  IFS=,
  for platform in \$platforms; do
    mkdir -p "\$target/\$platform"
  done
  IFS="\$old_ifs"
fi
exit 0
''';
}

Future<void> _writeFlutterPluginPackage(
  Directory directory, {
  String packageName = 'camera',
}) async {
  await Directory('${directory.path}/lib').create(recursive: true);
  await Directory('${directory.path}/test').create(recursive: true);
  await File(
    '${directory.path}/lib/$packageName.dart',
  ).writeAsString('library $packageName;\n');
  await File('${directory.path}/test/${packageName}_test.dart').writeAsString(
    '''
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('$packageName fixture package test', () {
    expect(true, isTrue);
  });
}
''',
  );
  await File(
    '${directory.path}/pubspec.yaml',
  ).writeAsString(_flutterPluginPubspec(packageName: packageName));
  await File('${directory.path}/LICENSE').writeAsString(_testLicenseContent);
}

Future<void> _writePackageManifest(
  Directory directory, {
  String packagePath = '.',
}) async {
  await File('${directory.path}/fluoh.yaml').writeAsString('''
schema: 1
name: camera

sdk:
  version: 3.35.8-ohos-0.0.3

repository:
  git:
    url: git@github.com:FlutterOH/camera.git
    branch: ohos/3.35

upstream:
  git:
    url: https://github.com/flutter/packages.git
    branch: main

packages:
  camera:
${packagePath == '.' ? '' : '    repository:\n      path: $packagePath\n'}${packagePath == '.' ? '' : '    upstream:\n      path: $packagePath\n'}    version: 0.1.0
    upstreamVersion: 0.11.0
    status: experimental
''');
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
  await Directory('${repo.path}/test').create(recursive: true);
  await File('${repo.path}/lib/camera.dart').writeAsString('library camera;\n');
  await File('${repo.path}/test/camera_test.dart').writeAsString('''
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('camera fixture package test', () {
    expect(true, isTrue);
  });
}
''');
  await File(
    '${repo.path}/pubspec.yaml',
  ).writeAsString(_flutterPluginPubspec());
  await File('${repo.path}/LICENSE').writeAsString(_testLicenseContent);
  await _runProcess('git', ['add', '.'], repo);
  await _runProcess('git', ['commit', '-m', 'Initial Flutter plugin'], repo);
  return repo;
}

void _expectInOrder(String text, List<String> needles) {
  var previous = -1;
  for (final needle in needles) {
    final index = text.indexOf(needle);
    expect(index, isNonNegative, reason: 'Missing "$needle" in output.');
    expect(index, greaterThan(previous), reason: 'Expected "$needle" later.');
    previous = index;
  }
}

String _flutterPluginPubspec({String packageName = 'camera'}) {
  return '''
name: $packageName
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
''';
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
