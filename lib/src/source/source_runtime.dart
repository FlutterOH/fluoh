import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

import '../cli/terminal_output.dart';
import '../config/fluoh_config.dart';
import '../context/fluoh_environment.dart';
import '../schema/version_rules.dart';
import '../version.dart';
import 'source_index.dart';
import 'source_sync.dart';

/// Loads and maintains resolved Source data for SDK and package lookups.
class SourceRuntime {
  /// Creates a Source runtime for [environment].
  const SourceRuntime(this.environment);

  /// Runtime environment containing config, cache, and lockfile paths.
  final FluohEnvironment environment;

  /// Loads the merged SDK index from configured Sources.
  Future<SdkIndex> loadSdkIndex() async {
    return (await _loadResolvedLock()).sdkIndex;
  }

  /// Loads the merged package index, optionally limited to [packageNames].
  Future<PackageIndex> loadPackageIndex({Set<String>? packageNames}) async {
    final config = await FluohConfigStore(environment).load();
    final lock = await _loadResolvedLock(config: config);
    return _buildPackageIndex(
      config,
      packageNames: packageNames,
      packageRoutes: lock.packageRoutes,
    );
  }

  /// Loads the legacy compatibility matrix view.
  Future<CompatibilityMatrix> loadCompatibilityMatrix({
    Set<String>? packageNames,
  }) async {
    return _compatibilityMatrixFromPackageIndex(
      await loadPackageIndex(packageNames: packageNames),
    );
  }

  /// Rebuilds the resolved Source lockfile.
  Future<void> rebuildLock({
    FluohConfig? config,
    TerminalOutput? output,
  }) async {
    final resolvedConfig = config ?? await FluohConfigStore(environment).load();
    await ensureSourceSnapshots(resolvedConfig, output: output);
    await _writeLock(await _buildLock(resolvedConfig, ensureSnapshots: false));
  }

  /// Saves config and rebuilds the Source lock atomically.
  Future<void> saveConfigAndRebuildLock(
    FluohConfig config, {
    Map<String, Directory> snapshots = const <String, Directory>{},
    TerminalOutput? output,
  }) async {
    final configFile = environment.configFile;
    final lockFile = environment.sourcesLockFile;
    final previousConfig = await configFile.exists()
        ? await configFile.readAsString()
        : null;
    final previousLock = await lockFile.exists()
        ? await lockFile.readAsString()
        : null;
    final snapshotTransactions = <_SourceSnapshotTransaction>[];
    try {
      for (final entry in snapshots.entries) {
        final sourceConfig = config.sources[entry.key];
        if (sourceConfig == null) {
          throw UsageException('Unknown source "${entry.key}".', '');
        }
        snapshotTransactions.add(
          await _replaceSourceSnapshotForTransaction(
            source: entry.value,
            destination: sourceConfig.directory,
          ),
        );
      }
      final lock = await _buildLock(config, output: output);
      await FluohConfigStore(environment).save(config);
      await _writeLock(lock);
    } catch (_) {
      await _restoreFile(configFile, previousConfig);
      await _restoreFile(lockFile, previousLock);
      for (final transaction in snapshotTransactions.reversed) {
        await transaction.restore();
      }
      rethrow;
    } finally {
      for (final transaction in snapshotTransactions) {
        await transaction.cleanup();
      }
    }
  }

  Future<_ResolvedSourceLock> _loadResolvedLock({FluohConfig? config}) async {
    final resolvedConfig = config ?? await FluohConfigStore(environment).load();
    final fingerprint = await _lockFingerprint(resolvedConfig);
    final current = await _readLock();
    if (current != null && _jsonEqual(current.fingerprint, fingerprint)) {
      return current;
    }
    await ensureSourceSnapshots(resolvedConfig);
    final refreshedFingerprint = await _lockFingerprint(resolvedConfig);
    final refreshed = await _readLock();
    if (refreshed != null &&
        _jsonEqual(refreshed.fingerprint, refreshedFingerprint)) {
      return refreshed;
    }
    final lock = await _buildLock(
      resolvedConfig,
      fingerprint: refreshedFingerprint,
      ensureSnapshots: false,
    );
    await _writeLock(lock);
    return lock;
  }

