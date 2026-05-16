import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:fluoh/src/pub/manifest/pub_manifest.dart';
import 'package:fluoh/src/pub/manifest/pubspec_package.dart';
import 'package:test/test.dart';

void main() {
  test('builds release tags from the Flutter OHOS SDK line', () {
    expect(
      pubReleaseTagForPackage(
        packageName: 'image_gallery_saver',
        upstreamVersion: '2.0.3',
        sdkVersion: '3.35.8-ohos-0.0.3',
        releaseVersion: '0.1.0',
      ),
      'image_gallery_saver-2.0.3-ohos-3.35-0.1.0',
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

  test('builds pub branches from the Flutter OHOS baseline version', () {
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

    await writePubManifest(
      destination: root,
      package: const PubspecPackage(
        name: 'image_gallery_saver',
        version: '2.0.3',
      ),
      upstream: 'https://github.com/fluttercandies/image_gallery_saver',
      packagePath: '.',
      sdkVersion: '3.35.8-ohos-0.0.3',
      branch: 'ohos/3.35',
      repositoryUrl: 'git@github.com:FlutterOH/image_gallery_saver.git',
    );

    final content = File('${root.path}/fluoh.yaml').readAsStringSync();
    expect(content, contains('schema: 1'));
    expect(content, contains('name: image_gallery_saver'));
    expect(
      content,
      contains(
        '# Complete Flutter OHOS SDK tag used by this adaptation branch.',
      ),
    );
    expect(
      content,
      contains(
        '# FlutterOH adaptation repository. Branches normally follow ohos/<sdkLine>.',
      ),
    );
    expect(
      content,
      contains(
        '# Package release metadata. Update version/status before fluoh pub release.',
      ),
    );
    expect(content, contains('sdk:\n  version: 3.35.8-ohos-0.0.3'));
    expect(content, contains('repository:'));
    expect(content, contains('  git:'));
    expect(content, contains('packages:'));
    expect(content, contains('  image_gallery_saver:'));
    expect(content, contains('    version: 0.1.0'));
    expect(content, contains('    status: experimental'));
    expect(content, contains('upstream:'));
    expect(content, contains('    upstreamVersion: 2.0.3'));
    expect(content, isNot(contains('type: git')));
    expect(content, contains('branch: ohos/3.35'));
    expect(content, isNot(contains('ref:')));
    expect(content, isNot(contains('release:')));
    expect(content, isNot(contains('implementation:')));
    expect(content, isNot(contains('dependency:')));
    expect(content, isNot(contains('fluoh:')));
    expect(content, isNot(contains('sdkVersion:')));
    expect(content, isNot(contains('    path:')));
    expect(
      content,
      contains('url: "git@github.com:FlutterOH/image_gallery_saver.git"'),
    );
    expect(content, isNot(contains('tag: 0.1.0')));
    expect(content, isNot(contains('tag: 2.0.3')));
    expect(content, isNot(contains('tag: image_gallery_saver')));

    final manifest = await readPubManifest(root);
    expect(
      manifest.repositoryUrl,
      'git@github.com:FlutterOH/image_gallery_saver.git',
    );
    expect(
      manifest.dependencyUrl,
      'https://github.com/FlutterOH/image_gallery_saver.git',
    );
    expect(manifest.dependencyPath, '.');
    expect(manifest.primaryPackage.upstreamPath, '.');
    expect(manifest.releaseTag, 'image_gallery_saver-2.0.3-ohos-3.35-0.1.0');
  });

  test('rejects legacy pub manifest layout', () async {
    final root = await Directory.systemTemp.createTemp('fluoh_manifest_');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    await File('${root.path}/fluoh.yaml').writeAsString('''
schema: 1
sdk:
  version: 3.35.8-ohos-0.0.3
package:
  name: image_gallery_saver
  version: 0.1.0
  status: experimental
  git:
    url: git@github.com:FlutterOH/image_gallery_saver.git
    ref: ohos/3.35
upstream:
  version: 2.0.3
  git:
    url: https://github.com/fluttercandies/image_gallery_saver
    ref: image_gallery_saver-v2.0.3
''');

    expect(
      () => readPubManifest(root),
      throwsA(
        isA<UsageException>().having(
          (error) => error.message,
          'message',
          contains('fluoh.yaml must not contain "package"'),
        ),
      ),
    );
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
        packagePath: 'packages/share_plus/share_plus',
        sdkVersion: '3.35.8-ohos-0.0.3',
        branch: 'ohos/3.35',
        repositoryUrl: 'git@github.com:FlutterOH/share_plus.git',
      );

      final content = File('${root.path}/fluoh.yaml').readAsStringSync();
      expect(content, contains('      path: packages/share_plus/share_plus'));

      final manifest = await readPubManifest(root);

      expect(
        manifest.primaryPackage.upstreamPath,
        'packages/share_plus/share_plus',
      );
      expect(manifest.dependencyPath, 'packages/share_plus/share_plus');
    },
  );

  test('writes separate upstream and dependency package paths', () async {
    final root = await Directory.systemTemp.createTemp(
      'fluoh_manifest_split_path_',
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
      packagePath: 'implementation/share_plus',
      dependencyPath: 'implementation/share_plus',
      upstreamPath: 'packages/share_plus/share_plus',
      sdkVersion: '3.35.8-ohos-0.0.3',
      branch: 'ohos/3.35',
      repositoryUrl: 'https://github.com/FlutterOH/share_plus.git',
    );

    final content = File('${root.path}/fluoh.yaml').readAsStringSync();
    expect(content, contains('    path: implementation/share_plus'));
    expect(content, contains('    path: packages/share_plus/share_plus'));

    final manifest = await readPubManifest(root);
    expect(manifest.dependencyPath, 'implementation/share_plus');
    expect(
      manifest.primaryPackage.upstreamPath,
      'packages/share_plus/share_plus',
    );
  });
}
