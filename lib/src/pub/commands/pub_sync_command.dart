import 'package:args/command_runner.dart';

import '../../cli/fluoh_command_runner.dart';
import '../../context/fluoh_environment.dart';
import '../git/pub_git.dart';

class PubSyncCommand extends Command<int> {
  PubSyncCommand({required this.environment, required OutputWriter stdout})
    : _stdout = stdout;

  final FluohEnvironment environment;
  final OutputWriter _stdout;

  @override
  String get name => 'sync';

  @override
  String get description => 'Synchronize the local upstream branch.';

  @override
  Future<int> run() async {
    final repository = environment.workingDirectory;
    await ensureCleanWorkingTree(repository, 'Sync');
    final startingBranch = await currentBranch(repository);
    await runGit(['fetch', 'upstream'], workingDirectory: repository);
    final defaultBranch = await upstreamDefaultBranch(repository);
    var switchedBranches = false;
    try {
      await runGit(['checkout', defaultBranch], workingDirectory: repository);
      switchedBranches = true;
      await runGit([
        'merge',
        '--ff-only',
        'upstream/$defaultBranch',
      ], workingDirectory: repository);
    } finally {
      if (switchedBranches &&
          startingBranch.isNotEmpty &&
          startingBranch != defaultBranch) {
        await runGit([
          'checkout',
          startingBranch,
        ], workingDirectory: repository);
      }
    }
    _stdout('Synchronized $defaultBranch from upstream/$defaultBranch.');
    return 0;
  }
}
