import 'package:yaml/yaml.dart';

const supportedFluohYamlSchema = 1;

class FluohSchemaException implements FormatException {
  const FluohSchemaException(this.message, [this.source, this.offset]);

  @override
  final String message;

  @override
  final dynamic source;

  @override
  final int? offset;

  @override
  String toString() => FormatException(message, source, offset).toString();
}

Map<String, Object?> parseYamlMap(String content, {required String label}) {
  final loaded = loadYaml(content);
  final converted = yamlValue(loaded);
  if (converted is! Map<String, Object?>) {
    throw FluohSchemaException('$label must contain a YAML map.');
  }
  return converted;
}

Object? yamlValue(Object? value) {
  if (value is YamlMap) {
    return {
      for (final entry in value.nodes.entries)
        _yamlMapKey(entry.key.value): yamlValue(entry.value.value),
    };
  }
  if (value is YamlList) {
    return value.nodes.map((node) => yamlValue(node.value)).toList();
  }
  return value;
}

String _yamlMapKey(Object? value) {
  if (value is String) {
    return value;
  }
  throw const FluohSchemaException('YAML map keys must be strings.');
}

void ensureSupportedSchema(
  Map<String, Object?> yaml, {
  String label = 'fluoh.yaml',
  String? packageVersion,
}) {
  final schema = yaml['schema'];
  if (schema == null) {
    throw FluohSchemaException('$label missing "schema".');
  }
  if (schema is! int) {
    throw FluohSchemaException('$label schema must be an integer.');
  }
  if (schema != supportedFluohYamlSchema) {
    final suffix = packageVersion == null
        ? 'Expected schema $supportedFluohYamlSchema.'
        : 'Upgrade fluoh and try again.';
    final version = packageVersion == null ? '' : ' by fluoh $packageVersion';
    throw FluohSchemaException(
      '$label schema $schema is not supported$version. $suffix',
    );
  }
}

Map<String, Object?> objectMap(Object? value, String label) {
  if (value is! Map<String, Object?>) {
    throw FluohSchemaException('Expected $label to be a YAML object.');
  }
  return value;
}

Map<String, Object?>? optionalObjectMap(Object? value, String label) {
  if (value == null) {
    return null;
  }
  return objectMap(value, label);
}

String requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FluohSchemaException('Expected "$key" to be a non-empty string.');
  }
  return value;
}

String? optionalString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null || '$value'.isEmpty) {
    return null;
  }
  return '$value';
}

void ensureAllowedKeys(
  Map<String, Object?> json,
  String label,
  Set<String> allowed,
) {
  for (final key in json.keys) {
    if (!allowed.contains(key)) {
      throw FluohSchemaException('$label must not contain "$key".');
    }
  }
}

Map<String, Object?> jsonObject(Object? value, String label) {
  if (value is! Map<String, Object?>) {
    throw FluohSchemaException('Expected $label to be a JSON object.');
  }
  return value;
}
