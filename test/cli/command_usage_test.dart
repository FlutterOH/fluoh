import 'package:args/command_runner.dart';
import 'package:fluoh/src/cli/command_usage.dart';
import 'package:fluoh/src/cli/terminal_output.dart';
import 'package:test/test.dart';

void main() {
  test('does not color command names in command lists', () {
    final usage = formatCommandUsage(
      {'flutter': _FixtureCommand('flutter')},
      sections: const [
        CommandUsageSection('', ['flutter']),
      ],
      isSubcommand: false,
      style: const TerminalStyle(
        capabilities: TerminalCapabilities(
          ansi: true,
          decorated: true,
          unicode: true,
        ),
      ),
    );

    expect(usage, contains('\n  flutter   Fixture command.'));
    expect(usage, isNot(contains('\u001b[36mflutter\u001b[0m')));
  });
}

class _FixtureCommand extends Command<int> {
  _FixtureCommand(this.name);

  @override
  final String name;

  @override
  String get description => 'Fixture command.';
}
