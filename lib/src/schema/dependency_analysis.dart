import 'package:pub_semver/pub_semver.dart';

import 'dependency_policy.dart';
import 'pubspec.dart';
import 'source_index.dart';

/// Compatibility status for one dependency on the selected FlutterOH SDK.
enum DependencyStatus {
  native('native'),
  implemented('implemented'),
  versionUpgrade('version-upgrade'),
  sdkMismatch('sdk-mismatch'),
  incompatibleVersion('incompatible-version'),
  unknown('unknown'),
  blocked('blocked');

  const DependencyStatus(this.label);

  /// Stable label used in JSON output and human summaries.
  final String label;
}

/// Dependency compatibility report for a project and SDK version.
class DependencyReport {
  /// Creates a dependency compatibility report.
  const DependencyReport({
    required this.sdkVersion,
    required this.dependencies,
  });

  /// Selected FlutterOH SDK version used for analysis.
  final String sdkVersion;

  /// Compatibility rows for project dependencies.
  final List<DependencyCompatibility> dependencies;

  /// Converts the report to CLI machine output fields.
  Map<String, Object?> toJson() {
    return {
      'sdkVersion': sdkVersion,
      'dependencies': dependencies
          .map((dependency) => dependency.toJson())
          .toList(),
    };
  }
}

/// Compatibility decision for one locked package.
class DependencyCompatibility {
  /// Creates a dependency compatibility row.
  const DependencyCompatibility({
    required this.name,
    required this.version,
    required this.direct,
    required this.status,
    this.implementation,
    this.advisory,
    this.dependencyChain = const <String>[],
  });

  /// Package name.
  final String name;

  /// Locked package version.
  final String version;

  /// Whether this package is a direct project dependency.
  final bool direct;

  /// Compatibility status for this dependency.
  final DependencyStatus status;

  /// Selected FlutterOH implementation, when one is available.
  final PackageImplementation? implementation;

  /// Source advisory attached to this package, when present.
  final SourcePackageAdvisory? advisory;

  /// Direct-to-transitive dependency chain for this package.
  final List<String> dependencyChain;

  /// Converts the compatibility row to JSON.
  Map<String, Object?> toJson() {
    return {
      'name': name,
      'version': version,
      'direct': direct,
      'status': status.label,
      if (implementation != null) 'implementationTag': implementation!.tag,
      if (implementation?.path != null)
        'implementationPath': implementation!.path,
      if (advisory != null) 'advisory': advisory!.toJson(),
      'dependencyChain': dependencyChain,
    };
  }
}

/// Classifies dependency status from source index and lockfile evidence.
DependencyStatus dependencyStatusFor(
  PubLockPackage locked, {
  required String? supportStatus,
  required List<PackageImplementation>? implementations,
  required List<PackageImplementation>? implementationForVersion,
  required PackageImplementation? selectedImplementation,
}) {
  if (supportStatus == 'native') {
    return DependencyStatus.native;
  }
  if (supportStatus == 'blocked') {
    return DependencyStatus.blocked;
  }
  if (implementationForVersion != null && implementationForVersion.isNotEmpty) {
    if (selectedImplementation?.upstreamVersion == locked.version) {
      return DependencyStatus.implemented;
    }
    if (selectedImplementation != null &&
        isCompatibleUpgrade(
          locked.version,
          selectedImplementation.upstreamVersion,
        )) {
      return DependencyStatus.versionUpgrade;
    }
    return DependencyStatus.incompatibleVersion;
  }
  if (implementations != null && implementations.isNotEmpty) {
    return DependencyStatus.sdkMismatch;
  }
  return DependencyStatus.unknown;
}

/// Selects the best implementation for a locked dependency version.
PackageImplementation? bestImplementationForVersion(
  List<PackageImplementation> implementations,
  String lockedVersion,
) {
  if (implementations.isEmpty) {
    return null;
  }

  final exact = implementations
      .where(
        (implementation) => implementation.upstreamVersion == lockedVersion,
      )
      .toList(growable: false);
  if (exact.isNotEmpty) {
    exact.sort(compareImplementationsDescending);
    return exact.first;
  }

  final compatibleUpgrades = implementations
      .where(
        (implementation) =>
            isCompatibleUpgrade(lockedVersion, implementation.upstreamVersion),
      )
      .toList(growable: false);
  if (compatibleUpgrades.isNotEmpty) {
    compatibleUpgrades.sort(compareImplementationsDescending);
    return compatibleUpgrades.first;
  }

  final sorted = implementations.toList(growable: false)
    ..sort(compareImplementationsDescending);
  return sorted.first;
}

