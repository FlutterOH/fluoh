import 'dart:io';

import 'package:fluoh/fluoh.dart';
import 'package:test/test.dart';

void main() {
  test('loads the fixture pub source indexes', () async {
    final source = PubSource.directory(Directory('test/fixtures/pub_source'));

    final sdkIndex = await source.loadSdkIndex();
    final packageIndex = await source.loadPackageIndex();
    final compatibilityMatrix = await source.loadCompatibilityMatrix();

    expect(sdkIndex.releases, hasLength(1));
    expect(sdkIndex.releases.single.tag, '3.35.8-ohos-0.0.3');
    expect(sdkIndex.releases.single.line, '3.35');

    expect(packageIndex.packages, contains('camera'));
    expect(
      packageIndex.packages['camera']!.adapters.single.tag,
      'camera-v0.11.0-ohos-3.35.8-1',
    );

    expect(compatibilityMatrix.sdkLines, contains('3.35'));
    expect(compatibilityMatrix.sdkLines['3.35']!.adapted, contains('camera'));
  });

  test('accepts broken package releases without replacements', () async {
    final root = await _createSourceRoot();
    await _writeSdkIndex(root);
    await _writePackageRegistry(root, packageName: 'camera');
    await _writePackageManifest(
      root,
      packageName: 'camera',
      status: 'broken',
      includeReplacement: false,
    );
    final source = PubSource.directory(root);

    final packageIndex = await source.loadPackageIndex();
    final compatibilityMatrix = await source.loadCompatibilityMatrix();

    expect(packageIndex.packages['camera']!.adapters, isEmpty);
    expect(compatibilityMatrix.sdkLines['3.35']!.blocked, ['camera']);
  });

  test('rejects compatible package releases without replacements', () async {
    final root = await _createSourceRoot();
    await _writeSdkIndex(root);
    await _writePackageRegistry(root, packageName: 'camera');
    await _writePackageManifest(
      root,
      packageName: 'camera',
      status: 'compatible',
      includeReplacement: false,
    );
    final source = PubSource.directory(root);

    expect(
      source.loadPackageIndex,
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('Expected package manifest replacement to be a YAML object'),
        ),
      ),
    );
  });

  test(
    'rejects manifests that disagree with the registry package name',
    () async {
      final root = await _createSourceRoot();
      await _writeSdkIndex(root);
      await _writePackageRegistry(root, packageName: 'camera');
      await _writePackageManifest(
        root,
        packageName: 'path_provider',
        fileName: 'camera',
        status: 'compatible',
      );
      final source = PubSource.directory(root);

      expect(
        source.loadPackageIndex,
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains(
              'Package manifest "path_provider" does not match registry package '
              '"camera"',
            ),
          ),
        ),
      );
    },
  );
}

Future<Directory> _createSourceRoot() async {
  final root = await Directory.systemTemp.createTemp('fluoh_pub_source_');
  addTearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });
  await Directory('${root.path}/sdk').create(recursive: true);
  await Directory('${root.path}/packages/manifests').create(recursive: true);
  return root;
}

Future<void> _writeSdkIndex(Directory root) async {
  await File('${root.path}/sdk/index.yaml').writeAsString('''
schema: 1
repositoryUrl: /tmp/flutter-ohos-sdk
versions:
  - version: 3.35.8-ohos-0.0.3
    tag: 3.35.8-ohos-0.0.3
    versionSeries: "3.35"
    status: stable
''');
}

Future<void> _writePackageRegistry(
  Directory root, {
  required String packageName,
}) async {
  await File('${root.path}/packages/registry.yaml').writeAsString('''
schema: 1
packages:
  - name: $packageName
    repositoryUrl: /tmp/$packageName
    upstreamUrl: https://github.com/example/$packageName
    packagePath: packages/$packageName
    status: compatible
''');
}

Future<void> _writePackageManifest(
  Directory root, {
  required String packageName,
  String? fileName,
  required String status,
  bool includeReplacement = true,
}) async {
  await File(
    '${root.path}/packages/manifests/${fileName ?? packageName}.yaml',
  ).writeAsString('''
schema: 1
package:
  name: $packageName
  repositoryUrl: /tmp/$packageName
  upstreamUrl: https://github.com/example/$packageName
  packagePath: packages/$packageName
releases:
  - version: 1.0.0
    upstreamRef: v1.0.0
    sdk:
      versionSeries: "3.35"
      versionRange: ">=3.35.8 <3.36.0"
      versions:
        - 3.35.8-ohos-0.0.3
    status: $status
    sourceBranch: ohos-3.35
    release:
      version: "1"
      tag: $packageName-v1.0.0-ohos-3.35.8-1
${includeReplacement ? '''
    replacement:
      type: git
      url: /tmp/$packageName
      ref: $packageName-v1.0.0-ohos-3.35.8-1
      path: packages/$packageName
''' : ''}
''');
}
