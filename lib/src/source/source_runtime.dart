import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

import '../cli/terminal_output.dart';
import '../config/fluoh_config.dart';
import '../context/fluoh_environment.dart';
import '../schema/dependency_policy.dart';
import '../schema/version_rules.dart';
import '../version.dart';
import 'source_index.dart';
import 'source_sync.dart';

part 'source_runtime_lock_json.dart';
part 'source_runtime_lock_models.dart';
part 'source_runtime_snapshot_hash.dart';
part 'source_runtime_snapshot_transaction.dart';

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
  Future<PackageIndex> loadPackageIndex({
    Set<String>? packageNames,
    Set<String> releaseStatuses = compatibleDependencyReleaseStatuses,
  }) async {
    final config = await FluohConfigStore(environment).load();
    final lock = await _loadResolvedLock(config: config);
    return _buildPackageIndex(
      config,
      packageNames: packageNames,
      packageRoutes: lock.packageRoutes,
      sdkIndex: lock.sdkIndex,
      releaseStatuses: releaseStatuses,
    );
  }

  /// Loads package compatibility buckets derived from Source manifests.
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
        (pubSource) async => _resolveSdkRepositories(
          source,
          (await pubSource.loadRootManifest()).sdkIndex,
        ),
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

  SdkIndex _resolveSdkRepositories(_NamedSource source, SdkIndex index) {
    return SdkIndex(
      schemaVersion: index.schemaVersion,
      releases: [
        for (final release in index.releases)
          _resolveSdkRepository(source, release),
      ],
    );
  }

  SdkRelease _resolveSdkRepository(_NamedSource source, SdkRelease release) {
    final repository = release.repository;
    if (_isNonRelativeSdkRepository(repository)) {
      return release;
    }
    final sourceRoot = localSourceDirectoryFromUrl(source.config.url);
    final base = (sourceRoot ?? source.config.directory).absolute.uri;
    return SdkRelease(
      version: release.version,
      versionSeries: release.versionSeries,
      flutterVersion: release.flutterVersion,
      channel: release.channel,
      repository: base.resolve(repository).toFilePath(),
      tag: release.tag,
      publishedAt: release.publishedAt,
      sourceName: release.sourceName,
      sourcePriority: release.sourcePriority,
    );
  }

  bool _isNonRelativeSdkRepository(String repository) {
    return repository.startsWith('/') ||
        repository.contains(':') ||
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(repository);
  }

  Future<_PackageRouteLock> _buildPackageRoutes(FluohConfig config) async {
    final sources = await _readableSources(
      config: config,
      hasIndex: (source) => source.hasPackageIndex,
    );
    final packages = <String, Map<String, List<String>>>{};

    for (final source in sources) {
      final routeIndex = await _loadSourceIndex(
        source,
        (pubSource) => pubSource.loadPackageRouteIndex(),
      );
      if (routeIndex.manifests.isNotEmpty) {
        packages[source.name] = {
          for (final entry in _sortedRouteManifests(routeIndex.manifests))
            entry.packageName: entry.sdkLines,
        };
      }
    }

    return _PackageRouteLock(
      packages: {
        for (final sourceName in _sortedStrings(packages.keys))
          sourceName: {
            for (final entry in _sortedPackageRoutes(packages[sourceName]!))
              entry.key: entry.value,
          },
      },
    );
  }

  Future<PackageIndex> _buildPackageIndex(
    FluohConfig config, {
    Set<String>? packageNames,
    _PackageRouteLock? packageRoutes,
    SdkIndex? sdkIndex,
    Set<String> releaseStatuses = compatibleDependencyReleaseStatuses,
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
          releaseStatuses: releaseStatuses,
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
              'Conflicting FlutterOH implementation $packageName ${sourced.tag} in '
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

    final index = PackageIndex(schemaVersion: 1, packages: packages);
    if (sdkIndex != null) {
      _validatePackageSdkLines(index, sdkIndex);
    }
    return index;
  }

  void _validatePackageSdkLines(PackageIndex packageIndex, SdkIndex sdkIndex) {
    final sdkLines = {
      for (final release in sdkIndex.releases)
        sdkLineFromSdkVersion(release.version),
    };
    for (final packageEntry in packageIndex.packages.entries) {
      for (final implementation in packageEntry.value.implementations) {
        _validatePackageSdkLine(
          packageName: packageEntry.key,
          sdkLine: implementation.sdkLine,
          availableSdkLines: sdkLines,
        );
      }
      for (final status in packageEntry.value.compatibility) {
        _validatePackageSdkLine(
          packageName: packageEntry.key,
          sdkLine: status.sdkLine,
          availableSdkLines: sdkLines,
        );
      }
    }
  }

  void _validatePackageSdkLine({
    required String packageName,
    required String sdkLine,
    required Set<String> availableSdkLines,
  }) {
    if (availableSdkLines.contains(sdkLine)) {
      return;
    }
    throw UsageException(
      'Package $packageName declares SDK line $sdkLine, but no configured '
          'Source provides a matching SDK version.',
      '',
    );
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
        'No readable data source index found. Run "fluoh source update" for '
            'configured Sources, or enable a Source with "fluoh source enable <name> <path>".',
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
