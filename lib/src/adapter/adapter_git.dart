import 'dart:io';

import 'package:args/command_runner.dart';

Future<ProcessResult> runGit(
  List<String> arguments, {
  Directory? workingDirectory,
  bool allowFailure = false,
}) async {
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: workingDirectory?.path,
  );
  if (!allowFailure && result.exitCode != 0) {
    throw UsageException(
      'git ${arguments.join(' ')} failed:\n${result.stderr}',
      '',
    );
  }
  return result;
}

Future<String> currentBranch(Directory repository) async {
  return (await runGit([
    'branch',
    '--show-current',
  ], workingDirectory: repository)).stdout.toString().trim();
}

Future<String> currentHead(Directory repository) async {
  return (await runGit([
    'rev-parse',
    'HEAD',
  ], workingDirectory: repository)).stdout.toString().trim();
}

Future<void> ensureCleanWorkingTree(Directory repository, String action) async {
  final status = (await runGit([
    'status',
    '--porcelain',
  ], workingDirectory: repository)).stdout.toString().trim();
  if (status.isNotEmpty) {
    throw UsageException('$action requires a clean working tree.', '');
  }
}

Future<void> configureAdapterRemotes(
  Directory repository,
  String repositoryUrl,
) async {
  final existingOrigin = await runGit(
    ['remote', 'get-url', 'origin'],
    workingDirectory: repository,
    allowFailure: true,
  );
  if (existingOrigin.exitCode == 0 &&
      existingOrigin.stdout.toString().trim().isNotEmpty) {
    await runGit([
      'remote',
      'rename',
      'origin',
      'upstream',
    ], workingDirectory: repository);
  }
  await runGit([
    'remote',
    'add',
    'origin',
    repositoryUrl,
  ], workingDirectory: repository);
}

Future<void> ensureGitIdentity(Directory repository) async {
  final email = await runGit(
    ['config', '--get', 'user.email'],
    workingDirectory: repository,
    allowFailure: true,
  );
  if (email.exitCode != 0 || email.stdout.toString().trim().isEmpty) {
    await runGit([
      'config',
      'user.email',
      'fluoh@example.invalid',
    ], workingDirectory: repository);
  }

  final name = await runGit(
    ['config', '--get', 'user.name'],
    workingDirectory: repository,
    allowFailure: true,
  );
  if (name.exitCode != 0 || name.stdout.toString().trim().isEmpty) {
    await runGit([
      'config',
      'user.name',
      'fluoh',
    ], workingDirectory: repository);
  }
}

Future<String> upstreamDefaultBranch(Directory repository) async {
  await runGit(
    ['remote', 'set-head', 'upstream', '--auto'],
    workingDirectory: repository,
    allowFailure: true,
  );
  final head = await runGit(
    ['symbolic-ref', '--short', 'refs/remotes/upstream/HEAD'],
    workingDirectory: repository,
    allowFailure: true,
  );
  final ref = head.stdout.toString().trim();
  if (head.exitCode == 0 && ref.startsWith('upstream/')) {
    return ref.substring('upstream/'.length);
  }
  final main = await runGit(
    ['rev-parse', '--verify', 'upstream/main'],
    workingDirectory: repository,
    allowFailure: true,
  );
  if (main.exitCode == 0) {
    return 'main';
  }
  final master = await runGit(
    ['rev-parse', '--verify', 'upstream/master'],
    workingDirectory: repository,
    allowFailure: true,
  );
  if (master.exitCode == 0) {
    return 'master';
  }
  throw UsageException('Could not determine upstream default branch.', '');
}
