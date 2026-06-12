part of 'fluoh_command_runner_test.dart';

void _registerFluohCommandRunnerHelpTests() {
  test('prints top-level commands by workflow group', () async {
    final stdout = <String>[];
    final stderr = <String>[];

    final exitCode = await runFluoh(
      ['--help'],
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(exitCode, 0);
    final help = stdout.join('\n');
    _expectInOrder(help, [
      'Fluoh',
      '  skill',
      '  doctor',
      '  flutter',
      '  clean',
      '  upgrade',
      '\nSDK & Metadata\n',
      '  sdk',
      '  source',
      'Project',
      '  create',
      '  deps',
      'Package',
      '  package',
      'Workflow',
      '  plan',
      '  verify',
      '  build',
      '  run',
      '  attach',
      '  drive',
      '  report',
      'Devices',
      '  devices',
      '  emulators',
    ]);
    expect(help, isNot(contains('  use')));
    expect(help, isNot(contains('  update')));
    expect(
      help,
      contains(
        'Shortcut: use "fluohf <flutter-args>" for '
        '"fluoh flutter <flutter-args>".',
      ),
    );
    expect(stderr, isEmpty);
  });

  test('prints focused command group help', () async {
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(['sdk', '--help'], stdout: stdout.add, stderr: stderr.add),
      0,
    );
    var help = stdout.join('\n');
    _expectInOrder(help, [
      '  list',
      '  use',
      '  current',
      '  install',
      '  remove',
    ]);

    stdout.clear();
    expect(
      await runFluoh(
        ['plan', '--help'],
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );
    help = stdout.join('\n');
    _expectInOrder(help, ['Adaptation plans:', '  app', '  package']);

    stdout.clear();
    expect(
      await runFluoh(
        ['package', '--help'],
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );
    help = stdout.join('\n');
    _expectInOrder(help, [
      'Source packages:',
      '  list',
      'Planning:',
      '  discover',
      '  queue',
      'Repository setup:',
      '  create',
      '  add',
      '  sync',
      '  docs',
      'Handoff:',
      '  handoff',
      'Release:',
      '  status',
      '  version',
      '  check',
      '  release',
    ]);
    expect(help, isNot(contains('  tag')));

    stdout.clear();
    expect(
      await runFluoh(
        ['verify', '--help'],
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );
    help = stdout.join('\n');
    expect(help, contains('Usage: fluoh verify'));
    expect(help, contains('--package=<name>'));
    expect(help, isNot(contains('  baseline')));
    expect(help, isNot(contains('  release')));

    stdout.clear();
    expect(
      await runFluoh(
        ['build', '--help'],
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );
    help = stdout.join('\n');
    expect(help, contains('Usage: fluoh build <platform>'));
    expect(help, contains('Build a FlutterOH project or package example.'));
    expect(help, contains('Generate temporary OHOS debug signing'));
    expect(help, contains('project or package example.'));
    expect(stderr, isEmpty);
  });

  test('prints deps command help', () async {
    final stdout = <String>[];
    final stderr = <String>[];

    final exitCode = await runFluoh(
      ['deps', '--help'],
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(exitCode, 0);
    final help = stdout.join('\n');
    expect(help, contains('Manage FlutterOH project dependencies.'));
    expect(help, contains('get'));
    expect(help, contains('check'));
    expect(help, contains('fix'));
    expect(help, contains('upgrade'));
    expect(help, isNot(contains('create')));
    expect(help, isNot(contains('sync')));
    expect(help, isNot(contains('release')));
    expect(stderr, isEmpty);
  });

  test('prints package create upstream help', () async {
    final stdout = <String>[];
    final stderr = <String>[];

    final exitCode = await runFluoh(
      ['package', 'create', '--help'],
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(exitCode, 0);
    final help = stdout.join('\n');
    expect(help, contains('Usage: fluoh package create <upstream>'));
    expect(help, contains('Upstream: Git URL or local Git repo path.'));
    expect(help, contains('--package-path'));
    expect(help, contains('--repository'));
    expect(help, contains('--git-author-name'));
    expect(help, contains('--git-author-email'));
    expect(stderr, isEmpty);
  });

  test('wraps leaf command option help at terminal width', () async {
    final stdout = <String>[];
    final stderr = <String>[];

    final exitCode = await runFluoh(
      ['verify', '--help'],
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(exitCode, 0);
    final help = stdout.join('\n');
    expect(help, contains('    --package=<name>'));
    expect(help, contains('current package'));
    expect(help, contains('branch.'));
    expect(help.split('\n').where((line) => line.length > 80), isEmpty);
    expect(stderr, isEmpty);
  });

  test('prints package create upstream argument guidance', () async {
    final stdout = <String>[];
    final stderr = <String>[];

    final exitCode = await runFluoh(
      ['package', 'create'],
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(exitCode, 64);
    expect(stdout, isEmpty);
    final error = stderr.join('\n');
    expect(
      error,
      contains('Expected <upstream>: Git URL or local Git repo path.'),
    );
    expect(error, contains('Usage: fluoh package create <upstream>'));
    expect(error, contains('Upstream: Git URL or local Git repo path.'));
  });

  test('prints package subcommands in lifecycle order', () async {
    final stdout = <String>[];
    final stderr = <String>[];

    final exitCode = await runFluoh(
      ['package', '--help'],
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(exitCode, 0);
    final help = stdout.join('\n');
    expect(help, contains('Maintain FlutterOH package repositories.'));
    _expectInOrder(help, [
      'Source packages:',
      '  list',
      'Planning:',
      '  discover',
      '  queue',
      'Repository setup:',
      '  create',
      '  add',
      '  sync',
      '  docs',
      'Handoff:',
      '  handoff',
      'Release:',
      '  status',
      '  version',
      '  check',
      '  release',
    ]);
    expect(help, isNot(contains('  tag')));
    expect(stderr, isEmpty);
  });
}
