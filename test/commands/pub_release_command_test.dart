import 'dart:io';

import 'package:fluoh/fluoh.dart';
import 'package:test/test.dart';

import '../helpers/fluoh_test_context.dart';
import '../helpers/pub_test_context.dart';

void main() {
  test('release writes a pub source package update', () async {
    final environment = await createTestEnvironment();
    final pubRepository = await createPubRepositoryFixture(environment);
    final pubSource = Directory('${environment.homeDirectory.path}/pub_update');
    final releaseEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: pubRepository,
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['pub', 'release', '--source-update', pubSource.path],
        environment: releaseEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final registryYaml = File('${pubSource.path}/packages/repositories.yaml');
    final manifestYaml = File(
      '${pubSource.path}/packages/manifests/camera.yaml',
    );
    expect(registryYaml.existsSync(), isTrue);
    expect(manifestYaml.existsSync(), isTrue);
    final registry = registryYaml.readAsStringSync();
    final manifest = manifestYaml.readAsStringSync();
    expect(registry, contains('repositories:'));
    expect(registry, contains('name: camera'));
    expect(registry, contains('url: git@github.com:FlutterOH/camera.git'));
    expect(registry, contains('path: .'));
    expect(registry, isNot(contains('packagePath:')));
    expect(registry, isNot(contains('upstreamUrl:')));
    expect(registry, isNot(contains('status:')));
    expect(manifest, contains('        - 3.35.8-ohos-0.0.3'));
    expect(manifest, contains('upstreamVersion: 0.11.0'));
    expect(manifest, contains('versionSeries: 3.35'));
    expect(manifest, isNot(contains('      version: 3.35.8-ohos-0.0.3')));
    expect(manifest, contains('fluohBranch: ohos/3.35'));
    expect(manifest, contains('tag: camera-v0.11.0-ohos-3.35.8-0.1.0'));
    expect(
      manifest,
      contains('      url: https://github.com/FlutterOH/camera.git'),
    );
    expect(manifest, contains('      ref: camera-v0.11.0-ohos-3.35.8-0.1.0'));
    expect(File('${pubSource.path}/packages/index.yaml').existsSync(), isFalse);
    expect(
      File('${pubSource.path}/packages/camera.yaml').existsSync(),
      isFalse,
    );
    expect(
      await runFluoh(
        ['source', 'add', 'generated', pubSource.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );
    expect(stdout, contains('Wrote pub source update for camera.'));
    expect(stdout, contains('Added source generated: ${pubSource.path}'));
    expect(stderr, isEmpty);
  });

  test(
    'release fails for dirty pub worktrees and mismatched branches',
    () async {
      final environment = await createTestEnvironment();
      final pubRepository = await createPubRepositoryFixture(environment);
      final stdout = <String>[];
      final stderr = <String>[];

      await File('${pubRepository.path}/README.md').writeAsString('# dirty\n');
      final dirtyEnvironment = FluohEnvironment(
        homeDirectory: environment.homeDirectory,
        workingDirectory: pubRepository,
      );
      expect(
        await runFluoh(
          ['pub', 'release'],
          environment: dirtyEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        64,
      );
      expect(
        stderr.join('\n'),
        contains('Release requires a clean working tree'),
      );

      await runGit(pubRepository, ['checkout', '--', 'README.md']);
      await runGit(pubRepository, ['checkout', '-b', 'ohos/3.34']);
      stderr.clear();
      expect(
        await runFluoh(
          ['pub', 'release'],
          environment: dirtyEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        64,
      );
      expect(
        stderr.join('\n'),
        contains('does not match pub branch ohos/3.35'),
      );
    },
  );

  test('release validates SDK tag and existing release tag commit', () async {
    final environment = await createTestEnvironment();
    final pubRepository = await createPubRepositoryFixture(environment);
    final releaseEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: pubRepository,
    );
    final stdout = <String>[];
    final stderr = <String>[];

    var manifest = File('${pubRepository.path}/fluoh.yaml').readAsStringSync();
    await File('${pubRepository.path}/fluoh.yaml').writeAsString(
      manifest.replaceFirst(
        '  sdkVersion: 3.35.8-ohos-0.0.3',
        '  sdkVersion: 3.35.8-ohos-9.9.9',
      ),
    );
    await runGit(pubRepository, ['add', 'fluoh.yaml']);
    await runGit(pubRepository, ['commit', '-m', 'Use invalid SDK tag']);

    expect(
      await runFluoh(
        ['pub', 'release'],
        environment: releaseEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );
    expect(stderr.join('\n'), contains('was not found in configured sources'));

    manifest = File('${pubRepository.path}/fluoh.yaml').readAsStringSync();
    await File('${pubRepository.path}/fluoh.yaml').writeAsString(
      manifest.replaceFirst(
        '  sdkVersion: 3.35.8-ohos-9.9.9',
        '  sdkVersion: 3.35.8-ohos-0.0.3',
      ),
    );
    await runGit(pubRepository, ['add', 'fluoh.yaml']);
    await runGit(pubRepository, ['commit', '-m', 'Restore valid SDK tag']);
    await runGit(pubRepository, [
      'tag',
      'camera-v0.11.0-ohos-3.35.8-0.1.0',
      'HEAD~1',
    ]);

    stderr.clear();
    expect(
      await runFluoh(
        ['pub', 'release'],
        environment: releaseEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );
    expect(stderr.join('\n'), contains('already exists on a different commit'));
  });
}
