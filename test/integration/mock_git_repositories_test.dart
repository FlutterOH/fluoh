import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('fixture SDK repository exposes an ohos SDK Git tag', () async {
    final temp = await Directory.systemTemp.createTemp('fluoh_sdk_repo_test_');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    final repo = Directory('${temp.path}/sdk');
    await repo.create();
    await _git(repo, ['init', '--initial-branch=main']);
    await _git(repo, ['config', 'user.email', 'fixture@example.com']);
    await _git(repo, ['config', 'user.name', 'Fixture']);

    await File(
      '${repo.path}/README.md',
    ).writeAsString('# Mock Flutter OHOS SDK\n');
    await _git(repo, ['add', 'README.md']);
    await _git(repo, ['commit', '-m', 'Initial SDK fixture']);
    await _git(repo, ['tag', '3.35.8-ohos-0.0.3']);

    final tags = await _git(repo, ['tag', '--list']);

    expect(tags.stdout.toString().split('\n'), contains('3.35.8-ohos-0.0.3'));
  });
}

Future<ProcessResult> _git(Directory repo, List<String> arguments) async {
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
