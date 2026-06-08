import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:pub_semver/pub_semver.dart';

import 'git/package_git.dart';
import 'manifest/pubspec_package.dart';

/// Upstream package target requested by a package workflow command.
class PackageUpstreamTarget {
  /// Creates an upstream target selection.
  const PackageUpstreamTarget({this.version, this.ref});

  /// Upstream package version requested by the user.
  final String? version;

  /// Upstream Git ref requested by the user.
  final String? ref;

  /// Whether the target is explicitly constrained by a version or ref.
  bool get isExplicit => version != null || ref != null;
}

/// Package source snapshot selected from the upstream repository.
class ResolvedPackageUpstreamRef {
  /// Creates a resolved upstream package source snapshot.
  const ResolvedPackageUpstreamRef({
    required this.package,
    required this.commit,
    this.ref,
  });

  /// Package metadata at the selected upstream ref.
  final PubspecPackage package;

  /// Resolved upstream Git commit for [ref], or for the fallback branch HEAD.
  final String commit;

  /// Selected upstream release tag or user-provided ref, when known.
  final String? ref;
}

/// Fetches upstream branch and tag refs from the configured `upstream` remote.
Future<void> fetchUpstreamRefs(Directory repository) async {
  await runGit(['fetch', '--tags', 'upstream'], workingDirectory: repository);
}

/// Fetches upstream branch and tag refs from [upstreamUrl] without writing
/// repository remote configuration.
Future<void> fetchUpstreamRefsFromUrl(
  Directory repository, {
  required String upstreamUrl,
}) async {
  await runGit([
    'fetch',
    '--tags',
    upstreamUrl,
    '+refs/heads/*:refs/remotes/upstream/*',
  ], workingDirectory: repository);
}

/// Fast-forwards the local upstream branch from its remote-tracking branch.
Future<void> synchronizeUpstreamBranch(
  Directory repository, {
  required String branch,
}) async {
  final local = await runGit(
    ['show-ref', '--verify', '--quiet', 'refs/heads/$branch'],
    workingDirectory: repository,
    allowFailure: true,
  );
  if (local.exitCode == 0) {
    await runGit(['checkout', branch], workingDirectory: repository);
  } else {
    await runGit([
      'checkout',
      '-b',
      branch,
      'upstream/$branch',
    ], workingDirectory: repository);
  }
  await runGit([
    'merge',
    '--ff-only',
    'upstream/$branch',
  ], workingDirectory: repository);
}

/// Resolves the package snapshot for [target].
///
/// When [target] is empty, the latest valid package release tag is selected.
/// If no release tag is available, the package at [fallbackRef] is used.
Future<ResolvedPackageUpstreamRef> resolvePackageUpstreamRef({
  required Directory repository,
  required String packageName,
  required String packagePath,
  required String fallbackRef,
  required PackageUpstreamTarget target,
}) async {
  final normalizedPath = _normalizePackagePath(packagePath);
  if (target.version != null && target.ref != null) {
    throw UsageException(
      'Use only one of --upstream-version or --upstream-ref.',
      '',
    );
  }

  if (target.ref != null) {
    final package = await _packageAtRef(
      repository: repository,
      ref: target.ref!,
      packagePath: normalizedPath,
    );
    if (package == null) {
      throw UsageException(
        'Missing pubspec.yaml for $packageName at $normalizedPath on '
            '${target.ref}.',
        '',
      );
    }
    _ensurePackageName(
      package,
      packageName,
      packagePath: normalizedPath,
      ref: target.ref!,
    );
    return ResolvedPackageUpstreamRef(
      package: package,
      ref: target.ref,
      commit: await _revParseCommit(repository, target.ref!),
    );
  }

  final candidates = await packageReleaseRefs(
    repository: repository,
    packageName: packageName,
    packagePath: normalizedPath,
  );
  if (target.version != null) {
    final version = _parseRequestedVersion(target.version!);
    final matches = candidates
        .where((candidate) => candidate.version == version)
        .toList(growable: false);
    if (matches.isEmpty) {
      throw UsageException(
        'No upstream release tag found for $packageName ${target.version}.',
        '',
      );
    }
    return matches.last.toResolved();
  }

  if (candidates.isNotEmpty) {
    return candidates.last.toResolved();
  }

  final package = await _packageAtRef(
    repository: repository,
    ref: fallbackRef,
    packagePath: normalizedPath,
  );
  if (package == null) {
    throw UsageException(
      'Missing pubspec.yaml for $packageName at $normalizedPath on $fallbackRef.',
      '',
    );
  }
  _ensurePackageName(
    package,
    packageName,
    packagePath: normalizedPath,
    ref: fallbackRef,
  );
  return ResolvedPackageUpstreamRef(
    package: package,
    commit: await _revParseCommit(repository, fallbackRef),
  );
}

