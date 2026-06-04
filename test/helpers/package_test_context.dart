import 'dart:io';

import 'package:fluoh/fluoh.dart';
import 'package:test/test.dart';

import 'fluoh_command_context.dart';

Future<Directory> createPackageRepositoryFixture(
  FluohEnvironment environment,
) async {
  final source = await createPackageSourceFixture(environment.homeDirectory);
  final upstream = await createUpstreamPackageRepository(
    Directory('${environment.homeDirectory.path}/upstream_camera'),
  );
  final packageRepository = Directory(
    '${environment.homeDirectory.path}/package_release',
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
      'package',
      'create',
      upstream.path,
      '--repository-name',
      'camera',
      '--output',
      packageRepository.path,
      '--sdk',
      '3.35.8-ohos-0.0.3',
    ],
    environment: environment,
    stdout: stdout.add,
    stderr: stderr.add,
  );
  await writeReadyPackageChangelog(packageRepository);
  await commitGeneratedPackageRepository(packageRepository);

  return packageRepository;
}

Future<void> writeReadyPackageChangelog(
  Directory packageRepository, {
  String tag = 'camera-0.11.0-ohos-3.35-0.1.0',
}) async {
  await File('${packageRepository.path}/FLUOH_CHANGELOG.md').writeAsString('''
# FlutterOH Changelog

## $tag

- Add verified FlutterOH/OHOS release notes for the fixture package.
''');
}

Future<void> commitGeneratedPackageRepository(
  Directory packageRepository, {
  String message = 'Initialize FlutterOH package repository',
}) async {
  await runGit(packageRepository, [
    'config',
    'user.email',
    'fixture@example.com',
  ]);
  await runGit(packageRepository, ['config', 'user.name', 'Fixture']);
  await commitAll(packageRepository, message: message);
}

Future<ProcessResult> runGit(Directory repo, List<String> arguments) async {
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: repo.path,
  );
  if (result.exitCode != 0) {
    fail('git ${arguments.join(' ')} failed:\n${result.stderr}');
  }
  return result;
}
