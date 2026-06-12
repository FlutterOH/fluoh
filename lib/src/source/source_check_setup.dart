part of 'source_check_command.dart';

extension on SourceCheckCommand {
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
}