/// Resolves the package snapshot at [packagePath].
///
/// When [target] is empty, [fallbackRef] is used to identify the package name
/// when possible. If the package path no longer exists on [fallbackRef], the
/// latest valid release tag at that path is selected instead.
Future<ResolvedPackageUpstreamRef> resolvePackageUpstreamRefAtPath({
  required Directory repository,
  required String packagePath,
  required String fallbackRef,
  required PackageUpstreamTarget target,
  String? expectedPackageName,
}) async {
  final normalizedPath = _normalizePackagePath(packagePath);
  if (target.version != null && target.ref != null) {
    throw UsageException(
      'Use only one of --upstream-version or --upstream-ref.',
      '',
    );
  }

  if (target.ref != null) {
    final package = await packageAtUpstreamRef(
      repository: repository,
      ref: target.ref!,
      packagePath: normalizedPath,
    );
    if (package == null) {
      throw UsageException(
        'Missing pubspec.yaml at $normalizedPath on ${target.ref}.',
        '',
      );
    }
    _ensureExpectedPackageName(
      package,
      expectedPackageName,
      packagePath: normalizedPath,
      ref: target.ref!,
    );
    return ResolvedPackageUpstreamRef(
      package: package,
      ref: target.ref,
      commit: await _revParseCommit(repository, target.ref!),
    );
  }

  if (target.version != null) {
    final version = _parseRequestedVersion(target.version!);
    final matches = await packageReleaseRefsAtPath(
      repository: repository,
      packagePath: normalizedPath,
      expectedPackageName: expectedPackageName,
      version: version,
    );
    if (matches.isEmpty) {
      final subject = expectedPackageName == null
          ? 'package at $normalizedPath'
          : '$expectedPackageName at $normalizedPath';
      throw UsageException(
        'No upstream release tag found for $subject ${target.version}.',
        '',
      );
    }
    return matches.last.toResolved();
  }

  final package = await packageAtUpstreamRef(
    repository: repository,
    ref: fallbackRef,
    packagePath: normalizedPath,
  );
  if (package != null) {
    _ensureExpectedPackageName(
      package,
      expectedPackageName,
      packagePath: normalizedPath,
      ref: fallbackRef,
    );
    return resolvePackageUpstreamRef(
      repository: repository,
      packageName: package.name,
      packagePath: normalizedPath,
      fallbackRef: fallbackRef,
      target: target,
    );
  }

  final candidates = await packageReleaseRefsAtPath(
    repository: repository,
    packagePath: normalizedPath,
    expectedPackageName: expectedPackageName,
  );
  if (candidates.isNotEmpty) {
    return candidates.last.toResolved();
  }

  throw UsageException(
    'Missing pubspec.yaml at package path $normalizedPath on $fallbackRef.',
    '',
  );
}

/// Returns valid package release refs sorted by version and tag name.
Future<List<PackageReleaseRef>> packageReleaseRefs({
  required Directory repository,
  required String packageName,
  required String packagePath,
}) async {
  final normalizedPath = _normalizePackagePath(packagePath);
  final tags = (await runGit([
    'tag',
    '--list',
  ], workingDirectory: repository)).stdout.toString().split('\n');
  final candidates = <PackageReleaseRef>[];
  for (final tag
      in tags.map((tag) => tag.trim()).where((tag) => tag.isNotEmpty)) {
    final tagVersion = packageVersionFromReleaseTag(
      tag: tag,
      packageName: packageName,
      rootPackage: normalizedPath == '.',
    );
    if (tagVersion == null) {
      continue;
    }
    final package = await _packageAtRef(
      repository: repository,
      ref: tag,
      packagePath: normalizedPath,
    );
    if (package == null || package.name != packageName) {
      continue;
    }
    if (package.version != tagVersion) {
      continue;
    }
    try {
      candidates.add(
        PackageReleaseRef(
          ref: tag,
          commit: await _revParseCommit(repository, tag),
          version: Version.parse(package.version),
          package: package,
        ),
      );
    } on FormatException {
      continue;
    }
  }
  candidates.sort((a, b) {
    final version = a.version.compareTo(b.version);
    if (version != 0) {
      return version;
    }
    return a.ref.compareTo(b.ref);
  });
  return candidates;
}

