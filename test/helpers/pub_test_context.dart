import 'dart:io';

import 'package:fluoh/fluoh.dart';
import 'package:test/test.dart';

import 'fluoh_test_context.dart';

Future<Directory> createPubRepositoryFixture(
  FluohEnvironment environment,
) async {
  final source = await createPubSourceFixture(environment.homeDirectory);
  final upstream = await createUpstreamPackageRepository(
    Directory('${environment.homeDirectory.path}/upstream_camera'),
  );
  final pubRepository = Directory(
    '${environment.homeDirectory.path}/pub_release',
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

  return pubRepository;
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
