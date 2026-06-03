import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

import '../cli/argument_validation.dart';
import '../cli/fluoh_command_runner.dart';
import '../cli/machine_output.dart';
import '../cli/terminal_output.dart';
import '../context/fluoh_environment.dart';
import '../schema/schema.dart';
import 'source_index.dart';
import 'source_sync.dart';

/// Validates Source files and verifies declared Package releases.
class SourceCheckCommand extends FluohCommand<int> {
  /// Creates the Source check command.
  SourceCheckCommand({
    required this.environment,
    required this.stdout,
    TerminalOutput? output,
  }) : _output = output ?? TerminalOutput(stdout: stdout) {
    argParser
      ..addFlag('json', negatable: false, help: 'Print the result as JSON.')
      ..addOption(
        'base-ref',
        valueHelp: 'ref',
        help:
            'Git base ref used to detect changed manifests. Defaults to '
            'origin/HEAD, main, master, then HEAD~1. Cannot be used with '
            '--all.',
      )
      ..addFlag(
        'all',
        negatable: false,
        help:
            'Check all manifest routes instead of only changed manifests. '
            'Cannot be used with --base-ref.',
      )
      ..addOption(
        'fluoh-command',
        valueHelp: 'command',
        defaultsTo: 'fluoh',
        help:
            'fluoh command used for nested package checks during release '
            'verification. Use a quoted command when running from a local '
            'checkout.',
      )
      ..addOption(
        'work-root',
        valueHelp: 'path',
        help:
            'Temporary work parent directory for cloned Source and Package '
            'repositories.',
      )
      ..addFlag(
        'keep-work-root',
        negatable: false,
        help: 'Keep the per-run work directory after check.',
      )
      ..addFlag(
        'skip-release-checks',
        negatable: false,
        help: 'Skip declared Package release verification.',
      )
      ..addOption(
        'release-check-timeout',
        valueHelp: 'seconds',
        defaultsTo: '600',
        help: 'Timeout for each declared Package release check.',
      )
      ..addOption(
        'max-release-checks',
        valueHelp: 'count',
        defaultsTo: '20',
        help: 'Maximum release records to check across selected manifests.',
      );
  }

  /// Runtime environment used to resolve local paths.
  final FluohEnvironment environment;

  /// Writer for machine output.
  final OutputWriter stdout;
  final TerminalOutput _output;

  @override
  String get name => 'check';

  @override
  String get description =>
      'Validate Source files and verify declared Package releases.';

  @override
  String get invocation => 'fluoh source check [source]';

  @override
  Future<int> run() async {
    final json = argResults!.flag('json');
    try {
      final report = await _runCheck();
      if (json) {
        writeMachineOutput(
          stdout,
          command: 'source check',
          ok: report.ok,
          exitCode: report.exitCode,
          fields: report.toJson(),
        );
      } else {
        _printHumanReport(report);
      }
      return report.exitCode;
    } on UsageException catch (error) {
      if (!json) {
        rethrow;
      }
      writeMachineOutput(
        stdout,
        command: 'source check',
        ok: false,
        exitCode: 64,
        fields: {
          'recommendation': 'blocked',
          'errors': [error.message],
          'warnings': <String>[],
        },
      );
      return 64;
    } on FormatException catch (error) {
      if (!json) {
        rethrow;
      }
      writeMachineOutput(
        stdout,
        command: 'source check',
        ok: false,
        exitCode: 64,
        fields: {
          'recommendation': 'blocked',
          'errors': [error.message],
          'warnings': <String>[],
        },
      );
      return 64;
    }
  }

