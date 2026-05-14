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

class SourceRuntime {
  const SourceRuntime(this.environment);

  final FluohEnvironment environment;

  Future<SdkIndex> loadSdkIndex() async {
    return (await _loadResolvedLock()).sdkIndex;
  }

  Future<PackageIndex> loadPackageIndex({Set<String>? packageNames}) async {
    final index = (await _loadResolvedLock()).packageIndex;
    if (packageNames == null) {
      return index;
    }
    return PackageIndex(
      schemaVersion: index.schemaVersion,
      packages: {
        for (final entry in index.packages.entries)
          if (packageNames.contains(entry.key)) entry.key: entry.value,
      },
    );
  }

  Future<CompatibilityMatrix> loadCompatibilityMatrix({
    Set<String>? packageNames,
  }) async {
    return _compatibilityMatrixFromPackageIndex(
      await loadPackageIndex(packageNames: packageNames),
    );
  }

  Future<void> rebuildLock({
    FluohConfig? config,
    TerminalOutput? output,
  }) async {
    final resolvedConfig = config ?? await FluohConfigStore(environment).load();
    await ensureSourceSnapshots(resolvedConfig, output: output);
    await _writeLock(await _buildLock(resolvedConfig));
  }

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

  Future<_ResolvedSourceLock> _loadResolvedLock() async {
    final config = await FluohConfigStore(environment).load();
    await ensureSourceSnapshots(config);
    final inputs = await _lockInputs(config);
    final current = await _readLock();
    if (current != null && _jsonEqual(current.inputs, inputs)) {
      return current;
    }
    final lock = await _buildLock(config, inputs: inputs);
    await _writeLock(lock);
    return lock;
  }

