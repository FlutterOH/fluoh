import 'dart:io';

import 'package:fluoh/fluoh.dart';
import 'package:test/test.dart';

import '../helpers/fluoh_test_context.dart';
import '../helpers/pub_test_context.dart';

void main() {
  test('test init creates automated tests and a manual example app', () async {
    final environment = await createTestEnvironment();
    final source = await _createFlutterSdkSource(
      environment.homeDirectory,
      logName: 'flutter_args.log',
    );
    await _writeFlutterPluginPackage(environment.workingDirectory);
    await _writePubRepositoryManifest(environment.workingDirectory);
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
      '${environment.workingDirectory.path}/fluoh_test/pubspec.yaml',
    ).readAsStringSync();
    expect(testPubspec, contains('name: camera_fluoh_test'));
    expect(testPubspec, contains('camera:\n    path: ..'));
    final gitignore = File(
      '${environment.workingDirectory.path}/fluoh_test/.gitignore',
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
      '${environment.workingDirectory.path}/fluoh_test/test/contract_test.dart',
    ).readAsStringSync();
    expect(contractTest, contains("package:camera/camera.dart"));
    final examplePubspec = File(
      '${environment.workingDirectory.path}/fluoh_test/example/pubspec.yaml',
    ).readAsStringSync();
    expect(examplePubspec, contains('camera:\n    path: ../..'));
    expect(
      Directory(
        '${environment.workingDirectory.path}/fluoh_test/example/ohos',
      ).existsSync(),
      isTrue,
    );
    final flutterLog = File(
      '${environment.homeDirectory.path}/flutter_args.log',
    ).readAsStringSync();
    expect(flutterLog, contains('create --no-pub --project-name'));
    expect(flutterLog, contains('--platforms=android,ios,ohos'));
    expect(stdout, contains('Created fluoh_test for camera.'));
    expect(stderr, isEmpty);
  });

  test('test run executes package tests before fluoh_test tests', () async {
    final environment = await createTestEnvironment();
    final source = await _createFlutterSdkSource(
      environment.homeDirectory,
      logName: 'flutter_run_args.log',
    );
    await _writeFlutterPluginPackage(environment.workingDirectory);
    await _writePubRepositoryManifest(environment.workingDirectory);
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
      '${environment.workingDirectory.path}/fluoh_test::pub get',
      '${environment.workingDirectory.path}/fluoh_test::test',
    ]);
    expect(stdout, contains('Running camera package Flutter tests.'));
    expect(stdout, contains('camera package tests passed.'));
    expect(stdout, contains('fluoh_test passed.'));
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
    await _writePubRepositoryManifest(environment.workingDirectory);
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
      '${environment.workingDirectory.path}/fluoh_test::pub get',
      '${environment.workingDirectory.path}/fluoh_test::test',
    ]);
    expect(
      stdout,
      contains('Skipping camera package tests: no test files found.'),
    );
    expect(stdout, contains('fluoh_test passed.'));
    expect(stderr, isEmpty);
  });

  test('test run executes package tests from monorepo package path', () async {
    final environment = await createTestEnvironment();
    final source = await _createFlutterSdkSource(
      environment.homeDirectory,
      logName: 'monorepo_flutter_run_args.log',
    );
    final packageDirectory = Directory(
      '${environment.workingDirectory.path}/packages/camera/camera',
    );
    await _writeFlutterPluginPackage(packageDirectory);
    await _writePubRepositoryManifest(
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
    await File(
      '${environment.homeDirectory.path}/monorepo_flutter_run_args.log',
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
      '${environment.homeDirectory.path}/monorepo_flutter_run_args.log',
    ).readAsStringSync();
    _expectInOrder(flutterLog, [
      '${packageDirectory.path}::pub get',
      '${packageDirectory.path}::test',
      '${environment.workingDirectory.path}/fluoh_test::pub get',
      '${environment.workingDirectory.path}/fluoh_test::test',
    ]);
    expect(stdout, contains('Running camera package Flutter tests.'));
    expect(stdout, contains('camera package tests passed.'));
    expect(stdout, contains('fluoh_test passed.'));
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
    'pub create initializes and stages fluoh_test for Flutter adapters',
    () async {
      final environment = await createTestEnvironment();
      final source = await _createFlutterSdkSource(
        environment.homeDirectory,
        logName: 'pub_create_flutter_args.log',
      );
      final upstream = await _createUpstreamFlutterPluginRepository(
        Directory('${environment.homeDirectory.path}/upstream_flutter_camera'),
      );
      final pubRepository = Directory(
        '${environment.homeDirectory.path}/pub_flutter_camera',
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
        File('${pubRepository.path}/fluoh_test/pubspec.yaml').existsSync(),
        isTrue,
      );
      expect(
        File(
          '${pubRepository.path}/fluoh_test/example/lib/main.dart',
        ).existsSync(),
        isTrue,
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
          '.gitignore',
          'FLUOH.md',
          'FLUOH_CHANGELOG.md',
          'fluoh.yaml',
          'fluoh_test/pubspec.yaml',
          'fluoh_test/test/contract_test.dart',
        ]),
      );
      expect(staged.stdout.toString(), isNot(contains('local.properties')));
      expect(
        staged.stdout.toString(),
        isNot(contains('.flutter-plugins-dependencies')),
      );
      expect(staged.stdout.toString(), isNot(contains('.fluoh')));
      expect(stdout, contains('Created fluoh_test for camera.'));
      expect(
        stdout,
        contains('Creating fluoh_test/example for android,ios,ohos.'),
      );
      expect(stdout.join('\n'), isNot(contains('fluoh flutter create')));
      expect(stdout, isNot(contains('flutter create stdout')));
      expect(stderr, isEmpty);
    },
  );

  test(
    'pub create replays flutter create output when example creation fails',
    () async {
      final environment = await createTestEnvironment();
      final source = await _createFlutterSdkSource(
        environment.homeDirectory,
        logName: 'pub_create_flutter_create_failure.log',
        failCreate: true,
      );
      final upstream = await _createUpstreamFlutterPluginRepository(
        Directory('${environment.homeDirectory.path}/upstream_failed_camera'),
      );
      final pubRepository = Directory(
        '${environment.homeDirectory.path}/pub_failed_camera',
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

      expect(stdout, contains('flutter create stdout'));
      expect(stderr, contains('flutter create stderr'));
      expect(
        stderr.join('\n'),
        contains('flutter create failed for fluoh_test/example.'),
      );
    },
  );

  test(
    'pub release runs package tests and fluoh_test before tagging',
    () async {
      final environment = await createTestEnvironment();
      final source = await _createFlutterSdkSource(
        environment.homeDirectory,
        logName: 'pub_release_flutter_args.log',
      );
      final upstream = await _createUpstreamFlutterPluginRepository(
        Directory('${environment.homeDirectory.path}/upstream_release_camera'),
      );
      final pubRepository = Directory(
        '${environment.homeDirectory.path}/pub_release_camera',
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
      await File(
        '${environment.homeDirectory.path}/pub_release_flutter_args.log',
      ).writeAsString('');
      final releaseEnvironment = FluohEnvironment(
        homeDirectory: environment.homeDirectory,
        workingDirectory: pubRepository,
      );

      expect(
        await runFluoh(
          ['pub', 'release'],
          environment: releaseEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final flutterLog = File(
        '${environment.homeDirectory.path}/pub_release_flutter_args.log',
      ).readAsStringSync();
      _expectInOrder(flutterLog, [
        '${pubRepository.path}::pub get',
        '${pubRepository.path}::test',
        '${pubRepository.path}/fluoh_test::pub get',
        '${pubRepository.path}/fluoh_test::test',
      ]);
      final tags = await runGit(pubRepository, ['tag', '--list']);
      expect(
        tags.stdout.toString().split('\n'),
        contains('camera-v0.11.0-ohos-3.35.8-0.1.0'),
      );
      expect(stdout, contains('Running fluoh test run before release.'));
      expect(stdout, contains('Running camera package Flutter tests.'));
      expect(stdout, contains('camera package tests passed.'));
      expect(stdout, contains('fluoh_test passed.'));
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
  await Directory('${source.path}/sdk').create(recursive: true);
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
  await File('${source.path}/sdk/releases.yaml').writeAsString('''
schema: 1
url: ${sdkRepository.path}
releases:
  - version: 3.35.8-ohos-0.0.3
    status: stable
''');
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

Future<void> _writeFlutterPluginPackage(Directory directory) async {
  await Directory('${directory.path}/lib').create(recursive: true);
  await Directory('${directory.path}/test').create(recursive: true);
  await File(
    '${directory.path}/lib/camera.dart',
  ).writeAsString('library camera;\n');
  await File('${directory.path}/test/camera_test.dart').writeAsString('''
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('camera fixture package test', () {
    expect(true, isTrue);
  });
}
''');
  await File(
    '${directory.path}/pubspec.yaml',
  ).writeAsString(_flutterPluginPubspec());
}

Future<void> _writePubRepositoryManifest(
  Directory directory, {
  String packagePath = '.',
}) async {
  await File('${directory.path}/fluoh.yaml').writeAsString('''
schema: 1
sdk:
  version: 3.35.8-ohos-0.0.3
package:
  name: camera
  version: 0.1.0
  git:
    url: git@github.com:FlutterOH/camera.git
    ref: ohos/3.35
${packagePath == '.' ? '' : '    path: $packagePath\n'}upstream:
  version: 0.11.0
  git:
    url: https://github.com/flutter/packages.git
    ref: camera-v0.11.0
${packagePath == '.' ? '' : '    path: $packagePath\n'}''');
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

String _flutterPluginPubspec() {
  return '''
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
''';
}

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
