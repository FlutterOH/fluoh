part of 'source_check_command.dart';

extension on SourceCheckCommand {
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
    final package = head.package;
    final basePackage = baseManifest.package.name == package.name
        ? baseManifest.package
        : null;
    if (basePackage == null) {
      checks.addAll(
        _releaseChecksForPackage(
          manifestName: headManifest.routeName,
          package: package,
          reason: 'package-added',
        ),
      );
      skipped.addAll(
        _skippedReleaseChecksForPackage(
          manifestName: headManifest.routeName,
          package: baseManifest.package,
          reason: 'package-deleted',
        ),
      );
      return _ReleaseManifestDiff(items: checks, skipped: skipped);
    }
    if (basePackage.path != package.path) {
      checks.addAll(
        _releaseChecksForPackage(
          manifestName: headManifest.routeName,
          package: package,
          reason: 'package-path-changed',
        ),
      );
      return _ReleaseManifestDiff(items: checks, skipped: skipped);
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
          _releaseTag(package.name, sdk.sdkLine, release): _releaseFingerprint(
            release,
          ),
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
        final tag = _releaseTag(basePackage.name, baseSdk.sdkLine, baseRelease);
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
    return _ReleaseManifestDiff(items: checks, skipped: skipped);
  }

  List<_PlannedReleaseCheck> _allReleaseChecksForManifest(
    _CheckedSourceManifest manifest, {
    required String reason,
  }) {
    return _releaseChecksForPackage(
      manifestName: manifest.routeName,
      package: manifest.manifest.package,
      reason: reason,
    );
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
}