  Future<_ResolvedSourceLock> _buildLock(
    FluohConfig config, {
    TerminalOutput? output,
    Map<String, Object?>? fingerprint,
    bool ensureSnapshots = true,
  }) async {
    if (ensureSnapshots) {
      await ensureSourceSnapshots(config, output: output);
    }
    final sdkIndex = await _buildSdkIndex(config);
    final packageRoutes = await _buildPackageRoutes(config);
    return _ResolvedSourceLock(
      fingerprint: fingerprint ?? await _lockFingerprint(config),
      sdkIndex: sdkIndex,
      packageRoutes: packageRoutes,
    );
  }

  Future<SdkIndex> _buildSdkIndex(FluohConfig config) async {
    final sources = await _readableSources(
      config: config,
      hasIndex: (source) => source.hasSdkIndex,
    );
    final releases = <String, _PrioritizedRelease>{};

    for (final source in sources) {
      final index = await _loadSourceIndex(
        source,
        (pubSource) => pubSource.loadSdkIndex(),
      );
      for (final release in index.releases) {
        final existing = releases[release.tag];
        if (existing == null ||
            source.config.priority > existing.source.config.priority) {
          releases[release.tag] = _PrioritizedRelease(
            source,
            release.withSource(source.name, source.config.priority),
          );
          continue;
        }
        if (source.config.priority == existing.source.config.priority &&
            (release.repository != existing.release.repository ||
                release.version != existing.release.version ||
                release.versionSeries != existing.release.versionSeries ||
                release.channel != existing.release.channel)) {
          throw UsageException(
            'Conflicting SDK version ${release.tag} in sources '
                '${existing.name} and ${source.name}. Adjust source priority or '
                'select a single source.',
            '',
          );
        }
      }
    }

    return SdkIndex(
      schemaVersion: 1,
      releases: releases.values.map((entry) => entry.release).toList(),
    );
  }

  Future<_PackageRouteLock> _buildPackageRoutes(FluohConfig config) async {
    final sources = await _readableSources(
      config: config,
      hasIndex: (source) => source.hasPackageIndex,
    );
    final manifests = <String, Map<String, Map<String, List<String>>>>{};

    for (final source in sources) {
      final routeIndex = await _loadSourceIndex(
        source,
        (pubSource) => pubSource.loadPackageRouteIndex(),
      );
      if (routeIndex.manifests.isNotEmpty) {
        manifests[source.name] = {
          for (final entry in _sortedRouteManifests(routeIndex.manifests))
            entry.name: {
              for (final packageEntry in _sortedPackageRoutes(entry.packages))
                packageEntry.key: packageEntry.value,
            },
        };
      }
    }

    return _PackageRouteLock(
      manifests: {
        for (final sourceName in _sortedStrings(manifests.keys))
          sourceName: {
            for (final entry in _sortedManifestRoutes(manifests[sourceName]!))
              entry.key: entry.value,
          },
      },
    );
  }

