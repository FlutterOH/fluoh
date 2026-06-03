import 'dart:io';

import 'package:fluoh/src/package/manifest/package_manifest.dart';
import 'package:fluoh/src/package/manifest/pubspec_package.dart';
import 'package:fluoh/src/schema/schema.dart' as schema;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('builds release tags from the Flutter OHOS SDK line', () {
    expect(
      packageReleaseTagForPackage(
        packageName: 'image_gallery_saver',
        upstreamVersion: '2.0.3',
        sdkVersion: '3.35.8-ohos-0.0.3',
        releaseVersion: '0.1.0',
      ),
      'image_gallery_saver-2.0.3-ohos-3.35-0.1.0',
    );
  });

  test('keeps FlutterOH patch releases on the same baseline tag line', () {
    final firstPatch = packageReleaseTagForPackage(
      packageName: 'image_gallery_saver',
      upstreamVersion: '2.0.3',
      sdkVersion: '3.35.8-ohos-0.0.3',
      releaseVersion: '0.1.0',
    );
    final secondPatch = packageReleaseTagForPackage(
      packageName: 'image_gallery_saver',
      upstreamVersion: '2.0.3',
      sdkVersion: '3.35.8-ohos-0.0.4',
      releaseVersion: '0.1.0',
    );

    expect(secondPatch, firstPatch);
  });

  test('builds package branches from the Flutter OHOS baseline version', () {
    expect(flutterOhosBranchForSdk('3.35.8-ohos-0.0.3'), 'ohos/3.35');
    expect(flutterOhosBranchForSdk('3.35.8-ohos-0.0.4'), 'ohos/3.35');
  });

  test('uses HTTPS dependency URLs for SSH implementation repositories', () {
    expect(
      dependencyUrlForImplementationRepository(
        'git@github.com:FlutterOH/image_gallery_saver.git',
      ),
      'https://github.com/FlutterOH/image_gallery_saver.git',
    );
    expect(
      dependencyUrlForImplementationRepository(
        'https://github.com/FlutterOH/image_gallery_saver.git',
      ),
      'https://github.com/FlutterOH/image_gallery_saver.git',
    );
  });

  test('builds FlutterOH SDK version series from SDK patch versions', () {
    expect(sdkVersionSeriesFromSdkVersion('3.35.8-ohos-0.0.3'), '3.35');
  });

  test('writes current fluoh package metadata format', () async {
    final root = await Directory.systemTemp.createTemp('fluoh_manifest_');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    await writePackageManifest(
      destination: root,
      package: const PubspecPackage(
        name: 'image_gallery_saver',
        version: '2.0.3',
      ),
      upstream: 'https://github.com/fluttercandies/image_gallery_saver',
      packagePath: '.',
      sdkVersion: '3.35.8-ohos-0.0.3',
      branch: 'ohos/3.35',
      repositoryUrl: 'https://github.com/FlutterOH/image_gallery_saver.git',
    );

    final content = File('${root.path}/fluoh.yaml').readAsStringSync();
    final yaml = loadYaml(content) as YamlMap;
    final repository = yaml['repository'] as YamlMap;
    final repositoryGit = repository['git'] as YamlMap;
    final upstream = yaml['upstream'] as YamlMap;
    final upstreamGit = upstream['git'] as YamlMap;
    final packages = yaml['packages'] as YamlMap;
    final package = packages['image_gallery_saver'] as YamlMap;

    expect(yaml['schema'], 1);
    expect(yaml['name'], 'image_gallery_saver');
    expect((yaml['sdk'] as YamlMap)['version'], '3.35.8-ohos-0.0.3');
    expect(
      repositoryGit['url'],
      'https://github.com/FlutterOH/image_gallery_saver.git',
    );
    expect(repositoryGit['branch'], 'ohos/3.35');
    expect(
      upstreamGit['url'],
      'https://github.com/fluttercandies/image_gallery_saver',
    );
    expect(package['version'], '0.1.0');
    expect(package['upstreamVersion'], '2.0.3');
    expect(package['status'], 'experimental');
    expect(package.containsKey('repository'), isFalse);
    expect(package.containsKey('upstream'), isFalse);
    expect(repositoryGit.containsKey('ref'), isFalse);
    expect(repositoryGit.containsKey('type'), isFalse);
    expect(package.containsKey('release'), isFalse);
    expect(package.containsKey('tag'), isFalse);
    expect(yaml.containsKey('implementation'), isFalse);
    expect(yaml.containsKey('dependency'), isFalse);
    expect(yaml.containsKey('fluoh'), isFalse);
    expect(yaml.containsKey('sdkVersion'), isFalse);

    final manifest = await readPackageManifest(root);
    expect(
      manifest.repositoryUrl,
      'https://github.com/FlutterOH/image_gallery_saver.git',
    );
    expect(
      manifest.dependencyUrl,
      'https://github.com/FlutterOH/image_gallery_saver.git',
    );
    expect(manifest.dependencyPath, '.');
    expect(manifest.primaryPackage.upstreamPath, '.');
    expect(manifest.primaryPackage.upstreamRef, isNull);
    expect(manifest.releaseTag, 'image_gallery_saver-2.0.3-ohos-3.35-0.1.0');
  });

  test(
    'writes package-level upstream refs without moving upstreamVersion',
    () async {
      final root = await Directory.systemTemp.createTemp('fluoh_manifest_ref_');
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });

      await writePackageManifest(
        destination: root,
        package: const PubspecPackage(name: 'camera', version: '0.12.0+1'),
        upstream: 'https://github.com/flutter/packages',
        packagePath: 'packages/camera/camera',
        upstreamRef: 'camera-v0.12.0+1',
        sdkVersion: '3.35.8-ohos-0.0.3',
        branch: 'ohos/3.35',
        repositoryUrl: 'https://github.com/FlutterOH/packages.git',
      );

      final content = File('${root.path}/fluoh.yaml').readAsStringSync();
      final yaml = loadYaml(content) as YamlMap;
      final packages = yaml['packages'] as YamlMap;
      final package = packages['camera'] as YamlMap;
      final upstream = package['upstream'] as YamlMap;

      expect(package['upstreamVersion'], '0.12.0+1');
      expect(upstream['path'], 'packages/camera/camera');
      expect(upstream['ref'], 'camera-v0.12.0+1');

      final manifest = await readPackageManifest(root);
      expect(manifest.primaryPackage.upstreamVersion, '0.12.0+1');
      expect(manifest.primaryPackage.upstreamPath, 'packages/camera/camera');
      expect(manifest.primaryPackage.upstreamRef, 'camera-v0.12.0+1');
    },
  );

  test(
    'uses the upstream package path as the downstream dependency path',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'fluoh_manifest_path_',
      );
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });

      await writePackageManifest(
        destination: root,
        package: const PubspecPackage(name: 'share_plus', version: '10.0.0'),
        upstream: 'https://github.com/fluttercommunity/plus_plugins',
        packagePath: 'packages/share_plus/share_plus',
        sdkVersion: '3.35.8-ohos-0.0.3',
        branch: 'ohos/3.35',
        repositoryUrl: 'https://github.com/FlutterOH/share_plus.git',
      );

      final manifest = await readPackageManifest(root);

      expect(
        manifest.primaryPackage.upstreamPath,
        'packages/share_plus/share_plus',
      );
      expect(manifest.dependencyPath, 'packages/share_plus/share_plus');
    },
  );

  test('clears upstream refs when upstream versions are refreshed', () {
    final manifest = schema.createPackageManifest(
      package: const PubspecPackage(name: 'camera', version: '0.12.0+1'),
      upstream: 'https://github.com/flutter/packages',
      packagePath: 'packages/camera/camera',
      upstreamRef: 'camera-v0.12.0+1',
      sdkVersion: '3.35.8-ohos-0.0.3',
      branch: 'ohos/3.35',
      repositoryUrl: 'https://github.com/FlutterOH/packages.git',
    );

    final updated = schema.updatePackageManifestUpstreamVersions(
      manifest: manifest,
      packageVersions: const {'camera': '0.12.1'},
    );

    expect(updated.primaryPackage.upstreamVersion, '0.12.1');
    expect(updated.primaryPackage.upstreamRef, isNull);
  });

  test('writes separate upstream and dependency package paths', () async {
    final root = await Directory.systemTemp.createTemp(
      'fluoh_manifest_split_path_',
    );
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    await writePackageManifest(
      destination: root,
      package: const PubspecPackage(name: 'share_plus', version: '10.0.0'),
      upstream: 'https://github.com/fluttercommunity/plus_plugins',
      packagePath: 'implementation/share_plus',
      dependencyPath: 'implementation/share_plus',
      upstreamPath: 'packages/share_plus/share_plus',
      sdkVersion: '3.35.8-ohos-0.0.3',
      branch: 'ohos/3.35',
      repositoryUrl: 'https://github.com/FlutterOH/share_plus.git',
    );

    final manifest = await readPackageManifest(root);
    expect(manifest.dependencyPath, 'implementation/share_plus');
    expect(
      manifest.primaryPackage.upstreamPath,
      'packages/share_plus/share_plus',
    );
  });
}
