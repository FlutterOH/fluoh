import 'package:args/command_runner.dart';
import 'package:yaml/yaml.dart';

import '../schema/schema.dart';
import '../version.dart';

/// Project/config schema version supported by this CLI.
const supportedFluohYamlSchema = 1;

/// Validates a loaded `fluoh.yaml` schema for command callers.
void ensureSupportedFluohYamlSchema(
  YamlMap yaml, {
  String label = 'fluoh.yaml',
}) {
  try {
    final converted = yamlValue(yaml);
    if (converted is! Map<String, Object?>) {
      throw FluohSchemaException('$label must contain a YAML map.');
    }
    ensureSupportedSchema(
      converted,
      label: label,
      packageVersion: packageVersion,
    );
  } on FormatException catch (error) {
    throw UsageException(error.message, '');
  }
}
