part of 'fluoh_command_runner_test.dart';

void _registerFluohCommandRunnerErrorTests() {
  test('prints machine-readable usage errors when json is requested', () async {
    final stdout = <String>[];
    final stderr = <String>[];

    final exitCode = await runFluoh(
      ['doctor', '--json', 'extra'],
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(exitCode, 64);
    expect(stderr, isEmpty);
    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('schema', 1));
    expect(report, containsPair('command', 'doctor'));
    expect(report, containsPair('ok', false));
    expect(report, containsPair('exitCode', 64));
    expect(
      report['error'],
      allOf(
        isA<Map<String, Object?>>(),
        containsPair('type', 'usage'),
        containsPair('message', contains('Unexpected argument')),
      ),
    );
  });

  test('does not treat passthrough --machine as fluoh json mode', () async {
    final home = await io.Directory.systemTemp.createTemp('fluoh_test_home_');
    final project = await io.Directory.systemTemp.createTemp(
      'fluoh_test_project_',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    try {
      final exitCode = await runFluoh(
        ['flutter', '--machine'],
        environment: FluohEnvironment(
          homeDirectory: home,
          workingDirectory: project,
        ),
        stdout: stdout.add,
        stderr: stderr.add,
      );

      expect(exitCode, 64);
      expect(stdout, isEmpty);
      expect(stderr.join('\n'), contains('No SDK selected'));
    } finally {
      await home.delete(recursive: true);
      await project.delete(recursive: true);
    }
  });

  test('suggests similar top-level command names', () async {
    final stdout = <String>[];
    final stderr = <String>[];

    final exitCode = await runFluoh(
      ['docter'],
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(exitCode, 64);
    expect(stdout, isEmpty);
    final output = stderr.join('\n');
    expect(output, contains('Could not find a command named "docter".'));
    expect(output, contains('Did you mean one of these?'));
    expect(output, contains('  fluoh doctor'));
    expect(output, contains('  fluoh doctor\n\nUsage:'));
  });

  test(
    'reports unknown leading commands before a valid command name',
    () async {
      final stdout = <String>[];
      final stderr = <String>[];

      final exitCode = await runFluoh(
        ['project', 'create', 'demo_app'],
        stdout: stdout.add,
        stderr: stderr.add,
      );

      expect(exitCode, 64);
      expect(stdout, isEmpty);
      final output = stderr.join('\n');
      expect(output, contains('Could not find a command named "project".'));
      expect(
        output,
        isNot(contains('Cannot specify arguments before a command')),
      );
      expect(output, contains('Usage: fluoh <command> [arguments]'));
    },
  );

  test('suggests similar subcommand names', () async {
    final stdout = <String>[];
    final stderr = <String>[];

    final exitCode = await runFluoh(
      ['deps', 'chek'],
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(exitCode, 64);
    expect(stdout, isEmpty);
    final output = stderr.join('\n');
    expect(
      output,
      contains('Could not find a subcommand named "chek" for "fluoh deps".'),
    );
    expect(output, contains('Did you mean one of these?'));
    expect(output, contains('  fluoh deps check'));
    expect(output, contains('  fluoh deps check\n\nUsage:'));
  });

  test('reports unknown subcommands even when help is set', () async {
    final stdout = <String>[];
    final stderr = <String>[];

    final depsExitCode = await runFluoh(
      ['deps', '--help', 'udpate'],
      stdout: stdout.add,
      stderr: stderr.add,
    );
    final depsOutput = stderr.join('\n');

    expect(depsExitCode, 64);
    expect(stdout, isEmpty);
    expect(
      depsOutput,
      contains('Could not find a subcommand named "udpate" for "fluoh deps".'),
    );
    expect(depsOutput, contains('Did you mean one of these?'));
    expect(depsOutput, contains('  fluoh deps upgrade'));

    stderr.clear();
    final reportExitCode = await runFluoh(
      ['report', 'compose', '--help'],
      stdout: stdout.add,
      stderr: stderr.add,
    );
    final reportOutput = stderr.join('\n');

    expect(reportExitCode, 64);
    expect(stdout, isEmpty);
    expect(
      reportOutput,
      contains(
        'Could not find a subcommand named "compose" for "fluoh report".',
      ),
    );
  });

  test('keeps help available for valid parent and leaf commands', () async {
    final stdout = <String>[];
    final stderr = <String>[];

    final depsExitCode = await runFluoh(
      ['deps', '--help'],
      stdout: stdout.add,
      stderr: stderr.add,
    );
    final depsOutput = stdout.join('\n');

    expect(depsExitCode, 0);
    expect(depsOutput, contains('Usage: fluoh deps <subcommand> [arguments]'));
    expect(stderr, isEmpty);

    stdout.clear();
    final sourceAddExitCode = await runFluoh(
      ['source', 'add', 'fixture', 'path', '--help'],
      stdout: stdout.add,
      stderr: stderr.add,
    );
    final sourceAddOutput = stdout.join('\n');

    expect(sourceAddExitCode, 0);
    expect(sourceAddOutput, contains('Usage: fluoh source add <name>'));
    expect(stderr, isEmpty);
  });

  test('suggests upgrade for pub update-style command typos', () async {
    final stdout = <String>[];
    final stderr = <String>[];

    final topLevelExitCode = await runFluoh(
      ['udpate'],
      stdout: stdout.add,
      stderr: stderr.add,
    );
    final topLevelOutput = stderr.join('\n');

    expect(topLevelExitCode, 64);
    expect(stdout, isEmpty);
    expect(
      topLevelOutput,
      contains('Could not find a command named "udpate".'),
    );
    expect(topLevelOutput, contains('Did you mean one of these?'));
    expect(topLevelOutput, contains('  fluoh upgrade'));

    stderr.clear();
    final subcommandExitCode = await runFluoh(
      ['deps', 'udpate'],
      stdout: stdout.add,
      stderr: stderr.add,
    );
    final subcommandOutput = stderr.join('\n');

    expect(subcommandExitCode, 64);
    expect(stdout, isEmpty);
    expect(
      subcommandOutput,
      contains('Could not find a subcommand named "udpate" for "fluoh deps".'),
    );
    expect(subcommandOutput, contains('Did you mean one of these?'));
    expect(subcommandOutput, contains('  fluoh deps upgrade'));
  });

  test('suggests commands from short prefixes', () async {
    final stdout = <String>[];
    final stderr = <String>[];

    final exitCode = await runFluoh(
      ['upg'],
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(exitCode, 64);
    expect(stdout, isEmpty);
    final output = stderr.join('\n');
    expect(output, contains('Could not find a command named "upg".'));
    expect(output, contains('Did you mean one of these?'));
    expect(output, contains('  fluoh upgrade'));
  });

  test('suggests semantic command aliases without executing them', () async {
    final stdout = <String>[];
    final stderr = <String>[];

    final depsExitCode = await runFluoh(
      ['deps', 'install'],
      stdout: stdout.add,
      stderr: stderr.add,
    );
    final depsOutput = stderr.join('\n');

    expect(depsExitCode, 64);
    expect(stdout, isEmpty);
    expect(
      depsOutput,
      contains('Could not find a subcommand named "install" for "fluoh deps".'),
    );
    expect(depsOutput, contains('Did you mean one of these?'));
    expect(depsOutput, contains('  fluoh deps get'));

    stderr.clear();
    final sdkExitCode = await runFluoh(
      ['sdk', 'rm'],
      stdout: stdout.add,
      stderr: stderr.add,
    );
    final sdkOutput = stderr.join('\n');

    expect(sdkExitCode, 64);
    expect(stdout, isEmpty);
    expect(
      sdkOutput,
      contains('Could not find a subcommand named "rm" for "fluoh sdk".'),
    );
    expect(sdkOutput, contains('Did you mean one of these?'));
    expect(sdkOutput, contains('  fluoh sdk remove'));
  });

  test('does not execute update as an upgrade alias', () async {
    final stdout = <String>[];
    final stderr = <String>[];

    final exitCode = await runFluoh(
      ['update'],
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(exitCode, 64);
    expect(stdout, isEmpty);
    final output = stderr.join('\n');
    expect(output, contains('Could not find a command named "update".'));
    expect(output, contains('Did you mean one of these?'));
    expect(output, contains('  fluoh upgrade'));
  });

  test('runs registered commands', () async {
    final runner = FluohCommandRunner(commands: [_FixtureCommand()]);

    final exitCode = await runner.run(['fixture']);

    expect(exitCode, 37);
  });

  test('registers doctor command', () async {
    final stdout = <String>[];
    final stderr = <String>[];

    final exitCode = await runFluoh(
      ['--help'],
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(exitCode, 0);
    expect(stdout.join('\n'), contains('doctor'));
    expect(stderr, isEmpty);
  });

  test('registers app workflow commands', () async {
    final stdout = <String>[];
    final stderr = <String>[];

    final exitCode = await runFluoh(
      ['--help'],
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(exitCode, 0);
    expect(stdout.join('\n'), contains('create'));
    expect(stdout.join('\n'), contains('deps'));
    expect(stdout.join('\n'), contains('plan'));
    expect(stdout.join('\n'), contains('verify'));
    expect(stdout.join('\n'), contains('build'));
    expect(stdout.join('\n'), contains('run'));
    expect(stdout.join('\n'), contains('attach'));
    expect(stdout.join('\n'), contains('drive'));
    expect(stdout.join('\n'), contains('report'));
    expect(stdout.join('\n'), contains('package'));
    expect(stderr, isEmpty);
  });

  test('rejects unexpected doctor arguments', () async {
    final stdout = <String>[];
    final stderr = <String>[];

    final exitCode = await runFluoh(
      ['doctor', 'extra'],
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(exitCode, 64);
    expect(stdout, isEmpty);
    expect(stderr.join('\n'), contains('Unexpected argument: extra.'));
  });
}
