import 'dart:io';

import '../schema/schema.dart';

/// Reads the selected SDK version from the nearest project `fluoh.yaml`.
Future<String?> readProjectSdkVersion(Directory workingDirectory) async {
  final fluohYaml = await findProjectFluohConfig(workingDirectory);
  if (fluohYaml == null) {
    return null;
  }

  final content = await fluohYaml.readAsString();
  if (content.trim().isEmpty) {
    return null;
  }
  final yaml = parseYamlMap(content, label: fluohYaml.path);
  final kind = yaml['kind'];
  if (kind == packageManifestKind) {
    return PackageManifest.parse(content).sdkVersion;
  }
  if (kind != null && kind != projectConfigKind) {
    return null;
  }
  return ProjectFluohConfig.parse(content).sdkVersion;
}

/// Finds the nearest project `fluoh.yaml` by walking up from [workingDirectory].
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
