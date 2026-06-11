import 'dart:io';

import 'package:pub_semver/pub_semver.dart';

import 'manifest/pubspec_package.dart';
import 'upstream_package_ref.dart';

/// Package selection metadata used to check the selected FlutterOH SDK.
class SelectedPackageForSdkCompatibility {
  /// Creates package selection metadata for SDK compatibility checks.
  const SelectedPackageForSdkCompatibility({
    required this.package,
    required this.path,
    this.upstreamRef,
  });

  /// Selected upstream package metadata.
  final PubspecPackage package;

  /// Package path inside the upstream repository.
  final String path;

  /// Selected upstream release tag or user-provided ref, when known.
  final String? upstreamRef;
}

/// Warning emitted when the selected package target needs a newer Dart SDK.
class PackageSdkCompatibilityWarning {
  /// Creates a Dart SDK compatibility warning for a package target.
  const PackageSdkCompatibilityWarning({
    required this.packageName,
    required this.packagePath,
    required this.selectedRef,
    required this.selectedVersion,
    required this.selectedDartConstraint,
    required this.sdkDartVersion,
    required this.latestCompatibleRef,
  });

  /// Package name.
  final String packageName;

  /// Package path inside the upstream repository.
  final String packagePath;

  /// Selected upstream release tag, ref, or package version.
  final String selectedRef;

  /// Selected package version.
  final String selectedVersion;

  /// Dart SDK constraint declared by the selected package.
  final String? selectedDartConstraint;

  /// Dart SDK version provided by the selected FlutterOH SDK.
  final Version sdkDartVersion;

  /// Latest older upstream tag compatible with the selected Dart SDK.
  final PackageReleaseRef? latestCompatibleRef;

  /// Human-readable warning message.
  String get message =>
      'Selected upstream $selectedRef for $packageName requires Dart '
      '$selectedDartConstraint, but the selected FlutterOH SDK provides '
      'Dart $sdkDartVersion.';

  /// Recommended next step.
  String get nextStep {
    final compatible = latestCompatibleRef;
    final keepLatest =
        'Keep adapting the selected upstream target $selectedRef. Adapt the '
        'package pubspec, example config, and Dart code to the selected '
        'FlutterOH SDK Dart $sdkDartVersion, then rerun verify.';
    if (compatible != null) {
      return '$keepLatest Latest compatible upstream tag: ${compatible.ref} '
          '(${compatible.package.version}) is informational only and must not '
          'be used unless maintainers explicitly approve an older baseline.';
    }
    return keepLatest;
  }

  /// Suggested lower SDK constraint compatible with the selected Dart SDK.
  String get suggestedEnvironmentSdkConstraint =>
      '>=${sdkDartVersion.major}.${sdkDartVersion.minor}.0 '
      '<${sdkDartVersion.major + 1}.0.0';

  /// Converts this warning to the machine-output contract.
  Map<String, Object?> toJson() {
    return {
      'code': 'package.dart_sdk_incompatible',
      'severity': 'warning',
      'message': message,
      'nextStep': nextStep,
      'package': {'name': packageName, 'path': packagePath},
      'selected': {
        'ref': selectedRef,
        'version': selectedVersion,
        'dartConstraint': selectedDartConstraint,
      },
      'sdk': {'dartVersion': sdkDartVersion.toString()},
      'policy': {
        'defaultAction': 'adapt-selected-upstream-to-selected-sdk',
        'keepSelectedUpstream': true,
        'adjustPackageForSelectedSdk': true,
        'suggestedEnvironmentSdkConstraint': suggestedEnvironmentSdkConstraint,
        'olderBaselineRequiresApproval': latestCompatibleRef != null,
        'sdkUpgradeOptional': true,
      },
      if (latestCompatibleRef != null)
        'latestCompatible': {
          'ref': latestCompatibleRef!.ref,
          'version': latestCompatibleRef!.package.version,
        },
    };
  }
}

/// Returns warnings for selected packages that do not satisfy [sdkDirectory].
Future<List<PackageSdkCompatibilityWarning>> packageSdkCompatibilityWarnings({
  required Directory repository,
  required List<SelectedPackageForSdkCompatibility> selectedPackages,
  required Directory sdkDirectory,
}) async {
  final dartVersion = await dartVersionForFlutterSdk(sdkDirectory);
  if (dartVersion == null) {
    return const [];
  }
  final warnings = <PackageSdkCompatibilityWarning>[];
  for (final selected in selectedPackages) {
    final constraint = dartSdkConstraint(selected.package);
    if (constraint == null || constraint.allows(dartVersion)) {
      continue;
    }
    final refs = await packageReleaseRefs(
      repository: repository,
      packageName: selected.package.name,
      packagePath: selected.path,
    );
    PackageReleaseRef? compatibleRef;
    for (final candidate in refs.reversed) {
      final candidateConstraint = dartSdkConstraint(candidate.package);
      if (candidateConstraint == null ||
          candidateConstraint.allows(dartVersion)) {
        compatibleRef = candidate;
        break;
      }
    }
    warnings.add(
      PackageSdkCompatibilityWarning(
        packageName: selected.package.name,
        packagePath: selected.path,
        selectedRef: selected.upstreamRef ?? selected.package.version,
        selectedVersion: selected.package.version,
        selectedDartConstraint: selected.package.sdkConstraint,
        sdkDartVersion: dartVersion,
        latestCompatibleRef:
            compatibleRef != null && compatibleRef.ref != selected.upstreamRef
            ? compatibleRef
            : null,
      ),
    );
  }
  return warnings;
}

/// Parses a package Dart SDK constraint.
VersionConstraint? dartSdkConstraint(PubspecPackage package) {
  final constraint = package.sdkConstraint?.trim();
  if (constraint == null || constraint.isEmpty) {
    return null;
  }
  try {
    return VersionConstraint.parse(constraint);
  } on FormatException {
    return null;
  }
}

/// Reads the Dart version bundled with a Flutter SDK directory.
Future<Version?> dartVersionForFlutterSdk(Directory sdkDirectory) async {
  final dart = File('${sdkDirectory.path}/bin/dart');
  if (!await dart.exists()) {
    return null;
  }
  final result = await Process.run(dart.path, const ['--version']);
  final output = '${result.stdout}\n${result.stderr}';
  final match = RegExp(
    r'Dart SDK version:\s*([0-9]+\.[0-9]+\.[0-9]+)',
  ).firstMatch(output);
  if (match == null) {
    return null;
  }
  try {
    return Version.parse(match.group(1)!);
  } on FormatException {
    return null;
  }
}
