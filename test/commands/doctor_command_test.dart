import 'dart:io';

import 'package:fluoh/fluoh.dart';
import 'package:test/test.dart';

import '../helpers/fluoh_test_context.dart';

void main() {
  test(
    'reports project, SDK, source, platform, and dependency status',
    () async {
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
      await runFluoh(
        ['use', '3.35'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );

      expect(
        await runFluoh(
          ['doctor'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      expect(stdout, contains('[OK] Flutter project detected.'));
      expect(stdout, contains('[OK] Sources available: fixture.'));
      expect(stdout, contains('[OK] Project SDK: 3.35.8-ohos-0.0.3.'));
      expect(stdout, contains('[OK] .fvm/flutter_sdk is managed by fluoh.'));
      expect(stdout, contains('[WARN] Missing ohos platform directory.'));
      expect(stdout.join('\n'), contains('Dependencies needing attention:'));
      expect(stdout.join('\n'), contains('mystery_package'));
      expect(stdout.join('\n'), contains('camera_platform_interface'));
      expect(stderr, isEmpty);
    },
  );

  test('reports non-Flutter projects without modifying files', () async {
    final environment = await createTestEnvironment();
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['doctor'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(
      stdout,
      contains('[WARN] Current directory is not a Flutter project.'),
    );
    expect(
      File('${environment.workingDirectory.path}/.fvmrc').existsSync(),
      isFalse,
    );
    expect(stderr, isEmpty);
  });

  test('reports malformed .fvmrc as a warning', () async {
    final environment = await createTestEnvironment();
    await writeFlutterProjectFixture(environment.workingDirectory);
    await File(
      '${environment.workingDirectory.path}/.fvmrc',
    ).writeAsString('{');
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['doctor'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(stdout, contains('[WARN] .fvmrc is not valid JSON.'));
    expect(stderr, isEmpty);
  });
}
