import 'dart:io';

import 'package:args/command_runner.dart';

import '../../cli/argument_validation.dart';
import '../../cli/fluoh_command_runner.dart';
import '../../cli/terminal_output.dart';
import '../../context/fluoh_environment.dart';
import '../git/pub_git.dart';
import '../manifest/pub_manifest.dart';
import '../manifest/pubspec_package.dart';

class PubSyncCommand extends Command<int> {
  PubSyncCommand({
    required this.environment,
    required OutputWriter stdout,
    TerminalOutput? output,
  }) : _output = output ?? TerminalOutput(stdout: stdout) {
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
  final TerminalOutput _output;

  @override
  String get name => 'sync';

  @override
  String get description =>
      'Synchronize upstream and merge it into the current OHOS pub branch.';

  @override
  Future<int> run() async {
    expectNoArguments(argResults!, usageException);
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
      _output.warning('Aborted pub sync merge.');
      return 0;
    }
    if (shouldContinue) {
      return _continueSync(repository);
    }

    await ensureCleanWorkingTree(repository, 'Sync');
    final manifest = await readPubManifest(repository);
    final startingBranch = await currentBranch(repository);
    _ensurePubBranch(startingBranch, manifest);
    await _output.withProgress(
      'Fetching upstream.',
      () => runGit(['fetch', 'upstream'], workingDirectory: repository),
    );
    final defaultBranch = manifest.upstreamBranch;
    var switchedBranches = false;
    try {
      _output.step('Checking out $defaultBranch.');
      await runGit(['checkout', defaultBranch], workingDirectory: repository);
      switchedBranches = true;
      await runGit([
        'merge',
        '--ff-only',
        'upstream/$defaultBranch',
      ], workingDirectory: repository);
      _output.success(
        'Synchronized $defaultBranch from upstream/$defaultBranch.',
      );
    } finally {
      if (switchedBranches &&
          startingBranch.isNotEmpty &&
          startingBranch != defaultBranch) {
        _output.step('Checking out $startingBranch.');
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

    final defaultBranch = manifest.upstreamBranch;
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
      _output.success('Merged $defaultBranch into $pubBranch.');
    } else {
      _output.skipped('Pub branch $pubBranch already contains $defaultBranch.');
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
    final packageVersions = <String, String>{};
    for (final packageManifest in manifest.packages) {
      final upstreamPath = packageManifest.upstreamPath;
      final package = await readPubspecPackage(
        packageDirectory(repository, upstreamPath),
      );
      if (package.name != packageManifest.name) {
        throw UsageException(
          'Package path $upstreamPath contains ${package.name}, expected '
              '${packageManifest.name}. Update fluoh.yaml before syncing.',
          '',
        );
      }
      packageVersions[package.name] = package.version;
    }
    await updatePubManifestUpstream(
      destination: repository,
      packageVersions: packageVersions,
    );
    await runGit(['add', 'fluoh.yaml'], workingDirectory: repository);
    final mergeInProgress = await _isMergeInProgress(repository);
    final changed = await runGit(
      ['diff', '--cached', '--quiet'],
      workingDirectory: repository,
      allowFailure: true,
    );
    if (!mergeInProgress && changed.exitCode == 0) {
      _output.skipped(
        'Pub branch $pubBranch already matches upstream metadata.',
      );
      return 0;
    }

    await runGit([
      'commit',
      '-m',
      'Sync upstream packages',
    ], workingDirectory: repository);
    _output.success('Updated upstream metadata for registered packages.');
    _output.next(
      'Complete the OHOS implementation, then update package.version and '
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
    if (branch != manifest.branch) {
      throw UsageException(
        'Current branch $branch does not match pub branch ${manifest.branch}.',
        '',
      );
    }
  }
}
