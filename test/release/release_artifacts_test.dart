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

  List<String> issueFormIds(YamlMap template) {
    final body = template['body'] as YamlList;
    return [
      for (final field in body)
        if (field is YamlMap && field['id'] != null) field['id'] as String,
    ];
  }

  List<String> markdownHeadings(String markdown) {
    return RegExp(
      r'^## (.+)$',
      multiLine: true,
    ).allMatches(markdown).map((match) => match.group(1)!).toList();
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

  test('provides maintainer automation workflows', () {
    final prWorkflow = File(
      '.github/workflows/pr-maintenance.yml',
    ).readAsStringSync();
    final issueWorkflow = File(
      '.github/workflows/issue-triage.yml',
    ).readAsStringSync();

    expect(prWorkflow, contains('name: Maintain pull requests'));
    expect(prWorkflow, contains('pull_request_target:'));
    expect(prWorkflow, contains('issues: write'));
    expect(prWorkflow, contains('pull-requests: read'));
    expect(prWorkflow, contains('<!-- fluoh-pr-maintenance-summary -->'));
    expect(prWorkflow, contains('risk:low'));
    expect(prWorkflow, contains('risk:medium'));
    expect(prWorkflow, contains('risk:high'));
    expect(prWorkflow, isNot(contains('areaLabels')));
    expect(prWorkflow, contains('Low-risk documentation'));
    expect(
      prWorkflow,
      isNot(contains('Documentation or generated guidance changed')),
    );
    expect(prWorkflow, contains('area:sdk'));
    expect(prWorkflow, contains('area:deps'));
    expect(prWorkflow, contains('area:package'));
    expect(prWorkflow, contains('area:source'));
    expect(prWorkflow, contains('area:schema'));
    expect(prWorkflow, contains('area:platform'));
    expect(prWorkflow, contains('area:skill'));
    expect(prWorkflow, contains('area:release'));
    expect(prWorkflow, contains('JSON contract impact'));
    expect(prWorkflow, contains('Suggested focused tests'));
    expect(prWorkflow, contains('Release metadata versions'));
    expect(prWorkflow, contains('dart pub publish --dry-run'));
    expect(prWorkflow, contains('lib/src/deps/pubspec_dependency_editor.dart'));
    expect(prWorkflow, contains('lib/src/cli/machine_output.dart'));
    expect(prWorkflow, contains('Formula/fluoh.rb'));

    expect(issueWorkflow, contains('name: Triage issues'));
    expect(issueWorkflow, contains('issues:'));
    expect(issueWorkflow, contains('issues: write'));
    expect(issueWorkflow, contains('<!-- fluoh-issue-triage -->'));
    expect(issueWorkflow, contains('needs-info:auto'));
    expect(issueWorkflow, contains('classifierText'));
    expect(issueWorkflow, contains('existingAreaLabels'));
    expect(issueWorkflow, contains('hasKnownArea'));
    expect(issueWorkflow, contains(r'^### ${escaped}[ \\t]*'));
    expect(issueWorkflow, isNot(contains(r'### ${escaped}\\s*\\n\\n')));
    expect(issueWorkflow, contains('deleteComment'));
    expect(issueWorkflow, isNot(contains('for (const label of areaLabels)')));
    expect(issueWorkflow, contains('area:sdk'));
    expect(issueWorkflow, contains('area:deps'));
    expect(issueWorkflow, contains('area:package'));
    expect(issueWorkflow, contains('area:source'));
    expect(issueWorkflow, contains('area:schema'));
    expect(issueWorkflow, contains('area:platform'));
    expect(issueWorkflow, contains('area:skill'));
    expect(issueWorkflow, contains('area:release'));
    expect(issueWorkflow, contains('fluoh\\s+sdk'));
    expect(issueWorkflow, contains('fluoh\\s+package'));
    expect(issueWorkflow, contains('fluoh\\s+source'));
    expect(issueWorkflow, contains('Doctor output'));
    expect(issueWorkflow, contains('Reproduction steps'));
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
    final bugIds = issueFormIds(bugYaml);
    final featureIds = issueFormIds(featureYaml);
    final pullRequestHeadings = markdownHeadings(pullRequestTemplate);

    expect(bugYaml['name'], 'Bug report');
    expect(bugIds, containsAll(['version', 'command', 'json_output']));
    expect(bugIds, containsAll(['environment', 'local_state']));
    expect(bugTemplate, contains('fluoh --version'));
    expect(bugTemplate, contains('fluoh 0.1.0'));
    expect(bugTemplate, contains('fluoh doctor -p'));
    expect(bugTemplate, contains('Doctor output'));
    expect(bugTemplate, contains('Reproduction steps'));
    expect(bugTemplate, contains('Actual behavior'));
    expect(bugTemplate, contains('JSON output'));
    expect(bugTemplate, contains('schema'));
    expect(bugTemplate, contains('exitCode'));
    expect(bugTemplate, contains('Expected behavior'));
    expect(bugTemplate, contains('Environment'));
    expect(bugTemplate, contains('Local state and changed files'));

    expect(featureYaml['name'], 'Feature request');
    expect(featureIds, containsAll(['output_contract', 'local_state']));
    expect(featureTemplate, contains('Problem'));
    expect(featureTemplate, contains('Proposed behavior'));
    expect(featureTemplate, contains('CLI and JSON output contract'));
    expect(featureTemplate, contains('Safety and local state'));
    expect(featureTemplate, contains('Compatibility and release impact'));
    expect(configYaml['blank_issues_enabled'], isFalse);

    expect(pullRequestHeadings, containsAll(['Summary', 'Verification']));
    expect(pullRequestHeadings, contains('Behavior and contracts'));
    expect(pullRequestHeadings, contains('Release impact'));
    expect(pullRequestTemplate, contains('`dart format .`'));
    expect(pullRequestTemplate, contains('`dart analyze`'));
    expect(pullRequestTemplate, contains('`dart test`'));
    expect(pullRequestTemplate, contains('`dart pub publish --dry-run`'));
    expect(pullRequestTemplate, contains('schema'));
    expect(pullRequestTemplate, contains('exitCode'));
    expect(
      pullRequestTemplate,
      contains('test/release/release_artifacts_test.dart'),
    );
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
    final scenarioTemplate = File(
      'skills/fluoh/references/interaction-scenario-template.md',
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
    final newScenario = File(
      'skills/fluoh/scripts/new_scenario.py',
    ).readAsStringSync();
    final inspectSession = File(
      'skills/fluoh/scripts/inspect_session.py',
    ).readAsStringSync();

    expect(skill, contains('name: fluoh'));
    expect(skill, contains('adapting Flutter apps'));
    expect(skill, contains('## AI-Driven Default Flow'));
    expect(skill, contains('## App Project Flow'));
    expect(skill, contains('## Preflight Routing'));
    expect(skill, contains('## Complete AI Evidence Loop'));
    expect(skill, contains('## Package Adaptation Flow'));
    expect(skill, contains('## Automatic Adaptation Command Flow'));
    expect(skill, contains('## Source Maintenance Flow'));
    expect(skill, contains('## User Request Routing'));
    expect(skill, contains('## CLI Setup'));
    expect(skill, contains('finalCheckCommands'));
    expect(skill, contains('deliveryChecks'));
    expect(skill, contains('upgradeChecks'));
    expect(skill, contains('final acceptance gate'));
    expect(skill, contains('dart pub global activate fluoh'));
    expect(skill, contains('brew install fluoh'));
    expect(skill, contains('fluoh --version'));
    expect(skill, contains('fluoh skill --json'));
    expect(skill, contains('--package <package-name>'));
    expect(skill, contains('repository.git.url'));
    expect(skill, contains('--repository-name'));
    expect(skill, contains('--repository'));
    expect(skill, contains('--git-author-name'));
    expect(skill, contains('--git-author-email'));
    expect(skill, contains('--plan --json'));
    expect(skill, contains('final setup confirmation'));
    expect(skill, contains('wait for explicit user approval'));
    expect(skill, contains('operations that will not run'));
    expect(skill, contains('approval such as release'));
    expect(skill, contains('It is not authorization to change project files'));
    expect(skill, contains('setup step does not authorize project'));
    expect(skill, contains('Git state changes'));
    expect(skill, contains('commit message, and local Git author identity'));
    expect(skill, contains('package queue'));
    expect(skill, contains('Implementation checkpoint'));
    expect(skill, contains('Release metadata checkpoint'));
    expect(
      skill,
      contains('python3 <skill-dir>/scripts/check_report.py <report-path>'),
    );
    expect(skill, contains('ignored state'));
    expect(skill, contains('skillVersion'));
    expect(skill, contains('upgradePrompt'));
    expect(skill, contains('fluoh deps check --json'));
    expect(skill, contains('```sh\n# Local YAML/index validation only.'));
    expect(skill, contains('fluoh source check [path] --schema-only'));
    expect(skill, contains('fluoh source check <source-pr-url> --json'));
    expect(skill, contains('fluoh source check . --all --json'));
    expect(skill, contains('schemaOnly'));
    expect(skill, contains('--skip-release-checks'));
    expect(skill, contains('changedFiles'));
    expect(skill, contains('checkedManifests'));
    expect(skill, contains('releaseChecks'));
    expect(skill, contains('fluoh package docs refresh'));
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
    expect(skill, contains('references/interaction-scenario-template.md'));
    expect(skill, contains('scripts/preflight.py'));
    expect(skill, contains('scripts/new_report.py'));
    expect(skill, contains('scripts/check_report.py'));
    expect(skill, contains('scripts/new_scenario.py'));
    expect(skill, contains('scripts/inspect_session.py'));
    expect(skill, contains('scenarioCommand'));
    expect(skill, contains('sessionInspectCommand'));
    expect(skill, contains('check_report.py'));
    expect(skill, contains('--require-vm-service'));
    expect(skill, isNot(contains('Codex')));

    expect(openai, contains('display_name: "FlutterOH fluoh"'));
    expect(
      openai,
      contains('short_description: "FlutterOH adaptation and Source checks"'),
    );
    expect(
      openai,
      contains(
        'default_prompt: "Use \$fluoh to install fluoh if needed, adapt this Flutter project or package for OHOS, or precheck this FlutterOH Source change."',
      ),
    );

    expect(reportTemplate, contains('# fluoh AI Report'));
    expect(reportTemplate, contains('## Public API / Compatibility'));
    expect(reportTemplate, contains('## Delivery Checklist'));
    expect(reportTemplate, contains('## Platform Matrix'));
    expect(reportTemplate, contains('## Interaction Evidence'));
    expect(reportTemplate, contains('No interaction required: <reason>'));
    expect(reportTemplate, contains('.fluoh/scenarios/'));
    expect(
      reportTemplate,
      contains('Flutter debug/widget/semantic/log evidence'),
    );
    expect(reportTemplate, contains('flutterRunSession/VM Service evidence'));
    expect(reportTemplate, contains('screenshots optional'));

    expect(scenarioTemplate, contains('# fluoh Interaction Scenario'));
    expect(scenarioTemplate, contains('## Preconditions'));
    expect(scenarioTemplate, contains('## Scenario'));
    expect(scenarioTemplate, contains('## Assertions'));
    expect(scenarioTemplate, contains('## Evidence To Record'));
    expect(scenarioTemplate, contains('Observation mode'));
    expect(scenarioTemplate, contains('Required Flutter debug output'));
    expect(scenarioTemplate, contains('Session inspect command'));
    expect(scenarioTemplate, contains('flutterRunSession JSON status'));
    expect(scenarioTemplate, contains('functional correctness'));
    expect(scenarioTemplate, contains('widget/component state'));
    expect(scenarioTemplate, contains('screenshot-optional'));
    expect(reportTemplate, contains('## Local State'));
    expect(reportTemplate, contains('Diff reviewed'));
    expect(reportTemplate, contains('Release recommendation: ready'));

    expectContainsAll(preflight, [
      'schema',
      'upgradeChecks',
      'PACKAGE_DOC_TEMPLATE_VERSION',
      'fluoh package docs refresh --dry-run',
      'suggestedCommands',
      'finalCheckCommands',
      'deliveryChecks',
      'reportCommand',
      'sessionInspectCommand',
      'scenarioCommand',
      'pathIsDirectory',
      'hasPackageBranch',
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
    expectContainsAll(newScenario, [
      '.fluoh',
      'scenarios',
      'interaction-scenario-template.md',
      'AI-assisted interaction scenario',
      'Observation mode',
      '--platform',
      '--name',
    ]);
    expectContainsAll(inspectSession, [
      'schema',
      'flutterRunSession',
      'vmServiceUri',
      'attachHints',
      'recommendation',
      'wait-for-launch',
      '--require-vm-service',
      '--expect-platform',
    ]);
    expectContainsAll(checkReport, [
      'schema',
      'Delivery checklist',
      'Interaction Evidence',
      'interactionRows',
      'No interaction required',
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
      'read-only setup checks',
      'asks for final setup confirmation',
      'package changes',
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
      '--repository-name <flutteroh-repo-name>',
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
      '只读 setup 检查',
      '最终 setup 确认',
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
      '--repository-name <flutteroh-repo-name>',
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
      'fluoh package version',
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
      'fluoh package version',
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
      'package.release.version',
      'upstreamVersion',
      'package.sdks.<sdkLine>.releases',
      '`config.json`',
      '`sources.lock.json`',
      '"fingerprint"',
      '"packageRoutes"',
      'FlutterOH/source',
    ]);
    expectContainsNone(schema, [
      'repository.git.ref',
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
      'package.release.version',
      'upstreamVersion',
      'package.sdks.<sdkLine>.releases',
      '`config.json`',
      '`sources.lock.json`',
      '"fingerprint"',
      '"packageRoutes"',
      'FlutterOH/source',
    ]);
    expectContainsNone(chineseSchema, [
      'repository.git.ref',
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
      'helper script argv',
      'reference template',
      'paths for reports',
      'dart pub global activate fluoh',
      'fluoh upgrade',
      'Install the fluoh skill from https://github.com/FlutterOH/fluoh/tree/main/skills/fluoh.',
      'Use \$fluoh to install fluoh if needed and adapt this Flutter project for OHOS.',
      'Use \$fluoh to adapt <upstream-git-url> for FlutterOH, SDK 3.35.',
      'Use \$fluoh to continue adapting <package-name> for OHOS.',
      'does not authorize project, package, Source, local Git, or implementation',
      'final setup',
      'confirmation includes',
      'wait for explicit user approval',
      'operations that require separate approval',
      'skills/fluoh/SKILL.md',
      'fluoh help [command]',
      'fluoh skill',
      'lib/src/cli/skill_command.dart',
      'fluoh clean',
      'lib/src/clean/clean_command.dart',
      'fluoh flutter <args>',
      'fluohf <args>',
      'fluoh source list',
      'fluoh source sync [path]',
      'fluoh source check [source]',
      '--schema-only',
      'changedFiles',
      '--skip-release-checks',
      'SDK-only root',
      'fluoh sdk list',
      'fluoh sdk current',
      'fluoh sdk use <version-or-series>',
      '--no-init-ohos',
      'fluoh deps upgrade',
      'fluoh package list',
      'fluoh package create <upstream>',
      '--repository-name',
      '--plan',
      'fluoh package add <package-path>',
      'fluoh package status',
      'fluoh package version',
      'fluoh package docs refresh',
      'fluoh verify',
      'fluoh build --platform ohos --auto-sign --json',
      'fluoh run --platform ohos --device <id>',
      'fluoh build --platform <platform>',
      '--no-codesign',
      'integration_test',
      'AI-assisted interaction',
      '.fluoh/scenarios',
      'interaction-scenario-template.md',
      'Flutter debug',
      'details.vmServiceUri',
      '--session-file <path>',
      'flutterRunSession',
      'inspect_session.py',
      'component state',
      'semantic',
      'depend on image',
      'visual layout',
      'No interaction required',
      'permission grant and denial',
      'Run-smoke success',
      'emulator or simulator',
      '--auto-sign',
      'fluoh devices',
      'fluoh emulators',
      'nextCommand',
      'diagnostics',
      'fluoh doctor -p --json --strict',
      '.fluoh/ai-report',
      'fluoh doctor',
      'fluoh package check',
      'fluoh package release',
      'fluoh doctor',
      '--strict',
      '\$FLUOH_HOME/sources.lock.json',
      'load-index API',
      '`changed`, `applied`, `files`, and `dryRun`',
    ]);
    expectContainsNone(commands, [
      'fluoh source package',
      'fluoh source use',
      'source_pr_review.py',
    ]);

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
      'helper script argv',
      'reference',
      '路径',
      'dart pub global activate fluoh',
      'fluoh upgrade',
      '从 https://github.com/FlutterOH/fluoh/tree/main/skills/fluoh 安装 fluoh skill。',
      '使用 \$fluoh，必要时先安装 fluoh，然后把当前 Flutter 项目适配到 OHOS。',
      '使用 \$fluoh，把 <upstream-git-url> 按 SDK 3.35 适配为 FlutterOH Package。',
      '使用 \$fluoh，继续适配 <package-name> 到 OHOS。',
      '不等于已经批准修改项目、Package、Source、本地 Git 或实现代码',
      '最终确认清单',
      '等待用户明确批准',
      '需要单独批准的操作',
      'skills/fluoh/SKILL.md',
      'fluoh help [command]',
      'fluoh skill',
      'lib/src/cli/skill_command.dart',
      'fluoh clean',
      'lib/src/clean/clean_command.dart',
      'fluoh flutter <args>',
      'fluohf <args>',
      'fluoh source list',
      'fluoh source sync [path]',
      'fluoh source check [source]',
      '--schema-only',
      'changedFiles',
      '--skip-release-checks',
      'SDK-only 根',
      'fluoh sdk list',
      'fluoh sdk current',
      'fluoh sdk use <version-or-series>',
      '--no-init-ohos',
      'fluoh deps upgrade',
      'fluoh package list',
      'fluoh package create <upstream>',
      '--repository-name',
      '--plan',
      'fluoh package add <package-path>',
      'fluoh package status',
      'fluoh package version',
      'fluoh package docs refresh',
      'fluoh verify',
      'fluoh build --platform ohos --auto-sign --json',
      'fluoh run --platform ohos --device <id>',
      'fluoh build --platform <platform>',
      '--no-codesign',
      'integration_test',
      'AI driver',
      '.fluoh/scenarios',
      'interaction-scenario-template.md',
      'Flutter debug',
      'details.vmServiceUri',
      '--session-file <path>',
      'flutterRunSession',
      'inspect_session.py',
      '组件状态',
      '语义标签',
      '识图能力',
      '视觉布局',
      'No interaction required',
      '权限允许/拒绝',
      'run-smoke 成功',
      'target',
      '--auto-sign',
      'fluoh devices',
      'fluoh emulators',
      'nextCommand',
      'diagnostics',
      'fluoh doctor -p --json --strict',
      '.fluoh/ai-report',
      'fluoh doctor',
      'fluoh package check',
      'fluoh package release',
      'fluoh doctor',
      '--strict',
      '\$FLUOH_HOME/sources.lock.json',
      'load-index API',
      '`changed`、`applied`、`files`',
    ]);
    expectContainsNone(chineseCommands, [
      'fluoh source package',
      'fluoh source use',
      'source_pr_review.py',
    ]);
  });

  test('provides a Homebrew formula backed by native executables', () {
    final formula = File('Formula/fluoh.rb').readAsStringSync();

    expect(formula, contains('class Fluoh < Formula'));
    expect(
      formula,
      contains('https://pub.dev/api/archives/fluoh-0.1.0.tar.gz'),
    );
    expect(formula, contains('sha256 :no_check'));
    expect(formula, contains('depends_on "dart-sdk" => :build'));
    expect(formula, contains('"dart", "pub", "get"'));
    expect(formula, contains('"dart", "compile", "exe", "bin/fluoh.dart"'));
    expect(formula, contains('"dart", "compile", "exe", "bin/fluohf.dart"'));
    expect(formula, isNot(contains('"dart", "pub", "global", "activate"')));
    expect(formula, isNot(contains('pub_cache/"bin/fluoh"')));
    expect(formula, contains('fluoh --version'));
    expect(formula, contains('fluohf --help'));
  });
}
