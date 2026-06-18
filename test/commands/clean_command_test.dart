import 'dart:convert';
import 'dart:io';

import 'package:fluoh/fluoh.dart';
import 'package:test/test.dart';

import '../helpers/fluoh_command_context.dart';

void main() {
  test('removes current task scratch output by default', () async {
    final environment = await createTestEnvironment();
    final task = await _writeTaskFixture(environment);
    await Directory(
      '${environment.homeDirectory.path}/sdks/3.35.8-ohos-0.0.3',
    ).create(recursive: true);
    await Directory(
      '${environment.homeDirectory.path}/sources/flutteroh',
    ).create(recursive: true);
    await environment.configFile.writeAsString('{}\n');
    await environment.sourcesLockFile.writeAsString('{}\n');
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

    expect(stdout.join('\n'), contains('Removed fluoh task output'));
    expect(await Directory('${task.path}/scratch').exists(), isFalse);
    expect(await File('${task.path}/reports/report.md').exists(), isTrue);
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
    expect(stderr, isEmpty);
  });

  test('dry-run reports task scratch output without deleting it', () async {
    final environment = await createTestEnvironment();
    final task = await _writeTaskFixture(environment);
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

    expect(stdout.join('\n'), contains('Would remove fluoh task output'));
    expect(stdout.join('\n'), contains('Files: 2'));
    expect(await File('${task.path}/scratch/logs/run.log').exists(), isTrue);
    expect(stderr, isEmpty);
  });

  test('prints task clean report as json', () async {
    final environment = await createTestEnvironment();
    final task = await _writeTaskFixture(environment);
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
    expect(report, containsPair('schema', 1));
    expect(report, containsPair('command', 'clean'));
    expect(report, containsPair('ok', true));
    expect(report, containsPair('exitCode', 0));
    expect(report, containsPair('dryRun', true));
    expect(report, containsPair('deleted', false));
    expect(
      report.keys,
      unorderedEquals([
        'schema',
        'command',
        'ok',
        'exitCode',
        'dryRun',
        'deleted',
        'targets',
      ]),
    );
    final targets = report['targets'] as List<Object?>;
    expect(targets, hasLength(1));
    final target = targets.single as Map<String, Object?>;
    expect(target, containsPair('path', '${task.path}/scratch'));
    expect(target, containsPair('exists', true));
    expect(target, containsPair('files', 2));
    expect(target, containsPair('directories', 3));
    expect(target, containsPair('bytes', 10));
    expect(await Directory('${task.path}/scratch').exists(), isTrue);
    expect(stderr, isEmpty);
  });

  test('tasks flag removes the whole current task workspace', () async {
    final environment = await createTestEnvironment();
    final task = await _writeTaskFixture(environment);
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['clean', '--tasks'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(await task.exists(), isFalse);
    expect(
      await File(
        '${environment.workingDirectory.path}/.fluoh/current-task.json',
      ).exists(),
      isFalse,
    );
    expect(stderr, isEmpty);
  });

  test('all flag removes every task workspace', () async {
    final environment = await createTestEnvironment();
    final first = await _writeTaskFixture(environment);
    final second = await _writeTaskFixture(environment, id: 'test-task-two');
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['clean', '--all'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(await first.exists(), isFalse);
    expect(await second.exists(), isFalse);
    expect(
      await File(
        '${environment.workingDirectory.path}/.fluoh/current-task.json',
      ).exists(),
      isFalse,
    );
    expect(stderr, isEmpty);
  });

  test('all flag is a no-op when no task workspace exists', () async {
    final environment = await createTestEnvironment();
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['clean', '--all', '--json'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('ok', true));
    expect(report, containsPair('deleted', false));
    expect(report['targets'], isEmpty);
    expect(stderr, isEmpty);
  });

  test('reports filesystem cleanup failures as json', () async {
    if (Platform.isWindows) {
      return;
    }
    final environment = await createTestEnvironment();
    final task = await _writeTaskFixture(environment);
    final chmod = await Process.run('chmod', ['u-w', task.path]);
    expect(chmod.exitCode, 0);
    addTearDown(() async {
      if (await task.exists()) {
        await Process.run('chmod', ['u+w', task.path]);
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
    expect(report, containsPair('schema', 1));
    expect(report, containsPair('command', 'clean'));
    expect(report, containsPair('ok', false));
    expect(report, containsPair('exitCode', 1));
    expect(report, containsPair('dryRun', false));
    expect(report, containsPair('deleted', false));
    expect(report.keys, containsAll(['targets', 'error']));
    final targets = report['targets'] as List<Object?>;
    expect(targets, hasLength(1));
    final error = report['error'] as Map<String, Object?>;
    expect(error, containsPair('type', 'filesystem'));
    expect(error['message'], isA<String>());
    expect(await Directory('${task.path}/scratch').exists(), isTrue);
    expect(stderr, isEmpty);
  });

  test('reports missing current task as an error', () async {
    final environment = await createTestEnvironment();
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

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('ok', false));
    expect(report, containsPair('deleted', false));
    expect(report['error'], isA<Map<String, Object?>>());
    expect(stderr, isEmpty);
  });
}

Future<Directory> _writeTaskFixture(
  FluohEnvironment environment, {
  String id = 'test-task',
}) async {
  final task = Directory(
    '${environment.workingDirectory.path}/.fluoh/tasks/$id',
  );
  await Directory('${task.path}/scratch/logs').create(recursive: true);
  await Directory('${task.path}/scratch/signing').create(recursive: true);
  await File('${task.path}/scratch/logs/run.log').writeAsString('run log');
  await File('${task.path}/scratch/signing/debug.p7b').writeAsString('sig');
  await File('${task.path}/reports/report.md').create(recursive: true);
  await File('${task.path}/reports/report.md').writeAsString('report');
  final current = File(
    '${environment.workingDirectory.path}/.fluoh/current-task.json',
  );
  await current.parent.create(recursive: true);
  await current.writeAsString(
    jsonEncode({
      'schema': 1,
      'kind': 'fluoh.currentTask',
      'id': id,
      'path': '.fluoh/tasks/$id',
      'updatedAt': '2026-06-18T00:00:00.000',
    }),
  );
  return task;
}
