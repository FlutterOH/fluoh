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
    final englishReadme = File('README.en.md').readAsStringSync();
    final contributing = File('CONTRIBUTING.md').readAsStringSync();
    final englishContributing = File('CONTRIBUTING.en.md').readAsStringSync();

    expect(readme, contains('[English](README.en.md)'));
    expect(readme, contains('dart pub global activate fluoh'));
    expect(readme, contains('brew tap FlutterOH/tap'));
    expect(readme, contains('brew install fluoh'));
    expect(readme, contains('fluoh upgrade'));
    expect(readme, contains('fluoh update'));
    expect(readme, contains('[CONTRIBUTING.md](CONTRIBUTING.md)'));
    expect(readme, isNot(contains('dart pub publish --dry-run')));
    expect(readme, isNot(contains('git tag v0.0.1')));

    expect(englishReadme, contains('[简体中文](README.md)'));
    expect(englishReadme, contains('dart pub global activate fluoh'));
    expect(englishReadme, contains('brew tap FlutterOH/tap'));
    expect(englishReadme, contains('brew install fluoh'));
    expect(englishReadme, contains('fluoh upgrade'));
    expect(englishReadme, contains('fluoh update'));
    expect(englishReadme, contains('[CONTRIBUTING.en.md](CONTRIBUTING.en.md)'));
    expect(englishReadme, isNot(contains('dart pub publish --dry-run')));
    expect(englishReadme, isNot(contains('git tag v0.0.1')));

    expect(contributing, contains('dart pub publish --dry-run'));
    expect(contributing, contains('提交前必须运行并通过'));
    expect(
      contributing,
      contains('dart format --output=none --set-exit-if-changed .'),
    );
    expect(contributing, contains('git tag v0.0.1'));
    expect(contributing, contains('brew tap FlutterOH/fluoh'));
    expect(contributing, contains('Conventional Commits'));

    expect(englishContributing, contains('dart pub publish --dry-run'));
    expect(
      englishContributing,
      contains('Run and pass these checks before committing'),
    );
    expect(
      englishContributing,
      contains('dart format --output=none --set-exit-if-changed .'),
    );
    expect(englishContributing, contains('git tag v0.0.1'));
    expect(englishContributing, contains('brew tap FlutterOH/fluoh'));
    expect(englishContributing, contains('Conventional Commits'));
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
