import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:pub_semver/pub_semver.dart';

import '../../cli/argument_validation.dart';
import '../../cli/fluoh_command_runner.dart';
import '../../cli/machine_output.dart';
import '../../cli/terminal_output.dart';
import '../../context/fluoh_environment.dart';
import '../git/package_git.dart';
import '../manifest/package_manifest.dart';
import '../manifest/pubspec_package.dart';
import '../upstream_package_ref.dart';

/// Synchronizes upstream changes into a package adaptation branch.
class PackageSyncCommand extends FluohCommand<int> {
  /// Creates the package sync command.
  PackageSyncCommand({
    required this.environment,
    required this.stdout,
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
      )
      ..addFlag(
        'json',
        negatable: false,
        help: 'Print the sync result as JSON.',
      )
      ..addOption(
        'upstream-version',
        valueHelp: 'version',
        help:
            'Upstream package version to merge. Must not be older than the '
            'current package branch upstream version. Defaults to the latest '
            'valid package release tag.',
      )
      ..addOption(
        'upstream-ref',
        valueHelp: 'ref',
        help:
            'Upstream Git ref to merge. Use only when release tags cannot '
            'identify the target package version.',
      );
  }

  /// Runtime environment for repository and process operations.
  final FluohEnvironment environment;

  /// Writer used for JSON output.
  final OutputWriter stdout;
  final TerminalOutput _output;

  @override
  String get name => 'sync';

  @override
  String get description =>
      'Synchronize upstream and merge it into the current OHOS package branch.';

  @override
  Future<int> run() async {
    expectNoArguments(argResults!, usageException);
    final repository = environment.workingDirectory;
    final shouldContinue = argResults!.flag('continue');
    final shouldAbort = argResults!.flag('abort');
    final json = argResults!.flag('json');
    final upstreamTarget = _upstreamTargetFromOptions(argResults!);
    final actions = <String>[];
    if (shouldContinue && shouldAbort) {
      usageException('Use only one of --continue or --abort.');
    }
    if (shouldAbort) {
      if (!await _isMergeInProgress(repository)) {
        throw UsageException('No package sync merge is in progress.', '');
      }
      final manifest = await readPackageManifest(repository);
      final branch = await currentBranch(repository);
      _ensurePackageBranch(branch, manifest);
      await runGit(['merge', '--abort'], workingDirectory: repository);
      actions.add('aborted merge');
      if (json) {
        _writeJson({'status': 'aborted', 'actions': actions});
      } else {
        _output.warning('Aborted package sync merge');
      }
      return 0;
    }
    if (shouldContinue) {
      return _continueSync(
        repository,
        target: upstreamTarget,
        json: json,
        actions: actions,
      );
    }

    await ensureCleanWorkingTree(repository, 'Sync');
    final manifest = await readPackageManifest(repository);
    final startingBranch = await currentBranch(repository);
    _ensurePackageBranch(startingBranch, manifest);
    if (json) {
      final fetch = await runGit(
        ['fetch', '--tags', 'upstream'],
        workingDirectory: repository,
        allowFailure: true,
      );
      if (fetch.exitCode != 0) {
        return _writeJsonFailure(
          status: 'fetch_failed',
          code: 'sync.fetch_failed',
          message:
              'Could not fetch upstream. Verify network access to the '
              'upstream repository, then retry.',
          nextCommand: 'fluoh package sync --json',
          result: fetch,
        );
      }
    } else {
      await _output.withProgress(
        'Fetching upstream',
        () => fetchUpstreamRefs(repository),
      );
    }
    actions.add('fetched upstream');
    final defaultBranch = manifest.upstreamBranch;
    var switchedBranches = false;
    late final ResolvedPackageUpstreamRef resolvedTarget;
    try {
      if (!json) {
        _output.step('Checking out $defaultBranch');
      }
      switchedBranches = true;
      await synchronizeUpstreamBranch(repository, branch: defaultBranch);
      actions.add('synchronized $defaultBranch from upstream/$defaultBranch');
      if (!json) {
        _output.success(
          'Synchronized $defaultBranch from upstream/$defaultBranch',
        );
      }
      resolvedTarget = await resolvePackageUpstreamRef(
        repository: repository,
        packageName: manifest.package.name,
        packagePath: manifest.package.path,
        fallbackRef: defaultBranch,
        target: upstreamTarget,
      );
      _ensureNonDowngradeSyncTarget(manifest, resolvedTarget);
    } finally {
      if (switchedBranches &&
          startingBranch.isNotEmpty &&
          startingBranch != defaultBranch) {
        if (!json) {
          _output.step('Checking out $startingBranch');
        }
        await runGit([
          'checkout',
          startingBranch,
        ], workingDirectory: repository);
        actions.add('checked out $startingBranch');
      }
    }
    return _mergeUpstreamBranch(
      repository: repository,
      manifest: manifest,
      defaultBranch: defaultBranch,
      packageBranch: startingBranch,
      upstreamTarget: resolvedTarget,
      json: json,
      actions: actions,
    );
  }

