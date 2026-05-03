import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:fluoh/fluoh.dart';
import 'package:fluoh/src/doctor/doctor_command.dart';
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
        ['sdk', 'use', '3.35.8-ohos-0.0.3'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );

      final result = await _runDoctorCommand(
        environment: environment,
        versionMetadataProvider: () async => const DoctorVersionMetadata(
          latestVersion: '0.0.1',
          currentVersionPublished: '2026-05-01',
        ),
      );
      stdout.addAll(result.stdout);
      stderr.addAll(result.stderr);

      expect(result.exitCode, 0);

      expect(stdout, contains('Doctor summary:'));
      expect(stdout, contains('[✓] fluoh (0.0.1)'));
      expect(
        stdout,
        contains('    • Installed with dart pub global activate.'),
      );
      expect(stdout, contains('    • Current version published: 2026-05-01.'));
      expect(stdout, contains('    • Up to date.'));
      expect(stdout.join('\n'), isNot(contains('\u001b[')));
      expect(stdout, contains('[✓] Flutter project'));
      expect(stdout, contains('    • Detected Flutter project.'));
      expect(stdout, contains('[!] Sources'));
      expect(stdout, contains('    • Available: fixture.'));
      expect(stdout, contains('    • Not updated: flutteroh.'));
      expect(stdout, contains('[✓] Project SDK'));
      expect(stdout, contains('    • 3.35.8-ohos-0.0.3.'));
      expect(stdout, contains('[✓] FVM'));
      expect(stdout, contains('    • .fvm/flutter_sdk is managed by fluoh.'));
      expect(stdout, contains('[!] OpenHarmony platform'));
      expect(stdout, contains('    • Missing ohos platform directory.'));
      expect(stdout.join('\n'), contains('Dependencies needing attention:'));
      expect(stdout.join('\n'), contains('mystery_package'));
      expect(stdout.join('\n'), contains('camera_platform_interface'));
      expect(stdout, contains('Doctor found issues in 3 categories.'));
      _expectInOrder(stdout.join('\n'), [
        '[✓] fluoh (0.0.1)',
        '[!] Sources',
        '[✓] Flutter project',
        '[✓] Project SDK',
        '[✓] FVM',
        '[!] OpenHarmony platform',
        '[!] Dependencies',
      ]);
      expect(stderr, isEmpty);
    },
  );

  test('reports non-Flutter projects without modifying files', () async {
    final environment = await createTestEnvironment();
    final stdout = <String>[];
    final stderr = <String>[];

    final result = await _runDoctorCommand(
      environment: environment,
      versionMetadataProvider: () async =>
          const DoctorVersionMetadata(latestVersion: '0.0.1'),
    );
    stdout.addAll(result.stdout);
    stderr.addAll(result.stderr);

    expect(result.exitCode, 0);

    expect(stdout, contains('[!] Flutter project'));
    expect(
      stdout,
      contains('    • Current directory is not a Flutter project.'),
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

    final result = await _runDoctorCommand(
      environment: environment,
      versionMetadataProvider: () async =>
          const DoctorVersionMetadata(latestVersion: '0.0.1'),
    );
    stdout.addAll(result.stdout);
    stderr.addAll(result.stderr);

    expect(result.exitCode, 0);

    expect(stdout, contains('[!] Project SDK'));
    expect(stdout, contains('    • .fvmrc is not valid JSON.'));
    expect(stderr, isEmpty);
  });

  test('reports the current CLI version and available upgrades', () async {
    final environment = await createTestEnvironment();
    final result = await _runDoctorCommand(
      environment: environment,
      versionMetadataProvider: () async =>
          const DoctorVersionMetadata(latestVersion: '0.0.2'),
    );

    expect(result.exitCode, 0);
    expect(result.stdout, contains('[!] fluoh (0.0.1)'));
    expect(
      result.stdout,
      contains('    • Upgrade available: 0.0.2. Run `fluoh upgrade`.'),
    );
    expect(result.stderr, isEmpty);
  });

  test('reports when the CLI is already up to date', () async {
    final environment = await createTestEnvironment();
    final result = await _runDoctorCommand(
      environment: environment,
      versionMetadataProvider: () async => const DoctorVersionMetadata(
        latestVersion: '0.0.1',
        currentVersionPublished: '2026-05-01',
      ),
    );

    expect(result.exitCode, 0);
    expect(result.stdout, contains('[✓] fluoh (0.0.1)'));
    expect(
      result.stdout,
      contains('    • Installed with dart pub global activate.'),
    );
    expect(
      result.stdout,
      contains('    • Current version published: 2026-05-01.'),
    );
    expect(result.stdout, contains('    • Up to date.'));
    expect(result.stderr, isEmpty);
  });

  test('reports when the latest CLI version cannot be checked', () async {
    final environment = await createTestEnvironment();
    final result = await _runDoctorCommand(
      environment: environment,
      versionMetadataProvider: () async => null,
    );

    expect(result.exitCode, 0);
    expect(result.stdout, contains('[!] fluoh (0.0.1)'));
    expect(
      result.stdout,
      contains('    • Installed with dart pub global activate.'),
    );
    expect(
      result.stdout,
      contains('    • Could not check the latest version from pub.dev.'),
    );
    expect(result.stderr, isEmpty);
  });

  test('colors doctor check headings when enabled', () async {
    final environment = await createTestEnvironment();
    final result = await _runDoctorCommand(
      environment: environment,
      versionMetadataProvider: () async =>
          const DoctorVersionMetadata(latestVersion: '0.0.1'),
      enableColor: true,
    );

    expect(result.exitCode, 0);
    expect(result.stdout, contains('\u001b[32m[✓] fluoh (0.0.1)\u001b[0m'));
    expect(result.stdout, contains('\u001b[33m[!] Flutter project\u001b[0m'));
    expect(result.stderr, isEmpty);
  });

  test('parses the current version release date from pub.dev metadata', () {
    final metadata = parseFluohVersionMetadata({
      'latest': {'version': '0.0.2'},
      'versions': [
        {'version': '0.0.0', 'published': '2026-04-01T08:00:00.000Z'},
        {'version': '0.0.1', 'published': '2026-05-01T09:30:00.000Z'},
      ],
    });

    expect(metadata?.latestVersion, '0.0.2');
    expect(metadata?.currentVersionPublished, '2026-05-01');
  });
}

