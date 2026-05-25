import 'dart:io';

import 'package:fluoh/fluoh.dart';
import 'package:test/test.dart';

import '../helpers/fluoh_command_context.dart';

void main() {
  test('runs existing Flutter package and example tests', () async {
    final environment = await createTestEnvironment();
    final source = await _createCheckSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
    );
    await _writePackageManifest(environment.workingDirectory);
    await _writeFlutterPackage(environment.workingDirectory);
    await _writeFlutterExample(
      Directory('${environment.workingDirectory.path}/example'),
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
        ['package', 'check'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final root = await environment.workingDirectory.resolveSymbolicLinks();
    expect(
      File(
        '${environment.workingDirectory.path}/package_check_invocations.txt',
      ).readAsStringSync(),
      [
        '$root::flutter pub get',
        '$root::flutter analyze',
        '$root::flutter test',
        '$root/example::flutter pub get',
        '$root/example::flutter analyze',
        '$root/example::flutter test',
        '',
      ].join('\n'),
    );
    expect(stdout, contains('Checking camera.'));
    expect(stdout, contains('Package analysis passed for camera.'));
    expect(stdout, contains('Package tests passed for camera.'));
    expect(stdout, contains('Example analysis passed for camera.'));
    expect(stdout, contains('Example tests passed for camera.'));
    expect(stdout, contains('Package check passed for camera.'));
    expect(stderr, contains('flutter stderr'));
  });

  test('uses dart test for non-Flutter packages', () async {
    final environment = await createTestEnvironment();
    final source = await _createCheckSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
    );
    await _writePackageManifest(environment.workingDirectory);
    await _writeDartPackage(environment.workingDirectory);
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
        ['package', 'check'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final root = await environment.workingDirectory.resolveSymbolicLinks();
    expect(
      File(
        '${environment.workingDirectory.path}/package_check_invocations.txt',
      ).readAsStringSync(),
      [
        '$root::dart pub get',
        '$root::dart analyze',
        '$root::dart test',
        '',
      ].join('\n'),
    );
    expect(stdout, contains('Package analysis passed for camera.'));
    expect(stdout, contains('Package tests passed for camera.'));
    expect(stdout.join('\n'), contains('Skipping example checks for camera'));
    expect(stderr, contains('dart stderr'));
  });

  test('runs analysis even when no tests exist', () async {
    final environment = await createTestEnvironment();
    final source = await _createCheckSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
    );
    await _writePackageManifest(environment.workingDirectory);
    await _writeFlutterPackage(environment.workingDirectory, withTests: false);
    await _writeFlutterExample(
      Directory('${environment.workingDirectory.path}/example'),
      withTests: false,
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
        ['package', 'check'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final root = await environment.workingDirectory.resolveSymbolicLinks();
    expect(
      File(
        '${environment.workingDirectory.path}/package_check_invocations.txt',
      ).readAsStringSync(),
      [
        '$root::flutter pub get',
        '$root::flutter analyze',
        '$root/example::flutter pub get',
        '$root/example::flutter analyze',
        '',
      ].join('\n'),
    );
    expect(stdout, contains('Package analysis passed for camera.'));
    expect(stdout, contains('Example analysis passed for camera.'));
    expect(
      stdout.join('\n'),
      contains('Skipping package tests for camera: no test files.'),
    );
    expect(
      stdout.join('\n'),
      contains('Skipping example tests for camera: no example test files.'),
    );
    expect(stdout, contains('Package check passed for camera.'));
    expect(stderr, contains('flutter stderr'));
  });

  test('fails when a registered package has no pubspec', () async {
    final environment = await createTestEnvironment();
    await _writePackageManifest(environment.workingDirectory);
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['package', 'check'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );

    expect(stderr.join('\n'), contains('Missing pubspec.yaml in .'));
    expect(stdout, contains('Checking camera.'));
    expect(stdout, isNot(contains('Package check passed for camera.')));
  });
}

Future<void> _writePackageManifest(Directory repository) async {
  await File('${repository.path}/fluoh.yaml').writeAsString('''
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
}

Future<void> _writeFlutterPackage(
  Directory directory, {
  bool withTests = true,
}) async {
  await Directory('${directory.path}/lib').create(recursive: true);
  await File(
    '${directory.path}/lib/camera.dart',
  ).writeAsString('library camera;\n');
  if (withTests) {
    await Directory('${directory.path}/test').create(recursive: true);
    await File('${directory.path}/test/camera_test.dart').writeAsString('''
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('camera fixture test', () {
    expect(true, isTrue);
  });
}
''');
  }
  await File('${directory.path}/pubspec.yaml').writeAsString('''
name: camera
version: 0.11.0

environment:
  sdk: ^3.0.0

dependencies:
  flutter:
    sdk: flutter

dev_dependencies:
  flutter_test:
    sdk: flutter
''');
}

Future<void> _writeFlutterExample(
  Directory directory, {
  bool withTests = true,
}) async {
  if (withTests) {
    await Directory('${directory.path}/test').create(recursive: true);
  } else {
    await directory.create(recursive: true);
  }
  await File('${directory.path}/pubspec.yaml').writeAsString('''
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
  if (withTests) {
    await File('${directory.path}/test/widget_test.dart').writeAsString('''
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('camera example fixture test', () {
    expect(true, isTrue);
  });
}
''');
  }
}

Future<void> _writeDartPackage(Directory directory) async {
  await Directory('${directory.path}/lib').create(recursive: true);
  await Directory('${directory.path}/test').create(recursive: true);
  await File(
    '${directory.path}/lib/camera.dart',
  ).writeAsString('library camera;\n');
  await File('${directory.path}/test/camera_test.dart').writeAsString('''
import 'package:test/test.dart';

void main() {
  test('camera fixture test', () {
    expect(true, isTrue);
  });
}
''');
  await File('${directory.path}/pubspec.yaml').writeAsString('''
name: camera
version: 0.11.0

environment:
  sdk: ^3.0.0

dev_dependencies:
  test: ^1.25.0
''');
}

Future<Directory> _createCheckSdkSource(
  Directory parent,
  Directory project,
) async {
  final source = Directory('${parent.path}/package_check_source');
  final sdkRepository = Directory('${parent.path}/package_check_sdk');
  await sdkRepository.create(recursive: true);
  await _runProcess('git', ['init', '--initial-branch=main'], sdkRepository);
  await _runProcess('git', [
    'config',
    'user.email',
    'fixture@example.com',
  ], sdkRepository);
  await _runProcess('git', ['config', 'user.name', 'Fixture'], sdkRepository);
  await Directory('${sdkRepository.path}/bin').create(recursive: true);
  await _writeTool(
    File('${sdkRepository.path}/bin/flutter'),
    '${project.path}/package_check_invocations.txt',
    'flutter',
  );
  await _writeTool(
    File('${sdkRepository.path}/bin/dart'),
    '${project.path}/package_check_invocations.txt',
    'dart',
  );
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

Future<void> _writeTool(File tool, String logPath, String name) async {
  await tool.writeAsString('''
#!/bin/sh
printf "%s::$name %s\\n" "\$(pwd)" "\$*" >> "$logPath"
printf "$name stdout\\n"
printf "$name stderr\\n" >&2
exit 0
''');
  await _runProcess('chmod', ['+x', tool.path], tool.parent);
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
