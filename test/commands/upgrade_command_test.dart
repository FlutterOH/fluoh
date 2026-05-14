import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:fluoh/src/upgrade/upgrade_command.dart';
import 'package:test/test.dart';

void main() {
  test(
    'executes dart pub global activate by default for pub-cache installations',
    () async {
      final processRunner = _FakeProcessRunner();
      final result = await _runUpgradeCommand(
        ['upgrade'],
        scriptUri: Uri.file(
          '/home/example/.pub-cache/hosted/pub.dev/fluoh-0.1.0/bin/fluoh.dart',
        ),
        processRunner: processRunner.run,
      );

      expect(result.exitCode, 0);
      expect(processRunner.calls, hasLength(1));
      expect(processRunner.calls.single.$1, 'dart');
      expect(processRunner.calls.single.$2, [
        'pub',
        'global',
        'activate',
        'fluoh',
      ]);
      expect(result.stdout, contains('upgraded'));
      expect(result.stderr, isEmpty);
    },
  );

  test('uses brew upgrade for Homebrew installations', () async {
    final processRunner = _FakeProcessRunner();
    final result = await _runUpgradeCommand(
      ['upgrade'],
      scriptUri: Uri.file(
        '/opt/homebrew/Cellar/fluoh/0.1.0/libexec/pub-cache/bin/fluoh',
      ),
      processRunner: processRunner.run,
    );

    expect(result.exitCode, 0);
    expect(processRunner.calls, hasLength(1));
    expect(processRunner.calls.single.$1, 'brew');
    expect(processRunner.calls.single.$2, ['upgrade', 'fluoh']);
    expect(result.stdout, contains('upgraded'));
    expect(result.stderr, isEmpty);
  });

  test('refuses to replace a local source checkout with pub.dev', () async {
    final processRunner = _FakeProcessRunner();
    final result = await _runUpgradeCommand(
      ['upgrade'],
      scriptUri: Uri.file('/home/example/dev/fluoh/bin/fluoh.dart'),
      processRunner: processRunner.run,
    );

    expect(result.exitCode, 64);
    expect(processRunner.calls, isEmpty);
    expect(
      result.stderr.join('\n'),
      contains('Local source checkouts cannot be upgraded automatically'),
    );
  });
}

Future<_UpgradeRunResult> _runUpgradeCommand(
  List<String> arguments, {
  required Uri scriptUri,
  required UpgradeProcessRunner processRunner,
}) async {
  final stdout = <String>[];
  final stderr = <String>[];
  final runner = CommandRunner<int>('fluoh', 'test')
    ..addCommand(
      UpgradeCommand(
        stdout: stdout.add,
        stderr: stderr.add,
        processRunner: processRunner,
        scriptUriProvider: () => scriptUri,
      ),
    );

  final exitCode = await runner.run(arguments);
  return _UpgradeRunResult(exitCode ?? 0, stdout, stderr);
}

class _UpgradeRunResult {
  const _UpgradeRunResult(this.exitCode, this.stdout, this.stderr);

  final int exitCode;
  final List<String> stdout;
  final List<String> stderr;
}

class _FakeProcessRunner {
  final calls = <(String, List<String>)>[];

  Future<ProcessResult> run(String executable, List<String> arguments) async {
    calls.add((executable, arguments));
    return ProcessResult(123, 0, 'upgraded\n', '');
  }
}