  Future<PackageIndex> _buildPackageIndex(
    FluohConfig config, {
    Set<String>? packageNames,
    _PackageRouteLock? packageRoutes,
  }) async {
    final sources = await _readableSources(
      config: config,
      hasIndex: (source) => source.hasPackageIndex,
      validate: packageRoutes == null,
    );
    final packages = <String, PackageEntry>{};
    final groupPriorities = <String, int>{};
    final supportStatuses = <String, _CompatibilityStatus>{};
    final seenReplacements = <String, _Replacement>{};

    for (final source in sources) {
      final manifestNames = packageRoutes?.manifestNamesForSource(
        source.name,
        packageNames,
      );
      if (manifestNames != null && manifestNames.isEmpty) {
        continue;
      }
      final index = await _loadSourceIndex(
        source,
        (pubSource) => pubSource.loadPackageIndex(
          packageNames: packageNames,
          manifestNames: manifestNames,
        ),
      );
      for (final packageEntry in index.packages.entries) {
        final packageName = packageEntry.key;
        final current = packages[packageName];
        final implementations = current == null
            ? <PackageImplementation>[]
            : current.implementations.toList(growable: true);
        final compatibility = current == null
            ? <SourceCompatibilityStatus>[]
            : current.compatibility.toList(growable: true);

        for (final implementation in packageEntry.value.implementations) {
          final sourced = implementation.withSource(
            source.name,
            source.config.priority,
          );
          final groupKey =
              '$packageName|${sourced.sdkVersion}|${sourced.upstreamVersion}';
          final groupPriority = groupPriorities[groupKey];
          if (groupPriority != null && source.config.priority < groupPriority) {
            continue;
          }
          if (groupPriority == null || source.config.priority > groupPriority) {
            groupPriorities[groupKey] = source.config.priority;
            implementations.removeWhere(
              (existing) =>
                  existing.sdkVersion == sourced.sdkVersion &&
                  existing.upstreamVersion == sourced.upstreamVersion,
            );
          }

          final replacementKey = '$groupKey|${sourced.tag}';
          final replacement = _Replacement.fromImplementation(
            sourced,
            source.name,
          );
          final existingReplacement = seenReplacements[replacementKey];
          if (existingReplacement != null &&
              existingReplacement.priority == source.config.priority &&
              existingReplacement != replacement) {
            throw UsageException(
              'Conflicting OHOS implementation $packageName ${sourced.tag} in '
                  'sources ${existingReplacement.sourceName} and ${source.name}. '
                  'Adjust source priority or select a single source.',
              '',
            );
          }
          seenReplacements[replacementKey] = replacement;
          if (!implementations.any(
            (existing) =>
                existing.repository == sourced.repository &&
                existing.tag == sourced.tag &&
                existing.path == sourced.path,
          )) {
            implementations.add(sourced);
          }
        }

        for (final status in packageEntry.value.compatibility) {
          final statusKey =
              '$packageName|${status.sdkVersion}|${status.upstreamVersion}';
          final incoming = _CompatibilityStatus(
            status: status.status,
            priority: source.config.priority,
            sourceName: source.name,
          );
          final existing = supportStatuses[statusKey];
          if (existing != null && incoming.priority < existing.priority) {
            continue;
          }
          if (existing != null && incoming.priority == existing.priority) {
            if (incoming.status != existing.status) {
              throw UsageException(
                'Conflicting compatibility status for $packageName '
                    '${status.upstreamVersion} on SDK version '
                    '${status.sdkVersion} in sources ${existing.sourceName} '
                    'and ${source.name}. Adjust source priority or select a '
                    'single source.',
                '',
              );
            }
            continue;
          }

          supportStatuses[statusKey] = incoming;
          compatibility.removeWhere(
            (existing) =>
                existing.sdkVersion == status.sdkVersion &&
                existing.upstreamVersion == status.upstreamVersion,
          );
          compatibility.add(status);
        }

        packages[packageName] = PackageEntry(
          repository: current?.repository ?? packageEntry.value.repository,
          upstream: current?.upstream ?? packageEntry.value.upstream,
          repositoryPath:
              current?.repositoryPath ?? packageEntry.value.repositoryPath,
          upstreamPath:
              current?.upstreamPath ?? packageEntry.value.upstreamPath,
          upstreamBranch:
              current?.upstreamBranch ?? packageEntry.value.upstreamBranch,
          implementations: implementations,
          compatibility: compatibility,
          sourceNames: <String>{
            ...?current?.sourceNames,
            source.name,
          }.toList(growable: false)..sort(),
          advisory: current == null
              ? packageEntry.value.advisory
              : current.advisory,
          maintenance: current == null
              ? packageEntry.value.maintenance
              : current.maintenance,
        );
      }
    }

    return PackageIndex(schemaVersion: 1, packages: packages);
  }

  Future<List<_NamedSource>> _readableSources({
    required FluohConfig config,
    required bool Function(SourceIndex source) hasIndex,
    bool validate = true,
  }) async {
    final sources = <_NamedSource>[];
    for (final entry in config.sources.entries) {
      final source = _NamedSource(entry.key, entry.value);
      final index = SourceIndex.directory(source.config.directory);
      if (!hasIndex(index)) {
        continue;
      }
      if (validate) {
        try {
          await validateSource(source.name, source.config);
        } on UsageException {
          continue;
        }
      }
      sources.add(source);
    }
    sources.sort((a, b) {
      final priority = b.config.priority.compareTo(a.config.priority);
      return priority == 0 ? a.name.compareTo(b.name) : priority;
    });

    if (config.sources.isEmpty) {
      return const <_NamedSource>[];
    }
    if (sources.isEmpty) {
      throw UsageException(
        'No readable data source index found. Run "fluoh source update" or '
            '"fluoh source add <name> <path>".',
        '',
      );
    }
    return sources;
  }

