import 'package:args/command_runner.dart';

import '../../cli/fluoh_command_runner.dart';
import '../../context/fluoh_environment.dart';
import '../git/pub_git.dart';
import '../manifest/pub_manifest.dart';
import '../manifest/pubspec_package.dart';

class PubAdaptCommand extends Command<int> {
  PubAdaptCommand({required this.environment, required OutputWriter stdout})
    : _stdout = stdout;

  final FluohEnvironment environment;
  final OutputWriter _stdout;

  @override
  String get name => 'adapt';

  @override
  String get description =>
      'Merge the synchronized upstream branch into an OHOS pub branch.';

  @override
  Future<int> run() async {
    final repository = environment.workingDirectory;
    await ensureCleanWorkingTree(repository, 'Adapt');
    final manifest = await readPubManifest(repository);
    final branch = await currentBranch(repository);
    if (branch != manifest.branch) {
      throw UsageException(
        'Current branch $branch does not match pub branch '
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
    final upstreamPath = manifest.upstreamPath ?? '.';
    final dependencyPath = manifest.dependencyPath;
    final package = await readPubspecPackage(
      packageDirectory(repository, upstreamPath),
    );
    await writePubManifest(
      destination: repository,
      package: package,
      upstream: manifest.upstreamUrl,
      upstreamRef: upstreamRef,
      packagePath: dependencyPath ?? '.',
      dependencyPath: dependencyPath,
      upstreamPath: upstreamPath,
      sdkVersion: manifest.sdkVersion,
      branch: manifest.branch,
      adapterUrl: manifest.adapterUrl,
      releaseVersion: manifest.releaseVersion,
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
        'Update FlutterOH pub metadata',
      ], workingDirectory: repository);
      _stdout('Updated pub manifest for ${package.name} ${package.version}.');
    } else {
      _stdout(
        'Pub manifest already matches ${package.name} ${package.version}.',
      );
    }
    return 0;
  }
}
