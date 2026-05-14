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
    expect(stdout.join('\n'), contains('Available subcommands:'));
    expect(stdout.join('\n'), contains('  use'));
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

  test(
    'lists and removes installed SDKs without readable source indexes',
    () async {
      final environment = await createTestEnvironment();
      final localSdk = Directory(
        '${environment.homeDirectory.path}/sdks/3.34.0-ohos-0.0.1',
      );
      await localSdk.create(recursive: true);
      final stdout = <String>[];
      final stderr = <String>[];

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
          ['sdk', 'remove', '3.34.0-ohos-0.0.1'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      expect(stdout, contains('[1] 3.34.0-ohos-0.0.1 unknown installed'));
      expect(stdout, contains('Removed SDK 3.34.0-ohos-0.0.1.'));
      expect(localSdk.existsSync(), isFalse);
      expect(stderr, isEmpty);
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
      ['sdk', 'use', '3.35.8-ohos-0.0.3'],
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

    expect(stdout, contains('[1] 3.35.8-ohos-0.0.3 stable remote'));
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

  test('lists installed SDKs that are missing from source indexes', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    final localSdk = Directory(
      '${environment.homeDirectory.path}/sdks/3.34.0-ohos-0.0.1',
    );
    await localSdk.create(recursive: true);
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

    expect(stdout, contains('[1] 3.35.8-ohos-0.0.3 stable remote'));
    expect(stdout, contains('[2] 3.34.0-ohos-0.0.1 unknown installed'));
    expect(
      File('${environment.homeDirectory.path}/config.json').readAsStringSync(),
      isNot(contains('"sdks"')),
    );
    expect(stderr, isEmpty);
  });

  test('removes installed SDKs that are missing from source indexes', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    final localSdk = Directory(
      '${environment.homeDirectory.path}/sdks/3.34.0-ohos-0.0.1',
    );
    await localSdk.create(recursive: true);
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
        ['sdk', 'remove', '3.34.0-ohos-0.0.1'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(stdout, contains('Removed SDK 3.34.0-ohos-0.0.1.'));
    expect(localSdk.existsSync(), isFalse);
    expect(stderr, isEmpty);
  });

  test('reports no current SDK without project fluoh.yaml', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
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
        ['sdk', 'install', '3.35.8-ohos-0.0.3'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(
      await runFluoh(
        ['sdk', 'current'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      1,
    );

    expect(stdout, contains('No SDK selected.'));
    expect(stderr, isEmpty);
  });

  test('reads SDK selection from pub manifests', () async {
    final environment = await createTestEnvironment();
    await File('${environment.workingDirectory.path}/fluoh.yaml').writeAsString(
      '''
schema: 1
sdk:
  version: 3.35.8-ohos-0.0.3
''',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['sdk', 'current'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(stdout, contains('Current SDK: 3.35.8-ohos-0.0.3'));
    expect(stderr, isEmpty);
  });

  test('resolves SDK version series to the latest release', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    final sdkRepository = Directory(
      '${environment.homeDirectory.path}/flutter-ohos-sdk',
    );
    await _runProcess('git', ['tag', '3.35.9-ohos-0.0.4'], sdkRepository);
    await writeSdkSourceFixture(
      source,
      sdkRepository: sdkRepository.path,
      releases: {'3.35.8-ohos-0.0.3': 'stable', '3.35.9-ohos-0.0.4': 'stable'},
    );
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
        ['sdk', 'use', '3.35'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(
      File(
        '${environment.workingDirectory.path}/fluoh.yaml',
      ).readAsStringSync(),
      contains('version: 3.35.9-ohos-0.0.4'),
    );
    expect(stdout, contains('Using Flutter OHOS SDK 3.35.9-ohos-0.0.4.'));
    expect(stderr, isEmpty);
  });

  test(
    'stops when equal-priority sources disagree on an SDK version',
    () async {
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
      expect(
        await runFluoh(
          ['source', 'add', 'second', secondSource.path, '--priority', '100'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        64,
      );
      expect(stderr.join('\n'), contains('Conflicting SDK version'));
      expect(stderr.join('\n'), contains('first and second'));
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
    await writeSdkSourceFixture(
      source,
      sdkRepository: sdkRepository.path,
      releases: {'3.35.8-ohos-9.9.9': 'stable'},
    );
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

Future<void> _runProcess(
  String executable,
  List<String> arguments,
  Directory workingDirectory,
) async {
  final result = await Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory.path,
  );
  if (result.exitCode != 0) {
    fail('$executable ${arguments.join(' ')} failed:\n${result.stderr}');
  }
}
