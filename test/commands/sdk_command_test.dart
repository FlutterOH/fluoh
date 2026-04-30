import 'dart:convert';
import 'dart:io';

import 'package:fluoh/fluoh.dart';
import 'package:test/test.dart';

import '../helpers/fluoh_test_context.dart';

void main() {
  test('lists, installs, reports current, and removes SDKs', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    await writeFlutterProjectFixture(environment.workingDirectory);
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'add', 'fixture', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    await runFluoh(
      ['source', 'use', 'fixture'],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(
      await runFluoh(
        ['sdk', 'list'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );
    expect(
      await runFluoh(
        ['sdk', 'install', '3.35.8-ohos-0.0.3'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    await runFluoh(
      ['use', '3.35'],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(
      await runFluoh(
        ['sdk', 'current'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );
    expect(
      await runFluoh(
        ['sdk', 'remove', '3.35.8-ohos-0.0.3'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(stdout, contains('3.35.8-ohos-0.0.3 stable remote'));
    expect(stdout, contains('Installed SDK 3.35.8-ohos-0.0.3.'));
    expect(stdout, contains('Current SDK: 3.35.8-ohos-0.0.3'));
    expect(stdout, contains('Removed SDK 3.35.8-ohos-0.0.3.'));
    expect(
      Directory(
        '${environment.homeDirectory.path}/sdks/3.35.8-ohos-0.0.3',
      ).existsSync(),
      isFalse,
    );
    expect(stderr, isEmpty);
  });

  test(
    'resolves SDK line to numeric latest tag when publish dates are absent',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPubSourceFixture(environment.homeDirectory);
      await writeFlutterProjectFixture(environment.workingDirectory);
      final repo9 = await createTaggedGitRepository(
        Directory('${environment.homeDirectory.path}/sdk9'),
        tag: '3.35.8-ohos-0.0.9',
        readme: '# sdk9\n',
      );
      final repo10 = await createTaggedGitRepository(
        Directory('${environment.homeDirectory.path}/sdk10'),
        tag: '3.35.8-ohos-0.0.10',
        readme: '# sdk10\n',
      );
      await File('${source.path}/generated/sdk-index.json').writeAsString(
        jsonEncode({
          'schemaVersion': 1,
          'releases': [
            {
              'version': '3.35.8-ohos-0.0.9',
              'flutterVersion': '3.35.8',
              'channel': 'stable',
              'repository': repo9.path,
              'tag': '3.35.8-ohos-0.0.9',
            },
            {
              'version': '3.35.8-ohos-0.0.10',
              'flutterVersion': '3.35.8',
              'channel': 'stable',
              'repository': repo10.path,
              'tag': '3.35.8-ohos-0.0.10',
            },
          ],
        }),
      );
      final stdout = <String>[];
      final stderr = <String>[];

      await runFluoh(
        ['source', 'add', 'fixture', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      await runFluoh(
        ['source', 'use', 'fixture'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );

      expect(
        await runFluoh(
          ['use', '3.35'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );
      expect(stdout, contains('Using Flutter OHOS SDK 3.35.8-ohos-0.0.10.'));
      expect(stderr, isEmpty);
    },
  );

  test('cleans up a partial SDK install when checkout fails', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    final sdkRepository = await createTaggedGitRepository(
      Directory('${environment.homeDirectory.path}/broken-sdk'),
      tag: '3.35.8-ohos-0.0.3',
      readme: '# sdk\n',
    );
    await File('${source.path}/generated/sdk-index.json').writeAsString(
      jsonEncode({
        'schemaVersion': 1,
        'releases': [
          {
            'version': '3.35.8-ohos-9.9.9',
            'flutterVersion': '3.35.8',
            'channel': 'stable',
            'repository': sdkRepository.path,
            'tag': '3.35.8-ohos-9.9.9',
          },
        ],
      }),
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'add', 'fixture', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    await runFluoh(
      ['source', 'use', 'fixture'],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(
      await runFluoh(
        ['sdk', 'install', '3.35.8-ohos-9.9.9'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );
    expect(
      Directory(
        '${environment.homeDirectory.path}/sdks/3.35.8-ohos-9.9.9',
      ).existsSync(),
      isFalse,
    );
    expect(stderr.join('\n'), contains('3.35.8-ohos-9.9.9'));
  });
}
