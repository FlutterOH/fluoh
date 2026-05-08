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
      expect(manifest, contains('sdk:\n  version: 3.35.8-ohos-0.0.3'));
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

  test('pub adapt preserves separate upstream and dependency paths', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamMonorepoRepository(
      Directory('${environment.homeDirectory.path}/upstream_adapt_paths'),
      packagePath: 'packages/camera/camera',
    );
    final pubRepository = Directory(
      '${environment.homeDirectory.path}/pub_adapt_paths',
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
        '--path',
        'packages/camera/camera',
      ],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );

    final manifestFile = File('${pubRepository.path}/fluoh.yaml');
    await Directory(
      '${pubRepository.path}/adapter/camera',
    ).create(recursive: true);
    await File(
      '${pubRepository.path}/adapter/camera/pubspec.yaml',
    ).writeAsString('''
name: camera
version: 0.11.0

environment:
  sdk: ^3.0.0
''');
    await manifestFile.writeAsString(
      manifestFile.readAsStringSync().replaceFirst(
        '    path: packages/camera/camera',
        '    path: adapter/camera',
      ),
    );
    await commitGeneratedPubRepository(
      pubRepository,
      message: 'Use separate dependency path',
    );
    await bumpUpstreamPackageVersion(
      upstream,
      version: '0.12.0',
      packagePath: 'packages/camera/camera',
    );

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
    expect(manifest, contains('version: 0.12.0'));
    expect(manifest, contains('    path: adapter/camera'));
    expect(manifest, contains('    path: packages/camera/camera'));
    expect(stderr, isEmpty);
  });

  test('pub adapt does not copy upstream paths to root adapters', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamMonorepoRepository(
      Directory('${environment.homeDirectory.path}/upstream_adapt_root_path'),
      packagePath: 'packages/camera/camera',
    );
    final pubRepository = Directory(
      '${environment.homeDirectory.path}/pub_adapt_root_path',
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
        '--path',
        'packages/camera/camera',
      ],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );

    final manifestFile = File('${pubRepository.path}/fluoh.yaml');
    await manifestFile.writeAsString(
      manifestFile.readAsStringSync().replaceFirst(
        '    path: packages/camera/camera\n',
        '',
      ),
    );
    await commitGeneratedPubRepository(
      pubRepository,
      message: 'Use root dependency path',
    );
    await bumpUpstreamPackageVersion(
      upstream,
      version: '0.12.0',
      packagePath: 'packages/camera/camera',
    );

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
    expect(manifest, contains('version: 0.12.0'));
    expect(
      RegExp(
        r'^\s+path: packages/camera/camera$',
        multiLine: true,
      ).allMatches(manifest),
      hasLength(1),
    );
    expect(stderr, isEmpty);
  });
}
