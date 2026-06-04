import 'dart:io';

import 'package:args/command_runner.dart';

import '../context/fluoh_environment.dart';
import '../schema/schema.dart';
import '../sdk/sdk_project_config.dart';
import '../source/source_runtime.dart';
import 'dependency_policy.dart';

export '../schema/schema.dart'
    show
        DependencyCompatibility,
        DependencyStatus,
        LockedPackage,
        DependencyReport;

/// Analyzes project dependencies against configured FlutterOH Sources.
class DependencyAnalyzer {
  /// Creates a dependency analyzer for [environment].
  const DependencyAnalyzer(this.environment);

  /// Runtime environment for the project and Source config.
  final FluohEnvironment environment;

  /// Builds a dependency compatibility report for the current project.
  Future<DependencyReport> analyze({DependencyPolicy? policy}) async {
    final pubspec = await _readRequiredFile('pubspec.yaml');
    final lock = await _readRequiredFile('pubspec.lock');
    final sdkVersion = await _readSdkVersion();
    final directDependencies = directDependencyNamesFromPubspec(pubspec);
    final lockedPackages = pubLockPackagesFromLock(lock);
    final chains = dependencyChains(lockedPackages, directDependencies);
    final packageNames = lockedPackages.keys.toSet();
    final sdkLine = sdkLineFromSdkVersion(sdkVersion);
    final resolvedPolicy =
        policy ?? await readDependencyPolicy(environment.workingDirectory);

    final runtime = SourceRuntime(environment);
    final packageIndex = await runtime.loadPackageIndex(
      packageNames: packageNames,
      releaseStatuses: resolvedPolicy.allowedReleaseStatuses,
    );

    final dependencies = <DependencyCompatibility>[];
    for (final locked in lockedPackages.values) {
      final direct = directDependencies.contains(locked.name);
      final packageEntry = packageIndex.packages[locked.name];
      final implementations = packageEntry?.implementations;
      final implementationsForVersion = implementations
          ?.where((implementation) => implementation.sdkLine == sdkLine)
          .toList(growable: false);
      final bestImplementation = bestImplementationForVersion(
        implementationsForVersion ?? const <PackageImplementation>[],
        locked.version,
      );

      final status = dependencyStatusFor(
        locked,
        supportStatus: _supportStatusForVersion(
          packageEntry,
          sdkLine: sdkLine,
          upstreamVersion: locked.version,
        ),
        implementations: implementations,
        implementationForVersion: implementationsForVersion,
        selectedImplementation: bestImplementation,
      );

      dependencies.add(
        DependencyCompatibility(
          name: locked.name,
          version: locked.version,
          direct: direct,
          status: status,
          implementation: bestImplementation,
          advisory: packageEntry?.advisory,
          dependencyChain:
              chains[locked.name] ??
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

    return DependencyReport(sdkVersion: sdkVersion, dependencies: dependencies);
  }

  Future<String> _readSdkVersion() async {
    final sdkVersion = await readProjectSdkVersion(
      environment.workingDirectory,
    );
    if (sdkVersion != null) {
      return sdkVersion;
    }

    throw UsageException(
      'No SDK version found. Run "fluoh sdk use <version-or-series>".',
      '',
    );
  }

  Future<String> _readRequiredFile(String name) async {
    final file = File('${environment.workingDirectory.path}/$name');
    if (!await file.exists()) {
      throw UsageException('Missing $name in the current project.', '');
    }
    return file.readAsString();
  }
}

String? _supportStatusForVersion(
  PackageEntry? packageEntry, {
  required String sdkLine,
  required String upstreamVersion,
}) {
  for (final status
      in packageEntry?.compatibility ?? const <SourceCompatibilityStatus>[]) {
    if (status.sdkLine == sdkLine &&
        status.upstreamVersion == upstreamVersion) {
      return status.status;
    }
  }
  return null;
}
