import 'dart:io';

import 'package:yaml/yaml.dart';

import '../sdk/sdk_release.dart';

class SourceIndex {
  const SourceIndex.directory(this.root);

  final Directory root;

  bool get hasSdkIndex => File('${root.path}/sdk/releases.yaml').existsSync();

  bool get hasPackageIndex =>
      File('${root.path}/packages/repositories.yaml').existsSync();

  bool get hasCompatibilityMatrix =>
      File('${root.path}/packages/repositories.yaml').existsSync();

  Future<SdkIndex> loadSdkIndex() async {
    return _readSourceSdkIndex();
  }

  Future<PackageIndex> loadPackageIndex() async {
    return _readSourcePackageIndex();
  }

  Future<CompatibilityMatrix> loadCompatibilityMatrix() async {
    return _readSourceCompatibilityMatrix();
  }

  Future<SdkIndex> _readSourceSdkIndex() async {
    final yaml = await _readSourceYaml('sdk/releases.yaml');
    final repository = _requiredString(yaml, 'repositoryUrl');
    final releases = yaml['releases'];
    if (releases is! List) {
      throw const FormatException('SDK source releases must be a list.');
    }

    return SdkIndex(
      schemaVersion: yaml['schema'] as int? ?? 1,
      releases: releases
          .map((value) {
            final release = _objectMap(value, 'SDK source release');
            return SdkRelease(
              version: _requiredString(release, 'version'),
              versionSeries: _requiredString(release, 'versionSeries'),
              flutterVersion: _flutterVersionFromSdkVersion(
                _requiredString(release, 'version'),
              ),
              channel: _requiredString(release, 'status'),
              repository: repository,
              tag: _requiredString(release, 'tag'),
            );
          })
          .toList(growable: false),
    );
  }

  Future<PackageIndex> _readSourcePackageIndex() async {
    final manifests = await _readSourcePackageManifests();
    return PackageIndex(
      schemaVersion: 1,
      packages: {
        for (final manifest in manifests)
          manifest.name: PackageEntry(
            upstream: manifest.upstream,
            adapters: manifest.adapters,
          ),
      },
    );
  }

  Future<CompatibilityMatrix> _readSourceCompatibilityMatrix() async {
    final manifests = await _readSourcePackageManifests();
    final versions = <String, ({List<String> adapted, List<String> blocked})>{};
    for (final manifest in manifests) {
      for (final status in manifest.compatibility) {
        final version = versions.putIfAbsent(
          status.sdkVersion,
          () => (adapted: <String>[], blocked: <String>[]),
        );
        switch (status.status) {
          case 'broken':
            version.blocked.add(manifest.name);
          case 'compatible':
          case 'experimental':
            version.adapted.add(manifest.name);
          default:
            throw FormatException(
              'Expected package manifest status to be compatible, '
              'experimental, or broken.',
            );
        }
      }
    }

    return CompatibilityMatrix(
      schemaVersion: 1,
      sdkVersions: versions.map(
        (sdkVersion, packages) => MapEntry(
          sdkVersion,
          CompatibilityVersion(
            native: const [],
            adapted: packages.adapted.toSet().toList(growable: false)..sort(),
            blocked: packages.blocked.toSet().toList(growable: false)..sort(),
          ),
        ),
      ),
    );
  }

  Future<List<_SourcePackageManifest>> _readSourcePackageManifests() async {
    final repositoryIndex = await _readSourceYaml('packages/repositories.yaml');
    final repositories = repositoryIndex['repositories'];
    if (repositories is! List) {
      throw const FormatException(
        'Package source repositories must be a list.',
      );
    }

    final manifests = <_SourcePackageManifest>[];
    for (final value in repositories) {
      final row = _objectMap(value, 'package source repository');
      final name = _requiredString(row, 'name');
      final manifest = await _readSourceYaml('packages/manifests/$name.yaml');
      manifests.add(_SourcePackageManifest.fromYaml(name, row, manifest));
    }
    return manifests;
  }

  Future<Map<String, Object?>> _readSourceYaml(String path) async {
    final file = File('${root.path}/$path');
    final loaded = loadYaml(await file.readAsString());
    final converted = _yamlValue(loaded);
    if (converted is! Map<String, Object?>) {
      throw FormatException('$path must contain a YAML object.');
    }
    return converted;
  }
}

@Deprecated('Use SourceIndex instead.')
typedef PubSource = SourceIndex;

class PackageIndex {
  const PackageIndex({required this.schemaVersion, required this.packages});

  final int schemaVersion;
  final Map<String, PackageEntry> packages;
}

class PackageEntry {
  const PackageEntry({required this.upstream, required this.adapters});

  final String upstream;
  final List<PackageAdapter> adapters;
}

class PackageAdapter {
  const PackageAdapter({
    required this.sdkVersion,
    required this.upstreamVersion,
    required this.repository,
    required this.tag,
    this.path,
    this.sourceName,
    this.sourcePriority = 0,
  });

