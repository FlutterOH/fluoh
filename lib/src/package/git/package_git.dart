import 'dart:io';

import 'package:args/command_runner.dart';

/// Git author identity used for generated package repositories.
class PackageGitAuthor {
  /// Creates a package Git author identity.
  const PackageGitAuthor({required this.name, required this.email});

  /// Git user.name value.
  final String name;

  /// Git user.email value.
  final String email;
}

/// Runs Git and throws [UsageException] on failure unless allowed.
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

/// Returns the current branch name for [repository].
Future<String> currentBranch(Directory repository) async {
  return (await runGit([
    'branch',
    '--show-current',
  ], workingDirectory: repository)).stdout.toString().trim();
}

/// Returns the current HEAD commit for [repository].
Future<String> currentHead(Directory repository) async {
  return (await runGit([
    'rev-parse',
    'HEAD',
  ], workingDirectory: repository)).stdout.toString().trim();
}

/// Ensures [repository] has no uncommitted changes.
Future<void> ensureCleanWorkingTree(Directory repository, String action) async {
  final status = (await runGit([
    'status',
    '--porcelain',
  ], workingDirectory: repository)).stdout.toString().trim();
  if (status.isNotEmpty) {
    throw UsageException('$action requires a clean working tree.', '');
  }
}

/// Converts the existing origin remote to upstream and adds a new origin.
Future<void> configurePackageRemotes(
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

/// Ensures the `upstream` remote points to [upstreamUrl].
Future<void> ensureUpstreamRemote(
  Directory repository,
  String upstreamUrl,
) async {
  final existing = await runGit(
    ['remote', 'get-url', 'upstream'],
    workingDirectory: repository,
    allowFailure: true,
  );
  final existingUrl = existing.stdout.toString().trim();
  if (existing.exitCode == 0 && existingUrl == upstreamUrl) {
    return;
  }
  if (existing.exitCode == 0) {
    await runGit([
      'remote',
      'set-url',
      'upstream',
      upstreamUrl,
    ], workingDirectory: repository);
    return;
  }
  await runGit([
    'remote',
    'add',
    'upstream',
    upstreamUrl,
  ], workingDirectory: repository);
}

/// Writes local Git author config for package adaptation commits.
Future<void> configurePackageGitAuthor(
  Directory repository,
  PackageGitAuthor author,
) async {
  await runGit([
    'config',
    '--local',
    'user.name',
    author.name,
  ], workingDirectory: repository);
  await runGit([
    'config',
    '--local',
    'user.email',
    author.email,
  ], workingDirectory: repository);
}

/// Resolves the upstream remote's default branch.
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
