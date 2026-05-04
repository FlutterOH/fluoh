import 'package:fluoh/src/pub/repository_url.dart';
import 'package:test/test.dart';

void main() {
  test('builds default pub repository URLs for SSH and HTTPS bases', () {
    expect(
      defaultPubRepositoryUrl('camera'),
      'git@github.com:FlutterOH/camera.git',
    );
    expect(
      defaultPubRepositoryUrl('camera.git'),
      'git@github.com:FlutterOH/camera.git',
    );
    expect(
      defaultPubRepositoryUrl('camera', base: 'https://github.com/FlutterOH/'),
      'https://github.com/FlutterOH/camera.git',
    );
  });

  test('rejects empty package names', () {
    expect(() => defaultPubRepositoryUrl('   '), throwsA(isA<ArgumentError>()));
  });

  test('extracts repository names from upstream URLs and paths', () {
    expect(
      repositoryNameFromUpstream('https://github.com/flutter/packages.git'),
      'packages',
    );
    expect(
      repositoryNameFromUpstream('git@github.com:flutter/packages.git/'),
      'packages',
    );
    expect(repositoryNameFromUpstream('/tmp/camera'), 'camera');
  });
}