  Future<T> _loadSourceIndex<T>(
    _NamedSource source,
    Future<T> Function(SourceIndex source) load,
  ) async {
    try {
      return await load(SourceIndex.directory(source.config.directory));
    } on FormatException catch (error) {
      throw UsageException(
        'Source ${source.name} is not valid: ${error.message}',
        '',
      );
    } on FileSystemException catch (error) {
      throw UsageException(
        'Source ${source.name} could not be read: ${_fileSystemMessage(error)}',
        '',
      );
    }
  }

  Future<Map<String, Object?>> _lockFingerprint(FluohConfig config) async {
    final sourceEntries = config.sources.entries.toList(growable: false)
      ..sort((a, b) => a.key.compareTo(b.key));
    return {
      'toolVersion': packageVersion,
      'sources': [
        for (final entry in sourceEntries)
          {
            'name': entry.key,
            'path': entry.value.path,
            if (entry.value.url != null) 'url': entry.value.url,
            'priority': entry.value.priority,
            'snapshotHash': await _snapshotHash(entry.value.directory),
          },
      ],
    };
  }

  Future<_ResolvedSourceLock?> _readLock() async {
    final file = environment.sourcesLockFile;
    if (!await file.exists()) {
      return null;
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, Object?>) {
        return null;
      }
      return _resolvedSourceLockFromJson(decoded.cast<String, Object?>());
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  Future<void> _writeLock(_ResolvedSourceLock lock) async {
    final file = environment.sourcesLockFile;
    await file.parent.create(recursive: true);
    final temp = File(
      '${file.path}.fluoh-next-${DateTime.now().microsecondsSinceEpoch}',
    );
    File? backup;
    try {
      await temp.writeAsString('${_encodeSourceLockJson(lock.toJson())}\n');
      if (await file.exists()) {
        backup = File(
          '${file.path}.fluoh-previous-'
          '${DateTime.now().microsecondsSinceEpoch}',
        );
        await file.rename(backup.path);
      }
      await temp.rename(file.path);
      if (backup != null && await backup.exists()) {
        await backup.delete();
      }
    } catch (_) {
      if (await temp.exists()) {
        await temp.delete();
      }
      if (backup != null && await backup.exists() && !await file.exists()) {
        await backup.rename(file.path);
      }
      rethrow;
    }
  }
}

const _sourceLockInlineJsonMaxLength = 120;

String _encodeSourceLockJson(Object? value) {
  final buffer = StringBuffer();
  _writeSourceLockJsonValue(buffer, value, 0, allowInline: false);
  return buffer.toString();
}

void _writeSourceLockJsonValue(
  StringBuffer buffer,
  Object? value,
  int indent, {
  bool allowInline = true,
}) {
  if (allowInline) {
    final inline = _inlineSourceLockJson(value);
    if (inline != null) {
      buffer.write(inline);
      return;
    }
  }

  if (value is Map) {
    _writeSourceLockJsonMap(buffer, value, indent);
    return;
  }
  if (value is Iterable) {
    _writeSourceLockJsonList(buffer, value.toList(growable: false), indent);
    return;
  }
  buffer.write(jsonEncode(value));
}

String? _inlineSourceLockJson(Object? value) {
  if (value is! Map && value is! Iterable) {
    return jsonEncode(value);
  }
  final encoded = jsonEncode(value);
  return encoded.length <= _sourceLockInlineJsonMaxLength ? encoded : null;
}

void _writeSourceLockJsonMap(
  StringBuffer buffer,
  Map<Object?, Object?> map,
  int indent,
) {
  if (map.isEmpty) {
    buffer.write('{}');
    return;
  }
  buffer.write('{\n');
  final entries = map.entries.toList(growable: false);
  for (var index = 0; index < entries.length; index += 1) {
    final entry = entries[index];
    _writeSourceLockJsonIndent(buffer, indent + 1);
    buffer
      ..write(jsonEncode('${entry.key}'))
      ..write(': ');
    _writeSourceLockJsonValue(buffer, entry.value, indent + 1);
    if (index != entries.length - 1) {
      buffer.write(',');
    }
    buffer.write('\n');
  }
  _writeSourceLockJsonIndent(buffer, indent);
  buffer.write('}');
}

void _writeSourceLockJsonList(
  StringBuffer buffer,
  List<Object?> list,
  int indent,
) {
  if (list.isEmpty) {
    buffer.write('[]');
    return;
  }
  buffer.write('[\n');
  for (var index = 0; index < list.length; index += 1) {
    _writeSourceLockJsonIndent(buffer, indent + 1);
    _writeSourceLockJsonValue(buffer, list[index], indent + 1);
    if (index != list.length - 1) {
      buffer.write(',');
    }
    buffer.write('\n');
  }
  _writeSourceLockJsonIndent(buffer, indent);
  buffer.write(']');
}

void _writeSourceLockJsonIndent(StringBuffer buffer, int indent) {
  buffer.write('  ' * indent);
}

String _fileSystemMessage(FileSystemException error) {
  final path = error.path;
  if (path == null || path.isEmpty) {
    return error.message;
  }
  return '${error.message}: $path';
}

const _sourceSnapshotStateFileName = '.fluoh-source-state.json';
const _sourceSnapshotStateVersion = 1;

class _ResolvedSourceLock {
  const _ResolvedSourceLock({
    required this.fingerprint,
    required this.sdkIndex,
    required this.packageRoutes,
  });

