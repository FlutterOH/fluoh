part of 'source_index.dart';

/// Builds the merged package index consumed by dependency commands.
PackageIndex packageIndexFromManifests(Iterable<SourcePackageManifest> items) {
  final packages = <String, PackageEntry>{};
  for (final manifest in items) {
    final existing = packages[manifest.name];
    if (existing == null) {
      packages[manifest.name] = PackageEntry(
        repository: manifest.repository,
        upstream: manifest.upstream,
        implementations: manifest.implementations,
        compatibility: manifest.compatibility,
        sourceNames: _sourceNamesFromImplementations(manifest.implementations),
        advisory: manifest.advisory,
        maintenance: manifest.maintenance,
      );
      continue;
    }
    packages[manifest.name] = PackageEntry(
      repository: existing.repository,
      upstream: existing.upstream,
      implementations: [
        ...existing.implementations,
        ...manifest.implementations,
      ],
      compatibility: [...existing.compatibility, ...manifest.compatibility],
      sourceNames: _sortedPackageSourceNames(
        existing.sourceNames,
        _sourceNamesFromImplementations(manifest.implementations),
      ),
      advisory: existing.advisory ?? manifest.advisory,
      maintenance: existing.maintenance ?? manifest.maintenance,
    );
  }
  return PackageIndex(schemaVersion: 1, packages: packages);
}

List<String> _sourceNamesFromImplementations(
  Iterable<PackageImplementation> implementations,
) {
  return _sortedPackageSourceNames(
    implementations.map((implementation) => implementation.sourceName).nonNulls,
  );
}

List<String> _sortedPackageSourceNames(
  Iterable<String> first, [
  Iterable<String> second = const <String>[],
]) {
  return <String>{...first, ...second}.toList(growable: false)..sort();
}

/// Builds a compatibility matrix from package Manifest records.
CompatibilityMatrix compatibilityMatrixFromManifests(
  Iterable<SourcePackageManifest> items,
) {
  final versions = <String, List<String>>{};
  for (final manifest in items) {
    for (final status in manifest.compatibility) {
      if (status.status != 'implemented') {
        continue;
      }
      versions.putIfAbsent(status.sdkLine, () => []).add(manifest.name);
    }
  }

  return CompatibilityMatrix(
    schemaVersion: 1,
    sdkVersions: versions.map(
      (sdkLine, packages) => MapEntry(
        sdkLine,
        CompatibilityVersion(
          native: const <String>[],
          implemented: _sortedPackageNames(packages),
          blocked: const <String>[],
        ),
      ),
    ),
  );
}
