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
    _ensureAllowedKeys(yaml, 'sdk/releases.yaml', {
      'schema',
      'url',
      'releases',
    });
    final repository = _requiredString(yaml, 'url');
    final releases = yaml['releases'];
    if (releases is! List) {
      throw const FormatException('SDK source releases must be a list.');
    }

    return SdkIndex(
      schemaVersion: yaml['schema'] as int? ?? 1,
      releases: releases
          .map((value) {
            final release = _objectMap(value, 'SDK source release');
            _ensureAllowedKeys(release, 'SDK source release', {
              'version',
              'status',
            });
            final version = _requiredString(release, 'version');
            return SdkRelease(
              version: version,
              versionSeries: _versionSeriesFromSdkVersion(version),
              flutterVersion: _flutterVersionFromSdkVersion(version),
              channel: _requiredString(release, 'status'),
              repository: repository,
              tag: version,
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
    _ensureAllowedKeys(repositoryIndex, 'packages/repositories.yaml', {
      'schema',
      'repositories',
    });
    final repositories = repositoryIndex['repositories'];
    if (repositories is! List) {
      throw const FormatException(
        'Package source repositories must be a list.',
      );
    }

    final manifests = <_SourcePackageManifest>[];
    for (final value in repositories) {
      final row = _objectMap(value, 'package source repository');
      _ensureAllowedKeys(row, 'package source repository', {
        'name',
        'url',
        'path',
        'fixture',
      });
      final name = _requiredString(row, 'name');
      _requiredString(row, 'url');
      _requiredString(row, 'path');
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

Map<String, Object?>? _optionalObjectMap(Object? value, String label) {
  if (value == null) {
    return null;
  }
  return _objectMap(value, label);
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('Expected "$key" to be a non-empty string.');
  }
  return value;
}

void _ensureAllowedKeys(
  Map<String, Object?> json,
  String label,
  Set<String> allowed,
) {
  for (final key in json.keys) {
    if (!allowed.contains(key)) {
      throw FormatException('$label must not contain "$key".');
    }
  }
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

String _versionSeriesFromSdkVersion(String version) {
  final match = RegExp(r'^(\d+)\.(\d+)\.').firstMatch(version);
  if (match == null) {
    throw FormatException('Invalid Flutter OHOS SDK version: $version');
  }
  return '${match.group(1)}.${match.group(2)}';
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
    _ensureAllowedKeys(yaml, 'package manifest', {
      'schema',
      'package',
      'upstream',
      'releases',
    });
    final package = _objectMap(yaml['package'], 'package manifest package');
    _ensureAllowedKeys(package, 'package manifest package', {'name', 'git'});
    final packageGit = _objectMap(
      package['git'],
      'package manifest package git',
    );
    _ensureAllowedKeys(packageGit, 'package manifest package git', {
      'url',
      'ref',
      'path',
    });
    final name = _requiredString(package, 'name');
    if (name != expectedName) {
      throw FormatException(
        'Package manifest "$name" does not match repository package '
        '"$expectedName".',
      );
    }
    final upstream = _objectMap(yaml['upstream'], 'package manifest upstream');
    _ensureAllowedKeys(upstream, 'package manifest upstream', {'git'});
    final upstreamGit = _objectMap(
      upstream['git'],
      'package manifest upstream git',
    );
    _ensureAllowedKeys(upstreamGit, 'package manifest upstream git', {
      'url',
      'ref',
      'path',
    });
    final upstreamUrl = _requiredString(upstreamGit, 'url');

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
      _ensureAllowedKeys(release, 'package manifest release', {
        'upstream',
        'package',
        'sdk',
        'status',
        'replacement',
      });
      final status = _requiredString(release, 'status');
      final releaseUpstream = _objectMap(
        release['upstream'],
        'package manifest release upstream',
      );
      _ensureAllowedKeys(releaseUpstream, 'package manifest release upstream', {
        'version',
        'git',
      });
      final releaseUpstreamGit = _optionalObjectMap(
        releaseUpstream['git'],
        'package manifest release upstream git',
      );
      if (releaseUpstreamGit != null) {
        _ensureAllowedKeys(
          releaseUpstreamGit,
          'package manifest release upstream git',
          {'url', 'ref', 'path'},
        );
      }
      final releasePackage = _objectMap(
        release['package'],
        'package manifest release package',
      );
      _ensureAllowedKeys(releasePackage, 'package manifest release package', {
        'version',
        'git',
      });
      final releasePackageGit = _optionalObjectMap(
        releasePackage['git'],
        'package manifest release package git',
      );
      if (releasePackageGit != null) {
        _ensureAllowedKeys(
          releasePackageGit,
          'package manifest release package git',
          {'url', 'ref', 'path'},
        );
      }
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
      _ensureAllowedKeys(replacement, 'package manifest replacement', {'git'});
      final replacementGit = _objectMap(
        replacement['git'],
        'package manifest replacement git',
      );
      _ensureAllowedKeys(replacementGit, 'package manifest replacement git', {
        'url',
        'ref',
        'path',
      });
      for (final sdkVersion in sdkVersions) {
        adapters.add(
          PackageAdapter(
            sdkVersion: sdkVersion,
            upstreamVersion: _requiredString(releaseUpstream, 'version'),
            repository: _requiredString(replacementGit, 'url'),
            tag: _requiredString(replacementGit, 'ref'),
            path: replacementGit['path'] as String?,
          ),
        );
      }
    }

    return _SourcePackageManifest(
      name: name,
      upstream: upstreamUrl,
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
  if (versions is! List) {
    throw const FormatException(
      'Expected package manifest release sdk.versions to be a non-empty '
      'string list.',
    );
  }
  final parsed = versions.whereType<String>().toList(growable: false);
  if (parsed.length != versions.length || parsed.isEmpty) {
    throw const FormatException(
      'Expected package manifest release sdk.versions to be a non-empty '
      'string list.',
    );
  }
  return parsed;
}

class _SourceCompatibilityStatus {
  const _SourceCompatibilityStatus({
    required this.sdkVersion,
    required this.status,
  });

  final String sdkVersion;
  final String status;
}
