part of 'package_create_command.dart';

String? _packageRepositoryNameSuggestion(String? packagePath) {
  if (packagePath == null) {
    return null;
  }
  final normalized = _normalizePackagePath(packagePath);
  if (normalized == '.') {
    return null;
  }
  return _pathName(normalized);
}

String _normalizeDirectoryPath(String path) {
  final normalizedSeparators = path.replaceAll('\\', '/');
  final absolutePrefix = normalizedSeparators.startsWith('/') ? '/' : '';
  final segments = <String>[];
  for (final segment in normalizedSeparators.split('/')) {
    if (segment.isEmpty || segment == '.') {
      continue;
    }
    if (segment == '..') {
      if (segments.isNotEmpty && segments.last != '..') {
        segments.removeLast();
      } else if (absolutePrefix.isEmpty) {
        segments.add(segment);
      }
      continue;
    }
    segments.add(segment);
  }

  final normalized = '$absolutePrefix${segments.join('/')}';
  final nativePath = Platform.pathSeparator == '/'
      ? normalized
      : normalized.replaceAll('/', Platform.pathSeparator);
  if (nativePath.isNotEmpty) {
    return nativePath;
  }
  return absolutePrefix.isEmpty ? '.' : Platform.pathSeparator;
}

class _SelectedPackage {
  const _SelectedPackage({
    required this.package,
    required this.path,
    this.upstreamCommit,
    this.upstreamRef,
  });

  final PubspecPackage package;
  final String path;
  final String? upstreamCommit;
  final String? upstreamRef;
}

Future<List<_SelectedPackage>> _selectPackagesForTarget({
  required Directory repository,
  required List<String> packagePaths,
  required String fallbackRef,
  required PackageUpstreamTarget target,
}) async {
  final paths = packagePaths.isEmpty ? const ['.'] : packagePaths;
  final selected = <_SelectedPackage>[];
  final seenPackages = <String>{};
  for (final path in paths) {
    final upstreamRef = await _resolveSelectedPackageUpstreamRef(
      repository: repository,
      packagePath: path,
      fallbackRef: fallbackRef,
      target: target,
    );
    final package = upstreamRef.package;
    if (!seenPackages.add(package.name)) {
      throw UsageException(
        'Package ${package.name} was selected more than once.',
        '',
      );
    }
    selected.add(
      _SelectedPackage(
        package: upstreamRef.package,
        path: path,
        upstreamCommit: upstreamRef.commit,
        upstreamRef: upstreamRef.ref,
      ),
    );
  }
  return selected;
}

Future<ResolvedPackageUpstreamRef> _resolveSelectedPackageUpstreamRef({
  required Directory repository,
  required String packagePath,
  required String fallbackRef,
  required PackageUpstreamTarget target,
}) async {
  try {
    return await resolvePackageUpstreamRefAtPath(
      repository: repository,
      packagePath: packagePath,
      fallbackRef: fallbackRef,
      target: target,
    );
  } on UsageException {
    if (target.isExplicit) {
      rethrow;
    }
    final package = await _readSelectedPackage(
      repository: repository,
      packagePath: packagePath,
    );
    return resolvePackageUpstreamRef(
      repository: repository,
      packageName: package.name,
      packagePath: packagePath,
      fallbackRef: fallbackRef,
      target: target,
    );
  }
}

Future<void> _warnForSelectedPackageSdkCompatibility({
  required Directory repository,
  required List<_SelectedPackage> selectedPackages,
  required Directory sdkDirectory,
  required TerminalOutput output,
}) async {
  final warnings = await packageSdkCompatibilityWarnings(
    repository: repository,
    selectedPackages: selectedPackages
        .map(
          (selected) => SelectedPackageForSdkCompatibility(
            package: selected.package,
            path: selected.path,
            upstreamRef: selected.upstreamRef,
          ),
        )
        .toList(),
    sdkDirectory: sdkDirectory,
  );
  for (final warning in warnings) {
    output.warning(warning.message);
    output.next(warning.nextStep);
  }
}

PackageRepositoryDocPackage _docPackageForSelection({
  required _SelectedPackage selectedPackage,
  required String repositoryUrl,
  PackageImplementationRecommendation? implementationRecommendation,
}) {
  return PackageRepositoryDocPackage(
    name: selectedPackage.package.name,
    version: selectedPackage.package.version,
    packagePath: selectedPackage.path,
    repositoryUrl: repositoryUrl,
    implementationRecommendation: implementationRecommendation,
  );
}

