import 'yaml_utils.dart';

enum DependencyPubspecSection {
  dependencyOverrides('dependency_overrides'),
  dependencies('dependencies');

  const DependencyPubspecSection(this.yamlValue);

  final String yamlValue;
}

enum DependencyVersionChangePolicy {
  compatible('compatible'),
  any('any');

  const DependencyVersionChangePolicy(this.yamlValue);

  final String yamlValue;
}

class DependencyPolicy {
  const DependencyPolicy({
    this.pubspecSection = DependencyPubspecSection.dependencyOverrides,
    this.versionChanges = DependencyVersionChangePolicy.compatible,
  });

  final DependencyPubspecSection pubspecSection;
  final DependencyVersionChangePolicy versionChanges;

  bool get allowAnyVersionChanges =>
      versionChanges == DependencyVersionChangePolicy.any;
}

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
