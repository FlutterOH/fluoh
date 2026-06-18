part of 'release_artifacts_test.dart';

void _registerReleaseArtifactsCiTests() {
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
    expect(prWorkflow, contains('area:source'));
    expect(prWorkflow, contains('area:project'));
    expect(prWorkflow, contains('area:deps'));
    expect(prWorkflow, contains('area:package'));
    expect(prWorkflow, contains('area:workflow'));
    expect(prWorkflow, contains('area:devices'));
    expect(prWorkflow, contains('area:schema'));
    expect(prWorkflow, contains('area:platform'));
    expect(prWorkflow, contains('area:skill'));
    expect(prWorkflow, contains('skill_command\\.dart'));
    expect(
      prWorkflow,
      contains('test/cli/fluoh_command_runner_skill_part.dart'),
    );
    expect(prWorkflow, contains('area:release'));
    expect(prWorkflow, contains('JSON contract impact'));
    expect(prWorkflow, contains('Suggested focused tests'));
    expect(prWorkflow, contains('Release metadata versions'));
    expect(prWorkflow, contains('dart pub publish --dry-run'));
    expect(prWorkflow, contains('test/commands/create_command_test.dart'));
    expect(prWorkflow, contains('test/workflow'));
    expect(prWorkflow, contains('test/commands/workflow_commands_test.dart'));
    expect(prWorkflow, contains('test/commands/clean_command_test.dart'));
    expect(
      prWorkflow,
      contains('Plan, verify, build, run, attach, drive, report, and clean'),
    );
    expect(
      prWorkflow,
      contains('test/commands/platform_target_commands_test.dart'),
    );
    expect(prWorkflow, isNot(contains('platform_commands_test.dart')));
    expect(prWorkflow, contains('lib/src/deps/pubspec_dependency_editor.dart'));
    expect(prWorkflow, contains('lib/src/project/create_command.dart'));
    expect(prWorkflow, contains('Workflow command behavior changed'));
    expect(prWorkflow, contains('package_(new|port|upstream|release)'));
    expect(
      prWorkflow,
      contains(
        'Package new, port, upstream, release, or manifest workflow changed',
      ),
    );
    final removedPackageWorkflowPattern =
        'package_(${['create', 'sync', 'release'].join('|')})';
    expect(prWorkflow, isNot(contains(removedPackageWorkflowPattern)));
    expect(
      prWorkflow,
      isNot(
        contains(
          'Package ${['create', 'sync', 'release'].join(', ')}, '
          'or manifest workflow changed',
        ),
      ),
    );
    expect(prWorkflow, contains('lib/src/cli/machine_output.dart'));
    expect(prWorkflow, contains('Formula/fluoh.rb'));

    expect(issueWorkflow, contains('name: Triage issues'));
    expect(issueWorkflow, contains('issues:'));
    expect(issueWorkflow, contains('issues: write'));
    expect(issueWorkflow, contains('<!-- fluoh-issue-triage -->'));
    expect(issueWorkflow, contains('needs-info:auto'));
    expect(issueWorkflow, contains('classifierText'));
    expect(issueWorkflow, isNot(contains('firstSectionValue')));
    expect(issueWorkflow, contains('selectedAreaLabels'));
    expect(issueWorkflow, contains('existingAreaLabels'));
    expect(issueWorkflow, contains('hasKnownArea'));
    expect(issueWorkflow, contains(r'^### ${escaped}[ \\t]*'));
    expect(issueWorkflow, isNot(contains(r'### ${escaped}\\s*\\n\\n')));
    expect(issueWorkflow, contains('deleteComment'));
    expect(issueWorkflow, isNot(contains('for (const label of areaLabels)')));
    expect(issueWorkflow, contains('area:sdk'));
    expect(issueWorkflow, contains('area:source'));
    expect(issueWorkflow, contains('area:project'));
    expect(issueWorkflow, contains('area:deps'));
    expect(issueWorkflow, contains('area:package'));
    expect(issueWorkflow, contains('area:workflow'));
    expect(issueWorkflow, contains('area:devices'));
    expect(issueWorkflow, contains('area:schema'));
    expect(issueWorkflow, contains('area:platform'));
    expect(issueWorkflow, contains('area:upgrade'));
    expect(issueWorkflow, contains('area:skill'));
    expect(issueWorkflow, contains('area:release'));
    expect(issueWorkflow, contains('area:other'));
    expect(issueWorkflow, contains('fluoh\\s+sdk'));
    expect(issueWorkflow, contains('fluoh\\s+create'));
    expect(
      issueWorkflow,
      contains('fluoh\\s+(plan|verify|build|run|attach|drive|report|clean)'),
    );
    expect(issueWorkflow, contains('fluoh\\s+(devices|emulators)'));
    expect(issueWorkflow, contains('fluoh\\s+package'));
    expect(issueWorkflow, contains('fluoh\\s+source'));
    expect(issueWorkflow, contains('source register'));
    expect(issueWorkflow, contains('package upstream check'));
    expect(issueWorkflow, contains('package upstream sync'));
    expect(issueWorkflow, contains('Affected area'));
    expect(issueWorkflow, contains("sectionValue('Command or workflow')"));
    expect(
      issueWorkflow,
      contains("sectionValue('Affected commands or files')"),
    );
    expect(
      issueWorkflow,
      contains("sectionValue('CLI, JSON, and file contract')"),
    );
    expect(
      issueWorkflow,
      contains("sectionValue('Contract and release impact')"),
    );
    expect(issueWorkflow, isNot(contains("sectionValue('Command')")));
    expect(issueWorkflow, isNot(contains("sectionValue('Affected commands')")));
    expect(
      issueWorkflow,
      isNot(contains("sectionValue('CLI and JSON output contract')")),
    );
    expect(
      issueWorkflow,
      isNot(contains("sectionValue('Compatibility and release impact')")),
    );
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
    const areaOptions = [
      'sdk',
      'source',
      'project',
      'deps',
      'package',
      'workflow',
      'devices',
      'schema',
      'platform',
      'doctor',
      'upgrade',
      'skill',
      'release',
      'ci',
      'docs',
      'other',
    ];

    expect(bugYaml['name'], 'Bug report');
    expect(bugYaml['title'], 'bug: ');
    expect(bugYaml['labels'], contains('bug'));
    expect(
      bugIds,
      containsAll([
        'area',
        'version',
        'command',
        'reproduction',
        'actual',
        'expected',
        'doctor',
        'json_output',
        'environment',
        'local_state',
        'context',
        'disclosure',
      ]),
    );
    expect(issueFormOptions(bugYaml, 'area'), areaOptions);
    expect(issueFormField(bugYaml, 'area')['type'], 'dropdown');
    expect(issueFormField(bugYaml, 'disclosure')['type'], 'checkboxes');
    expect(bugTemplate, contains('fluoh --version'));
    expect(
      bugTemplate,
      contains(
        'fluoh 0.1.0 - CLI for FlutterOH SDKs, projects, and package support workflows',
      ),
    );
    expect(bugTemplate, contains('fluoh doctor -p'));
    expect(bugTemplate, contains('Doctor output'));
    expect(bugTemplate, contains('Reproduction steps'));
    expect(bugTemplate, contains('Actual behavior'));
    expect(bugTemplate, contains('JSON output'));
    expect(bugTemplate, contains('schema'));
    expect(bugTemplate, contains('exitCode'));
    expect(bugTemplate, contains('Expected behavior'));
    expect(bugTemplate, contains('Environment details'));
    expect(bugTemplate, contains('Local state and changed files'));
    expect(bugTemplate, contains('credentials'));
    expect(bugTemplate, contains('fluoh package port'));
    expect(bugTemplate, contains('--repository-name example'));
    expect(bugTemplate, isNot(contains(['fluoh package', 'create'].join(' '))));

    expect(featureYaml['name'], 'Feature request');
    expect(featureYaml['labels'], contains('enhancement'));
    expect(
      featureIds,
      containsAll([
        'area',
        'problem',
        'proposal',
        'affected_commands',
        'acceptance',
        'output_contract',
        'safety',
        'contract_release_impact',
        'alternatives',
      ]),
    );
    expect(issueFormOptions(featureYaml, 'area'), areaOptions);
    expect(featureTemplate, contains('Problem'));
    expect(featureTemplate, contains('Proposed behavior'));
    expect(featureTemplate, contains('Acceptance criteria'));
    expect(featureTemplate, contains('CLI, JSON, and file contract'));
    expect(featureTemplate, contains('Safety and local state'));
    expect(featureTemplate, contains('Contract and release impact'));
    expect(featureTemplate, contains('package upstream sync'));
    expect(featureTemplate, contains('source register'));
    expect(configYaml['blank_issues_enabled'], isFalse);
    final contactLinks = configYaml['contact_links'] as YamlList;
    expect(contactLinks, hasLength(2));
    expect(issueConfig, contains('Command reference'));
    expect(issueConfig, contains('Contributing guide'));

    expect(pullRequestHeadings, [
      'Summary',
      'Related issue',
      'Scope',
      'Behavior and contracts',
      'Verification',
      'Release impact',
      'Reviewer notes',
    ]);
    expect(pullRequestTemplate, contains('CLI behavior'));
    expect(pullRequestTemplate, contains('JSON contract'));
    expect(
      pullRequestTemplate,
      contains('SDK, Source, or Flutter wrapper workflow'),
    );
    expect(
      pullRequestTemplate,
      contains('Project creation or dependency workflow'),
    );
    expect(pullRequestTemplate, contains('Package repository workflow'));
    expect(
      pullRequestTemplate,
      contains(
        'App workflow: plan, verify, build, run, attach, drive, report, or clean',
      ),
    );
    expect(
      pullRequestTemplate,
      contains('Devices, emulators, or platform tooling'),
    );
    expect(pullRequestTemplate, contains('Doctor, upgrade, or skill command'));
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
}
