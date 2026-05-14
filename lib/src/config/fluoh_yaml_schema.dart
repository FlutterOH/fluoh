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
    ensureSupportedSchema(
      yamlValue(yaml) as Map<String, Object?>,
      label: label,
      packageVersion: packageVersion,
    );
  } on FormatException catch (error) {
    throw UsageException(error.message, '');
  }
}