  Future<_SourceCheckReport> _runCheck() async {
    final rest = expectArgumentCountAtMost(
      argResults!,
      1,
      'Expected at most one Source target.',
      usageException,
    );
    final target = rest.isEmpty
        ? environment.workingDirectory.path
        : rest.single;
    final checkAll = argResults!.flag('all');
    final baseRefOption = argResults!.option('base-ref')?.trim();
    if (checkAll && baseRefOption != null && baseRefOption.isNotEmpty) {
      usageException('--all cannot be used with --base-ref.');
    }
    final releaseCheckTimeout = _positiveIntOption(
      'release-check-timeout',
      defaultValue: 600,
    );
    final maxReleaseChecks = _positiveIntOption(
      'max-release-checks',
      defaultValue: 20,
    );
    final fluohCommand = _splitCommand(
      argResults!.option('fluoh-command') ?? 'fluoh',
    );
    if (fluohCommand.isEmpty) {
      usageException('--fluoh-command must not be empty.');
    }

    final providedWorkRoot = argResults!.option('work-root')?.trim();
    final workRoot = await _createWorkRoot(providedWorkRoot);

    try {
      final sourceCheckout = await _prepareSource(target, workRoot);
      final source = sourceCheckout.path;
      final sourceValidation = sourceCheckout.ok
          ? await _validateSource(source)
          : const _SourceValidationCheck(
              ok: false,
              exitCode: 1,
              message: 'not checked because source checkout failed',
            );
      if (!sourceCheckout.ok || !sourceValidation.ok) {
        return _SourceCheckReport(
          target: target,
          workRoot: workRoot.path,
          sourcePath: source.path,
          sourceCheckout: sourceCheckout,
          sourceValidation: sourceValidation,
          baseRef: null,
          all: checkAll,
          changedFiles: const [],
          checkedManifests: const [],
          manifests: const [],
          releaseChecks: const [],
          warnings: const [],
          errors: [
            if (!sourceCheckout.ok)
              'Source checkout failed: ${sourceCheckout.message}',
            if (!sourceValidation.ok)
              'Source validation failed: ${sourceValidation.message}',
          ],
          recommendation: 'blocked',
        );
      }
      final baseRef = checkAll
          ? null
          : baseRefOption == null || baseRefOption.isEmpty
          ? await _defaultBaseRef(source)
          : baseRefOption;
      final diffResult = checkAll
          ? const _ChangedFilesResult(files: [], warnings: [])
          : await _changedFiles(source, baseRef!);
      final manifestNames = await _changedManifestNames(
        source,
        diffResult.files,
        all: checkAll,
      );
      final manifests = <_CheckedSourceManifest>[];
      for (final name in manifestNames) {
        final file = File('${source.path}/manifests/$name/fluoh.yaml');
        if (!await file.exists()) {
          continue;
        }
        manifests.add(await _readCheckedManifest(source, name));
      }
      final releaseResult = await _verifyDeclaredReleases(
        source: source,
        manifests: manifests,
        workRoot: workRoot,
        fluohCommand: fluohCommand,
        releaseCheckTimeout: releaseCheckTimeout,
        maxReleaseChecks: maxReleaseChecks,
      );
      final warnings = [
        ...diffResult.warnings,
        ...releaseResult.warnings,
        if (manifestNames.isEmpty) 'No changed Source manifests were found.',
      ];
      final errors = <String>[
        if (!sourceCheckout.ok)
          'Source checkout failed: ${sourceCheckout.message}',
        if (!sourceValidation.ok)
          'Source validation failed: ${sourceValidation.message}',
        for (final item in releaseResult.items)
          if (!item.repository.ok)
            'Package repository clone failed for ${item.manifestName}: '
                '${item.repository.message}',
        for (final item in releaseResult.items)
          for (final check in item.checks)
            if (!check.ok)
              'Declared release check failed for ${check.packageName} at '
                  '${check.tag}: ${check.message}',
      ];
      final recommendation = errors.isNotEmpty
          ? 'blocked'
          : warnings.isNotEmpty
          ? 'needs-maintainer-decision'
          : 'ready';
      return _SourceCheckReport(
        target: target,
        workRoot: workRoot.path,
        sourcePath: source.path,
        sourceCheckout: sourceCheckout,
        sourceValidation: sourceValidation,
        baseRef: baseRef,
        all: checkAll,
        changedFiles: diffResult.files,
        checkedManifests: manifestNames,
        manifests: manifests,
        releaseChecks: releaseResult.items,
        warnings: warnings,
        errors: errors,
        recommendation: recommendation,
      );
    } finally {
      if (!argResults!.flag('keep-work-root')) {
        await deleteIfExists(workRoot);
      }
    }
  }

