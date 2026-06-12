part of 'source_commands.dart';

class _SourceManifestRepository {
  const _SourceManifestRepository({
    required this.path,
    required this.displayPath,
    this.temporary = false,
  });

  final Directory path;
  final String displayPath;
  final bool temporary;

  Future<void> cleanup() async {
    if (temporary) {
      await deleteIfExists(path);
    }
  }
}

class _ReleasedSourcePackages {
  const _ReleasedSourcePackages({
    required this.packages,
    required this.skippedTags,
  });

  final List<_SourceSyncPackage> packages;
  final List<_SourceSyncSkippedTag> skippedTags;
}

class _TaggedPackageManifestRead {
  const _TaggedPackageManifestRead({this.manifest, this.skippedTag});

  final PackageManifest? manifest;
  final _SourceSyncSkippedTag? skippedTag;
}

class _SourceSyncRoutePlan {
  const _SourceSyncRoutePlan({
    required this.manifestName,
    required this.packageName,
    required this.packagePath,
    required this.repository,
    required this.resolvedRepository,
    required this.knownTags,
    required this.discoveredTags,
    required this.tagsToSync,
    this.skippedTags = const <_SourceSyncSkippedTag>[],
  });

  final String manifestName;
  final String packageName;
  final String packagePath;
  final String repository;
  final String resolvedRepository;
  final List<String> knownTags;
  final List<String> discoveredTags;
  final List<String> tagsToSync;
  final List<_SourceSyncSkippedTag> skippedTags;

  String get status => tagsToSync.isNotEmpty
      ? 'sync'
      : skippedTags.isNotEmpty
      ? 'skipped'
      : 'up-to-date';

  Map<String, Object?> toJson() {
    return {
      'manifest': manifestName,
      'package': packageName,
      'packagePath': packagePath,
      'repository': repository,
      'resolvedRepository': resolvedRepository,
      'knownTags': knownTags,
      'discoveredTags': discoveredTags,
      'tagsToSync': tagsToSync,
      'skippedTags': skippedTags.map((tag) => tag.toJson()).toList(),
      'status': status,
    };
  }

  _SourceSyncRoutePlan withAdditionalSkippedTags(
    List<_SourceSyncSkippedTag> additional,
  ) {
    final skippedTagNames = {for (final tag in additional) tag.tag};
    final nextTagsToSync =
        tagsToSync
            .where((tag) => !skippedTagNames.contains(tag))
            .toList(growable: false)
          ..sort();
    final nextSkippedTags = [...skippedTags, ...additional]
      ..sort((a, b) => a.tag.compareTo(b.tag));
    return _SourceSyncRoutePlan(
      manifestName: manifestName,
      packageName: packageName,
      packagePath: packagePath,
      repository: repository,
      resolvedRepository: resolvedRepository,
      knownTags: knownTags,
      discoveredTags: discoveredTags,
      tagsToSync: nextTagsToSync,
      skippedTags: nextSkippedTags,
    );
  }
}

class _SourceSyncSkippedTag {
  const _SourceSyncSkippedTag({
    required this.tag,
    required this.sdkLine,
    required this.reason,
    this.message,
  });

  final String tag;
  final String sdkLine;
  final String reason;
  final String? message;

  Map<String, Object?> toJson() => {
    'tag': tag,
    'sdkLine': sdkLine,
    'reason': reason,
    if (message != null) 'message': message,
  };
}

class _SourceSyncResult {
  const _SourceSyncResult({required this.repository, required this.result});

  final String repository;
  final _SourcePackageMetadataResult result;

  Map<String, Object?> toJson() {
    return {
      'package': result.packageName,
      'repository': repository,
      'manifestPath': result.manifestPath,
      'status': result.skippedFrozen ? 'skipped' : 'synced',
      if (result.frozenReason != null) 'reason': result.frozenReason,
    };
  }
}

class _SourceSyncPackage {
  const _SourceSyncPackage({
    required this.sourceManifestName,
    required this.repository,
    required this.manifest,
    required this.package,
    required this.releaseTag,
  });

  final String sourceManifestName;
  final String repository;
  final PackageManifest manifest;
  final PackageManifestPackage package;
  final String releaseTag;
}

