import 'dart:convert';
import 'dart:io';

import 'package:fluoh/fluoh.dart';
import 'package:test/test.dart';

import '../helpers/fluoh_command_context.dart';

void main() {
  test('task start creates unique task ids and updates current', () async {
    final environment = await createTestEnvironment();
    final stdout = <String>[];
    final stderr = <String>[];

    Future<Map<String, Object?>> startTask() async {
      stdout.clear();
      stderr.clear();
      expect(
        await runFluoh(
          [
            'task',
            'start',
            '--type',
            'packageSupport',
            '--scope',
            'camera',
            '--package',
            'camera',
            '--json',
          ],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );
      expect(stderr, isEmpty);
      return jsonDecode(stdout.single) as Map<String, Object?>;
    }

    final first = await startTask();
    final second = await startTask();
    final firstTask = first['task'] as Map<String, Object?>;
    final secondTask = second['task'] as Map<String, Object?>;

    expect(firstTask['id'], isNot(secondTask['id']));
    expect(await Directory(firstTask['path']! as String).exists(), isTrue);
    expect(await Directory(secondTask['path']! as String).exists(), isTrue);

    stdout.clear();
    stderr.clear();
    expect(
      await runFluoh(
        ['task', 'current', '--json'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );
    final current = jsonDecode(stdout.single) as Map<String, Object?>;
    final currentTask = current['task'] as Map<String, Object?>;
    expect(currentTask['id'], secondTask['id']);
  });

  test(
    'task clean removes the current pointer when deleting current task',
    () async {
      final environment = await createTestEnvironment();
      final stdout = <String>[];
      final stderr = <String>[];

      expect(
        await runFluoh(
          ['task', 'start', '--scope', 'camera', '--json'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );
      final started = jsonDecode(stdout.single) as Map<String, Object?>;
      final task = started['task'] as Map<String, Object?>;
      final taskDirectory = Directory(task['path']! as String);
      expect(await taskDirectory.exists(), isTrue);
      stdout.clear();

      expect(
        await runFluoh(
          ['task', 'clean', '--json'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final clean = jsonDecode(stdout.single) as Map<String, Object?>;
      expect(clean, containsPair('deleted', true));
      expect(await taskDirectory.exists(), isFalse);
      expect(
        await File(
          '${environment.workingDirectory.path}/.fluoh/current-task.json',
        ).exists(),
        isFalse,
      );
      expect(stderr, isEmpty);
    },
  );

  test('task clean all is a no-op when no task workspaces exist', () async {
    final environment = await createTestEnvironment();
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['task', 'clean', '--all', '--json'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final clean = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(clean, containsPair('ok', true));
    expect(clean, containsPair('deleted', false));
    expect(clean['tasks'], isEmpty);
    expect(stderr, isEmpty);
  });
}