  Future<Directory> _createWorkRoot(String? providedWorkRoot) async {
    if (providedWorkRoot == null || providedWorkRoot.isEmpty) {
      return Directory.systemTemp.createTemp('fluoh_source_check_');
    }
    final parent = _resolveDirectory(
      environment.workingDirectory,
      providedWorkRoot,
    );
    await parent.create(recursive: true);
    return parent.createTemp('run_');
  }

  Future<_SourceSetupResult> _prepareSource(
    String target,
    Directory workRoot,
  ) async {
    final localPath = _resolveDirectory(environment.workingDirectory, target);
    if (await localPath.exists()) {
      return _SourceSetupResult.local(localPath);
    }

    final pr = _GitHubPullRequest.tryParse(target);
    if (pr == null) {
      usageException(
        'Expected a local Source path or GitHub pull request URL.',
      );
    }

    final source = Directory('${workRoot.path}/source');
    final clone = await _runProcess(
      ['git', 'clone', '--quiet', pr.cloneUrl, source.path],
      workingDirectory: workRoot,
      timeout: const Duration(minutes: 5),
    );
    if (!clone.ok) {
      return _SourceSetupResult.github(
        source,
        pr,
        clone: clone,
        fetch: null,
        checkout: null,
      );
    }

    final branch = 'fluoh-pr-${pr.number}';
    final fetch = await _runProcess(
      ['git', 'fetch', '--quiet', 'origin', 'pull/${pr.number}/head:$branch'],
      workingDirectory: source,
      timeout: const Duration(minutes: 5),
    );
    final checkout = fetch.ok
        ? await _runProcess([
            'git',
            'checkout',
            '--quiet',
            branch,
          ], workingDirectory: source)
        : null;
    return _SourceSetupResult.github(
      source,
      pr,
      clone: clone,
      fetch: fetch,
      checkout: checkout,
    );
  }

  Future<_SourceValidationCheck> _validateSource(Directory source) async {
    try {
      await validateSource('check', SourceConfig(path: source.path));
      return const _SourceValidationCheck(ok: true, exitCode: 0, message: 'ok');
    } on UsageException catch (error) {
      return _SourceValidationCheck(
        ok: false,
        exitCode: 64,
        message: error.message,
      );
    } on FormatException catch (error) {
      return _SourceValidationCheck(
        ok: false,
        exitCode: 64,
        message: error.message,
      );
    }
  }

  Future<String> _defaultBaseRef(Directory source) async {
    final symbolic = await _runProcess([
      'git',
      'symbolic-ref',
      'refs/remotes/origin/HEAD',
      '--short',
    ], workingDirectory: source);
    if (symbolic.ok && symbolic.stdout.trim().isNotEmpty) {
      return symbolic.stdout.trim();
    }
    for (final candidate in const ['main', 'master']) {
      final rev = await _runProcess([
        'git',
        'rev-parse',
        '--verify',
        candidate,
      ], workingDirectory: source);
      if (rev.ok) {
        return candidate;
      }
    }
    return 'HEAD~1';
  }

  Future<_ChangedFilesResult> _changedFiles(
    Directory source,
    String baseRef,
  ) async {
    final inside = await _runProcess([
      'git',
      'rev-parse',
      '--is-inside-work-tree',
    ], workingDirectory: source);
    if (!inside.ok || inside.stdout.trim() != 'true') {
      return const _ChangedFilesResult(
        files: [],
        warnings: [
          'Source path is not a Git worktree; checking all manifest routes.',
        ],
      );
    }
    var result = await _runProcess([
      'git',
      'diff',
      '--name-only',
      '$baseRef...HEAD',
    ], workingDirectory: source);
    if (!result.ok) {
      result = await _runProcess([
        'git',
        'diff',
        '--name-only',
        '$baseRef..HEAD',
      ], workingDirectory: source);
    }
    if (!result.ok) {
      return _ChangedFilesResult(
        files: const [],
        warnings: [
          'Could not diff against $baseRef; checking all manifest routes.',
        ],
      );
    }
    return _ChangedFilesResult(
      files: result.stdout
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList(growable: false),
      warnings: const [],
    );
  }

