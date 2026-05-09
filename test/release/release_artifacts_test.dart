import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

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

  test('provides GitHub issue and pull request templates', () {
    final bugTemplate = File(
      '.github/ISSUE_TEMPLATE/bug_report.yml',
    ).readAsStringSync();
    final featureTemplate = File(
      '.github/ISSUE_TEMPLATE/feature_request.yml',
    ).readAsStringSync();
    final issueConfig = File(
      '.github/ISSUE_TEMPLATE/config.yml',
    ).readAsStringSync();
    final pullRequestTemplate = File(
      '.github/pull_request_template.md',
    ).readAsStringSync();

    final bugYaml = loadYaml(bugTemplate) as YamlMap;
    final featureYaml = loadYaml(featureTemplate) as YamlMap;
    final configYaml = loadYaml(issueConfig) as YamlMap;

    expect(bugYaml['name'], 'Bug report');
    expect(bugTemplate, contains('fluoh --version'));
    expect(bugTemplate, contains('Reproduction steps'));
    expect(bugTemplate, contains('Actual behavior'));
    expect(bugTemplate, contains('Expected behavior'));
    expect(bugTemplate, contains('Environment'));

    expect(featureYaml['name'], 'Feature request');
    expect(featureTemplate, contains('Problem'));
    expect(featureTemplate, contains('Proposed behavior'));
    expect(featureTemplate, contains('Compatibility and release impact'));
    expect(configYaml['blank_issues_enabled'], isFalse);

    expect(pullRequestTemplate, contains('## Summary'));
    expect(pullRequestTemplate, contains('## Verification'));
    expect(pullRequestTemplate, contains('`dart format .`'));
    expect(pullRequestTemplate, contains('`dart analyze`'));
    expect(pullRequestTemplate, contains('`dart test`'));
    expect(pullRequestTemplate, contains('## Release impact'));
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
    expect(readme, contains('fluoh pub upgrade'));
    expect(readme, contains('fluoh test init'));
    expect(readme, contains('fluoh test run'));
    expect(readme, contains("adapter package's own Flutter tests"));
    expect(readme, contains('fluoh_test/example'));
    expect(readme, contains('FLUOH_CHANGELOG.md'));
    expect(readme, contains('third-party FlutterOH pub repositories'));
    expect(readme, contains('packages/repositories.yaml'));
    expect(readme, contains('latest validated snapshot'));
    expect(readme, contains('https://github.com/FlutterOH/pub.git'));
    expect(readme, contains('fluoh source remove internal'));
    expect(readme, isNot(contains('fluoh source use')));
    expect(readme, contains('--repo git@github.com:FlutterOH/package.git'));
    expect(readme, contains('pull request'));
    expect(readme, contains('scheduled source ingestion process'));
    expect(readme, isNot(contains('--github')));
    expect(readme, contains('[CONTRIBUTING.md](CONTRIBUTING.md)'));
    expect(readme, isNot(contains('dart pub publish --dry-run')));
    expect(readme, isNot(contains('git tag v0.0.1')));

    expect(chineseReadme, contains('[English](README.md)'));
    expect(chineseReadme, contains('dart pub global activate fluoh'));
    expect(chineseReadme, contains('brew tap FlutterOH/tap'));
    expect(chineseReadme, contains('brew install fluoh'));
    expect(chineseReadme, contains('fluoh upgrade'));
    expect(chineseReadme, contains('fluoh pub upgrade'));
    expect(chineseReadme, contains('fluoh test init'));
    expect(chineseReadme, contains('fluoh test run'));
    expect(chineseReadme, contains('适配库自身的 Flutter 测试'));
    expect(chineseReadme, contains('fluoh_test/example'));
    expect(chineseReadme, contains('FLUOH_CHANGELOG.md'));
    expect(chineseReadme, contains('第三方库 FlutterOH pub 仓库'));
    expect(chineseReadme, contains('packages/repositories.yaml'));
    expect(chineseReadme, contains('最新校验通过的快照'));
    expect(chineseReadme, contains('https://github.com/FlutterOH/pub.git'));
    expect(chineseReadme, contains('fluoh source remove internal'));
    expect(chineseReadme, isNot(contains('fluoh source use')));
    expect(
      chineseReadme,
      contains('--repo git@github.com:FlutterOH/package.git'),
    );
    expect(chineseReadme, contains('通过 PR'));
    expect(contributing, contains('FLUOH_CHANGELOG.md'));
    expect(chineseContributing, contains('FLUOH_CHANGELOG.md'));
    expect(chineseReadme, contains('定时数据源拉取流程'));
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
    expect(
      contributing,
      contains('feat(pub): configure pub repository remotes'),
    );
    expect(contributing, isNot(contains('feat(adapter)')));
    expect(contributing, contains('dart pub global deactivate fluoh'));
    expect(
      contributing,
      contains('export PATH="\$HOME/.pub-cache/bin:\$PATH"'),
    );
    expect(contributing, contains('git@github.com:FlutterOH/<package>.git'));
    expect(contributing, contains('fluoh pub sync'));
    expect(contributing, isNot(contains('fluoh pub adapt')));
    expect(contributing, contains('fluoh test run'));
    expect(contributing, contains("adapter package's own Flutter tests"));
    expect(contributing, contains('fluoh_test/test'));
    expect(
      contributing,
      contains('--repo git@github.com:FlutterOH/package.git'),
    );
    expect(contributing, contains('FlutterOH/pub pull request'));
    expect(contributing, contains('scheduled source ingestion process'));
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
    expect(
      contributing,
      contains(
        'brew tap FlutterOH/fluoh https://github.com/FlutterOH/fluoh.git',
      ),
    );
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
    expect(
      chineseContributing,
      contains('feat(pub): configure pub repository remotes'),
    );
    expect(chineseContributing, isNot(contains('feat(adapter)')));
    expect(chineseContributing, contains('dart pub global deactivate fluoh'));
    expect(
      chineseContributing,
      contains('export PATH="\$HOME/.pub-cache/bin:\$PATH"'),
    );
    expect(
      chineseContributing,
      contains('git@github.com:FlutterOH/<package>.git'),
    );
    expect(chineseContributing, contains('fluoh pub sync'));
    expect(chineseContributing, isNot(contains('fluoh pub adapt')));
    expect(chineseContributing, contains('fluoh test run'));
    expect(chineseContributing, contains('适配库自身的 Flutter 测试'));
    expect(chineseContributing, contains('fluoh_test/test'));
    expect(
      chineseContributing,
      contains('--repo git@github.com:FlutterOH/package.git'),
    );
    expect(chineseContributing, contains('通过 FlutterOH/pub PR 注册'));
    expect(chineseContributing, contains('定时数据源拉取流程'));
    expect(chineseContributing, isNot(contains('gh auth login')));
    expect(chineseContributing, contains('提交前必须运行并通过'));
    expect(
      chineseContributing,
      contains('dart format --output=none --set-exit-if-changed .'),
    );
    expect(chineseContributing, contains('git tag v0.0.1'));
    expect(
      chineseContributing,
      contains(
        'brew tap FlutterOH/fluoh https://github.com/FlutterOH/fluoh.git',
      ),
    );
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
