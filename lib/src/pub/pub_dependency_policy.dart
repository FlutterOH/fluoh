import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:yaml/yaml.dart';

import '../schema/schema.dart';
import '../version.dart';

export '../schema/schema.dart'
    show
        PubDependencyPolicy,
        PubDependencyPubspecSection,
        PubDependencyVersionChangePolicy;

Future<PubDependencyPolicy> readPubDependencyPolicy(
  Directory workingDirectory,
) async {
  final config = File('${workingDirectory.path}/fluoh.yaml');
  if (!await config.exists()) {
    return const PubDependencyPolicy();
  }

  final loaded = loadYaml(await config.readAsString());
  final yaml = yamlValue(loaded);
  if (yaml is! Map<String, Object?>) {
    return const PubDependencyPolicy();
  }
  try {
    ensureSupportedSchema(yaml, packageVersion: packageVersion);
    return parsePubDependencyPolicy(yaml);
  } on FormatException catch (error) {
    throw UsageException(error.message, '');
  }
}
