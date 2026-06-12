part of 'fluoh_skill_scripts_test.dart';

void _registerFluohSkillScriptsReportTests() {
  test(
    'preflight reports schema migration blockers before adaptation',
    () async {
      final root = await createTempRoot();
      addTearDown(() => root.delete(recursive: true));
      final fluoh = await writeFakeFluoh(root);

      await File('${root.path}/pubspec.yaml').writeAsString('''
name: old_app
dependencies:
  flutter:
    sdk: flutter
''');
      await File('${root.path}/fluoh.yaml').writeAsString('''
sdk:
  version: 3.35.8-ohos-0.0.3
''');

      final report = await runPreflight(root, fluohCommand: fluoh.path);
      final upgradeChecks = report['upgradeChecks'] as Map<String, Object?>;
      final schema = upgradeChecks['schema'] as Map<String, Object?>;

      expect(schema['status'], 'missing');
      expect(upgradeChecks['needsMigration'], isTrue);
      expect(
        stringList(upgradeChecks['notes']),
        contains(contains('current canonical schema')),
      );
      expect(
        stringList(report['deliveryChecks']),
        contains(contains('upgradeChecks has no migration blocker')),
      );
    },
    skip: Platform.isWindows ? 'uses POSIX test executables' : false,
  );

  test(
    'preflight reports current-marker package docs when dry-run finds changes',
    () async {
      final root = await createTempRoot();
      addTearDown(() => root.delete(recursive: true));
      final fluoh = await writeFakeFluoh(
        root,
        docsDryRunOutput: '''
Package docs would be refreshed
    - README.md
    - FLUOH.md
    - AGENTS.md
''',
      );

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
      await File('${root.path}/FLUOH.md').writeAsString('''
<!-- fluoh:generated:start id=package-implementation-guide template=2 -->
Generated content.
<!-- fluoh:generated:end id=package-implementation-guide -->
''');
      await File('${root.path}/AGENTS.md').writeAsString('''
<!-- fluoh:generated:start id=package-agents-instructions template=1 -->
Generated content.
<!-- fluoh:generated:end id=package-agents-instructions -->
''');
      await File('${root.path}/README.md').writeAsString('''
<!-- fluoh:generated:start id=package-readme-adaptation template=1 -->
Generated content.
<!-- fluoh:generated:end id=package-readme-adaptation -->
''');

      final report = await runPreflight(root, fluohCommand: fluoh.path);
      final upgradeChecks = report['upgradeChecks'] as Map<String, Object?>;
      final packageDocs = upgradeChecks['packageDocs'] as Map<String, Object?>;
      final dryRun = packageDocs['dryRun'] as Map<String, Object?>;

      expect(packageDocs['needsRefresh'], isTrue);
      expect(dryRun['ok'], isTrue);
      expect(dryRun['needsRefresh'], isTrue);
      expect(dryRun['files'], ['README.md', 'FLUOH.md', 'AGENTS.md']);
      expect(
        stringList(report['suggestedCommands']),
        containsAll([
          'fluoh package docs refresh --dry-run',
          'fluoh package docs refresh',
        ]),
      );
    },
    skip: Platform.isWindows ? 'uses POSIX test executables' : false,
  );

  test(
    'preflight suggests allow-dirty docs refresh in dirty package repos',
    () async {
      final root = await createTempRoot();
      addTearDown(() => root.delete(recursive: true));
      final fluoh = await writeFakeFluoh(
        root,
        docsDryRunOutput: '''
Package docs would be refreshed
- FLUOH.md
''',
      );

      await File('${root.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: package

sdk:
  version: 3.35.8-ohos-0.0.3

package:
  name: camera
  path: .
  release:
    version: "0.1.0"
    upstream:
      version: "0.11.0"
      commit: "1111111111111111111111111111111111111111"
''');
      await File('${root.path}/FLUOH.md').writeAsString('''
<!-- fluoh:generated:start id=package-implementation-guide template=1 -->
Generated content.
<!-- fluoh:generated:end id=package-implementation-guide -->
''');
      await File('${root.path}/AGENTS.md').writeAsString('''
<!-- fluoh:generated:start id=package-agents-instructions template=1 -->
Generated content.
<!-- fluoh:generated:end id=package-agents-instructions -->
''');
      await File('${root.path}/README.md').writeAsString('''
<!-- fluoh:generated:start id=package-readme-adaptation template=1 -->
Generated content.
<!-- fluoh:generated:end id=package-readme-adaptation -->
''');
      await runProcess('git', ['init', '--initial-branch=main'], root);
      await runProcess('git', [
        'config',
        'user.email',
        'fixture@example.com',
      ], root);
      await runProcess('git', ['config', 'user.name', 'Fixture'], root);
      await runProcess('git', ['add', '.'], root);
      await runProcess('git', ['commit', '-m', 'Initial package repo'], root);
      await File('${root.path}/LOCAL_NOTES.md').writeAsString('local notes\n');

      final report = await runPreflight(root, fluohCommand: fluoh.path);
      final upgradeChecks = report['upgradeChecks'] as Map<String, Object?>;
      final packageDocs = upgradeChecks['packageDocs'] as Map<String, Object?>;

      expect(packageDocs['needsRefresh'], isTrue);
      expect(
        packageDocs['allowDirtyRefreshCommand'],
        'fluoh package docs refresh --allow-dirty',
      );
      expect(
        stringList(upgradeChecks['commands']),
        containsAll([
          'fluoh package docs refresh --dry-run',
          'fluoh package docs refresh --allow-dirty',
        ]),
      );
      expect(
        stringList(upgradeChecks['commands']),
        isNot(contains('fluoh package docs refresh')),
      );
      expect(
        stringList(upgradeChecks['notes']),
        contains(
          contains('The worktree is dirty, so use the explicit --allow-dirty'),
        ),
      );
    },
    skip: Platform.isWindows ? 'uses POSIX test executables' : false,
  );

  test(
    'preflight upgrades before refreshing newer-template package docs',
    () async {
      final root = await createTempRoot();
      addTearDown(() => root.delete(recursive: true));
      final fluoh = await writeFakeFluoh(
        root,
        docsDryRunOutput: '''
Package docs would be refreshed
    - README.md
    - FLUOH.md
    - AGENTS.md
''',
      );

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
      await File('${root.path}/FLUOH.md').writeAsString('''
<!-- fluoh:generated:start id=package-implementation-guide template=2 -->
Generated content.
<!-- fluoh:generated:end id=package-implementation-guide -->
''');
      await File('${root.path}/AGENTS.md').writeAsString('''
<!-- fluoh:generated:start id=package-agents-instructions template=2 -->
Generated content.
<!-- fluoh:generated:end id=package-agents-instructions -->
''');
      await File('${root.path}/README.md').writeAsString('''
<!-- fluoh:generated:start id=package-readme-adaptation template=2 -->
Generated content.
<!-- fluoh:generated:end id=package-readme-adaptation -->
''');

      final report = await runPreflight(root, fluohCommand: fluoh.path);
      final upgradeChecks = report['upgradeChecks'] as Map<String, Object?>;
      final packageDocs = upgradeChecks['packageDocs'] as Map<String, Object?>;

      expect(packageDocs['hasNewerTemplate'], isTrue);
      expect(packageDocs['needsRefresh'], isFalse);
      expect(stringList(upgradeChecks['commands']), ['fluoh upgrade']);
      expect(stringList(report['suggestedCommands']).take(3).toList(), [
        'fluoh upgrade',
        'fluoh deps get',
        'fluoh verify --package camera --json --trace-dir .fluoh/traces/camera/adaptation',
      ]);
    },
    skip: Platform.isWindows ? 'uses POSIX test executables' : false,
  );

  test(
    'preflight reports unknown package docs state when dry-run fails',
    () async {
      final root = await createTempRoot();
      addTearDown(() => root.delete(recursive: true));
      final fluoh = await writeFakeFluoh(
        root,
        docsDryRunOutput: 'dry-run failed',
        docsDryRunExitCode: 64,
      );

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
      await File('${root.path}/FLUOH.md').writeAsString('''
<!-- fluoh:generated:start id=package-implementation-guide template=2 -->
Generated content.
<!-- fluoh:generated:end id=package-implementation-guide -->
''');
      await File('${root.path}/AGENTS.md').writeAsString('''
<!-- fluoh:generated:start id=package-agents-instructions template=1 -->
Generated content.
<!-- fluoh:generated:end id=package-agents-instructions -->
''');
      await File('${root.path}/README.md').writeAsString('''
<!-- fluoh:generated:start id=package-readme-adaptation template=1 -->
Generated content.
<!-- fluoh:generated:end id=package-readme-adaptation -->
''');

      final report = await runPreflight(root, fluohCommand: fluoh.path);
      final upgradeChecks = report['upgradeChecks'] as Map<String, Object?>;
      final packageDocs = upgradeChecks['packageDocs'] as Map<String, Object?>;
      final dryRun = packageDocs['dryRun'] as Map<String, Object?>;

      expect(packageDocs['needsRefresh'], isFalse);
      expect(packageDocs['needsRefreshUnknown'], isTrue);
      expect(dryRun['ok'], isFalse);
      expect(
        stringList(upgradeChecks['commands']),
        contains('fluoh package docs refresh --dry-run'),
      );
      expect(
        stringList(upgradeChecks['notes']),
        contains(contains('dry-run did not complete')),
      );
    },
    skip: Platform.isWindows ? 'uses POSIX test executables' : false,
  );

  test(
    'preflight reports the current package branch',
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
  name: share_plus
  path: packages/share_plus/share_plus
  release:
    version: "0.1.0"
    upstream:
      version: "9.0.0"
      commit: "1111111111111111111111111111111111111111"
''');
      await Directory(
        '${root.path}/packages/share_plus/share_plus/example/ios',
      ).create(recursive: true);
      await Directory(
        '${root.path}/packages/share_plus/share_plus/example/macos',
      ).create(recursive: true);
      await Directory(
        '${root.path}/packages/share_plus/share_plus/example/linux',
      ).create(recursive: true);
      await Directory(
        '${root.path}/packages/share_plus/share_plus/example/web',
      ).create(recursive: true);
      await Directory(
        '${root.path}/packages/share_plus/share_plus/example/windows',
      ).create(recursive: true);

      final report = await runPreflight(root, fluohCommand: fluoh.path);
      final project = report['project'] as Map<String, Object?>;
      final packages = project['packages'] as List<Object?>;
      final sharePlus = packages.cast<Map<String, Object?>>().singleWhere(
        (package) => package['name'] == 'share_plus',
      );
      final sharePlusPlatforms =
          sharePlus['examplePlatforms'] as Map<String, Object?>;

      expect(project['kind'], 'package-repository');
      expect(project['hasPackageBranch'], isTrue);
      expect(project['packageNames'], ['share_plus']);
      expect(project['selectedPackage'], 'share_plus');
      expect(sharePlusPlatforms['ios'], isTrue);
      expect(sharePlusPlatforms['macos'], isTrue);
      expect(sharePlusPlatforms['linux'], isTrue);
      expect(sharePlusPlatforms['web'], isTrue);
      expect(sharePlusPlatforms['windows'], isTrue);
      const sharePlusTraceDir = '.fluoh/traces/share_plus/adaptation';
      final packageSuggestedCommands = [
        'fluoh verify --package share_plus --json --trace-dir $sharePlusTraceDir',
        'fluoh run ohos --package share_plus --auto-emulator --json --trace-dir $sharePlusTraceDir',
        if (Platform.isLinux)
          'fluoh build linux --package share_plus --json --trace-dir $sharePlusTraceDir',
        'fluoh run web --package share_plus --json --trace-dir $sharePlusTraceDir',
        if (Platform.isWindows)
          'fluoh build windows --package share_plus --json --trace-dir $sharePlusTraceDir',
      ];
      expect(
        stringList(report['suggestedCommands']),
        containsAll(packageSuggestedCommands),
      );
      expect(
        stringList(report['finalCheckCommands']),
        contains(
          'fluoh verify --package share_plus --json --trace-dir $sharePlusTraceDir',
        ),
      );
      expect(
        stringList(report['deliveryChecks']),
        contains(contains('.fluoh/reports/share_plus/ai-report-...md')),
      );
      expect(stringList(report['notes']), isEmpty);
      expect(
        report['reportCommand'],
        'python3 <skill-dir>/scripts/new_report.py . --scope share_plus --package share_plus',
      );
    },
    skip: Platform.isWindows ? 'uses POSIX test executables' : false,
  );

  test(
    'preflight validates a requested package against the current branch',
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
  name: share_plus
  path: packages/share_plus/share_plus
  release:
    version: "0.1.0"
    upstream:
      version: "9.0.0"
      commit: "1111111111111111111111111111111111111111"
''');
      await Directory(
        '${root.path}/packages/share_plus/share_plus/example/android',
      ).create(recursive: true);

      final report = await runPreflight(
        root,
        fluohCommand: fluoh.path,
        path: root.path,
      );
      expect(
        (report['project'] as Map<String, Object?>)['hasPackageBranch'],
        isTrue,
      );

      final selectedResult = await Process.run('python3', [
        preflightScript,
        root.path,
        '--fluoh-command',
        fluoh.path,
        '--package',
        'share_plus',
      ]);
      expect(selectedResult.exitCode, 0, reason: selectedResult.stderr);
      final selected =
          jsonDecode(selectedResult.stdout.toString()) as Map<String, Object?>;
      final project = selected['project'] as Map<String, Object?>;

      expect(project['requestedPackage'], 'share_plus');
      expect(project['selectedPackage'], 'share_plus');
      expect(project['packageSelectionValid'], isTrue);
      expect(project['hasPackageBranch'], isTrue);
      expect(stringList(selected['notes']), isEmpty);
      expect(
        stringList(selected['suggestedCommands']),
        containsAll([
          'fluoh verify --package share_plus --json --trace-dir .fluoh/traces/share_plus/adaptation',
          'fluoh run ohos --package share_plus --auto-emulator --json --trace-dir .fluoh/traces/share_plus/adaptation',
          'fluoh package handoff --package share_plus --json',
          'fluoh package check --package share_plus --json',
        ]),
      );
      expect(
        stringList(selected['finalCheckCommands']),
        containsAll([
          'git diff --check',
          'fluoh verify --package share_plus --json --trace-dir .fluoh/traces/share_plus/adaptation',
          'fluoh run ohos --package share_plus --auto-emulator --json --trace-dir .fluoh/traces/share_plus/adaptation',
          'fluoh package status --package share_plus',
          'fluoh package handoff --package share_plus --json',
          'fluoh package check --package share_plus --json',
        ]),
      );
      expect(
        selected['reportCommand'],
        'python3 <skill-dir>/scripts/new_report.py . --scope share_plus --package share_plus',
      );
      expect(
        selected['scenarioCommand'],
        'python3 <skill-dir>/scripts/new_scenario.py . --scope share_plus --package share_plus --platform <platform> --name <scenario-name>',
      );
      expect(
        selected['reportCheckCommand'],
        'python3 <skill-dir>/scripts/check_report.py <report-path>',
      );
      expect(
        selected['sessionInspectCommand'],
        'python3 <skill-dir>/scripts/inspect_session.py <session-file> --wait 30 --expect-platform <platform>',
      );
    },
    skip: Platform.isWindows ? 'uses POSIX test executables' : false,
  );

  test(
    'preflight reports an invalid requested package without guessing',
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

      final selectedResult = await Process.run('python3', [
        preflightScript,
        root.path,
        '--fluoh-command',
        fluoh.path,
        '--package',
        'share_plus',
      ]);
      expect(selectedResult.exitCode, 0, reason: selectedResult.stderr);
      final selected =
          jsonDecode(selectedResult.stdout.toString()) as Map<String, Object?>;
      final project = selected['project'] as Map<String, Object?>;

      expect(project['requestedPackage'], 'share_plus');
      expect(project['selectedPackage'], isNull);
      expect(project['packageSelectionValid'], isFalse);
      expect(stringList(selected['notes']).single, contains('current package'));
      expect(stringList(selected['notes']).single, contains('camera'));
      expect(
        stringList(selected['suggestedCommands']),
        contains(
          'fluoh verify --package <name> --json --trace-dir .fluoh/traces/<name>/adaptation',
        ),
      );
      expect(
        stringList(selected['deliveryChecks']),
        contains(contains('.fluoh/reports/<name>/ai-report-...md')),
      );
    },
    skip: Platform.isWindows ? 'uses POSIX test executables' : false,
  );

  test(
    'preflight reports unknown and missing paths without writing',
    () async {
      final root = await createTempRoot();
      addTearDown(() => root.delete(recursive: true));
      final fluoh = await writeFakeFluoh(root);
      final emptyProject = Directory('${root.path}/empty')..createSync();

      final unknown = await runPreflight(
        root,
        fluohCommand: fluoh.path,
        path: emptyProject.path,
      );
      final unknownProject = unknown['project'] as Map<String, Object?>;
      expect(unknownProject['kind'], 'unknown');
      expect(stringList(unknown['notes']).single, contains('No Flutter app'));
      expect(await emptyProject.list().isEmpty, isTrue);

      final missingPath = '${root.path}/does_not_exist';
      final missing = await runPreflight(
        root,
        fluohCommand: fluoh.path,
        path: missingPath,
      );
      expect(missing['pathExists'], isFalse);
      expect((missing['fluoh'] as Map<String, Object?>)['ok'], isTrue);
      expect((missing['project'] as Map<String, Object?>)['kind'], 'unknown');
      expect(stringList(missing['notes']).single, contains('does not exist'));
      expect(stringList(missing['finalCheckCommands']), isEmpty);
      expect(
        stringList(missing['deliveryChecks']),
        contains(
          'Choose a Flutter app project or FlutterOH package repository before editing.',
        ),
      );

      final filePath = File('${root.path}/not_a_directory')
        ..writeAsStringSync('not a project');
      final fileResult = await runPreflight(
        root,
        fluohCommand: fluoh.path,
        path: filePath.path,
      );
      expect(fileResult['pathExists'], isTrue);
      expect(fileResult['pathIsDirectory'], isFalse);
      expect(
        stringList(fileResult['notes']).single,
        contains('not a directory'),
      );
    },
    skip: Platform.isWindows ? 'uses POSIX test executables' : false,
  );

  test(
    'new_report creates report files and never overwrites',
    () async {
      final root = await createTempRoot();
      addTearDown(() => root.delete(recursive: true));
      final outputRoot = Directory('${root.path}/reports');

      await File('${root.path}/fluoh.yaml').writeAsString('''
schema: 1

sdk:
  version: 3.35.8-ohos-0.0.3

package:
  name: camera
  path: packages/camera/camera
''');

      Future<File> createReport() async {
        final result = await Process.run('python3', [
          reportScript,
          root.path,
          '--scope',
          'camera plugin',
          '--package',
          'camera',
          '--upstream-version',
          '0.11.0',
          '--recommendation',
          'ready',
          '--output-root',
          outputRoot.path,
        ]);
        expect(result.exitCode, 0, reason: result.stderr.toString());
        return File(result.stdout.toString().trim());
      }

      final first = await createReport();
      final second = await createReport();
      final defaultResult = await Process.run('python3', [
        reportScript,
        root.path,
        '--scope',
        'camera plugin',
        '--package',
        'camera',
      ]);
      expect(
        defaultResult.exitCode,
        0,
        reason: defaultResult.stderr.toString(),
      );
      final defaultReport = File(defaultResult.stdout.toString().trim());
      final firstZh = File(
        first.path.replaceFirst(RegExp(r'\.md$'), '.zh-CN.md'),
      );
      final secondZh = File(
        second.path.replaceFirst(RegExp(r'\.md$'), '.zh-CN.md'),
      );
      final defaultReportZh = File(
        defaultReport.path.replaceFirst(RegExp(r'\.md$'), '.zh-CN.md'),
      );

      expect(first.path, isNot(second.path));
      expect(first.existsSync(), isTrue);
      expect(second.existsSync(), isTrue);
      expect(defaultReport.existsSync(), isTrue);
      expect(firstZh.existsSync(), isTrue);
      expect(secondZh.existsSync(), isTrue);
      expect(defaultReportZh.existsSync(), isTrue);
      expect(
        defaultReport.path,
        contains('${root.path}/.fluoh/reports/camera/ai-report-'),
      );
      expect(
        first.uri.pathSegments.last,
        matches(RegExp(r'^ai-report-\d{8}-\d{6}(?:-\d+)?\.md$')),
      );
      expect(first.uri.pathSegments.last, isNot(contains('camera-plugin')));
      final content = await first.readAsString();
      expect(content, contains('- Scope: camera plugin'));
      expect(content, contains('- Package: camera'));
      expect(content, contains('- Upstream version: 0.11.0'));
      expect(content, contains('- FlutterOH SDK: 3.35.8-ohos-0.0.3'));
      expect(content, contains('- Recommendation: ready'));
      expect(content, contains('## Delivery Checklist'));
      expect(content, contains('## Interaction Evidence'));
      expect(content, contains('## Fluoh Feedback'));
      expect(content, contains('Diff reviewed'));
      expect(content, contains('OHOS build evidence recorded'));
      expect(content, contains('Functional interaction evidence recorded'));
      expect(content, contains('Release recommendation: ready'));
      final zhContent = await firstZh.readAsString();
      expect(zhContent, contains('# fluoh AI 适配报告'));
      expect(zhContent, contains('- Scope: camera plugin'));
      expect(zhContent, contains('- Package: camera'));
      expect(zhContent, contains('## Adaptation Responsibility / 适配责任边界'));
      expect(zhContent, contains('Release recommendation: ready'));
    },
    skip: Platform.isWindows ? 'uses POSIX test executables' : false,
  );

  test(
    'new_summary creates monorepo summary reports and never overwrites',
    () async {
      final root = await createTempRoot();
      addTearDown(() => root.delete(recursive: true));
      await File('${root.path}/fluoh.yaml').writeAsString('''
schema: 1

sdk:
  version: 3.35.8-ohos-0.0.3
''');
      final cameraReportDirectory = Directory(
        '${root.path}/.fluoh/reports/camera',
      );
      await cameraReportDirectory.create(recursive: true);
      await File(
        '${cameraReportDirectory.path}/ai-report-camera-20260525-153045.md',
      ).writeAsString('old report name');
      await File(
        '${cameraReportDirectory.path}/ai-report-20260526-153045.md',
      ).writeAsString('new report name');

      Future<File> createSummary() async {
        final result = await Process.run('python3', [
          summaryScript,
          root.path,
          '--scope',
          'flutter packages',
          '--package',
          'camera',
          '--package',
          'share_plus',
        ]);
        expect(result.exitCode, 0, reason: result.stderr.toString());
        return File(result.stdout.toString().trim());
      }

      final first = await createSummary();
      final second = await createSummary();

      expect(first.path, isNot(second.path));
      expect(first.existsSync(), isTrue);
      expect(second.existsSync(), isTrue);
      expect(
        first.path,
        contains('${root.path}/.fluoh/reports/flutter-packages/summary-'),
      );
      expect(
        first.uri.pathSegments.last,
        matches(RegExp(r'^summary-\d{8}-\d{6}(?:-\d+)?\.md$')),
      );
      final content = await first.readAsString();
      expect(content, contains('# fluoh Monorepo Summary'));
      expect(content, contains('- Scope: flutter packages'));
      expect(content, contains('- Packages: camera, share_plus'));
      expect(content, contains('| camera |'));
      expect(
        content,
        contains('.fluoh/reports/camera/ai-report-20260526-153045.md'),
      );
      expect(content, isNot(contains('ai-report-camera-20260525-153045.md')));
      expect(content, contains('| share_plus |'));
      expect(content, contains('## Package Matrix'));
      expect(content, contains('## Fluoh Feedback'));
      expect(content, contains('Keep the latest upstream target'));
    },
    skip: Platform.isWindows ? 'uses POSIX test executables' : false,
  );
}