Future<Set<String>> _lsRemoteReleaseTags(
  String repository, {
  required Directory source,
}) async {
  final result = await runGit(
    ['ls-remote', '--tags', repository],
    workingDirectory: source,
    allowFailure: true,
  );
  if (result.exitCode != 0) {
    throw UsageException(
      'Could not list release tags in $repository: ${result.stderr}',
      '',
    );
  }
  final tags = <String>{};
  for (final rawLine in result.stdout.toString().split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) {
      continue;
    }
    final parts = line.split(RegExp(r'\s+'));
    if (parts.length < 2) {
      continue;
    }
    var ref = parts[1];
    if (!ref.startsWith('refs/tags/')) {
      continue;
    }
    ref = ref.substring('refs/tags/'.length);
    if (ref.endsWith('^{}')) {
      ref = ref.substring(0, ref.length - 3);
    }
    try {
      parsePackageReleaseTag(ref);
    } on FormatException {
      continue;
    }
    tags.add(ref);
  }
  return tags;
}

Future<void> _fetchRepositoryTags(
  Directory repository, {
  required String url,
  required List<String> tags,
}) async {
  if (tags.isEmpty) {
    return;
  }
  final refspecs = [
    for (final tag in tags.toSet().toList(growable: false)..sort())
      'refs/tags/$tag:refs/tags/$tag',
  ];
  final result = await runGit(
    ['fetch', '--depth=1', '--no-tags', 'origin', ...refspecs],
    workingDirectory: repository,
    allowFailure: true,
  );
  if (result.exitCode == 0) {
    return;
  }
  final detail = result.stderr.toString().trim();
  throw UsageException(
    detail.isEmpty
        ? 'Could not fetch release tags in $url.'
        : 'Could not fetch release tags in $url: $detail',
    '',
  );
}

String _syncRepositoryDisplayPath(_SourceSyncRoutePlan item) {
  if (localSourceDirectoryFromUrl(item.repository) != null) {
    return item.resolvedRepository;
  }
  if (Directory(item.repository).isAbsolute) {
    return item.resolvedRepository;
  }
  if (_looksLikeRemoteGitUrl(item.repository)) {
    return item.repository;
  }
  return item.resolvedRepository;
}

Set<String> _declaredReleaseTags(
  SourceManifest manifest, {
  required Set<String> packageFilters,
}) {
  final tags = <String>{};
  final package = manifest.package;
  if (packageFilters.isNotEmpty && !packageFilters.contains(package.name)) {
    return tags;
  }
  for (final sdk in package.sdks.values) {
    for (final release in sdk.releases) {
      tags.add(_sourceReleaseTag(package.name, sdk.sdkLine, release));
    }
  }
  return tags;
}

List<String> _filterTagsForPackages(
  Iterable<String> tags, {
  required Set<String> packageFilters,
}) {
  final filtered = tags
      .where((tag) {
        final parsed = parsePackageReleaseTag(tag);
        if (packageFilters.isEmpty) {
          return true;
        }
        return packageFilters.contains(parsed.packageName);
      })
      .toList(growable: false);
  return filtered..sort();
}

Set<String>? _supportedSdkLines(SourceRootManifest root) {
  if (root.sdkReleases.isEmpty) {
    return null;
  }
  return {
    for (final release in root.sdkReleases)
      sdkLineFromSdkVersion(release.version),
  };
}

List<_SourceSyncSkippedTag> _skippedTagsForUnsupportedSdkLines(
  Iterable<String> tags, {
  required Set<String>? supportedSdkLines,
}) {
  if (supportedSdkLines == null) {
    return const <_SourceSyncSkippedTag>[];
  }
  final skipped = <_SourceSyncSkippedTag>[];
  for (final tag in tags) {
    final sdkLine = parsePackageReleaseTag(tag).sdkLine;
    if (supportedSdkLines.contains(sdkLine)) {
      continue;
    }
    skipped.add(
      _SourceSyncSkippedTag(
        tag: tag,
        sdkLine: sdkLine,
        reason: 'sdk-line-not-in-source',
      ),
    );
  }
  skipped.sort((a, b) => a.tag.compareTo(b.tag));
  return skipped;
}

