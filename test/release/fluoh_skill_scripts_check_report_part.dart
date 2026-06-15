part of 'fluoh_skill_scripts_test.dart';

void _registerFluohSkillScriptsCheckReportTests() {
  test(
    'new_scenario creates interaction scenarios and never overwrites',
    () async {
      final root = await createTempRoot();
      addTearDown(() => root.delete(recursive: true));
      await File('${root.path}/fluoh.yaml').writeAsString('''
schema: 1

sdk:
  version: 3.35.8-ohos-0.0.3

package:
  name: camera
  path: packages/camera/camera
''');
      final outputRoot = Directory('${root.path}/scenarios');

      final defaultScenarioResult = await Process.run('python3', [
        scenarioScript,
        root.path,
        '--scope',
        'camera',
        '--package',
        'camera',
        '--platform',
        'ohos',
        '--name',
        'capture permission',
      ]);
      expect(
        defaultScenarioResult.exitCode,
        0,
        reason: defaultScenarioResult.stderr.toString(),
      );
      final defaultScenario = File(
        defaultScenarioResult.stdout.toString().trim(),
      );
      expect(defaultScenario.existsSync(), isTrue);
      expect(
        defaultScenario.path,
        endsWith('/.fluoh/scenarios/camera/ohos-capture-permission.md'),
      );

      final androidScenarioResult = await Process.run('python3', [
        scenarioScript,
        root.path,
        '--scope',
        'camera',
        '--package',
        'camera',
        '--platform',
        'android',
        '--name',
        'capture permission',
      ]);
      expect(
        androidScenarioResult.exitCode,
        0,
        reason: androidScenarioResult.stderr.toString(),
      );
      final androidScenario = File(
        androidScenarioResult.stdout.toString().trim(),
      );
      expect(androidScenario.existsSync(), isTrue);
      expect(
        androidScenario.path,
        endsWith('/.fluoh/scenarios/camera/android-capture-permission.md'),
      );
      final androidContent = await androidScenario.readAsString();
      expect(
        androidContent,
        contains('- Example path: packages/camera/camera/example'),
      );
      expect(
        androidContent,
        contains(
          '- Session file command, when supported: fluoh run android --package camera --auto-emulator --session-file .fluoh/run-sessions/camera/android-session.json --json',
        ),
      );
      expect(
        androidContent,
        contains(
          '- Session inspect command, when supported: python3 <skill-dir>/scripts/inspect_session.py .fluoh/run-sessions/camera/android-session.json --wait 30 --expect-platform android',
        ),
      );
      expect(
        androidContent,
        contains(
          '- Session attach command, when supported: fluoh attach android --session-file .fluoh/run-sessions/camera/android-session.json',
        ),
      );
      final webScenarioResult = await Process.run('python3', [
        scenarioScript,
        root.path,
        '--scope',
        'camera',
        '--package',
        'camera',
        '--platform',
        'web',
        '--name',
        'capture permission',
      ]);
      expect(
        webScenarioResult.exitCode,
        0,
        reason: webScenarioResult.stderr.toString(),
      );
      final webScenario = File(webScenarioResult.stdout.toString().trim());
      expect(webScenario.existsSync(), isTrue);
      final webContent = await webScenario.readAsString();
      expect(
        webContent,
        contains('- Example path: packages/camera/camera/example'),
      );
      expect(webContent, contains('- Target requirement: browser'));
      expect(
        webContent,
        contains('- Related command: fluoh run web --package camera --json'),
      );
      expect(
        webContent,
        contains(
          '- Session file command, when supported: fluoh run web --package camera --session-file .fluoh/run-sessions/camera/web-session.json --json',
        ),
      );

      Future<File> createScenario() async {
        final result = await Process.run('python3', [
          scenarioScript,
          root.path,
          '--scope',
          'camera',
          '--package',
          'camera',
          '--platform',
          'ohos',
          '--name',
          'capture permission',
          '--output-root',
          outputRoot.path,
        ]);
        expect(result.exitCode, 0, reason: result.stderr.toString());
        return File(result.stdout.toString().trim());
      }

      final first = await createScenario();
      final second = await createScenario();

      expect(first.path, isNot(second.path));
      expect(
        first.uri.pathSegments.last,
        startsWith('camera-ohos-capture-permission'),
      );
      final content = await first.readAsString();
      expect(content, contains('# capture permission'));
      expect(content, contains('- Scope: camera'));
      expect(content, contains('- Package or app: camera'));
      expect(content, contains('- Platform: ohos'));
      expect(
        content,
        contains(
          '- Observation mode: flutter-debug | widget-tree | log-marker',
        ),
      );
      expect(content, contains('- Selected FlutterOH SDK: 3.35.8-ohos-0.0.3'));
      expect(
        content,
        contains('- Example path: packages/camera/camera/example'),
      );
      expect(
        content,
        contains('fluoh run ohos --package camera --auto-emulator --json'),
      );
      expect(
        content,
        contains(
          '- Session file command, when supported: fluoh run ohos --package camera --auto-emulator --session-file .fluoh/run-sessions/camera/ohos-session.json --json',
        ),
      );
      expect(
        content,
        contains(
          '- Session inspect command, when supported: python3 <skill-dir>/scripts/inspect_session.py .fluoh/run-sessions/camera/ohos-session.json --wait 30 --expect-platform ohos',
        ),
      );
      expect(
        content,
        contains(
          '- Session attach command, when supported: fluoh attach ohos --session-file .fluoh/run-sessions/camera/ohos-session.json',
        ),
      );
      expect(content, contains('## Failure Routing'));
    },
    skip: Platform.isWindows ? 'uses POSIX test executables' : false,
  );

  test(
    'collect_feedback summarizes trace feedback candidates',
    () async {
      final root = await createTempRoot();
      addTearDown(() => root.delete(recursive: true));
      final traceDir = Directory('${root.path}/.fluoh/traces/camera-session');
      await traceDir.create(recursive: true);
      final manifest = File('${traceDir.path}/trace.json');
      final candidate = {
        'id': 'F001',
        'owner': 'fluoh-cli',
        'category': 'diagnostic-gap',
        'severity': 'warning',
        'diagnosticCode': 'command.failed',
        'suggestedChange': 'Replace command.failed with a stable code.',
      };
      await manifest.writeAsString(
        jsonEncode({
          'schema': 1,
          'kind': 'fluoh.trace',
          'id': 'camera-session',
          'invocations': [
            {
              'command': 'verify',
              'commandLine':
                  'fluoh verify --package camera --json --trace-dir .fluoh/traces/camera-session',
              'feedbackCandidates': [candidate, candidate],
            },
            {
              'command': 'build',
              'commandLine':
                  'fluoh build ohos --package camera --json --trace-dir .fluoh/traces/camera-session',
              'feedbackCandidates': [
                {
                  'id': 'F002',
                  'owner': 'fluoh-cli',
                  'category': 'diagnostic-gap',
                  'severity': 'warning',
                  'diagnosticCode': 'ohos.hap_build_failed',
                  'suggestedChange':
                      'Add a targeted nextCommand for OHOS build failures.',
                },
              ],
            },
          ],
        }),
      );

      final result = await Process.run('python3', [
        collectFeedbackScript,
        traceDir.path,
      ]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
      final report =
          jsonDecode(result.stdout.toString()) as Map<String, Object?>;
      expect(report, containsPair('schema', 1));
      expect(report, containsPair('ok', true));
      expect(report, containsPair('feedbackCount', 2));
      final traces = report['traces'] as List<Object?>;
      expect(traces.single, containsPair('invocations', 2));
      final markdown = report['markdown'] as String;
      expect(markdown, contains('| F001 | fluoh-cli | diagnostic-gap |'));
      expect(markdown, contains('Replace command.failed'));
      expect(markdown, contains('Add a targeted nextCommand'));
      final feedback = report['feedback'] as List<Object?>;
      expect(feedback.map((item) => (item as Map<String, Object?>)['id']), [
        'F001',
        'F002',
      ]);
    },
    skip: Platform.isWindows ? 'uses POSIX test executables' : false,
  );

  test(
    'check_report requires explicit flutter integration test command evidence',
    () async {
      final root = await createTempRoot();
      addTearDown(() => root.delete(recursive: true));

      final backedReport = await _writeMinimalIntegrationReport(
        root,
        fileName: 'report-1780401600401.md',
        includeFlutterIntegrationCommand: true,
      );
      final backedResult = await Process.run('python3', [
        checkReportScript,
        backedReport.path,
      ]);
      expect(backedResult.exitCode, 0, reason: backedResult.stdout.toString());
      final backedJson =
          jsonDecode(backedResult.stdout.toString()) as Map<String, Object?>;
      expect(backedJson, containsPair('ok', true));
      expect(backedJson, containsPair('passedIntegrationTest', true));
      expect(backedJson, containsPair('passedAutomation', false));

      final runOnlyReport = await _writeMinimalIntegrationReport(
        root,
        fileName: 'report-1780401600402.md',
        includeFlutterIntegrationCommand: false,
      );
      final runOnlyResult = await Process.run('python3', [
        checkReportScript,
        runOnlyReport.path,
      ]);
      expect(runOnlyResult.exitCode, 1);
      final runOnlyJson =
          jsonDecode(runOnlyResult.stdout.toString()) as Map<String, Object?>;
      expect(runOnlyJson, containsPair('ok', false));
      expect(runOnlyJson, containsPair('passedIntegrationTest', false));
      expect(
        runOnlyJson['errors'],
        contains(contains('integration_test interaction evidence must cite')),
      );
    },
    skip: Platform.isWindows ? 'uses POSIX test executables' : false,
  );

  test(
    'inspect_session reports attach hints and validation failures',
    () async {
      final root = await createTempRoot();
      addTearDown(() => root.delete(recursive: true));
      final session = File('${root.path}/session.json');
      await session.writeAsString(
        jsonEncode({
          'schema': 1,
          'kind': 'flutterRunSession',
          'status': 'running',
          'platform': 'android',
          'processId': 123,
          'target': {'id': 'emulator-5554'},
          'launchDetected': true,
          'vmServiceUri': 'http://127.0.0.1:12345/abc=/',
          'outputLog': '${root.path}/flutter-run.log',
          'updatedAt': '2026-06-01T00:00:00.000',
        }),
      );

      final ok = await Process.run('python3', [
        inspectSessionScript,
        session.path,
        '--expect-platform',
        'android',
        '--require-vm-service',
      ]);
      expect(ok.exitCode, 0, reason: ok.stderr.toString());
      final report = jsonDecode(ok.stdout.toString()) as Map<String, Object?>;
      expect(report, containsPair('ok', true));
      expect(report, containsPair('status', 'running'));
      expect(report, containsPair('recommendation', 'attach-vm-service'));
      final resolvedSessionPath = session.resolveSymbolicLinksSync();
      expect(
        report,
        containsPair(
          'attachCommand',
          'fluoh attach android --session-file $resolvedSessionPath --require-vm-service',
        ),
      );
      expect(report['attachHints'], contains(contains('Attach with fluoh')));
      expect(report['attachHints'], contains(contains('Flutter VM Service')));

      final pendingSession = File('${root.path}/pending-session.json');
      await pendingSession.writeAsString(
        jsonEncode({
          'schema': 1,
          'kind': 'flutterRunSession',
          'status': 'running',
          'platform': 'android',
          'processId': 124,
          'target': {'id': 'emulator-5554'},
          'launchDetected': true,
          'updatedAt': '2026-06-01T00:00:00.000',
        }),
      );
      final waiting = await Process.start('python3', [
        inspectSessionScript,
        pendingSession.path,
        '--wait',
        '2',
        '--expect-platform',
        'android',
        '--require-vm-service',
      ]);
      final waitingStdout = waiting.stdout.transform(utf8.decoder).join();
      final waitingStderr = waiting.stderr.transform(utf8.decoder).join();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await pendingSession.writeAsString(
        jsonEncode({
          'schema': 1,
          'kind': 'flutterRunSession',
          'status': 'running',
          'platform': 'android',
          'processId': 124,
          'target': {'id': 'emulator-5554'},
          'launchDetected': true,
          'vmServiceUri': 'http://127.0.0.1:54321/def=/',
          'updatedAt': '2026-06-01T00:00:01.000',
        }),
      );
      expect(await waiting.exitCode, 0, reason: await waitingStderr);
      final waitingJson =
          jsonDecode(await waitingStdout) as Map<String, Object?>;
      expect(
        waitingJson,
        containsPair('vmServiceUri', 'http://127.0.0.1:54321/def=/'),
      );
      final resolvedPendingSessionPath = pendingSession
          .resolveSymbolicLinksSync();
      expect(
        waitingJson,
        containsPair(
          'attachCommand',
          'fluoh attach android --session-file $resolvedPendingSessionPath --require-vm-service',
        ),
      );

      final ohosSession = File('${root.path}/ohos-session.json');
      await ohosSession.writeAsString(
        jsonEncode({
          'schema': 1,
          'kind': 'flutterRunSession',
          'status': 'passed',
          'platform': 'ohos',
          'target': {'id': 'emulator-5554', 'targetPlatform': 'ohos'},
          'launchDetected': true,
          'outputLog': '${root.path}/ohos.hilog',
          'ohos': {
            'targetId': 'emulator-5554',
            'launchInfo': {
              'bundleName': 'com.example.camera',
              'moduleName': 'entry',
              'abilityName': 'EntryAbility',
            },
            'hilog': '${root.path}/ohos.hilog',
          },
          'updatedAt': '2026-06-01T00:00:00.000',
        }),
      );
      final ohos = await Process.run('python3', [
        inspectSessionScript,
        ohosSession.path,
        '--expect-platform',
        'ohos',
      ]);
      expect(ohos.exitCode, 0, reason: ohos.stderr.toString());
      final ohosReport =
          jsonDecode(ohos.stdout.toString()) as Map<String, Object?>;
      expect(ohosReport, containsPair('ok', true));
      expect(ohosReport, containsPair('recommendation', 'run-complete'));
      final resolvedOhosSessionPath = ohosSession.resolveSymbolicLinksSync();
      expect(
        ohosReport,
        containsPair(
          'attachCommand',
          'fluoh attach ohos --session-file $resolvedOhosSessionPath',
        ),
      );
      expect(ohosReport['attachHints'], contains(contains('OHOS hilog')));

      final wrongPlatform = await Process.run('python3', [
        inspectSessionScript,
        session.path,
        '--expect-platform',
        'ios',
      ]);
      expect(wrongPlatform.exitCode, 1);
      final failed =
          jsonDecode(wrongPlatform.stdout.toString()) as Map<String, Object?>;
      expect(failed, containsPair('ok', false));
      expect(
        failed['errors'],
        contains("Expected platform ios, found 'android'."),
      );
    },
    skip: Platform.isWindows ? 'uses POSIX test executables' : false,
  );

  test(
    'simulates a complete AI adaptation repair and delivery flow',
    () async {
      final root = await createTempRoot();
      addTearDown(() => root.delete(recursive: true));
      final fluoh = await writeFakeFluoh(root);
      await File('${root.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: package

sdk:
  version: 3.35.8-ohos-0.0.3

package:
  name: camera
  path: packages/camera/camera
  release:
    version: "0.1.0"
    upstream:
      version: "0.11.0"
      commit: "1111111111111111111111111111111111111111"
''');
      await Directory(
        '${root.path}/packages/camera/camera/example/android',
      ).create(recursive: true);
      await Directory(
        '${root.path}/packages/camera/camera/example/ohos',
      ).create(recursive: true);
      await Directory(
        '${root.path}/packages/camera/camera/example/web',
      ).create(recursive: true);

      final preflight = await runPreflight(root, fluohCommand: fluoh.path);
      final project = preflight['project'] as Map<String, Object?>;
      final package =
          (project['packages'] as List<Object?>).single as Map<String, Object?>;
      final examplePlatforms =
          package['examplePlatforms'] as Map<String, Object?>;
      final commandQueue = (preflight['commandQueue'] as List<Object?>)
          .cast<Map<String, Object?>>();
      final automationRunbook =
          preflight['automationRunbook'] as Map<String, Object?>;
      final checkpointPolicy =
          automationRunbook['checkpointPolicy'] as Map<String, Object?>;
      final deliveryGate = preflight['deliveryGate'] as Map<String, Object?>;
      expect(project['kind'], 'package-repository');
      expect(project['selectedPackage'], 'camera');
      expect(examplePlatforms['android'], isTrue);
      expect(examplePlatforms['ohos'], isTrue);
      expect(examplePlatforms['web'], isTrue);
      expect(
        commandQueue.map((item) => item['command']).toList(),
        containsAllInOrder([
          'fluoh verify --package camera --json --trace-dir .fluoh/traces/camera/adaptation',
          'fluoh build ohos --package camera --auto-sign --json --trace-dir .fluoh/traces/camera/adaptation',
          'fluoh run ohos --package camera --auto-emulator --json --trace-dir .fluoh/traces/camera/adaptation',
          'fluoh drive ohos --package camera --json --trace-dir .fluoh/traces/camera/adaptation',
          'fluoh doctor --platform android --json --strict',
          'fluoh run android --package camera --auto-emulator --json --trace-dir .fluoh/traces/camera/adaptation',
          'fluoh drive android --package camera --json --trace-dir .fluoh/traces/camera/adaptation',
          'fluoh doctor --platform web --json --strict',
          'fluoh run web --package camera --json --trace-dir .fluoh/traces/camera/adaptation',
          'fluoh report create --scope camera --package camera --trace-dir .fluoh/traces/camera/adaptation --json',
          'python3 <skill-dir>/scripts/check_report.py <report-path>',
          'fluoh package handoff --package camera --json',
          'fluoh package check --package camera --report <report-path> --json',
        ]),
      );
      expect(automationRunbook['mode'], 'autonomous-to-delivery');
      expect(checkpointPolicy['mode'], 'auto-local-commits');
      expect(
        stringList(checkpointPolicy['commitPhases']),
        containsAll([
          'implementation',
          'tests and example verification',
          'delivery report handoff',
        ]),
      );
      expect(deliveryGate['status'], 'active');
      expect(
        stringList(deliveryGate['finalCheckCommands']),
        containsAll([
          'fluoh drive ohos --package camera --json --trace-dir .fluoh/traces/camera/adaptation',
          'fluoh drive android --package camera --json --trace-dir .fluoh/traces/camera/adaptation',
          'fluoh run web --package camera --json --trace-dir .fluoh/traces/camera/adaptation',
          'fluoh package check --package camera --report <report-path> --json',
        ]),
      );
      expect(
        stringList(deliveryGate['readyRequires']),
        contains(
          contains(
            'fluoh package check --package camera --report <report-path> --json',
          ),
        ),
      );
      expect(
        preflight['sessionInspectCommand'],
        'python3 <skill-dir>/scripts/inspect_session.py <session-file> --wait 30 --expect-platform <platform>',
      );

      final scenarioResult = await Process.run('python3', [
        scenarioScript,
        root.path,
        '--scope',
        'camera',
        '--package',
        'camera',
        '--platform',
        'android',
        '--name',
        'permission-denied-fallback',
      ]);
      expect(
        scenarioResult.exitCode,
        0,
        reason: scenarioResult.stderr.toString(),
      );
      final scenario = File(scenarioResult.stdout.toString().trim());
      expect(await scenario.exists(), isTrue);
      await scenario.writeAsString('''
# permission-denied-fallback

## Metadata

- Scope: camera
- Package or app: camera
- Platform: android
- Target requirement: emulator
- Required local tools: Android emulator, Flutter VM Service
- Observation mode: flutter-debug | semantics-tree | log-marker
- Related command: fluoh run android --package camera --auto-emulator --session-file .fluoh/run-sessions/camera/android-session.json --json
- Session file command, when supported: fluoh run android --package camera --auto-emulator --session-file .fluoh/run-sessions/camera/android-session.json --json
- Session inspect command, when supported: python3 skills/fluoh/scripts/inspect_session.py .fluoh/run-sessions/camera/android-session.json --wait 30 --expect-platform android --require-vm-service

## Preconditions

- Selected FlutterOH SDK: 3.35.8-ohos-0.0.3
- Example path: packages/camera/camera/example
- Required permissions: camera
- Required test files, fixtures, media, URLs, accounts, or local services: none
- Required Flutter debug output, widget/component state, semantic labels, visible status text, test keys, or log markers: cameraPermissionDenied status text and camera.permissionDenied log marker
- Network requirement: none

## Scenario

| Step | Action | Expected result | Evidence |
| --- | --- | --- | --- |
| 1 | Launch camera example | Example reaches ready state | flutterRunSession status running, launchDetected true |
| 2 | Deny camera permission | Example reports denied state without crash | Semantics label cameraPermissionDenied and log marker camera.permissionDenied |

## Assertions

- Functional success state: permission denied fallback displayed and no crash recorded
- Flutter debug, widget/component tree, semantics tree, accessibility text, or log marker assertion: camera.permissionDenied
- Error state checked: permission denied
- Permission result checked: denied
- Output file, media, location, callback, or platform result checked: no output file expected

## Failure Routing

- If a permission prompt does not appear: mark scenario blocked by emulator permissions
- If a picker, camera, map, media, or external app cannot open: not applicable
- If the app crashes or freezes: route to run output log and VM Service isolate error
- If the local target cannot provide this capability: mark maintainer decision blocker

## Evidence To Record

- Device, emulator, simulator, or host id: emulator-5554
- Text, semantic, accessibility, structured log, or test assertion evidence: camera.permissionDenied
- flutterRunSession JSON status, VM Service URI, or attach result: vmServiceUri http://127.0.0.1:12345/abc=/
- Screenshots or screen recordings, optional: not used
- HAP/APK/app build path when relevant: package run output log
- Hilog or run output path: ${root.path}/.fluoh/android-run.log
- Actual result: passed
- Release impact: ready
''');

      final sessionFile = File(
        '${root.path}/.fluoh/run-sessions/camera/android-session.json',
      );
      await sessionFile.parent.create(recursive: true);
      await sessionFile.writeAsString(
        jsonEncode({
          'schema': 1,
          'kind': 'flutterRunSession',
          'status': 'running',
          'platform': 'android',
          'command':
              'flutter run -d emulator-5554 --debug --target lib/main.dart',
          'processId': 456,
          'target': {'id': 'emulator-5554', 'name': 'Pixel_6'},
          'launchDetected': true,
          'vmServiceUri': 'http://127.0.0.1:12345/abc=/',
          'outputLog': '${root.path}/.fluoh/android-run.log',
          'updatedAt': '2026-06-01T00:00:00.000',
        }),
      );
      await File(
        '${root.path}/.fluoh/android-run.log',
      ).writeAsString('camera.permissionDenied\nFlutter run key commands\n');
      final inspect = await Process.run('python3', [
        inspectSessionScript,
        sessionFile.path,
        '--wait',
        '1',
        '--expect-platform',
        'android',
        '--require-vm-service',
      ]);
      expect(inspect.exitCode, 0, reason: inspect.stderr.toString());
      final inspectJson =
          jsonDecode(inspect.stdout.toString()) as Map<String, Object?>;
      expect(inspectJson, containsPair('ok', true));
      expect(inspectJson, containsPair('recommendation', 'attach-vm-service'));
      expect(
        inspectJson,
        containsPair('vmServiceUri', 'http://127.0.0.1:12345/abc=/'),
      );

      final reportResult = await Process.run('python3', [
        reportScript,
        root.path,
        '--scope',
        'camera',
        '--package',
        'camera',
        '--upstream-version',
        '0.11.0',
        '--recommendation',
        'ready',
      ]);
      expect(reportResult.exitCode, 0, reason: reportResult.stderr.toString());
      final report = File(reportResult.stdout.toString().trim());
      final repairedReportContent =
          '''
# fluoh AI Report

- Scope: camera
- Repository: ${root.path}
- Package: camera
- Upstream version: 0.11.0
- FlutterOH SDK: 3.35.8-ohos-0.0.3
- Date: 2026-06-01 17:30:00 CST
- Recommendation: ready

## Summary

- Adaptation flow simulated from preflight through functional evidence and report validation.
- The first ready report intentionally failed automation coverage validation; the simulated AI loop repaired the coverage gate, reran report validation, and continued to handoff/check evidence.

## Changes

- Added OHOS package verification evidence, Web regression evidence, and Android AI-assisted permission scenario evidence.

## Public API / Compatibility

- Public Dart API changes: none
- Dependency constraint changes: none
- Non-OHOS regression risk: Android example run, Web example run, and permission-denied fallback checked

## Official Platform Basis

| Topic | Source | Decision / impact |
| --- | --- | --- |
| OpenHarmony camera permission and media capture APIs | OpenHarmony official API reference | permission request and denied fallback implemented and tested |

## Commands

| Command | Exit | Result | Notes |
| --- | --- | --- | --- |
| `python3 skills/fluoh/scripts/preflight.py ${root.path} --package camera` | 0 | passed | package repository detected, camera selected |
| `fluoh verify --package camera --json` | 0 | passed | pub get, analyze, and tests passed in simulated evidence |
| `fluoh build ohos --package camera --auto-sign --json` | 0 | passed | signed debug HAP built |
| `fluoh run ohos --package camera --auto-emulator --json` | 0 | passed | debug signing prepared, flutter run launched, session evidence recorded; post-launch screenshot .fluoh/evidence/screenshots/camera-ohos-main.png captured |
| `fluoh run android --package camera --auto-emulator --session-file .fluoh/run-sessions/camera/android-session.json --json` | 0 | passed | launch detected and session file written |
| `fluoh run web --package camera --json` | 0 | passed | Web example smoke and regression check passed |
| `fluoh drive android --package camera --json --trace-dir .fluoh/traces/camera/adaptation` | 0 | passed | mobile automation coverage gates ready; Android scenario ${scenario.path} passed; post-launch screenshot .fluoh/evidence/screenshots/camera-android-main.png captured |
| `python3 skills/fluoh/scripts/inspect_session.py .fluoh/run-sessions/camera/android-session.json --wait 1 --expect-platform android --require-vm-service` | 0 | passed | VM Service URI detected for non-visual inspection |
| `python3 skills/fluoh/scripts/check_report.py .fluoh/reports/camera/report-1780401600301.md` | 0 | passed | repaired report passed delivery validation |
| `fluoh package handoff --package camera --json` | 0 | passed | latest report and next commands surfaced |
| `fluoh package check --package camera --report .fluoh/reports/camera/report-1780401600301.md --json` | 0 | passed | release metadata validated |

## Delivery Checklist

- [x] Diff reviewed; unrelated files, local paths, generated caches, credentials, and private tokens excluded.
- [x] Commands table includes exit codes and enough evidence to reproduce the decision.
- [x] Existing package/app tests, example tests, and `integration_test/` were inspected against public API, platform interfaces, permissions, and behavior paths before final verification.
- [x] Missing or weak functional tests were added or repaired before final verification, or a concrete blocker is recorded.
- [x] Official OHOS/platform documentation basis was reviewed before implementation, or a concrete unavailable/not-applicable reason is recorded.
- [x] OHOS build evidence recorded.
- [x] OHOS run evidence recorded, or the missing device/emulator blocker is explicit.
- [x] Android, iOS, macOS, Linux, Web, and Windows regression checks recorded when relevant.
- [x] Every existing Android, iOS, macOS, Linux, Web, and Windows platform was functionally checked when supported by the current host/toolchain, or exact diagnostic evidence and skip reason are recorded.
- [x] Interaction automation evidence recorded through a passed `flutter test integration_test -d <device>` command or real `fluoh drive --json`, with no unresolved ready-blocking gates.
- [x] Functional interaction evidence recorded for permission, file, camera, location, media, deep link, external-app, or other device workflows.
- [x] Public API, dependency constraints, and non-OHOS regression risk reviewed.
- [x] Remaining risks and release decision are explicit.

## Platform Matrix

| Platform | Build | Run | Integration test | Target | Evidence / blocker |
| --- | --- | --- | --- | --- | --- |
| OHOS | passed | passed | absent | emulator-5554 | flutterRunSession and signing-preparation evidence |
| Android | passed | passed | absent | emulator-5554 | flutterRunSession and VM Service evidence |
| Web | passed | passed | absent | Chrome | Web example run evidence |
| iOS | not present | not present | absent | no target | example ios directory absent |
| macOS | not present | not present | absent | no target | example macos directory absent |
| Linux | not present | not present | absent | no target | example linux directory absent |
| Windows | not present | not present | absent | no target | example windows directory absent |

## Automation Coverage

- coveragePolicy.status: readyForExecution
- readyForAutomation: true
- qualityGateSummary: ready=10, notReady=0

| Gate | Status | Evidence / blocker |
| --- | --- | --- |
| coverage-inventory | readyForReview | public API and interaction inventory reviewed |
| coverage-metadata | readyForReview | scenario coverage metadata reviewed |
| coverage-items | readyForReview | every applicable capability has a coverage row |
| capability-inventory-coverage | readyForReview | camera permission fallback scenario covers applicable capability rows |
| blocked-coverage | readyForReview | no blocked rows remain |
| scenario-evidence-assertions | readyForReview | covered scenarios use functional interaction evidence such as assertText/waitText/assertLog; assertSession and screenshots are launch evidence only |
| page-readiness | readyForReview | post-launch functional page state asserted or no launch scenario required |
| existing-test-baseline | readyForReview | package and example tests reviewed |
| manifest-permission-coverage | readyForReview | Android camera permission fallback coverage reviewed |
| behavior-paths | readyForReview | denied fallback path covered; positive capture remains physical-target risk |

## Interaction Evidence

| Scenario | Method | Platform | Target | Result | Evidence / blocker |
| --- | --- | --- | --- | --- | --- |
| `${scenario.path}` | AI-assisted | Android | emulator-5554 | passed | camera permission denied fallback verified through VM Service attach hint, semantic label cameraPermissionDenied, log marker camera.permissionDenied, session ${sessionFile.path}, post-launch screenshot .fluoh/evidence/screenshots/camera-android-main.png |

## Diagnostics

- No unresolved diagnostic remains. Android session recommendation: ${inspectJson['recommendation']}.

## Fluoh Feedback

No fluoh feedback: diagnostics were actionable and no tool or Source gap was found.

## Signing

- Mode: automatic debug signing
- Generated HAPs (build-only when applicable): camera-ohos-debug.hap
- Run session / output log: .fluoh/run-sessions/camera/ohos-session.json
- Hilog (drive/debug scenarios only): no crash marker detected

## Remaining Risks

- Real camera capture positive path still depends on physical target availability.

## Local State

- Git status summary: simulated temp workspace only
- Files intentionally left uncommitted: ${scenario.path}, ${report.path}, ${sessionFile.path}
- Files that must not be committed: local session logs
- Local checkpoint commits recorded: generated baseline abc0001, selected-SDK baseline abc0002, implementation abc0003, tests and example verification abc0004, release metadata abc0005, delivery report handoff abc0006
- Push, release, tag, force-push, and destructive Git operations: not run

## Release Decision

Release recommendation: ready

Reason:
The simulated AI flow completed preflight, build/run evidence, non-visual interaction evidence, session inspection, and package check evidence.
''';

      final unrepairedReportContent = repairedReportContent
          .replaceFirst(
            '- readyForAutomation: true',
            '- readyForAutomation: false',
          )
          .replaceFirst(
            '- qualityGateSummary: ready=10, notReady=0',
            '- qualityGateSummary: ready=7, notReady=1',
          )
          .replaceFirst(
            '| scenario-evidence-assertions | readyForReview | covered scenarios use functional interaction evidence such as assertText/waitText/assertLog; assertSession and screenshots are launch evidence only |',
            '| scenario-evidence-assertions | blocked | missing log assertion before AI repair |',
          );
      await report.writeAsString(unrepairedReportContent);

      final failedCheck = await Process.run('python3', [
        checkReportScript,
        report.path,
      ]);
      expect(failedCheck.exitCode, 1);
      final failedCheckJson =
          jsonDecode(failedCheck.stdout.toString()) as Map<String, Object?>;
      expect(failedCheckJson, containsPair('ok', false));
      final failedErrors = stringList(failedCheckJson['errors']);
      expect(
        failedErrors,
        contains(
          'Automation Coverage has unresolved gates: scenario-evidence-assertions (blocked).',
        ),
      );
      expect(
        failedErrors,
        contains(
          'Automation Coverage must record readyForAutomation: true for ready reports.',
        ),
      );
      expect(
        failedErrors,
        contains(
          'Automation Coverage must record qualityGateSummary with zero notReady gates for ready reports.',
        ),
      );

      await report.writeAsString(repairedReportContent);

      final check = await Process.run('python3', [
        checkReportScript,
        report.path,
      ]);
      expect(check.exitCode, 0, reason: check.stdout.toString());
      final checkJson =
          jsonDecode(check.stdout.toString()) as Map<String, Object?>;
      expect(checkJson, containsPair('ok', true));
      expect(checkJson, containsPair('recommendation', 'ready'));
      expect(checkJson, containsPair('commandRows', 11));
      expect(checkJson, containsPair('passedCommandRows', 11));
      expect(checkJson, containsPair('automationCoverageRows', 10));
      expect(checkJson, containsPair('readyAutomationCoverageRows', 10));
      expect(checkJson, containsPair('interactionRows', 1));
      expect(checkJson, containsPair('passedInteractionRows', 1));
      expect(checkJson, containsPair('passedOhosBuild', true));
      expect(checkJson, containsPair('passedOhosRun', true));
      expect(checkJson, containsPair('passedAutomation', true));
      expect(checkJson['errors'], isEmpty);
    },
    skip: Platform.isWindows ? 'uses POSIX test executables' : false,
  );
}

Future<File> _writeMinimalIntegrationReport(
  Directory root, {
  required String fileName,
  required bool includeFlutterIntegrationCommand,
}) async {
  final report = File('${root.path}/$fileName');
  final integrationCommand = includeFlutterIntegrationCommand
      ? '| `flutter test integration_test -d emulator` | 0 | passed | integration_test exercised camera preview |\n'
      : '| `fluoh run ohos --package camera --json` | 0 | passed | launched target but did not run integration_test |\n';
  final interactionEvidence = includeFlutterIntegrationCommand
      ? 'flutter test integration_test -d emulator passed with camera.previewReady log marker'
      : 'fluoh run ohos executed flutter test integration_test -d emulator';
  await report.writeAsString('''
# fluoh AI Report

- Scope: camera
- Repository: minimal
- Package: camera
- Upstream version: 0.11.0
- FlutterOH SDK: 3.35.8-ohos-0.0.3
- Date: 2026-06-01
- Recommendation: ready

## Summary

- Minimal integration test report.

## Changes

- Added integration test evidence.

## Public API / Compatibility

- Public Dart API changes: none
- Dependency constraint changes: none
- Non-OHOS regression risk: none

## Official Platform Basis

| Topic | Source | Decision / impact |
| --- | --- | --- |
| OpenHarmony Flutter platform plugin and integration_test behavior | OpenHarmony official API reference | integration-test-backed behavior is supported by the selected emulator path |

## Commands

| Command | Exit | Result | Notes |
| --- | --- | --- | --- |
| `fluoh verify --package camera --json` | 0 | passed | baseline checks passed |
| `fluoh build ohos --package camera --auto-sign --json` | 0 | passed | signed HAP produced |
$integrationCommand
## Delivery Checklist

- [x] Diff reviewed; unrelated files, local paths, generated caches, credentials, and private tokens excluded.
- [x] Commands table includes exit codes and enough evidence to reproduce the decision.
- [x] Existing package/app tests, example tests, and `integration_test/` were inspected against public API, platform interfaces, permissions, and behavior paths before final verification.
- [x] Missing or weak functional tests were added or repaired before final verification, or a concrete blocker is recorded.
- [x] Official OHOS/platform documentation basis was reviewed before implementation, or a concrete unavailable/not-applicable reason is recorded.
- [x] OHOS build evidence recorded.
- [x] OHOS run evidence recorded, or the missing device/emulator blocker is explicit.
- [x] Android, iOS, macOS, Linux, Web, and Windows regression checks recorded when relevant.
- [x] Every existing Android, iOS, macOS, Linux, Web, and Windows platform was functionally checked when supported by the current host/toolchain, or exact diagnostic evidence and skip reason are recorded.
- [x] Interaction automation evidence recorded through integration_test or real fluoh drive JSON, with no unresolved ready-blocking gates.
- [x] Functional interaction evidence recorded for permission, file, camera, location, media, deep link, external-app, or other device workflows.
- [x] Public API, dependency constraints, and non-OHOS regression risk reviewed.
- [x] Remaining risks and release decision are explicit.

## Platform Matrix

| Platform | Build | Run | Integration test | Target | Evidence / blocker |
| --- | --- | --- | --- | --- | --- |
| OHOS | passed | passed | passed | emulator | integration test evidence recorded |
| Android | not present | not present | not required | none | no Android example platform |
| iOS | not present | not present | not required | none | no iOS example platform |
| macOS | not present | not present | not required | none | no macOS example platform |

## Automation Coverage

- coveragePolicy.status: readyForExecution
- readyForAutomation: true
- qualityGateSummary: ready=10, notReady=0

| Gate | Status | Evidence / blocker |
| --- | --- | --- |
| coverage-inventory | readyForReview | package API and example inventory reviewed |
| coverage-metadata | readyForReview | scenario metadata reviewed |
| coverage-items | readyForReview | all applicable capability rows reviewed |
| capability-inventory-coverage | readyForReview | package capabilities covered |
| blocked-coverage | readyForReview | no blocked rows remain |
| scenario-evidence-assertions | readyForReview | covered scenarios use functional interaction evidence such as assertText/waitText/assertLog; assertSession and screenshots are launch evidence only |
| page-readiness | readyForReview | post-launch functional page state asserted or no launch scenario required |
| existing-test-baseline | readyForReview | package tests reviewed |
| manifest-permission-coverage | readyForReview | selected-platform permissions reviewed |
| behavior-paths | readyForReview | success and error paths reviewed |

## Interaction Evidence

| Scenario | Method | Platform | Target | Result | Evidence / blocker |
| --- | --- | --- | --- | --- | --- |
| camera preview | integration_test | OHOS | emulator | passed | $interactionEvidence |

## Diagnostics

- No diagnostics remain.

## Fluoh Feedback

No fluoh feedback: diagnostics were actionable and no tool or Source gap was found.

## Signing

- Mode: automatic debug signing
- Generated HAPs (build-only when applicable): camera-ohos-debug.hap
- Run session / output log: not used
- Hilog (drive/debug scenarios only): not used

## Remaining Risks

- No remaining ready blocker.

## Local State

- Git status summary: minimal fixture only
- Files intentionally left uncommitted: report fixture
- Files that must not be committed: none

## Release Decision

Release recommendation: ready

Reason:
Minimal fixture for integration test evidence validation.
''');
  return report;
}
