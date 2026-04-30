import 'dart:io';

import 'package:fluoh/fluoh.dart';
import 'package:test/test.dart';

import '../helpers/fluoh_test_context.dart';

void main() {
  test(
    'lists the default FlutterOH source before user configuration',
    () async {
      final environment = await createTestEnvironment();
      final stdout = <String>[];
      final stderr = <String>[];

      expect(
        await runFluoh(
          ['source', 'list'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      expect(
        stdout,
        contains('flutteroh https://github.com/FlutterOH/pub.git'),
      );
      expect(stderr, isEmpty);
    },
  );

  test('adds, lists, and updates a named pub source', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['source', 'add', 'fixture', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );
    expect(
      await runFluoh(
        ['source', 'list'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );
    expect(
      await runFluoh(
        ['source', 'update', 'fixture'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(stdout, contains('Added source fixture: ${source.path}'));
    expect(stdout, contains('fixture ${source.path}'));
    expect(stdout, contains('Updated source fixture.'));
    expect(stderr, isEmpty);
  });

  test('does not allow replacing the official source', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['source', 'add', 'flutteroh', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );
    expect(stderr.join('\n'), contains('Cannot replace the official source.'));
  });

  test('removes non-default sources but keeps the official source', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['source', 'add', 'team', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );
    expect(
      await runFluoh(
        ['source', 'remove', 'team'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );
    expect(
      await runFluoh(
        ['source', 'list'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(stdout, contains('Removed source team.'));
    expect(stdout.last, 'flutteroh https://github.com/FlutterOH/pub.git');

    expect(
      await runFluoh(
        ['source', 'remove', 'flutteroh'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );
    expect(stderr.join('\n'), contains('Cannot remove the official source.'));
  });

  test('reports unknown source names for update and remove', () async {
    final environment = await createTestEnvironment();
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['source', 'update', 'missing'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );
    expect(stderr.join('\n'), contains('Unknown source "missing".'));

    stderr.clear();
    expect(
      await runFluoh(
        ['source', 'remove', 'missing'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );
    expect(stderr.join('\n'), contains('Unknown source "missing".'));
  });

  test('updates a git source URL into the local source cache', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    await initializeGitRepository(source);
    final sourceUrl = 'file://${source.path}';
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['source', 'add', 'remote', sourceUrl],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );
    expect(
      await runFluoh(
        ['source', 'update', 'remote'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(stdout, contains('Added source remote: $sourceUrl'));
    expect(stdout, contains('Updated source remote.'));
    expect(
      File(
        '${environment.homeDirectory.path}/sources/remote/sdk/index.yaml',
      ).existsSync(),
      isTrue,
    );
    expect(stderr, isEmpty);
  });

  test(
    'updates all sources and accepts package-only supplemental sources',
    () async {
      final environment = await createTestEnvironment();
      final supplemental = Directory(
        '${environment.homeDirectory.path}/supplemental',
      );
      await Directory('${supplemental.path}/packages').create(recursive: true);
      await File('${supplemental.path}/packages/registry.yaml').writeAsString(
        '''
schema: 1
packages: []
''',
      );
      final stdout = <String>[];
      final stderr = <String>[];

      expect(
        await runFluoh(
          ['source', 'add', 'team', supplemental.path, '--priority', '200'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );
      expect(
        await runFluoh(
          ['source', 'update', 'team'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      expect(stdout, contains('Updated source team.'));
      expect(stderr, isEmpty);
    },
  );

  test('updates a YAML source', () async {
    final environment = await createTestEnvironment();
    final source = Directory('${environment.homeDirectory.path}/schema_source');
    await Directory('${source.path}/sdk').create(recursive: true);
    await Directory('${source.path}/packages').create(recursive: true);
    await File('${source.path}/sdk/index.yaml').writeAsString('''
schema: 1
repositoryUrl: ${environment.homeDirectory.path}/flutter-ohos-sdk
versions:
  - version: 3.35.8-ohos-0.0.3
    tag: 3.35.8-ohos-0.0.3
    versionSeries: "3.35"
    status: stable
''');
    await File('${source.path}/packages/registry.yaml').writeAsString('''
schema: 1
packages: []
''');
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['source', 'add', 'schema', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(
      await runFluoh(
        ['source', 'update', 'schema'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(stdout, contains('Updated source schema.'));
    expect(stderr, isEmpty);
  });

  test('reports missing package manifests as usage errors', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    await File('${source.path}/packages/manifests/camera.yaml').delete();
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['source', 'add', 'broken', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );
    expect(
      await runFluoh(
        ['source', 'update', 'broken'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );

    expect(stderr.join('\n'), contains('Source broken could not be read'));
    expect(stderr.join('\n'), contains('camera.yaml'));
  });

  test('reports invalid source indexes as usage errors', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    await File('${source.path}/sdk/index.yaml').writeAsString('''
schema: 1
repositoryUrl: ${environment.homeDirectory.path}/flutter-ohos-sdk
versions: {}
''');
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['source', 'add', 'broken', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );
    expect(
      await runFluoh(
        ['source', 'update', 'broken'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );

    expect(stderr.join('\n'), contains('Source broken is not valid'));
    expect(stderr.join('\n'), contains('SDK source versions must be a list.'));
  });
}