  Future<List<String>> _changedManifestNames(
    Directory source,
    List<String> changedFiles, {
    required bool all,
  }) async {
    final names = <String>{};
    var rootChanged = all || changedFiles.isEmpty;
    for (final file in changedFiles) {
      if (file == 'fluoh.yaml') {
        rootChanged = true;
      }
      final match = RegExp(r'^manifests/([^/]+)/').firstMatch(file);
      if (match != null) {
        names.add(match.group(1)!);
      }
    }
    if (names.isEmpty || rootChanged) {
      try {
        final sourceManifest = await SourceIndex.directory(
          source,
        ).loadRootManifest();
        names.addAll(sourceManifest.manifests.map((route) => route.name));
      } on Object {
        // Source validation reports invalid root manifests. Keep diff-derived
        // names when available so the JSON still points to useful context.
      }
    }
    return names.toList(growable: false)..sort();
  }

  Future<_CheckedSourceManifest> _readCheckedManifest(
    Directory source,
    String name,
  ) async {
    final manifestPath = 'manifests/$name/fluoh.yaml';
    final manifest = parseSourceManifest(
      content: await File('${source.path}/$manifestPath').readAsString(),
      label: manifestPath,
    );
    return _CheckedSourceManifest(routeName: name, manifest: manifest);
  }

  Future<_ReleaseVerificationResult> _verifyDeclaredReleases({
    required Directory source,
    required List<_CheckedSourceManifest> manifests,
    required Directory workRoot,
    required List<String> fluohCommand,
    required int releaseCheckTimeout,
    required int maxReleaseChecks,
  }) async {
    if (argResults!.flag('skip-release-checks')) {
      return const _ReleaseVerificationResult(
        items: [],
        warnings: [
          'Declared Package release verification was skipped by request.',
        ],
      );
    }

    final warnings = <String>[];
    final items = <_ManifestReleaseCheck>[];
    final packagesRoot = Directory('${workRoot.path}/packages');
    await packagesRoot.create(recursive: true);
    var checkCount = 0;
    var limitReached = false;
    for (final manifest in manifests) {
      final repository = await _clonePackageRepository(
        source: source,
        manifest: manifest.manifest,
        destination: Directory('${packagesRoot.path}/${manifest.routeName}'),
      );
      final checks = <_PackageReleaseCheck>[];
      if (repository.ok) {
        final repo = Directory(repository.path);
        for (final package in manifest.manifest.packages.values) {
          var releaseCount = 0;
          for (final sdk in package.sdks.values) {
            for (final release in sdk.releases) {
              if (checkCount >= maxReleaseChecks) {
                if (!limitReached) {
                  warnings.add(
                    'Release check limit reached at $maxReleaseChecks; '
                    'remaining releases were skipped.',
                  );
                }
                limitReached = true;
                break;
              }
              releaseCount += 1;
              checkCount += 1;
              checks.add(
                await _checkRelease(
                  repository: repo,
                  package: package,
                  sdk: sdk,
                  release: release,
                  fluohCommand: fluohCommand,
                  timeout: Duration(seconds: releaseCheckTimeout),
                ),
              );
            }
            if (limitReached) {
              break;
            }
          }
          if (releaseCount == 0 && !limitReached) {
            warnings.add(
              'Package ${package.name} in manifest ${manifest.routeName} '
              'has no release records to check.',
            );
          }
          if (limitReached) {
            break;
          }
        }
      }
      items.add(
        _ManifestReleaseCheck(
          manifestName: manifest.routeName,
          repository: repository,
          checks: checks,
        ),
      );
      if (limitReached) {
        break;
      }
    }
    return _ReleaseVerificationResult(items: items, warnings: warnings);
  }

