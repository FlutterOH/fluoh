import 'dart:io';

import 'package:yaml/yaml.dart';

Future<String?> readProjectSdkTag(Directory workingDirectory) async {
  final fluohYaml = File('${workingDirectory.path}/fluoh.yaml');
  if (!await fluohYaml.exists()) {
    return null;
  }

  final loaded = loadYaml(await fluohYaml.readAsString());
  if (loaded is! YamlMap) {
    return null;
  }

  final sdk = loaded['sdk'];
  if (sdk is YamlMap && sdk['version'] != null) {
    return '${sdk['version']}';
  }

  final fluoh = loaded['fluoh'];
  if (fluoh is YamlMap && fluoh['sdkVersion'] != null) {
    return '${fluoh['sdkVersion']}';
  }

  return null;
}
