const fluohSchemaTemplates = <String, String>{
  'project': projectFluohYamlTemplate,
  'pub-repository': pubRepositoryFluohYamlTemplate,
  'source-root': sourceRootYamlTemplate,
  'source-package': sourcePackageManifestYamlTemplate,
  'tool-config': toolConfigJsonTemplate,
};

const projectFluohYamlTemplate = '''
schema: 1

sdk:
  version: 3.35.8-ohos-0.0.3

dependencyPolicy:
  pubspecSection: dependency_overrides
  versionChanges: compatible
''';

const pubRepositoryFluohYamlTemplate = '''
schema: 1
name: camera

sdk:
  version: 3.35.8-ohos-0.0.3

repository:
  git:
    url: git@github.com:FlutterOH/camera.git
    branch: ohos/3.35

upstream:
  git:
    url: https://github.com/flutter/packages
    branch: main

packages:
  camera:
    repository:
      path: packages/camera/camera
    upstream:
      path: packages/camera/camera
    version: 0.1.0
    upstreamVersion: 0.11.0
    status: experimental
''';

const sourceRootYamlTemplate = '''
schema: 1
kind: source
name: flutteroh
description: Flutter OHOS SDK and package implementation source.

repository:
  git:
    url: https://github.com/FlutterOH/pub.git

environment:
  fluoh: ">=0.1.0"

sdk:
  git:
    url: https://gitcode.com/openharmony-tpc/flutter_flutter.git
  versions:
    - 3.35.8-ohos-0.0.3

manifests:
  - name: camera
''';

const sourcePackageManifestYamlTemplate = '''
schema: 1
kind: manifest
name: camera

repository:
  git:
    url: https://github.com/FlutterOH/camera.git

upstream:
  git:
    url: https://github.com/flutter/packages

packages:
  camera:
    repository:
      path: packages/camera/camera
    upstream:
      path: packages/camera/camera
    sdks:
      "3.35":
        releases:
          - version: 0.1.0
            upstreamVersion: 0.11.0
            status: experimental
''';

const toolConfigJsonTemplate = '''
{
  "sources": {
    "flutteroh": {
      "path": ".fluoh/sources/flutteroh",
      "url": "https://github.com/FlutterOH/pub.git",
      "priority": 0
    }
  }
}
''';

String templateContent(String name) {
  final template = fluohSchemaTemplates[name];
  if (template == null) {
    throw ArgumentError('Unknown template "$name".');
  }
  return template;
}
