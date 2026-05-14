import 'yaml_utils.dart';

enum PubDependencyPubspecSection {
  dependencyOverrides('dependency_overrides'),
  dependencies('dependencies');

  const PubDependencyPubspecSection(this.yamlValue);

  final String yamlValue;
}

enum PubDependencyVersionChangePolicy {
  compatible('compatible'),
  any('any');

  const PubDependencyVersionChangePolicy(this.yamlValue);

  final String yamlValue;
}

class PubDependencyPolicy {
  const PubDependencyPolicy({
    this.pubspecSection = PubDependencyPubspecSection.dependencyOverrides,
    this.versionChanges = PubDependencyVersionChangePolicy.compatible,
  });

  final PubDependencyPubspecSection pubspecSection;
  final PubDependencyVersionChangePolicy versionChanges;

  bool get allowAnyVersionChanges =>
      versionChanges == PubDependencyVersionChangePolicy.any;
}

PubDependencyPolicy parsePubDependencyPolicy(Map<String, Object?> yaml) {
  final policy = yaml['dependencyPolicy'];
  if (policy == null) {
    return const PubDependencyPolicy();
  }
  if (policy is! Map<String, Object?>) {
    throw const FluohSchemaException(
      'dependencyPolicy in fluoh.yaml must be a YAML map.',
    );
  }

  return PubDependencyPolicy(
    pubspecSection: _pubspecSection(policy['pubspecSection']),
    versionChanges: _versionChanges(policy['versionChanges']),
  );
}

PubDependencyPubspecSection _pubspecSection(Object? value) {
  if (value == null) {
    return PubDependencyPubspecSection.dependencyOverrides;
  }
  if (value == PubDependencyPubspecSection.dependencyOverrides.yamlValue) {
    return PubDependencyPubspecSection.dependencyOverrides;
  }
  if (value == PubDependencyPubspecSection.dependencies.yamlValue) {
    return PubDependencyPubspecSection.dependencies;
  }
  throw const FluohSchemaException(
    'dependencyPolicy.pubspecSection must be "dependency_overrides" or "dependencies".',
  );
}

PubDependencyVersionChangePolicy _versionChanges(Object? value) {
  if (value == null) {
    return PubDependencyVersionChangePolicy.compatible;
  }
  if (value == PubDependencyVersionChangePolicy.compatible.yamlValue) {
    return PubDependencyVersionChangePolicy.compatible;
  }
  if (value == PubDependencyVersionChangePolicy.any.yamlValue) {
    return PubDependencyVersionChangePolicy.any;
  }
  throw const FluohSchemaException(
    'dependencyPolicy.versionChanges must be "compatible" or "any".',
  );
}