  Future<_PackageRepositoryCheck> _clonePackageRepository({
    required Directory source,
    required SourceManifest manifest,
    required Directory destination,
  }) async {
    final resolved = _resolveRepositoryUrl(source, manifest.repositoryGitUrl);
    final clone = await _runProcess(
      ['git', 'clone', '--quiet', resolved, destination.path],
      workingDirectory: destination.parent,
      timeout: const Duration(minutes: 5),
    );
    if (!clone.ok) {
      return _PackageRepositoryCheck(
        ok: false,
        repository: manifest.repositoryGitUrl,
        resolvedRepository: resolved,
        path: destination.path,
        clone: clone,
        fetchTags: null,
      );
    }
    final fetch = await _runProcess(
      ['git', 'fetch', '--quiet', '--tags'],
      workingDirectory: destination,
      timeout: const Duration(minutes: 5),
    );
    return _PackageRepositoryCheck(
      ok: fetch.ok,
      repository: manifest.repositoryGitUrl,
      resolvedRepository: resolved,
      path: destination.path,
      clone: clone,
      fetchTags: fetch,
    );
  }

  Future<_PackageReleaseCheck> _checkRelease({
    required Directory repository,
    required SourceManifestPackage package,
    required SourceManifestSdk sdk,
    required SourceManifestRelease release,
    required List<String> fluohCommand,
    required Duration timeout,
  }) async {
    final tag =
        release.tag ??
        packageReleaseTagForPackage(
          packageName: package.name,
          upstreamVersion: release.upstreamVersion,
          sdkVersion: '${sdk.sdkLine}.0-ohos-0.0.0',
          releaseVersion: release.version,
        );
    final tagCheck = await _runProcess([
      'git',
      'rev-parse',
      '--verify',
      '$tag^{}',
    ], workingDirectory: repository);
    final branch = tagCheck.ok
        ? await _packageBranchAtTag(repository: repository, tag: tag)
        : null;
    final checkout = tagCheck.ok && branch != null
        ? await _runProcess([
            'git',
            'checkout',
            '--quiet',
            '-B',
            branch,
            tag,
          ], workingDirectory: repository)
        : null;
    final packageCheck = checkout != null && checkout.ok
        ? await _runProcess(
            [
              ...fluohCommand,
              'package',
              'check',
              '--package',
              package.name,
              '--json',
            ],
            workingDirectory: repository,
            timeout: timeout,
          )
        : null;
    Map<String, Object?>? packageCheckJson;
    if (packageCheck != null && packageCheck.stdout.trim().isNotEmpty) {
      try {
        packageCheckJson =
            jsonDecode(packageCheck.stdout) as Map<String, Object?>;
      } on FormatException {
        packageCheckJson = null;
      }
    }
    final ok =
        tagCheck.ok && (checkout?.ok ?? false) && (packageCheck?.ok ?? false);
    return _PackageReleaseCheck(
      packageName: package.name,
      sdkLine: sdk.sdkLine,
      releaseVersion: release.version,
      upstreamVersion: release.upstreamVersion,
      status: release.status,
      tag: tag,
      branch: branch,
      tagCheck: tagCheck,
      checkout: checkout,
      packageCheck: packageCheck,
      packageCheckJson: packageCheckJson,
      ok: ok,
    );
  }

  Future<String?> _packageBranchAtTag({
    required Directory repository,
    required String tag,
  }) async {
    final show = await _runProcess([
      'git',
      'show',
      '$tag:fluoh.yaml',
    ], workingDirectory: repository);
    if (!show.ok) {
      return null;
    }
    try {
      return PackageManifest.parse(show.stdout).repositoryBranch;
    } on FormatException {
      return null;
    }
  }

