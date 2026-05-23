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

class SourceIndex {
  const SourceIndex.directory(this.root);

  final Directory root;

  bool get hasRootManifest => File('${root.path}/fluoh.yaml').existsSync();

  bool get hasSdkIndex => hasRootManifest;

  bool get hasPackageIndex => hasRootManifest;

  bool get hasCompatibilityMatrix => hasRootManifest;

  Future<SourceRootManifest> loadRootManifest() async =>
      parseSourceRootManifest(
        await File('${root.path}/fluoh.yaml').readAsString(),
      );

  Future<SdkIndex> loadSdkIndex() async => (await loadRootManifest()).sdkIndex;

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

class SourcePackageRouteIndex {
  const SourcePackageRouteIndex({required this.manifests});

  final Map<String, SourcePackageRouteManifest> manifests;
}

class SourcePackageRouteManifest {
  const SourcePackageRouteManifest({
    required this.name,
    required this.packages,
  });

  final String name;
  final Map<String, List<String>> packages;
}
