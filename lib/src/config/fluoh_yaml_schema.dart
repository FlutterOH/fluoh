import 'package:args/command_runner.dart';
import 'package:yaml/yaml.dart';

import '../schema/schema.dart';
import '../version.dart';

const supportedFluohYamlSchema = 1;

void ensureSupportedFluohYamlSchema(
  YamlMap yaml, {
  String label = 'fluoh.yaml',
}) {
  try {
    final converted = yamlValue(yaml);
    if (converted is! Map<String, Object?>) {
      throw FluohSchemaException('$label must contain a YAML map.');
    }
    final migrated = migrateFluohYamlMap(
      converted,
      owner: FluohYamlOwner.project,
      label: label,
    );
    ensureSupportedSchema(
      migrated.yaml,
      label: label,
      packageVersion: packageVersion,
    );
  } on FormatException catch (error) {
    throw UsageException(error.message, '');
  }
}
