import 'dart:convert';

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
    expect(report, containsPair('branchMatches', true));
    expect(report, containsPair('workingTreeClean', true));
    expect(report, containsPair('ready', false));
    final packages = report['packages'] as List<Object?>;
    final package = packages.single as Map<String, Object?>;
    expect(package, containsPair('package', 'camera'));
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