/// Returns valid package release refs for a package path sorted by version.
Future<List<PackageReleaseRef>> packageReleaseRefsAtPath({
  required Directory repository,
  required String packagePath,
  String? expectedPackageName,
  Version? version,
}) async {
  final normalizedPath = _normalizePackagePath(packagePath);
  final tags = (await runGit([
    'tag',
    '--list',
  ], workingDirectory: repository)).stdout.toString().split('\n');
  final candidates = <PackageReleaseRef>[];
  for (final tag
      in tags.map((tag) => tag.trim()).where((tag) => tag.isNotEmpty)) {
    final package = await packageAtUpstreamRef(
      repository: repository,
      ref: tag,
      packagePath: normalizedPath,
    );
    if (package == null) {
      continue;
    }
    if (expectedPackageName != null && package.name != expectedPackageName) {
      continue;
    }
    final tagVersion = packageVersionFromReleaseTag(
      tag: tag,
      packageName: package.name,
      rootPackage: normalizedPath == '.',
    );
    if (tagVersion == null || package.version != tagVersion) {
      continue;
    }
    try {
      final parsedVersion = Version.parse(package.version);
      if (version != null && parsedVersion != version) {
        continue;
      }
      candidates.add(
        PackageReleaseRef(
          ref: tag,
          commit: await _revParseCommit(repository, tag),
          version: parsedVersion,
          package: package,
        ),
      );
    } on FormatException {
      continue;
    }
  }
  candidates.sort((a, b) {
    final version = a.version.compareTo(b.version);
    if (version != 0) {
      return version;
    }
    return a.ref.compareTo(b.ref);
  });
  return candidates;
}

/// A valid upstream package release tag.
class PackageReleaseRef {
  /// Creates a package release ref.
  const PackageReleaseRef({
    required this.ref,
    required this.commit,
    required this.version,
    required this.package,
  });

  /// Release tag name.
  final String ref;

  /// Commit pointed to by [ref].
  final String commit;

  /// Parsed package version.
  final Version version;

  /// Package metadata read from [ref].
  final PubspecPackage package;

  /// Converts this release ref to a resolved command target.
  ResolvedPackageUpstreamRef toResolved() {
    return ResolvedPackageUpstreamRef(
      package: package,
      ref: ref,
      commit: commit,
    );
  }
}

/// Extracts a package version from a supported upstream release tag.
String? packageVersionFromReleaseTag({
  required String tag,
  required String packageName,
  required bool rootPackage,
}) {
  final escapedPackage = RegExp.escape(packageName);
  final packageTagPatterns = [
    RegExp('^$escapedPackage-v(.+)\$'),
    RegExp('^${escapedPackage}_v(.+)\$'),
    RegExp('^$escapedPackage-(.+)\$'),
  ];
  final rootTagPatterns = rootPackage
      ? [RegExp(r'^v(.+)$'), RegExp(r'^(.+)$')]
      : const <RegExp>[];
  for (final pattern in [...packageTagPatterns, ...rootTagPatterns]) {
    final match = pattern.firstMatch(tag);
    if (match == null) {
      continue;
    }
    final version = match.group(1)!;
    try {
      Version.parse(version);
      return version;
    } on FormatException {
      continue;
    }
  }
  return null;
}

Version _parseRequestedVersion(String value) {
  try {
    return Version.parse(value);
  } on FormatException {
    throw UsageException('Invalid --upstream-version $value.', '');
  }
}

Future<PubspecPackage?> _packageAtRef({
  required Directory repository,
  required String ref,
  required String packagePath,
}) async {
  return packageAtUpstreamRef(
    repository: repository,
    ref: ref,
    packagePath: packagePath,
  );
}

/// Reads a package pubspec at [ref] and [packagePath].
Future<PubspecPackage?> packageAtUpstreamRef({
  required Directory repository,
  required String ref,
  required String packagePath,
}) async {
  final pubspecPath = packagePath == '.'
      ? 'pubspec.yaml'
      : '${_normalizePackagePath(packagePath)}/pubspec.yaml';
  final result = await runGit(
    ['show', '$ref:$pubspecPath'],
    workingDirectory: repository,
    allowFailure: true,
  );
  if (result.exitCode != 0) {
    return null;
  }
  try {
    return PubspecPackage.fromYaml(result.stdout.toString());
  } on FormatException {
    return null;
  }
}

void _ensureExpectedPackageName(
  PubspecPackage package,
  String? expectedPackageName, {
  required String packagePath,
  required String ref,
}) {
  if (expectedPackageName == null || package.name == expectedPackageName) {
    return;
  }
  _ensurePackageName(
    package,
    expectedPackageName,
    packagePath: packagePath,
    ref: ref,
  );
}

Future<String> _revParseCommit(Directory repository, String ref) async {
  final result = await runGit([
    'rev-parse',
    '$ref^{commit}',
  ], workingDirectory: repository);
  return result.stdout.toString().trim();
}

void _ensurePackageName(
  PubspecPackage package,
  String packageName, {
  required String packagePath,
  required String ref,
}) {
  if (package.name == packageName) {
    return;
  }
  throw UsageException(
    'Package path $packagePath contains ${package.name}, expected '
        '$packageName. Ref: $ref.',
    '',
  );
}

String _normalizePackagePath(String path) {
  final segments = path
      .replaceAll('\\', '/')
      .split('/')
      .where((segment) => segment.isNotEmpty && segment != '.')
      .toList(growable: false);
  return segments.isEmpty ? '.' : segments.join('/');
}
