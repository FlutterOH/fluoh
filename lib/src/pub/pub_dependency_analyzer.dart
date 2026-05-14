import 'dart:io';

import 'package:args/command_runner.dart';

import '../context/fluoh_environment.dart';
import '../schema/schema.dart';
import '../sdk/sdk_project_config.dart';
import '../source/source_runtime.dart';

export '../schema/schema.dart'
    show
        DependencyCompatibility,
        DependencyStatus,
        LockedPackage,
        PubDependencyReport;

class PubDependencyAnalyzer {
  const PubDependencyAnalyzer(this.environment);

  final FluohEnvironment environment;

  Future<PubDependencyReport> analyze() async {
    final sdkVersion = await _readSdkVersion();
    final pubspec = await _readRequiredFile('pubspec.yaml');
    final lock = await _readRequiredFile('pubspec.lock');
    final directDependencies = directDependencyNamesFromPubspec(pubspec);
    final lockedPackages = pubLockPackagesFromLock(lock);
    final chains = dependencyChains(lockedPackages, directDependencies);
    final packageNames = lockedPackages.keys.toSet();
    final sdkLine = sdkLineFromSdkVersion(sdkVersion);

    final runtime = SourceRuntime(environment);
    final packageIndex = await runtime.loadPackageIndex(
      packageNames: packageNames,
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

    return PubDependencyReport(
      sdkVersion: sdkVersion,
      dependencies: dependencies,
    );
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
