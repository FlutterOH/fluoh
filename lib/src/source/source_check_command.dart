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
      ..addFlag(
        'schema-only',
        negatable: false,
        help:
            'Only validate local Source YAML and indexes. Does not read Git '
            'diffs, check SDK tags, or verify declared Package releases.',
      )
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
      ..addMultiOption(
        'manifest',
        valueHelp: 'name',
        help:
            'Limit checks to a Source manifest route. May be passed more than '
            'once.',
      )
      ..addMultiOption(
        'package',
        valueHelp: 'name',
        help:
            'Limit declared Package release verification to a package name. '
            'May be passed more than once.',
      )
      ..addOption(
        'shard',
        valueHelp: 'index/total',
        help:
            'Run only one shard of the selected release check plan, for '
            'example 1/10.',
      )
      ..addOption(
        'concurrency',
        valueHelp: 'count',
        defaultsTo: '1',
        help: 'Maximum manifest repositories to verify in parallel.',
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
    final schemaOnly = argResults!.flag('schema-only');
    if (schemaOnly) {
      _validateSchemaOnlyOptions();
      return _runSchemaOnlyCheck(target);
    }
    final checkAll = argResults!.flag('all');
    final baseRefOption = argResults!.option('base-ref')?.trim();
    if (checkAll && baseRefOption != null && baseRefOption.isNotEmpty) {
      usageException('--all cannot be used with --base-ref.');
    }
    final baseRefProvided = baseRefOption != null && baseRefOption.isNotEmpty;
    final manifestFilters = _multiOptionSet('manifest');
    final packageFilters = _multiOptionSet('package');
    final shard = _parseShardOption(argResults!.option('shard')?.trim());
    final concurrency = _positiveIntOption('concurrency', defaultValue: 1);
    final skipReleaseChecks = argResults!.flag('skip-release-checks');
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
      if (!sourceCheckout.ok) {
        return _SourceCheckReport(
          target: target,
          workRoot: workRoot.path,
          sourcePath: source.path,
          schemaOnly: false,
          sourceCheckout: sourceCheckout,
          sourceValidation: const _SourceValidationCheck(
            ok: false,
            exitCode: 1,
            message: 'not checked because source checkout failed',
          ),
          baseRef: null,
          all: checkAll,
          changedFiles: const [],
          checkedManifests: const [],
          manifests: const [],
          changeSummary: _SourceChangeSummary.none,
          releaseCheckPlan: _ReleaseCheckPlan.empty,
          releaseChecks: const [],
          sdkChecks: const [],
          warnings: const [],
          errors: ['Source checkout failed: ${sourceCheckout.message}'],
          recommendation: 'blocked',
        );
      }
      final baseRef = checkAll
          ? null
          : baseRefOption == null || baseRefOption.isEmpty
          ? await _defaultBaseRef(source)
          : baseRefOption;
      final diffResult = checkAll
          ? const _ChangedFilesResult(
              files: [],
              warnings: [],
              checkAllManifests: true,
            )
          : await _changedFiles(source, baseRef!);
      final manifestNames = await _changedManifestNames(
        source,
        diffResult.files,
        all: checkAll,
        baseRef: baseRef,
        checkAllManifests: diffResult.checkAllManifests,
      );
      final selectedManifestNames = _filterNames(
        manifestNames,
        manifestFilters,
      );
      final validateAllManifests =
          checkAll ||
          diffResult.checkAllManifests ||
          (!baseRefProvided && skipReleaseChecks);
      final sourceValidation = await _validateSource(
        source,
        manifestNames: validateAllManifests
            ? null
            : selectedManifestNames.toSet(),
        validatePackageManifests:
            validateAllManifests || selectedManifestNames.isNotEmpty,
      );
      if (!sourceValidation.ok) {
        return _SourceCheckReport(
          target: target,
          workRoot: workRoot.path,
          sourcePath: source.path,
          schemaOnly: false,
          sourceCheckout: sourceCheckout,
          sourceValidation: sourceValidation,
          baseRef: baseRef,
          all: checkAll,
          changedFiles: diffResult.files,
          checkedManifests: selectedManifestNames,
          manifests: const [],
          changeSummary: _SourceChangeSummary.none,
          releaseCheckPlan: _ReleaseCheckPlan.empty,
          releaseChecks: const [],
          sdkChecks: const [],
          warnings: diffResult.warnings,
          errors: ['Source validation failed: ${sourceValidation.message}'],
          recommendation: 'blocked',
        );
      }
      final manifests = <_CheckedSourceManifest>[];
      for (final name in selectedManifestNames) {
        final file = File('${source.path}/manifests/$name/fluoh.yaml');
        if (!await file.exists()) {
          continue;
        }
        manifests.add(await _readCheckedManifest(source, name));
      }
      final headRootManifest = await SourceIndex.directory(
        source,
      ).loadRootManifest();
      final sdkChecks = await _checkChangedSdkReleases(
        source: source,
        headRootManifest: headRootManifest,
        baseRef: baseRef,
        all: checkAll,
        checkAllRoot: diffResult.checkAllManifests,
        changedFiles: diffResult.files,
      );
      final releasePlan = await _planReleaseChecks(
        source: source,
        manifests: manifests,
        baseRef: baseRef,
        all: checkAll,
        checkAllManifests: diffResult.checkAllManifests,
      );
      final changeSummary = await _classifySourceChanges(
        source: source,
        headRootManifest: headRootManifest,
        baseRef: baseRef,
        all: checkAll,
        checkAllManifests: diffResult.checkAllManifests,
        changedFiles: diffResult.files,
        releasePlan: releasePlan,
      );
      final selectedReleasePlan = _filterReleaseCheckPlan(
        releasePlan,
        manifestFilters: manifestFilters,
        packageFilters: packageFilters,
        shard: shard,
        maxReleaseChecks: maxReleaseChecks,
        skipReleaseChecks: skipReleaseChecks,
      );
      final releaseResult = await _verifyDeclaredReleases(
        source: source,
        manifests: manifests,
        releasePlan: selectedReleasePlan,
        workRoot: workRoot,
        fluohCommand: fluohCommand,
        releaseCheckTimeout: releaseCheckTimeout,
        concurrency: concurrency,
      );
      final warnings = [
        ...diffResult.warnings,
        ...selectedReleasePlan.warnings,
        ...releaseResult.warnings,
      ];
      final errors = <String>[
        for (final check in sdkChecks)
          if (!check.ok)
            'SDK tag check failed for ${check.version}: ${check.message}',
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
        schemaOnly: false,
        sourceCheckout: sourceCheckout,
        sourceValidation: sourceValidation,
        baseRef: baseRef,
        all: checkAll,
        changedFiles: diffResult.files,
        checkedManifests: selectedManifestNames,
        manifests: manifests,
        changeSummary: changeSummary,
        releaseCheckPlan: selectedReleasePlan,
        releaseChecks: releaseResult.items,
        sdkChecks: sdkChecks,
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

  void _validateSchemaOnlyOptions() {
    for (final name in const [
      'base-ref',
      'all',
      'package',
      'shard',
      'concurrency',
      'fluoh-command',
      'work-root',
      'keep-work-root',
      'skip-release-checks',
      'release-check-timeout',
      'max-release-checks',
    ]) {
      if (argResults!.wasParsed(name)) {
        usageException('--schema-only cannot be used with --$name.');
      }
    }
  }

  Future<_SourceCheckReport> _runSchemaOnlyCheck(String target) async {
    final source = _resolveDirectory(environment.workingDirectory, target);
    if (!await source.exists()) {
      final pr = _GitHubPullRequest.tryParse(target);
      if (pr != null) {
        usageException('--schema-only requires a local Source path.');
      }
      usageException('Source path does not exist: ${source.path}');
    }

    final manifestFilters = _multiOptionSet('manifest');
    final sourceValidation = await _validateSource(
      source,
      label: source.path,
      manifestNames: manifestFilters.isEmpty ? null : manifestFilters,
      validatePackageManifests: true,
    );
    final manifestSelection = sourceValidation.ok
        ? await _schemaOnlyManifestSelection(source, manifestFilters)
        : (
            checkedManifests: manifestFilters.toList(growable: false)..sort(),
            errors: const <String>[],
          );
    final errors = [
      if (!sourceValidation.ok)
        'Source validation failed: ${sourceValidation.message}',
      ...manifestSelection.errors,
    ];
    return _SourceCheckReport(
      target: target,
      workRoot: null,
      sourcePath: source.path,
      schemaOnly: true,
      sourceCheckout: _SourceSetupResult.local(source),
      sourceValidation: sourceValidation,
      baseRef: null,
      all: false,
      changedFiles: const [],
      checkedManifests: manifestSelection.checkedManifests,
      manifests: const [],
      changeSummary: const _SourceChangeSummary(['schema-only']),
      releaseCheckPlan: _ReleaseCheckPlan.empty,
      releaseChecks: const [],
      sdkChecks: const [],
      warnings: const [],
      errors: errors,
      recommendation: errors.isEmpty ? 'ready' : 'blocked',
    );
  }

  Future<({List<String> checkedManifests, List<String> errors})>
  _schemaOnlyManifestSelection(
    Directory source,
    Set<String> manifestFilters,
  ) async {
    final manifestNames = await _allRootManifestNames(source);
    if (manifestFilters.isNotEmpty) {
      final manifestNameSet = manifestNames.toSet();
      final checkedManifests =
          manifestFilters
              .where(manifestNameSet.contains)
              .toList(growable: false)
            ..sort();
      final missingManifests =
          manifestFilters.difference(manifestNameSet).toList(growable: false)
            ..sort();
      return (
        checkedManifests: checkedManifests,
        errors: missingManifests.isEmpty
            ? const <String>[]
            : [
                'Unknown Source manifest route filter: '
                    '${missingManifests.join(', ')}',
              ],
      );
    }
    return (checkedManifests: manifestNames, errors: const <String>[]);
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

  Future<_SourceValidationCheck> _validateSource(
    Directory source, {
    String label = 'check',
    required Set<String>? manifestNames,
    required bool validatePackageManifests,
  }) async {
    try {
      await validateSource(
        label,
        SourceConfig(path: source.path),
        manifestNames: manifestNames,
        validatePackageManifests: validatePackageManifests,
      );
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
        checkAllManifests: true,
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
        checkAllManifests: true,
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
      checkAllManifests: false,
      warnings: const [],
    );
  }

  Future<List<String>> _changedManifestNames(
    Directory source,
    List<String> changedFiles, {
    required bool all,
    required String? baseRef,
    required bool checkAllManifests,
  }) async {
    final names = <String>{};
    var rootChanged = false;
    for (final file in changedFiles) {
      if (file == 'fluoh.yaml') {
        rootChanged = true;
      }
      final match = RegExp(r'^manifests/([^/]+)/').firstMatch(file);
      if (match != null) {
        names.add(match.group(1)!);
      }
    }

    if (all || checkAllManifests) {
      names.addAll(await _allRootManifestNames(source));
    } else if (rootChanged) {
      final changedRoutes = baseRef == null
          ? null
          : await _changedRootManifestRoutes(source, baseRef);
      if (changedRoutes == null) {
        names.addAll(await _allRootManifestNames(source));
      } else {
        names.addAll(changedRoutes);
      }
    }
    return names.toList(growable: false)..sort();
  }

  Future<List<String>> _allRootManifestNames(Directory source) async {
    try {
      final sourceManifest = await SourceIndex.directory(
        source,
      ).loadRootManifest();
      return sourceManifest.manifests
          .map((route) => route.name)
          .toList(growable: false);
    } on Object {
      // Source validation reports invalid root manifests. Keep diff-derived
      // names when available so the JSON still points to useful context.
      return const [];
    }
  }

  Future<List<String>?> _changedRootManifestRoutes(
    Directory source,
    String baseRef,
  ) async {
    final baseContent = await _runProcess([
      'git',
      'show',
      '$baseRef:fluoh.yaml',
    ], workingDirectory: source);
    if (!baseContent.ok) {
      return null;
    }

    try {
      final baseManifest = parseSourceRootManifest(baseContent.stdout);
      final headManifest = await SourceIndex.directory(
        source,
      ).loadRootManifest();
      final baseRoutes = {
        for (final route in baseManifest.manifests) route.name,
      };
      final headRoutes = {
        for (final route in headManifest.manifests) route.name,
      };
      return {
        ...baseRoutes.difference(headRoutes),
        ...headRoutes.difference(baseRoutes),
      }.toList(growable: false)..sort();
    } on Object {
      return null;
    }
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

  Future<SourceRootManifest?> _readBaseRootManifest(
    Directory source,
    String baseRef,
  ) async {
    final baseContent = await _runProcess([
      'git',
      'show',
      '$baseRef:fluoh.yaml',
    ], workingDirectory: source);
    if (!baseContent.ok) {
      return null;
    }
    try {
      return parseSourceRootManifest(baseContent.stdout);
    } on Object {
      return null;
    }
  }

  Future<SourceManifest?> _readBaseSourceManifest(
    Directory source,
    String baseRef,
    String name,
  ) async {
    final manifestPath = 'manifests/$name/fluoh.yaml';
    final baseContent = await _runProcess([
      'git',
      'show',
      '$baseRef:$manifestPath',
    ], workingDirectory: source);
    if (!baseContent.ok) {
      return null;
    }
    try {
      return parseSourceManifest(
        content: baseContent.stdout,
        label: manifestPath,
      );
    } on Object {
      return null;
    }
  }

  Future<List<_SdkReleaseCheck>> _checkChangedSdkReleases({
    required Directory source,
    required SourceRootManifest headRootManifest,
    required String? baseRef,
    required bool all,
    required bool checkAllRoot,
    required List<String> changedFiles,
  }) async {
    final repository = headRootManifest.sdkRepository;
    if (repository == null || headRootManifest.sdkReleases.isEmpty) {
      return const [];
    }

    final releases = <SdkRelease>[];
    var reason = 'all';
    if (all || checkAllRoot || baseRef == null) {
      releases.addAll(headRootManifest.sdkReleases);
      reason = all ? 'all' : 'diff-fallback';
    } else if (changedFiles.contains('fluoh.yaml')) {
      final baseManifest = await _readBaseRootManifest(source, baseRef);
      if (baseManifest == null || baseManifest.sdkRepository != repository) {
        releases.addAll(headRootManifest.sdkReleases);
        reason = baseManifest == null
            ? 'base-unavailable'
            : 'sdk-repository-changed';
      } else {
        final baseVersions = {
          for (final release in baseManifest.sdkReleases) release.version,
        };
        releases.addAll(
          headRootManifest.sdkReleases.where(
            (release) => !baseVersions.contains(release.version),
          ),
        );
        reason = 'added-sdk-release';
      }
    }

    final resolvedRepository = _resolveRepositoryUrl(source, repository);
    final checks = <_SdkReleaseCheck>[];
    for (final release in releases) {
      checks.add(
        await _checkSdkRelease(
          source: source,
          repository: repository,
          resolvedRepository: resolvedRepository,
          release: release,
          reason: reason,
        ),
      );
    }
    return checks;
  }

  Future<_SdkReleaseCheck> _checkSdkRelease({
    required Directory source,
    required String repository,
    required String resolvedRepository,
    required SdkRelease release,
    required String reason,
  }) async {
    final result = await _runProcess([
      'git',
      'ls-remote',
      '--tags',
      resolvedRepository,
      release.tag,
    ], workingDirectory: source);
    final tagRef = 'refs/tags/${release.tag}';
    final exists =
        result.ok &&
        result.stdout
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .any(
              (line) => line.endsWith(tagRef) || line.endsWith('$tagRef^{}'),
            );
    return _SdkReleaseCheck(
      version: release.version,
      tag: release.tag,
      repository: repository,
      resolvedRepository: resolvedRepository,
      reason: reason,
      result: result,
      ok: exists,
    );
  }

  Future<_ReleaseCheckPlan> _planReleaseChecks({
    required Directory source,
    required List<_CheckedSourceManifest> manifests,
    required String? baseRef,
    required bool all,
    required bool checkAllManifests,
  }) async {
    final warnings = <String>[];
    final items = <_PlannedReleaseCheck>[];
    final skipped = <_SkippedReleaseCheck>[];
    for (final manifest in manifests) {
      if (all || checkAllManifests || baseRef == null) {
        items.addAll(
          _allReleaseChecksForManifest(
            manifest,
            reason: all ? 'all' : 'diff-fallback',
          ),
        );
        continue;
      }

      final baseManifest = await _readBaseSourceManifest(
        source,
        baseRef,
        manifest.routeName,
      );
      if (baseManifest == null) {
        items.addAll(
          _allReleaseChecksForManifest(manifest, reason: 'new-manifest'),
        );
        continue;
      }

      try {
        final diff = _changedReleaseChecks(baseManifest, manifest);
        items.addAll(diff.items);
        skipped.addAll(diff.skipped);
      } on FormatException catch (error) {
        warnings.add(
          'Could not diff release records for ${manifest.routeName}: '
          '${error.message}; checking all releases in the manifest.',
        );
        items.addAll(
          _allReleaseChecksForManifest(
            manifest,
            reason: 'release-diff-fallback',
          ),
        );
      }
    }
    _sortPlannedReleaseChecks(items);
    _sortSkippedReleaseChecks(skipped);
    return _ReleaseCheckPlan(
      items: items,
      skipped: skipped,
      warnings: warnings,
    );
  }

  _ReleaseManifestDiff _changedReleaseChecks(
    SourceManifest baseManifest,
    _CheckedSourceManifest headManifest,
  ) {
    final head = headManifest.manifest;
    if (baseManifest.repositoryGitUrl != head.repositoryGitUrl) {
      return _ReleaseManifestDiff(
        items: _allReleaseChecksForManifest(
          headManifest,
          reason: 'repository-changed',
        ),
        skipped: const [],
      );
    }

    final checks = <_PlannedReleaseCheck>[];
    final skipped = <_SkippedReleaseCheck>[];
    for (final package in head.packages.values) {
      final basePackage = baseManifest.packages[package.name];
      if (basePackage == null) {
        checks.addAll(
          _releaseChecksForPackage(
            manifestName: headManifest.routeName,
            package: package,
            reason: 'package-added',
          ),
        );
        continue;
      }
      if (basePackage.repositoryPath != package.repositoryPath ||
          basePackage.upstreamPath != package.upstreamPath) {
        checks.addAll(
          _releaseChecksForPackage(
            manifestName: headManifest.routeName,
            package: package,
            reason: 'package-path-changed',
          ),
        );
        continue;
      }

      for (final sdk in package.sdks.values) {
        final baseSdk = basePackage.sdks[sdk.sdkLine];
        if (baseSdk == null) {
          checks.addAll(
            _releaseChecksForSdk(
              manifestName: headManifest.routeName,
              package: package,
              sdk: sdk,
              reason: 'sdk-line-added',
            ),
          );
          continue;
        }
        final baseReleases = {
          for (final release in baseSdk.releases)
            _releaseTag(package.name, sdk.sdkLine, release):
                _releaseFingerprint(release),
        };
        for (final release in sdk.releases) {
          final tag = _releaseTag(package.name, sdk.sdkLine, release);
          final baseFingerprint = baseReleases[tag];
          if (baseFingerprint == null) {
            checks.add(
              _PlannedReleaseCheck(
                manifestName: headManifest.routeName,
                package: package,
                sdk: sdk,
                release: release,
                tag: tag,
                reason: 'release-added',
              ),
            );
            continue;
          }
          if (baseFingerprint != _releaseFingerprint(release)) {
            checks.add(
              _PlannedReleaseCheck(
                manifestName: headManifest.routeName,
                package: package,
                sdk: sdk,
                release: release,
                tag: tag,
                reason: 'release-modified',
              ),
            );
          }
        }
        final headReleaseTags = {
          for (final release in sdk.releases)
            _releaseTag(package.name, sdk.sdkLine, release),
        };
        for (final baseRelease in baseSdk.releases) {
          final tag = _releaseTag(
            basePackage.name,
            baseSdk.sdkLine,
            baseRelease,
          );
          if (!headReleaseTags.contains(tag)) {
            skipped.add(
              _SkippedReleaseCheck(
                check: _PlannedReleaseCheck(
                  manifestName: headManifest.routeName,
                  package: basePackage,
                  sdk: baseSdk,
                  release: baseRelease,
                  tag: tag,
                  reason: 'release-deleted',
                ),
                skipReason: 'release-deleted',
              ),
            );
          }
        }
      }
    }
    for (final basePackage in baseManifest.packages.values) {
      if (head.packages.containsKey(basePackage.name)) {
        continue;
      }
      skipped.addAll(
        _skippedReleaseChecksForPackage(
          manifestName: headManifest.routeName,
          package: basePackage,
          reason: 'package-deleted',
        ),
      );
    }
    for (final package in head.packages.values) {
      final basePackage = baseManifest.packages[package.name];
      if (basePackage == null) {
        continue;
      }
      for (final baseSdk in basePackage.sdks.values) {
        if (package.sdks.containsKey(baseSdk.sdkLine)) {
          continue;
        }
        skipped.addAll(
          _skippedReleaseChecksForSdk(
            manifestName: headManifest.routeName,
            package: basePackage,
            sdk: baseSdk,
            reason: 'sdk-line-deleted',
          ),
        );
      }
    }
    return _ReleaseManifestDiff(items: checks, skipped: skipped);
  }

  List<_PlannedReleaseCheck> _allReleaseChecksForManifest(
    _CheckedSourceManifest manifest, {
    required String reason,
  }) {
    return [
      for (final package in manifest.manifest.packages.values)
        ..._releaseChecksForPackage(
          manifestName: manifest.routeName,
          package: package,
          reason: reason,
        ),
    ];
  }

  List<_PlannedReleaseCheck> _releaseChecksForPackage({
    required String manifestName,
    required SourceManifestPackage package,
    required String reason,
  }) {
    return [
      for (final sdk in package.sdks.values)
        ..._releaseChecksForSdk(
          manifestName: manifestName,
          package: package,
          sdk: sdk,
          reason: reason,
        ),
    ];
  }

  List<_PlannedReleaseCheck> _releaseChecksForSdk({
    required String manifestName,
    required SourceManifestPackage package,
    required SourceManifestSdk sdk,
    required String reason,
  }) {
    return [
      for (final release in sdk.releases)
        _PlannedReleaseCheck(
          manifestName: manifestName,
          package: package,
          sdk: sdk,
          release: release,
          tag: _releaseTag(package.name, sdk.sdkLine, release),
          reason: reason,
        ),
    ];
  }

  List<_SkippedReleaseCheck> _skippedReleaseChecksForPackage({
    required String manifestName,
    required SourceManifestPackage package,
    required String reason,
  }) {
    return [
      for (final sdk in package.sdks.values)
        ..._skippedReleaseChecksForSdk(
          manifestName: manifestName,
          package: package,
          sdk: sdk,
          reason: reason,
        ),
    ];
  }

  List<_SkippedReleaseCheck> _skippedReleaseChecksForSdk({
    required String manifestName,
    required SourceManifestPackage package,
    required SourceManifestSdk sdk,
    required String reason,
  }) {
    return [
      for (final release in sdk.releases)
        _SkippedReleaseCheck(
          check: _PlannedReleaseCheck(
            manifestName: manifestName,
            package: package,
            sdk: sdk,
            release: release,
            tag: _releaseTag(package.name, sdk.sdkLine, release),
            reason: reason,
          ),
          skipReason: reason,
        ),
    ];
  }

  _ReleaseCheckPlan _filterReleaseCheckPlan(
    _ReleaseCheckPlan plan, {
    required Set<String> manifestFilters,
    required Set<String> packageFilters,
    required _ReleaseCheckShard? shard,
    required int maxReleaseChecks,
    required bool skipReleaseChecks,
  }) {
    final skipped = plan.skipped.toList(growable: true);
    var selected = <_PlannedReleaseCheck>[];
    for (final item in plan.items) {
      final skipReason =
          manifestFilters.isNotEmpty &&
              !manifestFilters.contains(item.manifestName)
          ? 'manifest-filter'
          : packageFilters.isNotEmpty &&
                !packageFilters.contains(item.package.name)
          ? 'package-filter'
          : null;
      if (skipReason == null) {
        selected.add(item);
      } else {
        skipped.add(_SkippedReleaseCheck(check: item, skipReason: skipReason));
      }
    }

    if (shard != null) {
      final sharded = <_PlannedReleaseCheck>[];
      for (var index = 0; index < selected.length; index += 1) {
        final item = selected[index];
        if (index % shard.total == shard.index - 1) {
          sharded.add(item);
        } else {
          skipped.add(
            _SkippedReleaseCheck(check: item, skipReason: 'shard-filter'),
          );
        }
      }
      selected = sharded;
    }

    if (skipReleaseChecks) {
      skipped.addAll(
        selected.map(
          (item) => _SkippedReleaseCheck(
            check: item,
            skipReason: 'release-checks-skipped',
          ),
        ),
      );
      selected = <_PlannedReleaseCheck>[];
    }

    final warnings = plan.warnings.toList(growable: true);
    if (selected.length > maxReleaseChecks) {
      final limited = selected.take(maxReleaseChecks).toList(growable: false);
      skipped.addAll(
        selected
            .skip(maxReleaseChecks)
            .map(
              (item) => _SkippedReleaseCheck(
                check: item,
                skipReason: 'max-release-checks',
              ),
            ),
      );
      selected = limited;
      warnings.add(
        'Release check limit reached at $maxReleaseChecks; remaining releases '
        'were skipped.',
      );
    }

    _sortPlannedReleaseChecks(selected);
    _sortSkippedReleaseChecks(skipped);
    return _ReleaseCheckPlan(
      items: selected,
      skipped: skipped,
      warnings: warnings,
    );
  }

  Future<_ReleaseVerificationResult> _verifyDeclaredReleases({
    required Directory source,
    required List<_CheckedSourceManifest> manifests,
    required _ReleaseCheckPlan releasePlan,
    required Directory workRoot,
    required List<String> fluohCommand,
    required int releaseCheckTimeout,
    required int concurrency,
  }) async {
    if (releasePlan.items.isEmpty) {
      return const _ReleaseVerificationResult(items: [], warnings: []);
    }

    final packagesRoot = Directory('${workRoot.path}/packages');
    await packagesRoot.create(recursive: true);
    final manifestByName = {
      for (final manifest in manifests) manifest.routeName: manifest,
    };
    final plannedByManifest = <String, List<_PlannedReleaseCheck>>{};
    for (final item in releasePlan.items) {
      plannedByManifest.putIfAbsent(item.manifestName, () => []).add(item);
    }
    final manifestNames = plannedByManifest.keys.toList(growable: false)
      ..sort();
    final items = List<_ManifestReleaseCheck?>.filled(
      manifestNames.length,
      null,
    );
    var nextIndex = 0;

    Future<void> worker() async {
      while (nextIndex < manifestNames.length) {
        final index = nextIndex;
        nextIndex += 1;
        final name = manifestNames[index];
        final manifest = manifestByName[name];
        if (manifest == null) {
          continue;
        }
        items[index] = await _verifyManifestReleases(
          source: source,
          manifest: manifest,
          planned: plannedByManifest[name]!,
          packagesRoot: packagesRoot,
          fluohCommand: fluohCommand,
          releaseCheckTimeout: releaseCheckTimeout,
        );
      }
    }

    final workerCount = concurrency < manifestNames.length
        ? concurrency
        : manifestNames.length;
    await Future.wait([for (var i = 0; i < workerCount; i += 1) worker()]);
    return _ReleaseVerificationResult(
      items: items.whereType<_ManifestReleaseCheck>().toList(growable: false),
      warnings: const [],
    );
  }

  Future<_ManifestReleaseCheck> _verifyManifestReleases({
    required Directory source,
    required _CheckedSourceManifest manifest,
    required List<_PlannedReleaseCheck> planned,
    required Directory packagesRoot,
    required List<String> fluohCommand,
    required int releaseCheckTimeout,
  }) async {
    final repository = await _clonePackageRepository(
      source: source,
      manifest: manifest.manifest,
      destination: Directory('${packagesRoot.path}/${manifest.routeName}'),
    );
    final checks = <_PackageReleaseCheck>[];
    if (repository.ok) {
      final repo = Directory(repository.path);
      for (final plannedRelease in planned) {
        checks.add(
          await _checkRelease(
            repository: repo,
            package: plannedRelease.package,
            sdk: plannedRelease.sdk,
            release: plannedRelease.release,
            fluohCommand: fluohCommand,
            timeout: Duration(seconds: releaseCheckTimeout),
          ),
        );
      }
    }
    return _ManifestReleaseCheck(
      manifestName: manifest.routeName,
      repository: repository,
      checks: checks,
    );
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
    final metadataCheck = tagCheck.ok
        ? await _checkTaggedPackageMetadata(
            repository: repository,
            tag: tag,
            package: package,
            sdk: sdk,
            release: release,
          )
        : null;
    final branch = metadataCheck?.branch;
    final checkout =
        tagCheck.ok && (metadataCheck?.ok ?? false) && branch != null
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
        tagCheck.ok &&
        (metadataCheck?.ok ?? false) &&
        (checkout?.ok ?? false) &&
        (packageCheck?.ok ?? false);
    return _PackageReleaseCheck(
      packageName: package.name,
      sdkLine: sdk.sdkLine,
      releaseVersion: release.version,
      upstreamVersion: release.upstreamVersion,
      status: release.status,
      tag: tag,
      branch: branch,
      tagCheck: tagCheck,
      metadataCheck: metadataCheck,
      checkout: checkout,
      packageCheck: packageCheck,
      packageCheckJson: packageCheckJson,
      ok: ok,
    );
  }

  Future<_TaggedPackageMetadataCheck> _checkTaggedPackageMetadata({
    required Directory repository,
    required String tag,
    required SourceManifestPackage package,
    required SourceManifestSdk sdk,
    required SourceManifestRelease release,
  }) async {
    final show = await _runProcess([
      'git',
      'show',
      '$tag:fluoh.yaml',
    ], workingDirectory: repository);
    if (!show.ok) {
      return _TaggedPackageMetadataCheck(
        ok: false,
        message: show.message,
        branch: null,
        packageManifest: null,
        packageName: package.name,
        show: show,
      );
    }
    try {
      final manifest = PackageManifest.parse(show.stdout);
      final taggedPackage = manifest.packageForName(package.name);
      final expectedSdkLine = sdk.sdkLine;
      final actualSdkLine = sdkLineFromSdkVersion(manifest.sdkVersion);
      final expectedStatus = release.status == 'compatible'
          ? null
          : release.status;
      final actualStatus = taggedPackage.status == 'compatible'
          ? null
          : taggedPackage.status;
      final mismatches = <String>[
        if (actualSdkLine != expectedSdkLine)
          'sdk line is $actualSdkLine, expected $expectedSdkLine',
        if (taggedPackage.version != release.version)
          'release version is ${taggedPackage.version}, expected ${release.version}',
        if (taggedPackage.upstreamVersion != release.upstreamVersion)
          'upstream version is ${taggedPackage.upstreamVersion}, expected ${release.upstreamVersion}',
        if (taggedPackage.repositoryPath != package.repositoryPath)
          'repository path is ${taggedPackage.repositoryPath}, expected ${package.repositoryPath}',
        if (taggedPackage.upstreamPath != package.upstreamPath)
          'upstream path is ${taggedPackage.upstreamPath}, expected ${package.upstreamPath}',
        if (actualStatus != expectedStatus)
          'status is ${actualStatus ?? 'compatible'}, expected ${expectedStatus ?? 'compatible'}',
        if (release.tag == null &&
            !taggedPackage.matchesReleaseTag(manifest.sdkVersion, tag))
          'tag $tag does not match package-owned release metadata',
      ];
      return _TaggedPackageMetadataCheck(
        ok: mismatches.isEmpty,
        message: mismatches.isEmpty
            ? 'ok'
            : 'Tagged package metadata mismatch: ${mismatches.join('; ')}.',
        branch: manifest.repositoryBranch,
        packageManifest: manifest,
        packageName: package.name,
        package: taggedPackage,
        show: show,
      );
    } on FormatException catch (error) {
      return _TaggedPackageMetadataCheck(
        ok: false,
        message: error.message,
        branch: null,
        packageManifest: null,
        packageName: package.name,
        show: show,
      );
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

  Set<String> _multiOptionSet(String name) {
    final values = <String>{};
    for (final value in argResults!.multiOption(name)) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        usageException('--$name values must not be empty.');
      }
      values.add(trimmed);
    }
    return values;
  }

  _ReleaseCheckShard? _parseShardOption(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    final match = RegExp(r'^([0-9]+)/([0-9]+)$').firstMatch(value);
    if (match == null) {
      usageException('--shard must use index/total, for example 1/10.');
    }
    final index = int.parse(match.group(1)!);
    final total = int.parse(match.group(2)!);
    if (index <= 0 || total <= 0 || index > total) {
      usageException('--shard index must be between 1 and the shard total.');
    }
    return _ReleaseCheckShard(index: index, total: total);
  }

  Future<_SourceChangeSummary> _classifySourceChanges({
    required Directory source,
    required SourceRootManifest headRootManifest,
    required String? baseRef,
    required bool all,
    required bool checkAllManifests,
    required List<String> changedFiles,
    required _ReleaseCheckPlan releasePlan,
  }) async {
    final types = <String>{};
    if (all) {
      types.add('full-audit');
    }
    if (checkAllManifests) {
      types.add('diff-fallback');
    }
    if (changedFiles.isEmpty && !all && !checkAllManifests) {
      return _SourceChangeSummary.none;
    }

    if (changedFiles.contains('fluoh.yaml')) {
      types.addAll(
        await _classifyRootChange(
          source: source,
          headRootManifest: headRootManifest,
          baseRef: baseRef,
        ),
      );
    }

    final changedManifestNames = <String>{
      for (final file in changedFiles)
        if (RegExp(r'^manifests/([^/]+)/fluoh\.yaml$').firstMatch(file)
            case final match?)
          match.group(1)!,
    };
    for (final name in changedManifestNames) {
      types.addAll(
        await _classifyManifestChange(
          source: source,
          baseRef: baseRef,
          name: name,
        ),
      );
    }

    if (releasePlan.changedRecords.isNotEmpty) {
      types.add('release-record');
    }
    if (types.isEmpty && changedFiles.isNotEmpty) {
      types.add('supporting-files');
    }
    return _SourceChangeSummary(types.toList(growable: false)..sort());
  }

  Future<List<String>> _classifyRootChange({
    required Directory source,
    required SourceRootManifest headRootManifest,
    required String? baseRef,
  }) async {
    if (baseRef == null) {
      return const ['source-root'];
    }
    final baseRootManifest = await _readBaseRootManifest(source, baseRef);
    if (baseRootManifest == null) {
      return const ['source-root'];
    }
    final types = <String>{};
    if (baseRootManifest.sdkRepository != headRootManifest.sdkRepository ||
        _sdkReleaseVersions(baseRootManifest) !=
            _sdkReleaseVersions(headRootManifest)) {
      types.add('sdk-versions');
    }
    if (_rootManifestRoutes(baseRootManifest) !=
        _rootManifestRoutes(headRootManifest)) {
      types.add('manifest-route');
    }
    if (_rootManifestMetadataFingerprint(baseRootManifest) !=
        _rootManifestMetadataFingerprint(headRootManifest)) {
      types.add('source-root');
    }
    return types.isEmpty ? const ['source-root'] : types.toList();
  }

  Future<List<String>> _classifyManifestChange({
    required Directory source,
    required String? baseRef,
    required String name,
  }) async {
    final headFile = File('${source.path}/manifests/$name/fluoh.yaml');
    final headExists = await headFile.exists();
    if (baseRef == null) {
      return headExists ? const ['manifest'] : const ['manifest-deleted'];
    }
    final baseManifest = await _readBaseSourceManifest(source, baseRef, name);
    if (baseManifest == null) {
      return headExists ? const ['manifest-added'] : const ['manifest-deleted'];
    }
    if (!headExists) {
      return const ['manifest-deleted'];
    }
    final headManifest = await _readCheckedManifest(source, name);
    final head = headManifest.manifest;
    final types = <String>{};
    if (_sourceManifestMetadataFingerprint(baseManifest) !=
        _sourceManifestMetadataFingerprint(head)) {
      types.add('manifest-metadata');
    }
    final baseReleases = _manifestReleaseFingerprints(baseManifest);
    final headReleases = _manifestReleaseFingerprints(head);
    if (baseReleases.keys
        .toSet()
        .difference(headReleases.keys.toSet())
        .isNotEmpty) {
      types.add('release-record-deleted');
    }
    if (headReleases.keys
            .toSet()
            .difference(baseReleases.keys.toSet())
            .isNotEmpty ||
        headReleases.entries.any(
          (entry) =>
              baseReleases[entry.key] != null &&
              baseReleases[entry.key] != entry.value,
        )) {
      types.add('release-record');
    }
    if (types.isEmpty &&
        _advisoryMaintenanceFingerprint(baseManifest) !=
            _advisoryMaintenanceFingerprint(head)) {
      types.add('advisory-maintenance');
    }
    return types.isEmpty ? const ['manifest'] : types.toList();
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

List<String> _filterNames(List<String> names, Set<String> filters) {
  if (filters.isEmpty) {
    return names;
  }
  return names.where(filters.contains).toList(growable: false)..sort();
}

void _sortPlannedReleaseChecks(List<_PlannedReleaseCheck> items) {
  items.sort(_comparePlannedReleaseChecks);
}

void _sortSkippedReleaseChecks(List<_SkippedReleaseCheck> items) {
  items.sort(
    (a, b) => _comparePlannedReleaseChecks(a.check, b.check) != 0
        ? _comparePlannedReleaseChecks(a.check, b.check)
        : a.skipReason.compareTo(b.skipReason),
  );
}

int _comparePlannedReleaseChecks(
  _PlannedReleaseCheck a,
  _PlannedReleaseCheck b,
) {
  final fields = [
    a.manifestName.compareTo(b.manifestName),
    a.package.name.compareTo(b.package.name),
    a.sdk.sdkLine.compareTo(b.sdk.sdkLine),
    a.tag.compareTo(b.tag),
    a.reason.compareTo(b.reason),
  ];
  return fields.firstWhere((value) => value != 0, orElse: () => 0);
}

bool _looksLikeRemoteGitUrl(String value) {
  return RegExp(r'^(https?|ssh|git)://').hasMatch(value) ||
      RegExp(r'^[A-Za-z0-9_.-]+@[^:]+:.+').hasMatch(value);
}

String _releaseTag(
  String packageName,
  String sdkLine,
  SourceManifestRelease release,
) {
  return release.tag ??
      packageReleaseTagForPackage(
        packageName: packageName,
        upstreamVersion: release.upstreamVersion,
        sdkVersion: '$sdkLine.0-ohos-0.0.0',
        releaseVersion: release.version,
      );
}

String _releaseFingerprint(SourceManifestRelease release) {
  return [
    release.version,
    release.upstreamVersion,
    release.tag ?? '',
    release.status,
  ].join('\u{1f}');
}

String _sdkReleaseVersions(SourceRootManifest manifest) {
  return (manifest.sdkReleases.map((release) => release.version).toList()
        ..sort())
      .join('\u{1f}');
}

String _rootManifestRoutes(SourceRootManifest manifest) {
  return (manifest.manifests.map((route) => route.name).toList()..sort()).join(
    '\u{1f}',
  );
}

String _rootManifestMetadataFingerprint(SourceRootManifest manifest) {
  return [
    manifest.schemaVersion,
    manifest.name,
    manifest.description ?? '',
    manifest.repositoryGitUrl ?? '',
    manifest.fluohConstraint ?? '',
  ].join('\u{1f}');
}

String _sourceManifestMetadataFingerprint(SourceManifest manifest) {
  final packageFields = <String>[];
  final packages = manifest.packages.values.toList(growable: false)
    ..sort((a, b) => a.name.compareTo(b.name));
  for (final package in packages) {
    packageFields.add(
      [
        package.name,
        package.repositoryPath,
        package.upstreamPath,
      ].join('\u{1e}'),
    );
  }
  return [
    manifest.schemaVersion,
    manifest.name,
    manifest.repositoryGitUrl,
    manifest.repositoryPath,
    manifest.upstreamGitUrl,
    manifest.upstreamBranch,
    manifest.upstreamPath,
    ...packageFields,
  ].join('\u{1f}');
}

Map<String, String> _manifestReleaseFingerprints(SourceManifest manifest) {
  final releases = <String, String>{};
  final packages = manifest.packages.values.toList(growable: false)
    ..sort((a, b) => a.name.compareTo(b.name));
  for (final package in packages) {
    final sdks = package.sdks.values.toList(growable: false)
      ..sort((a, b) => a.sdkLine.compareTo(b.sdkLine));
    for (final sdk in sdks) {
      for (final release in sdk.releases) {
        final tag = _releaseTag(package.name, sdk.sdkLine, release);
        releases['${package.name}\u{1e}${sdk.sdkLine}\u{1e}$tag'] =
            _releaseFingerprint(release);
      }
    }
  }
  return releases;
}

String _advisoryMaintenanceFingerprint(SourceManifest manifest) {
  final fields = <String>[];
  final packages = manifest.packages.values.toList(growable: false)
    ..sort((a, b) => a.name.compareTo(b.name));
  for (final package in packages) {
    final maintenance = package.maintenance;
    final advisory = package.advisory;
    fields.add(
      [
        package.name,
        maintenance?.status ?? '',
        maintenance?.reason ?? '',
        advisory?.message ?? '',
        if (advisory != null)
          for (final alternative in advisory.alternatives)
            [
              alternative.name,
              alternative.reason ?? '',
              alternative.url ?? '',
            ].join('\u{1d}'),
      ].join('\u{1e}'),
    );
  }
  return fields.join('\u{1f}');
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
    required this.schemaOnly,
    required this.sourceCheckout,
    required this.sourceValidation,
    required this.baseRef,
    required this.all,
    required this.changedFiles,
    required this.checkedManifests,
    required this.manifests,
    required this.changeSummary,
    required this.releaseCheckPlan,
    required this.releaseChecks,
    required this.sdkChecks,
    required this.warnings,
    required this.errors,
    required this.recommendation,
  });

  final String target;
  final String? workRoot;
  final String sourcePath;
  final bool schemaOnly;
  final _SourceSetupResult sourceCheckout;
  final _SourceValidationCheck sourceValidation;
  final String? baseRef;
  final bool all;
  final List<String> changedFiles;
  final List<String> checkedManifests;
  final List<_CheckedSourceManifest> manifests;
  final _SourceChangeSummary changeSummary;
  final _ReleaseCheckPlan releaseCheckPlan;
  final List<_ManifestReleaseCheck> releaseChecks;
  final List<_SdkReleaseCheck> sdkChecks;
  final List<String> warnings;
  final List<String> errors;
  final String recommendation;

  bool get ok => errors.isEmpty;
  int get exitCode => ok ? 0 : 1;

  Map<String, Object?> toJson() => {
    'recommendation': recommendation,
    'target': target,
    if (workRoot != null) 'workRoot': workRoot,
    'sourcePath': sourcePath,
    'schemaOnly': schemaOnly,
    'sourceCheckout': sourceCheckout.toJson(),
    'sourceValidation': sourceValidation.toJson(),
    if (baseRef != null) 'baseRef': baseRef,
    'all': all,
    'changeType': changeSummary.changeType,
    'changeTypes': changeSummary.changeTypes,
    'affectedManifests': checkedManifests,
    'changedFiles': changedFiles,
    'checkedManifests': checkedManifests,
    'manifests': [for (final manifest in manifests) manifest.toJson()],
    'changedReleaseRecords': [
      for (final check in releaseCheckPlan.changedRecords) check.toJson(),
    ],
    'releaseCheckPlan': releaseCheckPlan.toJson(),
    'skippedReleaseChecks': [
      for (final check in releaseCheckPlan.skipped) check.toJson(),
    ],
    'releaseChecks': [for (final check in releaseChecks) check.toJson()],
    'sdkChecks': [for (final check in sdkChecks) check.toJson()],
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
  const _ChangedFilesResult({
    required this.files,
    required this.warnings,
    required this.checkAllManifests,
  });

  final List<String> files;
  final List<String> warnings;
  final bool checkAllManifests;
}

class _SourceChangeSummary {
  const _SourceChangeSummary(this.changeTypes);

  static const none = _SourceChangeSummary(['none']);

  final List<String> changeTypes;

  String get changeType {
    if (changeTypes.isEmpty) {
      return 'none';
    }
    if (changeTypes.length == 1) {
      return changeTypes.single;
    }
    return 'mixed';
  }
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

class _SdkReleaseCheck {
  const _SdkReleaseCheck({
    required this.version,
    required this.tag,
    required this.repository,
    required this.resolvedRepository,
    required this.reason,
    required this.result,
    required this.ok,
  });

  final String version;
  final String tag;
  final String repository;
  final String resolvedRepository;
  final String reason;
  final _ProcessCheckResult result;
  final bool ok;

  String get message => result.ok && result.stdout.trim().isEmpty
      ? 'Tag $tag was not found in $repository.'
      : result.message;

  Map<String, Object?> toJson() => {
    'version': version,
    'tag': tag,
    'repository': repository,
    'resolvedRepository': resolvedRepository,
    'reason': reason,
    'ok': ok,
    'tagCheck': result.toJson(),
  };
}

class _ReleaseCheckPlan {
  const _ReleaseCheckPlan({
    required this.items,
    required this.skipped,
    required this.warnings,
  });

  static const empty = _ReleaseCheckPlan(items: [], skipped: [], warnings: []);

  final List<_PlannedReleaseCheck> items;
  final List<_SkippedReleaseCheck> skipped;
  final List<String> warnings;

  List<_PlannedReleaseCheck> get changedRecords => [
    ...items,
    for (final skippedCheck in skipped) skippedCheck.check,
  ];

  Map<String, Object?> toJson() => {
    'items': [for (final item in items) item.toJson()],
    'skipped': [for (final item in skipped) item.toJson()],
    'warnings': warnings,
  };
}

class _ReleaseManifestDiff {
  const _ReleaseManifestDiff({required this.items, required this.skipped});

  final List<_PlannedReleaseCheck> items;
  final List<_SkippedReleaseCheck> skipped;
}

class _ReleaseCheckShard {
  const _ReleaseCheckShard({required this.index, required this.total});

  final int index;
  final int total;
}

class _PlannedReleaseCheck {
  const _PlannedReleaseCheck({
    required this.manifestName,
    required this.package,
    required this.sdk,
    required this.release,
    required this.tag,
    required this.reason,
  });

  final String manifestName;
  final SourceManifestPackage package;
  final SourceManifestSdk sdk;
  final SourceManifestRelease release;
  final String tag;
  final String reason;

  Map<String, Object?> toJson() => {
    'manifest': manifestName,
    'package': package.name,
    'sdkLine': sdk.sdkLine,
    'version': release.version,
    'upstreamVersion': release.upstreamVersion,
    'status': release.status,
    'tag': tag,
    'reason': reason,
  };
}

class _SkippedReleaseCheck {
  const _SkippedReleaseCheck({required this.check, required this.skipReason});

  final _PlannedReleaseCheck check;
  final String skipReason;

  Map<String, Object?> toJson() => {
    ...check.toJson(),
    'skipReason': skipReason,
  };
}

class _TaggedPackageMetadataCheck {
  const _TaggedPackageMetadataCheck({
    required this.ok,
    required this.message,
    required this.branch,
    required this.packageManifest,
    required this.packageName,
    required this.show,
    this.package,
  });

  final bool ok;
  final String message;
  final String? branch;
  final PackageManifest? packageManifest;
  final String packageName;
  final PackageManifestPackage? package;
  final _ProcessCheckResult show;

  Map<String, Object?> toJson() => {
    'ok': ok,
    'message': message,
    'package': packageName,
    if (branch != null) 'branch': branch,
    if (packageManifest != null) ...{
      'sdkVersion': packageManifest!.sdkVersion,
      'repositoryBranch': packageManifest!.repositoryBranch,
    },
    if (package != null) ...{
      'version': package!.version,
      'upstreamVersion': package!.upstreamVersion,
      'status': package!.status ?? 'compatible',
      'repositoryPath': package!.repositoryPath,
      'upstreamPath': package!.upstreamPath,
    },
    'show': show.toJson(),
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
    required this.metadataCheck,
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
  final _TaggedPackageMetadataCheck? metadataCheck;
  final _ProcessCheckResult? checkout;
  final _ProcessCheckResult? packageCheck;
  final Map<String, Object?>? packageCheckJson;
  final bool ok;

  String get message {
    if (!tagCheck.ok) {
      return tagCheck.message;
    }
    if (metadataCheck != null && !metadataCheck!.ok) {
      return metadataCheck!.message;
    }
    if (checkout != null && !checkout!.ok) {
      return checkout!.message;
    }
    if (packageCheck != null && !packageCheck!.ok) {
      return packageCheck!.message;
    }
    return packageCheck?.message ??
        checkout?.message ??
        metadataCheck?.message ??
        tagCheck.message;
  }

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
    if (metadataCheck != null) 'metadataCheck': metadataCheck!.toJson(),
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
