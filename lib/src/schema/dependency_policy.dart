import 'yaml_utils.dart';

/// Pubspec section where `fluoh deps fix` writes implementation refs.
enum DependencyPubspecSection {
  /// Write implementation refs under `dependency_overrides`.
  dependencyOverrides('dependency_overrides'),

  /// Rewrite direct entries under `dependencies`.
  dependencies('dependencies');

  const DependencyPubspecSection(this.yamlValue);

  /// YAML value used in `dependencyPolicy.pubspecSection`.
  final String yamlValue;
}

/// Policy for upstream version differences when selecting implementations.
enum DependencyVersionChangePolicy {
  /// Allow only semver-compatible implementation upgrades.
  compatible('compatible'),

  /// Allow any implementation version selected by Source data.
  any('any');

  const DependencyVersionChangePolicy(this.yamlValue);

  /// YAML value used in `dependencyPolicy.versionChanges`.
  final String yamlValue;
}

/// Release statuses consumed by default.
const compatibleDependencyReleaseStatuses = <String>{'compatible'};

/// Release statuses consumed when every release state is explicitly included.
const unrestrictedDependencyReleaseStatuses = <String>{
  'compatible',
  'experimental',
  'broken',
};

/// Canonical ordering for dependency release status output.
const dependencyReleaseStatusOrder = <String>[
  'compatible',
  'experimental',
  'broken',
];

/// Orders dependency release statuses for stable user and machine output.
List<String> orderedDependencyReleaseStatuses(Set<String> statuses) {
  return dependencyReleaseStatusOrder
      .where(statuses.contains)
      .toList(growable: false);
}

/// Project-level policy for dependency rewrites.
class DependencyPolicy {
  /// Creates a dependency rewrite policy.
  const DependencyPolicy({
    this.pubspecSection = DependencyPubspecSection.dependencyOverrides,
    this.versionChanges = DependencyVersionChangePolicy.compatible,
    this.allowedReleaseStatuses = compatibleDependencyReleaseStatuses,
  });

  /// Pubspec section selected for dependency rewrites.
  final DependencyPubspecSection pubspecSection;

  /// Version-change policy for implementation selection.
  final DependencyVersionChangePolicy versionChanges;

  /// Source release statuses allowed by the current command.
  final Set<String> allowedReleaseStatuses;

  /// Whether incompatible upstream version changes may still be applied.
  bool get allowAnyVersionChanges =>
      versionChanges == DependencyVersionChangePolicy.any;

  /// Returns a copy with command-selected release status visibility.
  DependencyPolicy copyWithAllowedReleaseStatuses(Set<String> statuses) {
    return DependencyPolicy(
      pubspecSection: pubspecSection,
      versionChanges: versionChanges,
      allowedReleaseStatuses: statuses,
    );
  }
}

/// Parses dependency policy from a project `fluoh.yaml` object.
DependencyPolicy parseDependencyPolicy(Map<String, Object?> yaml) {
  final policy = yaml['dependencyPolicy'];
  if (policy == null) {
    throw const FluohSchemaException(
      'dependencyPolicy in fluoh.yaml is required.',
    );
  }
  if (policy is! Map<String, Object?>) {
    throw const FluohSchemaException(
      'dependencyPolicy in fluoh.yaml must be a YAML map.',
    );
  }
  ensureAllowedKeys(policy, 'dependencyPolicy in fluoh.yaml', {
    'pubspecSection',
    'versionChanges',
  });
  if (!policy.containsKey('pubspecSection')) {
    throw const FluohSchemaException(
      'dependencyPolicy.pubspecSection is required.',
    );
  }
  if (!policy.containsKey('versionChanges')) {
    throw const FluohSchemaException(
      'dependencyPolicy.versionChanges is required.',
    );
  }

  return DependencyPolicy(
    pubspecSection: _pubspecSection(policy['pubspecSection']),
    versionChanges: _versionChanges(policy['versionChanges']),
  );
}

DependencyPubspecSection _pubspecSection(Object? value) {
  if (value == null) {
    return DependencyPubspecSection.dependencyOverrides;
  }
  if (value == DependencyPubspecSection.dependencyOverrides.yamlValue) {
    return DependencyPubspecSection.dependencyOverrides;
  }
  if (value == DependencyPubspecSection.dependencies.yamlValue) {
    return DependencyPubspecSection.dependencies;
  }
  throw const FluohSchemaException(
    'dependencyPolicy.pubspecSection must be "dependency_overrides" or "dependencies".',
  );
}

DependencyVersionChangePolicy _versionChanges(Object? value) {
  if (value == null) {
    return DependencyVersionChangePolicy.compatible;
  }
  if (value == DependencyVersionChangePolicy.compatible.yamlValue) {
    return DependencyVersionChangePolicy.compatible;
  }
  if (value == DependencyVersionChangePolicy.any.yamlValue) {
    return DependencyVersionChangePolicy.any;
  }
  throw const FluohSchemaException(
    'dependencyPolicy.versionChanges must be "compatible" or "any".',
  );
}