_SourceSyncSkippedTag _skippedTagFor(
  String tag, {
  required String reason,
  String? message,
}) {
  return _SourceSyncSkippedTag(
    tag: tag,
    sdkLine: parsePackageReleaseTag(tag).sdkLine,
    reason: reason,
    message: message,
  );
}

String _sourceSyncSkippedTagMessage(_SourceSyncSkippedTag tag) {
  final detail = tag.message == null ? '' : ': ${tag.message}';
  return switch (tag.reason) {
    'sdk-line-not-in-source' =>
      'Skipped ${tag.tag}: SDK line ${tag.sdkLine} is not declared in source sdk.versions',
    'missing-package-manifest' =>
      'Skipped ${tag.tag}: tag does not contain fluoh.yaml',
    'invalid-package-manifest' =>
      'Skipped ${tag.tag}: package fluoh.yaml is invalid$detail',
    'invalid-package-metadata' =>
      'Skipped ${tag.tag}: package metadata is invalid$detail',
    'tag-metadata-mismatch' =>
      'Skipped ${tag.tag}: tag does not match package metadata',
    'package-path-mismatch' =>
      'Skipped ${tag.tag}: package.path does not match Source Manifest$detail',
    _ => 'Skipped ${tag.tag}: ${tag.reason}$detail',
  };
}

String _sourceReleaseTag(
  String packageName,
  String sdkLine,
  SourceManifestRelease release,
) {
  return packageReleaseTagForPackage(
    packageName: packageName,
    upstreamVersion: release.upstreamVersion,
    sdkVersion: '$sdkLine.0-ohos-0.0.0',
    releaseVersion: release.version,
  );
}

String _resolveSyncRepositoryUrl(Directory source, String url) {
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

Set<String> _multiOptionSet(ArgResults argResults, String name) {
  final values = <String>{};
  for (final value in argResults.multiOption(name)) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw UsageException('--$name values must not be empty.', '');
    }
    values.add(trimmed);
  }
  return values;
}

int _positiveIntOption(
  ArgResults argResults,
  String name, {
  required int defaultValue,
}) {
  final value = argResults.option(name)?.trim();
  if (value == null || value.isEmpty) {
    return defaultValue;
  }
  final parsed = int.tryParse(value);
  if (parsed == null || parsed <= 0) {
    throw UsageException('--$name must be a positive integer.', '');
  }
  return parsed;
}

class _SourcePackageMetadataResult {
  const _SourcePackageMetadataResult({
    required this.packageName,
    required this.manifestPath,
    required this.skippedFrozen,
    this.frozenReason,
  });

  final String packageName;
  final String manifestPath;
  final bool skippedFrozen;
  final String? frozenReason;
}

