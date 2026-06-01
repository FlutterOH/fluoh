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
    expect(bugTemplate, contains('fluoh doctor -p'));
    expect(bugTemplate, contains('Doctor output'));
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

  test('ships the fluoh AI agent skill', () {
    final skill = File('skills/fluoh/SKILL.md').readAsStringSync();
    final openai = File('skills/fluoh/agents/openai.yaml').readAsStringSync();
    final reportTemplate = File(
      'skills/fluoh/references/report-template.md',
    ).readAsStringSync();
    final preflight = File(
      'skills/fluoh/scripts/preflight.py',
    ).readAsStringSync();
    final newReport = File(
      'skills/fluoh/scripts/new_report.py',
    ).readAsStringSync();
    final checkReport = File(
      'skills/fluoh/scripts/check_report.py',
    ).readAsStringSync();

    expect(skill, contains('name: fluoh'));
    expect(skill, contains('adapting Flutter apps'));
    expect(skill, contains('## AI-Driven Default Flow'));
    expect(skill, contains('## App Project Flow'));
    expect(skill, contains('## Preflight Routing'));
    expect(skill, contains('## Package Adaptation Flow'));
    expect(skill, contains('## Automatic Adaptation Command Flow'));
    expect(skill, contains('## User Request Routing'));
    expect(skill, contains('## CLI Setup'));
    expect(skill, contains('finalCheckCommands'));
    expect(skill, contains('deliveryChecks'));
    expect(skill, contains('final acceptance gate'));
    expect(skill, contains('dart pub global activate fluoh'));
    expect(skill, contains('brew install fluoh'));
    expect(skill, contains('fluoh --version'));
    expect(skill, contains('fluoh skill --json'));
    expect(skill, contains('--package <package-name>'));
    expect(skill, contains('skillVersion'));
    expect(skill, contains('upgradePrompt'));
    expect(skill, contains('fluoh deps check --json'));
    expect(skill, contains('fluoh build --platform ohos --auto-sign --json'));
    expect(
      skill,
      contains('fluoh run --platform ohos --package <name> --json'),
    );
    expect(
      skill,
      contains('fluoh run --platform android --package <name> --json'),
    );
    expect(skill, contains('JSON Diagnostics'));
    expect(skill, contains('references/report-template.md'));
    expect(skill, contains('scripts/preflight.py'));
    expect(skill, contains('scripts/new_report.py'));
    expect(skill, contains('scripts/check_report.py'));
    expect(skill, isNot(contains('Codex')));

    expect(openai, contains('display_name: "fluoh"'));
    expect(
      openai,
      contains('short_description: "FlutterOH/OHOS adaptation workflow"'),
    );
    expect(
      openai,
      contains(
        'default_prompt: "Use \$fluoh to install fluoh if needed and adapt this Flutter project or package for OHOS."',
      ),
    );

    expect(reportTemplate, contains('# fluoh AI Report'));
    expect(reportTemplate, contains('## Public API / Compatibility'));
    expect(reportTemplate, contains('## Delivery Checklist'));
    expect(reportTemplate, contains('## Platform Matrix'));
    expect(reportTemplate, contains('## Local State'));
    expect(reportTemplate, contains('Diff reviewed'));
    expect(reportTemplate, contains('Release recommendation: ready'));

    expectContainsAll(preflight, [
      'schemaVersion',
      'suggestedCommands',
      'finalCheckCommands',
      'deliveryChecks',
      'reportCommand',
      'pathIsDirectory',
      'needsPackageSelection',
      'selectedPackage',
      'examplePlatforms',
      '--package',
      'fluoh --version',
      'package-repository',
    ]);
    expectContainsAll(newReport, [
      '.fluoh',
      'ai-report-',
      'report-template.md',
      'unique_report_path',
      'Release recommendation',
    ]);
    expectContainsAll(checkReport, [
      'schemaVersion',
      'Delivery checklist',
      'commandRows',
      'Release recommendation',
      'Report still contains placeholder content',
    ]);
  });

  test('documents Dart and Homebrew installation paths in both languages', () {
    final readme = File('README.md').readAsStringSync();
    final chineseReadme = File('README.zh-CN.md').readAsStringSync();
    final readmeHero = File(
      'doc/assets/svg/readme-hero.svg',
    ).readAsStringSync();
    final chineseReadmeHero = File(
      'doc/assets/svg/readme-hero.zh-CN.svg',
    ).readAsStringSync();
    final contributing = File('CONTRIBUTING.md').readAsStringSync();
    final chineseContributing = File(
      'CONTRIBUTING.zh-CN.md',
    ).readAsStringSync();

    expectContainsAll(readme, [
      'href="README.zh-CN.md">简体中文',
      'href="skills/fluoh/SKILL.md">Skill',
      'AI%20skill-skills%2Ffluoh',
      'diagnostics-JSON',
      'Adapt Flutter apps and packages to OHOS with AI.',
      'fluoh AI adaptation prompt preview',
      '## Quick Start',
      'dart pub global activate fluoh',
      'brew tap FlutterOH/tap',
      'brew install fluoh',
      'skills/fluoh',
      'fluoh skill --json',
      'returned localPath',
      'fluoh upgrade',
      'Install the fluoh skill from https://github.com/FlutterOH/fluoh/tree/main/skills/fluoh.',
      'Use \$fluoh to install fluoh if needed and adapt this Flutter project for OHOS.',
      'Use \$fluoh to adapt <upstream-git-url> for FlutterOH.',
      'Use \$fluoh to continue adapting <package-name> for OHOS.',
      'The skill checks `fluoh --version`',
      '.fluoh/ai-report-...md',
      '## Manual Fallback',
      'fluoh sdk use 3.35 --pub-get',
      'fluoh deps check',
      'fluoh deps fix',
      'fluoh doctor -p --platform ohos',
      'fluoh build --platform ohos --auto-sign',
      'For package maintainers',
      'fluoh package create <upstream-git-url>',
      'fluoh verify',
      'fluoh package status',
      'fluohf pub get',
      'fluohf run',
      'fluohf build hap',
      'https://github.com/FlutterOH/source.git',
      '[Command reference](doc/commands.md)',
      '[Source schema](doc/schema.md)',
      '[Contributing and release workflow](CONTRIBUTING.md)',
    ]);
    expectContainsNone(readme, [
      'fluoh source package',
      'fluoh source use',
      '--repository git@github.com:FlutterOH/package.git',
      'dart pub publish --dry-run',
      'git tag v0.1.0',
      'doc/ai-adaptation',
      '## Why fluoh',
      '## AI Workflows',
      '## Common Workflows',
      '### Daily Loop',
      '## Maintenance Workflows',
      '--no-init-ohos',
    ]);

    expectContainsAll(chineseReadme, [
      'href="README.md">English',
      'href="skills/fluoh/SKILL.md">Skill',
      'AI%20skill-skills%2Ffluoh',
      'diagnostics-JSON',
      '用 AI 将 Flutter App 和 Package 适配到 OHOS',
      'fluoh AI 适配提示预览',
      '## 快速开始',
      'dart pub global activate fluoh',
      'brew tap FlutterOH/tap',
      'brew install fluoh',
      'skills/fluoh',
      'fluoh skill --json',
      '返回的 localPath',
      'fluoh upgrade',
      '从 https://github.com/FlutterOH/fluoh/tree/main/skills/fluoh 安装 fluoh skill。',
      '使用 \$fluoh，必要时先安装 fluoh，然后把当前 Flutter 项目适配到 OHOS。',
      '使用 \$fluoh，把 <upstream-git-url> 适配为 FlutterOH Package。',
      '使用 \$fluoh，继续适配 <package-name> 到 OHOS。',
      'skill 会先检查 `fluoh --version`',
      '.fluoh/ai-report-...md',
      '## 手动兜底',
      'fluoh sdk use 3.35 --pub-get',
      'fluoh deps check',
      'fluoh deps fix',
      'fluoh doctor -p --platform ohos',
      'fluoh build --platform ohos --auto-sign',
      'Package 维护者可以用',
      'fluoh package create <upstream-git-url>',
      'fluoh verify',
      'fluoh package status',
      'fluohf pub get',
      'fluohf run',
      'fluohf build hap',
      'https://github.com/FlutterOH/source.git',
      '[命令参考](doc/commands.zh-CN.md)',
      '[Source schema](doc/schema.zh-CN.md)',
      '[贡献和发布流程](CONTRIBUTING.zh-CN.md)',
    ]);
    expectContainsNone(chineseReadme, [
      'fluoh source package',
      'fluoh source use',
      '--repository git@github.com:FlutterOH/package.git',
      'dart pub publish --dry-run',
      'git tag v0.1.0',
      'doc/ai-adaptation',
      '## 为什么用 fluoh',
      '## AI 工作流',
      '## 常见工作流',
      '### 日常循环',
      '## 维护工作流',
      '--no-init-ohos',
    ]);

    expectContainsAll(readmeHero, [
      'fluoh AI adaptation prompt',
      'Tell AI the goal. fluoh runs the workflow.',
      'Apps and packages follow one verified command path.',
      'Use \$fluoh to add OHOS to this Flutter project.',
      'install',
      'detect project',
      'pin SDK',
      'fix deps',
      'build/run',
      'save report',
    ]);
    expectContainsAll(chineseReadmeHero, [
      'fluoh AI 适配对话',
      '告诉 AI 目标，fluoh 负责执行。',
      'App 和 Package 都走同一套可验证命令链路。',
      '用 \$fluoh 让当前 Flutter 项目支持 OHOS。',
      '安装工具',
      '识别项目',
      '固定 SDK',
      '替换依赖',
      '构建运行',
      '保存报告',
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
      'fluoh package create',
      '--repository https://github.com/FlutterOH/package.git',
      'fluoh package sync',
      'fluoh verify',
      'fluoh package release',
      'fluoh source sync',
      'FLUOH_CHANGELOG.md',
    ]);
    expectContainsNone(contributing, [
      'feat(implementation)',
      'fluoh package adapt',
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
      'fluoh package create',
      '--repository https://github.com/FlutterOH/package.git',
      'fluoh package sync',
      'fluoh verify',
      'fluoh package release',
      'fluoh source sync',
      'FLUOH_CHANGELOG.md',
    ]);
    expectContainsNone(chineseContributing, [
      'feat(implementation)',
      'fluoh package adapt',
      'fluoh source package',
      'gh auth login',
    ]);
  });

  test('documents schema ownership and source file layout', () {
    final schema = File('doc/schema.md').readAsStringSync();
    final chineseSchema = File('doc/schema.zh-CN.md').readAsStringSync();

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
      '"fingerprint"',
      '"routes"',
      'FlutterOH/source',
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
      '"fingerprint"',
      '"routes"',
      'FlutterOH/source',
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
    final commands = File('doc/commands.md').readAsStringSync();
    final chineseCommands = File('doc/commands.zh-CN.md').readAsStringSync();

    expectContainsAll(commands, [
      '# Command Design',
      '[简体中文](commands.zh-CN.md)',
      'End-to-End Workflows',
      'AI-driven adaptation is the primary end-to-end path',
      'AI-Driven Adaptation',
      'Add OHOS to an App Project Manually',
      'skills/fluoh',
      'Run `fluoh skill --json`',
      'returned localPath',
      'dart pub global activate fluoh',
      'fluoh upgrade',
      'Install the fluoh skill from https://github.com/FlutterOH/fluoh/tree/main/skills/fluoh.',
      'Use \$fluoh to install fluoh if needed and adapt this Flutter project for OHOS.',
      'Use \$fluoh to adapt <upstream-git-url> for FlutterOH, SDK 3.35.',
      'Use \$fluoh to continue adapting <package-name> for OHOS.',
      'skills/fluoh/SKILL.md',
      'fluoh help [command]',
      'fluoh skill',
      'lib/src/cli/skill_command.dart',
      'fluoh flutter <args>',
      'fluohf <args>',
      'fluoh source sync [path]',
      'fluoh sdk use <version-or-series>',
      '--no-init-ohos',
      'fluoh package create <upstream>',
      'fluoh package add <package-path>',
      'fluoh package status',
      'fluoh verify',
      'fluoh build --platform ohos --auto-sign --json',
      'fluoh run --platform ohos --device <id>',
      'fluoh build --platform <platform>',
      '--no-codesign',
      'integration_test',
      'emulator or simulator',
      '--auto-sign',
      'fluoh devices',
      'fluoh emulators',
      'nextCommand',
      'diagnostics',
      'fluoh doctor -p --json --strict',
      '.fluoh/ai-report',
      'fluoh doctor',
      'fluoh package release',
      '--dry-run',
      'fluoh doctor',
      '--strict',
      '\$FLUOH_HOME/sources.lock.json',
      'load-index API',
    ]);
    expectContainsNone(commands, ['fluoh source package', 'fluoh source use']);

    expectContainsAll(chineseCommands, [
      '# 命令设计',
      '[English](commands.md)',
      '端到端工作流',
      'AI 驱动适配是主要端到端链路',
      'AI 驱动适配',
      '手动让 App 项目支持 OHOS',
      'skills/fluoh',
      '运行 `fluoh skill --json`',
      '返回的 localPath',
      'dart pub global activate fluoh',
      'fluoh upgrade',
      '从 https://github.com/FlutterOH/fluoh/tree/main/skills/fluoh 安装 fluoh skill。',
      '使用 \$fluoh，必要时先安装 fluoh，然后把当前 Flutter 项目适配到 OHOS。',
      '使用 \$fluoh，把 <upstream-git-url> 按 SDK 3.35 适配为 FlutterOH Package。',
      '使用 \$fluoh，继续适配 <package-name> 到 OHOS。',
      'skills/fluoh/SKILL.md',
      'fluoh help [command]',
      'fluoh skill',
      'lib/src/cli/skill_command.dart',
      'fluoh flutter <args>',
      'fluohf <args>',
      'fluoh source sync [path]',
      'fluoh sdk use <version-or-series>',
      '--no-init-ohos',
      'fluoh package create <upstream>',
      'fluoh package add <package-path>',
      'fluoh package status',
      'fluoh verify',
      'fluoh build --platform ohos --auto-sign --json',
      'fluoh run --platform ohos --device <id>',
      'fluoh build --platform <platform>',
      '--no-codesign',
      'integration_test',
      'target',
      '--auto-sign',
      'fluoh devices',
      'fluoh emulators',
      'nextCommand',
      'diagnostics',
      'fluoh doctor -p --json --strict',
      '.fluoh/ai-report',
      'fluoh doctor',
      'fluoh package release',
      '--dry-run',
      'fluoh doctor',
      '--strict',
      '\$FLUOH_HOME/sources.lock.json',
      'load-index API',
    ]);
    expectContainsNone(chineseCommands, [
      'fluoh source package',
      'fluoh source use',
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
