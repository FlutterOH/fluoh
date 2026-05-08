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

  test(
    'test run executes all fluoh_test tests with the selected SDK',
    () async {
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
      expect(flutterLog, contains('pub get'));
      expect(flutterLog, contains('test'));
      expect(stdout, contains('fluoh_test passed.'));
      expect(stderr, isEmpty);
    },
  );

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
          'FLUOH.md',
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
      expect(stdout, contains('Created fluoh_test for camera.'));
      expect(stderr, isEmpty);
    },
  );

  test('pub release runs fluoh_test before creating the tag', () async {
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
    expect(flutterLog, contains('pub get'));
    expect(flutterLog, contains('test'));
    final tags = await runGit(pubRepository, ['tag', '--list']);
    expect(
      tags.stdout.toString().split('\n'),
      contains('camera-v0.11.0-ohos-3.35.8-0.1.0'),
    );
    expect(stdout, contains('Running fluoh test run before release.'));
    expect(stdout, contains('fluoh_test passed.'));
    expect(stderr, isEmpty);
  });
}

Future<Directory> _createFlutterSdkSource(
  Directory parent, {
  required String logName,
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
  await flutter.writeAsString(_fakeFlutterScript('${parent.path}/$logName'));
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

String _fakeFlutterScript(String logPath) {
  return '''
#!/bin/sh
printf "%s\\n" "\$*" >> "$logPath"
if [ "\$1" = "create" ]; then
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
  await File(
    '${directory.path}/lib/camera.dart',
  ).writeAsString('library camera;\n');
  await File(
    '${directory.path}/pubspec.yaml',
  ).writeAsString(_flutterPluginPubspec());
}

Future<void> _writePubRepositoryManifest(Directory directory) async {
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
upstream:
  version: 0.11.0
  git:
    url: https://github.com/flutter/packages.git
    ref: camera-v0.11.0
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
  await File('${repo.path}/lib/camera.dart').writeAsString('library camera;\n');
  await File(
    '${repo.path}/pubspec.yaml',
  ).writeAsString(_flutterPluginPubspec());
  await _runProcess('git', ['add', '.'], repo);
  await _runProcess('git', ['commit', '-m', 'Initial Flutter plugin'], repo);
  return repo;
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