Future<_DoctorRunResult> _runDoctorCommand({
  required FluohEnvironment environment,
  required DoctorVersionMetadataProvider versionMetadataProvider,
  Uri? scriptUri,
  bool enableColor = false,
}) async {
  final stdout = <String>[];
  final stderr = <String>[];
  final runner = CommandRunner<int>('fluoh', 'test')
    ..addCommand(
      DoctorCommand(
        environment: environment,
        stdout: stdout.add,
        versionMetadataProvider: versionMetadataProvider,
        scriptUriProvider: () =>
            scriptUri ??
            Uri.file(
              '/home/example/.pub-cache/global_packages/fluoh/bin/fluoh.dart',
            ),
        enableColor: enableColor,
      ),
    );

  final exitCode = await runner.run(['doctor']);
  return _DoctorRunResult(exitCode ?? 0, stdout, stderr);
}

class _DoctorRunResult {
  const _DoctorRunResult(this.exitCode, this.stdout, this.stderr);

  final int exitCode;
  final List<String> stdout;
  final List<String> stderr;
}

void _expectInOrder(String text, List<String> needles) {
  var previous = -1;
  for (final needle in needles) {
    final index = text.indexOf(needle);
    expect(index, isNonNegative, reason: 'Missing "$needle" in output.');
    expect(index, greaterThan(previous), reason: 'Expected "$needle" later.');
    previous = index;
  }
}