  Future<_ProcessCheckResult> _runProcess(
    List<String> command, {
    required Directory workingDirectory,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    try {
      final result = await Process.run(
        command.first,
        command.skip(1).toList(growable: false),
        workingDirectory: workingDirectory.path,
      ).timeout(timeout);
      return _ProcessCheckResult(
        command: command,
        exitCode: result.exitCode,
        stdout: result.stdout.toString().trim(),
        stderr: result.stderr.toString().trim(),
      );
    } on TimeoutException {
      return _ProcessCheckResult(
        command: command,
        exitCode: null,
        stdout: '',
        stderr: 'Timed out after ${timeout.inSeconds}s',
      );
    } on ProcessException catch (error) {
      return _ProcessCheckResult(
        command: command,
        exitCode: null,
        stdout: '',
        stderr: error.message,
      );
    } on OSError catch (error) {
      return _ProcessCheckResult(
        command: command,
        exitCode: null,
        stdout: '',
        stderr: error.message,
      );
    }
  }

  int _positiveIntOption(String name, {required int defaultValue}) {
    final value = argResults!.option(name)?.trim();
    if (value == null || value.isEmpty) {
      return defaultValue;
    }
    final parsed = int.tryParse(value);
    if (parsed == null || parsed <= 0) {
      usageException('--$name must be a positive integer.');
    }
    return parsed;
  }

  void _printHumanReport(_SourceCheckReport report) {
    _output.write('Source check: ${report.recommendation}');
    _output.write('Checked manifests: ${report.checkedManifests.join(', ')}');
    if (report.errors.isNotEmpty) {
      _output.error('Errors');
      for (final error in report.errors) {
        _output.write('- $error');
      }
    }
    if (report.warnings.isNotEmpty) {
      _output.warning('Warnings');
      for (final warning in report.warnings) {
        _output.write('- $warning');
      }
    }
    if (report.ok) {
      _output.success('Technical checks completed');
    }
  }
}

Directory _resolveDirectory(Directory workingDirectory, String path) {
  final directory = Directory(path);
  return directory.isAbsolute
      ? directory
      : Directory('${workingDirectory.path}/$path');
}

String _resolveRepositoryUrl(Directory source, String url) {
  final local = localSourceDirectoryFromUrl(url);
  if (local != null) {
    return local.isAbsolute
        ? local.path
        : Directory('${source.path}/${local.path}').path;
  }
  final directory = Directory(url);
  if (directory.isAbsolute || _looksLikeRemoteGitUrl(url)) {
    return url;
  }
  return Directory('${source.path}/$url').path;
}

bool _looksLikeRemoteGitUrl(String value) {
  return RegExp(r'^(https?|ssh|git)://').hasMatch(value) ||
      RegExp(r'^[A-Za-z0-9_.-]+@[^:]+:.+').hasMatch(value);
}

List<String> _splitCommand(String value) {
  final args = <String>[];
  final buffer = StringBuffer();
  String? quote;
  var escaping = false;
  for (final codeUnit in value.runes) {
    final char = String.fromCharCode(codeUnit);
    if (escaping) {
      buffer.write(char);
      escaping = false;
      continue;
    }
    if (char == '\\') {
      escaping = true;
      continue;
    }
    if (quote != null) {
      if (char == quote) {
        quote = null;
      } else {
        buffer.write(char);
      }
      continue;
    }
    if (char == '"' || char == "'") {
      quote = char;
      continue;
    }
    if (char.trim().isEmpty) {
      if (buffer.isNotEmpty) {
        args.add(buffer.toString());
        buffer.clear();
      }
      continue;
    }
    buffer.write(char);
  }
  if (buffer.isNotEmpty) {
    args.add(buffer.toString());
  }
  return args;
}

class _GitHubPullRequest {
  const _GitHubPullRequest({
    required this.owner,
    required this.repository,
    required this.number,
  });

  final String owner;
  final String repository;
  final String number;

  String get cloneUrl => 'https://github.com/$owner/$repository.git';

  static _GitHubPullRequest? tryParse(String value) {
    final match = RegExp(
      r'^https://github\.com/([^/]+)/([^/]+)/pull/([0-9]+)(?:[/?#].*)?$',
    ).firstMatch(value);
    if (match == null) {
      return null;
    }
    return _GitHubPullRequest(
      owner: match.group(1)!,
      repository: match.group(2)!,
      number: match.group(3)!,
    );
  }
}

class _SourceCheckReport {
  const _SourceCheckReport({
    required this.target,
    required this.workRoot,
    required this.sourcePath,
    required this.sourceCheckout,
    required this.sourceValidation,
    required this.baseRef,
    required this.all,
    required this.changedFiles,
    required this.checkedManifests,
    required this.manifests,
    required this.releaseChecks,
    required this.warnings,
    required this.errors,
    required this.recommendation,
  });

