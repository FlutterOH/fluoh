import 'dart:io';

import 'package:fluoh/fluoh.dart';
import 'package:test/test.dart';

import '../helpers/fluoh_test_context.dart';

void main() {
  test('runs pub get for project, fluoh_test, and example', () async {
    final environment = await createTestEnvironment();
    final source = await _createPubGetSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
    );
    await writeFlutterProjectFixture(environment.workingDirectory);
    await _writePubWorkspace(
      Directory('${environment.workingDirectory.path}/fluoh_test'),
      'camera_fluoh_test',
    );
    await _writePubWorkspace(
      Directory('${environment.workingDirectory.path}/fluoh_test/example'),
      'fluoh_test_example',
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
      ['sdk', 'use', '3.35.8-ohos-0.0.3'],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    stdout.clear();
    stderr.clear();

    expect(
      await runFluoh(
        ['pub', 'get', '--offline'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final root = await environment.workingDirectory.resolveSymbolicLinks();
    expect(
      File(
        '${environment.workingDirectory.path}/pub_get_invocations.txt',
      ).readAsStringSync(),
      [
        '$root::pub get --offline',
        '$root/fluoh_test::pub get --offline',
        '$root/fluoh_test/example::pub get --offline',
        '',
      ].join('\n'),
    );
    expect(stdout.join('\n'), contains('Running flutter pub get in .'));
    expect(
      stdout.join('\n'),
      contains('Running flutter pub get in fluoh_test'),
    );
    expect(
      stdout.join('\n'),
      contains('Running flutter pub get in fluoh_test/example'),
    );
    expect(stdout, contains('Pub dependencies are up to date.'));
    expect(stderr, contains('flutter stderr'));
  });

  test('uses the package path from pub repository manifests', () async {
    final environment = await createTestEnvironment();
    final source = await _createPubGetSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
    );
    final packageDirectory = Directory(
      '${environment.workingDirectory.path}/packages/camera/camera',
    );
    await _writePubWorkspace(packageDirectory, 'camera');
    await File('${environment.workingDirectory.path}/fluoh.yaml').writeAsString(
      '''
schema: 1

sdk:
  version: 3.35.8-ohos-0.0.3

package:
  name: camera
  version: 0.1.0
  git:
    url: git@github.com:FlutterOH/camera.git
    ref: ohos/3.35
    path: packages/camera/camera

upstream:
  version: 0.11.0
  git:
    url: https://github.com/flutter/packages.git
    ref: camera-v0.11.0
    path: packages/camera/camera
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
    stdout.clear();

    expect(
      await runFluoh(
        ['pub', 'get'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final packagePath = await packageDirectory.resolveSymbolicLinks();
    expect(
      File(
        '${environment.workingDirectory.path}/pub_get_invocations.txt',
      ).readAsStringSync(),
      '$packagePath::pub get\n',
    );
    expect(
      stdout.join('\n'),
      contains('Running flutter pub get in packages/camera/camera'),
    );
  });

  test('runs cached selected SDK with malformed source config', () async {
    final environment = await createTestEnvironment();
    final source = await _createPubGetSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
    );
    await writeFlutterProjectFixture(environment.workingDirectory);
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'add', 'fixture', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    await runFluoh(
      ['sdk', 'use', '3.35.8-ohos-0.0.3'],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    await environment.configFile.writeAsString('{');
    stdout.clear();
    stderr.clear();

    expect(
      await runFluoh(
        ['pub', 'get'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final root = await environment.workingDirectory.resolveSymbolicLinks();
    expect(
      File(
        '${environment.workingDirectory.path}/pub_get_invocations.txt',
      ).readAsStringSync(),
      '$root::pub get\n',
    );
    expect(
      stderr.join('\n'),
      isNot(contains('fluoh config could not be read')),
    );
  });

  test('fails when no pubspec is available', () async {
    final environment = await createTestEnvironment();
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['pub', 'get'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );
    expect(stderr.join('\n'), contains('No pubspec.yaml found for pub get.'));
  });
}

Future<void> _writePubWorkspace(Directory directory, String name) async {
  await directory.create(recursive: true);
  await File('${directory.path}/pubspec.yaml').writeAsString('''
name: $name

environment:
  sdk: ^3.0.0

dependencies:
  flutter:
    sdk: flutter
''');
}

Future<Directory> _createPubGetSdkSource(
  Directory parent,
  Directory project,
) async {
  final source = Directory('${parent.path}/pub_get_source');
  final sdkRepository = Directory('${parent.path}/pub_get_sdk');
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
  await flutter.writeAsString('''
#!/bin/sh
printf "%s::%s\\n" "\$(pwd)" "\$*" >> "${project.path}/pub_get_invocations.txt"
printf "flutter stdout\\n"
printf "flutter stderr\\n" >&2
exit 0
''');
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