  final String sdkVersion;
  final String upstreamVersion;
  final String repository;
  final String tag;
  final String? path;
  final String? sourceName;
  final int sourcePriority;

  PackageAdapter withSource(String name, int priority) {
    return PackageAdapter(
      sdkVersion: sdkVersion,
      upstreamVersion: upstreamVersion,
      repository: repository,
      tag: tag,
      path: path,
      sourceName: name,
      sourcePriority: priority,
    );
  }
}

class CompatibilityMatrix {
  const CompatibilityMatrix({
    required this.schemaVersion,
    required this.sdkVersions,
  });

  final int schemaVersion;
  final Map<String, CompatibilityVersion> sdkVersions;
}

class CompatibilityVersion {
  const CompatibilityVersion({
    required this.native,
    required this.adapted,
    required this.blocked,
  });

  final List<String> native;
  final List<String> adapted;
  final List<String> blocked;
}

Map<String, Object?> _objectMap(Object? value, String label) {
  if (value is! Map<String, Object?>) {
    throw FormatException('Expected $label to be a YAML object.');
  }
  return value;
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('Expected "$key" to be a non-empty string.');
  }
  return value;
}

Object? _yamlValue(Object? value) {
  if (value is YamlMap) {
    return {
      for (final entry in value.nodes.entries)
        if (entry.key.value is String)
          entry.key.value as String: _yamlValue(entry.value.value),
    };
  }
  if (value is YamlList) {
    return value.nodes.map((node) => _yamlValue(node.value)).toList();
  }
  return value;
}

String _flutterVersionFromSdkVersion(String version) {
  final match = RegExp(r'^(.+)-ohos-.+$').firstMatch(version);
  if (match == null) {
    throw FormatException('Invalid Flutter OHOS SDK version: $version');
  }
  return match.group(1)!;
}

class _SourcePackageManifest {
  const _SourcePackageManifest({
    required this.name,
    required this.upstream,
    required this.adapters,
    required this.compatibility,
  });

  factory _SourcePackageManifest.fromYaml(
    String expectedName,
    Map<String, Object?> row,
    Map<String, Object?> yaml,
  ) {
    final package = _objectMap(yaml['package'], 'package manifest package');
    final name = _requiredString(package, 'name');
    if (name != expectedName) {
      throw FormatException(
        'Package manifest "$name" does not match repository package '
        '"$expectedName".',
      );
    }
    final upstream =
        package['upstreamUrl'] as String? ??
        row['upstreamUrl'] as String? ??
        '';
    if (upstream.isEmpty) {
      throw FormatException(
        'Expected package manifest "$name" upstreamUrl to be a non-empty '
        'string.',
      );
    }

    final releases = yaml['releases'];
    if (releases is! List) {
      throw FormatException(
        'Package manifest "$name" releases must be a list.',
      );
    }

    final adapters = <PackageAdapter>[];
    final compatibility = <_SourceCompatibilityStatus>[];
    for (final value in releases) {
      final release = _objectMap(value, 'package manifest release');
      final status = _requiredString(release, 'status');
      final sdk = _objectMap(release['sdk'], 'package manifest release sdk');
      final sdkVersions = _sdkVersions(sdk);
      compatibility.addAll(
        sdkVersions.map(
          (sdkVersion) => _SourceCompatibilityStatus(
            sdkVersion: sdkVersion,
            status: status,
          ),
        ),
      );
      if (status == 'broken') {
        continue;
      }

      final replacement = _objectMap(
        release['replacement'],
        'package manifest replacement',
      );
      for (final sdkVersion in sdkVersions) {
        adapters.add(
          PackageAdapter(
            sdkVersion: sdkVersion,
            upstreamVersion: _requiredString(release, 'upstreamVersion'),
            repository: _requiredString(replacement, 'url'),
            tag: _requiredString(replacement, 'ref'),
            path: replacement['path'] as String?,
          ),
        );
      }
    }

    return _SourcePackageManifest(
      name: name,
      upstream: upstream,
      adapters: adapters,
      compatibility: compatibility,
    );
  }

  final String name;
  final String upstream;
  final List<PackageAdapter> adapters;
  final List<_SourceCompatibilityStatus> compatibility;
}

List<String> _sdkVersions(Map<String, Object?> sdk) {
  final versions = sdk['versions'];
  if (versions is List) {
    final parsed = versions.whereType<String>().toList(growable: false);
    if (parsed.length != versions.length || parsed.isEmpty) {
      throw const FormatException(
        'Expected package manifest release sdk.versions to be a non-empty '
        'string list.',
      );
    }
    return parsed;
  }
  return [_requiredString(sdk, 'version')];
}

class _SourceCompatibilityStatus {
  const _SourceCompatibilityStatus({
    required this.sdkVersion,
    required this.status,
  });

  final String sdkVersion;
  final String status;
}
