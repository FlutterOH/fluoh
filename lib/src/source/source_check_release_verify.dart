part of 'source_check_command.dart';

extension on SourceCheckCommand {
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
    final tag = release.tag;
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
      upstreamVersion: release.sourceVersion,
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
      final actualUpstreamRef =
          taggedPackage.upstreamRef ?? taggedPackage.upstreamCommit;
      final mismatches = <String>[
        if (actualSdkLine != expectedSdkLine)
          'sdk line is $actualSdkLine, expected $expectedSdkLine',
        if (taggedPackage.version != release.version)
          'release version is ${taggedPackage.version}, expected ${release.version}',
        if (release.upstreamVersion != null &&
            taggedPackage.upstreamVersion != release.upstreamVersion)
          'upstream version is ${taggedPackage.upstreamVersion}, expected ${release.upstreamVersion}',
        if (release.upstreamRef != null &&
            actualUpstreamRef != release.upstreamRef)
          'upstream ref is $actualUpstreamRef, expected ${release.upstreamRef}',
        if (release.upstreamCommit != null &&
            taggedPackage.upstreamCommit != release.upstreamCommit)
          'upstream commit is ${taggedPackage.upstreamCommit}, expected ${release.upstreamCommit}',
        if (taggedPackage.path != package.path)
          'package.path is ${taggedPackage.path}, expected ${package.path}',
        if (actualStatus != expectedStatus)
          'status is ${actualStatus ?? 'compatible'}, expected ${expectedStatus ?? 'compatible'}',
        if (!taggedPackage.matchesReleaseTag(manifest.sdkVersion, tag))
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
}
