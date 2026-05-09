import 'dart:io';

import 'package:yaml/yaml.dart';

import '../config/fluoh_yaml_schema.dart';

Future<String?> readProjectSdkTag(Directory workingDirectory) async {
  final fluohYaml = File('${workingDirectory.path}/fluoh.yaml');
  if (!await fluohYaml.exists()) {
    return null;
  }

  final loaded = loadYaml(await fluohYaml.readAsString());
  if (loaded is! YamlMap) {
    return null;
  }
  ensureSupportedFluohYamlSchema(loaded);

  final sdk = loaded['sdk'];
  if (sdk is YamlMap && sdk['version'] != null) {
    return '${sdk['version']}';
  }

  return null;
}