  final String target;
  final String workRoot;
  final String sourcePath;
  final _SourceSetupResult sourceCheckout;
  final _SourceValidationCheck sourceValidation;
  final String? baseRef;
  final bool all;
  final List<String> changedFiles;
  final List<String> checkedManifests;
  final List<_CheckedSourceManifest> manifests;
  final List<_ManifestReleaseCheck> releaseChecks;
  final List<String> warnings;
  final List<String> errors;
  final String recommendation;

  bool get ok => errors.isEmpty;
  int get exitCode => ok ? 0 : 1;

  Map<String, Object?> toJson() => {
    'recommendation': recommendation,
    'target': target,
    'workRoot': workRoot,
    'sourcePath': sourcePath,
    'sourceCheckout': sourceCheckout.toJson(),
    'sourceValidation': sourceValidation.toJson(),
    if (baseRef != null) 'baseRef': baseRef,
    'all': all,
    'changedFiles': changedFiles,
    'checkedManifests': checkedManifests,
    'manifests': [for (final manifest in manifests) manifest.toJson()],
    'releaseChecks': [for (final check in releaseChecks) check.toJson()],
    'warnings': warnings,
    'errors': errors,
  };
}

class _SourceSetupResult {
  const _SourceSetupResult({
    required this.kind,
    required this.path,
    required this.ok,
    required this.message,
    this.pullRequest,
    this.clone,
    this.fetch,
    this.checkout,
  });

  factory _SourceSetupResult.local(Directory path) =>
      _SourceSetupResult(kind: 'local', path: path, ok: true, message: 'ok');

  factory _SourceSetupResult.github(
    Directory path,
    _GitHubPullRequest pullRequest, {
    required _ProcessCheckResult clone,
    required _ProcessCheckResult? fetch,
    required _ProcessCheckResult? checkout,
  }) {
    final ok = clone.ok && (fetch?.ok ?? false) && (checkout?.ok ?? false);
    return _SourceSetupResult(
      kind: 'github',
      path: path,
      ok: ok,
      message: checkout?.message ?? fetch?.message ?? clone.message,
      pullRequest: pullRequest,
      clone: clone,
      fetch: fetch,
      checkout: checkout,
    );
  }

  final String kind;
  final Directory path;
  final bool ok;
  final String message;
  final _GitHubPullRequest? pullRequest;
  final _ProcessCheckResult? clone;
  final _ProcessCheckResult? fetch;
  final _ProcessCheckResult? checkout;

  Map<String, Object?> toJson() => {
    'kind': kind,
    'path': path.path,
    'ok': ok,
    'message': message,
    if (pullRequest != null)
      'pullRequest': {
        'owner': pullRequest!.owner,
        'repository': pullRequest!.repository,
        'number': pullRequest!.number,
        'cloneUrl': pullRequest!.cloneUrl,
      },
    if (clone != null) 'clone': clone!.toJson(),
    if (fetch != null) 'fetch': fetch!.toJson(),
    if (checkout != null) 'checkout': checkout!.toJson(),
  };
}

class _SourceValidationCheck {
  const _SourceValidationCheck({
    required this.ok,
    required this.exitCode,
    required this.message,
  });

  final bool ok;
  final int exitCode;
  final String message;

  Map<String, Object?> toJson() => {
    'ok': ok,
    'exitCode': exitCode,
    'message': message,
  };
}

class _ChangedFilesResult {
  const _ChangedFilesResult({required this.files, required this.warnings});

  final List<String> files;
  final List<String> warnings;
}

class _CheckedSourceManifest {
  const _CheckedSourceManifest({
    required this.routeName,
    required this.manifest,
  });

  final String routeName;
  final SourceManifest manifest;

