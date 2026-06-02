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
  Future<SdkIndex> loadSdkIndex() async => (await loadRootManifest()).sdkIndex;

  /// Loads package implementation data from registered Manifests.
  Future<PackageIndex> loadPackageIndex({
    Set<String>? packageNames,
    Set<String>? manifestNames,
  }) async {
    return packageIndexFromManifests(
      await _readSourcePackageManifests(
        packageNames: packageNames,
        manifestNames: manifestNames,
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

  /// Loads a compact route index of Manifest names to package SDK lines.
  Future<SourcePackageRouteIndex> loadPackageRouteIndex() async {
    final source = await loadRootManifest();
    final manifests = <String, SourcePackageRouteManifest>{};
    final packageOwners = <String, String>{};
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
      final packages = <String, List<String>>{};
      for (final packageName in manifest.packages.keys.toList(
        growable: false,
      )..sort()) {
        final existing = packageOwners[packageName];
        if (existing != null) {
          throw FluohSchemaException(
            'Package $packageName appears in both $existing and $manifestPath.',
          );
        }
        packageOwners[packageName] = manifestPath;
        final package = manifest.packages[packageName]!;
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
        packages[packageName] = sdkLines;
      }
      manifests[route.name] = SourcePackageRouteManifest(
        name: route.name,
        packages: packages,
      );
    }
    return SourcePackageRouteIndex(manifests: manifests);
  }

  Future<List<SourcePackageManifest>> _readSourcePackageManifests({
    Set<String>? packageNames,
    Set<String>? manifestNames,
  }) async {
    final source = await loadRootManifest();
    final manifests = <SourcePackageManifest>[];
    final packageOwners = <String, String>{};
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
      for (final package in manifest.packages.keys) {
        final existing = packageOwners[package];
        if (existing != null) {
          throw FluohSchemaException(
            'Package $package appears in both $existing and $manifestPath.',
          );
        }
        packageOwners[package] = manifestPath;
      }
      manifests.addAll(
        sourcePackageManifestsFromManifest(
          manifest,
          packageNames: packageNames,
        ),
      );
    }
    return manifests;
  }
}

/// Index of package route data for all Manifests in a Source.
class SourcePackageRouteIndex {
  /// Creates an index of package route Manifests.
  const SourcePackageRouteIndex({required this.manifests});

  /// Manifests keyed by route name.
  final Map<String, SourcePackageRouteManifest> manifests;
}

/// Package route data for one Manifest.
class SourcePackageRouteManifest {
  /// Creates package route data for one Manifest.
  const SourcePackageRouteManifest({
    required this.name,
    required this.packages,
  });

  /// Manifest route name.
  final String name;

  /// Package names mapped to SDK lines with compatible releases.
  final Map<String, List<String>> packages;
}
