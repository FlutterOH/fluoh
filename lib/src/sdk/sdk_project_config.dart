import 'dart:io';

import 'package:yaml/yaml.dart';

import '../config/fluoh_yaml_schema.dart';

Future<String?> readProjectSdkTag(Directory workingDirectory) async {
  final fluohYaml = await findProjectFluohConfig(workingDirectory);
  if (fluohYaml == null) {
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

Future<File?> findProjectFluohConfig(Directory workingDirectory) async {
  var directory = workingDirectory.absolute;
  while (true) {
    final fluohYaml = File('${directory.path}/fluoh.yaml');
    if (await fluohYaml.exists()) {
      return fluohYaml;
    }

    final parent = directory.parent;
    if (parent.path == directory.path) {
      return null;
    }
    directory = parent;
  }
}
