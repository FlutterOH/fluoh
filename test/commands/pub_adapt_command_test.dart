import 'dart:io';

import 'package:fluoh/fluoh.dart';
import 'package:test/test.dart';

import '../helpers/fluoh_test_context.dart';
import '../helpers/pub_test_context.dart';

void main() {
  test(
    'pub adapt merges default branch and refreshes upstream metadata',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPubSourceFixture(environment.homeDirectory);
      final upstream = await createUpstreamPackageRepository(
        Directory('${environment.homeDirectory.path}/upstream_adapt'),
      );
      final pubRepository = Directory(
        '${environment.homeDirectory.path}/pub_adapt',
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
      await commitGeneratedPubRepository(pubRepository);
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
      expect(
        await runFluoh(
          ['pub', 'adapt'],
          environment: pubEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final branch = await runGit(pubRepository, ['branch', '--show-current']);
      final manifest = File(
        '${pubRepository.path}/fluoh.yaml',
      ).readAsStringSync();
      expect(branch.stdout.toString().trim(), 'ohos/3.35');
      expect(manifest, contains('version: 0.12.0'));
      expect(manifest, contains('sdkVersion: 3.35.8-ohos-0.0.3'));
      expect(stdout, contains('Merged main into ohos/3.35.'));
      expect(stdout, contains('Updated pub manifest for camera 0.12.0.'));
      expect(stderr, isEmpty);
    },
  );

  test('pub adapt preserves a non-default manifest status', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamPackageRepository(
      Directory('${environment.homeDirectory.path}/upstream_adapt_status'),
    );
    final pubRepository = Directory(
      '${environment.homeDirectory.path}/pub_adapt_status',
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

    final manifestFile = File('${pubRepository.path}/fluoh.yaml');
    await manifestFile.writeAsString(
      manifestFile.readAsStringSync().replaceFirst(
        'status: experimental',
        'status: compatible',
      ),
    );
    await commitGeneratedPubRepository(
      pubRepository,
      message: 'Promote manifest status',
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
    expect(
      await runFluoh(
        ['pub', 'adapt'],
        environment: pubEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final manifest = manifestFile.readAsStringSync();
    expect(manifest, contains('status: compatible'));
    expect(manifest, isNot(contains('status: experimental')));
    expect(stderr, isEmpty);
  });
}
