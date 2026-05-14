import 'dart:io';

import 'package:fluoh/fluoh.dart';
import 'package:test/test.dart';

import '../helpers/fluoh_test_context.dart';

void main() {
  test('uses an SDK version and writes fluoh project config', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    await writeFlutterProjectFixture(environment.workingDirectory);
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'add', 'fixture', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );

    final exitCode = await runFluoh(
      ['sdk', 'use', '3.35.8-ohos-0.0.3'],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(exitCode, 0);
    expect(
      stdout,
      contains('Will modify ${environment.workingDirectory.path}/fluoh.yaml.'),
    );
    expect(
      stdout,
      contains(
        'Flutter OHOS SDK path: '
        '${environment.homeDirectory.path}/sdks/3.35.8-ohos-0.0.3.',
      ),
    );
    expect(stdout, contains('Using Flutter OHOS SDK 3.35.8-ohos-0.0.3.'));
    expect(stderr, isEmpty);

    final fluohConfig = File(
      '${environment.workingDirectory.path}/fluoh.yaml',
    ).readAsStringSync();
    expect(fluohConfig, '''
schema: 1

sdk:
  version: 3.35.8-ohos-0.0.3

dependencyPolicy:
  # pubspecSection controls where fluoh pub fix writes OHOS implementations:
  # - dependency_overrides: add dependency_overrides without changing dependencies.
  # - dependencies: replace matching entries in dependencies directly.
  pubspecSection: dependency_overrides
  # versionChanges controls version differences after exact matches and compatible upgrades:
  # - compatible: leave incompatible version changes and downgrades for manual review.
  # - any: apply the recommended implementation anyway.
  versionChanges: compatible
''');
    expect(fluohConfig, isNot(contains('line:')));
    expect(fluohConfig, contains('version: 3.35.8-ohos-0.0.3'));
    expect(fluohConfig, isNot(contains('sources:')));
    expect(fluohConfig, isNot(contains(environment.homeDirectory.path)));
    expect(fluohConfig, isNot(contains(RegExp(r'^\s+path:', multiLine: true))));
    expect(
      File('${environment.workingDirectory.path}/.fvmrc').existsSync(),
      isFalse,
    );
    expect(
      Directory('${environment.workingDirectory.path}/.fvm').existsSync(),
      isFalse,
    );
    final link = Link(
      '${environment.workingDirectory.path}/.fluoh/flutter_sdk',
    );
    expect(link.existsSync(), isTrue);
    expect(
      link.targetSync(),
      '${environment.homeDirectory.path}/sdks/3.35.8-ohos-0.0.3',
    );
    expect(
      File(
        '${environment.workingDirectory.path}/.gitignore',
      ).readAsStringSync(),
      contains('.fluoh/'),
    );
    expect(
      stdout,
      contains(
        'IDE Flutter SDK link: '
        '${environment.workingDirectory.path}/.fluoh/flutter_sdk.',
      ),
    );
    expect(
      stdout,
      contains(
        'Use this link as your IDE Flutter SDK path; reload the IDE if it keeps the old SDK.',
      ),
    );
  });

  test('updates an existing IDE SDK link automatically', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    await writeFlutterProjectFixture(environment.workingDirectory);
    final legacySdk = Directory('${environment.homeDirectory.path}/legacy_sdk');
    await legacySdk.create(recursive: true);
    final linkRoot = Directory('${environment.workingDirectory.path}/.fluoh');
    await linkRoot.create(recursive: true);
    await Link('${linkRoot.path}/flutter_sdk').create(legacySdk.path);
    await File(
      '${environment.workingDirectory.path}/.gitignore',
    ).writeAsString('build/\n');
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
        ['sdk', 'use', '3.35.8-ohos-0.0.3'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final link = Link(
      '${environment.workingDirectory.path}/.fluoh/flutter_sdk',
    );
    expect(link.existsSync(), isTrue);
    expect(
      link.targetSync(),
      '${environment.homeDirectory.path}/sdks/3.35.8-ohos-0.0.3',
    );
    expect(
      File(
        '${environment.workingDirectory.path}/.gitignore',
      ).readAsStringSync(),
      'build/\n.fluoh/\n',
    );
    expect(stderr, isEmpty);
  });

  test('refuses to replace a non-symlink IDE SDK path', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    await writeFlutterProjectFixture(environment.workingDirectory);
    final existingSdkPath = Directory(
      '${environment.workingDirectory.path}/.fluoh/flutter_sdk',
    );
    await existingSdkPath.create(recursive: true);
    await File('${existingSdkPath.path}/README.md').writeAsString('keep me');
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
        ['sdk', 'use', '3.35.8-ohos-0.0.3'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );

    expect(
      File('${existingSdkPath.path}/README.md').readAsStringSync(),
      'keep me',
    );
    expect(
      File('${environment.workingDirectory.path}/fluoh.yaml').existsSync(),
      isFalse,
    );
    expect(stderr.join('\n'), contains('already exists and is not a symlink'));
  });

  test('refuses to write config when the IDE link root is a file', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    await writeFlutterProjectFixture(environment.workingDirectory);
    final linkRoot = File('${environment.workingDirectory.path}/.fluoh');
    await linkRoot.writeAsString('not a directory');
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
        ['sdk', 'use', '3.35.8-ohos-0.0.3'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );

    expect(await linkRoot.readAsString(), 'not a directory');
    expect(
      File('${environment.workingDirectory.path}/fluoh.yaml').existsSync(),
      isFalse,
    );
    expect(
      stderr.join('\n'),
      contains('already exists and is not a directory'),
    );
  });

  test('leaves pre-existing FVM files untouched', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    await writeFlutterProjectFixture(environment.workingDirectory);
    final fvmrc = File('${environment.workingDirectory.path}/.fvmrc');
    await fvmrc.writeAsString('{"flutter":"legacy"}');
    final existingSdk = Directory(
      '${environment.workingDirectory.path}/.fvm/flutter_sdk',
    );
    await existingSdk.create(recursive: true);
    await File('${existingSdk.path}/README.md').writeAsString('existing sdk');
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
        ['sdk', 'use', '3.35.8-ohos-0.0.3'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(fvmrc.readAsStringSync(), '{"flutter":"legacy"}');
    expect(
      File('${existingSdk.path}/README.md').readAsStringSync(),
      'existing sdk',
    );
    expect(stdout, contains('Using Flutter OHOS SDK 3.35.8-ohos-0.0.3.'));
    expect(stderr, isEmpty);
  });

  test(
    'updates existing project fluoh config without removing user fields',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPubSourceFixture(environment.homeDirectory);
      await writeFlutterProjectFixture(environment.workingDirectory);
      final manifest = File('${environment.workingDirectory.path}/fluoh.yaml');
      await manifest.writeAsString('''
schema: 1
# Keep project-specific fluoh settings.
sdk:
  version: 3.34.0-ohos-0.0.1 # selected SDK
dependencyPolicy:
  pubspecSection: dependencies
custom:
  keep: true
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
          ['sdk', 'use', '3.35.8-ohos-0.0.3'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final updated = manifest.readAsStringSync();
      expect(updated, contains('version: 3.35.8-ohos-0.0.3 # selected SDK'));
      expect(updated, contains('# Keep project-specific fluoh settings.'));
      expect(updated, contains('pubspecSection: dependencies'));
      expect(updated, contains('custom:\n  keep: true'));
      expect(stderr, isEmpty);
    },
  );

  test('runs flutter pub get from the selected SDK when requested', () async {
    final environment = await createTestEnvironment();
    final source = await _createPubGetSdkSourceFixture(
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

    expect(
      await runFluoh(
        ['sdk', 'use', '3.35.8-ohos-0.0.3', '--pub-get'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(
      File(
        '${environment.workingDirectory.path}/pub_get_args.txt',
      ).readAsStringSync(),
      'pub get',
    );
    expect(stdout, contains('Using Flutter OHOS SDK 3.35.8-ohos-0.0.3.'));
    expect(stderr, isEmpty);
  });

  test('refuses to write SDK files outside a Flutter project', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
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
        ['sdk', 'use', '3.35.8-ohos-0.0.3'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );
    expect(
      stderr.join('\n'),
      contains('Current directory is not a Flutter project'),
    );
    expect(
      File('${environment.workingDirectory.path}/fluoh.yaml').existsSync(),
      isFalse,
    );
  });

  test('refuses to replace pub repository metadata', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    await writeFlutterProjectFixture(environment.workingDirectory);
    final manifest = File('${environment.workingDirectory.path}/fluoh.yaml');
    await manifest.writeAsString('''
schema: 1
sdk:
  version: 3.35.8-ohos-0.0.3
package:
  name: camera
  version: 0.1.0
  git:
    url: git@github.com:FlutterOH/camera.git
upstream:
  version: 0.11.0
  git:
    url: https://github.com/flutter/packages.git
    ref: camera-v0.11.0
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
        ['sdk', 'use', '3.35.8-ohos-0.0.3'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );

    expect(
      stderr.join('\n'),
      contains('Refusing to replace pub repository metadata in fluoh.yaml.'),
    );
    expect(manifest.readAsStringSync(), contains('package:\n  name: camera'));
  });
}

Future<Directory> _createPubGetSdkSourceFixture(
  Directory parent,
  Directory project,
) async {
  final source = Directory('${parent.path}/pub_get_source');
  final sdkRepository = Directory('${parent.path}/flutter_with_pub_get');
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
printf "%s %s" "\$1" "\$2" > "${project.path}/pub_get_args.txt"
exit 0
''');
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