  Future<int> _continueSync(
    Directory repository, {
    required PackageUpstreamTarget target,
    required bool json,
    required List<String> actions,
  }) async {
    if (!await _isMergeInProgress(repository)) {
      throw UsageException('No package sync merge is in progress.', '');
    }
    final manifest = await readPackageManifest(repository);
    final branch = await currentBranch(repository);
    _ensurePackageBranch(branch, manifest);
    final unresolved = (await runGit([
      'diff',
      '--name-only',
      '--diff-filter=U',
    ], workingDirectory: repository)).stdout.toString().trim();
    if (unresolved.isNotEmpty) {
      throw UsageException(
        'Resolve and stage merge conflicts before running '
            '"fluoh package sync --continue".',
        '',
      );
    }

    final defaultBranch = manifest.upstreamBranch;
    final upstreamTarget = target.isExplicit
        ? await resolvePackageUpstreamRef(
            repository: repository,
            packageName: manifest.package.name,
            packagePath: manifest.package.path,
            fallbackRef: defaultBranch,
            target: target,
          )
        : await _resolvedMergeHeadTarget(repository, manifest);
    if (target.isExplicit) {
      await _ensureExplicitContinueTargetMatchesMergeHead(
        repository,
        upstreamTarget,
      );
    }
    _ensureNonDowngradeSyncTarget(manifest, upstreamTarget);
    return _updateManifestAndCommit(
      repository: repository,
      manifest: manifest,
      defaultBranch: defaultBranch,
      packageBranch: branch,
      upstreamTarget: upstreamTarget,
      json: json,
      actions: actions,
    );
  }

  Future<int> _mergeUpstreamBranch({
    required Directory repository,
    required PackageManifest manifest,
    required String defaultBranch,
    required String packageBranch,
    required ResolvedPackageUpstreamRef upstreamTarget,
    required bool json,
    required List<String> actions,
  }) async {
    final mergeRef = upstreamTarget.ref ?? defaultBranch;
    if (_manifestMatchesUpstreamTarget(manifest, upstreamTarget) &&
        await _branchContainsCommit(
          repository,
          branch: packageBranch,
          commit: upstreamTarget.commit,
        )) {
      actions.add(
        '$packageBranch already adapts ${upstreamTarget.package.version}',
      );
      if (json) {
        _writeJson({
          'status': 'unchanged',
          'packageBranch': packageBranch,
          'upstreamBranch': defaultBranch,
          'upstreamVersion': upstreamTarget.package.version,
          if (upstreamTarget.ref != null) 'upstreamRef': upstreamTarget.ref,
          'actions': actions,
          'committed': false,
        });
      } else {
        _output.skipped(
          'Package branch $packageBranch already adapts upstream '
          '${upstreamTarget.package.version} ($mergeRef)',
        );
      }
      return 0;
    }
    final merge = await runGit(
      ['merge', '--no-ff', '--no-commit', upstreamTarget.commit],
      workingDirectory: repository,
      allowFailure: true,
    );
    if (merge.exitCode != 0) {
      final conflictedFiles = await _conflictedFiles(repository);
      if (json) {
        if (conflictedFiles.isNotEmpty) {
          return _writeJsonFailure(
            status: 'merge_conflict',
            code: 'sync.merge_conflict',
            message:
                'Upstream merge produced file conflicts. Resolve conflicts, '
                'stage files, then run "fluoh package sync --continue".',
            nextCommand: 'fluoh package sync --continue',
            result: merge,
            details: {'conflictedFiles': conflictedFiles},
          );
        }
        return _writeJsonFailure(
          status: 'merge_failed',
          code: 'sync.merge_failed',
          message:
              'Upstream merge failed before producing resolvable conflicts. '
              'Inspect git output, fix the repository state, then retry.',
          nextCommand: 'fluoh package sync --json',
          result: merge,
        );
      }
      if (conflictedFiles.isEmpty) {
        throw UsageException(
          'git merge --no-ff --no-commit $mergeRef failed:\n'
              '${merge.stderr}',
          '',
        );
      }
      throw UsageException(
        'git merge --no-ff --no-commit $mergeRef failed:\n'
            '${merge.stderr}\n'
            'Resolve conflicts, stage the resolved files, and run '
            '"fluoh package sync --continue", or run "fluoh package sync --abort".',
        '',
      );
    }
    if (await _isMergeInProgress(repository)) {
      actions.add('merged $mergeRef into $packageBranch');
      if (!json) {
        _output.success('Merged $mergeRef into $packageBranch');
      }
    } else {
      actions.add('$packageBranch already contains $mergeRef');
      if (!json) {
        _output.skipped(
          'Package branch $packageBranch already contains $mergeRef',
        );
      }
    }

    return _updateManifestAndCommit(
      repository: repository,
      manifest: manifest,
      defaultBranch: defaultBranch,
      packageBranch: packageBranch,
      upstreamTarget: upstreamTarget,
      json: json,
      actions: actions,
    );
  }