/// Returns whether [implementationVersion] is a semver-compatible upgrade.
bool isCompatibleUpgrade(String lockedVersion, String implementationVersion) {
  final Version locked;
  final Version implementation;
  try {
    locked = Version.parse(lockedVersion);
    implementation = Version.parse(implementationVersion);
  } on FormatException {
    return false;
  }
  if (implementation <= locked) {
    return false;
  }
  return VersionConstraint.compatibleWith(locked).allows(implementation);
}

/// Sorts implementations from newest upstream/sdk/release version to oldest.
int compareImplementationsDescending(
  PackageImplementation a,
  PackageImplementation b,
) {
  final upstream = compareNumericVersion(b.upstreamVersion, a.upstreamVersion);
  if (upstream != 0) {
    return upstream;
  }

  final sdkVersion = compareNumericVersion(b.sdkVersion, a.sdkVersion);
  if (sdkVersion != 0) {
    return sdkVersion;
  }

  return compareNumericVersion(
    implementationVersionFromTag(b.tag),
    implementationVersionFromTag(a.tag),
  );
}

/// Extracts the package release version suffix from an implementation tag.
String implementationVersionFromTag(String tag) {
  final match = RegExp(r'-([0-9]+(?:\.[0-9]+)*)$').firstMatch(tag);
  return match?.group(1) ?? '0';
}

