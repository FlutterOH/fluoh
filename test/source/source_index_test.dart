import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:fluoh/fluoh.dart';
import 'package:fluoh/src/config/fluoh_config.dart';
import 'package:fluoh/src/source/source_sync.dart';
import 'package:test/test.dart';

void main() {
  test('loads the fixture pub source indexes', () async {
    final source = SourceIndex.directory(Directory('test/fixtures/pub_source'));

    final sdkIndex = await source.loadSdkIndex();
    final packageIndex = await source.loadPackageIndex();
    final compatibilityMatrix = await source.loadCompatibilityMatrix();

    expect(sdkIndex.releases, hasLength(1));
    expect(sdkIndex.releases.single.tag, '3.35.8-ohos-0.0.3');
    expect(sdkIndex.releases.single.versionSeries, '3.35');

    expect(packageIndex.packages, contains('camera'));
    expect(
      packageIndex.packages['camera']!.implementations.single.tag,
      'camera-0.11.0-ohos-3.35-1',
    );
    expect(
      packageIndex.packages['camera']!.compatibility.single.upstreamVersion,
      '0.11.0',
    );
    expect(
      packageIndex.packages['camera']!.compatibility.single.status,
      'implemented',
    );

    expect(compatibilityMatrix.sdkVersions, contains('3.35'));
    expect(
      compatibilityMatrix.sdkVersions['3.35']!.implemented,
      contains('camera'),
    );
  });

  test('accepts multiple compatible release versions', () async {
    final root = await _createSourceRoot();
    await _writeSourceRoot(root, manifests: const ['camera']);
    await _writeManifest(
      root,
      packageName: 'camera',
      releaseVersions: const ['0.1.0', '0.2.0'],
    );
    final source = SourceIndex.directory(root);

    final packageIndex = await source.loadPackageIndex();
    final implementations = packageIndex.packages['camera']!.implementations;

    expect(implementations.map((implementation) => implementation.tag), [
      'camera-1.0.0-ohos-3.35-0.1.0',
      'camera-1.0.0-ohos-3.35-0.2.0',
    ]);
  });

  test(
    'does not expose experimental releases as compatible replacements',
    () async {
      final root = await _createSourceRoot();
      await _writeSourceRoot(root, manifests: const ['camera']);
      await _writeManifest(
        root,
        packageName: 'camera',
        releaseVersions: const ['0.1.0'],
        releaseStatus: 'experimental',
      );
      final source = SourceIndex.directory(root);

      final packageIndex = await source.loadPackageIndex();
      final compatibilityMatrix = await source.loadCompatibilityMatrix();

      expect(packageIndex.packages['camera']!.implementations, isEmpty);
      expect(compatibilityMatrix.sdkVersions, isEmpty);
    },
  );

  test('rejects release records without releases', () async {
    final root = await _createSourceRoot();
    await _writeSourceRoot(root, manifests: const ['camera']);
    await _writeManifest(root, packageName: 'camera', includeReleases: false);
    final source = SourceIndex.directory(root);

    expect(
      source.loadPackageIndex,
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('releases must not be empty'),
        ),
      ),
    );
  });

  test('rejects duplicate package names across manifests', () async {
    final root = await _createSourceRoot();
    await _writeSourceRoot(root, manifests: const ['camera', 'duplicate']);
    await _writeManifest(root, manifestName: 'camera', packageName: 'camera');
    await _writeManifest(
      root,
      manifestName: 'duplicate',
      packageName: 'camera',
    );
    final source = SourceIndex.directory(root);

    expect(
      source.loadPackageIndex,
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('appears in both'),
        ),
      ),
    );
  });

  test(
    'validates only requested packages during filtered source loads',
    () async {
      final root = await _createSourceRoot();
      await _writeSourceRoot(root, manifests: const ['camera', 'share_plus']);
      await _writeManifest(root, manifestName: 'camera', packageName: 'camera');
      await _writeManifest(
        root,
        manifestName: 'share_plus',
        packageName: 'share_plus',
      );
      final source = SourceIndex.directory(root);

      final packageIndex = await source.loadPackageIndex(
        packageNames: {'camera'},
      );

      expect(packageIndex.packages, contains('camera'));
      expect(packageIndex.packages, isNot(contains('share_plus')));
    },
  );

  test('parses relative file source URLs as relative paths', () {
    expect(localSourceDirectoryFromUrl('file:.')!.path, '.');
    expect(
      localSourceDirectoryFromUrl('file:test/fixtures/pub_source')!.path,
      'test/fixtures/pub_source',
    );
    expect(
      localSourceDirectoryFromUrl('file:///tmp/pub_source')!.path,
      '/tmp/pub_source',
    );
  });

  test(
    'rejects legacy sidecars when current root sections are missing',
    () async {
      final legacyPackages = await _createSourceRoot();
      await File('${legacyPackages.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: source
name: Legacy packages
repository:
  git:
    url: file:${legacyPackages.path}
sdk:
  git:
    url: /tmp/flutter-ohos-sdk
  versions:
    - 3.35.8-ohos-0.0.3
''');
      await File(
        '${legacyPackages.path}/packages/repositories.yaml',
      ).create(recursive: true);

      final legacySdk = await _createSourceRoot();
      await File('${legacySdk.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: source
name: Legacy SDK
repository:
  git:
    url: file:${legacySdk.path}
manifests:
  - name: camera
''');
      await File('${legacySdk.path}/sdk/releases.yaml').create(recursive: true);

      await expectLater(
        validateSource(
          'legacy_packages',
          SourceConfig(path: legacyPackages.path),
        ),
        throwsA(
          isA<UsageException>().having(
            (error) => error.message,
            'message',
            contains('legacy source layout stores SDK'),
          ),
        ),
      );
      await expectLater(
        validateSource('legacy_sdk', SourceConfig(path: legacySdk.path)),
        throwsA(
          isA<UsageException>().having(
            (error) => error.message,
            'message',
            contains('legacy source layout stores SDK'),
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
  return root;
}

Future<void> _writeSourceRoot(
  Directory root, {
  required List<String> manifests,
}) async {
  await File('${root.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: source
name: Test source
description: Test source.

repository:
  git:
    url: file:${root.path}

sdk:
  git:
    url: /tmp/flutter-ohos-sdk
  versions:
    - 3.35.8-ohos-0.0.3

manifests:
${manifests.map((entry) => '  - name: $entry').join('\n')}
''');
}

Future<void> _writeManifest(
  Directory root, {
  String manifestName = 'camera',
  required String packageName,
  List<String> releaseVersions = const ['0.1.0'],
  String releaseStatus = 'compatible',
  bool includeReleases = true,
}) async {
  final manifest = Directory('${root.path}/manifests/$manifestName');
  await manifest.create(recursive: true);
  final releases = includeReleases
      ? releaseVersions
            .map(
              (version) =>
                  '          - version: "$version"\n'
                  '            upstreamVersion: "1.0.0"'
                  '${releaseStatus == 'compatible' ? '' : '\n            status: $releaseStatus'}',
            )
            .join('\n')
      : '';
  await File('${manifest.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: manifest
name: $manifestName

repository:
  git:
    url: /tmp/$manifestName

upstream:
  git:
    url: https://github.com/example/$manifestName
    branch: main

packages:
  $packageName:
    repository:
      path: packages/$packageName
    upstream:
      path: packages/$packageName
    sdks:
      "3.35":
        releases:${includeReleases ? '\n$releases' : ' []'}
''');
}
