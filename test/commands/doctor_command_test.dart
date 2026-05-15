import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:fluoh/fluoh.dart';
import 'package:fluoh/src/doctor/doctor_command.dart';
import 'package:test/test.dart';

import '../helpers/fluoh_test_context.dart';

const _currentVersionPublished = '2026-05-01';
const _newerVersion = '99.0.0';

void main() {
  test('reports project, SDK, source, and platform status', () async {
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
        latestVersion: packageVersion,
        currentVersionPublished: _currentVersionPublished,
      ),
    );
    stdout.addAll(result.stdout);
    stderr.addAll(result.stderr);

    expect(result.exitCode, 0);

    expect(stdout, contains('Doctor summary:'));
    expect(stdout, contains('[✓] fluoh ($packageVersion)'));
    expect(stdout, contains('    • Installed with dart pub global activate.'));
    expect(
      stdout,
      contains('    • Current version published: $_currentVersionPublished.'),
    );
    expect(stdout, contains('    • Up to date.'));
    expect(stdout.join('\n'), isNot(contains('\u001b[')));
    expect(stdout, contains('[✓] Flutter project'));
    expect(stdout, contains('    • Detected Flutter project.'));
    expect(stdout, contains('[!] Sources'));
    expect(stdout, contains('    • Available: fixture.'));
    expect(stdout, contains('    • Not updated: flutteroh.'));
    expect(stdout, contains('[✓] Project SDK'));
    expect(stdout, contains('    • 3.35.8-ohos-0.0.3.'));
    expect(stdout, contains('[!] OHOS platform'));
    expect(stdout, contains('    • Missing ohos platform directory.'));
    expect(stdout.join('\n'), isNot(contains('Dependencies')));
    expect(stdout.join('\n'), isNot(contains('mystery_package')));
    expect(stdout.join('\n'), isNot(contains('camera_platform_interface')));
    expect(stdout, contains('Doctor found issues in 2 categories.'));
    _expectInOrder(stdout.join('\n'), [
      '[✓] fluoh ($packageVersion)',
      '[!] Sources',
      '[✓] Flutter project',
      '[✓] Project SDK',
      '[!] OHOS platform',
    ]);
    expect(stderr, isEmpty);
  });

  test('reports non-Flutter projects without modifying files', () async {
    final environment = await createTestEnvironment();
    final stdout = <String>[];
    final stderr = <String>[];

    final result = await _runDoctorCommand(
      environment: environment,
      versionMetadataProvider: () async =>
          const DoctorVersionMetadata(latestVersion: packageVersion),
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
      File('${environment.workingDirectory.path}/fluoh.yaml').existsSync(),
      isFalse,
    );
    expect(stderr, isEmpty);
  });

  test('reports malformed fluoh.yaml as a warning', () async {
    final environment = await createTestEnvironment();
    await writeFlutterProjectFixture(environment.workingDirectory);
    await File(
      '${environment.workingDirectory.path}/fluoh.yaml',
    ).writeAsString('{');
    final stdout = <String>[];
    final stderr = <String>[];

    final result = await _runDoctorCommand(
      environment: environment,
      versionMetadataProvider: () async =>
          const DoctorVersionMetadata(latestVersion: packageVersion),
    );
    stdout.addAll(result.stdout);
    stderr.addAll(result.stderr);

    expect(result.exitCode, 0);

    expect(stdout, contains('[!] Project SDK'));
    expect(stdout, contains('    • fluoh.yaml is not valid YAML.'));
    expect(stderr, isEmpty);
  });

  test('reports invalid source snapshots as warnings', () async {
    final environment = await createTestEnvironment();
    final source = Directory(
      '${environment.homeDirectory.path}/sources/broken',
    );
    await source.create(recursive: true);
    await File('${source.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: source
name: Broken source
repository:
  git:
    url: /tmp/broken
manifests:
  - name: missing
''');
    await File('${environment.homeDirectory.path}/config.json').writeAsString(
      jsonEncode({
        'sources': {
          'broken': {'path': source.path, 'priority': 10},
        },
      }),
    );

    final result = await _runDoctorCommand(
      environment: environment,
      versionMetadataProvider: () async =>
          const DoctorVersionMetadata(latestVersion: packageVersion),
    );

    expect(result.exitCode, 0);
    expect(result.stdout, contains('[!] Sources'));
    expect(result.stdout.join('\n'), isNot(contains('Available: broken.')));
    expect(result.stdout.join('\n'), contains('Invalid: broken'));
    expect(result.stderr, isEmpty);
  });

  test('reports the current CLI version and available upgrades', () async {
    final environment = await createTestEnvironment();
    final result = await _runDoctorCommand(
      environment: environment,
      versionMetadataProvider: () async =>
          const DoctorVersionMetadata(latestVersion: _newerVersion),
    );

    expect(result.exitCode, 0);
    expect(result.stdout, contains('[!] fluoh ($packageVersion)'));
    expect(
      result.stdout,
      contains('    • Upgrade available: $_newerVersion. Run `fluoh upgrade`.'),
    );
    expect(result.stderr, isEmpty);
  });

  test('reports when the CLI is already up to date', () async {
    final environment = await createTestEnvironment();
    final result = await _runDoctorCommand(
      environment: environment,
      versionMetadataProvider: () async => const DoctorVersionMetadata(
        latestVersion: packageVersion,
        currentVersionPublished: _currentVersionPublished,
      ),
    );

    expect(result.exitCode, 0);
    expect(result.stdout, contains('[✓] fluoh ($packageVersion)'));
    expect(
      result.stdout,
      contains('    • Installed with dart pub global activate.'),
    );
    expect(
      result.stdout,
      contains('    • Current version published: $_currentVersionPublished.'),
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
    expect(result.stdout, contains('[!] fluoh ($packageVersion)'));
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
          const DoctorVersionMetadata(latestVersion: packageVersion),
      enableColor: true,
    );

    expect(result.exitCode, 0);
    expect(
      result.stdout,
      contains('\u001b[32m[✓] fluoh ($packageVersion)\u001b[0m'),
    );
    expect(result.stdout, contains('\u001b[33m[!] Flutter project\u001b[0m'));
    expect(result.stderr, isEmpty);
  });

  test('parses the current version release date from pub.dev metadata', () {
    final metadata = parseFluohVersionMetadata({
      'latest': {'version': _newerVersion},
      'versions': [
        {'version': '0.0.0', 'published': '2026-04-01T08:00:00.000Z'},
        {
          'version': packageVersion,
          'published': '${_currentVersionPublished}T09:30:00.000Z',
        },
      ],
    });

    expect(metadata?.latestVersion, _newerVersion);
    expect(metadata?.currentVersionPublished, _currentVersionPublished);
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