  final Map<String, Object?> fingerprint;
  final SdkIndex sdkIndex;
  final _PackageRouteLock packageRoutes;

  Map<String, Object?> toJson() {
    return {
      'fingerprint': fingerprint,
      'sdk': {
        'versions': {
          for (final release in _sortedSdkReleases(sdkIndex.releases))
            release.version: _sdkReleaseToJson(release),
        },
      },
      'routes': packageRoutes.toJson(),
    };
  }
}

_ResolvedSourceLock _resolvedSourceLockFromJson(Map<String, Object?> json) {
  return _ResolvedSourceLock(
    fingerprint: _jsonObject(
      json['fingerprint'],
      'sources.lock.json fingerprint',
    ),
    sdkIndex: _sdkIndexFromLock(json),
    packageRoutes: _packageRouteLockFromJson(json['routes']),
  );
}

class _PackageRouteLock {
  const _PackageRouteLock({required this.manifests});

  final Map<String, Map<String, Map<String, List<String>>>> manifests;

  Set<String>? manifestNamesForSource(
    String sourceName,
    Set<String>? packageNames,
  ) {
    if (packageNames == null) {
      return null;
    }
    final sourceManifests = manifests[sourceName];
    if (sourceManifests == null) {
      return <String>{};
    }
    return {
      for (final entry in sourceManifests.entries)
        if (entry.value.keys.any(packageNames.contains)) entry.key,
    };
  }

