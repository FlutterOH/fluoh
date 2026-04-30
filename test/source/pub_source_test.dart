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
}
