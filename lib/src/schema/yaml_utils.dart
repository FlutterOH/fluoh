import 'package:yaml/yaml.dart';

/// YAML schema version supported by shared fluoh schema parsers.
const supportedFluohYamlSchema = 1;

/// Format exception used for fluoh-owned YAML and JSON schema failures.
class FluohSchemaException implements FormatException {
  /// Creates a schema exception with optional source location data.
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

/// Parses [content] as a YAML map with normalized Dart collection values.
Map<String, Object?> parseYamlMap(String content, {required String label}) {
  final loaded = loadYaml(content);
  final converted = yamlValue(loaded);
  if (converted is! Map<String, Object?>) {
    throw FluohSchemaException('$label must contain a YAML map.');
  }
  return converted;
}

/// Converts `package:yaml` node values into plain Dart values recursively.
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

/// Ensures a YAML object declares the supported fluoh schema version.
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
    if (schema > supportedFluohYamlSchema) {
      final version = packageVersion == null
          ? ''
          : ' Current version is $packageVersion.';
      throw FluohSchemaException(
        '$label schema $schema requires a newer fluoh.$version',
      );
    }
    final suffix = 'Expected schema $supportedFluohYamlSchema.';
    throw FluohSchemaException(
      '$label schema $schema is not supported. $suffix',
    );
  }
}

/// Returns [value] as a JSON/YAML object or throws a schema exception.
Map<String, Object?> objectMap(Object? value, String label) {
  if (value is! Map<String, Object?>) {
    throw FluohSchemaException('Expected $label to be a YAML object.');
  }
  return value;
}

/// Returns [value] as an object when present, otherwise `null`.
Map<String, Object?>? optionalObjectMap(Object? value, String label) {
  if (value == null) {
    return null;
  }
  return objectMap(value, label);
}

/// Reads a required non-empty string field from [json].
String requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FluohSchemaException('Expected "$key" to be a non-empty string.');
  }
  return value;
}

/// Reads an optional string-like field from [json].
String? optionalString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null || '$value'.isEmpty) {
    return null;
  }
  return '$value';
}

/// Ensures [json] contains only keys listed in [allowed].
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

/// Returns [value] as a JSON object or throws a schema exception.
Map<String, Object?> jsonObject(Object? value, String label) {
  if (value is! Map<String, Object?>) {
    throw FluohSchemaException('Expected $label to be a JSON object.');
  }
  return value;
}