  Future<int> _updateManifestAndCommit({
    required Directory repository,
    required PackageManifest manifest,
    required String defaultBranch,
    required String packageBranch,
    required ResolvedPackageUpstreamRef upstreamTarget,
    required bool json,
    required List<String> actions,
  }) async {
    final packageVersions = <String, String>{};
    final packageManifest = manifest.package;
    final packagePath = packageManifest.path;
    final package = await readPubspecPackage(
      packageDirectory(repository, packagePath),
    );
    if (package.name != packageManifest.name) {
      throw UsageException(
        'Package path $packagePath contains ${package.name}, expected '
            '${packageManifest.name}. Update fluoh.yaml before syncing.',
        '',
      );
    }
    if (package.version != upstreamTarget.package.version) {
      throw UsageException(
        'Resolved package version ${package.version} does not match selected '
            'upstream version ${upstreamTarget.package.version}. Re-apply the '
            'upstream pubspec version before running '
            '"fluoh package sync --continue".',
        '',
      );
    }
    packageVersions[package.name] = package.version;
    await updatePackageManifestUpstream(
      destination: repository,
      packageVersions: packageVersions,
      upstreamRef: upstreamTarget.ref,
      upstreamCommit: upstreamTarget.commit,
      clearUpstreamRef: upstreamTarget.ref == null,
    );
    await runGit(['add', 'fluoh.yaml'], workingDirectory: repository);
    final mergeInProgress = await _isMergeInProgress(repository);
    final changed = await runGit(
      ['diff', '--cached', '--quiet'],
      workingDirectory: repository,
      allowFailure: true,
    );
    if (!mergeInProgress && changed.exitCode == 0) {
      actions.add('$packageBranch already matches upstream metadata');
      if (json) {
        _writeJson({
          'status': 'unchanged',
          'packageBranch': packageBranch,
          'upstreamBranch': defaultBranch,
          'actions': actions,
          'committed': false,
        });
      } else {
        _output.skipped(
          'Package branch $packageBranch already matches upstream metadata',
        );
      }
      return 0;
    }

    await runGit([
      'commit',
      '-m',
      'Sync upstream package',
    ], workingDirectory: repository);
    actions.add('committed Sync upstream package');
    if (json) {
      _writeJson({
        'status': 'synced',
        'packageBranch': packageBranch,
        'upstreamBranch': defaultBranch,
        'actions': actions,
        'committed': true,
      });
    } else {
      _output.success('Updated upstream metadata for package branch');
      _output.next(
        'Complete the OHOS implementation, then update package.version and '
        'FLUOH_CHANGELOG.md before release.',
      );
    }
    return 0;
  }

  void _writeJson(Map<String, Object?> value) {
    writeMachineOutput(
      stdout,
      command: 'package sync',
      ok: true,
      exitCode: 0,
      fields: value,
    );
  }

  int _writeJsonFailure({
    required String status,
    required String code,
    required String message,
    required String nextCommand,
    ProcessResult? result,
    Map<String, Object?> details = const {},
  }) {
    writeMachineOutput(
      stdout,
      command: 'package sync',
      ok: false,
      exitCode: 1,
      fields: {
        'status': status,
        'diagnostics': [
          {
            'code': code,
            'message': message,
            'nextCommand': nextCommand,
            ...details,
            if (result != null) ..._processOutputFields(result),
          },
        ],
      },
    );
    return 1;
  }