/// Compares dot-separated numeric version-like strings.
int compareNumericVersion(String a, String b) {
  final aParts = numericParts(a);
  final bParts = numericParts(b);
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

/// Extracts numeric components from a version-like string.
List<int> numericParts(String version) {
  return RegExp(r'\d+')
      .allMatches(version)
      .map((match) => int.parse(match.group(0)!))
      .toList(growable: false);
}

/// Purpose for building a dependency rewrite plan.
enum DependencyPlanPurpose { fix, upgrade }

/// Status for one dependency rewrite plan entry.
enum DependencyPlanStatus {
  ready,
  alreadyCurrent,
  incompatibleVersion,
  overrideExists,
  native,
  blocked,
  sdkMismatch,
  unknown,
  transitive,
}

/// Planned dependency changes for a project.
class DependencyPlan {
  /// Creates a dependency rewrite plan.
  const DependencyPlan({
    required this.sdkVersion,
    required this.policy,
    required this.purpose,
    required this.entries,
  });

  /// Selected FlutterOH SDK version used for the plan.
  final String sdkVersion;

  /// Dependency rewrite policy read from project config.
  final DependencyPolicy policy;

  /// Whether the plan is for fixing or upgrading replacements.
  final DependencyPlanPurpose purpose;

  /// Plan entries for each dependency row.
  final List<DependencyPlanEntry> entries;

  /// Flattened pubspec changes from actionable entries.
  List<PubspecDependencyChange> get changes {
    return [
      for (final entry in entries)
        for (final change in entry.changes) change,
    ];
  }

  /// Entries that would modify pubspec content.
  List<DependencyPlanEntry> get actionableEntries {
    return entries.where((entry) => entry.changes.isNotEmpty).toList();
  }

  /// Converts the plan to CLI JSON fields.
  Map<String, Object?> toJson() {
    return {
      'sdkVersion': sdkVersion,
      'pubspecSection': policy.pubspecSection.yamlValue,
      'versionChanges': policy.versionChanges.yamlValue,
      'dependencies': entries.map((entry) => entry.toJson()).toList(),
    };
  }
}

/// Planned action for one dependency.
class DependencyPlanEntry {
  /// Creates a dependency plan entry.
  const DependencyPlanEntry({
    required this.dependency,
    required this.status,
    required this.reason,
    this.recommendedAction,
    this.changes = const <PubspecDependencyChange>[],
  });

  /// Compatibility row this entry is based on.
  final DependencyCompatibility dependency;

  /// Plan status for the dependency.
  final DependencyPlanStatus status;

  /// Human-readable reason for the status.
  final String reason;

  /// Stable action token for automated consumers.
  final String? recommendedAction;

  /// Pubspec changes required by this entry.
  final List<PubspecDependencyChange> changes;

  /// Whether this entry can modify pubspec content.
  bool get actionable => changes.isNotEmpty;

  /// Converts the entry to JSON.
  Map<String, Object?> toJson() {
    final implementation = dependency.implementation;
    return {
      ...dependency.toJson(),
      'actionable': actionable,
      'recommendedAction': recommendedAction,
      'reason': reason,
      if (implementation != null)
        'implementationRepository': implementation.repository,
      if (implementation != null) 'implementationRef': implementation.tag,
      if (implementation != null)
        'implementationUpstreamVersion': implementation.upstreamVersion,
    };
  }
}

/// Builds a dependency rewrite plan from a compatibility report.
DependencyPlan buildDependencyPlanFromReport({
  required DependencyReport report,
  required PubspecDependencyState state,
  required DependencyPolicy policy,
  required DependencyPlanPurpose purpose,
}) {
  return DependencyPlan(
    sdkVersion: report.sdkVersion,
    policy: policy,
    purpose: purpose,
    entries: [
      for (final dependency in report.dependencies)
        _entryFor(dependency, state: state, policy: policy, purpose: purpose),
    ],
  );
}

DependencyPlanEntry _entryFor(
  DependencyCompatibility dependency, {
  required PubspecDependencyState state,
  required DependencyPolicy policy,
  required DependencyPlanPurpose purpose,
}) {
  final existingOhosRefs = state.ohosRefsFor(dependency.name);
  if (purpose == DependencyPlanPurpose.upgrade) {
    return _upgradeEntry(dependency, existingOhosRefs, policy);
  }

  if (existingOhosRefs.isNotEmpty) {
    return _updateExistingEntry(dependency, existingOhosRefs, policy);
  }

  if (!dependency.direct) {
    return DependencyPlanEntry(
      dependency: dependency,
      status: DependencyPlanStatus.transitive,
      reason: 'Transitive dependency; fluoh only rewrites direct dependencies.',
    );
  }

  return switch (dependency.status) {
    DependencyStatus.implemented => _addImplementationEntry(
      dependency,
      state,
      policy,
    ),
    DependencyStatus.versionUpgrade => _addImplementationEntry(
      dependency,
      state,
      policy,
    ),
    DependencyStatus.incompatibleVersion =>
      policy.allowAnyVersionChanges
          ? _addImplementationEntry(dependency, state, policy)
          : _incompatibleVersionEntry(dependency),
    DependencyStatus.native => DependencyPlanEntry(
      dependency: dependency,
      status: DependencyPlanStatus.native,
      reason: 'Native OHOS support is available.',
    ),
    DependencyStatus.blocked => DependencyPlanEntry(
      dependency: dependency,
      status: DependencyPlanStatus.blocked,
      reason: 'Configured sources mark this package as blocked for OHOS.',
    ),
    DependencyStatus.sdkMismatch => DependencyPlanEntry(
      dependency: dependency,
      status: DependencyPlanStatus.sdkMismatch,
      reason:
          'OHOS implementations exist, but not for the selected Flutter OHOS SDK.',
    ),
    DependencyStatus.unknown => DependencyPlanEntry(
      dependency: dependency,
      status: DependencyPlanStatus.unknown,
      reason: 'No known OHOS implementation is available.',
    ),
  };
}

DependencyPlanEntry _upgradeEntry(
  DependencyCompatibility dependency,
  List<PubspecDependencyRef> existingOhosRefs,
  DependencyPolicy policy,
) {
  if (existingOhosRefs.isEmpty) {
    return DependencyPlanEntry(
      dependency: dependency,
      status: DependencyPlanStatus.transitive,
      reason: 'No existing FlutterOH dependency replacement found.',
    );
  }
  return _updateExistingEntry(dependency, existingOhosRefs, policy);
}

DependencyPlanEntry _updateExistingEntry(
  DependencyCompatibility dependency,
  List<PubspecDependencyRef> existingOhosRefs,
  DependencyPolicy policy,
) {
  if (dependency.status != DependencyStatus.implemented &&
      dependency.status != DependencyStatus.versionUpgrade &&
      dependency.status != DependencyStatus.incompatibleVersion) {
    return DependencyPlanEntry(
      dependency: dependency,
      status: _statusForDependency(dependency.status),
      reason: _reasonForDependencyStatus(dependency.status),
    );
  }

  final implementation = dependency.implementation;
  if (implementation == null) {
    return DependencyPlanEntry(
      dependency: dependency,
      status: DependencyPlanStatus.unknown,
      reason:
          'No compatible OHOS implementation is available for the selected SDK.',
    );
  }

  if (dependency.status == DependencyStatus.incompatibleVersion &&
      !policy.allowAnyVersionChanges) {
    return _incompatibleVersionEntry(dependency);
  }

  final changes = [
    for (final ref in existingOhosRefs)
      if (ref.value != implementation.tag)
        PubspecDependencyChange.updateRef(
          packageName: dependency.name,
          implementation: implementation,
          section: ref.section,
          currentRef: ref.value,
        ),
  ];
  if (changes.isEmpty) {
    return DependencyPlanEntry(
      dependency: dependency,
      status: DependencyPlanStatus.alreadyCurrent,
      reason:
          'Existing FlutterOH dependency replacements already match the recommended replacement.',
    );
  }

  return DependencyPlanEntry(
    dependency: dependency,
    status: DependencyPlanStatus.ready,
    reason: 'Existing FlutterOH dependency replacements can be upgraded.',
    recommendedAction: 'upgrade-existing-ref',
    changes: changes,
  );
}

DependencyPlanEntry _addImplementationEntry(
  DependencyCompatibility dependency,
  PubspecDependencyState state,
  DependencyPolicy policy,
) {
  final implementation = dependency.implementation!;
  if (policy.pubspecSection == DependencyPubspecSection.dependencyOverrides) {
    if (state.overrideNames.contains(dependency.name)) {
      return DependencyPlanEntry(
        dependency: dependency,
        status: DependencyPlanStatus.overrideExists,
        reason: 'dependency_overrides already contains this package.',
      );
    }
    return DependencyPlanEntry(
      dependency: dependency,
      status: DependencyPlanStatus.ready,
      reason: 'A matching OHOS implementation is available.',
      recommendedAction: 'write-override',
      changes: [
        PubspecDependencyChange.writeOverride(
          packageName: dependency.name,
          implementation: implementation,
        ),
      ],
    );
  }

  return DependencyPlanEntry(
    dependency: dependency,
    status: DependencyPlanStatus.ready,
    reason: 'A matching OHOS implementation is available.',
    recommendedAction: 'rewrite-dependency',
    changes: [
      PubspecDependencyChange.rewriteDependency(
        packageName: dependency.name,
        implementation: implementation,
      ),
    ],
  );
}

DependencyPlanEntry _incompatibleVersionEntry(
  DependencyCompatibility dependency,
) {
  final implementation = dependency.implementation!;
  return DependencyPlanEntry(
    dependency: dependency,
    status: DependencyPlanStatus.incompatibleVersion,
    reason:
        'OHOS implementation targets upstream ${implementation.upstreamVersion}, but pubspec.lock '
        'uses ${dependency.version}.',
  );
}

DependencyPlanStatus _statusForDependency(DependencyStatus status) {
  return switch (status) {
    DependencyStatus.native => DependencyPlanStatus.native,
    DependencyStatus.implemented => DependencyPlanStatus.ready,
    DependencyStatus.versionUpgrade => DependencyPlanStatus.ready,
    DependencyStatus.incompatibleVersion =>
      DependencyPlanStatus.incompatibleVersion,
    DependencyStatus.sdkMismatch => DependencyPlanStatus.sdkMismatch,
    DependencyStatus.unknown => DependencyPlanStatus.unknown,
    DependencyStatus.blocked => DependencyPlanStatus.blocked,
  };
}

/// Formats an upstream version change note for a dependency rewrite.
String implementationUpstreamVersionChange(
  PubspecDependencyChange change,
  DependencyCompatibility dependency,
) {
  final upstreamVersion = change.implementation.upstreamVersion;
  if (upstreamVersion == dependency.version) {
    return '';
  }
  return ' (upstream ${dependency.version} -> $upstreamVersion)';
}

String _reasonForDependencyStatus(DependencyStatus status) {
  return switch (status) {
    DependencyStatus.native => 'Native OHOS support is available.',
    DependencyStatus.implemented =>
      'A matching OHOS implementation is available.',
    DependencyStatus.versionUpgrade =>
      'A compatible OHOS implementation upgrade is available.',
    DependencyStatus.incompatibleVersion =>
      'OHOS implementation upstream version differs.',
    DependencyStatus.sdkMismatch =>
      'OHOS implementations exist, but not for the selected Flutter OHOS SDK.',
    DependencyStatus.unknown => 'No known OHOS implementation is available.',
    DependencyStatus.blocked =>
      'Configured sources mark this package as blocked for OHOS.',
  };
}
