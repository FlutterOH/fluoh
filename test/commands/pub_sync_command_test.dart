import 'dart:io';

import 'package:fluoh/fluoh.dart';
import 'package:test/test.dart';

import '../helpers/fluoh_test_context.dart';
import '../helpers/pub_test_context.dart';

void main() {
  test(
    'pub sync fast-forwards the clean default branch from upstream',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPubSourceFixture(environment.homeDirectory);
      final upstream = await createUpstreamPackageRepository(
        Directory('${environment.homeDirectory.path}/upstream_sync'),
      );
      final pubRepository = Directory(
        '${environment.homeDirectory.path}/pub_sync',
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
        [
          'pub',
          'create',
          upstream.path,
          '--output',
          pubRepository.path,
          '--sdk',
          '3.35.8-ohos-0.0.3',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      await bumpUpstreamPackageVersion(upstream, version: '0.12.0');

      final pubEnvironment = FluohEnvironment(
        homeDirectory: environment.homeDirectory,
        workingDirectory: pubRepository,
      );
      expect(
        await runFluoh(
          ['pub', 'sync'],
          environment: pubEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final branch = await runGit(pubRepository, ['branch', '--show-current']);
      expect(branch.stdout.toString().trim(), 'ohos/3.35.8-ohos-0.0.3');

      await runGit(pubRepository, ['checkout', 'main']);
      final pubspec = File(
        '${pubRepository.path}/pubspec.yaml',
      ).readAsStringSync();
      expect(pubspec, contains('version: 0.12.0'));
      expect(File('${pubRepository.path}/fluoh.yaml').existsSync(), isFalse);
      expect(stdout, contains('Synchronized main from upstream/main.'));
      expect(stderr, isEmpty);
    },
  );

  test(
    'pub sync restores the starting branch when fast-forward fails',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPubSourceFixture(environment.homeDirectory);
      final upstream = await createUpstreamPackageRepository(
        Directory('${environment.homeDirectory.path}/upstream_sync_diverged'),
      );
      final pubRepository = Directory(
        '${environment.homeDirectory.path}/pub_sync_diverged',
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
        [
          'pub',
          'create',
          upstream.path,
          '--output',
          pubRepository.path,
          '--sdk',
          '3.35.8-ohos-0.0.3',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );

      await runGit(pubRepository, ['checkout', 'main']);
      await File('${pubRepository.path}/LOCAL.md').writeAsString('local\n');
      await runGit(pubRepository, ['add', 'LOCAL.md']);
      await runGit(pubRepository, ['commit', '-m', 'Local main change']);
      await runGit(pubRepository, ['checkout', 'ohos/3.35.8-ohos-0.0.3']);
      await bumpUpstreamPackageVersion(upstream, version: '0.12.0');

      final pubEnvironment = FluohEnvironment(
        homeDirectory: environment.homeDirectory,
        workingDirectory: pubRepository,
      );
      expect(
        await runFluoh(
          ['pub', 'sync'],
          environment: pubEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        64,
      );

      final branch = await runGit(pubRepository, ['branch', '--show-current']);
      expect(branch.stdout.toString().trim(), 'ohos/3.35.8-ohos-0.0.3');
      expect(stderr.join('\n'), contains('Not possible to fast-forward'));
    },
  );
}
