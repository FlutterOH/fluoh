import 'package:args/command_runner.dart';

import '../cli/command_usage.dart';
import '../cli/fluoh_command_runner.dart';
import '../context/fluoh_environment.dart';
import 'adapter_commands.dart';
import 'adapter_git.dart';
import 'adapter_manifest.dart';

class PubCommand extends Command<int> {
  PubCommand({
    required FluohEnvironment environment,
    required OutputWriter stdout,
  }) : _stdout = stdout {
    addSubcommand(CreateCommand(environment: environment, stdout: stdout));
    addSubcommand(PubSyncCommand(environment: environment, stdout: stdout));
    addSubcommand(PubAdaptCommand(environment: environment, stdout: stdout));
    addSubcommand(ReleaseCommand(environment: environment, stdout: stdout));
  }

  final OutputWriter _stdout;

  @override
  String get name => 'pub';

  @override
  String get description => 'Manage FlutterOH package adapter repositories.';

  @override
  String get usage => '$description\n\n$_usageWithoutDescription';

  @override
  void printUsage() {
    _stdout(usage);
  }

  @override
  Never usageException(String message) {
    throw UsageException(message, _usageWithoutDescription);
  }

  String get _usageWithoutDescription {
    return [
      'Usage: $invocation',
      argParser.usage,
      '',
      formatCommandUsage(
        subcommands,
        sections: _pubCommandSections,
        isSubcommand: true,
        lineLength: argParser.usageLineLength,
      ),
      '',
      'Run "${runner!.executableName} help" to see global options.',
    ].join('\n');
  }
}

const _pubCommandSections = [
  CommandUsageSection('', ['create', 'sync', 'adapt', 'release']),
];

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

class PubAdaptCommand extends Command<int> {
  PubAdaptCommand({required this.environment, required OutputWriter stdout})
    : _stdout = stdout;

  final FluohEnvironment environment;
  final OutputWriter _stdout;

  @override
  String get name => 'adapt';

  @override
  String get description =>
      'Merge the synchronized upstream branch into an adapter branch.';

  @override
  Future<int> run() async {
    final repository = environment.workingDirectory;
    await ensureCleanWorkingTree(repository, 'Adapt');
    final manifest = await readAdapterManifest(repository);
    final branch = await currentBranch(repository);
    if (branch != manifest.branch) {
      throw UsageException(
        'Current branch $branch does not match adapter branch '
            '${manifest.branch}.',
        '',
      );
    }

    final defaultBranch = await upstreamDefaultBranch(repository);
    await runGit(['merge', defaultBranch], workingDirectory: repository);
    _stdout('Merged $defaultBranch into $branch.');

    final upstreamRef = (await runGit([
      'rev-parse',
      defaultBranch,
    ], workingDirectory: repository)).stdout.toString().trim();
    final packagePath = manifest.upstreamPath ?? '.';
    final package = await readPackageInfo(
      packageDirectory(repository, packagePath),
    );
    await writeAdapterManifest(
      destination: repository,
      package: package,
      upstream: manifest.upstreamUrl,
      upstreamRef: upstreamRef,
      packagePath: packagePath,
      sdkVersion: manifest.sdkVersion,
      branch: manifest.branch,
      flutterOhUrl: manifest.flutterOhUrl,
      adapterVersion: manifest.adapterVersion,
      status: manifest.status ?? 'experimental',
    );
    await runGit(['add', 'fluoh.yaml'], workingDirectory: repository);
    final changed = await runGit(
      ['diff', '--cached', '--quiet', '--', 'fluoh.yaml'],
      workingDirectory: repository,
      allowFailure: true,
    );
    if (changed.exitCode != 0) {
      await runGit([
        'commit',
        '-m',
        'Update FlutterOH adapter metadata',
      ], workingDirectory: repository);
      _stdout(
        'Updated adapter manifest for ${package.name} ${package.version}.',
      );
    } else {
      _stdout(
        'Adapter manifest already matches ${package.name} ${package.version}.',
      );
    }
    return 0;
  }
}
