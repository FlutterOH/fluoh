import 'yaml_utils.dart';

/// Pubspec section where `fluoh deps fix` writes implementation refs.
enum DependencyPubspecSection {
  dependencyOverrides('dependency_overrides'),
  dependencies('dependencies');

  const DependencyPubspecSection(this.yamlValue);

  /// YAML value used in `dependencyPolicy.pubspecSection`.
  final String yamlValue;
}

/// Policy for upstream version differences when selecting implementations.
enum DependencyVersionChangePolicy {
  compatible('compatible'),
  any('any');

  const DependencyVersionChangePolicy(this.yamlValue);

  /// YAML value used in `dependencyPolicy.versionChanges`.
  final String yamlValue;
}

/// Project-level policy for dependency rewrites.
class DependencyPolicy {
  /// Creates a dependency rewrite policy.
  const DependencyPolicy({
    this.pubspecSection = DependencyPubspecSection.dependencyOverrides,
    this.versionChanges = DependencyVersionChangePolicy.compatible,
  });

  /// Pubspec section selected for dependency rewrites.
  final DependencyPubspecSection pubspecSection;

  /// Version-change policy for implementation selection.
  final DependencyVersionChangePolicy versionChanges;

  /// Whether incompatible upstream version changes may still be applied.
  bool get allowAnyVersionChanges =>
      versionChanges == DependencyVersionChangePolicy.any;
}

/// Parses dependency policy from a project `fluoh.yaml` object.
DependencyPolicy parseDependencyPolicy(Map<String, Object?> yaml) {
  final policy = yaml['dependencyPolicy'];
  if (policy == null) {
    return const DependencyPolicy();
  }
  if (policy is! Map<String, Object?>) {
    throw const FluohSchemaException(
      'dependencyPolicy in fluoh.yaml must be a YAML map.',
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
