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
      'fluoh 0.0.1 - FlutterOH SDK and package adapter CLI',
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
}

class _FixtureCommand extends Command<int> {
  @override
  String get name => 'fixture';

  @override
  String get description => 'Fixture command for command registration tests.';

  @override
  int run() => 37;
}
