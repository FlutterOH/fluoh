part of 'fluoh_command_runner_test.dart';

void _registerFluohCommandRunnerSkillTests() {
  test('prints Flutter-style version details from version flag', () async {
    final stdout = <String>[];
    final stderr = <String>[];
    final dartVersion = io.Platform.version.split(' ').first;
    final platformVersion = io.Platform.operatingSystemVersion
        .trim()
        .replaceFirst(RegExp(r'^Version\s+', caseSensitive: false), '')
        .replaceAllMapped(
          RegExp(r'\s*\((?:Build\s+)?([^)]+)\)', caseSensitive: false),
          (match) => ' ${match.group(1)}',
        );

    final exitCode = await runFluoh(
      ['--version'],
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(exitCode, 0);
    expect(stdout, [
      'fluoh $packageVersion - CLI for FlutterOH SDKs, projects, and package adaptation workflows',
      'Dart $dartVersion',
      'Platform ${io.Platform.operatingSystem} $platformVersion',
      'Repository https://github.com/FlutterOH/fluoh',
    ]);
    expect(stderr, isEmpty);
  });

  test('does not register a version command', () async {
    final stdout = <String>[];
    final stderr = <String>[];

    final exitCode = await runFluoh(
      ['version'],
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(exitCode, 64);
    expect(stdout, isEmpty);
    expect(stderr.join('\n'), contains('Could not find a command named'));
  });

  test('prints bundled AI skill details', () async {
    final stdout = <String>[];
    final stderr = <String>[];

    final exitCode = await runFluoh(
      ['skill'],
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(exitCode, 0);
    expect(stderr, isEmpty);
    final output = stdout.join('\n');
    expect(output, contains('fluoh skill bundled AI workflow'));
    expect(output, contains('Version $packageVersion'));
    expect(output, contains('Local path'));
    expect(output, contains('skills/fluoh'));
    expect(output, contains('Scripts preflight.py, new_report.py'));
    expect(output, contains('new_summary.py'));
    expect(output, contains('new_scenario.py'));
    expect(output, contains('inspect_session.py'));
    expect(output, contains('collect_feedback.py'));
    expect(output, contains('References app-project-flow.md'));
    expect(output, contains('package-adaptation-flow.md'));
    expect(output, contains('automation-evidence-flow.md'));
    expect(output, contains('independent-review-flow.md'));
    expect(output, contains('source-maintenance-flow.md'));
    expect(output, contains('report-template.md'));
    expect(output, contains('interaction-scenario-template.md'));
    expect(
      output,
      contains(
        'Run `fluoh skill --path`, install the printed path as the fluoh '
        'skill, and overwrite any existing installation.',
      ),
    );
    expect(
      output,
      contains(
        'Use https://github.com/FlutterOH/fluoh/tree/main/skills/fluoh only '
        'when fluoh is not installed yet.',
      ),
    );
    expect(output, contains('fluoh skill --path'));
    expect(output, contains('fluoh upgrade'));
    expect(output, contains('precheck a FlutterOH Source change'));
  });

  test('prints AI skill path only', () async {
    final stdout = <String>[];
    final stderr = <String>[];

    final exitCode = await runFluoh(
      ['skill', '--path'],
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(exitCode, 0);
    expect(stderr, isEmpty);
    expect(stdout, hasLength(1));
    expect(stdout.single, endsWith('skills/fluoh'));
    expect(io.Directory(stdout.single).existsSync(), isTrue);
  });

  test('prints bundled AI skill details as json', () async {
    final stdout = <String>[];
    final stderr = <String>[];

    final exitCode = await runFluoh(
      ['skill', '--json'],
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(exitCode, 0);
    expect(stderr, isEmpty);
    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('schema', 1));
    expect(report, containsPair('command', 'skill'));
    expect(report, containsPair('ok', true));
    expect(report, containsPair('exitCode', 0));
    expect(report, containsPair('available', true));
    expect(report, containsPair('skillName', 'fluoh'));
    expect(report, containsPair('skillVersion', packageVersion));
    expect(report['localPath'], isA<String>());
    expect(report['localPath'], contains('skills/fluoh'));
    expect(report, containsPair('repository', 'FlutterOH/fluoh'));
    expect(
      report,
      containsPair('repositoryUrl', 'https://github.com/FlutterOH/fluoh'),
    );
    expect(report, containsPair('repositoryPath', 'skills/fluoh'));
    expect(
      report,
      containsPair(
        'skillUrl',
        'https://github.com/FlutterOH/fluoh/tree/main/skills/fluoh',
      ),
    );
    expect(
      report,
      containsPair(
        'defaultPrompt',
        'Use \$fluoh to install fluoh if needed, adapt this Flutter project '
            'or package for OHOS, or precheck this FlutterOH Source change.',
      ),
    );
    expect(
      report['examplePrompts'],
      containsAll([
        'Use \$fluoh to install fluoh if needed and adapt this Flutter project '
            'for OHOS.',
        'Use \$fluoh to adapt <upstream-git-url> for FlutterOH.',
        'Use \$fluoh to continue adapting <package-name> for OHOS.',
        'Use \$fluoh to precheck this FlutterOH Source change.',
      ]),
    );
    expect(
      report,
      containsPair(
        'installPrompt',
        'Run `fluoh skill --path`, install the printed path as the fluoh '
            'skill, and overwrite any existing installation. Use '
            'https://github.com/FlutterOH/fluoh/tree/main/skills/fluoh only '
            'when fluoh is not installed yet.',
      ),
    );
    expect(report, containsPair('upgradeCommand', 'fluoh upgrade'));
    expect(
      report,
      containsPair(
        'upgradePrompt',
        'Upgrade fluoh with `fluoh upgrade`, then run `fluoh skill --path` '
            'and reinstall or reload the printed path.',
      ),
    );
    final scripts = report['scripts'] as Map<String, Object?>;
    expect(
      scripts.keys,
      containsAll([
        'preflight',
        'newReport',
        'newSummary',
        'newScenario',
        'inspectSession',
        'collectFeedback',
        'checkReport',
      ]),
    );
    final preflight = scripts['preflight'] as Map<String, Object?>;
    expect(preflight['relativePath'], 'scripts/preflight.py');
    expect(preflight['path'], allOf(isA<String>(), contains('preflight.py')));
    expect(
      preflight['argv'],
      containsAllInOrder(['python3', contains('preflight.py'), '<workspace>']),
    );
    final newReport = scripts['newReport'] as Map<String, Object?>;
    expect(newReport['relativePath'], 'scripts/new_report.py');
    expect(
      newReport['argv'],
      containsAllInOrder(['python3', contains('new_report.py'), '--scope']),
    );
    expect(newReport['argv'], isNot(contains('--root')));
    expect(newReport['argv'], isNot(contains('--type')));
    final newSummary = scripts['newSummary'] as Map<String, Object?>;
    expect(newSummary['relativePath'], 'scripts/new_summary.py');
    expect(
      newSummary['argv'],
      containsAllInOrder(['python3', contains('new_summary.py'), '--scope']),
    );
    final newScenario = scripts['newScenario'] as Map<String, Object?>;
    expect(newScenario['relativePath'], 'scripts/new_scenario.py');
    expect(
      newScenario['argv'],
      containsAllInOrder([
        'python3',
        contains('new_scenario.py'),
        '<workspace>',
        '--scope',
        '<scope>',
        '--platform',
        '<platform>',
        '--name',
        '<scenario-name>',
      ]),
    );
    final inspectSession = scripts['inspectSession'] as Map<String, Object?>;
    expect(inspectSession['relativePath'], 'scripts/inspect_session.py');
    expect(
      inspectSession['argv'],
      containsAllInOrder([
        'python3',
        contains('inspect_session.py'),
        '<session-file>',
        '--wait',
        '30',
        '--expect-platform',
        '<platform>',
      ]),
    );
    final collectFeedback = scripts['collectFeedback'] as Map<String, Object?>;
    expect(collectFeedback['relativePath'], 'scripts/collect_feedback.py');
    expect(
      collectFeedback['argv'],
      containsAllInOrder([
        'python3',
        contains('collect_feedback.py'),
        '<trace-dir-or-manifest>',
      ]),
    );
    final checkReport = scripts['checkReport'] as Map<String, Object?>;
    expect(checkReport['relativePath'], 'scripts/check_report.py');
    expect(
      checkReport['argv'],
      containsAllInOrder(['python3', contains('check_report.py')]),
    );
    final references = report['references'] as Map<String, Object?>;
    expect(
      references.keys,
      containsAll([
        'appProjectFlow',
        'packageAdaptationFlow',
        'automationEvidenceFlow',
        'independentReviewFlow',
        'sourceMaintenanceFlow',
        'reportTemplate',
        'interactionScenarioTemplate',
      ]),
    );
    final appProjectFlow = references['appProjectFlow'] as Map<String, Object?>;
    expect(appProjectFlow['relativePath'], 'references/app-project-flow.md');
    expect(
      appProjectFlow['path'],
      allOf(isA<String>(), contains('app-project-flow.md')),
    );
    final packageAdaptationFlow =
        references['packageAdaptationFlow'] as Map<String, Object?>;
    expect(
      packageAdaptationFlow['relativePath'],
      'references/package-adaptation-flow.md',
    );
    expect(
      packageAdaptationFlow['path'],
      allOf(isA<String>(), contains('package-adaptation-flow.md')),
    );
    final automationEvidenceFlow =
        references['automationEvidenceFlow'] as Map<String, Object?>;
    expect(
      automationEvidenceFlow['relativePath'],
      'references/automation-evidence-flow.md',
    );
    expect(
      automationEvidenceFlow['path'],
      allOf(isA<String>(), contains('automation-evidence-flow.md')),
    );
    final independentReviewFlow =
        references['independentReviewFlow'] as Map<String, Object?>;
    expect(
      independentReviewFlow['relativePath'],
      'references/independent-review-flow.md',
    );
    expect(
      independentReviewFlow['path'],
      allOf(isA<String>(), contains('independent-review-flow.md')),
    );
    final sourceMaintenanceFlow =
        references['sourceMaintenanceFlow'] as Map<String, Object?>;
    expect(
      sourceMaintenanceFlow['relativePath'],
      'references/source-maintenance-flow.md',
    );
    expect(
      sourceMaintenanceFlow['path'],
      allOf(isA<String>(), contains('source-maintenance-flow.md')),
    );
    final reportTemplate = references['reportTemplate'] as Map<String, Object?>;
    expect(reportTemplate['relativePath'], 'references/report-template.md');
    expect(
      reportTemplate['path'],
      allOf(isA<String>(), contains('report-template.md')),
    );
    final scenarioTemplate =
        references['interactionScenarioTemplate'] as Map<String, Object?>;
    expect(
      scenarioTemplate['relativePath'],
      'references/interaction-scenario-template.md',
    );
    expect(
      scenarioTemplate['path'],
      allOf(isA<String>(), contains('interaction-scenario-template.md')),
    );
  });

  test('advertised AI skill script argv can be executed', () async {
    final stdout = <String>[];
    final stderr = <String>[];

    final exitCode = await runFluoh(
      ['skill', '--json'],
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(exitCode, 0);
    expect(stderr, isEmpty);
    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    final scripts = report['scripts'] as Map<String, Object?>;
    final references = report['references'] as Map<String, Object?>;

    final workspace = await io.Directory.systemTemp.createTemp(
      'fluoh_skill_scripts_',
    );
    addTearDown(() async {
      if (await workspace.exists()) {
        await workspace.delete(recursive: true);
      }
    });
    await io.File('${workspace.path}/pubspec.yaml').writeAsString('''
name: fixture_app

dependencies:
  flutter:
    sdk: flutter
''');

    final preflight = await _runAdvertisedScript(
      scripts,
      'preflight',
      replacements: {'<workspace>': workspace.path},
    );
    expect(preflight.exitCode, 0, reason: preflight.stderr.toString());
    final preflightJson =
        jsonDecode(preflight.stdout.toString()) as Map<String, Object?>;
    expect(preflightJson['project'], containsPair('kind', 'app-project'));

    final newReport = await _runAdvertisedScript(
      scripts,
      'newReport',
      replacements: {
        '<workspace>': workspace.path,
        '<scope>': 'fixture_app',
        '<ready|needs-maintainer-decision|blocked>': 'blocked',
      },
    );
    expect(newReport.exitCode, 0, reason: newReport.stderr.toString());
    final reportPath = newReport.stdout.toString().trim();
    expect(await io.File(reportPath).exists(), isTrue);

    final newSummary = await _runAdvertisedScript(
      scripts,
      'newSummary',
      replacements: {'<workspace>': workspace.path, '<scope>': 'fixture_app'},
    );
    expect(newSummary.exitCode, 0, reason: newSummary.stderr.toString());
    final summaryPath = newSummary.stdout.toString().trim();
    expect(await io.File(summaryPath).exists(), isTrue);

    final newScenario = await _runAdvertisedScript(
      scripts,
      'newScenario',
      replacements: {
        '<workspace>': workspace.path,
        '<scope>': 'fixture_app',
        '<platform>': 'ohos',
        '<scenario-name>': 'permission flow',
      },
    );
    expect(newScenario.exitCode, 0, reason: newScenario.stderr.toString());
    final scenarioPath = newScenario.stdout.toString().trim();
    final scenarioFile = io.File(scenarioPath);
    expect(await scenarioFile.exists(), isTrue);
    final scenarioContent = await scenarioFile.readAsString();
    expect(scenarioContent, contains('# permission flow'));
    expect(scenarioContent, contains('- Scope: fixture_app'));
    expect(scenarioContent, contains('- Platform: ohos'));
    expect(scenarioContent, contains('functional correctness'));
    final scenarioTemplate =
        references['interactionScenarioTemplate'] as Map<String, Object?>;
    final appFlow = references['appProjectFlow'] as Map<String, Object?>;
    expect(
      await io.File(appFlow['path']! as String).readAsString(),
      contains('# App Project Flow'),
    );
    expect(
      await io.File(scenarioTemplate['path']! as String).readAsString(),
      contains('functional correctness'),
    );

    final sessionFile = io.File('${workspace.path}/session.json');
    await sessionFile.writeAsString(
      jsonEncode({
        'schema': 1,
        'kind': 'flutterRunSession',
        'status': 'running',
        'platform': 'android',
        'processId': 42,
        'launchDetected': true,
        'vmServiceUri': 'http://127.0.0.1:12345/abc=/',
        'target': {'id': 'emulator-5554'},
        'updatedAt': '2026-06-01T00:00:00.000',
      }),
    );
    final inspectSession = await _runAdvertisedScript(
      scripts,
      'inspectSession',
      replacements: {
        '<session-file>': sessionFile.path,
        '<platform>': 'android',
      },
    );
    expect(
      inspectSession.exitCode,
      0,
      reason: inspectSession.stderr.toString(),
    );
    final sessionJson =
        jsonDecode(inspectSession.stdout.toString()) as Map<String, Object?>;
    expect(sessionJson, containsPair('ok', true));
    expect(sessionJson, containsPair('recommendation', 'attach-vm-service'));

    final traceDir = io.Directory('${workspace.path}/trace session');
    await traceDir.create();
    await io.File('${traceDir.path}/trace.json').writeAsString(
      jsonEncode({
        'schema': 1,
        'kind': 'fluohTrace',
        'id': 'trace-fixture',
        'invocations': [
          {
            'command': 'verify',
            'commandLine': 'fluoh verify --json --trace-dir trace session',
            'feedbackCandidates': [
              {
                'id': 'F001',
                'owner': 'fluoh',
                'category': 'diagnostic-actionability',
                'diagnosticCode': 'verify.failed',
                'suggestedChange': 'Add a targeted verify nextCommand.',
              },
            ],
          },
        ],
      }),
    );
    final collectFeedback = await _runAdvertisedScript(
      scripts,
      'collectFeedback',
      replacements: {'<trace-dir-or-manifest>': traceDir.path},
    );
    expect(
      collectFeedback.exitCode,
      0,
      reason: collectFeedback.stderr.toString(),
    );
    final feedbackJson =
        jsonDecode(collectFeedback.stdout.toString()) as Map<String, Object?>;
    expect(feedbackJson, containsPair('ok', true));
    expect(feedbackJson, containsPair('feedbackCount', 1));
    expect(feedbackJson['markdown'], contains('F001'));
    expect(feedbackJson['markdown'], contains('Add a targeted verify'));

    final checkReport = await _runAdvertisedScript(
      scripts,
      'checkReport',
      replacements: {'<report-path>': reportPath},
    );
    expect(checkReport.exitCode, 1);
    final checkJson =
        jsonDecode(checkReport.stdout.toString()) as Map<String, Object?>;
    expect(checkJson, containsPair('ok', false));
    expect(
      checkJson['errors'],
      contains(
        'Commands table must include at least one concrete command row.',
      ),
    );
  });
}
