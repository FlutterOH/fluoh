import 'dart:io';

import 'package:fluoh/src/package/manifest/package_manifest.dart';
import 'package:fluoh/src/package/manifest/pubspec_package.dart';
import 'package:fluoh/src/schema/schema.dart' as schema;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('builds release tags from the FlutterOH SDK line', () {
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

  test('builds package branches from the FlutterOH baseline version', () {
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
      branch: 'ohos/3.35/image_gallery_saver',
      repositoryUrl: 'https://github.com/FlutterOH/image_gallery_saver.git',
      upstreamCommit: '1111111111111111111111111111111111111111',
    );

    final content = File('${root.path}/fluoh.yaml').readAsStringSync();
    final yaml = loadYaml(content) as YamlMap;
    final repository = yaml['repository'] as YamlMap;
    final repositoryGit = repository['git'] as YamlMap;
    final upstream = yaml['upstream'] as YamlMap;
    final upstreamGit = upstream['git'] as YamlMap;
    final package = yaml['package'] as YamlMap;
    final release = package['release'] as YamlMap;
    final releaseUpstream = release['upstream'] as YamlMap;

    expect(yaml['schema'], 1);
    expect(yaml['kind'], 'package');
    expect(yaml.containsKey('name'), isFalse);
    expect((yaml['sdk'] as YamlMap)['version'], '3.35.8-ohos-0.0.3');
    expect(
      repositoryGit['url'],
      'https://github.com/FlutterOH/image_gallery_saver.git',
    );
    expect(repositoryGit['branch'], 'ohos/3.35/image_gallery_saver');
    expect(
      upstreamGit['url'],
      'https://github.com/fluttercandies/image_gallery_saver',
    );
    expect(upstreamGit['branch'], 'main');
    expect(package['name'], 'image_gallery_saver');
    expect(package.containsKey('path'), isFalse);
    expect(releaseUpstream['version'], '2.0.3');
    expect(
      releaseUpstream['commit'],
      '1111111111111111111111111111111111111111',
    );
    expect(release['version'], '0.1.0');
    expect(release['status'], 'experimental');
    expect(package.containsKey('upstream'), isFalse);
    expect(package.containsKey('repository'), isFalse);
    expect(repositoryGit.containsKey('ref'), isFalse);
    expect(repositoryGit.containsKey('type'), isFalse);
    expect(package.containsKey('tag'), isFalse);
    expect(yaml.containsKey('packages'), isFalse);
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
    expect(manifest.package.path, '.');
    expect(manifest.primaryPackage.path, '.');
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
        branch: 'ohos/3.35/camera',
        repositoryUrl: 'https://github.com/FlutterOH/packages.git',
        upstreamCommit: '2222222222222222222222222222222222222222',
      );

      final content = File('${root.path}/fluoh.yaml').readAsStringSync();
      final yaml = loadYaml(content) as YamlMap;
      final package = yaml['package'] as YamlMap;
      final release = package['release'] as YamlMap;
      final upstream = release['upstream'] as YamlMap;

      expect(package['name'], 'camera');
      expect(package['path'], 'packages/camera/camera');
      expect(upstream['version'], '0.12.0+1');
      expect(upstream['ref'], 'camera-v0.12.0+1');
      expect(upstream['commit'], '2222222222222222222222222222222222222222');

      final manifest = await readPackageManifest(root);
      expect(manifest.primaryPackage.upstreamVersion, '0.12.0+1');
      expect(manifest.primaryPackage.path, 'packages/camera/camera');
      expect(manifest.primaryPackage.upstreamRef, 'camera-v0.12.0+1');
    },
  );

  test('uses package.path for package directory metadata', () async {
    final root = await Directory.systemTemp.createTemp('fluoh_manifest_path_');
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
      branch: 'ohos/3.35/share_plus',
      repositoryUrl: 'https://github.com/FlutterOH/share_plus.git',
      upstreamCommit: '3333333333333333333333333333333333333333',
    );

    final manifest = await readPackageManifest(root);

    expect(manifest.primaryPackage.path, 'packages/share_plus/share_plus');
    expect(manifest.package.path, 'packages/share_plus/share_plus');
  });

  test('clears upstream refs when upstream versions are refreshed', () {
    final manifest = schema.createPackageManifest(
      package: const PubspecPackage(name: 'camera', version: '0.12.0+1'),
      upstream: 'https://github.com/flutter/packages',
      packagePath: 'packages/camera/camera',
      upstreamRef: 'camera-v0.12.0+1',
      sdkVersion: '3.35.8-ohos-0.0.3',
      branch: 'ohos/3.35/camera',
      repositoryUrl: 'https://github.com/FlutterOH/packages.git',
      upstreamCommit: '4444444444444444444444444444444444444444',
    );

    final updated = schema.updatePackageManifestUpstreamVersions(
      manifest: manifest,
      packageVersions: const {'camera': '0.12.1'},
    );

    expect(updated.primaryPackage.upstreamVersion, '0.12.1');
    expect(updated.primaryPackage.upstreamRef, isNull);
  });

  test('uses one package path for upstream and dependency metadata', () async {
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
      packagePath: 'packages/share_plus/share_plus',
      sdkVersion: '3.35.8-ohos-0.0.3',
      branch: 'ohos/3.35/share_plus',
      repositoryUrl: 'https://github.com/FlutterOH/share_plus.git',
      upstreamCommit: '5555555555555555555555555555555555555555',
    );

    final manifest = await readPackageManifest(root);
    expect(manifest.package.path, 'packages/share_plus/share_plus');
    expect(manifest.primaryPackage.path, 'packages/share_plus/share_plus');
  });
}
