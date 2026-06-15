import 'dart:io';

import 'package:fluoh/src/workflow/workflow_tool_discovery.dart';
import 'package:test/test.dart';

void main() {
  test(
    'PATH lookup skips non-executable POSIX candidates',
    () async {
      final root = await Directory.systemTemp.createTemp('fluoh_tools_');
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      final first = Directory('${root.path}/first');
      final second = Directory('${root.path}/second');
      await first.create(recursive: true);
      await second.create(recursive: true);
      final stale = File('${first.path}/adb');
      await stale.writeAsString('#!/bin/sh\nexit 1\n');
      await _chmod(stale, '-x');
      final valid = File('${second.path}/adb');
      await valid.writeAsString('#!/bin/sh\nexit 0\n');
      await _chmod(valid, '+x');

      final executable = await findWorkflowExecutableOnPath('adb', {
        'PATH': '${first.path}:${second.path}',
      });

      expect(executable?.path, valid.path);
    },
    skip: Platform.isWindows ? 'POSIX executable bits only' : false,
  );
}

Future<void> _chmod(File file, String mode) async {
  final result = await Process.run('chmod', [mode, file.path]);
  expect(result.exitCode, 0, reason: result.stderr.toString());
}