  Future<_ResolvedSourceLock> _buildLock(
    FluohConfig config, {
    TerminalOutput? output,
    Map<String, Object?>? inputs,
  }) async {
    await ensureSourceSnapshots(config, output: output);
    final sdkIndex = await _buildSdkIndex(config);
    final packageIndex = await _buildPackageIndex(config);
    return _ResolvedSourceLock(
      generatedBy: 'fluoh $packageVersion',
      generatedAt: DateTime.now().toUtc().toIso8601String(),
      inputs: inputs ?? await _lockInputs(config),
      sdkIndex: sdkIndex,
      packageIndex: packageIndex,
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

  Future<PackageIndex> _buildPackageIndex(
    FluohConfig config, {
    Set<String>? packageNames,
  }) async {
    final sources = await _readableSources(
      config: config,
      hasIndex: (source) => source.hasPackageIndex,
    );
    final packages = <String, PackageEntry>{};
    final groupPriorities = <String, int>{};
    final supportStatuses = <String, _CompatibilityStatus>{};
    final seenReplacements = <String, _Replacement>{};

    for (final source in sources) {
      final index = await _loadSourceIndex(
        source,
        (pubSource) => pubSource.loadPackageIndex(packageNames: packageNames),
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
  }) async {
    final sources = <_NamedSource>[];
    for (final entry in config.sources.entries) {
      final source = _NamedSource(entry.key, entry.value);
      final index = SourceIndex.directory(source.config.directory);
      if (!hasIndex(index)) {
        continue;
      }
      try {
        await validateSource(source.name, source.config);
      } on UsageException {
        continue;
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

  Future<Map<String, Object?>> _lockInputs(FluohConfig config) async {
    final sourceEntries = config.sources.entries.toList(growable: false)
      ..sort((a, b) => a.key.compareTo(b.key));
    return {
      'toolVersion': packageVersion,
      'configHash': _stableHash(_normalizedConfig(config)),
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
      return _ResolvedSourceLock.fromJson(decoded);
    } on FormatException {
      return null;
    }
  }

  Future<void> _writeLock(_ResolvedSourceLock lock) async {
    final file = environment.sourcesLockFile;
    await file.parent.create(recursive: true);
    final content = const JsonEncoder.withIndent('  ').convert(lock.toJson());
    final temp = File(
      '${file.path}.fluoh-next-${DateTime.now().microsecondsSinceEpoch}',
    );
    File? backup;
    try {
      await temp.writeAsString(content);
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

String _fileSystemMessage(FileSystemException error) {
  final path = error.path;
  if (path == null || path.isEmpty) {
    return error.message;
  }
  return '${error.message}: $path';
}

class _ResolvedSourceLock {
  const _ResolvedSourceLock({
    required this.generatedBy,
    required this.generatedAt,
    required this.inputs,
    required this.sdkIndex,
    required this.packageIndex,
  });

  factory _ResolvedSourceLock.fromJson(Map<String, Object?> json) {
    return _ResolvedSourceLock(
      generatedBy: _optionalString(json['generatedBy']) ?? '',
      generatedAt: _optionalString(json['generatedAt']) ?? '',
      inputs: _jsonObject(json['inputs'], 'sources.lock.json inputs'),
      sdkIndex: _sdkIndexFromLock(json),
      packageIndex: _packageIndexFromLock(json),
    );
  }

  final String generatedBy;
  final String generatedAt;
  final Map<String, Object?> inputs;
  final SdkIndex sdkIndex;
  final PackageIndex packageIndex;

  Map<String, Object?> toJson() {
    return {
      'generatedBy': generatedBy,
      'generatedAt': generatedAt,
      'inputs': inputs,
      'sdk': {
        'versions': {
          for (final release in _sortedSdkReleases(sdkIndex.releases))
            release.version: {
              if (release.sourceName != null) 'source': release.sourceName,
              'priority': release.sourcePriority,
              'versionSeries': release.versionSeries,
              'flutterVersion': release.flutterVersion,
              'channel': release.channel,
              'tag': release.tag,
              if (release.publishedAt != null)
                'publishedAt': release.publishedAt,
              'git': {'url': release.repository},
            },
        },
      },
      'packages': {
        for (final entry in _sortedPackageEntries(packageIndex.packages))
          entry.key: _packageEntryToJson(entry.value),
      },
    };
  }
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

PackageIndex _packageIndexFromLock(Map<String, Object?> json) {
  final packages = _optionalJsonObject(
    json['packages'],
    'sources.lock.json packages',
  );
  if (packages == null) {
    return const PackageIndex(schemaVersion: 1, packages: {});
  }
  return PackageIndex(
    schemaVersion: 1,
    packages: packages.map(
      (name, value) => MapEntry(name, _packageEntryFromLock(name, value)),
    ),
  );
}

PackageEntry _packageEntryFromLock(String name, Object? value) {
  final json = _jsonObject(value, 'sources.lock.json packages.$name');
  final repository = _jsonObject(json['repository'], '$name.repository');
  final repositoryGit = _jsonObject(repository['git'], '$name.repository.git');
  final upstream = _jsonObject(json['upstream'], '$name.upstream');
  final upstreamGit = _jsonObject(upstream['git'], '$name.upstream.git');
  final upstreamBranch = _optionalString(upstreamGit['branch']) ?? 'main';
  final repositoryUrl = _requiredString(
    repositoryGit['url'],
    '$name.repository.git.url',
  );
  final repositoryPath = _optionalString(repository['path']);
  final upstreamPath = _optionalString(upstream['path']);
  final packageSource = _optionalString(json['source']);
  final packagePriority = _optionalInt(json['priority']) ?? 0;
  final sdks = _optionalJsonObject(json['sdks'], '$name.sdks');
  final implementations = <PackageImplementation>[];
  final compatibility = <SourceCompatibilityStatus>[];

  if (sdks != null) {
    for (final sdkEntry in sdks.entries) {
      final sdkLine = sdkEntry.key;
      final sdkJson = _jsonObject(sdkEntry.value, '$name.sdks.$sdkLine');
      final releases = _jsonList(
        sdkJson['releases'],
        '$name.sdks.$sdkLine.releases',
      );
      for (final releaseValue in releases) {
        final release = _jsonObject(
          releaseValue,
          '$name.sdks.$sdkLine.releases[]',
        );
        final status = _optionalString(release['status']) ?? 'compatible';
        if (status != 'compatible') {
          continue;
        }
        final upstreamVersion = _requiredString(
          release['upstreamVersion'],
          '$name upstreamVersion',
        );
        final version = _requiredString(release['version'], '$name version');
        final sourceName = _optionalString(release['source']) ?? packageSource;
        final sourcePriority =
            _optionalInt(release['priority']) ?? packagePriority;
        final releaseRepository = _optionalJsonObject(
          release['repository'],
          '$name.sdks.$sdkLine.releases[].repository',
        );
        final releaseRepositoryGit = releaseRepository == null
            ? null
            : _optionalJsonObject(
                releaseRepository['git'],
                '$name.sdks.$sdkLine.releases[].repository.git',
              );
        final releaseUpstream = _optionalJsonObject(
          release['upstream'],
          '$name.sdks.$sdkLine.releases[].upstream',
        );
        final releaseUpstreamGit = releaseUpstream == null
            ? null
            : _optionalJsonObject(
                releaseUpstream['git'],
                '$name.sdks.$sdkLine.releases[].upstream.git',
              );
        implementations.add(
          PackageImplementation(
            sdkLine: sdkLine,
            upstreamVersion: upstreamVersion,
            repository: releaseRepositoryGit == null
                ? repositoryUrl
                : _requiredString(
                    releaseRepositoryGit['url'],
                    '$name.sdks.$sdkLine.releases[].repository.git.url',
                  ),
            tag:
                _optionalString(release['tag']) ??
                pubReleaseTagForPackage(
                  packageName: name,
                  upstreamVersion: upstreamVersion,
                  sdkVersion: '$sdkLine.0-ohos-0.0.0',
                  releaseVersion: version,
                ),
            version: version,
            path: _optionalString(releaseRepository?['path']) ?? repositoryPath,
            upstreamPath:
                _optionalString(releaseUpstream?['path']) ?? upstreamPath,
            upstreamBranch:
                _optionalString(releaseUpstreamGit?['branch']) ??
                upstreamBranch,
            sourceName: sourceName,
            sourcePriority: sourcePriority,
          ),
        );
        compatibility.add(
          SourceCompatibilityStatus(
            sdkLine: sdkLine,
            upstreamVersion: upstreamVersion,
            status: 'implemented',
          ),
        );
      }
    }
  }

  return PackageEntry(
    repository: repositoryUrl,
    upstream: _requiredString(upstreamGit['url'], '$name.upstream.git.url'),
    repositoryPath: repositoryPath,
    upstreamPath: upstreamPath,
    upstreamBranch: upstreamBranch,
    implementations: implementations,
    compatibility: compatibility,
    maintenance: _maintenanceFromLock(json['maintenance']),
    advisory: _advisoryFromLock(json['advisory']),
  );
}

Map<String, Object?> _packageEntryToJson(PackageEntry entry) {
  final source = _packageEntrySource(entry);
  return {
    if (source != null) 'source': source.name,
    if (source != null) 'priority': source.priority,
    'repository': {
      'git': {'url': entry.repository},
      if (entry.repositoryPath != null && entry.repositoryPath != '.')
        'path': entry.repositoryPath,
    },
    'upstream': {
      'git': {'url': entry.upstream, 'branch': entry.upstreamBranch},
      if (entry.upstreamPath != null && entry.upstreamPath != '.')
        'path': entry.upstreamPath,
    },
    if (entry.maintenance != null)
      'maintenance': _maintenanceToJson(entry.maintenance!),
    if (entry.advisory != null && entry.advisory!.toJson().isNotEmpty)
      'advisory': entry.advisory!.toJson(),
    'sdks': _packageSdksToJson(entry),
  };
}

Map<String, Object?> _packageSdksToJson(PackageEntry entry) {
  final grouped = <String, List<PackageImplementation>>{};
  for (final implementation in entry.implementations) {
    grouped
        .putIfAbsent(implementation.sdkLine, () => <PackageImplementation>[])
        .add(implementation);
  }
  final sdkLines = grouped.keys.toList(growable: false)..sort();
  return {
    for (final sdkLine in sdkLines)
      sdkLine: {
        'releases': [
          for (final implementation in _sortedImplementations(
            grouped[sdkLine]!,
          ))
            {
              'version': implementation.version,
              'upstreamVersion': implementation.upstreamVersion,
              'status': 'compatible',
              'tag': implementation.tag,
              'repository': {
                'git': {'url': implementation.repository},
                if (implementation.path != null && implementation.path != '.')
                  'path': implementation.path,
              },
              'upstream': {
                'git': {
                  'url': entry.upstream,
                  'branch': implementation.upstreamBranch,
                },
                if (implementation.upstreamPath != null &&
                    implementation.upstreamPath != '.')
                  'path': implementation.upstreamPath,
              },
              if (implementation.sourceName != null)
                'source': implementation.sourceName,
              'priority': implementation.sourcePriority,
            },
        ],
      },
  };
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

SourcePackageMaintenance? _maintenanceFromLock(Object? value) {
  if (value == null) {
    return null;
  }
  final json = _jsonObject(value, 'maintenance');
  return SourcePackageMaintenance(
    status: _optionalString(json['status']) ?? 'active',
    reason: _optionalString(json['reason']),
  );
}

Map<String, Object?> _maintenanceToJson(SourcePackageMaintenance maintenance) {
  return {
    'status': maintenance.status,
    if (maintenance.reason != null) 'reason': maintenance.reason,
  };
}

SourcePackageAdvisory? _advisoryFromLock(Object? value) {
  if (value == null) {
    return null;
  }
  final json = _jsonObject(value, 'advisory');
  return SourcePackageAdvisory(
    message: _optionalString(json['message']),
    alternatives: [
      for (final item in _jsonList(
        json['alternatives'],
        'advisory.alternatives',
        allowNull: true,
      ))
        _alternativeFromLock(item),
    ],
  );
}

SourcePackageAlternative _alternativeFromLock(Object? value) {
  final json = _jsonObject(value, 'advisory.alternatives[]');
  return SourcePackageAlternative(
    name: _requiredString(json['name'], 'advisory.alternatives[].name'),
    reason: _optionalString(json['reason']),
    url: _optionalString(json['url']),
  );
}

({String name, int priority})? _packageEntrySource(PackageEntry entry) {
  for (final implementation in entry.implementations) {
    final sourceName = implementation.sourceName;
    if (sourceName != null) {
      return (name: sourceName, priority: implementation.sourcePriority);
    }
  }
  return null;
}

List<SdkRelease> _sortedSdkReleases(Iterable<SdkRelease> releases) {
  return releases.toList(growable: false)
    ..sort((a, b) => a.version.compareTo(b.version));
}

List<MapEntry<String, PackageEntry>> _sortedPackageEntries(
  Map<String, PackageEntry> packages,
) {
  return packages.entries.toList(growable: false)
    ..sort((a, b) => a.key.compareTo(b.key));
}

List<PackageImplementation> _sortedImplementations(
  Iterable<PackageImplementation> implementations,
) {
  return implementations.toList(growable: false)..sort((a, b) {
    final bySdk = a.sdkLine.compareTo(b.sdkLine);
    if (bySdk != 0) {
      return bySdk;
    }
    final byUpstream = a.upstreamVersion.compareTo(b.upstreamVersion);
    if (byUpstream != 0) {
      return byUpstream;
    }
    return a.version.compareTo(b.version);
  });
}

Map<String, Object?> _normalizedConfig(FluohConfig config) {
  final entries = config.sources.entries.toList(growable: false)
    ..sort((a, b) => a.key.compareTo(b.key));
  return {
    'sources': {
      for (final entry in entries)
        entry.key: {
          'path': entry.value.path,
          if (entry.value.url != null) 'url': entry.value.url,
          'priority': entry.value.priority,
        },
    },
  };
}

Future<String> _snapshotHash(Directory root) async {
  if (!await root.exists()) {
    return _stableHash({'missing': root.path});
  }
  final files = <File>[];
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is File) {
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

Map<String, Object?>? _optionalJsonObject(Object? value, String label) {
  if (value == null) {
    return null;
  }
  return _jsonObject(value, label);
}

List<Object?> _jsonList(Object? value, String label, {bool allowNull = false}) {
  if (value == null && allowNull) {
    return const <Object?>[];
  }
  if (value is! List) {
    throw FormatException('$label must be a JSON list.');
  }
  return value.cast<Object?>();
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
