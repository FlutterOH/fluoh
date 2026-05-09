import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:yaml/yaml.dart';

import '../config/fluoh_yaml_schema.dart';

enum PubDependencyReplacementMode {
  overrides('overrides'),
  rewrite('rewrite');

  const PubDependencyReplacementMode(this.yamlValue);

  final String yamlValue;
}

enum PubDependencyVersionMismatchMode {
  skip('skip'),
  allow('allow');

  const PubDependencyVersionMismatchMode(this.yamlValue);

  final String yamlValue;
}

class PubDependencyPolicy {
  const PubDependencyPolicy({
    this.replacementMode = PubDependencyReplacementMode.overrides,
    this.versionMismatch = PubDependencyVersionMismatchMode.skip,
  });

  final PubDependencyReplacementMode replacementMode;
  final PubDependencyVersionMismatchMode versionMismatch;

  bool get allowVersionMismatch =>
      versionMismatch == PubDependencyVersionMismatchMode.allow;
}

Future<PubDependencyPolicy> readPubDependencyPolicy(
  Directory workingDirectory,
) async {
  final config = File('${workingDirectory.path}/fluoh.yaml');
  if (!await config.exists()) {
    return const PubDependencyPolicy();
  }

  final loaded = loadYaml(await config.readAsString());
  if (loaded is! YamlMap) {
    return const PubDependencyPolicy();
  }
  ensureSupportedFluohYamlSchema(loaded);

  final policy = loaded['dependencyPolicy'];
  if (policy == null) {
    return const PubDependencyPolicy();
  }
  if (policy is! YamlMap) {
    throw UsageException(
      'dependencyPolicy in fluoh.yaml must be a YAML map.',
      '',
    );
  }

  return PubDependencyPolicy(
    replacementMode: _replacementMode(policy['replacementMode']),
    versionMismatch: _versionMismatchMode(policy['versionMismatch']),
  );
}

PubDependencyReplacementMode _replacementMode(Object? value) {
  if (value == null) {
    return PubDependencyReplacementMode.overrides;
  }
  if (value == PubDependencyReplacementMode.overrides.yamlValue) {
    return PubDependencyReplacementMode.overrides;
  }
  if (value == PubDependencyReplacementMode.rewrite.yamlValue) {
    return PubDependencyReplacementMode.rewrite;
  }
  throw UsageException(
    'dependencyPolicy.replacementMode must be "overrides" or "rewrite".',
    '',
  );
}

PubDependencyVersionMismatchMode _versionMismatchMode(Object? value) {
  if (value == null) {
    return PubDependencyVersionMismatchMode.skip;
  }
  if (value == PubDependencyVersionMismatchMode.skip.yamlValue) {
    return PubDependencyVersionMismatchMode.skip;
  }
  if (value == PubDependencyVersionMismatchMode.allow.yamlValue) {
    return PubDependencyVersionMismatchMode.allow;
  }
  throw UsageException(
    'dependencyPolicy.versionMismatch must be "skip" or "allow".',
    '',
  );
}
