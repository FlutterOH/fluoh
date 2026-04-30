import 'package:fluoh/fluoh.dart';
import 'package:test/test.dart';

import '../helpers/fluoh_test_context.dart';

void main() {
  test('prints the tool self-upgrade command by default', () async {
    final environment = await createTestEnvironment();
    final stdout = <String>[];
    final stderr = <String>[];

    final exitCode = await runFluoh(
      ['upgrade'],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(exitCode, 0);
    expect(stdout, contains('Upgrade command: dart pub global activate fluoh'));
    expect(stdout, contains('Run with --yes to execute.'));
    expect(stderr, isEmpty);
  });
}
