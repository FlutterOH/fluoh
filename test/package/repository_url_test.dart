import 'package:fluoh/src/package/repository_url.dart';
import 'package:test/test.dart';

void main() {
  test('builds default package repository URLs for HTTPS and SSH bases', () {
    expect(
      defaultPackageRepositoryUrl('camera'),
      'https://github.com/FlutterOH/camera.git',
    );
    expect(
      defaultPackageRepositoryUrl('camera.git'),
      'https://github.com/FlutterOH/camera.git',
    );
    expect(
      defaultPackageRepositoryUrl('camera', base: 'git@github.com:FlutterOH'),
      'git@github.com:FlutterOH/camera.git',
    );
  });

  test('rejects empty package names', () {
    expect(
      () => defaultPackageRepositoryUrl('   '),
      throwsA(isA<ArgumentError>()),
    );
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
