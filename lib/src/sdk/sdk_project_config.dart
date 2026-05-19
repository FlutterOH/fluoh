import 'dart:io';

import '../schema/schema.dart';

Future<String?> readProjectSdkVersion(Directory workingDirectory) async {
  final fluohYaml = await findProjectFluohConfig(workingDirectory);
  if (fluohYaml == null) {
    return null;
  }

  final content = await fluohYaml.readAsString();
  if (content.trim().isEmpty) {
    return null;
  }
  return ProjectFluohConfig.parse(content).sdkVersion;
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
