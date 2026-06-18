import 'dart:convert';
import 'dart:io' as io;

import 'package:fluoh/fluoh.dart';
import 'package:fluoh/src/cli/skill_command.dart';
import 'package:args/command_runner.dart';
import 'package:test/test.dart';

part 'fluoh_command_runner_skill_part.dart';
part 'fluoh_command_runner_errors_part.dart';
part 'fluoh_command_runner_help_part.dart';

void main() {
  _registerFluohCommandRunnerSkillTests();
  _registerFluohCommandRunnerErrorTests();
  _registerFluohCommandRunnerHelpTests();
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

Future<io.ProcessResult> _runAdvertisedScript(
  Map<String, Object?> scripts,
  String name, {
  required Map<String, String> replacements,
}) {
  final script = scripts[name] as Map<String, Object?>;
  final argv = (script['argv'] as List<Object?>)
      .cast<String>()
      .map((value) {
        return replacements[value] ?? value;
      })
      .toList(growable: false);
  return io.Process.run(argv.first, argv.skip(1).toList());
}
