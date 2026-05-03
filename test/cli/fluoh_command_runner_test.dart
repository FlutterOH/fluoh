import 'dart:io' as io;

import 'package:fluoh/fluoh.dart';
import 'package:args/command_runner.dart';
import 'package:test/test.dart';

void main() {
  test('prints Flutter-style version details from version flag', () async {
    final stdout = <String>[];
    final stderr = <String>[];
    final dartVersion = io.Platform.version.split(' ').first;

    final exitCode = await runFluoh(
      ['--version'],
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(exitCode, 0);
    expect(stdout, [
      'fluoh 0.0.1 - FlutterOH SDK and pub package CLI',
      'Dart $dartVersion',
      startsWith('Platform ${io.Platform.operatingSystem} '),
      'Repository https://github.com/FlutterOH/fluoh',
    ]);
    expect(stderr, isEmpty);
  });

  test('does not register a version command', () async {
    final stdout = <String>[];
    final stderr = <String>[];

    final exitCode = await runFluoh(
      ['version'],
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(exitCode, 64);
    expect(stdout, isEmpty);
    expect(stderr.join('\n'), contains('Could not find a command named'));
  });

  test('does not register workflow commands as top-level aliases', () async {
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(['create'], stdout: stdout.add, stderr: stderr.add),
      64,
    );
    expect(
      await runFluoh(['release'], stdout: stdout.add, stderr: stderr.add),
      64,
    );
    expect(await runFluoh(['use'], stdout: stdout.add, stderr: stderr.add), 64);
    expect(
      await runFluoh(['update'], stdout: stdout.add, stderr: stderr.add),
      64,
    );

    expect(stdout, isEmpty);
    expect(stderr.join('\n'), contains('Could not find a command named'));
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

  test('registers pub command group', () async {
    final stdout = <String>[];
    final stderr = <String>[];

    final exitCode = await runFluoh(
      ['--help'],
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(exitCode, 0);
    expect(stdout.join('\n'), contains('pub'));
    expect(stderr, isEmpty);
  });

  test('prints top-level commands without grouping', () async {
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
      '  sdk',
      '  deps',
      '  pub',
      '  source',
      '  doctor',
      '  upgrade',
    ]);
    expect(help, isNot(contains('\nConfig:')));
    expect(help, isNot(contains('\nSDK:')));
    expect(help, isNot(contains('\nProject:')));
    expect(help, isNot(contains('\nPub:')));
    expect(help, isNot(contains('\nTool:')));
    expect(help, isNot(contains('  use')));
    expect(help, isNot(contains('  update')));
    expect(stderr, isEmpty);
  });

  test('prints moved workflow commands under their command groups', () async {
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(['sdk', '--help'], stdout: stdout.add, stderr: stderr.add),
      0,
    );
    var help = stdout.join('\n');
    _expectInOrder(help, [
      '  list',
      '  install',
      '  current',
      '  remove',
      '  use',
    ]);

    stdout.clear();
    expect(
      await runFluoh(
        ['deps', '--help'],
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );
    help = stdout.join('\n');
    _expectInOrder(help, ['  check', '  fix', '  update']);
    expect(stderr, isEmpty);
  });

  test('prints pub command help', () async {
    final stdout = <String>[];
    final stderr = <String>[];

    final exitCode = await runFluoh(
      ['pub', '--help'],
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(exitCode, 0);
    final help = stdout.join('\n');
    expect(help, contains('Manage FlutterOH pub package repositories.'));
    expect(help, contains('create'));
    expect(help, contains('sync'));
    expect(help, contains('adapt'));
    expect(help, contains('release'));
    expect(stderr, isEmpty);
  });

  test('prints pub subcommands in lifecycle order', () async {
    final stdout = <String>[];
    final stderr = <String>[];

    final exitCode = await runFluoh(
      ['pub', '--help'],
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(exitCode, 0);
    final help = stdout.join('\n');
    _expectInOrder(help, ['  create', '  sync', '  adapt', '  release']);
    expect(help, isNot(contains('Repository setup:')));
    expect(help, isNot(contains('Upstream adaptation:')));
    expect(help, isNot(contains('Release:')));
    expect(stderr, isEmpty);
  });
}

class _FixtureCommand extends Command<int> {
  @override
  String get name => 'fixture';

  @override
  String get description => 'Fixture command for command registration tests.';

  @override
  int run() => 37;
}

void _expectInOrder(String text, List<String> needles) {
  var previous = -1;
  for (final needle in needles) {
    final index = text.indexOf(needle);
    expect(index, isNonNegative, reason: 'Missing "$needle" in help output.');
    expect(index, greaterThan(previous), reason: 'Expected "$needle" later.');
    previous = index;
  }
}
