import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:fluoh/src/pub/manifest/pub_manifest.dart';
import 'package:fluoh/src/pub/manifest/pubspec_package.dart';
import 'package:test/test.dart';

void main() {
  test('builds release tags from the Flutter baseline version', () {
    expect(
      pubReleaseTagForPackage(
        packageName: 'image_gallery_saver',
        upstreamVersion: '2.0.3',
        sdkVersion: '3.35.8-ohos-0.0.3',
        releaseVersion: '0.1.0',
      ),
      'image_gallery_saver-v2.0.3-ohos-3.35.8-0.1.0',
    );
  });

  test('keeps FlutterOH patch releases on the same baseline tag line', () {
    final firstPatch = pubReleaseTagForPackage(
      packageName: 'image_gallery_saver',
      upstreamVersion: '2.0.3',
      sdkVersion: '3.35.8-ohos-0.0.3',
      releaseVersion: '0.1.0',
    );
    final secondPatch = pubReleaseTagForPackage(
      packageName: 'image_gallery_saver',
      upstreamVersion: '2.0.3',
      sdkVersion: '3.35.8-ohos-0.0.4',
      releaseVersion: '0.1.0',
    );

    expect(secondPatch, firstPatch);
  });

  test('uses HTTPS dependency URLs for SSH adapter repositories', () {
    expect(
      dependencyUrlForAdapterRepository(
        'git@github.com:FlutterOH/image_gallery_saver.git',
      ),
      'https://github.com/FlutterOH/image_gallery_saver.git',
    );
    expect(
      dependencyUrlForAdapterRepository(
        'https://github.com/FlutterOH/image_gallery_saver.git',
      ),
      'https://github.com/FlutterOH/image_gallery_saver.git',
    );
  });

  test('builds FlutterOH SDK version series from SDK patch tags', () {
    expect(sdkVersionSeriesFromSdkVersion('3.35.8-ohos-0.0.3'), '3.35.8-ohos');
  });

  test('writes fluoh metadata without a separate dependency block', () async {
    final root = await Directory.systemTemp.createTemp('fluoh_manifest_');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    await writePubManifest(
      destination: root,
      package: const PubspecPackage(
        name: 'image_gallery_saver',
        version: '2.0.3',
      ),
      upstream: 'https://github.com/fluttercandies/image_gallery_saver',
      upstreamRef: 'image_gallery_saver-v2.0.3',
      packagePath: '.',
      sdkVersion: '3.35.8-ohos-0.0.3',
      branch: 'ohos/3.35.8-ohos',
      adapterUrl: 'git@github.com:FlutterOH/image_gallery_saver.git',
    );

    final content = File('${root.path}/fluoh.yaml').readAsStringSync();
    expect(content, contains('fluoh:'));
    expect(content, isNot(contains('adapter:')));
    expect(content, isNot(contains('dependency:')));
    expect(
      content,
      contains('url: git@github.com:FlutterOH/image_gallery_saver.git'),
    );
    expect(
      content,
      contains('tag: image_gallery_saver-v2.0.3-ohos-3.35.8-0.1.0'),
    );

    final manifest = await readPubManifest(root);
    expect(
      manifest.adapterUrl,
      'git@github.com:FlutterOH/image_gallery_saver.git',
    );
    expect(
      manifest.dependencyUrl,
      'https://github.com/FlutterOH/image_gallery_saver.git',
    );
    expect(manifest.releaseTag, 'image_gallery_saver-v2.0.3-ohos-3.35.8-0.1.0');
  });

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

      await writePubManifest(
        destination: root,
        package: const PubspecPackage(name: 'share_plus', version: '10.0.0'),
        upstream: 'https://github.com/fluttercommunity/plus_plugins',
        upstreamRef: 'share_plus-v10.0.0',
        packagePath: 'packages/share_plus/share_plus',
        sdkVersion: '3.35.8-ohos-0.0.3',
        branch: 'ohos/3.35.8-ohos',
        adapterUrl: 'git@github.com:FlutterOH/share_plus.git',
      );

      final manifest = await readPubManifest(root);

      expect(manifest.upstreamPath, 'packages/share_plus/share_plus');
      expect(manifest.dependencyPath, 'packages/share_plus/share_plus');
    },
  );

  test('rejects legacy adapter and dependency metadata', () async {
    final root = await Directory.systemTemp.createTemp(
      'fluoh_manifest_legacy_',
    );
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    await File('${root.path}/fluoh.yaml').writeAsString('''
schema: 1
name: camera

upstream:
  type: git
  url: https://github.com/flutter/packages
  path: packages/camera/camera
  ref: camera-v0.11.0
  version: 0.11.0

adapter:
  type: git
  url: git@github.com:FlutterOH/camera.git
  branch: ohos/3.35.8-ohos
  sdkVersion: 3.35.8-ohos-0.0.3
  status: compatible
  release:
    version: "1"
    tag: camera-v0.11.0-ohos-3.35.8-1

dependency:
  type: git
  url: https://github.com/FlutterOH/camera.git
  ref: camera-v0.11.0-ohos-3.35.8-1
  path: packages/camera/camera
''');

    expect(
      () => readPubManifest(root),
      throwsA(
        isA<UsageException>().having(
          (error) => error.message,
          'message',
          'fluoh.yaml missing "fluoh".',
        ),
      ),
    );
  });

  test('rejects dependency metadata in fluoh manifests', () async {
    final root = await Directory.systemTemp.createTemp(
      'fluoh_manifest_dependency_',
    );
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    await File('${root.path}/fluoh.yaml').writeAsString('''
schema: 1
name: camera

upstream:
  type: git
  url: https://github.com/flutter/packages
  path: packages/camera/camera
  ref: camera-v0.11.0
  version: 0.11.0

fluoh:
  type: git
  url: git@github.com:FlutterOH/camera.git
  branch: ohos/3.35.8-ohos
  sdkVersion: 3.35.8-ohos-0.0.3
  status: compatible
  release:
    version: "1"
    tag: camera-v0.11.0-ohos-3.35.8-1

dependency:
  type: git
  url: https://github.com/FlutterOH/camera.git
  ref: camera-v0.11.0-ohos-3.35.8-1
  path: packages/camera/camera
''');

    expect(
      () => readPubManifest(root),
      throwsA(
        isA<UsageException>().having(
          (error) => error.message,
          'message',
          'fluoh.yaml must not contain "dependency".',
        ),
      ),
    );
  });
}
