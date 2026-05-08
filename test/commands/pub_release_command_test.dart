import 'dart:io';

import 'package:fluoh/fluoh.dart';
import 'package:test/test.dart';

import '../helpers/fluoh_test_context.dart';
import '../helpers/pub_test_context.dart';

void main() {
  test('release creates a tag', () async {
    final environment = await createTestEnvironment();
    final pubRepository = await createPubRepositoryFixture(environment);
    final releaseEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: pubRepository,
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['pub', 'release'],
        environment: releaseEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final tags = await runGit(pubRepository, ['tag', '--list']);
    expect(
      tags.stdout.toString().split('\n'),
      contains('camera-v0.11.0-ohos-3.35.8-0.1.0'),
    );
    expect(
      stdout,
      contains('Created release tag camera-v0.11.0-ohos-3.35.8-0.1.0.'),
    );
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
        'sdk:\n  version: 3.35.8-ohos-0.0.3',
        'sdk:\n  version: 3.35.8-ohos-9.9.9',
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
        'sdk:\n  version: 3.35.8-ohos-9.9.9',
        'sdk:\n  version: 3.35.8-ohos-0.0.3',
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
