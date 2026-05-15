import 'package:pub_semver/pub_semver.dart';

import 'pub_dependency_policy.dart';
import 'pubspec.dart';
import 'source_index.dart';

enum DependencyStatus {
  native('native'),
  implemented('implemented'),
  versionUpgrade('version-upgrade'),
  sdkMismatch('sdk-mismatch'),
  incompatibleVersion('incompatible-version'),
  unknown('unknown'),
  blocked('blocked');

  const DependencyStatus(this.label);

  final String label;
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
    this.implementation,
    this.advisory,
    this.dependencyChain = const <String>[],
  });

  final String name;
  final String version;
  final bool direct;
  final DependencyStatus status;
  final PackageImplementation? implementation;
  final SourcePackageAdvisory? advisory;
  final List<String> dependencyChain;

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

String implementationVersionFromTag(String tag) {
  final match = RegExp(r'-([0-9]+(?:\.[0-9]+)*)$').firstMatch(tag);
  return match?.group(1) ?? '0';
}

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

List<int> numericParts(String version) {
  return RegExp(r'\d+')
      .allMatches(version)
      .map((match) => int.parse(match.group(0)!))
      .toList(growable: false);
}

enum PubDependencyPlanPurpose { fix, upgrade }

enum PubDependencyPlanStatus {
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

class PubDependencyPlan {
  const PubDependencyPlan({
    required this.sdkVersion,
    required this.policy,
    required this.purpose,
    required this.entries,
  });

  final String sdkVersion;
  final PubDependencyPolicy policy;
  final PubDependencyPlanPurpose purpose;
  final List<PubDependencyPlanEntry> entries;

  List<PubspecDependencyChange> get changes {
    return [
      for (final entry in entries)
        for (final change in entry.changes) change,
    ];
  }

  List<PubDependencyPlanEntry> get actionableEntries {
    return entries.where((entry) => entry.changes.isNotEmpty).toList();
  }

  Map<String, Object?> toJson() {
    return {
      'sdkVersion': sdkVersion,
      'pubspecSection': policy.pubspecSection.yamlValue,
      'versionChanges': policy.versionChanges.yamlValue,
      'dependencies': entries.map((entry) => entry.toJson()).toList(),
    };
  }
}

class PubDependencyPlanEntry {
  const PubDependencyPlanEntry({
    required this.dependency,
    required this.status,
    required this.reason,
    this.recommendedAction,
    this.changes = const <PubspecDependencyChange>[],
  });

  final DependencyCompatibility dependency;
  final PubDependencyPlanStatus status;
  final String reason;
  final String? recommendedAction;
  final List<PubspecDependencyChange> changes;

