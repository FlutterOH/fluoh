part of 'release_artifacts_test.dart';

void _registerReleaseArtifactsSkillTests() {
  test('ships the fluoh AI agent skill', () {
    final skill = File('skills/fluoh/SKILL.md').readAsStringSync();
    final openai = File('skills/fluoh/agents/openai.yaml').readAsStringSync();
    final reportTemplate = File(
      'skills/fluoh/references/report-template.md',
    ).readAsStringSync();
    final scenarioTemplate = File(
      'skills/fluoh/references/interaction-scenario-template.md',
    ).readAsStringSync();
    final appProjectFlow = File(
      'skills/fluoh/references/app-project-flow.md',
    ).readAsStringSync();
    final automationFlow = File(
      'skills/fluoh/references/automation-evidence-flow.md',
    ).readAsStringSync();
    final packageFlow = File(
      'skills/fluoh/references/package-adaptation-flow.md',
    ).readAsStringSync();
    final sourceFlow = File(
      'skills/fluoh/references/source-maintenance-flow.md',
    ).readAsStringSync();
    final preflight = File(
      'skills/fluoh/scripts/preflight.py',
    ).readAsStringSync();
    final preflightGuidance = File(
      'skills/fluoh/scripts/preflight_guidance.py',
    ).readAsStringSync();
    final newReport = File(
      'skills/fluoh/scripts/new_report.py',
    ).readAsStringSync();
    final newSummary = File(
      'skills/fluoh/scripts/new_summary.py',
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
    expect(skill.split('\n').length, lessThanOrEqualTo(350));
    expectContainsAll(skill, [
      'name: fluoh',
      'adapting Flutter apps',
      '## Helper Scripts',
      '## Request Routing',
      '## Start',
      '## CLI Setup',
      '## Adaptation Scope Gate',
      '## Preflight Routing',
      '## JSON Diagnostics',
      '## Evidence Loop',
      '## Completion Report',
      'finalCheckCommands',
      'deliveryChecks',
      'automationRunbook',
      'deliveryGate',
      'upgradeChecks',
      'final adaptation scope confirmation',
      'explicit user',
      'approval unless',
      'operations that will not run',
      'It is not authorization to change project files',
      'setup step does not authorize project',
      'dart pub global activate fluoh',
      'brew tap FlutterOH/fluoh https://github.com/FlutterOH/fluoh.git',
      'brew install FlutterOH/fluoh/fluoh',
      'brew tap FlutterOH/tap',
      'fluoh --version',
      'fluoh upgrade',
      'fluoh skill --json',
      'skillVersion',
      'upgradePrompt',
      'reinstall or reload',
      'overwriting any existing fluoh',
      'references/app-project-flow.md',
      'references/package-adaptation-flow.md',
      'references/automation-evidence-flow.md',
      'references/source-maintenance-flow.md',
      'references/report-template.md',
      'references/interaction-scenario-template.md',
      'scripts/preflight.py',
      'scripts/new_report.py',
      'scripts/new_summary.py',
      'scripts/check_report.py',
      'scripts/collect_feedback.py',
      'scripts/new_scenario.py',
      'scripts/inspect_session.py',
      'scenarioCommand',
      'sessionInspectCommand',
      'sessionAttachCommand',
      'deliveryGate.readyRequires',
      'Session attach command',
      'python3 <skill-dir>/scripts/check_report.py <report-path>',
      'manual-assisted',
    ]);
    expect(skill, isNot(contains('Codex')));

    expectContainsAll(appProjectFlow, [
      '# App Project Flow',
      'fluoh deps check --json',
      'fluoh deps fix --dry-run',
      'fluoh build ohos --auto-sign --json',
      'fluoh run ohos --auto-emulator --json',
    ]);
    expectContainsAll(packageFlow, [
      '# Package Adaptation Flow',
      '## End-to-End Contract',
      'fluoh package discover <upstream> --json',
      '--repository-name',
      '--repository',
      '--git-author-name',
      '--git-author-email',
      '--plan --json',
      'repository.git.url',
      'fluoh package docs refresh',
      'fluoh package docs refresh --allow-dirty',
      'fluoh package queue',
      'fluoh verify --package <name> --json',
      'fluoh run ohos --package <name> --auto-emulator --json',
      'fluoh drive ohos --package <name> --json',
      'fluoh report create --scope <name> --package <name>',
      'python3 <skill-dir>/scripts/check_report.py <report-path>',
      'fluoh run android --package <name> --auto-emulator --json',
      'fluoh run ios --package <name> --auto-emulator --json',
      'fluoh run web --package <name> --json',
      'fluoh build linux --package <name> --json',
      'fluoh build windows --package <name> --json',
      'local Git author identity',
      'Create small local checkpoint commits automatically',
      'delivery report handoff',
      'still require separate maintainer approval',
    ]);
    expectContainsAll(automationFlow, [
      '# Automation Evidence Flow',
      'fluoh drive <platform> --package <name> --dry-run --json',
      'flutterRunSession',
      '--require-vm-service',
      'integration_test',
      'manual-assisted',
      'manifestPermissionCoverage',
      'permissionCoverage',
      'readyForAutomation',
      'ready=8, notReady=0',
      'automation.repairQueue',
    ]);
    expectContainsAll(sourceFlow, [
      '# Source Maintenance Flow',
      'fluoh source check [path] --schema-only --json',
      'fluoh source check <source-pr-url> --json',
      'fluoh source check . --all --json',
      'schemaOnly',
      '--skip-release-checks',
      'changedFiles',
      'checkedManifests',
      'releaseChecks',
    ]);

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
    expect(reportTemplate, contains('## Adaptation Responsibility'));
    expect(reportTemplate, contains('## Public API / Compatibility'));
    expect(reportTemplate, contains('## Delivery Checklist'));
    expect(reportTemplate, contains('## Platform Matrix'));
    expect(reportTemplate, contains('## Automation Coverage'));
    expect(reportTemplate, contains('coverage-inventory'));
    expect(reportTemplate, contains('complete required'));
    expect(reportTemplate, contains('## Interaction Evidence'));
    expect(reportTemplate, contains('No interaction required: <reason>'));
    expect(
      reportTemplate,
      contains('flutter test integration_test -d <device>'),
    );
    expect(reportTemplate, contains('manual-assisted'));
    expect(reportTemplate, contains('meaningful session state beyond launch'));
    expect(reportTemplate, contains('.fluoh/scenarios/'));
    expect(
      reportTemplate,
      contains('Flutter debug/widget/semantic/log evidence'),
    );
    expect(reportTemplate, contains('flutterRunSession/VM Service evidence'));
    expect(reportTemplate, contains('screenshots optional'));
    expect(newSummary, contains('fluoh Monorepo Summary'));
    expect(newSummary, contains('Package Matrix'));
    expect(newSummary, contains('.fluoh/reports'));

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
      'fluoh package docs refresh --allow-dirty',
      'suggestedCommands',
      'finalCheckCommands',
      'deliveryChecks',
      'automationRunbook',
      'deliveryGate',
      'reportCommand',
      'summaryCommand',
      'sessionInspectCommand',
      'sessionAttachCommand',
      'scenarioCommand',
      'pathIsDirectory',
      'hasPackageBranch',
      'selectedPackage',
      'examplePlatforms',
      '--package',
      'fluoh --version',
      'package-repository',
    ]);
    expectContainsAll(preflightGuidance, [
      'command_queue',
      'automation_runbook',
      'delivery_gate',
      'delivery_checks',
      'report_command',
      'summary_command',
      'session_inspect_command',
      'session_attach_command',
      'scenario_command',
      'fluoh attach <platform> --session-file <session-file>',
    ]);
    expectContainsAll(newReport, [
      '.fluoh',
      'report-',
      'report-template.md',
      'timestamp',
      'Release recommendation',
    ]);
    expectContainsAll(newSummary, [
      '.fluoh',
      'summary-',
      'Package Matrix',
      'Fluoh Feedback',
      '--package',
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
      'attachCommand',
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
}
