part of 'fluoh_skill_scripts_test.dart';

void _registerFluohSkillScriptsMiscTests() {
  test(
    'check_report fails placeholders and accepts completed ready reports',
    () async {
      final root = await createTempRoot();
      addTearDown(() => root.delete(recursive: true));
      File reportFixture(int timestamp) =>
          File('${root.path}/report-$timestamp.md');
      final outputRoot = Directory('${root.path}/reports');
      await File('${root.path}/fluoh.yaml').writeAsString('''
schema: 1

sdk:
  version: 3.35.8-ohos-0.0.3
''');

      final create = await Process.run('python3', [
        reportScript,
        root.path,
        '--scope',
        'camera',
        '--package',
        'camera',
        '--recommendation',
        'ready',
        '--output-root',
        outputRoot.path,
      ]);
      expect(create.exitCode, 0, reason: create.stderr.toString());
      final report = File(create.stdout.toString().trim());

      final incomplete = await Process.run('python3', [
        checkReportScript,
        report.path,
      ]);
      expect(incomplete.exitCode, isNot(0));
      final incompleteJson =
          jsonDecode(incomplete.stdout.toString()) as Map<String, Object?>;
      expect(incompleteJson['ok'], isFalse);
      expect(
        stringList(incompleteJson['errors']),
        contains('Report still contains placeholder content.'),
      );

      var content = await report.readAsString();
      content = content
          .replaceAll(
            '| `...` | 0 | passed | ... |',
            '| `fluoh verify --package camera --json` | 0 | passed | pub get, analyze, tests passed |\n'
                '| `fluoh build ohos --package camera --auto-sign --json` | 0 | passed | signed HAP produced |\n'
                '| `flutter test integration_test -d emulator-5554` | 0 | passed | camera preview integration_test passed |\n'
                '| `fluoh drive ohos --package camera --json` | 0 | passed | automation coverage gates ready; post-launch screenshot .fluoh/evidence/screenshots/camera-ohos-main.png captured |',
          )
          .replaceAll(
            '| `...` | official docs URL, SDK API path, or `blocked: <reason>` | implementation and test impact |',
            '| OpenHarmony camera permission and media capture APIs | OpenHarmony official API reference | permission and media behavior reviewed before implementation |',
          )
          .replaceAll(
            RegExp(r'^- \.\.\.$', multiLine: true),
            '- Evidence recorded',
          )
          .replaceAll('- [ ]', '- [x]')
          .replaceAll(
            '- coveragePolicy.status: ...\n'
                '- readyForAutomation: ...\n'
                '- qualityGateSummary: ...',
            '- coveragePolicy.status: readyForExecution\n'
                '- readyForAutomation: true\n'
                '- qualityGateSummary: ready=10, notReady=0',
          )
          .replaceAll(
            'OHOS | skipped | skipped | n/a | n/a | ...',
            'OHOS | passed | passed | n/a | emulator-5554 | flutterRunSession and signing-preparation evidence',
          )
          .replaceAll(
            'Android | not present | not present | n/a | n/a | ...',
            'Android | not present | not present | n/a | n/a | no example',
          )
          .replaceAll(
            'iOS | not present | not present | n/a | n/a | ...',
            'iOS | not present | not present | n/a | n/a | no example',
          )
          .replaceAll(
            'macOS | not present | not present | n/a | n/a | ...',
            'macOS | not present | not present | n/a | n/a | no example',
          )
          .replaceAll(
            'Linux | not present | not present | n/a | n/a | ...',
            'Linux | not present | not present | n/a | n/a | no example',
          )
          .replaceAll(
            'Web | not present | not present | n/a | n/a | ...',
            'Web | not present | not present | n/a | n/a | no example',
          )
          .replaceAll(
            'Windows | not present | not present | n/a | n/a | ...',
            'Windows | not present | not present | n/a | n/a | no example',
          )
          .replaceAll(
            RegExp(
              r'^\| `\.\.\.` \| integration_test \\\| AI-assisted \\\| manual-assisted \| OHOS \| device-or-emulator \| passed \| .* \|$',
              multiLine: true,
            ),
            '| camera preview | integration_test | OHOS | emulator-5554 | passed | flutter test integration_test -d emulator-5554 passed and hilog marker camera.captureSuccess confirmed the result |',
          )
          .replaceAll(
            '''
Replace this section with either `No fluoh feedback: <reason>` or concrete
feedback rows from `collect_feedback.py`. If JSON contains `traceError`, record
the local trace-evidence issue here.

| ID | Owner | Category | Evidence | Proposed fluoh change | Status |
| --- | --- | --- | --- | --- | --- |
''',
            'No fluoh feedback: diagnostics were actionable and no tool or Source gap was found.\n',
          )
          .replaceAll(
            'Reason:\n',
            'Reason:\nReady after local verification.\n',
          );
      await report.writeAsString(content);

      final complete = await Process.run('python3', [
        checkReportScript,
        report.path,
      ]);
      expect(complete.exitCode, 0, reason: complete.stdout.toString());
      final completeJson =
          jsonDecode(complete.stdout.toString()) as Map<String, Object?>;
      expect(completeJson['ok'], isTrue);
      expect(completeJson['commandRows'], 4);
      expect(completeJson['passedCommandRows'], 4);
      expect(completeJson['passedAutomation'], isTrue);
      expect(
        completeJson,
        containsPair('coveragePolicyStatus', 'readyForExecution'),
      );
      expect(completeJson, containsPair('readyForAutomation', 'true'));
      expect(
        completeJson,
        containsPair('qualityGateSummary', 'ready=10, notReady=0'),
      );
      expect(completeJson['automationCoverageRows'], 10);
      expect(completeJson['readyAutomationCoverageRows'], 10);
      expect(completeJson['passedVerify'], isTrue);
      expect(completeJson['passedOhosBuild'], isTrue);
      expect(completeJson['passedOhosRun'], isFalse);
      expect(completeJson['passedManualAssisted'], isFalse);
      expect(completeJson['passedMobileRunOrDrive'], isTrue);
      expect(completeJson['postLaunchVisualEvidence'], isTrue);
      expect(completeJson['interactionRows'], 1);
      expect(completeJson['passedInteractionRows'], 1);
      expect(completeJson['checklistDone'], completeJson['checklistTotal']);

      final missingOfficialBasisReport = reportFixture(1780401600106);
      await missingOfficialBasisReport.writeAsString(
        content.replaceFirst(
          RegExp(
            r'## Official Platform Basis\n\n.*?\n\n## Commands',
            dotAll: true,
          ),
          '## Commands',
        ),
      );
      final missingOfficialBasis = await Process.run('python3', [
        checkReportScript,
        missingOfficialBasisReport.path,
      ]);
      expect(missingOfficialBasis.exitCode, 1);
      final missingOfficialBasisJson =
          jsonDecode(missingOfficialBasis.stdout.toString())
              as Map<String, Object?>;
      expect(
        stringList(missingOfficialBasisJson['errors']).join('\n'),
        contains(
          'Ready reports must record official OHOS/platform documentation basis',
        ),
      );

      final missingPostLaunchVisualReport = reportFixture(1780401600107);
      await missingPostLaunchVisualReport.writeAsString(
        content
            .replaceAll(
              '; post-launch screenshot .fluoh/evidence/screenshots/camera-ohos-main.png captured',
              '',
            )
            .replaceFirst(
              '| `fluoh verify --package camera --json` | 0 | passed | pub get, analyze, tests passed |\n',
              '| `fluoh verify --package camera --json` | 0 | passed | pub get, analyze, tests passed |\n'
                  '| `fluoh drive ohos --package camera --json` | 1 | failed | post-launch screenshot .fluoh/evidence/screenshots/failed.png failed |\n',
            ),
      );
      final missingPostLaunchVisual = await Process.run('python3', [
        checkReportScript,
        missingPostLaunchVisualReport.path,
      ]);
      expect(missingPostLaunchVisual.exitCode, 1);
      final missingPostLaunchVisualJson =
          jsonDecode(missingPostLaunchVisual.stdout.toString())
              as Map<String, Object?>;
      expect(
        missingPostLaunchVisualJson,
        containsPair('postLaunchVisualEvidence', false),
      );
      expect(
        stringList(missingPostLaunchVisualJson['errors']).join('\n'),
        contains(
          'Ready reports with passed mobile fluoh run or drive evidence must record post-launch screenshot or UI-state evidence.',
        ),
      );

      final partialPostLaunchVisualReport = reportFixture(1780401600118);
      await partialPostLaunchVisualReport.writeAsString(
        content.replaceFirst(
          '| `fluoh drive ohos --package camera --json` | 0 | passed | automation coverage gates ready; post-launch screenshot .fluoh/evidence/screenshots/camera-ohos-main.png captured |',
          '| `fluoh drive ohos --package camera --json` | 0 | passed | automation coverage gates ready; post-launch screenshot .fluoh/evidence/screenshots/camera-ohos-main.png captured |\n'
              '| `fluoh drive android --package camera --json` | 0 | passed | android automation coverage gates ready |',
        ),
      );
      final partialPostLaunchVisual = await Process.run('python3', [
        checkReportScript,
        partialPostLaunchVisualReport.path,
      ]);
      expect(partialPostLaunchVisual.exitCode, 1);
      final partialPostLaunchVisualJson =
          jsonDecode(partialPostLaunchVisual.stdout.toString())
              as Map<String, Object?>;
      expect(
        stringList(partialPostLaunchVisualJson['errors']).join('\n'),
        contains(
          'Missing: android (fluoh drive android --package camera --json).',
        ),
      );

      final samePlatformPostLaunchVisualReport = reportFixture(1780401600119);
      await samePlatformPostLaunchVisualReport.writeAsString(
        content.replaceFirst(
          '| `fluoh drive ohos --package camera --json` | 0 | passed | automation coverage gates ready; post-launch screenshot .fluoh/evidence/screenshots/camera-ohos-main.png captured |',
          '| `fluoh run ohos --package camera --json` | 0 | passed | launch evidence only |\n'
              '| `fluoh drive ohos --package camera --json` | 0 | passed | automation coverage gates ready; post-launch screenshot .fluoh/evidence/screenshots/camera-ohos-main.png captured |',
        ),
      );
      final samePlatformPostLaunchVisual = await Process.run('python3', [
        checkReportScript,
        samePlatformPostLaunchVisualReport.path,
      ]);
      expect(samePlatformPostLaunchVisual.exitCode, 0);
      final samePlatformPostLaunchVisualJson =
          jsonDecode(samePlatformPostLaunchVisual.stdout.toString())
              as Map<String, Object?>;
      expect(samePlatformPostLaunchVisualJson, containsPair('ok', true));
      expect(samePlatformPostLaunchVisualJson['errors'], isEmpty);

      final manualAssistedReadyReport = reportFixture(1780401600101);
      await manualAssistedReadyReport.writeAsString(
        content
            .replaceFirst(
              '| `fluoh drive ohos --package camera --json` | 0 | passed | automation coverage gates ready; post-launch screenshot .fluoh/evidence/screenshots/camera-ohos-main.png captured |',
              '| `dart test` | 0 | passed | unit tests passed |',
            )
            .replaceFirst(
              '| camera preview | integration_test | OHOS | emulator-5554 | passed | flutter test integration_test -d emulator-5554 passed and hilog marker camera.captureSuccess confirmed the result |',
              '| camera preview | manual-assisted | OHOS | emulator-5554 | passed | flutterRunSession session file showed launched=true and hilog marker camera.captureSuccess confirmed the result |',
            ),
      );
      final manualAssistedReady = await Process.run('python3', [
        checkReportScript,
        manualAssistedReadyReport.path,
      ]);
      expect(
        manualAssistedReady.exitCode,
        0,
        reason: manualAssistedReady.stdout.toString(),
      );
      final manualAssistedReadyJson =
          jsonDecode(manualAssistedReady.stdout.toString())
              as Map<String, Object?>;
      expect(manualAssistedReadyJson['ok'], isTrue);
      expect(manualAssistedReadyJson['passedAutomation'], isFalse);
      expect(manualAssistedReadyJson['passedIntegrationTest'], isFalse);
      expect(manualAssistedReadyJson['passedManualAssisted'], isTrue);

      final launchOnlyManualAssistedReport = reportFixture(1780401600102);
      await launchOnlyManualAssistedReport.writeAsString(
        content
            .replaceFirst(
              '| `flutter test integration_test -d emulator-5554` | 0 | passed | camera preview integration_test passed |',
              '| `fluoh run ohos --package camera --json` | 0 | passed | launch evidence only |',
            )
            .replaceFirst(
              '| `fluoh drive ohos --package camera --json` | 0 | passed | automation coverage gates ready; post-launch screenshot .fluoh/evidence/screenshots/camera-ohos-main.png captured |',
              '| `dart test` | 0 | passed | unit tests passed |',
            )
            .replaceFirst(
              '| camera preview | integration_test | OHOS | emulator-5554 | passed | flutter test integration_test -d emulator-5554 passed and hilog marker camera.captureSuccess confirmed the result |',
              '| camera preview | manual-assisted | OHOS | emulator-5554 | passed | fluoh run ohos launched the example |',
            ),
      );
      final launchOnlyManualAssisted = await Process.run('python3', [
        checkReportScript,
        launchOnlyManualAssistedReport.path,
      ]);
      expect(launchOnlyManualAssisted.exitCode, 1);
      final launchOnlyManualAssistedJson =
          jsonDecode(launchOnlyManualAssisted.stdout.toString())
              as Map<String, Object?>;
      expect(launchOnlyManualAssistedJson['passedManualAssisted'], isFalse);
      expect(
        stringList(launchOnlyManualAssistedJson['errors']),
        contains(
          'Passed manual-assisted interaction evidence must include tool-readable confirmation such as logs, meaningful session state beyond launch, stable text, semantics, test keys, command JSON, hilog, or app log markers.',
        ),
      );

      final launchOnlySessionReport = reportFixture(1780401600103);
      await launchOnlySessionReport.writeAsString(
        content
            .replaceFirst(
              '| `flutter test integration_test -d emulator-5554` | 0 | passed | camera preview integration_test passed |',
              '| `fluoh run ohos --package camera --json` | 0 | passed | launch evidence only |',
            )
            .replaceFirst(
              '| `fluoh drive ohos --package camera --json` | 0 | passed | automation coverage gates ready; post-launch screenshot .fluoh/evidence/screenshots/camera-ohos-main.png captured |',
              '| `dart test` | 0 | passed | unit tests passed |',
            )
            .replaceFirst(
              '| camera preview | integration_test | OHOS | emulator-5554 | passed | flutter test integration_test -d emulator-5554 passed and hilog marker camera.captureSuccess confirmed the result |',
              '| camera preview | manual-assisted | OHOS | emulator-5554 | passed | flutterRunSession session file showed launched=true |',
            ),
      );
      final launchOnlySession = await Process.run('python3', [
        checkReportScript,
        launchOnlySessionReport.path,
      ]);
      expect(launchOnlySession.exitCode, 1);
      final launchOnlySessionJson =
          jsonDecode(launchOnlySession.stdout.toString())
              as Map<String, Object?>;
      expect(launchOnlySessionJson['passedManualAssisted'], isFalse);
      expect(
        stringList(launchOnlySessionJson['errors']),
        contains(
          'Passed manual-assisted interaction evidence must include tool-readable confirmation such as logs, meaningful session state beyond launch, stable text, semantics, test keys, command JSON, hilog, or app log markers.',
        ),
      );

      final launchOnlyAiAssistedReport = reportFixture(1780401600120);
      await launchOnlyAiAssistedReport.writeAsString(
        content.replaceFirst(
          '| camera preview | integration_test | OHOS | emulator-5554 | passed | flutter test integration_test -d emulator-5554 passed and hilog marker camera.captureSuccess confirmed the result |',
          '| camera preview | AI-assisted | OHOS | emulator-5554 | passed | assertSession passed; post-launch screenshot .fluoh/evidence/screenshots/camera-ohos-main.png captured |',
        ),
      );
      final launchOnlyAiAssisted = await Process.run('python3', [
        checkReportScript,
        launchOnlyAiAssistedReport.path,
      ]);
      expect(launchOnlyAiAssisted.exitCode, 1);
      final launchOnlyAiAssistedJson =
          jsonDecode(launchOnlyAiAssisted.stdout.toString())
              as Map<String, Object?>;
      expect(launchOnlyAiAssistedJson['passedAutomation'], isTrue);
      expect(
        stringList(launchOnlyAiAssistedJson['errors']),
        contains(
          'Passed AI-assisted interaction evidence cannot rely on assertSession, launch, wait, or screenshots alone; add functional assertions such as assertText, waitText, assertLog, visible text, semantics, test keys, diagnostic command JSON, hilog, or app log markers.',
        ),
      );

      final unbackedIntegrationReadyReport = reportFixture(1780401600104);
      await unbackedIntegrationReadyReport.writeAsString(
        content
            .replaceFirst(
              '| `flutter test integration_test -d emulator-5554` | 0 | passed | camera preview integration_test passed |\n',
              '| `fluoh run ohos --package camera --json` | 0 | passed | launch evidence only |\n',
            )
            .replaceFirst(
              '| `fluoh drive ohos --package camera --json` | 0 | passed | automation coverage gates ready; post-launch screenshot .fluoh/evidence/screenshots/camera-ohos-main.png captured |',
              '| `dart test` | 0 | passed | unit tests passed |',
            ),
      );
      final unbackedIntegrationReady = await Process.run('python3', [
        checkReportScript,
        unbackedIntegrationReadyReport.path,
      ]);
      expect(unbackedIntegrationReady.exitCode, 1);
      final unbackedIntegrationReadyJson =
          jsonDecode(unbackedIntegrationReady.stdout.toString())
              as Map<String, Object?>;
      expect(unbackedIntegrationReadyJson['passedAutomation'], isFalse);
      expect(unbackedIntegrationReadyJson['passedIntegrationTest'], isFalse);
      expect(
        stringList(unbackedIntegrationReadyJson['errors']),
        contains(
          'Passed integration_test interaction evidence must cite and be backed by a passed flutter test integration_test command row.',
        ),
      );

      final backedIntegrationReadyReport = reportFixture(1780401600105);
      await backedIntegrationReadyReport.writeAsString(
        content.replaceFirst(
          '| `fluoh drive ohos --package camera --json` | 0 | passed | automation coverage gates ready; post-launch screenshot .fluoh/evidence/screenshots/camera-ohos-main.png captured |',
          '| `dart test` | 0 | passed | unit tests passed |',
        ),
      );
      final backedIntegrationReady = await Process.run('python3', [
        checkReportScript,
        backedIntegrationReadyReport.path,
      ]);
      expect(
        backedIntegrationReady.exitCode,
        0,
        reason: backedIntegrationReady.stdout.toString(),
      );
      final backedIntegrationReadyJson =
          jsonDecode(backedIntegrationReady.stdout.toString())
              as Map<String, Object?>;
      expect(backedIntegrationReadyJson['passedAutomation'], isFalse);
      expect(backedIntegrationReadyJson['passedIntegrationTest'], isTrue);
      expect(backedIntegrationReadyJson['passedManualAssisted'], isFalse);

      final missingGateReport = reportFixture(1780401600106);
      await missingGateReport.writeAsString(
        '${content.split('\n').where((line) => !line.startsWith('| manifest-permission-coverage |')).join('\n')}\n',
      );
      final missingGateCheck = await Process.run('python3', [
        checkReportScript,
        missingGateReport.path,
      ]);
      expect(missingGateCheck.exitCode, 1);
      final missingGateJson =
          jsonDecode(missingGateCheck.stdout.toString())
              as Map<String, Object?>;
      expect(
        stringList(missingGateJson['errors']),
        contains(contains('Automation Coverage is missing required gates')),
      );
      expect(
        stringList(missingGateJson['errors']).join('\n'),
        contains('manifest-permission-coverage'),
      );

      final missingStatusReport = reportFixture(1780401600107);
      await missingStatusReport.writeAsString(
        '${content.split('\n').where((line) => !line.startsWith('- coveragePolicy.status:')).join('\n')}\n',
      );
      final missingStatusCheck = await Process.run('python3', [
        checkReportScript,
        missingStatusReport.path,
      ]);
      expect(missingStatusCheck.exitCode, 1);
      final missingStatusJson =
          jsonDecode(missingStatusCheck.stdout.toString())
              as Map<String, Object?>;
      expect(
        stringList(missingStatusJson['errors']),
        contains(
          'Automation Coverage must record coveragePolicy.status: readyForExecution for ready reports.',
        ),
      );

      final nonzeroSummaryReport = reportFixture(1780401600108);
      await nonzeroSummaryReport.writeAsString(
        content.replaceFirst(
          '- qualityGateSummary: ready=10, notReady=0',
          '- qualityGateSummary: ready=7, notReady=1',
        ),
      );
      final nonzeroSummaryCheck = await Process.run('python3', [
        checkReportScript,
        nonzeroSummaryReport.path,
      ]);
      expect(nonzeroSummaryCheck.exitCode, 1);
      final nonzeroSummaryJson =
          jsonDecode(nonzeroSummaryCheck.stdout.toString())
              as Map<String, Object?>;
      expect(
        stringList(nonzeroSummaryJson['errors']),
        contains(
          'Automation Coverage must record qualityGateSummary with zero notReady gates for ready reports.',
        ),
      );

      final manualReport = reportFixture(1780401600109);
      await manualReport.writeAsString(
        content.replaceFirst(
          '| camera preview | integration_test | OHOS | emulator-5554 | passed |',
          '| camera preview | manual | OHOS | emulator-5554 | passed |',
        ),
      );
      final manualCheck = await Process.run('python3', [
        checkReportScript,
        manualReport.path,
      ]);
      expect(manualCheck.exitCode, 1);
      final manualJson =
          jsonDecode(manualCheck.stdout.toString()) as Map<String, Object?>;
      expect(
        stringList(manualJson['errors']),
        contains(
          "Interaction Evidence must include a concrete row or 'No interaction required: <reason>'.",
        ),
      );

      final bareManualAssistedReport = reportFixture(1780401600110);
      await bareManualAssistedReport.writeAsString(
        content.replaceFirst(
          '| camera preview | integration_test | OHOS | emulator-5554 | passed | flutter test integration_test -d emulator-5554 passed and hilog marker camera.captureSuccess confirmed the result |',
          '| camera preview | manual-assisted | OHOS | emulator-5554 | passed | user session confirmed preview worked |',
        ),
      );
      final bareManualAssistedCheck = await Process.run('python3', [
        checkReportScript,
        bareManualAssistedReport.path,
      ]);
      expect(bareManualAssistedCheck.exitCode, 1);
      final bareManualAssistedJson =
          jsonDecode(bareManualAssistedCheck.stdout.toString())
              as Map<String, Object?>;
      expect(
        stringList(bareManualAssistedJson['errors']),
        contains(
          'Passed manual-assisted interaction evidence must include tool-readable confirmation such as logs, meaningful session state beyond launch, stable text, semantics, test keys, command JSON, hilog, or app log markers.',
        ),
      );

      final maintainerDecisionReport = reportFixture(1780401600111);
      await maintainerDecisionReport.writeAsString(
        content.replaceFirst(
          'Release recommendation: ready',
          'Release recommendation: needs-maintainer-decision',
        ),
      );
      final maintainerDecision = await Process.run('python3', [
        checkReportScript,
        maintainerDecisionReport.path,
      ]);
      expect(
        maintainerDecision.exitCode,
        0,
        reason: maintainerDecision.stdout.toString(),
      );
      final maintainerDecisionJson =
          jsonDecode(maintainerDecision.stdout.toString())
              as Map<String, Object?>;
      expect(
        maintainerDecisionJson,
        containsPair('recommendation', 'needs maintainer decision'),
      );

      final failedEvidenceReport = reportFixture(1780401600112);
      await failedEvidenceReport.writeAsString(
        content.replaceFirst(
          '| `fluoh verify --package camera --json` | 0 | passed | pub get, analyze, tests passed |',
          '| `fluoh verify --package camera --json` | 1 | failed | analysis failed |',
        ),
      );
      final failedEvidence = await Process.run('python3', [
        checkReportScript,
        failedEvidenceReport.path,
      ]);
      expect(failedEvidence.exitCode, isNot(0));
      final failedEvidenceJson =
          jsonDecode(failedEvidence.stdout.toString()) as Map<String, Object?>;
      expect(failedEvidenceJson['ok'], isFalse);
      expect(
        stringList(failedEvidenceJson['errors']),
        contains('Ready reports must include passed fluoh verify evidence.'),
      );

      final verifyOnlyReport = reportFixture(1780401600113);
      await verifyOnlyReport.writeAsString(
        content.replaceFirst(
          '\n| `fluoh build ohos --package camera --auto-sign --json` | 0 | passed | signed HAP produced |',
          '',
        ),
      );
      final verifyOnly = await Process.run('python3', [
        checkReportScript,
        verifyOnlyReport.path,
      ]);
      expect(verifyOnly.exitCode, isNot(0));
      final verifyOnlyJson =
          jsonDecode(verifyOnly.stdout.toString()) as Map<String, Object?>;
      expect(verifyOnlyJson['ok'], isFalse);
      expect(
        stringList(verifyOnlyJson['errors']),
        contains(
          'Ready reports must include passed OHOS build or run evidence.',
        ),
      );

      final ordinaryEvidenceReport = reportFixture(1780401600114);
      await ordinaryEvidenceReport.writeAsString(
        content
            .replaceFirst(
              '| `fluoh verify --package camera --json` | 0 | passed | pub get, analyze, tests passed |\n'
                  '| `fluoh build ohos --package camera --auto-sign --json` | 0 | passed | signed HAP produced |\n'
                  '| `flutter test integration_test -d emulator-5554` | 0 | passed | camera preview integration_test passed |\n'
                  '| `fluoh drive ohos --package camera --json` | 0 | passed | automation coverage gates ready; post-launch screenshot .fluoh/evidence/screenshots/camera-ohos-main.png captured |',
              '| `dart test` | 0 | passed | unit tests passed |',
            )
            .replaceFirst(
              '| camera preview | integration_test | OHOS | emulator-5554 | passed | flutter test integration_test -d emulator-5554 passed and hilog marker camera.captureSuccess confirmed the result |',
              '| camera preview | manual-assisted | OHOS | emulator-5554 | passed | user confirmed preview |',
            ),
      );
      final ordinaryEvidence = await Process.run('python3', [
        checkReportScript,
        ordinaryEvidenceReport.path,
      ]);
      expect(ordinaryEvidence.exitCode, isNot(0));
      final ordinaryEvidenceJson =
          jsonDecode(ordinaryEvidence.stdout.toString())
              as Map<String, Object?>;
      expect(ordinaryEvidenceJson['ok'], isFalse);
      expect(
        stringList(ordinaryEvidenceJson['errors']),
        containsAll([
          'Ready reports must include passed fluoh verify evidence.',
          'Ready reports must include passed OHOS build or run evidence.',
          'Passed manual-assisted interaction evidence must include tool-readable confirmation such as logs, meaningful session state beyond launch, stable text, semantics, test keys, command JSON, hilog, or app log markers.',
          'Ready reports must include passed fluoh drive --json, integration_test, or manual-assisted tool-readable interaction evidence.',
        ]),
      );
    },
    skip: Platform.isWindows ? 'uses POSIX test executables' : false,
  );

  test(
    'check_report rejects noncanonical report filenames',
    () async {
      final root = await createTempRoot();
      addTearDown(() => root.delete(recursive: true));
      final report = File('${root.path}/custom-report.md');
      await report.writeAsString('# custom report\n');

      final check = await Process.run('python3', [
        checkReportScript,
        report.path,
      ]);

      expect(check.exitCode, 1);
      final json = jsonDecode(check.stdout.toString()) as Map<String, Object?>;
      expect(
        stringList(json['errors']),
        contains(
          'Report filename must match report-<timestamp>.md using an integer timestamp.',
        ),
      );
    },
    skip: Platform.isWindows ? 'uses POSIX test executables' : false,
  );

  test(
    'new_report fails clearly for invalid inputs',
    () async {
      final root = await createTempRoot();
      addTearDown(() => root.delete(recursive: true));

      final missingProject = await Process.run('python3', [
        reportScript,
        '${root.path}/missing',
      ]);
      expect(missingProject.exitCode, isNot(0));
      expect(
        missingProject.stderr.toString(),
        contains('Project directory does not exist'),
      );

      final missingTemplate = await Process.run('python3', [
        reportScript,
        root.path,
        '--template',
        '${root.path}/missing-template.md',
      ]);
      expect(missingTemplate.exitCode, isNot(0));
      expect(
        missingTemplate.stderr.toString(),
        contains('Report template does not exist'),
      );
    },
    skip: Platform.isWindows ? 'uses POSIX test executables' : false,
  );

  test(
    'check_report requires completed fluoh feedback evidence',
    () async {
      final root = await createTempRoot();
      addTearDown(() => root.delete(recursive: true));
      final report = File('${root.path}/report-1780401600201.md');
      const defaultFeedback = '''
Replace this section with either `No fluoh feedback: <reason>` or concrete
feedback rows from `collect_feedback.py`. If JSON contains `traceError`, record
the local trace-evidence issue here.

| ID | Owner | Category | Evidence | Proposed fluoh change | Status |
| --- | --- | --- | --- | --- | --- |
''';
      await report.writeAsString('''
# fluoh AI Report

## Summary

- Complete.

## Changes

- Complete.

## Public API / Compatibility

- Public Dart API changes: none
- Dependency constraint changes: none
- Non-OHOS regression risk: none

## Official Platform Basis

No official platform basis required: fixture represents a pure Dart package with no platform API behavior.

## Commands

| Command | Exit | Result | Notes |
| --- | --- | --- | --- |
| `fluoh verify --package camera --json` | 0 | passed | pub get, analyze, tests passed |
| `fluoh build ohos --package camera --auto-sign --json` | 0 | passed | signed HAP produced |
| `fluoh drive ohos --package camera --json` | 0 | passed | automation coverage gates ready; post-launch screenshot .fluoh/evidence/screenshots/camera-ohos-main.png captured |

## Delivery Checklist

- [x] Diff reviewed.
- [x] Existing package/app tests, example tests, and `integration_test/` were inspected against public API, platform interfaces, permissions, and behavior paths before final verification.
- [x] Missing or weak functional tests were added or repaired before final verification, or a concrete blocker is recorded.
- [x] Official OHOS/platform documentation basis was reviewed before implementation, or a concrete unavailable/not-applicable reason is recorded.
- [x] Every existing Android, iOS, macOS, Linux, Web, and Windows platform was functionally checked when supported by the current host/toolchain, or exact diagnostic evidence and skip reason are recorded.

## Platform Matrix

| Platform | Build | Run | Integration test | Target | Evidence / blocker |
| --- | --- | --- | --- | --- | --- |
| OHOS | passed | skipped | absent | host | signed build evidence |

## Automation Coverage

- coveragePolicy.status: readyForExecution
- readyForAutomation: true
- qualityGateSummary: ready=10, notReady=0

| Gate | Status | Evidence / blocker |
| --- | --- | --- |
| coverage-inventory | readyForReview | public API inventory reviewed |
| coverage-metadata | readyForReview | no interaction required row is explicit |
| coverage-items | readyForReview | every applicable capability has a coverage row |
| capability-inventory-coverage | readyForReview | pure package capability rows covered |
| blocked-coverage | readyForReview | no blocked rows remain |
| scenario-evidence-assertions | readyForReview | covered scenarios use functional interaction evidence such as assertText/waitText/assertLog; assertSession and screenshots are launch evidence only |
| page-readiness | readyForReview | post-launch functional page state asserted or no launch scenario required |
| existing-test-baseline | readyForReview | package tests reviewed |
| manifest-permission-coverage | readyForReview | no selected-platform manifest runtime permissions apply |
| behavior-paths | readyForReview | no device-side behavior path applies |

## Interaction Evidence

No interaction required: pure Dart package exposes no device-side flow.

## Diagnostics

- None.

## Fluoh Feedback

$defaultFeedback
## Signing

- Mode: automatic debug signing
- Generated HAPs (build-only when applicable): camera-ohos-debug.hap
- Run session / output log: .fluoh/run-sessions/camera/ohos-session.json
- Hilog (drive/debug scenarios only): none

## Remaining Risks

- None.

## Local State

- Git status summary: clean
- Files intentionally left uncommitted: report-1780401600201.md
- Files that must not be committed: none

## Release Decision

Release recommendation: ready

Reason:
Ready.
''');

      final missingFeedback = await Process.run('python3', [
        checkReportScript,
        report.path,
      ]);
      expect(missingFeedback.exitCode, 1);
      final missingJson =
          jsonDecode(missingFeedback.stdout.toString()) as Map<String, Object?>;
      expect(
        missingJson['errors'],
        contains(
          "Fluoh Feedback must include a concrete row or 'No fluoh feedback: <reason>'.",
        ),
      );

      await report.writeAsString(
        (await report.readAsString()).replaceFirst(defaultFeedback, '''
| ID | Owner | Category | Evidence | Proposed fluoh change | Status |
| --- | --- | --- | --- | --- | --- |
| F001 | fluoh-cli | diagnostic-gap | trace-1, verify, command.failed | Replace command.failed with a stable code. | queued |
'''),
      );
      final accepted = await Process.run('python3', [
        checkReportScript,
        report.path,
      ]);
      expect(accepted.exitCode, 0, reason: accepted.stdout.toString());
      final acceptedJson =
          jsonDecode(accepted.stdout.toString()) as Map<String, Object?>;
      expect(acceptedJson, containsPair('ok', true));
      expect(acceptedJson, containsPair('feedbackRows', 1));
      expect(acceptedJson, containsPair('openFeedbackRows', 1));
      expect(
        acceptedJson['warnings'],
        contains('Fluoh Feedback includes queued or open tool follow-ups.'),
      );
    },
    skip: Platform.isWindows ? 'uses POSIX test executables' : false,
  );

  test(
    'check_report requires a concrete no-interaction reason',
    () async {
      final root = await createTempRoot();
      addTearDown(() => root.delete(recursive: true));
      final report = File('${root.path}/report-1780401600202.md');
      await report.writeAsString('''
# fluoh AI Report

## Summary

- Complete.

## Changes

- Complete.

## Public API / Compatibility

- Public Dart API changes: none
- Dependency constraint changes: none
- Non-OHOS regression risk: none

## Official Platform Basis

No official platform basis required: fixture represents a pure Dart package with no platform API behavior.

## Commands

| Command | Exit | Result | Notes |
| --- | --- | --- | --- |
| `fluoh verify --package pure_dart --json` | 0 | passed | no device APIs |
| `fluoh build ohos --package pure_dart --auto-sign --json` | 0 | passed | signed example HAP produced |
| `fluoh drive ohos --package pure_dart --json` | 0 | passed | automation coverage gates ready; post-launch screenshot .fluoh/evidence/screenshots/pure-dart-ohos-main.png captured |

## Delivery Checklist

- [x] Diff reviewed.
- [x] Existing package/app tests, example tests, and `integration_test/` were inspected against public API, platform interfaces, permissions, and behavior paths before final verification.
- [x] Missing or weak functional tests were added or repaired before final verification, or a concrete blocker is recorded.
- [x] Official OHOS/platform documentation basis was reviewed before implementation, or a concrete unavailable/not-applicable reason is recorded.
- [x] Every existing Android, iOS, macOS, Linux, Web, and Windows platform was functionally checked when supported by the current host/toolchain, or exact diagnostic evidence and skip reason are recorded.

## Platform Matrix

| Platform | Build | Run | Integration test | Target | Evidence / blocker |
| --- | --- | --- | --- | --- | --- |
| OHOS | passed | skipped | absent | host | pure Dart package |

## Automation Coverage

- coveragePolicy.status: readyForExecution
- readyForAutomation: true
- qualityGateSummary: ready=10, notReady=0

| Gate | Status | Evidence / blocker |
| --- | --- | --- |
| coverage-inventory | readyForReview | public API inventory reviewed |
| coverage-metadata | readyForReview | no interaction required row is explicit |
| coverage-items | readyForReview | every applicable capability has a coverage row |
| capability-inventory-coverage | readyForReview | pure Dart capability rows covered |
| blocked-coverage | readyForReview | no blocked rows remain |
| scenario-evidence-assertions | readyForReview | covered scenarios use functional interaction evidence such as assertText/waitText/assertLog; assertSession and screenshots are launch evidence only |
| page-readiness | readyForReview | post-launch functional page state asserted or no launch scenario required |
| existing-test-baseline | readyForReview | package tests reviewed |
| manifest-permission-coverage | readyForReview | no selected-platform manifest runtime permissions apply |
| behavior-paths | readyForReview | no device-side behavior path applies |

## Interaction Evidence

Use `No interaction required: <reason>` only when no device-side flow applies.

## Diagnostics

- None.

## Fluoh Feedback

No fluoh feedback: diagnostics were actionable and no tool or Source gap was found.

## Signing

- Mode: not required
- Generated HAPs (build-only when applicable): none
- Run session / output log: none
- Hilog (drive/debug scenarios only): none

## Remaining Risks

- None.

## Local State

- Git status summary: clean
- Files intentionally left uncommitted: report-1780401600202.md
- Files that must not be committed: none

## Release Decision

Release recommendation: ready

Reason:
Ready.
''');

      final missingReason = await Process.run('python3', [
        checkReportScript,
        report.path,
      ]);
      expect(missingReason.exitCode, 1);
      final missingJson =
          jsonDecode(missingReason.stdout.toString()) as Map<String, Object?>;
      expect(
        missingJson['errors'],
        contains(
          "Interaction Evidence must include a concrete row or 'No interaction required: <reason>'.",
        ),
      );

      await report.writeAsString(
        (await report.readAsString()).replaceFirst(
          'Use `No interaction required: <reason>` only when no device-side flow applies.',
          'No interaction required: pure Dart package exposes no device-side flow.',
        ),
      );
      final accepted = await Process.run('python3', [
        checkReportScript,
        report.path,
      ]);
      expect(accepted.exitCode, 0, reason: accepted.stdout.toString());
      final acceptedJson =
          jsonDecode(accepted.stdout.toString()) as Map<String, Object?>;
      expect(acceptedJson, containsPair('ok', true));
      expect(acceptedJson, containsPair('interactionRows', 0));
    },
    skip: Platform.isWindows ? 'uses POSIX test executables' : false,
  );
}
