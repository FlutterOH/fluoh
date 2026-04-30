import 'dart:io';

import 'package:args/command_runner.dart';

import '../config/fluoh_config.dart';
import '../context/fluoh_environment.dart';
import '../sdk/sdk_release.dart';
import 'pub_source.dart';

class SourceRegistry {
  const SourceRegistry(this.environment);

  final FluohEnvironment environment;

  Future<SdkIndex> loadSdkIndex() async {
    final sources = await _readableSources(
      requiredFiles: const ['sdk-index.json'],
    );
    final releases = <String, _PrioritizedRelease>{};

    for (final source in sources) {
      final index = await PubSource.directory(
        source.config.directory,
      ).loadSdkIndex();
      for (final release in index.releases) {
        final existing = releases[release.tag];
        if (existing == null ||
            source.config.priority > existing.source.config.priority) {
          releases[release.tag] = _PrioritizedRelease(source, release);
          continue;
        }
        if (source.config.priority == existing.source.config.priority &&
            (release.repository != existing.release.repository ||
                release.version != existing.release.version)) {
          throw UsageException(
            'Conflicting SDK release ${release.tag} in sources '
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

  Future<PackageIndex> loadPackageIndex() async {
    final sources = await _readableSources(
      requiredFiles: const ['package-index.json'],
    );
    final packages = <String, PackageEntry>{};
    final groupPriorities = <String, int>{};
    final seenReplacements = <String, _Replacement>{};

    for (final source in sources) {
      final index = await PubSource.directory(
        source.config.directory,
      ).loadPackageIndex();
      for (final packageEntry in index.packages.entries) {
        final packageName = packageEntry.key;
        final current = packages[packageName];
        final adapters = current == null
            ? <PackageAdapter>[]
            : current.adapters.toList(growable: true);

        for (final adapter in packageEntry.value.adapters) {
          final sourced = adapter.withSource(
            source.name,
            source.config.priority,
          );
          final groupKey =
              '$packageName|${sourced.sdkLine}|${sourced.upstreamVersion}';
          final groupPriority = groupPriorities[groupKey];
          if (groupPriority != null && source.config.priority < groupPriority) {
            continue;
          }
          if (groupPriority == null || source.config.priority > groupPriority) {
            groupPriorities[groupKey] = source.config.priority;
            adapters.removeWhere(
              (existing) =>
                  existing.sdkLine == sourced.sdkLine &&
                  existing.upstreamVersion == sourced.upstreamVersion,
            );
          }

          final replacementKey = '$groupKey|${sourced.tag}';
          final replacement = _Replacement.fromAdapter(sourced, source.name);
          final existingReplacement = seenReplacements[replacementKey];
          if (existingReplacement != null &&
              existingReplacement.priority == source.config.priority &&
              existingReplacement != replacement) {
            throw UsageException(
              'Conflicting package adapter $packageName ${sourced.tag} in '
                  'sources ${existingReplacement.sourceName} and ${source.name}. '
                  'Adjust source priority or select a single source.',
              '',
            );
          }
          seenReplacements[replacementKey] = replacement;
          if (!adapters.any(
            (existing) =>
                existing.repository == sourced.repository &&
                existing.tag == sourced.tag &&
                existing.path == sourced.path,
          )) {
            adapters.add(sourced);
          }
        }

        packages[packageName] = PackageEntry(
          upstream: current?.upstream ?? packageEntry.value.upstream,
          adapters: adapters,
        );
      }
    }

    return PackageIndex(schemaVersion: 1, packages: packages);
  }

  Future<CompatibilityMatrix> loadCompatibilityMatrix() async {
    final sources = await _readableSources(
      requiredFiles: const ['compatibility-matrix.json'],
    );
    final lines = <String, Map<String, _CompatibilityStatus>>{};

    for (final source in sources) {
      final matrix = await PubSource.directory(
        source.config.directory,
      ).loadCompatibilityMatrix();
      for (final entry in matrix.sdkLines.entries) {
        final packages = lines.putIfAbsent(
          entry.key,
          () => <String, _CompatibilityStatus>{},
        );
        _mergeCompatibilityStatus(
          packages,
          sdkLine: entry.key,
          status: 'native',
          packageNames: entry.value.native,
          source: source,
        );
        _mergeCompatibilityStatus(
          packages,
          sdkLine: entry.key,
          status: 'adapted',
          packageNames: entry.value.adapted,
          source: source,
        );
        _mergeCompatibilityStatus(
          packages,
          sdkLine: entry.key,
          status: 'blocked',
          packageNames: entry.value.blocked,
          source: source,
        );
      }
    }

    return CompatibilityMatrix(
      schemaVersion: 1,
      sdkLines: lines.map(
        (sdkLine, packages) => MapEntry(
          sdkLine,
          CompatibilityLine(
            native: _packagesWithStatus(packages, 'native'),
            adapted: _packagesWithStatus(packages, 'adapted'),
            blocked: _packagesWithStatus(packages, 'blocked'),
          ),
        ),
      ),
    );
  }

  Future<List<_NamedSource>> _readableSources({
    required List<String> requiredFiles,
  }) async {
    final config = await FluohConfigStore(environment).load();
    final sources =
        config.sources.entries
            .map((entry) => _NamedSource(entry.key, entry.value))
            .where((source) => _hasGeneratedFiles(source.config, requiredFiles))
            .toList(growable: false)
          ..sort((a, b) {
            final priority = b.config.priority.compareTo(a.config.priority);
            return priority == 0 ? a.name.compareTo(b.name) : priority;
          });

    if (sources.isEmpty) {
      throw UsageException(
        'No readable data source index found. Run "fluoh source update" or '
            '"fluoh source add <name> <path>".',
        '',
      );
    }
    return sources;
  }

  bool _hasGeneratedFiles(SourceConfig source, List<String> fileNames) {
    return fileNames.every(
      (name) => File('${source.directory.path}/generated/$name').existsSync(),
    );
  }

  void _mergeCompatibilityStatus(
    Map<String, _CompatibilityStatus> packages, {
    required String sdkLine,
    required String status,
    required List<String> packageNames,
    required _NamedSource source,
  }) {
    for (final packageName in packageNames) {
      final incoming = _CompatibilityStatus(
        status: status,
        priority: source.config.priority,
        sourceName: source.name,
      );
      final existing = packages[packageName];
      if (existing == null || incoming.priority > existing.priority) {
        packages[packageName] = incoming;
        continue;
      }
      if (incoming.priority == existing.priority &&
          incoming.status != existing.status) {
        throw UsageException(
          'Conflicting compatibility status for $packageName on SDK line '
              '$sdkLine in sources ${existing.sourceName} and ${source.name}. '
              'Adjust source priority or select a single source.',
          '',
        );
      }
    }
  }

  List<String> _packagesWithStatus(
    Map<String, _CompatibilityStatus> packages,
    String status,
  ) {
    return packages.entries
        .where((entry) => entry.value.status == status)
        .map((entry) => entry.key)
        .toList(growable: false)
      ..sort();
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

  factory _Replacement.fromAdapter(PackageAdapter adapter, String sourceName) {
    return _Replacement(
      repository: adapter.repository,
      tag: adapter.tag,
      path: adapter.path,
      priority: adapter.sourcePriority,
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