  Map<String, Object?> toJson() {
    return {
      for (final sourceEntry in manifests.entries)
        sourceEntry.key: {
          for (final manifestEntry in sourceEntry.value.entries)
            manifestEntry.key: manifestEntry.value,
        },
    };
  }
}

_PackageRouteLock _packageRouteLockFromJson(Object? value) {
  final manifests = _jsonObject(value, 'sources.lock.json routes');
  return _PackageRouteLock(
    manifests: {
      for (final sourceEntry in manifests.entries)
        sourceEntry.key: _packageManifestRoutesFromJson(
          sourceEntry.value,
          'sources.lock.json routes.${sourceEntry.key}',
        ),
    },
  );
}

Map<String, Map<String, List<String>>> _packageManifestRoutesFromJson(
  Object? value,
  String label,
) {
  final json = _jsonObject(value, label);
  return {
    for (final entry in json.entries)
      entry.key: _packageSdkLinesFromJson(entry.value, '$label.${entry.key}'),
  };
}

Map<String, List<String>> _packageSdkLinesFromJson(
  Object? value,
  String label,
) {
  final json = _jsonObject(value, label);
  return {
    for (final entry in json.entries)
      entry.key: _jsonStringList(entry.value, '$label.${entry.key}'),
  };
}

Map<String, Object?> _sdkReleaseToJson(SdkRelease release) {
  return {
    if (release.sourceName != null) 'source': release.sourceName,
    if (release.versionSeries !=
        sdkVersionSeriesFromSdkVersion(release.version))
      'versionSeries': release.versionSeries,
    if (release.flutterVersion != flutterVersionFromSdkVersion(release.version))
      'flutterVersion': release.flutterVersion,
    if (release.channel != 'stable') 'channel': release.channel,
    if (release.tag != release.version) 'tag': release.tag,
    if (release.publishedAt != null) 'publishedAt': release.publishedAt,
    'git': {'url': release.repository},
  };
}

SdkIndex _sdkIndexFromLock(Map<String, Object?> json) {
  final sdk = _optionalJsonObject(json['sdk'], 'sources.lock.json sdk');
  final versions = sdk == null
      ? const <String, Object?>{}
      : _jsonObject(sdk['versions'], 'sources.lock.json sdk.versions');
  return SdkIndex(
    schemaVersion: 1,
    releases: [
      for (final entry in versions.entries)
        _sdkReleaseFromLock(entry.key, entry.value),
    ],
  );
}

SdkRelease _sdkReleaseFromLock(String version, Object? value) {
  final json = _jsonObject(value, 'sources.lock.json sdk.versions.$version');
  final git = _jsonObject(
    json['git'],
    'sources.lock.json sdk.versions.$version.git',
  );
  return SdkRelease(
    version: version,
    versionSeries:
        _optionalString(json['versionSeries']) ??
        sdkVersionSeriesFromSdkVersion(version),
    flutterVersion:
        _optionalString(json['flutterVersion']) ??
        flutterVersionFromSdkVersion(version),
    channel: _optionalString(json['channel']) ?? 'stable',
    repository: _requiredString(git['url'], 'sdk.versions.$version.git.url'),
    tag: _optionalString(json['tag']) ?? version,
    publishedAt: _optionalString(json['publishedAt']),
    sourceName: _optionalString(json['source']),
    sourcePriority: _optionalInt(json['priority']) ?? 0,
  );
}

CompatibilityMatrix _compatibilityMatrixFromPackageIndex(PackageIndex index) {
  final versions = <String, List<String>>{};
  for (final entry in index.packages.entries) {
    for (final status in entry.value.compatibility) {
      if (status.status != 'implemented') {
        continue;
      }
      versions.putIfAbsent(status.sdkLine, () => <String>[]).add(entry.key);
    }
  }
  return CompatibilityMatrix(
    schemaVersion: 1,
    sdkVersions: versions.map(
      (sdkLine, packageNames) => MapEntry(
        sdkLine,
        CompatibilityVersion(
          native: const <String>[],
          implemented: packageNames.toSet().toList(growable: false)..sort(),
          blocked: const <String>[],
        ),
      ),
    ),
  );
}

List<SdkRelease> _sortedSdkReleases(Iterable<SdkRelease> releases) {
  return releases.toList(growable: false)
    ..sort((a, b) => a.version.compareTo(b.version));
}

List<SourcePackageRouteManifest> _sortedRouteManifests(
  Map<String, SourcePackageRouteManifest> manifests,
) {
  return manifests.values.toList(growable: false)
    ..sort((a, b) => a.name.compareTo(b.name));
}

List<MapEntry<String, List<String>>> _sortedPackageRoutes(
  Map<String, List<String>> packages,
) {
  return packages.entries.toList(growable: false)
    ..sort((a, b) => a.key.compareTo(b.key));
}

List<MapEntry<String, Map<String, List<String>>>> _sortedManifestRoutes(
  Map<String, Map<String, List<String>>> manifests,
) {
  return manifests.entries.toList(growable: false)
    ..sort((a, b) => a.key.compareTo(b.key));
}

List<String> _sortedStrings(Iterable<String> values) {
  return values.toSet().toList(growable: false)..sort();
}

Future<String> _snapshotHash(Directory root) async {
  if (!await root.exists()) {
    return _stableHash({'missing': root.path});
  }
  final fingerprint = await _snapshotFingerprint(root);
  final stateHash = await _readSnapshotStateHash(root, fingerprint);
  if (stateHash != null) {
    return stateHash;
  }
  final hash = await _calculateSnapshotHash(root);
  await _writeSnapshotState(root, hash, fingerprint);
  return hash;
}

Future<String> _calculateSnapshotHash(Directory root) async {
  final files = <File>[];
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is File &&
        _relativePath(root, entity) != _sourceSnapshotStateFileName) {
      files.add(entity);
    }
  }
  files.sort(
    (a, b) => _relativePath(root, a).compareTo(_relativePath(root, b)),
  );
  return _stableHash({
    for (final file in files)
      _relativePath(root, file): _hashBytes(await file.readAsBytes()),
  });
}

