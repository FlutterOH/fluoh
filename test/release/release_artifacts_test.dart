import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
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

    expect(readme, contains('href="README.zh-CN.md">简体中文'));
    expect(readme, contains('dart pub global activate fluoh'));
    expect(readme, contains('brew tap FlutterOH/tap'));
    expect(readme, contains('brew install fluoh'));
    expect(readme, contains('fluoh upgrade'));
    expect(readme, contains('fluohf pub get'));
    expect(readme, contains('fluoh clean'));
    expect(readme, contains('fluoh pub get'));
    expect(readme, contains('fluoh pub upgrade'));
    expect(readme, contains('fluoh test init'));
    expect(readme, contains('fluoh test run'));
    expect(readme, contains('third-party FlutterOH pub repositories'));
    expect(readme, contains('fluoh source sync'));
    expect(readme, isNot(contains('fluoh source package')));
    expect(readme, contains('exact SDK version'));
    expect(readme, contains('latest validated snapshot'));
    expect(readme, contains('https://github.com/FlutterOH/pub.git'));
    expect(readme, isNot(contains('SDK tag')));
    expect(readme, isNot(contains('fluoh source use')));
    expect(readme, contains('[docs/commands.md](docs/commands.md)'));
    expect(readme, contains('[docs/schema.md](docs/schema.md)'));
    expect(readme, isNot(contains('repositories/camera/fluoh.yaml')));
    expect(
      readme,
      isNot(contains('--repo git@github.com:FlutterOH/package.git')),
    );
    expect(readme, isNot(contains('scheduled package ingestion workflows')));
    expect(readme, isNot(contains('--github')));
    expect(readme, contains('[CONTRIBUTING.md](CONTRIBUTING.md)'));
    expect(readme, isNot(contains('dart pub publish --dry-run')));
    expect(readme, isNot(contains('git tag v0.1.0')));

    expect(chineseReadme, contains('href="README.md">English'));
    expect(chineseReadme, contains('dart pub global activate fluoh'));
    expect(chineseReadme, contains('brew tap FlutterOH/tap'));
    expect(chineseReadme, contains('brew install fluoh'));
    expect(chineseReadme, contains('fluoh upgrade'));
    expect(chineseReadme, contains('fluohf pub get'));
    expect(chineseReadme, contains('fluoh clean'));
    expect(chineseReadme, contains('fluoh pub get'));
    expect(chineseReadme, contains('fluoh pub upgrade'));
    expect(chineseReadme, contains('fluoh test init'));
    expect(chineseReadme, contains('fluoh test run'));
    expect(chineseReadme, contains('第三方库 FlutterOH pub 仓库'));
    expect(chineseReadme, contains('fluoh source sync'));
    expect(chineseReadme, isNot(contains('fluoh source package')));
    expect(chineseReadme, contains('精确 SDK version'));
    expect(chineseReadme, contains('最新校验通过的快照'));
    expect(chineseReadme, contains('https://github.com/FlutterOH/pub.git'));
    expect(chineseReadme, isNot(contains('SDK tag')));
    expect(chineseReadme, isNot(contains('fluoh source use')));
    expect(chineseReadme, isNot(contains('repositories/camera/fluoh.yaml')));
    expect(
      chineseReadme,
      isNot(contains('--repo git@github.com:FlutterOH/package.git')),
    );
    expect(contributing, contains('FLUOH_CHANGELOG.md'));
    expect(chineseContributing, contains('FLUOH_CHANGELOG.md'));
    expect(chineseReadme, isNot(contains('--github')));
    expect(
      chineseReadme,
      contains('[docs/commands.zh-CN.md](docs/commands.zh-CN.md)'),
    );
    expect(
      chineseReadme,
      contains('[CONTRIBUTING.zh-CN.md](CONTRIBUTING.zh-CN.md)'),
    );
    expect(
      chineseReadme,
      contains('[docs/schema.zh-CN.md](docs/schema.zh-CN.md)'),
    );
    expect(chineseReadme, isNot(contains('dart pub publish --dry-run')));
    expect(chineseReadme, isNot(contains('git tag v0.1.0')));

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
      contains('dart pub global activate fluoh 0.1.0 --overwrite'),
    );
    expect(
      contributing,
      contains('feat(pub): configure pub repository remotes'),
    );
    expect(contributing, isNot(contains('feat(implementation)')));
    expect(contributing, contains('dart pub global deactivate fluoh'));
    expect(
      contributing,
      contains('export PATH="\$HOME/.pub-cache/bin:\$PATH"'),
    );
    expect(contributing, contains('git@github.com:FlutterOH/<package>.git'));
    expect(contributing, contains('fluoh pub sync'));
    expect(contributing, isNot(contains('fluoh pub adapt')));
    expect(contributing, contains('fluoh test run'));
    expect(contributing, contains("package's own Flutter tests"));
    expect(contributing, contains('fluoh_test/test'));
    expect(
      contributing,
      contains('--repo git@github.com:FlutterOH/package.git'),
    );
    expect(contributing, contains('FlutterOH/pub pull request'));
    expect(
      contributing,
      contains('The SDK version comes from configured sources'),
    );
    expect(
      contributing,
      isNot(contains('The SDK tag comes from configured sources')),
    );
    expect(contributing, contains('fluoh source sync'));
    expect(contributing, isNot(contains('fluoh source package')));
    expect(contributing, contains('scheduled package ingestion workflow'));
    expect(contributing, isNot(contains('gh auth login')));
    expect(
      contributing,
      contains('Run and pass these checks before committing'),
    );
    expect(
      contributing,
      contains('dart format --output=none --set-exit-if-changed .'),
    );
    expect(contributing, contains('git tag v0.1.0'));
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
      contains('dart pub global activate fluoh 0.1.0 --overwrite'),
    );
    expect(
      chineseContributing,
      contains('feat(pub): configure pub repository remotes'),
    );
    expect(chineseContributing, isNot(contains('feat(implementation)')));
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
    expect(chineseContributing, contains('package 自身的 Flutter 测试'));
    expect(chineseContributing, contains('fluoh_test/test'));
    expect(
      chineseContributing,
      contains('--repo git@github.com:FlutterOH/package.git'),
    );
    expect(chineseContributing, contains('通过 FlutterOH/pub PR 注册'));
    expect(chineseContributing, contains('SDK version 来自已配置的数据源'));
    expect(chineseContributing, isNot(contains('SDK tag 来自已配置的数据源')));
    expect(chineseContributing, contains('fluoh source sync'));
    expect(chineseContributing, isNot(contains('fluoh source package')));
    expect(chineseContributing, contains('定时 package 拉取流程'));
    expect(chineseContributing, isNot(contains('gh auth login')));
    expect(chineseContributing, contains('提交前必须运行并通过'));
    expect(
      chineseContributing,
      contains('dart format --output=none --set-exit-if-changed .'),
    );
    expect(chineseContributing, contains('git tag v0.1.0'));
    expect(
      chineseContributing,
      contains(
        'brew tap FlutterOH/fluoh https://github.com/FlutterOH/fluoh.git',
      ),
    );
    expect(chineseContributing, contains('Conventional Commits'));
  });

  test('documents schema ownership and source file layout', () {
    final schema = File('docs/schema.md').readAsStringSync();
    final chineseSchema = File('docs/schema.zh-CN.md').readAsStringSync();

    expect(schema, contains('# Schema Design'));
    expect(schema, contains('[简体中文](schema.zh-CN.md)'));
    expect(schema, contains('lib/src/schema/'));
    expect(schema, contains('| Project |'));
    expect(schema, contains('| Package |'));
    expect(schema, contains('| Source |'));
    expect(schema, contains('| Manifest |'));
    expect(schema, contains('manifests/<name>/fluoh.yaml'));
    expect(schema, contains('valid but contributes no'));
    expect(
      schema,
      contains('Package names are derived from the `packages` keys'),
    );
    expect(schema, contains('kind: manifest'));
    expect(schema, contains('ohos/3.35'));
    expect(schema, contains('Adaptation Rules And Workflow'));
    expect(schema, contains('stable SDK versions'));
    expect(
      schema,
      contains(
        'Complete SDK versions that do not match this shape fail validation',
      ),
    );
    expect(schema, contains('repository.git.branch'));
    expect(schema, contains('upstreamVersion'));
    expect(schema, contains('sdks.<sdkLine>.releases'));
    expect(schema, contains('`config.json`'));
    expect(schema, contains('`sources.lock.json`'));
    expect(schema, contains('does not contain a `schema` field'));
    expect(schema, contains('regenerated from scratch'));
    expect(schema, contains('configured-snapshot `fluoh source sync`'));
    expect(schema, contains('first default'));
    expect(schema, contains('selected-SDK installation needs'));
    expect(schema, contains('SDK metadata'));
    expect(schema, contains('Dependency Report And Plan'));
    expect(schema, contains('FlutterOH/pub'));
    expect(schema, isNot(contains('repository.git.ref')));
    expect(schema, isNot(contains('release.version')));
    expect(schema, isNot(contains('manifests[].packages')));
    expect(schema, isNot(contains('repositories/<repository>/fluoh.yaml')));
    expect(schema, isNot(contains('CompatibilityMatrix')));
    expect(schema, isNot(contains('fluoh_schema')));

    expect(chineseSchema, contains('# Schema 设计'));
    expect(chineseSchema, contains('[English](schema.md)'));
    expect(chineseSchema, contains('| Project |'));
    expect(chineseSchema, contains('| Package |'));
    expect(chineseSchema, contains('| Source |'));
    expect(chineseSchema, contains('| Manifest |'));
    expect(chineseSchema, contains('manifests/<name>/fluoh.yaml'));
    expect(chineseSchema, contains('空脚手架'));
    expect(chineseSchema, contains('从 Manifest 文件的 `packages` keys 派生'));
    expect(chineseSchema, contains('kind: manifest'));
    expect(chineseSchema, contains('ohos/3.35'));
    expect(chineseSchema, contains('适配规则和流程'));
    expect(chineseSchema, contains('完整稳定 SDK 版本'));
    expect(chineseSchema, contains('不符合该格式的完整 SDK 版本校验失败'));
    expect(chineseSchema, contains('repository.git.branch'));
    expect(chineseSchema, contains('upstreamVersion'));
    expect(chineseSchema, contains('sdks.<sdkLine>.releases'));
    expect(chineseSchema, contains('`sources.lock.json`'));
    expect(chineseSchema, contains('不包含 `schema` 字段'));
    expect(chineseSchema, contains('整体重新生成'));
    expect(chineseSchema, contains('目标是已配置快照的 `fluoh source sync`'));
    expect(chineseSchema, contains('首次默认 Source bootstrap'));
    expect(chineseSchema, contains('需要 SDK 元数据来安装'));
    expect(chineseSchema, contains('Dependency Report 和 Plan'));
    expect(chineseSchema, contains('FlutterOH/pub'));
    expect(chineseSchema, isNot(contains('repository.git.ref')));
    expect(chineseSchema, isNot(contains('release.version')));
    expect(chineseSchema, isNot(contains('manifests[].packages')));
    expect(
      chineseSchema,
      isNot(contains('repositories/<repository>/fluoh.yaml')),
    );
    expect(chineseSchema, isNot(contains('CompatibilityMatrix')));
    expect(chineseSchema, isNot(contains('fluoh_schema')));
  });

  test('documents command design in both languages', () {
    final commands = File('docs/commands.md').readAsStringSync();
    final chineseCommands = File('docs/commands.zh-CN.md').readAsStringSync();

    expect(commands, contains('# Command Design'));
    expect(commands, contains('[简体中文](commands.zh-CN.md)'));
    expect(commands, contains('fluoh help [command]'));
    expect(commands, contains('fluoh source`'));
    expect(commands, contains('fluohf <args>'));
    expect(commands, contains('fluoh source sync [path]'));
    expect(commands, isNot(contains('fluoh source package')));
    expect(commands, contains('\$FLUOH_HOME/sources.lock.json'));
    expect(commands, contains('Dart global installs'));
    expect(commands, contains('validated local copy of a Source'));
    expect(commands, contains('HTTPS/SSH URLs are cloned immediately'));
    expect(commands, contains('every configured source snapshot'));
    expect(commands, contains('Source lock maintenance has one owner'));
    expect(commands, contains('Command classes must not read or write'));
    expect(commands, contains('load-index API'));
    expect(commands, contains('Source mutation commands pass the candidate'));
    expect(commands, contains('selected SDK is missing'));
    expect(commands, contains('first default Source'));
    expect(commands, contains('configured source snapshots'));
    expect(commands, contains('source snapshots under'));
    expect(commands, contains('package Source data'));
    expect(commands, contains('selected-SDK installation needs SDK metadata'));
    expect(commands, isNot(contains('or invalidates')));
    expect(commands, isNot(contains('recorded for future Git-backed')));
    expect(commands, isNot(contains('every selected source is validated')));
    expect(commands, contains('fluoh sdk use <version-or-series>'));
    expect(commands, contains('current project SDK version'));
    expect(commands, contains('fluoh pub create <upstream>'));
    expect(commands, contains('maintenance branch recorded by Package'));
    expect(commands, contains('fluoh pub release'));
    expect(commands, contains('fluoh test run'));
    expect(commands, contains('State Ownership'));
    expect(commands, isNot(contains('fluoh source use')));
    expect(commands, isNot(contains('manifest pub branch')));

    expect(chineseCommands, contains('# Command 设计'));
    expect(chineseCommands, contains('[English](commands.md)'));
    expect(chineseCommands, contains('fluoh help [command]'));
    expect(chineseCommands, contains('fluoh source`'));
    expect(chineseCommands, contains('fluohf <args>'));
    expect(chineseCommands, contains('fluoh source sync [path]'));
    expect(chineseCommands, isNot(contains('fluoh source package')));
    expect(chineseCommands, contains('\$FLUOH_HOME/sources.lock.json'));
    expect(chineseCommands, contains('Dart global 安装执行'));
    expect(chineseCommands, contains('source 快照是保存在'));
    expect(chineseCommands, contains('HTTPS/SSH URL 会立即 clone'));
    expect(chineseCommands, contains('所有已配置 source'));
    expect(chineseCommands, contains('Source lock 维护只有一个 owner'));
    expect(chineseCommands, contains('不应该直接读写'));
    expect(chineseCommands, contains('load-index API'));
    expect(chineseCommands, contains('把候选 config 或快照状态交给'));
    expect(chineseCommands, contains('已选择 SDK'));
    expect(chineseCommands, contains('首次默认 Source bootstrap'));
    expect(chineseCommands, contains('已配置 source 快照'));
    expect(chineseCommands, contains('package Source 数据'));
    expect(chineseCommands, contains('需要 SDK 元数据来安装'));
    expect(chineseCommands, isNot(contains('把它标记为')));
    expect(chineseCommands, isNot(contains('等待之后的 `source update`')));
    expect(chineseCommands, isNot(contains('所有选中的 source')));
    expect(chineseCommands, contains('fluoh sdk use <version-or-series>'));
    expect(chineseCommands, contains('当前项目 SDK version'));
    expect(chineseCommands, contains('fluoh pub create <upstream>'));
    expect(
      chineseCommands,
      contains('Package `repository.git.branch` 记录的维护分支'),
    );
    expect(chineseCommands, contains('fluoh pub release'));
    expect(chineseCommands, contains('fluoh test run'));
    expect(chineseCommands, contains('状态归属'));
    expect(chineseCommands, isNot(contains('fluoh source use')));
    expect(chineseCommands, isNot(contains('manifest 记录的 pub 分支')));
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
