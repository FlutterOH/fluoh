import 'dart:io';

import 'package:args/command_runner.dart';

import '../../cli/fluoh_command_runner.dart';
import '../../context/fluoh_environment.dart';
import '../git/pub_git.dart';
import '../manifest/pub_manifest.dart';
import '../manifest/pubspec_package.dart';

class PubSyncCommand extends Command<int> {
  PubSyncCommand({required this.environment, required OutputWriter stdout})
    : _stdout = stdout {
    argParser
      ..addFlag(
        'continue',
        negatable: false,
        help: 'Continue after resolving sync merge conflicts.',
      )
      ..addFlag(
        'abort',
        negatable: false,
        help: 'Abort an in-progress sync merge.',
      );
  }

  final FluohEnvironment environment;
  final OutputWriter _stdout;

  @override
  String get name => 'sync';

  @override
  String get description =>
      'Synchronize upstream and merge it into the current OHOS pub branch.';

  @override
  Future<int> run() async {
    final repository = environment.workingDirectory;
    final shouldContinue = argResults!.flag('continue');
    final shouldAbort = argResults!.flag('abort');
    if (shouldContinue && shouldAbort) {
      usageException('Use only one of --continue or --abort.');
    }
    if (shouldAbort) {
      if (!await _isMergeInProgress(repository)) {
        throw UsageException('No pub sync merge is in progress.', '');
      }
      final manifest = await readPubManifest(repository);
      final branch = await currentBranch(repository);
      _ensurePubBranch(branch, manifest);
      await runGit(['merge', '--abort'], workingDirectory: repository);
      _stdout('Aborted pub sync merge.');
      return 0;
    }
    if (shouldContinue) {
      return _continueSync(repository);
    }

    await ensureCleanWorkingTree(repository, 'Sync');
    final manifest = await readPubManifest(repository);
    final startingBranch = await currentBranch(repository);
    _ensurePubBranch(startingBranch, manifest);
    await runGit(['fetch', 'upstream'], workingDirectory: repository);
    final defaultBranch = await upstreamDefaultBranch(repository);
    var switchedBranches = false;
    try {
      _stdout('Checking out $defaultBranch.');
      await runGit(['checkout', defaultBranch], workingDirectory: repository);
      switchedBranches = true;
      await runGit([
        'merge',
        '--ff-only',
        'upstream/$defaultBranch',
      ], workingDirectory: repository);
      _stdout('Synchronized $defaultBranch from upstream/$defaultBranch.');
    } finally {
      if (switchedBranches &&
          startingBranch.isNotEmpty &&
          startingBranch != defaultBranch) {
        _stdout('Checking out $startingBranch.');
        await runGit([
          'checkout',
          startingBranch,
        ], workingDirectory: repository);
      }
    }
    return _mergeUpstreamBranch(
      repository: repository,
      manifest: manifest,
      defaultBranch: defaultBranch,
      pubBranch: startingBranch,
    );
  }

  Future<int> _continueSync(Directory repository) async {
    if (!await _isMergeInProgress(repository)) {
      throw UsageException('No pub sync merge is in progress.', '');
    }
    final manifest = await readPubManifest(repository);
    final branch = await currentBranch(repository);
    _ensurePubBranch(branch, manifest);
    final unresolved = (await runGit([
      'diff',
      '--name-only',
      '--diff-filter=U',
    ], workingDirectory: repository)).stdout.toString().trim();
    if (unresolved.isNotEmpty) {
      throw UsageException(
        'Resolve and stage merge conflicts before running '
            '"fluoh pub sync --continue".',
        '',
      );
    }

    final defaultBranch = await upstreamDefaultBranch(repository);
    return _updateManifestAndCommit(
      repository: repository,
      manifest: manifest,
      defaultBranch: defaultBranch,
      pubBranch: branch,
    );
  }

  Future<int> _mergeUpstreamBranch({
    required Directory repository,
    required PubManifest manifest,
    required String defaultBranch,
    required String pubBranch,
  }) async {
    final merge = await runGit(
      ['merge', '--no-ff', '--no-commit', defaultBranch],
      workingDirectory: repository,
      allowFailure: true,
    );
    if (merge.exitCode != 0) {
      throw UsageException(
        'git merge --no-ff --no-commit $defaultBranch failed:\n'
            '${merge.stderr}\n'
            'Resolve conflicts, stage the resolved files, and run '
            '"fluoh pub sync --continue", or run "fluoh pub sync --abort".',
        '',
      );
    }
    if (await _isMergeInProgress(repository)) {
      _stdout('Merged $defaultBranch into $pubBranch.');
    } else {
      _stdout('Pub branch $pubBranch already contains $defaultBranch.');
    }

    return _updateManifestAndCommit(
      repository: repository,
      manifest: manifest,
      defaultBranch: defaultBranch,
      pubBranch: pubBranch,
    );
  }

  Future<int> _updateManifestAndCommit({
    required Directory repository,
    required PubManifest manifest,
    required String defaultBranch,
    required String pubBranch,
  }) async {
    final upstreamRef = (await runGit([
      'rev-parse',
      defaultBranch,
    ], workingDirectory: repository)).stdout.toString().trim();
    final upstreamPath = manifest.upstreamPath ?? '.';
    final package = await readPubspecPackage(
      packageDirectory(repository, upstreamPath),
    );
    await updatePubManifestUpstream(
      destination: repository,
      upstreamVersion: package.version,
      upstreamRef: upstreamRef,
    );
    await runGit(['add', 'fluoh.yaml'], workingDirectory: repository);
    final mergeInProgress = await _isMergeInProgress(repository);
    final changed = await runGit(
      ['diff', '--cached', '--quiet'],
      workingDirectory: repository,
      allowFailure: true,
    );
    if (!mergeInProgress && changed.exitCode == 0) {
      _stdout(
        'Pub branch $pubBranch already matches ${package.name} '
        '${package.version}.',
      );
      return 0;
    }

    await runGit([
      'commit',
      '-m',
      'Sync upstream ${package.name} ${package.version}',
    ], workingDirectory: repository);
    _stdout(
      'Updated upstream metadata for ${package.name} ${package.version}.',
    );
    _stdout(
      'Complete OHOS adaptation, then update package.version and '
      'FLUOH_CHANGELOG.md before release.',
    );
    return 0;
  }

  Future<bool> _isMergeInProgress(Directory repository) async {
    final mergeHeadPath = (await runGit([
      'rev-parse',
      '--git-path',
      'MERGE_HEAD',
    ], workingDirectory: repository)).stdout.toString().trim();
    final mergeHead = File(mergeHeadPath);
    if (mergeHead.isAbsolute) {
      return mergeHead.exists();
    }
    return File('${repository.path}/$mergeHeadPath').exists();
  }

  void _ensurePubBranch(String branch, PubManifest manifest) {
    if (!branch.startsWith('ohos/')) {
      throw UsageException('Sync must run from an ohos/* pub branch.', '');
    }
    if (branch != manifest.branch) {
      throw UsageException(
        'Current branch $branch does not match pub branch ${manifest.branch}.',
        '',
      );
    }
  }
}
