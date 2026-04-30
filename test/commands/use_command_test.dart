import 'dart:convert';
import 'dart:io';

import 'package:fluoh/fluoh.dart';
import 'package:test/test.dart';

import '../helpers/fluoh_test_context.dart';

void main() {
  test('uses an SDK line and writes FVM-compatible project files', () async {
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
      ['use', '3.35'],
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
    expect(fluohConfig, contains('line: "3.35"'));
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
          ['use', '3.35'],
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
        ['use', '3.35'],
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
