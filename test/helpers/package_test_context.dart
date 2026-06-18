import 'dart:io';

import 'package:fluoh/fluoh.dart';
import 'package:test/test.dart';

import 'fluoh_command_context.dart';

Future<Directory> createPackageRepositoryFixture(
  FluohEnvironment environment, {
  bool reviewSpec = true,
}) async {
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
    ['source', 'enable', 'fixture', source.path],
    environment: environment,
    stdout: stdout.add,
    stderr: stderr.add,
  );
  await runFluoh(
    [
      'package',
      'port',
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
  if (reviewSpec) {
    await writeReviewedPackageSpec(packageRepository);
  }
  await commitGeneratedPackageRepository(packageRepository);

  return packageRepository;
}

Future<void> writeReviewedPackageSpec(
  Directory packageRepository, {
  String packageName = 'camera',
}) async {
  final spec = File('${packageRepository.path}/doc/fluoh/$packageName/spec.md');
  final content = await spec.readAsString();
  await spec.writeAsString(
    content
        .replaceFirst(
          '- TODO: Define the user-facing package goal and required platform behavior.',
          '- Provide the public camera package behavior on target platforms while preserving the upstream Dart API.',
        )
        .replaceFirst(
          '- TODO: List the Dart API surface and platform scope for each API.',
          '- Support the exported camera API surface used by package tests and the example app across the platform matrix.',
        )
        .replaceFirst(
          '- TODO: Describe each target platform role: implementation target, preserved baseline, unsupported, not applicable, or manual required.',
          '- Treat OHOS as the implementation target and preserve upstream Android, iOS, web, and desktop behavior when those examples exist.',
        )
        .replaceFirst(
          '- TODO: Map each P0 scope entry to native/platform APIs, permissions, configuration files, device-only constraints, and reviewed sources for every target platform.',
          '- Map P0 capture and permission scope entries to reviewed platform APIs, permissions, and device-only constraints.',
        )
        .replaceFirst(
          '- TODO: Identify example app flows that demonstrate the supported behavior.',
          '- Use the example app to launch the camera flow and expose visible pass, failure, and permission states.',
        )
        .replaceFirst(
          '- TODO: Define unit, integration, example-app, manual-assisted, regression, and device evidence required per platform before delivery.',
          '- Require package tests, example integration or scenario coverage, OHOS build/run, and existing-platform regression evidence.',
        ),
  );
}

Future<void> writeReadyPackageChangelog(
  Directory packageRepository, {
  String tag = 'camera-0.11.0-ohos-3.35-0.1.0',
}) async {
  final guide = File('${packageRepository.path}/FLUOH.md');
  final content = await guide.readAsString();
  await guide.writeAsString(
    content.replaceFirst(
      RegExp(r'### camera-0\.11\.0-ohos-3\.35-0\.1\.0\n\n- TODO: [^\n]+\n'),
      '### $tag\n\n'
      '- Add verified FlutterOH release notes for the fixture package.\n',
    ),
  );
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