Future<Map<String, Object?>> _snapshotFingerprint(Directory root) async {
  final entries = <Map<String, Object?>>[];
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File) {
      continue;
    }
    final relative = _relativePath(root, entity);
    if (relative == _sourceSnapshotStateFileName) {
      continue;
    }
    final stat = await entity.stat();
    entries.add({
      'path': relative,
      'size': stat.size,
      'modified': stat.modified.toUtc().microsecondsSinceEpoch,
    });
  }
  entries.sort((a, b) => '${a['path']}'.compareTo('${b['path']}'));
  return {'files': entries};
}

Future<String?> _readSnapshotStateHash(
  Directory root,
  Map<String, Object?> fingerprint,
) async {
  final file = File('${root.path}/$_sourceSnapshotStateFileName');
  if (!await file.exists()) {
    return null;
  }
  try {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, Object?>) {
      return null;
    }
    if (_optionalInt(decoded['stateVersion']) != _sourceSnapshotStateVersion) {
      return null;
    }
    if (!_jsonEqual(decoded['fingerprint'], fingerprint)) {
      return null;
    }
    final hash = _optionalString(decoded['snapshotHash']);
    return hash == null || !hash.startsWith('hash64:') ? null : hash;
  } on FormatException {
    return null;
  } on FileSystemException {
    return null;
  }
}

Future<void> _writeSnapshotState(
  Directory root,
  String snapshotHash,
  Map<String, Object?> fingerprint,
) async {
  final file = File('${root.path}/$_sourceSnapshotStateFileName');
  final content = const JsonEncoder.withIndent('  ').convert({
    'stateVersion': _sourceSnapshotStateVersion,
    'generatedBy': 'fluoh $packageVersion',
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'fingerprint': fingerprint,
    'snapshotHash': snapshotHash,
  });
  await file.writeAsString('$content\n');
}

String _relativePath(Directory root, FileSystemEntity entity) {
  final rootPath = root.absolute.path;
  final entityPath = entity.absolute.path;
  if (entityPath == rootPath) {
    return '';
  }
  return entityPath.substring(rootPath.length + 1);
}

String _stableHash(Object? value) {
  final normalized = _normalizeJson(value);
  final bytes = utf8.encode(jsonEncode(normalized));
  return _hashBytes(bytes);
}

Object? _normalizeJson(Object? value) {
  if (value is Map) {
    final entries = value.entries.toList(growable: false)
      ..sort((a, b) => '${a.key}'.compareTo('${b.key}'));
    return {
      for (final entry in entries) '${entry.key}': _normalizeJson(entry.value),
    };
  }
  if (value is Iterable) {
    return [for (final item in value) _normalizeJson(item)];
  }
  return value;
}

String _hashBytes(List<int> bytes) {
  const mask = 0xffffffffffffffff;
  var hash = 0xcbf29ce484222325;
  for (final byte in bytes) {
    hash ^= byte;
    hash = (hash * 0x100000001b3) & mask;
  }
  return 'hash64:${hash.toRadixString(16).padLeft(16, '0')}';
}

bool _jsonEqual(Object? left, Object? right) {
  return jsonEncode(_normalizeJson(left)) == jsonEncode(_normalizeJson(right));
}

