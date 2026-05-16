import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  void expectContainsAll(String actual, Iterable<String> expected) {
    for (final value in expected) {
      expect(actual, contains(value), reason: 'Expected to find "$value".');
    }
  }

  void expectContainsNone(String actual, Iterable<String> unexpected) {
    for (final value in unexpected) {
      expect(
        actual,
        isNot(contains(value)),
        reason: 'Did not expect to find "$value".',
      );
    }
  }

  test('publishes to pub.dev from version tags using OIDC', () {
    final workflow = File('.github/workflows/publish.yml').readAsStringSync();

    expect(workflow, contains('name: Publish to pub.dev'));
    expect(workflow, contains('tags:'));
    expect(workflow, contains("v[0-9]+.[0-9]+.[0-9]+"));
    expect(workflow, isNot(contains('packages/fluoh_schema')));
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
    expect(workflow, isNot(contains('packages/fluoh_schema')));
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
    expect(pubspec, isNot(contains('fluoh_schema:')));
    expect(pubspec, contains('pub_semver:'));
    expect(
      pubspec,
      contains('issue_tracker: https://github.com/FlutterOH/fluoh/issues'),
    );
    expect(pubspec, contains('executables:'));
    expect(pubspec, contains('  fluoh:'));
    expect(pubspec, contains('  fluohf:'));
    expect(File('bin/fluohf.dart').existsSync(), isTrue);
    expect(Directory('packages/fluoh_schema').existsSync(), isFalse);
  });

  test('documents Dart and Homebrew installation paths in both languages', () {
    final readme = File('README.md').readAsStringSync();
    final chineseReadme = File('README.zh-CN.md').readAsStringSync();
    final contributing = File('CONTRIBUTING.md').readAsStringSync();
    final chineseContributing = File(
      'CONTRIBUTING.zh-CN.md',
    ).readAsStringSync();

    expectContainsAll(readme, [
      'href="README.zh-CN.md">简体中文',
      'dart pub global activate fluoh',
      'brew tap FlutterOH/tap',
      'brew install fluoh',
      'fluoh sdk use',
      'fluoh pub check',
      'fluoh pub fix',
      'fluohf build hap',
      'https://github.com/FlutterOH/pub.git',
      '[docs/commands.md](docs/commands.md)',
      '[docs/schema.md](docs/schema.md)',
      '[CONTRIBUTING.md](CONTRIBUTING.md)',
    ]);
    expectContainsNone(readme, [
      'fluoh source package',
      'fluoh source use',
      '--repo git@github.com:FlutterOH/package.git',
      'dart pub publish --dry-run',
      'git tag v0.1.0',
    ]);

    expectContainsAll(chineseReadme, [
      'href="README.md">English',
      'dart pub global activate fluoh',
      'brew tap FlutterOH/tap',
      'brew install fluoh',
      'fluoh sdk use',
      'fluoh pub check',
      'fluoh pub fix',
      'fluohf build hap',
      'https://github.com/FlutterOH/pub.git',
      '[docs/commands.zh-CN.md](docs/commands.zh-CN.md)',
      '[docs/schema.zh-CN.md](docs/schema.zh-CN.md)',
      '[CONTRIBUTING.zh-CN.md](CONTRIBUTING.zh-CN.md)',
    ]);
    expectContainsNone(chineseReadme, [
      'fluoh source package',
      'fluoh source use',
      '--repo git@github.com:FlutterOH/package.git',
      'dart pub publish --dry-run',
      'git tag v0.1.0',
    ]);

    expectContainsAll(contributing, [
      'dart pub publish --dry-run',
      'dart pub global activate --source path . --overwrite',
      'dart pub global activate fluoh --overwrite',
      'dart pub global deactivate fluoh',
      'export PATH="\$HOME/.pub-cache/bin:\$PATH"',
      'Conventional Commits',
      'git tag v0.1.0',
      'brew tap FlutterOH/fluoh https://github.com/FlutterOH/fluoh.git',
      'fluoh pub create',
      '--repo git@github.com:FlutterOH/package.git',
      'fluoh pub sync',
      'fluoh test run',
      'fluoh pub release',
      'fluoh source sync',
      'FLUOH_CHANGELOG.md',
    ]);
    expectContainsNone(contributing, [
      'feat(implementation)',
      'fluoh pub adapt',
      'fluoh source package',
      'gh auth login',
    ]);

    expectContainsAll(chineseContributing, [
      'dart pub publish --dry-run',
      'dart pub global activate --source path . --overwrite',
      'dart pub global activate fluoh --overwrite',
      'dart pub global deactivate fluoh',
      'export PATH="\$HOME/.pub-cache/bin:\$PATH"',
      'Conventional Commits',
      'git tag v0.1.0',
      'brew tap FlutterOH/fluoh https://github.com/FlutterOH/fluoh.git',
      'fluoh pub create',
      '--repo git@github.com:FlutterOH/package.git',
      'fluoh pub sync',
      'fluoh test run',
      'fluoh pub release',
      'fluoh source sync',
      'FLUOH_CHANGELOG.md',
    ]);
    expectContainsNone(chineseContributing, [
      'feat(implementation)',
      'fluoh pub adapt',
      'fluoh source package',
      'gh auth login',
    ]);
  });

  test('documents schema ownership and source file layout', () {
    final schema = File('docs/schema.md').readAsStringSync();
    final chineseSchema = File('docs/schema.zh-CN.md').readAsStringSync();

    expectContainsAll(schema, [
      '# Schema Design',
      '[简体中文](schema.zh-CN.md)',
      'lib/src/schema/',
      '| Project |',
      '| Package |',
      '| Source |',
      '| Manifest |',
      'manifests/<name>/fluoh.yaml',
      'kind: source',
      'kind: manifest',
      'ohos/3.35',
      'repository.git.branch',
      'upstreamVersion',
      'sdks.<sdkLine>.releases',
      '`config.json`',
      '`sources.lock.json`',
      'FlutterOH/pub',
    ]);
    expectContainsNone(schema, [
      'repository.git.ref',
      'release.version',
      'manifests[].packages',
      'repositories/<repository>/fluoh.yaml',
      'CompatibilityMatrix',
      'fluoh_schema',
    ]);

    expectContainsAll(chineseSchema, [
      '# Schema 设计',
      '[English](schema.md)',
      '| Project |',
      '| Package |',
      '| Source |',
      '| Manifest |',
      'manifests/<name>/fluoh.yaml',
      'kind: source',
      'kind: manifest',
      'ohos/3.35',
      'repository.git.branch',
      'upstreamVersion',
      'sdks.<sdkLine>.releases',
      '`config.json`',
      '`sources.lock.json`',
      'FlutterOH/pub',
    ]);
    expectContainsNone(chineseSchema, [
      'repository.git.ref',
      'release.version',
      'manifests[].packages',
      'repositories/<repository>/fluoh.yaml',
      'CompatibilityMatrix',
      'fluoh_schema',
    ]);
  });

  test('documents command design in both languages', () {
    final commands = File('docs/commands.md').readAsStringSync();
    final chineseCommands = File('docs/commands.zh-CN.md').readAsStringSync();

    expectContainsAll(commands, [
      '# Command Design',
      '[简体中文](commands.zh-CN.md)',
      'fluoh help [command]',
      'fluoh flutter <args>',
      'fluohf <args>',
      'fluoh source sync [path]',
      'fluoh sdk use <version-or-series>',
      'fluoh pub create <upstream>',
      'fluoh pub add <package-path>',
      'fluoh pub release',
      'fluoh test run',
      '\$FLUOH_HOME/sources.lock.json',
      'load-index API',
      'State Ownership',
    ]);
    expectContainsNone(commands, [
      'fluoh source package',
      'fluoh source use',
      'manifest pub branch',
      'recorded for future Git-backed',
    ]);

    expectContainsAll(chineseCommands, [
      '# 命令设计',
      '[English](commands.md)',
      'fluoh help [command]',
      'fluoh flutter <args>',
      'fluohf <args>',
      'fluoh source sync [path]',
      'fluoh sdk use <version-or-series>',
      'fluoh pub create <upstream>',
      'fluoh pub add <package-path>',
      'fluoh pub release',
      'fluoh test run',
      '\$FLUOH_HOME/sources.lock.json',
      'load-index API',
      '状态归属',
    ]);
    expectContainsNone(chineseCommands, [
      'fluoh source package',
      'fluoh source use',
      'manifest 记录的 pub 分支',
      '等待之后的 `source update`',
    ]);
  });

  test('provides a Homebrew formula backed by pub.dev activation', () {
    final formula = File('Formula/fluoh.rb').readAsStringSync();

    expect(formula, contains('class Fluoh < Formula'));
    expect(
      formula,
      contains('https://pub.dev/api/archives/fluoh-0.1.0.tar.gz'),
    );
    expect(formula, contains('sha256 :no_check'));
    expect(formula, contains('depends_on "dart-sdk"'));
    expect(formula, contains('"dart", "pub", "global", "activate"'));
    expect(formula, contains('"--source", "path", "."'));
    expect(formula, contains('pub_cache/"bin/fluoh"'));
    expect(formula, contains('pub_cache/"bin/fluohf"'));
    expect(formula, contains('fluoh --version'));
    expect(formula, contains('fluohf --help'));
  });
}
