import 'dart:convert';
import 'dart:io';

import 'package:fluoh/fluoh.dart';
import 'package:test/test.dart';

import '../helpers/fluoh_test_context.dart';

void main() {
  test('uses an SDK version and writes FVM-compatible project files', () async {
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
    expect(stdout, contains('Using Flutter OHOS SDK 3.35.8-ohos-0.0.3.'));
    expect(stderr, isEmpty);

    final fvmrc = File('${environment.workingDirectory.path}/.fvmrc');
    expect(jsonDecode(fvmrc.readAsStringSync()), {
      'flutter': '3.35.8-ohos-0.0.3',
    });

    final sdkLink = Link(
      '${environment.workingDirectory.path}/.fvm/flutter_sdk',
    );
    final sdkDirectory = Directory(
      '${environment.workingDirectory.path}/.fvm/flutter_sdk',
    );
    expect(await sdkLink.exists() || await sdkDirectory.exists(), isTrue);

    final fluohConfig = File(
      '${environment.workingDirectory.path}/fluoh.yaml',
    ).readAsStringSync();
    expect(fluohConfig, isNot(contains('line:')));
    expect(fluohConfig, contains('version: 3.35.8-ohos-0.0.3'));
    expect(fluohConfig, contains('sources:\n  - flutteroh\n  - fixture'));
    expect(fluohConfig, isNot(contains(environment.homeDirectory.path)));
    expect(fluohConfig, isNot(contains(RegExp(r'^\s+path:', multiLine: true))));
  });

  test(
    'does not delete a pre-existing non-fluoh flutter_sdk directory',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPubSourceFixture(environment.homeDirectory);
      await writeFlutterProjectFixture(environment.workingDirectory);
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
        64,
      );
      expect(
        File('${existingSdk.path}/README.md').readAsStringSync(),
        'existing sdk',
      );
      expect(stderr.join('\n'), contains('Refusing to replace existing'));
    },
  );

  test('replaces a pre-existing fluoh-managed flutter_sdk directory', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    await writeFlutterProjectFixture(environment.workingDirectory);
    final existingSdk = Directory(
      '${environment.workingDirectory.path}/.fvm/flutter_sdk',
    );
    await existingSdk.create(recursive: true);
    await File(
      '${existingSdk.path}/FLUOH_SDK_PATH',
    ).writeAsString('${environment.sdksDirectory.path}/stale');
    await File('${existingSdk.path}/stale.txt').writeAsString('stale');
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

    expect(File('${existingSdk.path}/stale.txt').existsSync(), isFalse);
    expect(stdout, contains('Using Flutter OHOS SDK 3.35.8-ohos-0.0.3.'));
    expect(stderr, isEmpty);
  });

  test('does not replace a pre-existing flutter_sdk file', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    await writeFlutterProjectFixture(environment.workingDirectory);
    final fvmDirectory = Directory('${environment.workingDirectory.path}/.fvm');
    await fvmDirectory.create(recursive: true);
    final existingSdk = File('${fvmDirectory.path}/flutter_sdk');
    await existingSdk.writeAsString('not a directory');
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

    expect(existingSdk.readAsStringSync(), 'not a directory');
    expect(stderr.join('\n'), contains('Refusing to replace existing'));
  });

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
      File('${environment.workingDirectory.path}/.fvmrc').existsSync(),
      isFalse,
    );
  });
}

Future<Directory> _createPubGetSdkSourceFixture(
  Directory parent,
  Directory project,
) async {
  final source = Directory('${parent.path}/pub_get_source');
  final sdkRepository = Directory('${parent.path}/flutter_with_pub_get');
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
printf "%s %s" "\$1" "\$2" > "${project.path}/pub_get_args.txt"
exit 0
''');
  await _runProcess('chmod', ['+x', flutter.path], sdkRepository);
  await File('${sdkRepository.path}/README.md').writeAsString('# SDK\n');
  await _runProcess('git', ['add', '.'], sdkRepository);
  await _runProcess('git', ['commit', '-m', 'Initial SDK'], sdkRepository);
  await _runProcess('git', ['tag', '3.35.8-ohos-0.0.3'], sdkRepository);
  await File('${source.path}/sdk/index.yaml').writeAsString('''
schema: 1
repositoryUrl: ${sdkRepository.path}
versions:
  - version: 3.35.8-ohos-0.0.3
    tag: 3.35.8-ohos-0.0.3
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
