import 'package:fluoh/src/cli/terminal_output.dart';
import 'package:test/test.dart';

void main() {
  test('plain output does not add color or decorative markers', () {
    final stdout = <String>[];
    final stderr = <String>[];
    final output = TerminalOutput(stdout: stdout.add, stderr: stderr.add);

    output.success('Installed SDK 3.35.');
    output.failure('SDK install failed.');
    output.error('No SDK selected.');
    output.next('Next: run `fluoh flutter pub get`.');

    expect(stdout, [
      'Installed SDK 3.35.',
      'SDK install failed.',
      'Next: run `fluoh flutter pub get`.',
    ]);
    expect(stderr, ['No SDK selected.']);
  });

  test('decorated ANSI output prefixes status messages', () {
    final stdout = <String>[];
    final stderr = <String>[];
    final output = TerminalOutput(
      stdout: stdout.add,
      stderr: stderr.add,
      style: const TerminalStyle(
        capabilities: TerminalCapabilities(
          ansi: true,
          decorated: true,
          unicode: true,
        ),
      ),
    );

    output.success('Installed SDK 3.35.');
    output.error('No SDK selected.');

    expect(stdout, ['\u001b[32m✓\u001b[0m Installed SDK 3.35.']);
    expect(stderr, ['\u001b[31m✗\u001b[0m No SDK selected.']);
  });

  test('status messages wrap at the configured line length', () {
    final stdout = <String>[];
    final output = TerminalOutput(stdout: stdout.add, lineLength: 32);

    output.warning(
      'No FlutterOH SDK selected for this project; run fluoh sdk use 3.35.',
    );

    expect(stdout.length, greaterThan(1));
    expect(stdout.every((line) => line.length <= 32), isTrue);
  });

  test('decorated wrapped messages align continuation lines', () {
    final stdout = <String>[];
    final output = TerminalOutput(
      stdout: stdout.add,
      lineLength: 36,
      style: const TerminalStyle(
        capabilities: TerminalCapabilities(
          ansi: true,
          decorated: true,
          unicode: true,
        ),
      ),
    );

    output.warning(
      'No FlutterOH SDK selected for this project; run fluoh sdk use 3.35.',
    );

    expect(stdout.length, greaterThan(1));
    expect(stdout.first, startsWith('\u001b[33m!\u001b[0m '));
    expect(stdout.skip(1).every((line) => line.startsWith('  ')), isTrue);
    expect(stdout.map(_stripAnsi).every((line) => line.length <= 36), isTrue);
  });

  test('style uses standard ANSI color codes', () {
    const style = TerminalStyle(
      capabilities: TerminalCapabilities(
        ansi: true,
        decorated: true,
        unicode: true,
      ),
    );

    expect(
      style.status(TerminalStatus.ok, 'installed'),
      '\u001b[32minstalled\u001b[0m',
    );
    expect(style.command('fluoh'), '\u001b[36mfluoh\u001b[0m');
    expect(style.section('Sources'), '\u001b[1mSources\u001b[0m');
  });

  test('table output aligns headers and rows', () {
    final stdout = <String>[];
    final output = TerminalOutput(
      stdout: stdout.add,
      style: const TerminalStyle(
        capabilities: TerminalCapabilities(
          ansi: false,
          decorated: true,
          unicode: true,
        ),
      ),
    );

    output.table(
      columns: const [
        TerminalTableColumn('#', style: TerminalTableCellStyle.muted),
        TerminalTableColumn('Name'),
        TerminalTableColumn('Status', style: TerminalTableCellStyle.status),
      ],
      rows: const [
        ['1', 'camera', 'installed'],
        ['2', 'share', 'remote'],
      ],
    );

    expect(stdout.first, startsWith('#  Name'));
    expect(stdout[1], startsWith('1  camera'));
    expect(stdout[2], startsWith('2  share '));
    expect(stdout[1].length, stdout[2].length);
  });

  test('progress uses transient output when available', () async {
    final stdout = <String>[];
    final transient = <String>[];
    final output = TerminalOutput(
      stdout: stdout.add,
      transient: transient.add,
      style: const TerminalStyle(
        capabilities: TerminalCapabilities(
          ansi: false,
          decorated: true,
          unicode: true,
        ),
      ),
    );

    final result = await output.withProgress('Downloading SDK.', () async {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      return 7;
    }, successMessage: 'Downloaded SDK.');

    expect(result, 7);
    expect(transient.join(), contains('Downloading SDK.'));
    expect(transient.last, startsWith('\r'));
    expect(stdout, ['✓ Downloaded SDK.']);
  });

  test(
    'capability detection respects color and terminal compatibility env',
    () {
      final noColor = TerminalCapabilities.detect(
        enableFormatting: true,
        environment: {'NO_COLOR': '1', 'LANG': 'en_US.UTF-8'},
        supportsAnsiEscapes: true,
      );
      expect(noColor.ansi, isFalse);
      expect(noColor.decorated, isTrue);
      expect(noColor.unicode, isTrue);

      final dumb = TerminalCapabilities.detect(
        enableFormatting: true,
        environment: {'TERM': 'dumb', 'LANG': 'en_US.UTF-8'},
        supportsAnsiEscapes: true,
      );
      expect(dumb.ansi, isFalse);
      expect(dumb.decorated, isFalse);
      expect(dumb.unicode, isFalse);

      final forced = TerminalCapabilities.detect(
        enableFormatting: true,
        environment: {'FORCE_COLOR': '1', 'LANG': 'en_US.UTF-8'},
        supportsAnsiEscapes: false,
      );
      expect(forced.ansi, isTrue);
      expect(forced.decorated, isTrue);
      expect(forced.unicode, isTrue);

      final forceDisabled = TerminalCapabilities.detect(
        enableFormatting: true,
        environment: {'FORCE_COLOR': '0', 'LANG': 'en_US.UTF-8'},
        supportsAnsiEscapes: false,
      );
      expect(forceDisabled.ansi, isFalse);
      expect(forceDisabled.decorated, isFalse);
      expect(forceDisabled.unicode, isTrue);

      final redirected = TerminalCapabilities.detect(
        enableFormatting: true,
        environment: {'LANG': 'en_US.UTF-8'},
        supportsAnsiEscapes: false,
      );
      expect(redirected.ansi, isFalse);
      expect(redirected.decorated, isFalse);
      expect(redirected.unicode, isTrue);
    },
  );
}

String _stripAnsi(String value) {
  return value.replaceAll(RegExp('\u001b\\[[0-9;]*m'), '');
}