  Future<List<String>> _conflictedFiles(Directory repository) async {
    final result = await runGit(
      ['diff', '--name-only', '--diff-filter=U'],
      workingDirectory: repository,
      allowFailure: true,
    );
    return result.stdout
        .toString()
        .trim()
        .split('\n')
        .where((line) => line.isNotEmpty)
        .toList();
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

  void _ensurePackageBranch(String branch, PackageManifest manifest) {
    if (branch != manifest.branch) {
      throw UsageException(
        'Current branch $branch does not match package branch ${manifest.branch}.',
        '',
      );
    }
  }
}

Future<String> _revParseCommit(Directory repository, String ref) async {
  final result = await runGit([
    'rev-parse',
    '$ref^{commit}',
  ], workingDirectory: repository);
  return result.stdout.toString().trim();
}

Future<void> _ensureExplicitContinueTargetMatchesMergeHead(
  Directory repository,
  ResolvedPackageUpstreamRef target,
) async {
  final mergeHead = await _revParseCommit(repository, 'MERGE_HEAD');
  if (mergeHead == target.commit) {
    return;
  }
  final selectedRef = target.ref ?? target.commit;
  throw UsageException(
    'Selected upstream target $selectedRef (${target.commit}) does not match '
        'the in-progress merge $mergeHead. Re-run '
        '"fluoh package sync --continue" with the same upstream target used '
        'for the interrupted sync, or abort with '
        '"fluoh package sync --abort".',
    '',
  );
}

void _ensureNonDowngradeSyncTarget(
  PackageManifest manifest,
  ResolvedPackageUpstreamRef target,
) {
  final current = Version.parse(manifest.package.upstreamVersion);
  final selected = Version.parse(target.package.version);
  if (selected.compareTo(current) >= 0) {
    return;
  }
  throw UsageException(
    'package sync does not downgrade ${manifest.package.name} upstream '
        'version ${manifest.package.upstreamVersion} -> '
        '${target.package.version}. If ${manifest.package.upstreamVersion} '
        'should not be used, mark this adaptation as broken with '
        '"fluoh package version --status broken".',
    '',
  );
}

bool _manifestMatchesUpstreamTarget(
  PackageManifest manifest,
  ResolvedPackageUpstreamRef target,
) {
  return manifest.package.upstreamVersion == target.package.version &&
      manifest.package.upstreamRef == target.ref &&
      manifest.package.upstreamCommit == target.commit;
}

Future<bool> _branchContainsCommit(
  Directory repository, {
  required String branch,
  required String commit,
}) async {
  final result = await runGit(
    ['merge-base', '--is-ancestor', commit, branch],
    workingDirectory: repository,
    allowFailure: true,
  );
  return result.exitCode == 0;
}

PackageUpstreamTarget _upstreamTargetFromOptions(ArgResults argResults) {
  final version = argResults.option('upstream-version')?.trim();
  final ref = argResults.option('upstream-ref')?.trim();
  final hasVersion = version != null && version.isNotEmpty;
  final hasRef = ref != null && ref.isNotEmpty;
  if (hasVersion && hasRef) {
    throw UsageException(
      'Use only one of --upstream-version or --upstream-ref.',
      '',
    );
  }
  return PackageUpstreamTarget(
    version: hasVersion ? version : null,
    ref: hasRef ? ref : null,
  );
}

Future<ResolvedPackageUpstreamRef> _resolvedMergeHeadTarget(
  Directory repository,
  PackageManifest manifest,
) async {
  final mergeHead = await _revParseCommit(repository, 'MERGE_HEAD');
  final package = await packageAtUpstreamRef(
    repository: repository,
    ref: mergeHead,
    packagePath: manifest.package.path,
  );
  if (package == null) {
    throw UsageException(
      'Missing pubspec.yaml for ${manifest.package.name} at '
          '${manifest.package.path} on MERGE_HEAD.',
      '',
    );
  }
  if (package.name != manifest.package.name) {
    throw UsageException(
      'Package path ${manifest.package.path} contains ${package.name}, '
          'expected ${manifest.package.name}. Update fluoh.yaml before syncing.',
      '',
    );
  }
  final refs = await packageReleaseRefs(
    repository: repository,
    packageName: manifest.package.name,
    packagePath: manifest.package.path,
  );
  PackageReleaseRef? matchingRef;
  for (final ref in refs) {
    if (ref.commit == mergeHead && ref.package.version == package.version) {
      matchingRef = ref;
    }
  }
  if (matchingRef == null) {
    final defaultBranchHead = await _revParseCommit(
      repository,
      manifest.upstreamBranch,
    );
    if (mergeHead != defaultBranchHead) {
      throw UsageException(
        'Could not infer an upstream release tag for MERGE_HEAD. Re-run '
            '"fluoh package sync --continue --upstream-ref <ref>" with the '
            'same non-tag ref used for the interrupted sync.',
        '',
      );
    }
  }
  return ResolvedPackageUpstreamRef(
    package: package,
    commit: mergeHead,
    ref: matchingRef?.ref,
  );
}

Map<String, Object?> _processOutputFields(ProcessResult result) {
  return {
    if (_outputTail(result.stdout) case final stdoutTail?) ...{
      'stdoutTail': stdoutTail,
    },
    if (_outputTail(result.stderr) case final stderrTail?) ...{
      'stderrTail': stderrTail,
    },
  };
}

String? _outputTail(Object output) {
  final text = output.toString().trim();
  if (text.isEmpty) {
    return null;
  }
  final lines = text.split('\n');
  const maxLines = 20;
  if (lines.length <= maxLines) {
    return text;
  }
  return lines.sublist(lines.length - maxLines).join('\n');
}
