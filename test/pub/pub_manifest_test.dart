import 'package:fluoh/src/pub/manifest/pub_manifest.dart';
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
}
