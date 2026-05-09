import 'package:args/command_runner.dart';
import 'package:yaml/yaml.dart';

import '../version.dart';

const supportedFluohYamlSchema = 1;

void ensureSupportedFluohYamlSchema(
  YamlMap yaml, {
  String label = 'fluoh.yaml',
}) {
  final schema = yaml['schema'];
  if (schema == null) {
    throw UsageException('$label missing "schema".', '');
  }
  if (schema is! int) {
    throw UsageException('$label schema must be an integer.', '');
  }
  if (schema != supportedFluohYamlSchema) {
    throw UsageException(
      '$label schema $schema is not supported by fluoh $packageVersion. '
          'Upgrade fluoh and try again.',
      '',
    );
  }
}
