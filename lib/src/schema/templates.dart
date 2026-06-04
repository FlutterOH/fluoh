/// Built-in schema template content keyed by template name.
const fluohSchemaTemplates = <String, String>{
  'project': projectFluohYamlTemplate,
  'package-repository': packageRepositoryFluohYamlTemplate,
  'source-root': sourceRootYamlTemplate,
  'source-package': sourcePackageManifestYamlTemplate,
  'tool-config': toolConfigJsonTemplate,
};

/// Template for a project-level `fluoh.yaml`.
const projectFluohYamlTemplate = '''
schema: 1
kind: project

sdk:
  version: 3.35.8-ohos-0.0.3

dependencyPolicy:
  pubspecSection: dependency_overrides
  versionChanges: compatible
''';

/// Template for a package repository `fluoh.yaml`.
const packageRepositoryFluohYamlTemplate = '''
schema: 1
kind: package

sdk:
  version: 3.35.8-ohos-0.0.3

repository:
  git:
    url: https://github.com/FlutterOH/camera.git
    branch: ohos/3.35/camera

upstream:
  git:
    url: https://github.com/flutter/packages.git
    branch: main

package:
  name: camera
  path: packages/camera/camera
  release:
    version: 0.1.0
    upstream:
      version: 0.11.0
      commit: "0123456789abcdef0123456789abcdef01234567"
    status: experimental
''';

/// Template for a Source root `fluoh.yaml`.
const sourceRootYamlTemplate = '''
schema: 1
kind: source
name: flutteroh
description: Flutter OHOS SDK and package adaptation source.

# repository:
#   git:
#     url: https://github.com/FlutterOH/source.git

sdk:
  git:
    url: https://gitcode.com/CPF-Flutter/flutter_flutter.git
  versions:
    - 3.35.8-ohos-0.0.3
    - 3.35.8-ohos-1.0.1

manifests:
  - name: camera
''';

/// Template for a Source package Manifest YAML file.
const sourcePackageManifestYamlTemplate = '''
schema: 1
kind: manifest

repository:
  git:
    url: https://github.com/FlutterOH/camera.git

upstream:
  git:
    url: https://github.com/flutter/packages.git

package:
  name: camera
  path: packages/camera/camera
  sdks:
    "3.35":
      releases:
        - version: 0.1.0
          upstream:
            version: 0.11.0
            ref: camera-v0.11.0
            commit: "0123456789abcdef0123456789abcdef01234567"
          status: experimental
''';

/// Template for persisted tool configuration JSON.
const toolConfigJsonTemplate = '''
{
  "sources": {
    "flutteroh": {
      "path": ".fluoh/sources/flutteroh",
      "url": "https://github.com/FlutterOH/source.git",
      "priority": 0
    }
  }
}
''';

/// Returns a built-in schema template by [name].
String templateContent(String name) {
  final template = fluohSchemaTemplates[name];
  if (template == null) {
    throw ArgumentError('Unknown template "$name".');
  }
  return template;
}
