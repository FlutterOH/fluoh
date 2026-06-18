part of 'package_port_command.dart';

Future<PackageImplementationRecommendation?>
_implementationRecommendationForSelectedPackage({
  required Directory repository,
  required _SelectedPackage selected,
  required String missingPlatform,
}) async {
  final discovery = await discoverPackageSupportCandidates(
    repository: repository,
    missingPlatform: missingPlatform,
  );
  for (final candidate in discovery.candidates) {
    if (candidate.name == selected.package.name &&
        candidate.path == selected.path) {
      return candidate.implementationRecommendation(missingPlatform);
    }
  }
  return null;
}

Future<_DefaultBranchPackageVersionWarning?>
_defaultBranchPackageVersionWarning({
  required Directory repository,
  required _SelectedPackage selected,
  required String upstreamBranch,
  required PackageUpstreamTarget upstreamTarget,
}) async {
  final selectedRef = selected.upstreamRef;
  if (upstreamTarget.isExplicit || selectedRef == null) {
    return null;
  }
  final defaultBranchPackage = await packageAtUpstreamRef(
    repository: repository,
    ref: upstreamBranch,
    packagePath: selected.path,
  );
  if (defaultBranchPackage == null ||
      defaultBranchPackage.name != selected.package.name ||
      !_isPackageVersionAheadOrDifferent(
        defaultBranchPackage.version,
        selected.package.version,
      )) {
    return null;
  }
  return _DefaultBranchPackageVersionWarning(
    packageName: selected.package.name,
    packagePath: selected.path,
    selectedRef: selectedRef,
    selectedVersion: selected.package.version,
    defaultBranch: upstreamBranch,
    defaultBranchVersion: defaultBranchPackage.version,
  );
}

bool _isPackageVersionAheadOrDifferent(
  String defaultBranchVersion,
  String selectedVersion,
) {
  if (defaultBranchVersion == selectedVersion) {
    return false;
  }
  try {
    return Version.parse(
          defaultBranchVersion,
        ).compareTo(Version.parse(selectedVersion)) >=
        0;
  } on FormatException {
    return true;
  }
}

Directory _packagePortDestination({
  required FluohEnvironment environment,
  required String? output,
  required String repositoryName,
}) {
  final trimmedOutput = output?.trim();
  if (trimmedOutput != null && trimmedOutput.isNotEmpty) {
    final outputDirectory = Directory(trimmedOutput);
    final path = outputDirectory.isAbsolute
        ? trimmedOutput
        : '${environment.workingDirectory.path}/$trimmedOutput';
    return Directory(_normalizeDirectoryPath(path));
  }
  return Directory(
    _normalizeDirectoryPath(
      '${environment.workingDirectory.path}/$repositoryName',
    ),
  );
}

enum _PackagePortPlanCloneMode { shallow, partial, full }

Future<_PackagePortPlanCloneMode> _cloneUpstreamForPackagePortPlan({
  required String upstream,
  required Directory scratchRepository,
  required List<String> packagePaths,
  required PackageUpstreamTarget upstreamTarget,
}) async {
  if (upstreamTarget.ref == null) {
    final sparsePaths = _packagePortPlanSparsePaths(packagePaths);
    if (sparsePaths.isNotEmpty) {
      final sparse = await runGit([
        'clone',
        '--quiet',
        '--depth',
        '1',
        '--single-branch',
        '--filter=blob:none',
        '--sparse',
        upstream,
        scratchRepository.path,
      ], allowFailure: true);
      if (sparse.exitCode == 0 &&
          await _setPackagePortPlanSparsePaths(
            scratchRepository,
            sparsePaths,
          )) {
        return _PackagePortPlanCloneMode.shallow;
      }
      if (await scratchRepository.exists()) {
        await scratchRepository.delete(recursive: true);
      }
    }

    final shallow = await runGit([
      'clone',
      '--quiet',
      '--depth',
      '1',
      '--single-branch',
      upstream,
      scratchRepository.path,
    ], allowFailure: true);
    if (shallow.exitCode == 0) {
      return _PackagePortPlanCloneMode.shallow;
    }
    if (await scratchRepository.exists()) {
      await scratchRepository.delete(recursive: true);
    }
  }

  final partial = await runGit([
    'clone',
    '--quiet',
    '--filter=blob:none',
    '--no-checkout',
    upstream,
    scratchRepository.path,
  ], allowFailure: true);
  if (partial.exitCode == 0) {
    return _PackagePortPlanCloneMode.partial;
  }
  if (await scratchRepository.exists()) {
    await scratchRepository.delete(recursive: true);
  }
  await runGit(['clone', '--quiet', upstream, scratchRepository.path]);
  return _PackagePortPlanCloneMode.full;
}

List<String> _packagePortPlanSparsePaths(List<String> packagePaths) {
  final paths = packagePaths
      .map(_normalizePackagePath)
      .where((path) => path != '.')
      .toList(growable: false);
  return paths;
}