  bool get actionable => changes.isNotEmpty;

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

PubDependencyPlan buildPubDependencyPlanFromReport({
  required PubDependencyReport report,
  required PubspecDependencyState state,
  required PubDependencyPolicy policy,
  required PubDependencyPlanPurpose purpose,
}) {
  return PubDependencyPlan(
    sdkVersion: report.sdkVersion,
    policy: policy,
    purpose: purpose,
    entries: [
      for (final dependency in report.dependencies)
        _entryFor(dependency, state: state, policy: policy, purpose: purpose),
    ],
  );
}

PubDependencyPlanEntry _entryFor(
  DependencyCompatibility dependency, {
  required PubspecDependencyState state,
  required PubDependencyPolicy policy,
  required PubDependencyPlanPurpose purpose,
}) {
  final existingOhosRefs = state.ohosRefsFor(dependency.name);
  if (purpose == PubDependencyPlanPurpose.upgrade) {
    return _upgradeEntry(dependency, existingOhosRefs, policy);
  }

  if (existingOhosRefs.isNotEmpty) {
    return _updateExistingEntry(dependency, existingOhosRefs, policy);
  }

  if (!dependency.direct) {
    return PubDependencyPlanEntry(
      dependency: dependency,
      status: PubDependencyPlanStatus.transitive,
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
    DependencyStatus.native => PubDependencyPlanEntry(
      dependency: dependency,
      status: PubDependencyPlanStatus.native,
      reason: 'Native OHOS support is available.',
    ),
    DependencyStatus.blocked => PubDependencyPlanEntry(
      dependency: dependency,
      status: PubDependencyPlanStatus.blocked,
      reason: 'Configured sources mark this package as blocked for OHOS.',
    ),
    DependencyStatus.sdkMismatch => PubDependencyPlanEntry(
      dependency: dependency,
      status: PubDependencyPlanStatus.sdkMismatch,
      reason:
          'OHOS implementations exist, but not for the selected Flutter OHOS SDK.',
    ),
    DependencyStatus.unknown => PubDependencyPlanEntry(
      dependency: dependency,
      status: PubDependencyPlanStatus.unknown,
      reason: 'No known OHOS implementation is available.',
    ),
  };
}

PubDependencyPlanEntry _upgradeEntry(
  DependencyCompatibility dependency,
  List<PubspecDependencyRef> existingOhosRefs,
  PubDependencyPolicy policy,
) {
  if (existingOhosRefs.isEmpty) {
    return PubDependencyPlanEntry(
      dependency: dependency,
      status: PubDependencyPlanStatus.transitive,
      reason: 'No existing FlutterOH dependency replacement found.',
    );
  }
  return _updateExistingEntry(dependency, existingOhosRefs, policy);
}

PubDependencyPlanEntry _updateExistingEntry(
  DependencyCompatibility dependency,
  List<PubspecDependencyRef> existingOhosRefs,
  PubDependencyPolicy policy,
) {
  if (dependency.status != DependencyStatus.implemented &&
      dependency.status != DependencyStatus.versionUpgrade &&
      dependency.status != DependencyStatus.incompatibleVersion) {
    return PubDependencyPlanEntry(
      dependency: dependency,
      status: _statusForDependency(dependency.status),
      reason: _reasonForDependencyStatus(dependency.status),
    );
  }

  final implementation = dependency.implementation;
  if (implementation == null) {
    return PubDependencyPlanEntry(
      dependency: dependency,
      status: PubDependencyPlanStatus.unknown,
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
    return PubDependencyPlanEntry(
      dependency: dependency,
      status: PubDependencyPlanStatus.alreadyCurrent,
      reason:
          'Existing FlutterOH dependency replacements already match the recommended replacement.',
    );
  }

  return PubDependencyPlanEntry(
    dependency: dependency,
    status: PubDependencyPlanStatus.ready,
    reason: 'Existing FlutterOH dependency replacements can be upgraded.',
    recommendedAction: 'upgrade-existing-ref',
    changes: changes,
  );
}

PubDependencyPlanEntry _addImplementationEntry(
  DependencyCompatibility dependency,
  PubspecDependencyState state,
  PubDependencyPolicy policy,
) {
  final implementation = dependency.implementation!;
  if (policy.pubspecSection ==
      PubDependencyPubspecSection.dependencyOverrides) {
    if (state.overrideNames.contains(dependency.name)) {
      return PubDependencyPlanEntry(
        dependency: dependency,
        status: PubDependencyPlanStatus.overrideExists,
        reason: 'dependency_overrides already contains this package.',
      );
    }
    return PubDependencyPlanEntry(
      dependency: dependency,
      status: PubDependencyPlanStatus.ready,
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

  return PubDependencyPlanEntry(
    dependency: dependency,
    status: PubDependencyPlanStatus.ready,
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

PubDependencyPlanEntry _incompatibleVersionEntry(
  DependencyCompatibility dependency,
) {
  final implementation = dependency.implementation!;
  return PubDependencyPlanEntry(
    dependency: dependency,
    status: PubDependencyPlanStatus.incompatibleVersion,
    reason:
        'OHOS implementation targets upstream ${implementation.upstreamVersion}, but pubspec.lock '
        'uses ${dependency.version}.',
  );
}

PubDependencyPlanStatus _statusForDependency(DependencyStatus status) {
  return switch (status) {
    DependencyStatus.native => PubDependencyPlanStatus.native,
    DependencyStatus.implemented => PubDependencyPlanStatus.ready,
    DependencyStatus.versionUpgrade => PubDependencyPlanStatus.ready,
    DependencyStatus.incompatibleVersion =>
      PubDependencyPlanStatus.incompatibleVersion,
    DependencyStatus.sdkMismatch => PubDependencyPlanStatus.sdkMismatch,
    DependencyStatus.unknown => PubDependencyPlanStatus.unknown,
    DependencyStatus.blocked => PubDependencyPlanStatus.blocked,
  };
}

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
