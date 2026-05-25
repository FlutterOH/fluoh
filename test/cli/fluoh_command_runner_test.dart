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
      'fluoh $packageVersion - CLI for Flutter OHOS SDKs and package workflows',
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

  test(
    'prints parent command help instead of suggestions when help is set',
    () async {
      final stdout = <String>[];
      final stderr = <String>[];

      final exitCode = await runFluoh(
        ['deps', '--help', 'udpate'],
        stdout: stdout.add,
        stderr: stderr.add,
      );

      expect(exitCode, 0);
      final output = stdout.join('\n');
      expect(output, contains('Manage FlutterOH project dependencies.'));
      expect(output, contains('Usage: fluoh deps <subcommand> [arguments]'));
      expect(output, isNot(contains('Did you mean one of these?')));
      expect(stderr, isEmpty);
    },
  );

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

  test('registers deps command group', () async {
    final stdout = <String>[];
    final stderr = <String>[];

    final exitCode = await runFluoh(
      ['--help'],
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(exitCode, 0);
    expect(stdout.join('\n'), contains('deps'));
    expect(stdout.join('\n'), contains('package'));
    expect(stderr, isEmpty);
  });

  test('rejects unexpected arguments for leaf commands', () async {
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
      '  flutter',
      '  source',
      '  sdk',
      '  deps',
      '  package',
      '  doctor',
      '  upgrade',
    ]);
    expect(help, isNot(contains('\nConfig:')));
    expect(help, isNot(contains('\nSDK:')));
    expect(help, isNot(contains('\nProject:')));
    expect(help, isNot(contains('\nDeps:')));
    expect(help, isNot(contains('\nPackage:')));
    expect(help, isNot(contains('\nTool:')));
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
        ['package', '--help'],
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );
    help = stdout.join('\n');
    _expectInOrder(help, [
      '  create',
      '  add',
      '  sync',
      '  check',
      '  release',
    ]);
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
      ['package', 'check', '--help'],
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(exitCode, 0);
    final help = stdout.join('\n');
    expect(
      help,
      contains(
        '    --package=<name>            Package to check when fluoh.yaml registers\n'
        '                                multiple packages.',
      ),
    );
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
      'Package repositories:',
      '  create',
      '  add',
      '  sync',
      '  check',
      '  release',
    ]);
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
