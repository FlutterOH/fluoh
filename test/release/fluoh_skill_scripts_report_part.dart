part of 'fluoh_skill_scripts_test.dart';

void _registerFluohSkillScriptsReportTests() {
  test(
    'preflight reports schema blockers before support',
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
      expect(upgradeChecks['blocksEditing'], isTrue);
      expect(
        stringList(upgradeChecks['notes']),
        contains(contains('current canonical schema')),
      );
      expect(
        stringList(report['deliveryChecks']),
        contains(contains('upgradeChecks has no schema blocker')),
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

repository:
  git:
    url: https://github.com/FlutterOH/share_plus.git
    branch: ohos/3.35/share_plus

origin:
  kind: ported

upstream:
  git:
    url: https://github.com/fluttercommunity/plus_plugins.git
    branch: main

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
      final packageSuggestedCommands = [
        'fluoh package next --package share_plus --json',
        'fluoh package status --package share_plus --json',
        'fluoh package handoff --package share_plus --json',
        'fluoh package check --package share_plus --report <report-path> --json',
      ];
      expect(
        stringList(report['suggestedCommands']),
        containsAllInOrder(packageSuggestedCommands),
      );
      expect(
        stringList(report['finalCheckCommands']),
        contains('fluoh package next --package share_plus --json'),
      );
      expect(
        stringList(report['finalCheckCommands']),
        contains('fluoh verify --package share_plus --json --trace'),
      );
      expect(
        stringList(report['finalCheckCommands']),
        contains('fluoh drive ohos --package share_plus --json --trace'),
      );
      if (Platform.isMacOS) {
        expect(
          stringList(report['finalCheckCommands']),
          contains('fluoh drive ios --package share_plus --json --trace'),
        );
      }
      expect(
        stringList(report['deliveryChecks']),
        contains(contains('current task report')),
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

repository:
  git:
    url: https://github.com/FlutterOH/share_plus.git
    branch: ohos/3.35/share_plus

origin:
  kind: ported

upstream:
  git:
    url: https://github.com/fluttercommunity/plus_plugins.git
    branch: main

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
        containsAllInOrder([
          'fluoh package next --package share_plus --json',
          'fluoh package status --package share_plus --json',
          'fluoh package handoff --package share_plus --json',
          'fluoh package check --package share_plus --report <report-path> --json',
        ]),
      );
      expect(
        stringList(selected['finalCheckCommands']),
        containsAllInOrder([
          'git diff --check',
          'fluoh package next --package share_plus --json',
          'fluoh verify --package share_plus --json --trace',
          'fluoh run ohos --package share_plus --auto-emulator --json --trace',
          'fluoh drive ohos --package share_plus --json --trace',
          'fluoh doctor --platform android --json --strict',
          'fluoh run android --package share_plus --auto-emulator --json --trace',
          'fluoh drive android --package share_plus --json --trace',
          'fluoh package status --package share_plus --json',
          'python3 <skill-dir>/scripts/check_report.py <report-path>',
          'fluoh package handoff --package share_plus --json',
          'fluoh package check --package share_plus --report <report-path> --json',
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

repository:
  git:
    url: https://github.com/FlutterOH/camera.git
    branch: ohos/3.35/camera

origin:
  kind: ported

upstream:
  git:
    url: https://github.com/flutter/packages.git
    branch: main

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
        contains('fluoh package next --package <name> --json'),
      );
      expect(
        stringList(selected['deliveryChecks']),
        contains(contains('current task report')),
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
    'new_report creates a canonical timestamped report',
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

      final report = await createReport();
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

      expect(report.existsSync(), isTrue);
      expect(defaultReport.existsSync(), isTrue);
      expect(
        File(
          report.path.replaceFirst(RegExp(r'\.md$'), '.zh-CN.md'),
        ).existsSync(),
        isFalse,
      );
      expect(
        File(
          defaultReport.path.replaceFirst(RegExp(r'\.md$'), '.zh-CN.md'),
        ).existsSync(),
        isFalse,
      );
      expect(
        defaultReport.path,
        allOf(contains('/.fluoh/tasks/'), contains('/reports/report-')),
      );
      expect(
        report.uri.pathSegments.last,
        matches(RegExp(r'^report-\d+\.md$')),
      );
      expect(report.uri.pathSegments.last, isNot(contains('camera-plugin')));
      final content = await report.readAsString();
      expect(content, contains('- Scope: camera plugin'));
      expect(content, contains('- Package: camera'));
      expect(content, contains('- Upstream version: 0.11.0'));
      expect(content, contains('- FlutterOH SDK: 3.35.8-ohos-0.0.3'));
      expect(content, contains('- Recommendation: ready'));
      expect(content, contains('## Delivery Checklist'));
      expect(content, contains('## Interaction Evidence'));
      expect(content, contains('## Fluoh Feedback'));
      expect(content, contains('Diff reviewed'));
      expect(content, contains('Target-platform build evidence recorded'));
      expect(content, contains('Functional interaction evidence recorded'));
      expect(content, contains('Release recommendation: ready'));
    },
    skip: Platform.isWindows ? 'uses POSIX test executables' : false,
  );

  test(
    'new_summary creates a canonical timestamped monorepo summary',
    () async {
      final root = await createTempRoot();
      addTearDown(() => root.delete(recursive: true));
      await File('${root.path}/fluoh.yaml').writeAsString('''
schema: 1

sdk:
  version: 3.35.8-ohos-0.0.3
''');
      final cameraReportDirectory = Directory(
        '${root.path}/.fluoh/tasks/camera-support/reports',
      );
      await cameraReportDirectory.create(recursive: true);
      await File(
        '${cameraReportDirectory.path}/report-1781092800122.md',
      ).writeAsString('old report name');
      await File(
        '${cameraReportDirectory.path}/report-1781092800123.md',
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

      final summary = await createSummary();

      expect(summary.existsSync(), isTrue);
      expect(
        summary.path,
        allOf(contains('/.fluoh/tasks/'), contains('/reports/summary-')),
      );
      expect(
        summary.uri.pathSegments.last,
        matches(RegExp(r'^summary-\d+\.md$')),
      );
      final content = await summary.readAsString();
      expect(content, contains('# fluoh Monorepo Summary'));
      expect(content, contains('- Scope: flutter packages'));
      expect(content, contains('- Packages: camera, share_plus'));
      expect(content, contains('| camera |'));
      expect(content, contains('| camera | <branch> |'));
      expect(content, contains('| share_plus | <branch> |'));
      expect(content, contains('| <report> |'));
      expect(content, isNot(contains('report-1781092800122.md')));
      expect(content, contains('| share_plus |'));
      expect(content, contains('## Package Matrix'));
      expect(content, contains('## Fluoh Feedback'));
      expect(content, contains('Keep the latest upstream target'));
    },
    skip: Platform.isWindows ? 'uses POSIX test executables' : false,
  );
}