Future<bool> _setPackagePortPlanSparsePaths(
  Directory repository,
  List<String> sparsePaths,
) async {
  final result = await runGit(
    ['sparse-checkout', 'set', ...sparsePaths],
    workingDirectory: repository,
    allowFailure: true,
  );
  return result.exitCode == 0;
}

Future<void> _prepareUpstreamRefsForPackagePortPlan({
  required Directory repository,
  required _PackagePortPlanCloneMode cloneMode,
  required List<String> packagePaths,
  required String upstreamBranch,
  required PackageUpstreamTarget upstreamTarget,
}) async {
  if (cloneMode == _PackagePortPlanCloneMode.shallow) {
    final selectedTagsPrepared = await _prepareSelectedPackageReleaseTags(
      repository: repository,
      packagePaths: packagePaths,
      upstreamBranch: upstreamBranch,
      upstreamTarget: upstreamTarget,
    );
    if (selectedTagsPrepared) {
      return;
    }
  }
  await fetchUpstreamRefs(repository);
}

Future<bool> _prepareSelectedPackageReleaseTags({
  required Directory repository,
  required List<String> packagePaths,
  required String upstreamBranch,
  required PackageUpstreamTarget upstreamTarget,
}) async {
  final paths = packagePaths.isEmpty ? const ['.'] : packagePaths;
  for (final path in paths) {
    final package = await packageAtUpstreamRef(
      repository: repository,
      ref: upstreamBranch,
      packagePath: path,
    );
    if (package == null) {
      return false;
    }
    final fetched = await _fetchLatestValidPackageReleaseTag(
      repository: repository,
      package: package,
      packagePath: path,
      upstreamTarget: upstreamTarget,
    );
    if (!fetched) {
      return false;
    }
  }
  return true;
}

Future<bool> _fetchLatestValidPackageReleaseTag({
  required Directory repository,
  required PubspecPackage package,
  required String packagePath,
  required PackageUpstreamTarget upstreamTarget,
}) async {
  final requestedVersion = upstreamTarget.version == null
      ? null
      : _tryParsePackageVersion(upstreamTarget.version!);
  if (upstreamTarget.version != null && requestedVersion == null) {
    return true;
  }
  final tags = await _remotePackageReleaseTags(
    repository: repository,
    packageName: package.name,
    rootPackage: _normalizePackagePath(packagePath) == '.',
    requestedVersion: requestedVersion,
  );
  if (tags == null) {
    return false;
  }
  for (final tag in tags.reversed) {
    final fetched = await _fetchUpstreamTag(repository, tag.ref);
    if (!fetched) {
      return false;
    }
    final tagPackage = await packageAtUpstreamRef(
      repository: repository,
      ref: tag.ref,
      packagePath: packagePath,
    );
    if (tagPackage == null || tagPackage.name != package.name) {
      continue;
    }
    if (tagPackage.version != tag.version.toString()) {
      continue;
    }
    return true;
  }
  return true;
}

Future<List<_RemotePackageReleaseTag>?> _remotePackageReleaseTags({
  required Directory repository,
  required String packageName,
  required bool rootPackage,
  required Version? requestedVersion,
}) async {
  final result = await runGit(
    ['ls-remote', '--tags', 'upstream'],
    workingDirectory: repository,
    allowFailure: true,
  );
  if (result.exitCode != 0) {
    return null;
  }
  final tags = <_RemotePackageReleaseTag>[];
  for (final line in result.stdout.toString().split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length < 2) {
      continue;
    }
    final ref = parts[1];
    if (!ref.startsWith('refs/tags/') || ref.endsWith('^{}')) {
      continue;
    }
    final tag = ref.substring('refs/tags/'.length);
    final version = packageVersionFromReleaseTag(
      tag: tag,
      packageName: packageName,
      rootPackage: rootPackage,
    );
    if (version == null) {
      continue;
    }
    final parsedVersion = _tryParsePackageVersion(version);
    if (parsedVersion == null) {
      continue;
    }
    if (requestedVersion != null && parsedVersion != requestedVersion) {
      continue;
    }
    tags.add(_RemotePackageReleaseTag(ref: tag, version: parsedVersion));
  }
  tags.sort((a, b) {
    final version = a.version.compareTo(b.version);
    if (version != 0) {
      return version;
    }
    return a.ref.compareTo(b.ref);
  });
  return tags;
}

Future<bool> _fetchUpstreamTag(Directory repository, String tag) async {
  final result = await runGit(
    ['fetch', '--depth', '1', 'upstream', 'refs/tags/$tag:refs/tags/$tag'],
    workingDirectory: repository,
    allowFailure: true,
  );
  return result.exitCode == 0;
}

Version? _tryParsePackageVersion(String value) {
  try {
    return Version.parse(value);
  } on FormatException {
    return null;
  }
}

class _RemotePackageReleaseTag {
  const _RemotePackageReleaseTag({required this.ref, required this.version});

  final String ref;
  final Version version;
}
