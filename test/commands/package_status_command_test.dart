import 'dart:convert';
import 'dart:io';

import 'package:fluoh/fluoh.dart';
import 'package:test/test.dart';

import '../helpers/fluoh_command_context.dart';
import '../helpers/package_test_context.dart';

void main() {
  test('reports package release readiness as json', () async {
    final environment = await createTestEnvironment();
    final packageRepository = await createPackageRepositoryFixture(environment);
    final packageEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['package', 'status', '--json'],
        environment: packageEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('schema', 1));
    expect(report, containsPair('command', 'package status'));
    expect(report, containsPair('ok', false));
    expect(report, containsPair('exitCode', 0));
    expect(report, containsPair('branchMatches', true));
    expect(report, containsPair('workingTreeClean', true));
    expect(report, containsPair('ready', false));
    final blockers = report['readinessBlockers'] as List<Object?>;
    expect(
      blockers,
      contains(
        allOf(
          containsPair('scope', 'package'),
          containsPair('package', 'camera'),
          containsPair('code', 'evidence.ohos_run_missing'),
          containsPair(
            'nextCommand',
            'fluoh run --platform ohos --package camera --auto-emulator --json',
          ),
        ),
      ),
    );
    expect(
      blockers,
      contains(
        allOf(
          containsPair('scope', 'package'),
          containsPair('package', 'camera'),
          containsPair('code', 'evidence.interaction_missing'),
        ),
      ),
    );
    final packages = report['packages'] as List<Object?>;
    final package = packages.single as Map<String, Object?>;
    expect(package, containsPair('package', 'camera'));
    final packageBlockers = package['readinessBlockers'] as List<Object?>;
    expect(packageBlockers, isNotEmpty);
    final checks = package['checks'] as List<Object?>;
    expect(
      checks,
      contains(
        allOf(
          containsPair('name', 'release-status'),
          containsPair('status', 'warning'),
        ),
      ),
    );
    expect(stderr, isEmpty);
  });

  test('reports the current package branch by default', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamWorkspaceRepository(
      Directory('${environment.homeDirectory.path}/upstream_status_multi'),
      packagePath: 'packages/camera/camera',
      packageName: 'camera',
      version: '0.11.0',
    );
    await runGit(upstream, ['tag', 'camera-v0.11.0']);
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_status_multi',
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
        [
          'package',
          'create',
          upstream.path,
          '--repository-name',
          'package_status_multi',
          '--output',
          packageRepository.path,
          '--sdk',
          '3.35.8-ohos-0.0.3',
          '--package-path',
          'packages/camera/camera',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );
    await commitGeneratedPackageRepository(packageRepository);
    final packageEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    stdout.clear();

    expect(
      await runFluoh(
        ['package', 'status', '--json'],
        environment: packageEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    final packages = report['packages'] as List<Object?>;
    expect(
      packages.cast<Map<String, Object?>>().map(
        (package) => package['package'],
      ),
      containsAll(['camera']),
    );
    expect(packages, hasLength(1));
    expect(report['readinessBlockers'], isA<List<Object?>>());
    expect(stderr, isEmpty);
  });

  test('reports release validation failures as readiness warnings', () async {
    final environment = await createTestEnvironment();
    final packageRepository = await createPackageRepositoryFixture(environment);
    await runGit(packageRepository, ['tag', 'camera-0.11.0-ohos-3.35-0.2.0']);
    final packageEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['package', 'status', '--json'],
        environment: packageEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('ready', false));
    final packages = report['packages'] as List<Object?>;
    final package = packages.single as Map<String, Object?>;
    final checks = package['checks'] as List<Object?>;
    expect(
      checks,
      contains(
        allOf(
          containsPair('name', 'release-metadata'),
          containsPair('status', 'warning'),
          containsPair(
            'message',
            contains('must be greater than latest release version 0.2.0'),
          ),
        ),
      ),
    );
    expect(stderr, isEmpty);
  });
}
