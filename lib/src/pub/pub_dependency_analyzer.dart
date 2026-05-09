import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

import '../context/fluoh_environment.dart';
import '../sdk/sdk_project_config.dart';
import '../source/source_index.dart';
import '../source/source_registry.dart';

class PubDependencyAnalyzer {
  const PubDependencyAnalyzer(this.environment);

  final FluohEnvironment environment;

  Future<PubDependencyReport> analyze() async {
    final sdkVersion = await _readSdkVersion();
    final pubspec = await _readYamlFile('pubspec.yaml');
    final lock = await _readYamlFile('pubspec.lock');
    final directDependencies = _directDependencyNames(pubspec);
    final lockedPackages = _lockedPackages(lock);
    final dependencyChains = _dependencyChains(
      lockedPackages,
      directDependencies,
    );

    final registry = SourceRegistry(environment);
    final packageIndex = await registry.loadPackageIndex();
    final compatibilityMatrix = await registry.loadCompatibilityMatrix();
    final compatibility = compatibilityMatrix.sdkVersions[sdkVersion];

    final dependencies = <DependencyCompatibility>[];
    for (final locked in lockedPackages.values) {
      final direct = directDependencies.contains(locked.name);
      final adapters = packageIndex.packages[locked.name]?.adapters;
      final adaptersForVersion = adapters
          ?.where((adapter) => adapter.sdkVersion == sdkVersion)
          .toList(growable: false);
      final bestAdapter = _bestAdapterForVersion(
        adaptersForVersion ?? const <PackageAdapter>[],
        locked.version,
      );

      final status = _statusFor(
        locked,
        compatibility: compatibility,
        adapters: adapters,
        adapterForVersion: adaptersForVersion,
        selectedAdapter: bestAdapter,
      );

      dependencies.add(
        DependencyCompatibility(
          name: locked.name,
          version: locked.version,
          direct: direct,
          status: status,
          adapter: bestAdapter,
          dependencyChain:
              dependencyChains[locked.name] ??
              (direct ? <String>[locked.name] : const <String>['<transitive>']),
        ),
      );
    }

    dependencies.sort((a, b) {
      if (a.direct != b.direct) {
        return a.direct ? -1 : 1;
      }
      return a.name.compareTo(b.name);
    });

    return PubDependencyReport(
      sdkVersion: sdkVersion,
      dependencies: dependencies,
    );
  }

  Future<String> _readSdkVersion() async {
    final sdkTag = await readProjectSdkTag(environment.workingDirectory);
    if (sdkTag != null) {
      return sdkTag;
    }

    throw UsageException(
      'No SDK version found. Run "fluoh sdk use <version-or-series>".',
      '',
    );
  }

  Future<YamlMap> _readYamlFile(String name) async {
    final file = File('${environment.workingDirectory.path}/$name');
    if (!await file.exists()) {
      throw UsageException('Missing $name in the current project.', '');
    }

    final loaded = loadYaml(await file.readAsString());
    if (loaded is! YamlMap) {
      throw UsageException('$name must contain a YAML map.', '');
    }
    return loaded;
  }

  Set<String> _directDependencyNames(YamlMap pubspec) {
    final dependencies = pubspec['dependencies'];
    if (dependencies is! YamlMap) {
      return const {};
    }

    return dependencies.nodes.keys
        .map((key) => key.value)
        .whereType<String>()
        .where((name) {
          final value = dependencies[name];
          return !(value is YamlMap && value['sdk'] == 'flutter');
        })
        .toSet();
  }

  Map<String, LockedPackage> _lockedPackages(YamlMap lock) {
    final packages = lock['packages'];
    if (packages is! YamlMap) {
      throw UsageException('pubspec.lock packages must be a map.', '');
    }

    return packages.nodes.map((key, value) {
      final name = key.value as String;
      final package = value.value as YamlMap;
      return MapEntry(
        name,
        LockedPackage(
          name: name,
          version: package['version'] as String? ?? '',
          dependencies: _packageDependencies(package),
        ),
      );
    });
  }

  List<String> _packageDependencies(YamlMap package) {
    final dependencies = package['dependencies'];
    if (dependencies is! YamlMap) {
      return const [];
    }
    return dependencies.nodes.keys
        .map((key) => key.value)
        .whereType<String>()
        .toList(growable: false);
  }

  Map<String, List<String>> _dependencyChains(
    Map<String, LockedPackage> packages,
    Set<String> directDependencies,
  ) {
    final chains = <String, List<String>>{};
    final queue = <List<String>>[];
    for (final direct in directDependencies) {
      if (!packages.containsKey(direct)) {
        continue;
      }
      final chain = <String>[direct];
      chains[direct] = chain;
      queue.add(chain);
    }

    for (var index = 0; index < queue.length; index += 1) {
      final chain = queue[index];
      final package = packages[chain.last];
      if (package == null) {
        continue;
      }
      for (final dependency in package.dependencies) {
        if (!packages.containsKey(dependency) ||
            chains.containsKey(dependency)) {
          continue;
        }
        final next = [...chain, dependency];
        chains[dependency] = next;
        queue.add(next);
      }
    }
    return chains;
  }