Map<String, Object?> _jsonObject(Object? value, String label) {
  if (value is! Map) {
    throw FormatException('$label must be a JSON object.');
  }
  return {for (final entry in value.entries) '${entry.key}': entry.value};
}

List<String> _jsonStringList(Object? value, String label) {
  if (value is! Iterable) {
    throw FormatException('$label must be a JSON array.');
  }
  return [for (final item in value) _requiredString(item, '$label[]')];
}

Map<String, Object?>? _optionalJsonObject(Object? value, String label) {
  if (value == null) {
    return null;
  }
  return _jsonObject(value, label);
}

String _requiredString(Object? value, String label) {
  final text = _optionalString(value);
  if (text == null || text.isEmpty) {
    throw FormatException('$label must be a non-empty string.');
  }
  return text;
}

String? _optionalString(Object? value) {
  if (value == null) {
    return null;
  }
  return '$value';
}

int? _optionalInt(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  return int.tryParse('$value');
}

Future<void> _restoreFile(File file, String? content) async {
  if (content == null) {
    if (await file.exists()) {
      await file.delete();
    }
    return;
  }
  await file.parent.create(recursive: true);
  await file.writeAsString(content);
}

Future<_SourceSnapshotTransaction> _replaceSourceSnapshotForTransaction({
  required Directory source,
  required Directory destination,
}) async {
  final parent = destination.parent;
  await parent.create(recursive: true);
  var staging = await parent.createTemp('.${basename(destination.path)}-next-');
  Directory? backup;
  var installed = false;
  try {
    await copySourceSnapshot(source, staging);
    final fingerprint = await _snapshotFingerprint(staging);
    await _writeSnapshotState(
      staging,
      await _calculateSnapshotHash(staging),
      fingerprint,
    );
    if (await destination.exists()) {
      backup = await destination.rename(
        '${parent.path}/.${basename(destination.path)}-previous-'
        '${DateTime.now().microsecondsSinceEpoch}',
      );
    }
    await staging.rename(destination.path);
    staging = Directory('');
    installed = true;
    return _SourceSnapshotTransaction(destination: destination, backup: backup);
  } catch (_) {
    if (installed && await destination.exists()) {
      await deleteIfExists(destination);
    }
    if (backup != null &&
        await backup.exists() &&
        !await destination.exists()) {
      await backup.rename(destination.path);
    }
    rethrow;
  } finally {
    if (staging.path.isNotEmpty) {
      await deleteIfExists(staging);
    }
  }
}

class _SourceSnapshotTransaction {
  const _SourceSnapshotTransaction({required this.destination, this.backup});

  final Directory destination;
  final Directory? backup;

  Future<void> restore() async {
    if (await destination.exists()) {
      await deleteIfExists(destination);
    }
    if (backup != null && await backup!.exists()) {
      await backup!.rename(destination.path);
    }
  }

  Future<void> cleanup() async {
    if (backup != null && await backup!.exists()) {
      await deleteIfExists(backup!);
    }
  }
}

class _NamedSource {
  const _NamedSource(this.name, this.config);

  final String name;
  final SourceConfig config;
}

class _PrioritizedRelease {
  const _PrioritizedRelease(this.source, this.release);

  String get name => source.name;

  final _NamedSource source;
  final SdkRelease release;
}

class _Replacement {
  const _Replacement({
    required this.repository,
    required this.tag,
    required this.path,
    required this.priority,
    required this.sourceName,
  });

  factory _Replacement.fromImplementation(
    PackageImplementation implementation,
    String sourceName,
  ) {
    return _Replacement(
      repository: implementation.repository,
      tag: implementation.tag,
      path: implementation.path,
      priority: implementation.sourcePriority,
      sourceName: sourceName,
    );
  }

  final String repository;
  final String tag;
  final String? path;
  final int priority;
  final String sourceName;

  @override
  bool operator ==(Object other) {
    return other is _Replacement &&
        repository == other.repository &&
        tag == other.tag &&
        path == other.path &&
        priority == other.priority;
  }

  @override
  int get hashCode => Object.hash(repository, tag, path, priority);
}

class _CompatibilityStatus {
  const _CompatibilityStatus({
    required this.status,
    required this.priority,
    required this.sourceName,
  });

  final String status;
  final int priority;
  final String sourceName;
}
