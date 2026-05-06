import 'dart:io';

import 'package:fluoh/src/pub/manifest/pub_manifest.dart';
import 'package:fluoh/src/pub/pub_source_writer.dart';
import 'package:test/test.dart';

void main() {
  test('appends new packages to an existing pub source registry', () async {
    final root = await Directory.systemTemp.createTemp('fluoh_pub_source_');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final source = Directory('${root.path}/source');
    final packages = Directory('${source.path}/packages');
    await packages.create(recursive: true);
    await File('${packages.path}/registry.yaml').writeAsString('''
schema: 1
packages:
  - name: camera
    repositoryUrl: git@github.com:FlutterOH/camera.git
''');

    await writePubSourcePackageUpdate(
      source,
      manifest: _manifest(packageName: 'share_plus'),
      releaseTag: 'share_plus-v10.0.0-ohos-3.35.8-0.1.0',
    );

    final registry = await File(
      '${packages.path}/registry.yaml',
    ).readAsString();
    expect(registry, contains('  - name: camera'));
    expect(registry, contains('  - name: share_plus'));
    expect(
      registry,
      contains('    packagePath: packages/share_plus/share_plus'),
    );
    expect(registry, isNot(contains('upstreamUrl:')));
    expect(registry, isNot(contains('status:')));
    final manifest = File(
      '${packages.path}/manifests/share_plus.yaml',
    ).readAsStringSync();
    expect(manifest, contains('      versionSeries: 3.35.8-ohos'));
    expect(manifest, contains('      versions:'));
    expect(manifest, isNot(contains('      version: 3.35.8-ohos-0.0.3')));
    expect(manifest, contains('      path: packages/share_plus/share_plus'));
  });

  test('does not duplicate packages already present in registry', () async {
    final root = await Directory.systemTemp.createTemp('fluoh_pub_source_');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final source = Directory('${root.path}/source');
    final packages = Directory('${source.path}/packages');
    await packages.create(recursive: true);
    await File('${packages.path}/registry.yaml').writeAsString('''
schema: 1
packages:
  - name: camera
    repositoryUrl: git@github.com:FlutterOH/camera.git
''');

    await writePubSourcePackageUpdate(
      source,
      manifest: _manifest(),
      releaseTag: 'camera-v0.11.0-ohos-3.35.8-0.1.0',
    );

    final registry = await File(
      '${packages.path}/registry.yaml',
    ).readAsString();
    expect(
      RegExp(
        r'^\s*-\s+name:\s+camera\s*$',
        multiLine: true,
      ).allMatches(registry),
      hasLength(1),
    );
  });
}

PubManifest _manifest({String packageName = 'camera'}) {
  return PubManifest(
    packageName: packageName,
    upstreamVersion: packageName == 'camera' ? '0.11.0' : '10.0.0',
    sdkVersion: '3.35.8-ohos-0.0.3',
    releaseVersion: '0.1.0',
    branch: 'ohos/3.35.8-ohos',
    releaseTag: '$packageName-release',
    upstreamUrl: 'https://github.com/flutter/packages',
    upstreamPath: 'packages/$packageName/$packageName',
    upstreamRef: '$packageName-upstream',
    adapterUrl: 'git@github.com:FlutterOH/$packageName.git',
    dependencyUrl: 'https://github.com/FlutterOH/$packageName.git',
    dependencyPath: 'packages/$packageName/$packageName',
    status: 'compatible',
  );
}
