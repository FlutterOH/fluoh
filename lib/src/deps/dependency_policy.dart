import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:yaml/yaml.dart';

import '../schema/schema.dart';
import '../version.dart';

export '../schema/schema.dart'
    show
        DependencyPolicy,
        DependencyPubspecSection,
        DependencyVersionChangePolicy;

/// Reads dependency rewrite policy from project `fluoh.yaml`.
Future<DependencyPolicy> readDependencyPolicy(
  Directory workingDirectory,
) async {
  final config = File('${workingDirectory.path}/fluoh.yaml');
  if (!await config.exists()) {
    return const DependencyPolicy();
  }

  final loaded = loadYaml(await config.readAsString());
  final yaml = yamlValue(loaded);
  if (yaml is! Map<String, Object?>) {
    return const DependencyPolicy();
  }
  try {
    ensureSupportedSchema(yaml, packageVersion: packageVersion);
    return parseDependencyPolicy(yaml);
  } on FormatException catch (error) {
    throw UsageException(error.message, '');
  }
}