Future<_SourcePackageMetadataResult> _writeSourcePackageMetadata({
  required Directory source,
  required String manifestName,
  required String packageName,
  required String packageUrl,
  required String packagePath,
  required String upstreamGitUrl,
  required String upstreamVersion,
  required String? upstreamRef,
  required String upstreamCommit,
  required String sdkVersion,
  required String releaseVersion,
  required String releaseTag,
  required String releaseStatus,
  required Never Function(String message) usageException,
}) async {
  if (!const {'compatible', 'experimental', 'broken'}.contains(releaseStatus)) {
    usageException(
      'Expected release status to be compatible, experimental, or broken.',
    );
  }
  try {
    validateReleaseVersion(releaseVersion);
  } on FormatException catch (error) {
    usageException(error.message);
  }
  final sourceManifest = await _readSourceRootManifest(
    source,
    usageException: usageException,
  );
  final sdkLine = sdkLineFromSdkVersion(sdkVersion);
  final supportedSdkLines = _supportedSdkLines(sourceManifest);
  if (supportedSdkLines != null && !supportedSdkLines.contains(sdkLine)) {
    usageException(
      'Package $packageName release $releaseTag targets SDK line $sdkLine, '
      'but source sdk.versions does not declare a matching SDK version.',
    );
  }
  manifestName = _validatedSourceName(manifestName);
  if (manifestName != packageName) {
    usageException(
      'Source manifest route $manifestName cannot sync package $packageName. '
      'Use one route per package, named $packageName.',
    );
  }
  final manifestPath = 'manifests/$manifestName';
  final manifestFile = File('${source.path}/$manifestPath/fluoh.yaml');
  final packageTemplate = SourceManifestPackageTemplate(
    name: packageName,
    path: packagePath,
    upstreamVersion: upstreamVersion,
    upstreamRef: upstreamRef,
    upstreamCommit: upstreamCommit,
    version: releaseVersion,
    sdkLine: sdkLine,
    status: releaseStatus,
  );
  final canonicalTag = packageReleaseTagForPackage(
    packageName: packageName,
    upstreamVersion: upstreamVersion,
    sdkVersion: sdkVersion,
    releaseVersion: releaseVersion,
  );
  if (releaseTag != canonicalTag) {
    usageException(
      'Release tag $releaseTag does not match package metadata; expected '
      '$canonicalTag.',
    );
  }

  final _SourceManifestUpdate manifestUpdate;
  try {
    manifestUpdate = await _updatedSourceManifest(
      manifestFile: manifestFile,
      manifestName: manifestName,
      repositoryUrl: packageUrl,
      upstreamGitUrl: upstreamGitUrl,
      package: packageTemplate,
      usageException: usageException,
    );
  } on FormatException catch (error) {
    usageException(error.message);
  }

  final nextSourceManifest = SourceRootManifestTemplate(
    name: sourceManifest.name,
    description: sourceManifest.description,
    repositoryGitUrl: sourceManifest.repositoryGitUrl,
    sdkRepository: sourceManifest.sdkRepository,
    sdkReleases: sourceManifest.sdkReleases,
    manifests: _updatedManifestRoutes(
      sourceManifest.manifests,
      manifestName: manifestName,
    ),
  );
  final rootFile = File('${source.path}/fluoh.yaml');
  final writes = <File, String>{
    rootFile: sourceRootManifestContent(nextSourceManifest),
  };
  if (!manifestUpdate.skippedFrozen) {
    writes[manifestFile] = sourceManifestToContent(manifestUpdate.manifest);
  }
  try {
    await _writeFilesAtomically(writes);
  } on FileSystemException catch (error) {
    usageException(
      'Could not write source metadata: ${fileSystemMessage(error)}',
    );
  }

  return _SourcePackageMetadataResult(
    packageName: packageName,
    manifestPath: manifestPath,
    skippedFrozen: manifestUpdate.skippedFrozen,
    frozenReason: manifestUpdate.frozenReason,
  );
}

Future<SourceRootManifest> _readSourceRootManifest(
  Directory source, {
  required Never Function(String message) usageException,
}) async {
  final file = File('${source.path}/fluoh.yaml');
  if (!await file.exists()) {
    usageException(
      'Missing fluoh.yaml. Run "fluoh source init ${source.path}" first.',
    );
  }
  try {
    return parseSourceRootManifest(await file.readAsString());
  } on FormatException catch (error) {
    usageException(error.message);
  }
}

Future<void> _writeFilesAtomically(Map<File, String> writes) async {
  if (writes.isEmpty) {
    return;
  }

  final suffix = DateTime.now().microsecondsSinceEpoch;
  final temps = <File, File>{};
  final backups = <File, File?>{};
  final replacedTargets = <File>[];
  try {
    for (final entry in writes.entries) {
      final target = entry.key;
      await target.parent.create(recursive: true);
      final temp = File('${target.path}.fluoh-next-$suffix');
      await temp.writeAsString(entry.value);
      temps[target] = temp;
    }

    for (final target in writes.keys) {
      final temp = temps[target]!;
      if (await target.exists()) {
        final backup = File('${target.path}.fluoh-previous-$suffix');
        await target.rename(backup.path);
        backups[target] = backup;
      } else {
        backups[target] = null;
      }
      await temp.rename(target.path);
      replacedTargets.add(target);
    }
  } catch (_) {
    for (final target in replacedTargets.reversed) {
      if (await target.exists()) {
        await target.delete();
      }
    }
    for (final entry in backups.entries) {
      final backup = entry.value;
      if (backup != null && await backup.exists()) {
        await backup.rename(entry.key.path);
      }
    }
    rethrow;
  } finally {
    for (final temp in temps.values) {
      if (await temp.exists()) {
        await temp.delete();
      }
    }
    for (final backup in backups.values) {
      if (backup != null && await backup.exists()) {
        await backup.delete();
      }
    }
  }
}

