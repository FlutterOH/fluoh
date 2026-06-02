import 'dart:convert';
import 'dart:io';

import 'package:fluoh/fluoh.dart';
import 'package:test/test.dart';

import '../helpers/fluoh_command_context.dart';
import '../helpers/package_test_context.dart';

void main() {
  test(
    'chains source add, package create, deps check, deps fix, verify, check, and release',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      final upstream = await createUpstreamPackageRepository(
        Directory('${environment.homeDirectory.path}/upstream_camera'),
      );
      final packageRepository = Directory(
        '${environment.homeDirectory.path}/package_camera',
      );
      final stdout = <String>[];
      final stderr = <String>[];

      // Phase 1: Register source and create package repository.
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
            '--output',
            packageRepository.path,
            '--sdk',
            '3.35.8-ohos-0.0.3',
          ],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );
      await commitGeneratedPackageRepository(packageRepository);

      // Verify repository structure.
      final manifest = File('${packageRepository.path}/fluoh.yaml');
      expect(manifest.existsSync(), isTrue);
      expect(manifest.readAsStringSync(), contains('packages:\n  camera:'));
      final branch = await runGit(packageRepository, [
        'branch',
        '--show-current',
      ]);
      expect(branch.stdout.toString().trim(), 'ohos/3.35');

      // Phase 2: deps check in a Flutter project that uses the package.
      await writeFlutterProjectFixture(environment.workingDirectory);
      await runFluoh(
        ['sdk', 'use', '3.35.8-ohos-0.0.3'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      stdout.clear();
      expect(
        await runFluoh(
          ['deps', 'check', '--json'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );
      final checkReport = jsonDecode(stdout.last) as Map<String, Object?>;
      expect(checkReport, containsPair('schemaVersion', 1));
      expect(checkReport, containsPair('command', 'deps check'));
      final checkDeps = checkReport['dependencies'] as List<Object?>;
      expect(
        checkDeps,
        contains(
          allOf(
            containsPair('name', 'camera'),
            containsPair('status', 'implemented'),
            containsPair('direct', true),
          ),
        ),
      );

      // Phase 3: deps fix writes OHOS dependency overrides.
      stdout.clear();
      expect(
        await runFluoh(
          ['deps', 'fix'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );
      final pubspec = File(
        '${environment.workingDirectory.path}/pubspec.yaml',
      ).readAsStringSync();
      expect(pubspec, contains('dependency_overrides:'));
      expect(pubspec, contains('camera-0.11.0-ohos-3.35-1'));

      // Phase 4: Verify the package (pub get + analyze + test).
      final releaseEnvironment = FluohEnvironment(
        homeDirectory: environment.homeDirectory,
        workingDirectory: packageRepository,
      );
      stdout.clear();
      expect(
        await runFluoh(
          ['verify', '--package', 'camera', '--json'],
          environment: releaseEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );
      final verifyReport = jsonDecode(stdout.last) as Map<String, Object?>;
      expect(verifyReport, containsPair('schemaVersion', 1));
      expect(verifyReport, containsPair('command', 'verify'));
      expect(verifyReport, containsPair('ok', true));
      final targets = verifyReport['targets'] as List<Object?>;
      expect(targets, isNotEmpty);
      final packageTarget = targets.first as Map<String, Object?>;
      expect(packageTarget, containsPair('passed', true));
      final target = packageTarget['target'] as Map<String, Object?>;
      expect(target, containsPair('kind', 'package'));
      expect(target, containsPair('name', 'camera'));

      // Phase 5: Release check validates without creating tags.
      stdout.clear();
      expect(
        await runFluoh(
          ['package', 'check', '--json'],
          environment: releaseEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );
      final releaseReport = jsonDecode(stdout.last) as Map<String, Object?>;
      expect(releaseReport, containsPair('schemaVersion', 1));
      expect(releaseReport, containsPair('command', 'package check'));
      expect(releaseReport, containsPair('ok', true));
      expect(releaseReport, containsPair('dryRun', true));
      expect(
        releaseReport,
        containsPair('tags', ['camera-0.11.0-ohos-3.35-0.1.0']),
      );
      final tags = await runGit(packageRepository, ['tag', '--list']);
      expect(tags.stdout.toString(), isNot(contains('camera-0.11.0-ohos')));

      // Phase 6: Actual release creates the tag.
      stdout.clear();
      expect(
        await runFluoh(
          ['package', 'release'],
          environment: releaseEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );
      final releaseTags = await runGit(packageRepository, ['tag', '--list']);
      expect(
        releaseTags.stdout.toString().split('\n'),
        contains('camera-0.11.0-ohos-3.35-0.1.0'),
      );
      expect(stderr, isEmpty);
    },
  );
}
