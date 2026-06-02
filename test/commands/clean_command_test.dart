import 'dart:convert';
import 'dart:io';

import 'package:fluoh/fluoh.dart';
import 'package:test/test.dart';

import '../helpers/fluoh_command_context.dart';

void main() {
  test('removes only cleanable runtime cache artifacts', () async {
    final environment = await createTestEnvironment();
    await _writeCacheFixture(environment.homeDirectory);
    await Directory(
      '${environment.homeDirectory.path}/sdks/3.35.8-ohos-0.0.3',
    ).create(recursive: true);
    await Directory(
      '${environment.homeDirectory.path}/sources/flutteroh',
    ).create(recursive: true);
    await File(
      '${environment.homeDirectory.path}/config.json',
    ).writeAsString('{}\n');
    await File(
      '${environment.homeDirectory.path}/sources.lock.json',
    ).writeAsString('{}\n');
    await Directory(
      '${environment.workingDirectory.path}/.fluoh',
    ).create(recursive: true);
    await File(
      '${environment.workingDirectory.path}/.fluoh/ai-report-test.md',
    ).writeAsString('report');
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['clean'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(stdout.join('\n'), contains('Removed fluoh cache'));
    expect(stdout.join('\n'), contains('Cache path:'));
    expect(await environment.cacheDirectory.exists(), isFalse);
    expect(
      await Directory(
        '${environment.homeDirectory.path}/sdks/3.35.8-ohos-0.0.3',
      ).exists(),
      isTrue,
    );
    expect(
      await Directory(
        '${environment.homeDirectory.path}/sources/flutteroh',
      ).exists(),
      isTrue,
    );
    expect(await environment.configFile.exists(), isTrue);
    expect(await environment.sourcesLockFile.exists(), isTrue);
    expect(
      await File(
        '${environment.workingDirectory.path}/.fluoh/ai-report-test.md',
      ).exists(),
      isTrue,
    );
    expect(stderr, isEmpty);
  });

  test('dry-run reports cache artifacts without deleting them', () async {
    final environment = await createTestEnvironment();
    await _writeCacheFixture(environment.homeDirectory);
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['clean', '--dry-run'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(stdout.join('\n'), contains('Would remove fluoh cache'));
    expect(stdout.join('\n'), contains('Files: 2'));
    expect(await environment.cacheDirectory.exists(), isTrue);
    expect(
      await File(
        '${environment.packageRunsDirectory.path}/flutter-run-android.log',
      ).exists(),
      isTrue,
    );
    expect(stderr, isEmpty);
  });

  test('prints clean report as json', () async {
    final environment = await createTestEnvironment();
    await _writeCacheFixture(environment.homeDirectory);
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['clean', '--dry-run', '--json'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(stdout, hasLength(1));
    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('schemaVersion', 1));
    expect(report, containsPair('command', 'clean'));
    expect(report, containsPair('ok', true));
    expect(report, containsPair('exitCode', 0));
    expect(report, containsPair('dryRun', true));
    expect(report, containsPair('deleted', false));
    final cache = report['cache'] as Map<String, Object?>;
    expect(cache, containsPair('path', environment.cacheDirectory.path));
    expect(cache, containsPair('exists', true));
    expect(cache, containsPair('files', 2));
    expect(cache, containsPair('directories', 3));
    expect(cache, containsPair('bytes', 11));
    expect(await environment.cacheDirectory.exists(), isTrue);
    expect(stderr, isEmpty);
  });

  test('reports filesystem cleanup failures as json', () async {
    if (Platform.isWindows) {
      return;
    }
    final environment = await createTestEnvironment();
    await _writeCacheFixture(environment.homeDirectory);
    final chmod = await Process.run('chmod', [
      'u-w',
      environment.cacheDirectory.path,
    ]);
    expect(chmod.exitCode, 0);
    addTearDown(() async {
      if (await environment.cacheDirectory.exists()) {
        await Process.run('chmod', ['u+w', environment.cacheDirectory.path]);
      }
    });
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['clean', '--json'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      1,
    );

    expect(stdout, hasLength(1));
    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('schemaVersion', 1));
    expect(report, containsPair('command', 'clean'));
    expect(report, containsPair('ok', false));
    expect(report, containsPair('exitCode', 1));
    expect(report, containsPair('dryRun', false));
    expect(report, containsPair('deleted', false));
    final cache = report['cache'] as Map<String, Object?>;
    expect(cache, containsPair('path', environment.cacheDirectory.path));
    expect(cache, containsPair('exists', true));
    final error = report['error'] as Map<String, Object?>;
    expect(error, containsPair('type', 'filesystem'));
    expect(error['message'], isA<String>());
    expect(await environment.cacheDirectory.exists(), isTrue);
    expect(stderr, isEmpty);
  });

  test('reports missing cache as already clean', () async {
    final environment = await createTestEnvironment();
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['clean'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(stdout.join('\n'), contains('No cleanable cache found'));
    expect(stdout.join('\n'), contains('Cache path:'));
    expect(stderr, isEmpty);
  });
}

Future<void> _writeCacheFixture(Directory home) async {
  final environment = FluohEnvironment(
    homeDirectory: home,
    workingDirectory: Directory.current,
  );
  await environment.packageRunsDirectory.create(recursive: true);
  await environment.ohosSigningDirectory.create(recursive: true);
  await File(
    '${environment.packageRunsDirectory.path}/flutter-run-android.log',
  ).writeAsString('run log');
  await File(
    '${environment.ohosSigningDirectory.path}/debug-profile.p7b',
  ).writeAsString('sign');
}
