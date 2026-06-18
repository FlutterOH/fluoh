import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import '../../cli/fluoh_command_runner.dart';
import '../../cli/machine_output.dart';
import '../../cli/terminal_output.dart';
import '../../context/fluoh_environment.dart';
import '../../sdk/sdk_manager.dart';
import '../git/package_git.dart';
import '../manifest/package_manifest.dart';
import '../package_sdk_compatibility.dart';
import '../upstream_package_ref.dart';

/// Resolves a read-only package support queue for monorepos.
class PackageQueueCommand extends FluohCommand<int> {
  /// Creates the package queue command.
  PackageQueueCommand({
    required this.environment,
    required OutputWriter stdout,
    TerminalOutput? output,
  }) : _stdout = stdout,
       _output = output ?? TerminalOutput(stdout: stdout, stderr: (_) {}) {
    argParser
      ..addOption(
        'upstream-version',
        valueHelp: 'version',
        help:
            'Upstream package version to target for every queued path. '
            'Defaults to the latest valid package release tag.',
      )
      ..addOption(
        'upstream-ref',
        valueHelp: 'ref',
        help:
            'Upstream Git ref to target for every queued path. Use only when '
            'release tags cannot identify the target package version.',
      )
      ..addOption(
        'org',
        valueHelp: 'organization',
        help:
            'Organization to pass through to each package add command when '
            'adding OHOS to examples.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help: 'Print the resolved package queue as JSON.',
      );
  }

  /// Runtime environment for repository and Flutter SDK operations.
  final FluohEnvironment environment;
  final OutputWriter _stdout;
  final TerminalOutput _output;

  @override
  String get name => 'queue';

  @override
  String get description => 'Resolve a read-only multi-package support queue.';

  @override
  String get invocation => 'fluoh package queue <package-path>...';

  @override
  String get usage => '$description\n\n$_usageWithoutDescription';

  @override
  void printUsage() {
    _output.write(usage);
  }

  @override
  Never usageException(String message) {
    throw UsageException(message, _usageWithoutDescription);
  }

  @override
  Future<int> run() async {
    final packagePaths = argResults!.rest;
    if (packagePaths.isEmpty) {
      usageException('Expected at least one <package-path>.');
    }
    final json = argResults!.flag('json');
    final output = json
        ? TerminalOutput(stdout: (_) {}, stderr: (_) {})
        : _output;
    final repository = environment.workingDirectory;
    final manifest = await readPackageManifest(repository);
    if (!manifest.isPorted) {
      usageException('package queue is only available for ported packages.');
    }
    final current = await currentBranch(repository);
    if (current != manifest.branch) {
      usageException(
        'Current branch $current does not match package branch '
        '${manifest.branch}.',
      );
    }
    final target = _upstreamTargetFromOptions(argResults!);
    final org = _flutterCreateOrgFromOptions(argResults!);
    if (!json) {
      output.step('Resolving package queue');
    }
    await fetchUpstreamRefsFromUrl(
      repository,
      upstreamUrl: manifest.requiredUpstreamUrl,
    );
    final status = await runGit(
      ['status', '--porcelain'],
      workingDirectory: repository,
      allowFailure: true,
    );
    final workingTreeClean =
        status.exitCode == 0 && status.stdout.toString().trim().isEmpty;
    final items = <_PackageQueueItem>[];
    final seenPackages = <String>{};
    for (final packagePath in packagePaths) {
      final resolved = await resolvePackageUpstreamRefAtPath(
        repository: repository,
        packagePath: packagePath,
        fallbackRef: 'upstream/${manifest.upstreamBranch}',
        target: target,
      );
      if (!seenPackages.add(resolved.package.name)) {
        usageException('Package ${resolved.package.name} was queued twice.');
      }
      final branch = flutterOhosPackageBranchForSdk(
        sdkVersion: manifest.sdkVersion,
        packageName: resolved.package.name,
      );
      final warnings = await packageSdkCompatibilityWarnings(
        repository: repository,
        selectedPackages: [
          SelectedPackageForSdkCompatibility(
            package: resolved.package,
            path: packagePath,
            upstreamRef: resolved.ref,
          ),
        ],
        sdkDirectory: SdkManager(environment).sdkDirectory(manifest.sdkVersion),
      );
      items.add(
        _PackageQueueItem(
          packagePath: packagePath,
          packageName: resolved.package.name,
          upstreamVersion: resolved.package.version,
          upstreamRef: resolved.ref,
          upstreamCommit: resolved.commit,
          branch: branch,
          branchExists: await _branchExists(repository, branch),
          addCommand: _addCommandFor(
            packagePath: packagePath,
            target: target,
            org: org,
          ),
          warnings: warnings,
        ),
      );
    }
    final queue = _PackageQueue(
      repositoryUrl: manifest.repositoryUrl,
      upstreamUrl: manifest.requiredUpstreamUrl,
      upstreamBranch: manifest.upstreamBranch,
      currentBranch: current,
      sourceBranch: manifest.branch,
      sdkVersion: manifest.sdkVersion,
      workingTreeClean: workingTreeClean,
      packages: items,
    );
    if (json) {
      writeMachineOutput(
        _stdout,
        command: 'package queue',
        ok: true,
        exitCode: 0,
        fields: {'changed': false, 'queue': queue.toJson()},
      );
      return 0;
    }
    _printQueue(output, queue);
    return 0;
  }