  Map<String, Object?> toJson() => {
    'routeName': routeName,
    'name': manifest.name,
    'repository': manifest.repositoryGitUrl,
    'repositoryPath': manifest.repositoryPath,
    'upstream': manifest.upstreamGitUrl,
    'upstreamBranch': manifest.upstreamBranch,
    'upstreamPath': manifest.upstreamPath,
    'packages': [
      for (final package in manifest.packages.values)
        {
          'name': package.name,
          'repositoryPath': package.repositoryPath,
          'upstreamPath': package.upstreamPath,
          'sdks': [
            for (final sdk in package.sdks.values)
              {
                'sdkLine': sdk.sdkLine,
                'releases': [
                  for (final release in sdk.releases)
                    {
                      'version': release.version,
                      'upstreamVersion': release.upstreamVersion,
                      if (release.tag != null) 'tag': release.tag,
                      'status': release.status,
                    },
                ],
              },
          ],
        },
    ],
  };
}

class _ReleaseVerificationResult {
  const _ReleaseVerificationResult({
    required this.items,
    required this.warnings,
  });

  final List<_ManifestReleaseCheck> items;
  final List<String> warnings;
}

class _ManifestReleaseCheck {
  const _ManifestReleaseCheck({
    required this.manifestName,
    required this.repository,
    required this.checks,
  });

  final String manifestName;
  final _PackageRepositoryCheck repository;
  final List<_PackageReleaseCheck> checks;

  Map<String, Object?> toJson() => {
    'manifest': manifestName,
    'ok': repository.ok && checks.every((check) => check.ok),
    'repository': repository.toJson(),
    'checks': [for (final check in checks) check.toJson()],
  };
}

class _PackageRepositoryCheck {
  const _PackageRepositoryCheck({
    required this.ok,
    required this.repository,
    required this.resolvedRepository,
    required this.path,
    required this.clone,
    required this.fetchTags,
  });

  final bool ok;
  final String repository;
  final String resolvedRepository;
  final String path;
  final _ProcessCheckResult clone;
  final _ProcessCheckResult? fetchTags;

  String get message => fetchTags?.message ?? clone.message;

  Map<String, Object?> toJson() => {
    'ok': ok,
    'repository': repository,
    'resolvedRepository': resolvedRepository,
    'path': path,
    'clone': clone.toJson(),
    if (fetchTags != null) 'fetchTags': fetchTags!.toJson(),
  };
}

class _PackageReleaseCheck {
  const _PackageReleaseCheck({
    required this.packageName,
    required this.sdkLine,
    required this.releaseVersion,
    required this.upstreamVersion,
    required this.status,
    required this.tag,
    required this.branch,
    required this.tagCheck,
    required this.checkout,
    required this.packageCheck,
    required this.packageCheckJson,
    required this.ok,
  });

  final String packageName;
  final String sdkLine;
  final String releaseVersion;
  final String upstreamVersion;
  final String status;
  final String tag;
  final String? branch;
  final _ProcessCheckResult tagCheck;
  final _ProcessCheckResult? checkout;
  final _ProcessCheckResult? packageCheck;
  final Map<String, Object?>? packageCheckJson;
  final bool ok;

  String get message =>
      packageCheck?.message ?? checkout?.message ?? tagCheck.message;

  Map<String, Object?> toJson() => {
    'package': packageName,
    'sdkLine': sdkLine,
    'version': releaseVersion,
    'upstreamVersion': upstreamVersion,
    'status': status,
    'tag': tag,
    if (branch != null) 'branch': branch,
    'ok': ok,
    'tagCheck': tagCheck.toJson(),
    if (checkout != null) 'checkout': checkout!.toJson(),
    if (packageCheck != null) 'packageCheck': packageCheck!.toJson(),
    if (packageCheckJson != null) 'packageCheckJson': packageCheckJson,
  };
}

class _ProcessCheckResult {
  const _ProcessCheckResult({
    required this.command,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final List<String> command;
  final int? exitCode;
  final String stdout;
  final String stderr;

  bool get ok => exitCode == 0;
  String get message => stderr.isNotEmpty ? stderr : stdout;

  Map<String, Object?> toJson() => {
    'command': command,
    'ok': ok,
    'exitCode': exitCode,
    'stdout': stdout,
    'stderr': stderr,
  };
}
