import 'dart:io';

import 'package:fluoh/src/sdk/sdk_project_config.dart';
import 'package:test/test.dart';

void main() {
  test('reads the SDK version from the nearest parent fluoh.yaml', () async {
    final root = await _createTempDirectory();
    final project = Directory('${root.path}/project');
    final testDirectory = Directory('${project.path}/fluoh_test');
    await testDirectory.create(recursive: true);
    await File('${project.path}/fluoh.yaml').writeAsString('''
schema: 1
sdk:
  version: 3.35.8-ohos-0.0.3
''');

    expect(await readProjectSdkVersion(testDirectory), '3.35.8-ohos-0.0.3');
  });

  test('prefers the nearest fluoh.yaml in nested monorepo projects', () async {
    final root = await _createTempDirectory();
    final project = Directory('${root.path}/project');
    final package = Directory('${project.path}/packages/camera');
    await package.create(recursive: true);
    await File('${project.path}/fluoh.yaml').writeAsString('''
schema: 1
sdk:
  version: 3.35.8-ohos-0.0.3
''');
    await File('${package.path}/fluoh.yaml').writeAsString('''
schema: 1
sdk:
  version: 4.0.0-ohos-0.0.1
''');

    expect(await readProjectSdkVersion(package), '4.0.0-ohos-0.0.1');
  });

  test('rejects incomplete SDK versions in project fluoh.yaml', () async {
    final root = await _createTempDirectory();
    await File('${root.path}/fluoh.yaml').writeAsString('''
schema: 1
sdk:
  version: 3.35.8-ohos
''');

    expect(readProjectSdkVersion(root), throwsA(isA<FormatException>()));
  });
}

Future<Directory> _createTempDirectory() async {
  final root = await Directory.systemTemp.createTemp('fluoh_config_test_');
  addTearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });
  return root;
}