  String get _usageWithoutDescription {
    return [
      'Usage: $invocation',
      '',
      argParser.usage,
      '',
      'Run "${runner!.executableName} help" to see global options.',
    ].join('\n');
  }
}

class _PackageQueue {
  const _PackageQueue({
    required this.repositoryUrl,
    required this.upstreamUrl,
    required this.upstreamBranch,
    required this.currentBranch,
    required this.sourceBranch,
    required this.sdkVersion,
    required this.workingTreeClean,
    required this.packages,
  });

  final String repositoryUrl;
  final String upstreamUrl;
  final String upstreamBranch;
  final String currentBranch;
  final String sourceBranch;
  final String sdkVersion;
  final bool workingTreeClean;
  final List<_PackageQueueItem> packages;

  String get sdkLine => sdkLineFromSdkVersion(sdkVersion);

  Map<String, Object?> toJson() {
    return {
      'supportKind': 'package',
      'repository': {
        'url': repositoryUrl,
        'currentBranch': currentBranch,
        'sourceBranch': sourceBranch,
        'workingTreeClean': workingTreeClean,
      },
      'upstream': {'urlOrPath': upstreamUrl, 'branch': upstreamBranch},
      'sdk': {'version': sdkVersion, 'line': sdkLine},
      'packages': packages.map((package) => package.toJson()).toList(),
    };
  }
}

class _PackageQueueItem {
  const _PackageQueueItem({
    required this.packagePath,
    required this.packageName,
    required this.upstreamVersion,
    required this.upstreamRef,
    required this.upstreamCommit,
    required this.branch,
    required this.branchExists,
    required this.addCommand,
    required this.warnings,
  });

  final String packagePath;
  final String packageName;
  final String upstreamVersion;
  final String? upstreamRef;
  final String upstreamCommit;
  final String branch;
  final bool branchExists;
  final String addCommand;
  final List<PackageSdkCompatibilityWarning> warnings;

  String get nextCommand => branchExists
      ? 'git checkout $branch && fluoh package status --package $packageName'
      : addCommand;

  Map<String, Object?> toJson() {
    return {
      'name': packageName,
      'path': packagePath,
      'upstreamVersion': upstreamVersion,
      'upstreamRef': upstreamRef,
      'upstreamCommit': upstreamCommit,
      'branch': branch,
      'branchExists': branchExists,
      'nextCommand': nextCommand,
      'warnings': warnings.map((warning) => warning.toJson()).toList(),
    };
  }
}

void _printQueue(TerminalOutput output, _PackageQueue queue) {
  output.success('Package queue resolved');
  output.info('Repository branch: ${queue.sourceBranch}');
  output.info('SDK: ${queue.sdkVersion} (${queue.sdkLine})');
  if (!queue.workingTreeClean) {
    output.warning('Current working tree is not clean.');
    output.next('Commit or stash local changes before running package add');
  }
  for (final item in queue.packages) {
    output.blank();
    output.info('${item.packageName}: ${item.packagePath}');
    output.info('Branch: ${item.branch}');
    output.info('Upstream version: ${item.upstreamVersion}');
    if (item.branchExists) {
      output.warning('Package branch already exists: ${item.branch}');
    }
    for (final warning in item.warnings) {
      output.warning(warning.message);
      output.next(warning.nextStep);
    }
    output.next(item.nextCommand);
  }
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

String? _flutterCreateOrgFromOptions(ArgResults argResults) {
  final org = argResults.option('org')?.trim();
  if (org == null) {
    return null;
  }
  if (org.isEmpty) {
    throw UsageException('--org must not be empty.', '');
  }
  return org;
}

String _addCommandFor({
  required String packagePath,
  required PackageUpstreamTarget target,
  required String? org,
}) {
  final parts = ['fluoh package add $packagePath'];
  if (target.version != null) {
    parts.add('--upstream-version ${target.version}');
  }
  if (target.ref != null) {
    parts.add('--upstream-ref ${target.ref}');
  }
  if (org != null) {
    parts.add('--org $org');
  }
  return parts.join(' ');
}

Future<bool> _branchExists(Directory repository, String branch) async {
  final local = await runGit(
    ['show-ref', '--verify', '--quiet', 'refs/heads/$branch'],
    workingDirectory: repository,
    allowFailure: true,
  );
  if (local.exitCode == 0) {
    return true;
  }
  final origin = await runGit(
    ['show-ref', '--verify', '--quiet', 'refs/remotes/origin/$branch'],
    workingDirectory: repository,
    allowFailure: true,
  );
  return origin.exitCode == 0;
}
