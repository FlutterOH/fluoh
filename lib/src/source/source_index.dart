import 'dart:io';

import '../schema/schema.dart';

export '../schema/schema.dart'
    show
        CompatibilityMatrix,
        CompatibilityVersion,
        PackageImplementation,
        PackageEntry,
        PackageIndex,
        SdkIndex,
        SdkRelease,
        SourceManifest,
        SourceManifestPackage,
        SourceManifestRelease,
        SourceManifestRoute,
        SourcePackageAdvisory,
        SourcePackageAlternative,
        SourcePackageMaintenance,
        SourceCompatibilityStatus,
        SourceRootManifest,
        SourcePackageManifest,
        SourceSdkIndex;

/// File-backed reader for a FlutterOH Source repository.
///
/// A Source repository contains a root `fluoh.yaml` and package Manifests under
/// `manifests/<name>/fluoh.yaml`. This class validates and expands that data
/// into the indexes consumed by SDK and dependency commands.
class SourceIndex {
  /// Creates a Source reader rooted at [root].
  const SourceIndex.directory(this.root);

  /// Source repository root directory.
  final Directory root;

  /// Whether the root Source manifest exists.
  bool get hasRootManifest => File('${root.path}/fluoh.yaml').existsSync();

  /// Whether SDK index data can be read from this Source.
  bool get hasSdkIndex => hasRootManifest;

  /// Whether package index data can be read from this Source.
  bool get hasPackageIndex => hasRootManifest;

  /// Whether compatibility matrix data can be read from this Source.
  bool get hasCompatibilityMatrix => hasRootManifest;

  /// Loads and validates the root Source manifest.
  Future<SourceRootManifest> loadRootManifest() async =>
      parseSourceRootManifest(
        await File('${root.path}/fluoh.yaml').readAsString(),
      );

  /// Loads SDK release data from the root Source manifest.
  Future<SdkIndex> loadSdkIndex() async {
    final index = (await loadRootManifest()).sdkIndex;
    return SdkIndex(
      schemaVersion: index.schemaVersion,
      releases: [
        for (final release in index.releases)
          _resolveSourceRelativeSdkRepository(release),
      ],
    );
  }

  /// Loads package implementation data from registered Manifests.
  Future<PackageIndex> loadPackageIndex({
    Set<String>? packageNames,
    Set<String>? manifestNames,
    Set<String> releaseStatuses = compatibleDependencyReleaseStatuses,
  }) async {
    return packageIndexFromManifests(
      await _readSourcePackageManifests(
        packageNames: packageNames,
        manifestNames: manifestNames,
        releaseStatuses: releaseStatuses,
      ),
    );
  }

  /// Loads package compatibility buckets from registered Manifests.
  Future<CompatibilityMatrix> loadCompatibilityMatrix({
    Set<String>? packageNames,
    Set<String>? manifestNames,
  }) async {
    return compatibilityMatrixFromManifests(
      await _readSourcePackageManifests(
        packageNames: packageNames,
        manifestNames: manifestNames,
      ),
    );
  }

  /// Loads a compact route index of package names to SDK lines.
  Future<SourcePackageRouteIndex> loadPackageRouteIndex() async {
    final source = await loadRootManifest();
    final manifests = <String, SourcePackageRouteManifest>{};
    for (final route in source.manifests) {
      final manifestPath = 'manifests/${route.name}/fluoh.yaml';
      final manifest = parseSourceManifest(
        content: await File('${root.path}/$manifestPath').readAsString(),
        label: manifestPath,
      );
      if (manifest.name != route.name) {
        throw FluohSchemaException(
          '$manifestPath name must match source manifest route ${route.name}.',
        );
      }
      final package = manifest.package;
      if (package.name != route.name) {
        throw FluohSchemaException(
          '$manifestPath package.name must match source manifest route '
          '${route.name}.',
        );
      }
      final sdkLines =
          package.sdks.values
              .where(
                (sdk) => sdk.releases.any(
                  (release) => release.status == 'compatible',
                ),
              )
              .map((sdk) => sdk.sdkLine)
              .toSet()
              .toList(growable: false)
            ..sort();
      manifests[route.name] = SourcePackageRouteManifest(
        name: route.name,
        packageName: package.name,
        sdkLines: sdkLines,
      );
    }
    return SourcePackageRouteIndex(manifests: manifests);
  }

  SdkRelease _resolveSourceRelativeSdkRepository(SdkRelease release) {
    final repository = release.repository;
    if (_isNonRelativeRepository(repository)) {
      return release;
    }
    return SdkRelease(
      version: release.version,
      versionSeries: release.versionSeries,
      flutterVersion: release.flutterVersion,
      channel: release.channel,
      repository: root.absolute.uri.resolve(repository).toFilePath(),
      tag: release.tag,
      publishedAt: release.publishedAt,
      sourceName: release.sourceName,
      sourcePriority: release.sourcePriority,
    );
  }

  bool _isNonRelativeRepository(String repository) {
    return repository.startsWith('/') ||
        repository.contains(':') ||
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(repository);
  }

  Future<List<SourcePackageManifest>> _readSourcePackageManifests({
    Set<String>? packageNames,
    Set<String>? manifestNames,
    Set<String> releaseStatuses = compatibleDependencyReleaseStatuses,
  }) async {
    final source = await loadRootManifest();
    final manifests = <SourcePackageManifest>[];
    for (final route in source.manifests) {
      if (manifestNames != null && !manifestNames.contains(route.name)) {
        continue;
      }
      final manifestPath = 'manifests/${route.name}/fluoh.yaml';
      final manifest = parseSourceManifest(
        content: await File('${root.path}/$manifestPath').readAsString(),
        label: manifestPath,
      );
      if (manifest.name != route.name) {
        throw FluohSchemaException(
          '$manifestPath name must match source manifest route ${route.name}.',
        );
      }
      if (manifest.package.name != route.name) {
        throw FluohSchemaException(
          '$manifestPath package.name must match source manifest route '
          '${route.name}.',
        );
      }
      manifests.addAll(
        sourcePackageManifestsFromManifest(
          manifest,
          packageNames: packageNames,
          releaseStatuses: releaseStatuses,
        ),
      );
    }
    return manifests;
  }
}

/// Index of package route data for all package Manifests in a Source.
class SourcePackageRouteIndex {
  /// Creates an index of package route Manifests.
  const SourcePackageRouteIndex({required this.manifests});

  /// Package Manifests keyed by route name.
  final Map<String, SourcePackageRouteManifest> manifests;
}

/// Package route data for one Manifest.
class SourcePackageRouteManifest {
  /// Creates package route data for one Manifest.
  const SourcePackageRouteManifest({
    required this.name,
    required this.packageName,
    required this.sdkLines,
  });

  /// Manifest route name.
  final String name;

  /// Package name exposed by this route.
  final String packageName;

  /// SDK lines with compatible releases.
  final List<String> sdkLines;
}