  DependencyStatus _statusFor(
    LockedPackage locked, {
    required CompatibilityVersion? compatibility,
    required List<PackageAdapter>? adapters,
    required List<PackageAdapter>? adapterForVersion,
    required PackageAdapter? selectedAdapter,
  }) {
    if (compatibility?.native.contains(locked.name) ?? false) {
      return DependencyStatus.native;
    }
    if (compatibility?.blocked.contains(locked.name) ?? false) {
      return DependencyStatus.blocked;
    }
    if (adapterForVersion != null && adapterForVersion.isNotEmpty) {
      if (selectedAdapter?.upstreamVersion == locked.version) {
        return DependencyStatus.adapted;
      }
      if (selectedAdapter != null &&
          _isCompatibleUpgrade(
            locked.version,
            selectedAdapter.upstreamVersion,
          )) {
        return DependencyStatus.versionUpgrade;
      }
      return DependencyStatus.versionMismatch;
    }
    if (adapters != null && adapters.isNotEmpty) {
      return DependencyStatus.sdkMismatch;
    }
    return DependencyStatus.unknown;
  }
}

PackageAdapter? _bestAdapterForVersion(
  List<PackageAdapter> adapters,
  String lockedVersion,
) {
  if (adapters.isEmpty) {
    return null;
  }

  final exact = adapters
      .where((adapter) => adapter.upstreamVersion == lockedVersion)
      .toList(growable: false);
  if (exact.isNotEmpty) {
    exact.sort(_compareAdaptersDescending);
    return exact.first;
  }

  final compatibleUpgrades = adapters
      .where(
        (adapter) =>
            _isCompatibleUpgrade(lockedVersion, adapter.upstreamVersion),
      )
      .toList(growable: false);
  if (compatibleUpgrades.isNotEmpty) {
    compatibleUpgrades.sort(_compareAdaptersDescending);
    return compatibleUpgrades.first;
  }

  final sorted = adapters.toList(growable: false)
    ..sort(_compareAdaptersDescending);
  return sorted.first;
}

bool _isCompatibleUpgrade(String lockedVersion, String adapterVersion) {
  final Version locked;
  final Version adapter;
  try {
    locked = Version.parse(lockedVersion);
    adapter = Version.parse(adapterVersion);
  } on FormatException {
    return false;
  }
  if (adapter <= locked) {
    return false;
  }
  return VersionConstraint.compatibleWith(locked).allows(adapter);
}

int _compareAdaptersDescending(PackageAdapter a, PackageAdapter b) {
  final upstream = _compareNumericVersion(b.upstreamVersion, a.upstreamVersion);
  if (upstream != 0) {
    return upstream;
  }

  final sdkVersion = _compareNumericVersion(b.sdkVersion, a.sdkVersion);
  if (sdkVersion != 0) {
    return sdkVersion;
  }

  return _compareNumericVersion(
    _adapterVersionFromTag(b.tag),
    _adapterVersionFromTag(a.tag),
  );
}

String _adapterVersionFromTag(String tag) {
  final match = RegExp(r'-([0-9]+(?:\.[0-9]+)*)$').firstMatch(tag);
  return match?.group(1) ?? '0';
}

int _compareNumericVersion(String a, String b) {
  final aParts = _numericParts(a);
  final bParts = _numericParts(b);
  final length = aParts.length > bParts.length ? aParts.length : bParts.length;
  for (var i = 0; i < length; i += 1) {
    final aPart = i < aParts.length ? aParts[i] : 0;
    final bPart = i < bParts.length ? bParts[i] : 0;
    final compared = aPart.compareTo(bPart);
    if (compared != 0) {
      return compared;
    }
  }
  return 0;
}

List<int> _numericParts(String version) {
  return RegExp(r'\d+')
      .allMatches(version)
      .map((match) => int.parse(match.group(0)!))
      .toList(growable: false);
}

class PubDependencyReport {
  const PubDependencyReport({
    required this.sdkVersion,
    required this.dependencies,
  });

  final String sdkVersion;
  final List<DependencyCompatibility> dependencies;

  Map<String, Object?> toJson() {
    return {
      'sdkVersion': sdkVersion,
      'dependencies': dependencies
          .map((dependency) => dependency.toJson())
          .toList(),
    };
  }
}

class DependencyCompatibility {
  const DependencyCompatibility({
    required this.name,
    required this.version,
    required this.direct,
    required this.status,
    this.adapter,
    this.dependencyChain = const <String>[],
  });

  final String name;
  final String version;
  final bool direct;
  final DependencyStatus status;
  final PackageAdapter? adapter;
  final List<String> dependencyChain;

  Map<String, Object?> toJson() {
    return {
      'name': name,
      'version': version,
      'direct': direct,
      'status': status.label,
      if (adapter != null) 'adapterTag': adapter!.tag,
      if (adapter?.path != null) 'adapterPath': adapter!.path,
      'dependencyChain': dependencyChain,
    };
  }
}

class LockedPackage {
  const LockedPackage({
    required this.name,
    required this.version,
    this.dependencies = const <String>[],
  });

  final String name;
  final String version;
  final List<String> dependencies;
}

enum DependencyStatus {
  native('native'),
  adapted('adapted'),
  versionUpgrade('version-upgrade'),
  sdkMismatch('sdk-mismatch'),
  versionMismatch('version-mismatch'),
  unknown('unknown'),
  blocked('blocked');

  const DependencyStatus(this.label);

  final String label;
}
