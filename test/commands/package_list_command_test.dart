import 'dart:convert';
import 'dart:io';

import 'package:fluoh/fluoh.dart';
import 'package:test/test.dart';

import '../helpers/fluoh_command_context.dart';

void main() {
  test('lists packages from configured sources', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'enable', 'fixture', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    stdout.clear();

    expect(
      await runFluoh(
        ['package', 'list'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(stdout, contains('[1] camera 3.35 fixture'));
    expect(stdout, contains('[2] share_plus 3.35 fixture'));
    expect(stderr, isEmpty);
  });

  test('lists packages from configured sources as json', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'enable', 'fixture', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    stdout.clear();

    expect(
      await runFluoh(
        ['package', 'list', '--json'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('schema', 1));
    expect(report, containsPair('command', 'package list'));
    expect(report, containsPair('ok', true));
    expect(report, containsPair('exitCode', 0));
    expect(report, containsPair('count', 2));
    final packages = report['packages'] as List<Object?>;
    expect(
      packages,
      contains(
        allOf(
          containsPair('package', 'camera'),
          containsPair('sdkLines', ['3.35']),
          containsPair('sources', ['fixture']),
          containsPair('compatibleReleaseCount', 2),
        ),
      ),
    );
    expect(
      packages,
      contains(
        allOf(
          containsPair('package', 'share_plus'),
          containsPair('sdkLines', ['3.35']),
          containsPair('sources', ['fixture']),
          containsPair('compatibleReleaseCount', 1),
        ),
      ),
    );
    expect(stderr, isEmpty);
  });

  test(
    'keeps source aliases for packages without compatible releases',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      final sharePlusManifest = File(
        '${source.path}/manifests/share_plus/fluoh.yaml',
      );
      await sharePlusManifest.writeAsString(
        (await sharePlusManifest.readAsString()).replaceFirst(
          '          upstream:\n'
              '            version: "9.0.0"\n'
              '            ref: share_plus-v9.0.0\n'
              '            commit: "9999999999999999999999999999999999999999"',
          '          upstream:\n'
              '            version: "9.0.0"\n'
              '            ref: share_plus-v9.0.0\n'
              '            commit: "9999999999999999999999999999999999999999"\n'
              '          status: experimental',
        ),
      );
      final stdout = <String>[];
      final stderr = <String>[];

      await runFluoh(
        ['source', 'enable', 'fixture', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      stdout.clear();

      expect(
        await runFluoh(
          ['package', 'list'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );
      expect(
        await runFluoh(
          ['package', 'list', '--json'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      expect(stdout, contains('[2] share_plus - fixture'));
      final report = jsonDecode(stdout.last) as Map<String, Object?>;
      final packages = report['packages'] as List<Object?>;
      expect(
        packages,
        contains(
          allOf(
            containsPair('package', 'share_plus'),
            containsPair('sdkLines', <Object?>[]),
            containsPair('sources', ['fixture']),
            containsPair('compatibleReleaseCount', 0),
          ),
        ),
      );
      expect(stderr, isEmpty);
    },
  );
}