Future<_SourceManifestUpdate> _updatedSourceManifest({
  required File manifestFile,
  required String manifestName,
  required String repositoryUrl,
  required String upstreamGitUrl,
  required SourceManifestPackageTemplate package,
  required Never Function(String message) usageException,
}) async {
  if (!await manifestFile.exists()) {
    return _SourceManifestUpdate(
      manifest: parseSourceManifest(
        content: sourceManifestContent(
          SourceManifestTemplate(
            repositoryGitUrl: repositoryUrl,
            upstreamGitUrl: upstreamGitUrl,
            package: package,
          ),
        ),
        label: manifestFile.path,
      ),
    );
  }

  final existing = parseSourceManifest(
    content: await manifestFile.readAsString(),
    label: manifestFile.path,
  );
  if (existing.repositoryGitUrl != repositoryUrl) {
    usageException(
      'Manifest ${existing.name} already uses git URL '
      '${existing.repositoryGitUrl}.',
    );
  }
  if (existing.upstreamGitUrl != upstreamGitUrl) {
    usageException(
      'Manifest ${existing.name} already uses upstream '
      '${existing.upstreamGitUrl}.',
    );
  }
  if (existing.package.name != package.name) {
    usageException(
      'Manifest ${existing.name} already manages package '
      '${existing.package.name}.',
    );
  }

  final currentPackage = existing.package;
  final maintenance = currentPackage.maintenance;
  if (maintenance != null && maintenance.frozen) {
    return _SourceManifestUpdate(
      manifest: existing,
      skippedFrozen: true,
      frozenReason: maintenance.note,
    );
  }
  final release = SourceManifestRelease(
    version: package.version,
    upstreamVersion: package.upstreamVersion,
    upstreamRef: package.upstreamRef,
    upstreamCommit: package.upstreamCommit,
    status: package.status,
  );
  final sdk = SourceManifestSdk(sdkLine: package.sdkLine, releases: [release]);

  if (currentPackage.path != package.path) {
    usageException(
      'Package ${package.name} already uses package.path '
      '${currentPackage.path}.',
    );
  }
  final sdks = {...currentPackage.sdks};
  final currentSdk = sdks[package.sdkLine];
  sdks[package.sdkLine] = currentSdk == null
      ? sdk
      : SourceManifestSdk(
          sdkLine: currentSdk.sdkLine,
          releases: _upsertManifestRelease(currentSdk.releases, release),
        );

  return _SourceManifestUpdate(
    manifest: SourceManifest(
      schemaVersion: existing.schemaVersion,
      repositoryGitUrl: existing.repositoryGitUrl,
      upstreamGitUrl: existing.upstreamGitUrl,
      package: SourceManifestPackage(
        name: currentPackage.name,
        path: currentPackage.path,
        maintenance: currentPackage.maintenance,
        advisory: currentPackage.advisory,
        sdks: sdks,
      ),
    ),
  );
}

class _SourceManifestUpdate {
  const _SourceManifestUpdate({
    required this.manifest,
    this.skippedFrozen = false,
    this.frozenReason,
  });

  final SourceManifest manifest;
  final bool skippedFrozen;
  final String? frozenReason;
}

List<SourceManifestRelease> _upsertManifestRelease(
  List<SourceManifestRelease> releases,
  SourceManifestRelease release,
) {
  final next = releases.toList(growable: true);
  final index = next.indexWhere(
    (existing) =>
        existing.version == release.version &&
        existing.upstreamVersion == release.upstreamVersion,
  );
  if (index == -1) {
    next.add(release);
  } else {
    next[index] = release;
  }
  return next;
}

/// Adds a Source to the persisted tool configuration.
