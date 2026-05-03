import 'dart:io';

import 'package:fluoh/fluoh.dart';
import 'package:test/test.dart';

import '../helpers/fluoh_test_context.dart';

void main() {
  test('does not create source config when showing command help', () async {
    final environment = await createTestEnvironment();
    final configFile = File('${environment.homeDirectory.path}/config.json');
    final stdout = <String>[];
    final stderr = <String>[];

    await environment.homeDirectory.delete(recursive: true);

    expect(
      await runFluoh(
        ['sdk', '--help'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(configFile.existsSync(), isFalse);
    expect(stdout, isEmpty);
    expect(stderr, isEmpty);
  });

  test(
    'recreates the default source config before reading source indexes',
    () async {
      final environment = await createTestEnvironment();
      final configFile = File('${environment.homeDirectory.path}/config.json');
      final stdout = <String>[];
      final stderr = <String>[];

      await environment.homeDirectory.delete(recursive: true);

      expect(
        await runFluoh(
          ['sdk', 'list'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        64,
      );

      expect(configFile.existsSync(), isTrue);
      expect(
        configFile.readAsStringSync(),
        contains('https://github.com/FlutterOH/pub.git'),
      );
      expect(
        stderr.join('\n'),
        contains('No readable data source index found'),
      );
    },
  );

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
      final repo10 = await createTaggedGitRepository(
        Directory('${environment.homeDirectory.path}/sdk10'),
        tag: '3.35.8-ohos-0.0.10',
        readme: '# sdk10\n',
      );
      await File('${source.path}/sdk/index.yaml').writeAsString('''
schema: 1
repositoryUrl: ${repo10.path}
versions:
  - version: 3.35.8-ohos-0.0.9
    tag: 3.35.8-ohos-0.0.9
    versionSeries: "3.35"
    status: stable
  - version: 3.35.8-ohos-0.0.10
    tag: 3.35.8-ohos-0.0.10
    versionSeries: "3.35"
    status: stable
''');
      final stdout = <String>[];
      final stderr = <String>[];

      await runFluoh(
        ['source', 'add', 'fixture', source.path],
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

  test('stops when equal-priority sources disagree on an SDK tag', () async {
    final environment = await createTestEnvironment();
    final firstSource = await createPubSourceFixture(
      Directory('${environment.homeDirectory.path}/first'),
    );
    final secondSource = await createPubSourceFixture(
      Directory('${environment.homeDirectory.path}/second'),
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'add', 'first', firstSource.path, '--priority', '100'],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    await runFluoh(
      ['source', 'add', 'second', secondSource.path, '--priority', '100'],
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
      64,
    );
    expect(stderr.join('\n'), contains('Conflicting SDK release'));
    expect(stderr.join('\n'), contains('first and second'));
  });

  test('cleans up a partial SDK install when checkout fails', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    final sdkRepository = await createTaggedGitRepository(
      Directory('${environment.homeDirectory.path}/broken-sdk'),
      tag: '3.35.8-ohos-0.0.3',
      readme: '# sdk\n',
    );
    await File('${source.path}/sdk/index.yaml').writeAsString('''
schema: 1
repositoryUrl: ${sdkRepository.path}
versions:
  - version: 3.35.8-ohos-9.9.9
    tag: 3.35.8-ohos-9.9.9
    versionSeries: "3.35"
    status: stable
''');
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'add', 'fixture', source.path],
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
