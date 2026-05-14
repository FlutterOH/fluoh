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

  Future<PackageIndex> loadPackageIndex({Set<String>? packageNames}) async {
    return packageIndexFromManifests(
      await _readSourcePackageManifests(packageNames: packageNames),
    );
  }

  Future<CompatibilityMatrix> loadCompatibilityMatrix({
    Set<String>? packageNames,
  }) async {
    return compatibilityMatrixFromManifests(
      await _readSourcePackageManifests(packageNames: packageNames),
    );
  }

  Future<List<SourcePackageManifest>> _readSourcePackageManifests({
    Set<String>? packageNames,
  }) async {
    final source = await loadRootManifest();
    final manifests = <SourcePackageManifest>[];
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

@Deprecated('Use SourceIndex instead.')
typedef PubSource = SourceIndex;
