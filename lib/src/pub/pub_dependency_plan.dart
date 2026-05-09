import 'dart:io';

import '../context/fluoh_environment.dart';
import 'pub_dependency_analyzer.dart';
import 'pub_dependency_policy.dart';
import 'pubspec_dependency_editor.dart';

enum PubDependencyPlanPurpose { fix, upgrade }

enum PubDependencyPlanStatus {
  ready,
  alreadyCurrent,
  versionMismatch,
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
      'replacementMode': policy.replacementMode.yamlValue,
      'versionMismatch': policy.versionMismatch.yamlValue,
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
    final adapter = dependency.adapter;
    return {
      ...dependency.toJson(),
      'actionable': actionable,
      'recommendedAction': recommendedAction,
      'reason': reason,
      if (adapter != null) 'adapterRepository': adapter.repository,
      if (adapter != null) 'adapterRef': adapter.tag,
      if (adapter != null) 'adapterUpstreamVersion': adapter.upstreamVersion,
    };
  }
}

Future<PubDependencyPlan> buildPubDependencyPlan({
  required FluohEnvironment environment,
  required PubDependencyPolicy policy,
  required PubDependencyPlanPurpose purpose,
}) async {
  final report = await PubDependencyAnalyzer(environment).analyze();
  final pubspec = File('${environment.workingDirectory.path}/pubspec.yaml');
  final state = await readPubspecDependencyState(pubspec);
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
    DependencyStatus.adapted => _addAdapterEntry(dependency, state, policy),
    DependencyStatus.versionMismatch =>
      policy.allowVersionMismatch
          ? _addAdapterEntry(dependency, state, policy)
          : _versionMismatchEntry(dependency),
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
      reason: 'Adapters exist, but not for the selected Flutter OHOS SDK.',
    ),
    DependencyStatus.unknown => PubDependencyPlanEntry(
      dependency: dependency,
      status: PubDependencyPlanStatus.unknown,
      reason: 'No known OHOS adapter is available.',
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
      reason: 'No existing OHOS adapter ref found.',
    );
  }
  return _updateExistingEntry(dependency, existingOhosRefs, policy);
}

PubDependencyPlanEntry _updateExistingEntry(
  DependencyCompatibility dependency,
  List<PubspecDependencyRef> existingOhosRefs,
  PubDependencyPolicy policy,
) {
  final adapter = dependency.adapter;
  if (adapter == null) {
    return PubDependencyPlanEntry(
      dependency: dependency,
      status: PubDependencyPlanStatus.unknown,
      reason: 'No compatible adapter is available for the selected SDK.',
    );
  }

  if (dependency.status == DependencyStatus.versionMismatch &&
      !policy.allowVersionMismatch) {
    return _versionMismatchEntry(dependency);
  }
  if (dependency.status != DependencyStatus.adapted &&
      dependency.status != DependencyStatus.versionMismatch) {
    return PubDependencyPlanEntry(
      dependency: dependency,
      status: _statusForDependency(dependency.status),
      reason: _reasonForDependencyStatus(dependency.status),
    );
  }

  final changes = [
    for (final ref in existingOhosRefs)
      if (ref.value != adapter.tag)
        PubspecDependencyChange.updateRef(
          packageName: dependency.name,
          adapter: adapter,
          section: ref.section,
          currentRef: ref.value,
        ),
  ];
  if (changes.isEmpty) {
    return PubDependencyPlanEntry(
      dependency: dependency,
      status: PubDependencyPlanStatus.alreadyCurrent,
      reason: 'Existing OHOS adapter refs already match the recommended ref.',
    );
  }

  return PubDependencyPlanEntry(
    dependency: dependency,
    status: PubDependencyPlanStatus.ready,
    reason: 'Existing OHOS adapter refs can be upgraded.',
    recommendedAction: 'upgrade-existing-ref',
    changes: changes,
  );
}

PubDependencyPlanEntry _addAdapterEntry(
  DependencyCompatibility dependency,
  PubspecDependencyState state,
  PubDependencyPolicy policy,
) {
  final adapter = dependency.adapter!;
  if (policy.replacementMode == PubDependencyReplacementMode.overrides) {
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
      reason: 'A matching OHOS adapter is available.',
      recommendedAction: 'write-override',
      changes: [
        PubspecDependencyChange.writeOverride(
          packageName: dependency.name,
          adapter: adapter,
        ),
      ],
    );
  }

  return PubDependencyPlanEntry(
    dependency: dependency,
    status: PubDependencyPlanStatus.ready,
    reason: 'A matching OHOS adapter is available.',
    recommendedAction: 'rewrite-dependency',
    changes: [
      PubspecDependencyChange.rewriteDependency(
        packageName: dependency.name,
        adapter: adapter,
      ),
    ],
  );
}

PubDependencyPlanEntry _versionMismatchEntry(
  DependencyCompatibility dependency,
) {
  final adapter = dependency.adapter!;
  return PubDependencyPlanEntry(
    dependency: dependency,
    status: PubDependencyPlanStatus.versionMismatch,
    reason:
        'Adapter targets upstream ${adapter.upstreamVersion}, but pubspec.lock '
        'uses ${dependency.version}.',
  );
}

PubDependencyPlanStatus _statusForDependency(DependencyStatus status) {
  return switch (status) {
    DependencyStatus.native => PubDependencyPlanStatus.native,
    DependencyStatus.adapted => PubDependencyPlanStatus.ready,
    DependencyStatus.versionMismatch => PubDependencyPlanStatus.versionMismatch,
    DependencyStatus.sdkMismatch => PubDependencyPlanStatus.sdkMismatch,
    DependencyStatus.unknown => PubDependencyPlanStatus.unknown,
    DependencyStatus.blocked => PubDependencyPlanStatus.blocked,
  };
}

String _reasonForDependencyStatus(DependencyStatus status) {
  return switch (status) {
    DependencyStatus.native => 'Native OHOS support is available.',
    DependencyStatus.adapted => 'A matching OHOS adapter is available.',
    DependencyStatus.versionMismatch => 'Adapter upstream version differs.',
    DependencyStatus.sdkMismatch =>
      'Adapters exist, but not for the selected Flutter OHOS SDK.',
    DependencyStatus.unknown => 'No known OHOS adapter is available.',
    DependencyStatus.blocked =>
      'Configured sources mark this package as blocked for OHOS.',
  };
}
