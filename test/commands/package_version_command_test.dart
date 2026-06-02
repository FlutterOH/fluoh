import 'dart:convert';
import 'dart:io';

import 'package:fluoh/fluoh.dart';
import 'package:test/test.dart';

import '../helpers/fluoh_command_context.dart';
import '../helpers/package_test_context.dart';

void main() {
  test('bumps package release version and clears compatible status', () async {
    final environment = await createTestEnvironment();
    final packageRepository = await createPackageRepositoryFixture(environment);
    final releaseEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['package', 'version', '--bump', 'patch', '--status', 'compatible'],
        environment: releaseEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final manifest = File(
      '${packageRepository.path}/fluoh.yaml',
    ).readAsStringSync();
    expect(manifest, contains('version: 0.1.1'));
    expect(manifest, isNot(contains('status: experimental')));
    expect(stdout, contains('Updated camera version 0.1.0 -> 0.1.1'));
    expect(
      stdout,
      contains('Updated camera status experimental -> compatible'),
    );
    expect(
      stdout,
      contains(
        'Update FLUOH_CHANGELOG.md, review fluoh.yaml, commit release metadata, then run fluoh package check --package camera',
      ),
    );
    expect(stderr, isEmpty);
  });

  test('refuses to write in a dirty worktree', () async {
    final environment = await createTestEnvironment();
    final packageRepository = await createPackageRepositoryFixture(environment);
    final releaseEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    final stdout = <String>[];
    final stderr = <String>[];
    await File(
      '${packageRepository.path}/README.md',
    ).writeAsString('# dirty\n');

    expect(
      await runFluoh(
        ['package', 'version', '--bump', 'patch'],
        environment: releaseEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );

    expect(
      stderr.join('\n'),
      contains('Package version requires a clean working tree'),
    );
    final manifest = File(
      '${packageRepository.path}/fluoh.yaml',
    ).readAsStringSync();
    expect(manifest, contains('version: 0.1.0'));
  });

  test('dry run reports json without writing', () async {
    final environment = await createTestEnvironment();
    final packageRepository = await createPackageRepositoryFixture(environment);
    final releaseEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        [
          'package',
          'version',
          '--set',
          '0.2.0',
          '--status',
          'broken',
          '--dry-run',
          '--json',
        ],
        environment: releaseEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final result = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(result, containsPair('command', 'package version'));
    expect(result, containsPair('ok', true));
    expect(result, containsPair('dryRun', true));
    expect(result, containsPair('changed', true));
    expect(result, containsPair('version', '0.2.0'));
    expect(result, containsPair('status', 'broken'));
    final manifest = File(
      '${packageRepository.path}/fluoh.yaml',
    ).readAsStringSync();
    expect(manifest, contains('version: 0.1.0'));
    expect(manifest, contains('status: experimental'));
    expect(stderr, isEmpty);
  });

  test('requires one version action and rejects bump with set', () async {
    final environment = await createTestEnvironment();
    final packageRepository = await createPackageRepositoryFixture(environment);
    final releaseEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['package', 'version'],
        environment: releaseEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );
    expect(stderr.join('\n'), contains('Pass --bump, --set, or --status.'));

    stderr.clear();
    expect(
      await runFluoh(
        ['package', 'version', '--bump', 'patch', '--set', '0.2.0'],
        environment: releaseEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );
    expect(stderr.join('\n'), contains('Use only one of --bump or --set.'));
  });
}