String _normalizePackagePath(String path) {
  final segments = _pathSegments(path);
  if (segments.isEmpty) {
    return '.';
  }
  return segments.join('/');
}

List<String> _pathSegments(String path) {
  return path
      .replaceAll('\\', '/')
      .split('/')
      .where((segment) => segment.isNotEmpty && segment != '.')
      .toList(growable: false);
}

String _pathName(String path) {
  final segments = _pathSegments(path);
  return segments.isEmpty ? path : segments.last;
}

Future<PubspecPackage> _readSelectedPackage({
  required Directory repository,
  required String packagePath,
}) async {
  final directory = packageDirectory(repository, packagePath);
  final pubspec = File('${directory.path}/pubspec.yaml');
  if (await pubspec.exists()) {
    return readPubspecPackage(directory);
  }

  if (packagePath == '.' || packagePath.isEmpty) {
    final candidates = await _packageSelectionCandidates(repository);
    final candidateHelp = _packageSelectionCandidateHelp(candidates);
    throw UsageException(
      'Missing pubspec.yaml at the upstream repository root. '
          'For packages below the root, select package paths with '
          '"--package-path <package-path>".'
          '$candidateHelp',
      '',
    );
  }
  throw UsageException(
    'Missing pubspec.yaml at package path $packagePath.',
    '',
  );
}

Future<List<_PackageSelectionCandidate>> _packageSelectionCandidates(
  Directory repository,
) async {
  final candidates = <_PackageSelectionCandidate>[];
  if (!await repository.exists()) {
    return candidates;
  }
  final pending = <Directory>[repository];
  while (pending.isNotEmpty) {
    final directory = pending.removeLast();
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is Directory) {
        final path = _relativeCandidatePath(repository, entity);
        if (!_shouldSkipCandidatePath(path)) {
          pending.add(entity);
        }
        continue;
      }
      if (entity is! File || !_isPubspecFile(entity)) {
        continue;
      }
      final path = _relativeCandidatePath(repository, entity.parent);
      if (_shouldSkipCandidatePath(path)) {
        continue;
      }
      try {
        final package = await readPubspecPackage(entity.parent);
        final refs = await packageReleaseRefs(
          repository: repository,
          packageName: package.name,
          packagePath: path,
        );
        candidates.add(
          _PackageSelectionCandidate(
            package: package,
            path: path,
            latestRef: refs.isEmpty ? null : refs.last,
          ),
        );
      } on Object {
        // Ignore malformed nested pubspec files while building selection help.
      }
    }
  }
  candidates.sort((a, b) => a.path.compareTo(b.path));
  return candidates;
}

String _relativeCandidatePath(Directory repository, Directory directory) {
  final root = repository.absolute.path;
  final path = directory.absolute.path;
  if (path == root) {
    return '.';
  }
  if (path.startsWith('$root${Platform.pathSeparator}')) {
    return _normalizePackagePath(path.substring(root.length + 1));
  }
  return _normalizePackagePath(path);
}

String _packageSelectionCandidateHelp(
  List<_PackageSelectionCandidate> candidates,
) {
  if (candidates.isEmpty) {
    return '';
  }
  final visible = candidates.take(20).map((candidate) {
    final package = candidate.package;
    return [
      '\n- ${package.name} ${package.version} at ${candidate.path}',
      if (package.sdkConstraint != null) ' (Dart ${package.sdkConstraint})',
      if (candidate.latestRef != null)
        ' [latest tag ${candidate.latestRef!.ref}]',
      ': --package-path ${candidate.path} --repository-name ${package.name}',
    ].join();
  }).join();
  final hidden = candidates.length > 20
      ? '\n- ... ${candidates.length - 20} more package candidates'
      : '';
  return '\nCandidate packages:$visible$hidden';
}

bool _isPubspecFile(File file) {
  final normalized = file.path.replaceAll('\\', '/');
  return normalized.endsWith('/pubspec.yaml');
}

bool _shouldSkipCandidatePath(String path) {
  final segments = _pathSegments(path);
  return segments.any(
    (segment) => const {
      '.dart_tool',
      '.git',
      '.idea',
      'build',
      'example',
      'examples',
      'node_modules',
    }.contains(segment),
  );
}

class _PackageSelectionCandidate {
  const _PackageSelectionCandidate({
    required this.package,
    required this.path,
    required this.latestRef,
  });

  final PubspecPackage package;
  final String path;
  final PackageReleaseRef? latestRef;
}
