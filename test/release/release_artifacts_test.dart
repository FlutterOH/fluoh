import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('publishes to pub.dev from version tags using OIDC', () {
    final workflow = File('.github/workflows/publish.yml').readAsStringSync();

    expect(workflow, contains('name: Publish to pub.dev'));
    expect(workflow, contains('tags:'));
    expect(workflow, contains("v[0-9]+.[0-9]+.[0-9]+"));
    expect(
      workflow,
      contains('dart format --output=none --set-exit-if-changed .'),
    );
    expect(workflow, contains('dart analyze'));
    expect(workflow, contains('dart test'));
    expect(workflow, contains('needs: test'));
    expect(workflow, contains('id-token: write'));
    expect(
      workflow,
      contains('dart-lang/setup-dart/.github/workflows/publish.yml@v1'),
    );
    expect(workflow, contains('environment: pub.dev'));
  });

  test('enforces format, analysis, and tests in CI', () {
    final workflow = File('.github/workflows/ci.yml').readAsStringSync();

    expect(workflow, contains('name: CI'));
    expect(workflow, contains('pull_request:'));
    expect(workflow, contains('branches:'));
    expect(workflow, contains('main'));
    expect(workflow, contains('tags:'));
    expect(workflow, contains("v[0-9]+.[0-9]+.[0-9]+"));
    expect(workflow, contains('dart pub get'));
    expect(
      workflow,
      contains('dart format --output=none --set-exit-if-changed .'),
    );
    expect(workflow, contains('dart analyze'));
    expect(workflow, contains('dart test'));
  });

  test('declares pub metadata and an executable for global activation', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(pubspec, contains('name: fluoh'));
    expect(pubspec, contains('repository: https://github.com/FlutterOH/fluoh'));
    expect(
      pubspec,
      contains('issue_tracker: https://github.com/FlutterOH/fluoh/issues'),
    );
    expect(pubspec, contains('executables:'));
    expect(pubspec, contains('  fluoh:'));
  });

  test('documents Dart and Homebrew installation paths in both languages', () {
    final readme = File('README.md').readAsStringSync();
    final chineseReadme = File('README.zh-CN.md').readAsStringSync();
    final contributing = File('CONTRIBUTING.md').readAsStringSync();
    final chineseContributing = File(
      'CONTRIBUTING.zh-CN.md',
    ).readAsStringSync();

    expect(readme, contains('[简体中文](README.zh-CN.md)'));
    expect(readme, contains('dart pub global activate fluoh'));
    expect(readme, contains('brew tap FlutterOH/tap'));
    expect(readme, contains('brew install fluoh'));
    expect(readme, contains('fluoh upgrade'));
    expect(readme, contains('fluoh update'));
    expect(readme, contains('packages/registry.yaml'));
    expect(readme, contains('fluoh source remove internal'));
    expect(readme, isNot(contains('fluoh source use')));
    expect(
      readme,
      contains('--repository git@github.com:FlutterOH/package.git'),
    );
    expect(readme, isNot(contains('--github')));
    expect(readme, contains('[CONTRIBUTING.md](CONTRIBUTING.md)'));
    expect(readme, isNot(contains('dart pub publish --dry-run')));
    expect(readme, isNot(contains('git tag v0.0.1')));

    expect(chineseReadme, contains('[English](README.md)'));
    expect(chineseReadme, contains('dart pub global activate fluoh'));
    expect(chineseReadme, contains('brew tap FlutterOH/tap'));
    expect(chineseReadme, contains('brew install fluoh'));
    expect(chineseReadme, contains('fluoh upgrade'));
    expect(chineseReadme, contains('fluoh update'));
    expect(chineseReadme, contains('packages/registry.yaml'));
    expect(chineseReadme, contains('fluoh source remove internal'));
    expect(chineseReadme, isNot(contains('fluoh source use')));
    expect(
      chineseReadme,
      contains('--repository git@github.com:FlutterOH/package.git'),
    );
    expect(chineseReadme, isNot(contains('--github')));
    expect(
      chineseReadme,
      contains('[CONTRIBUTING.zh-CN.md](CONTRIBUTING.zh-CN.md)'),
    );
    expect(chineseReadme, isNot(contains('dart pub publish --dry-run')));
    expect(chineseReadme, isNot(contains('git tag v0.0.1')));

    expect(contributing, contains('dart pub publish --dry-run'));
    expect(
      contributing,
      contains('dart pub global activate --source path . --overwrite'),
    );
    expect(
      contributing,
      contains('dart pub global activate fluoh --overwrite'),
    );
    expect(
      contributing,
      contains('dart pub global activate fluoh 0.0.1 --overwrite'),
    );
    expect(contributing, contains('dart pub global deactivate fluoh'));
    expect(
      contributing,
      contains('export PATH="\$HOME/.pub-cache/bin:\$PATH"'),
    );
    expect(contributing, contains('git@github.com:FlutterOH/fluoh.git'));
    expect(
      contributing,
      contains('--repository git@github.com:FlutterOH/package.git'),
    );
    expect(contributing, isNot(contains('gh auth login')));
    expect(
      contributing,
      contains('Run and pass these checks before committing'),
    );
    expect(
      contributing,
      contains('dart format --output=none --set-exit-if-changed .'),
    );
    expect(contributing, contains('git tag v0.0.1'));
    expect(contributing, contains('brew tap FlutterOH/fluoh'));
    expect(contributing, contains('Conventional Commits'));

    expect(chineseContributing, contains('dart pub publish --dry-run'));
    expect(
      chineseContributing,
      contains('dart pub global activate --source path . --overwrite'),
    );
    expect(
      chineseContributing,
      contains('dart pub global activate fluoh --overwrite'),
    );
    expect(
      chineseContributing,
      contains('dart pub global activate fluoh 0.0.1 --overwrite'),
    );
    expect(chineseContributing, contains('dart pub global deactivate fluoh'));
    expect(
      chineseContributing,
      contains('export PATH="\$HOME/.pub-cache/bin:\$PATH"'),
    );
    expect(chineseContributing, contains('git@github.com:FlutterOH/fluoh.git'));
    expect(
      chineseContributing,
      contains('--repository git@github.com:FlutterOH/package.git'),
    );
    expect(chineseContributing, isNot(contains('gh auth login')));
    expect(chineseContributing, contains('提交前必须运行并通过'));
    expect(
      chineseContributing,
      contains('dart format --output=none --set-exit-if-changed .'),
    );
    expect(chineseContributing, contains('git tag v0.0.1'));
    expect(chineseContributing, contains('brew tap FlutterOH/fluoh'));
    expect(chineseContributing, contains('Conventional Commits'));
  });

  test('provides a Homebrew formula backed by pub.dev activation', () {
    final formula = File('Formula/fluoh.rb').readAsStringSync();

    expect(formula, contains('class Fluoh < Formula'));
    expect(
      formula,
      contains('https://pub.dev/api/archives/fluoh-0.0.1.tar.gz'),
    );
    expect(formula, contains('sha256 :no_check'));
    expect(formula, contains('depends_on "dart-sdk"'));
    expect(formula, contains('"dart", "pub", "global", "activate"'));
    expect(formula, contains('"--source", "path", "."'));
    expect(formula, contains('fluoh --version'));
  });
}
