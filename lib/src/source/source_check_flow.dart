part of 'source_check_command.dart';

extension on SourceCheckCommand {
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
}
