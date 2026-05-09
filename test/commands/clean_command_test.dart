import 'dart:io';

import 'package:fluoh/fluoh.dart';
import 'package:test/test.dart';

import '../helpers/fluoh_test_context.dart';

void main() {
  test('runs flutter clean and removes fluoh_test artifacts', () async {
    final environment = await createTestEnvironment();
    final source = await _createCleanCommandSdkSource(
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
    stdout.clear();
    stderr.clear();

    await _writeFluohTestArtifactFixture(environment.workingDirectory);

    expect(
      await runFluoh(
        ['clean'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final projectPath = await environment.workingDirectory
        .resolveSymbolicLinks();
    expect(
      File(
        '${environment.workingDirectory.path}/flutter_invocations.txt',
      ).readAsStringSync(),
      '$projectPath::clean\n',
    );
    expect(
      Directory(
        '${environment.workingDirectory.path}/fluoh_test/.dart_tool',
      ).existsSync(),
      isFalse,
    );
    expect(
      Directory(
        '${environment.workingDirectory.path}/fluoh_test/build',
      ).existsSync(),
      isFalse,
    );
    expect(
      File(
        '${environment.workingDirectory.path}/fluoh_test/.flutter-plugins',
      ).existsSync(),
      isFalse,
    );
    expect(
      Directory(
        '${environment.workingDirectory.path}/fluoh_test/example/build',
      ).existsSync(),
      isFalse,
    );
    expect(
      File(
        '${environment.workingDirectory.path}/fluoh_test/pubspec.yaml',
      ).existsSync(),
      isTrue,
    );
    expect(stdout, contains('Running flutter clean in .'));
    expect(stdout.join('\n'), contains('Removed 4 fluoh_test artifacts.'));
    expect(stdout, contains('flutter stdout'));
    expect(stderr, contains('flutter stderr'));
  });

  test('runs flutter clean from pub repository package path', () async {
    final environment = await createTestEnvironment();
    final source = await _createCleanCommandSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
    );
    final packageDirectory = Directory(
      '${environment.workingDirectory.path}/packages/camera/camera',
    );
    await packageDirectory.create(recursive: true);
    await writeFlutterProjectFixture(packageDirectory);
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
    await _writeFluohTestArtifactFixture(environment.workingDirectory);
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
        ['clean'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final packagePath = await packageDirectory.resolveSymbolicLinks();
    expect(
      File(
        '${environment.workingDirectory.path}/flutter_invocations.txt',
      ).readAsStringSync(),
      '$packagePath::clean\n',
    );
    expect(
      stdout.join('\n'),
      contains('Running flutter clean in packages/camera/camera'),
    );
    expect(
      Directory(
        '${environment.workingDirectory.path}/fluoh_test/build',
      ).existsSync(),
      isFalse,
    );
  });

  test('skips tracked fluoh_test artifact paths', () async {
    final environment = await createTestEnvironment();
    final source = await _createCleanCommandSdkSource(
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
    await _writeFluohTestArtifactFixture(environment.workingDirectory);
    await initializeGitRepository(environment.workingDirectory);
    await Directory(
      '${environment.workingDirectory.path}/fluoh_test/coverage',
    ).create(recursive: true);
    await File(
      '${environment.workingDirectory.path}/fluoh_test/coverage/lcov.info',
    ).writeAsString('coverage');
    stdout.clear();
    stderr.clear();

    expect(
      await runFluoh(
        ['clean'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(
      Directory(
        '${environment.workingDirectory.path}/fluoh_test/build',
      ).existsSync(),
      isTrue,
    );
    expect(
      Directory(
        '${environment.workingDirectory.path}/fluoh_test/coverage',
      ).existsSync(),
      isFalse,
    );
    expect(
      stdout.join('\n'),
      contains('Skipped tracked fluoh_test artifact: fluoh_test/build.'),
    );
    expect(stdout.join('\n'), contains('Removed 1 fluoh_test artifact.'));
  });

  test('reports when fluoh_test is absent', () async {
    final environment = await createTestEnvironment();
    final source = await _createCleanCommandSdkSource(
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
    stdout.clear();

    expect(
      await runFluoh(
        ['clean'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(stdout.join('\n'), contains('No fluoh_test directory found.'));
  });

  test('fails when no SDK has been selected', () async {
    final environment = await createTestEnvironment();
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['clean'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );
    expect(
      stderr.join('\n'),
      contains('No SDK selected. Run "fluoh sdk use <version-or-series>".'),
    );
  });
}

Future<void> _writeFluohTestArtifactFixture(Directory repository) async {
  await Directory('${repository.path}/fluoh_test').create(recursive: true);
  await File(
    '${repository.path}/fluoh_test/pubspec.yaml',
  ).writeAsString('name: camera_fluoh_test\n');
  await Directory(
    '${repository.path}/fluoh_test/.dart_tool',
  ).create(recursive: true);
  await File(
    '${repository.path}/fluoh_test/.dart_tool/package_config.json',
  ).writeAsString('{}');
  await Directory(
    '${repository.path}/fluoh_test/build',
  ).create(recursive: true);
  await File(
    '${repository.path}/fluoh_test/build/app.dill',
  ).writeAsString('build');
  await File(
    '${repository.path}/fluoh_test/.flutter-plugins',
  ).writeAsString('plugins');
  await Directory(
    '${repository.path}/fluoh_test/example/build',
  ).create(recursive: true);
  await File(
    '${repository.path}/fluoh_test/example/build/app.dill',
  ).writeAsString('example build');
}

Future<Directory> _createCleanCommandSdkSource(
  Directory parent,
  Directory project,
) async {
  final source = Directory('${parent.path}/clean_command_source');
  final sdkRepository = Directory('${parent.path}/clean_command_sdk');
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
printf "%s::%s\\n" "\$(pwd)" "\$*" >> "${project.path}/flutter_invocations.txt"
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
