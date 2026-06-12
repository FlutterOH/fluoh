part of 'doctor_command_test.dart';

void _registerDoctorCommandVersionTests() {
  test('reports the current CLI version and available upgrades', () async {
    final environment = await createTestEnvironment();
    final result = await _runDoctorCommand(
      environment: environment,
      versionMetadataProvider: () async =>
          const DoctorVersionMetadata(latestVersion: _newerVersion),
      arguments: const ['doctor'],
    );

    expect(result.exitCode, 0);
    expect(
      result.stdout.join('\n'),
      contains('[!] fluoh ($packageVersion, on '),
    );
    expect(
      result.stdout,
      contains('    • Upgrade available: $_newerVersion; run `fluoh upgrade`'),
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
      arguments: const ['doctor'],
    );

    expect(result.exitCode, 0);
    expect(
      result.stdout.join('\n'),
      contains('[✓] fluoh ($packageVersion, on '),
    );
    expect(
      result.stdout,
      contains('    • Installed with dart pub global activate.'),
    );
    expect(
      result.stdout,
      contains('    • Current version published: $_currentVersionPublished'),
    );
    expect(result.stdout, contains('    • Up to date'));
    expect(result.stderr, isEmpty);
  });

  test('reports when the latest CLI version cannot be checked', () async {
    final environment = await createTestEnvironment();
    final result = await _runDoctorCommand(
      environment: environment,
      versionMetadataProvider: () async => null,
      arguments: const ['doctor'],
    );

    expect(result.exitCode, 0);
    expect(
      result.stdout.join('\n'),
      contains('[✓] fluoh ($packageVersion, on '),
    );
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

  test('rejects details and verbose aliases', () async {
    final environment = await createTestEnvironment();
    final detailsStdout = <String>[];
    final detailsStderr = <String>[];
    final shortStdout = <String>[];
    final shortStderr = <String>[];
    final longStdout = <String>[];
    final longStderr = <String>[];

    final detailsExitCode = await runFluoh(
      const ['doctor', '--details'],
      environment: environment,
      stdout: detailsStdout.add,
      stderr: detailsStderr.add,
    );
    final shortExitCode = await runFluoh(
      const ['doctor', '-v'],
      environment: environment,
      stdout: shortStdout.add,
      stderr: shortStderr.add,
    );
    final longExitCode = await runFluoh(
      const ['doctor', '--verbose'],
      environment: environment,
      stdout: longStdout.add,
      stderr: longStderr.add,
    );

    expect(detailsExitCode, 64);
    expect(detailsStdout, isEmpty);
    expect(
      detailsStderr.join('\n'),
      contains('Could not find an option named "--details".'),
    );
    expect(shortExitCode, 64);
    expect(shortStdout, isEmpty);
    expect(
      shortStderr.join('\n'),
      contains('Could not find an option or flag "-v".'),
    );
    expect(longExitCode, 64);
    expect(longStdout, isEmpty);
    expect(
      longStderr.join('\n'),
      contains('Could not find an option named "--verbose".'),
    );
  });

  test('colors doctor check headings when enabled', () async {
    final environment = await createTestEnvironment();
    await writeFlutterProjectFixture(environment.workingDirectory);
    final result = await _runDoctorCommand(
      environment: environment,
      versionMetadataProvider: () async =>
          const DoctorVersionMetadata(latestVersion: packageVersion),
      enableColor: true,
      arguments: const ['doctor', '--project'],
    );

    expect(result.exitCode, 0);
    expect(
      result.stdout.join('\n'),
      contains('\u001b[32m[✓]\u001b[0m fluoh ($packageVersion, on '),
    );
    expect(
      result.stdout.join('\n'),
      contains('\u001b[33m[!]\u001b[0m Flutter project'),
    );
    expect(
      result.stdout.join('\n'),
      contains(
        '    \u001b[32m•\u001b[0m \u001b[1mDetected Flutter project\u001b[0m',
      ),
    );
    expect(
      result.stdout.join('\n'),
      contains(
        '    \u001b[33m•\u001b[0m \u001b[1mNo FlutterOH SDK selected\u001b[0m',
      ),
    );
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
