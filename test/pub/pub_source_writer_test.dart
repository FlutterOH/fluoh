import 'dart:io';

import 'package:fluoh/src/pub/manifest/pub_manifest.dart';
import 'package:fluoh/src/pub/pub_source_writer.dart';
import 'package:test/test.dart';

void main() {
  test(
    'appends new packages to an existing pub source repositories list',
    () async {
      final root = await Directory.systemTemp.createTemp('fluoh_pub_source_');
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      final source = Directory('${root.path}/source');
      final packages = Directory('${source.path}/packages');
      await packages.create(recursive: true);
      await File('${packages.path}/repositories.yaml').writeAsString('''
schema: 1
repositories:
  - name: camera
    url: git@github.com:FlutterOH/camera.git
''');

      await writePubSourcePackageUpdate(
        source,
        manifest: _manifest(packageName: 'share_plus'),
        releaseTag: 'share_plus-v10.0.0-ohos-3.35.8-0.1.0',
      );

      final repositories = await File(
        '${packages.path}/repositories.yaml',
      ).readAsString();
      expect(repositories, contains('  - name: camera'));
      expect(repositories, contains('  - name: share_plus'));
      expect(
        repositories,
        contains('    packagePath: packages/share_plus/share_plus'),
      );
      expect(
        repositories,
        contains('    url: git@github.com:FlutterOH/share_plus.git'),
      );
      expect(repositories, isNot(contains('upstreamUrl:')));
      expect(repositories, isNot(contains('status:')));
      final manifest = File(
        '${packages.path}/manifests/share_plus.yaml',
      ).readAsStringSync();
      expect(manifest, contains('  - upstreamVersion: 10.0.0'));
      expect(manifest, contains('      versionSeries: 3.35'));
      expect(manifest, contains('      versions:'));
      expect(manifest, isNot(contains('      version: 3.35.8-ohos-0.0.3')));
      expect(manifest, contains('    fluohBranch: ohos/3.35'));
      expect(manifest, contains('      path: packages/share_plus/share_plus'));
    },
  );

  test(
    'does not duplicate packages already present in repositories list',
    () async {
      final root = await Directory.systemTemp.createTemp('fluoh_pub_source_');
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      final source = Directory('${root.path}/source');
      final packages = Directory('${source.path}/packages');
      await packages.create(recursive: true);
      await File('${packages.path}/repositories.yaml').writeAsString('''
schema: 1
repositories:
  - name: camera
    url: git@github.com:FlutterOH/camera.git
''');

      await writePubSourcePackageUpdate(
        source,
        manifest: _manifest(),
        releaseTag: 'camera-v0.11.0-ohos-3.35.8-0.1.0',
      );

      final repositories = await File(
        '${packages.path}/repositories.yaml',
      ).readAsString();
      expect(
        RegExp(
          r'^\s*-\s+name:\s+camera\s*$',
          multiLine: true,
        ).allMatches(repositories),
        hasLength(1),
      );
    },
  );

  test(
    'expands an empty repositories list before appending packages',
    () async {
      final root = await Directory.systemTemp.createTemp('fluoh_pub_source_');
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      final source = Directory('${root.path}/source');
      final packages = Directory('${source.path}/packages');
      await packages.create(recursive: true);
      await File('${packages.path}/repositories.yaml').writeAsString('''
schema: 1
repositories: []
''');

      await writePubSourcePackageUpdate(
        source,
        manifest: _manifest(),
        releaseTag: 'camera-v0.11.0-ohos-3.35.8-0.1.0',
      );

      final repositories = File(
        '${packages.path}/repositories.yaml',
      ).readAsStringSync();
      expect(repositories, contains('repositories:\n  - name: camera'));
      expect(repositories, isNot(contains('repositories: []')));
    },
  );

  test('writes root package paths for repository source updates', () async {
    final root = await Directory.systemTemp.createTemp('fluoh_pub_source_');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final source = Directory('${root.path}/source');

    await writePubSourcePackageUpdate(
      source,
      manifest: _manifest(withPath: false),
      releaseTag: 'camera-v0.11.0-ohos-3.35.8-0.1.0',
    );

    final repositories = File(
      '${source.path}/packages/repositories.yaml',
    ).readAsStringSync();
    final manifest = File(
      '${source.path}/packages/manifests/camera.yaml',
    ).readAsStringSync();
    expect(repositories, contains('    packagePath: .'));
    expect(manifest, contains('  packagePath: .'));
    expect(manifest, isNot(contains('      path: .')));
  });
}

PubManifest _manifest({String packageName = 'camera', bool withPath = true}) {
  final packagePath = withPath ? 'packages/$packageName/$packageName' : null;
  return PubManifest(
    packageName: packageName,
    upstreamVersion: packageName == 'camera' ? '0.11.0' : '10.0.0',
    sdkVersion: '3.35.8-ohos-0.0.3',
    releaseVersion: '0.1.0',
    branch: 'ohos/3.35',
    releaseTag: '$packageName-release',
    upstreamUrl: 'https://github.com/flutter/packages',
    upstreamPath: packagePath,
    upstreamRef: '$packageName-upstream',
    adapterUrl: 'git@github.com:FlutterOH/$packageName.git',
    dependencyUrl: 'https://github.com/FlutterOH/$packageName.git',
    dependencyPath: packagePath,
    status: 'compatible',
  );
}
