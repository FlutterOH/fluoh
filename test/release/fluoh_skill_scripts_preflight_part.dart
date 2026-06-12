part of 'fluoh_skill_scripts_test.dart';

void _registerFluohSkillScriptsPreflightTests() {
  test(
    'preflight recognizes an app project and suggests the app flow',
    () async {
      final root = await createTempRoot();
      addTearDown(() => root.delete(recursive: true));
      final fluoh = await writeFakeFluoh(root);

      await File('${root.path}/pubspec.yaml').writeAsString('''
name: example_app
dependencies:
  flutter:
    sdk: flutter
''');
      await File('${root.path}/fluoh.yaml').writeAsString('''
schema: 1

sdk:
  version: 3.35.8-ohos-0.0.3
''');
      await Directory('${root.path}/ohos').create();
      await Directory('${root.path}/android').create();
      await Directory('${root.path}/linux').create();
      await Directory('${root.path}/web').create();
      await Directory('${root.path}/windows').create();

      final report = await runPreflight(root, fluohCommand: fluoh.path);
      final project = report['project'] as Map<String, Object?>;
      final fluohResult = report['fluoh'] as Map<String, Object?>;
      final platforms = project['platformDirectories'] as Map<String, Object?>;
      final upgradeChecks = report['upgradeChecks'] as Map<String, Object?>;
      final schema = upgradeChecks['schema'] as Map<String, Object?>;

      expect(project['kind'], 'app-project');
      expect(project['name'], 'example_app');
      expect(project['isFlutter'], isTrue);
      expect(project['isFlutterPlugin'], isFalse);
      expect(project['sdkVersion'], '3.35.8-ohos-0.0.3');
      expect(project['hasPackageBranch'], isFalse);
      expect(platforms['ohos'], isTrue);
      expect(platforms['android'], isTrue);
      expect(platforms['linux'], isTrue);
      expect(platforms['web'], isTrue);
      expect(platforms['windows'], isTrue);
      expect(fluohResult['ok'], isTrue);
      expect(fluohResult['stdout'], 'fluoh 9.9.9');
      expect(schema['status'], 'current');
      expect(upgradeChecks['needsMigration'], isFalse);
      expect(
        report['adaptPlanCommand'],
        'fluoh plan app --sdk 3.35.8-ohos-0.0.3 --json',
      );
      const appTraceDir = '.fluoh/traces/example_app/adaptation';
      final appRegressionCommands = [
        'fluoh doctor --platform android --json --strict',
        'fluoh run android --auto-emulator --json --trace-dir $appTraceDir',
        if (Platform.isLinux) ...[
          'fluoh doctor --platform linux --json --strict',
          'fluoh build linux --json --trace-dir $appTraceDir',
        ],
        'fluoh doctor --platform web --json --strict',
        'fluoh run web --json --trace-dir $appTraceDir',
        if (Platform.isWindows) ...[
          'fluoh doctor --platform windows --json --strict',
          'fluoh build windows --json --trace-dir $appTraceDir',
        ],
      ];
      expect(stringList(report['suggestedCommands']), [
        'fluoh source update',
        'fluoh sdk use 3.35.8-ohos-0.0.3 --pub-get',
        'fluoh deps check --json',
        'fluoh deps fix --dry-run',
        'fluoh deps fix',
        'fluoh deps get',
        'fluoh doctor --platform ohos --project --json --strict',
        'fluoh build ohos --auto-sign --json --trace-dir $appTraceDir',
        'fluoh devices --platform ohos --json',
        'fluoh emulators --platform ohos --json',
        'fluoh run ohos --auto-emulator --json --trace-dir $appTraceDir',
        'fluoh drive ohos --json --trace-dir $appTraceDir',
        'fluoh drive android --json --trace-dir $appTraceDir',
        ...appRegressionCommands,
        'fluoh report create --scope example_app --trace-dir $appTraceDir --json',
      ]);
      final commandQueue = (report['commandQueue'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(
        commandQueue.map((item) => item['command']).toList(),
        stringList(report['suggestedCommands']),
      );
      expect(
        commandQueue,
        contains(
          allOf(
            containsPair('phase', 'setup'),
            containsPair('command', 'fluoh source update'),
            containsPair('mutating', isTrue),
            containsPair('requiresApproval', isTrue),
            containsPair('expectedEvidence', 'source update result'),
          ),
        ),
      );
      expect(
        commandQueue,
        contains(
          allOf(
            containsPair('phase', 'automation'),
            containsPair('mutating', isTrue),
            containsPair(
              'expectedEvidence',
              contains('automation coverage policy'),
            ),
          ),
        ),
      );
      expect(
        commandQueue,
        contains(
          allOf(
            containsPair('phase', 'report'),
            containsPair('mutating', isTrue),
            containsPair('expectedEvidence', 'local AI report path'),
          ),
        ),
      );
      expect(stringList(report['finalCheckCommands']), [
        'git diff --check',
        'fluoh doctor --platform ohos --project --json --strict',
        'fluoh build ohos --auto-sign --json --trace-dir $appTraceDir',
        'fluoh devices --platform ohos --json',
        'fluoh emulators --platform ohos --json',
        'fluoh run ohos --auto-emulator --json --trace-dir $appTraceDir',
        'fluoh drive ohos --json --trace-dir $appTraceDir',
        'fluoh drive android --json --trace-dir $appTraceDir',
        ...appRegressionCommands,
      ]);
      final automationRunbook =
          report['automationRunbook'] as Map<String, Object?>;
      expect(automationRunbook['mode'], 'autonomous-to-delivery');
      expect(automationRunbook['loop'], contains('run, parse, fix, rerun'));
      final deliveryGate = report['deliveryGate'] as Map<String, Object?>;
      expect(deliveryGate['status'], 'active');
      expect(deliveryGate['requiresReportCheckPass'], isTrue);
      expect(
        deliveryGate['reportCheckCommand'],
        'python3 <skill-dir>/scripts/check_report.py <report-path>',
      );
      expect(
        stringList(deliveryGate['readyRequires']),
        contains(contains('reportCheckCommand passes')),
      );
      expect(
        stringList(report['deliveryChecks']),
        containsAll([
          contains('.fluoh/reports/example_app/report-<timestamp>.md'),
          contains('Record deps, doctor, build, and run command results'),
          contains('State ready, blocked, or needs maintainer decision'),
        ]),
      );
      expect(
        report['reportCommand'],
        'python3 <skill-dir>/scripts/new_report.py . --scope example_app',
      );
      expect(
        report['summaryCommand'],
        'python3 <skill-dir>/scripts/new_summary.py . --scope example_app',
      );
      expect(
        report['scenarioCommand'],
        'python3 <skill-dir>/scripts/new_scenario.py . --scope example_app --app --platform <platform> --name <scenario-name>',
      );
      expect(
        report['reportCheckCommand'],
        'python3 <skill-dir>/scripts/check_report.py <report-path>',
      );
      expect(
        report['feedbackCommand'],
        'python3 <skill-dir>/scripts/collect_feedback.py <trace-dir-or-manifest>',
      );
      expect(
        report['sessionInspectCommand'],
        'python3 <skill-dir>/scripts/inspect_session.py <session-file> --wait 30 --expect-platform <platform>',
      );
      expect(
        report['sessionAttachCommand'],
        'fluoh attach <platform> --session-file <session-file>',
      );
      expect(
        report['sessionAttachCommand'],
        'fluoh attach <platform> --session-file <session-file>',
      );
    },
    skip: Platform.isWindows ? 'uses POSIX test executables' : false,
  );

  test(
    'preflight accepts a multi-word fluoh command',
    () async {
      final root = await createTempRoot();
      addTearDown(() => root.delete(recursive: true));
      final dartRunner = await writeFakeDartRunner(root);

      await File('${root.path}/pubspec.yaml').writeAsString('''
name: local_cli_app
dependencies:
  flutter:
    sdk: flutter
''');

      final report = await runPreflight(
        root,
        fluohCommand: '${dartRunner.path} run bin/fluoh.dart',
      );
      final fluohResult = report['fluoh'] as Map<String, Object?>;

      expect(fluohResult['ok'], isTrue);
      expect(fluohResult['stdout'], 'fluoh 8.8.8');
    },
    skip: Platform.isWindows ? 'uses POSIX test executables' : false,
  );

  test(
    'preflight runs a local Dart fluoh entry through dart',
    () async {
      final root = await createTempRoot();
      addTearDown(() => root.delete(recursive: true));
      final localFluoh = File('${root.path}/fluoh.dart');
      await localFluoh.writeAsString('void main() {}\n');
      final dart = await writeFakeDartExecutable(
        root,
        scriptPath: localFluoh.path,
        extraArgs: const ['--checked-entry'],
      );

      await File('${root.path}/pubspec.yaml').writeAsString('''
name: local_cli_app
dependencies:
  flutter:
    sdk: flutter
''');

      final report = await runPreflight(
        root,
        fluohCommand: '${localFluoh.path} --checked-entry',
        environment: {
          'PATH': '${dart.parent.path}:${Platform.environment['PATH'] ?? ''}',
        },
      );
      final fluohResult = report['fluoh'] as Map<String, Object?>;

      expect(fluohResult['ok'], isTrue);
      expect(fluohResult['stdout'], 'fluoh 7.7.7');
    },
    skip: Platform.isWindows ? 'uses POSIX test executables' : false,
  );

  test(
    'preflight bypasses Flutter dart wrapper for local Dart fluoh entries',
    () async {
      final root = await createTempRoot();
      addTearDown(() => root.delete(recursive: true));
      final localFluoh = File('${root.path}/fluoh.dart');
      await localFluoh.writeAsString('void main() {}\n');
      final wrapper = await writeFakeFlutterDartWrapper(
        root,
        scriptPath: localFluoh.path,
      );

      await File('${root.path}/pubspec.yaml').writeAsString('''
name: local_cli_app
dependencies:
  flutter:
    sdk: flutter
''');

      final report = await runPreflight(
        root,
        fluohCommand: 'dart ${localFluoh.path}',
        environment: {
          'PATH':
              '${wrapper.parent.path}:${Platform.environment['PATH'] ?? ''}',
        },
      );
      final fluohResult = report['fluoh'] as Map<String, Object?>;

      expect(fluohResult['ok'], isTrue);
      expect(fluohResult['stdout'], 'fluoh 6.6.6');
    },
    skip: Platform.isWindows ? 'uses POSIX test executables' : false,
  );

  test(
    'preflight quotes helper command scope values when needed',
    () async {
      final root = await createTempRoot();
      addTearDown(() => root.delete(recursive: true));
      final fluoh = await writeFakeFluoh(root);

      await File('${root.path}/pubspec.yaml').writeAsString('''
name: "Example App"
dependencies:
  flutter:
    sdk: flutter
''');

      final report = await runPreflight(root, fluohCommand: fluoh.path);
      final project = report['project'] as Map<String, Object?>;

      expect(project['kind'], 'app-project');
      expect(project['name'], 'Example App');
      expect(
        stringList(report['deliveryChecks']),
        contains(contains('.fluoh/reports/Example-App/report-<timestamp>.md')),
      );
      expect(
        report['reportCommand'],
        "python3 <skill-dir>/scripts/new_report.py . --scope 'Example App'",
      );
      expect(
        report['scenarioCommand'],
        "python3 <skill-dir>/scripts/new_scenario.py . --scope 'Example App' --app --platform <platform> --name <scenario-name>",
      );
    },
    skip: Platform.isWindows ? 'uses POSIX test executables' : false,
  );

  test(
    'preflight keeps going before fluoh is installed or an SDK is selected',
    () async {
      final root = await createTempRoot();
      addTearDown(() => root.delete(recursive: true));

      await File('${root.path}/pubspec.yaml').writeAsString('''
name: onboarding_app
dependencies:
  flutter:
    sdk: flutter
''');

      final report = await runPreflight(
        root,
        fluohCommand: '${root.path}/missing-fluoh',
      );
      final project = report['project'] as Map<String, Object?>;
      final fluohResult = report['fluoh'] as Map<String, Object?>;

      expect(project['kind'], 'app-project');
      expect(project['name'], 'onboarding_app');
      expect(project['sdkVersion'], isNull);
      expect(fluohResult['ok'], isFalse);
      expect(report['adaptPlanCommand'], 'fluoh plan app --json');
      expect(
        stringList(report['suggestedCommands']),
        containsAll([
          'fluoh sdk use <sdk-version-or-line> --pub-get',
          'fluoh deps check --json',
          'fluoh deps fix',
        ]),
      );
      expect(
        report['reportCommand'],
        'python3 <skill-dir>/scripts/new_report.py . --scope onboarding_app',
      );
    },
    skip: Platform.isWindows ? 'uses POSIX test executables' : false,
  );

  test(
    'preflight does not route ordinary Dart packages through the app flow',
    () async {
      final root = await createTempRoot();
      addTearDown(() => root.delete(recursive: true));
      final fluoh = await writeFakeFluoh(root);

      await File('${root.path}/pubspec.yaml').writeAsString('''
name: dart_tooling_package
dependencies:
  args: ^2.7.0
''');

      final report = await runPreflight(root, fluohCommand: fluoh.path);
      final project = report['project'] as Map<String, Object?>;

      expect(project['kind'], 'dart-package');
      expect(project['isFlutter'], isFalse);
      expect(report['adaptPlanCommand'], isNull);
      expect(
        stringList(report['suggestedCommands']).single,
        contains('not a Flutter app or FlutterOH package repository'),
      );
      expect(stringList(report['finalCheckCommands']), isEmpty);
      expect(
        stringList(report['notes']).single,
        contains('does not look like a Flutter app'),
      );
    },
    skip: Platform.isWindows ? 'uses POSIX test executables' : false,
  );

  test(
    'preflight accepts FLUOH_BIN for the fluoh executable',
    () async {
      final root = await createTempRoot();
      addTearDown(() => root.delete(recursive: true));
      final fluoh = await writeFakeFluoh(root);

      final result = await Process.run(
        'python3',
        [preflightScript, root.path],
        environment: {'FLUOH_BIN': fluoh.path},
      );
      expect(result.exitCode, 0, reason: result.stderr.toString());

      final report =
          jsonDecode(result.stdout.toString()) as Map<String, Object?>;
      final fluohResult = report['fluoh'] as Map<String, Object?>;
      expect(fluohResult['ok'], isTrue);
      expect(fluohResult['stdout'], 'fluoh 9.9.9');
    },
    skip: Platform.isWindows ? 'uses POSIX test executables' : false,
  );

  test(
    'preflight routes upstream Flutter packages to package repository setup',
    () async {
      final root = await createTempRoot();
      addTearDown(() => root.delete(recursive: true));
      final fluoh = await writeFakeFluoh(root);

      await File('${root.path}/pubspec.yaml').writeAsString('''
name: camera
version: 0.11.0
dependencies:
  flutter:
    sdk: flutter
flutter:
  plugin:
    platforms:
      android:
        package: io.flutter.plugins.camera
''');
      await Directory('${root.path}/example').create();
      await File('${root.path}/example/pubspec.yaml').writeAsString('''
name: camera_example
dependencies:
  flutter:
    sdk: flutter
''');

      final report = await runPreflight(root, fluohCommand: fluoh.path);
      final project = report['project'] as Map<String, Object?>;

      expect(project['kind'], 'flutter-package');
      expect(project['isFlutter'], isTrue);
      expect(project['isFlutterPlugin'], isTrue);
      expect(project['hasExample'], isTrue);
      expect(
        stringList(report['suggestedCommands']).first,
        allOf([
          contains('Resolve package setup'),
          contains('repository-name=camera'),
          contains('output=../camera_ohos'),
          contains('repository=<flutteroh-repo-url-or-path>'),
          contains('git-author-name=<name>'),
          contains('git-author-email=<email>'),
          contains('sdk=<sdk-version-or-line>'),
        ]),
      );
      expect(
        stringList(report['suggestedCommands'])[1],
        allOf([
          contains('fluoh package create'),
          contains('--plan --json'),
          contains('--repository-name camera'),
          contains('--repository <flutteroh-repo-url-or-path>'),
          contains('--git-author-name <name>'),
          contains('--git-author-email <email>'),
          contains('--sdk <sdk-version-or-line>'),
          contains('--package-path .'),
          contains('--output ../camera_ohos'),
        ]),
      );
      expect(
        stringList(report['suggestedCommands'])[2],
        allOf([
          contains('fluoh package create'),
          isNot(contains('--plan')),
          contains('--repository-name camera'),
          contains('--repository <flutteroh-repo-url-or-path>'),
          contains('--git-author-name <name>'),
          contains('--git-author-email <email>'),
          contains('--sdk <sdk-version-or-line>'),
          contains('--package-path .'),
          contains('--output ../camera_ohos'),
        ]),
      );
      expect(
        stringList(report['suggestedCommands']),
        contains(
          'fluoh verify --package camera --json --trace-dir .fluoh/traces/camera/adaptation',
        ),
      );
      expect(stringList(report['finalCheckCommands']), isEmpty);
      expect(
        stringList(report['deliveryChecks']),
        containsAll([
          contains('Create a FlutterOH package repository'),
          contains('Rerun preflight in ../camera_ohos'),
        ]),
      );
      expect(
        report['reportCommand'],
        'python3 <skill-dir>/scripts/new_report.py ../camera_ohos '
        '--scope camera --package camera',
      );
      expect(
        report['summaryCommand'],
        'python3 <skill-dir>/scripts/new_summary.py ../camera_ohos '
        '--scope camera --package camera',
      );
      expect(
        stringList(report['notes']).single,
        contains('upstream Flutter package'),
      );
    },
    skip: Platform.isWindows ? 'uses POSIX test executables' : false,
  );

  test(
    'preflight recognizes a single-package repository',
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

      final report = await runPreflight(root, fluohCommand: fluoh.path);
      final project = report['project'] as Map<String, Object?>;
      final packages = project['packages'] as List<Object?>;
      final package = packages.single as Map<String, Object?>;
      final examplePlatforms =
          package['examplePlatforms'] as Map<String, Object?>;
      final upgradeChecks = report['upgradeChecks'] as Map<String, Object?>;
      final packageDocs = upgradeChecks['packageDocs'] as Map<String, Object?>;

      expect(project['kind'], 'package-repository');
      expect(project['hasPackageBranch'], isTrue);
      expect(project['packageNames'], ['camera']);
      expect(project['selectedPackage'], 'camera');
      expect(project['sdkVersion'], '3.35.8-ohos-0.0.3');
      expect(package['path'], 'packages/camera/camera');
      expect(examplePlatforms['ohos'], isTrue);
      expect(examplePlatforms['android'], isTrue);
      expect(examplePlatforms['web'], isTrue);
      expect(
        (upgradeChecks['schema'] as Map<String, Object?>)['status'],
        'current',
      );
      expect(upgradeChecks['needsMigration'], isFalse);
      expect(packageDocs['needsRefresh'], isTrue);
      expect(
        report['adaptPlanCommand'],
        'fluoh plan package --package camera --json',
      );
      expect(
        packageDocs['dryRunCommand'],
        'fluoh package docs refresh --dry-run',
      );
      expect(
        stringList(report['suggestedCommands']),
        containsAll([
          'fluoh package docs refresh --dry-run',
          'fluoh package docs refresh',
          'fluoh verify --package camera --json --trace-dir .fluoh/traces/camera/adaptation',
          'fluoh build ohos --package camera --auto-sign --json --trace-dir .fluoh/traces/camera/adaptation',
          'fluoh devices --platform ohos --json',
          'fluoh emulators --platform ohos --json',
          'fluoh run ohos --package camera --auto-emulator --json --trace-dir .fluoh/traces/camera/adaptation',
          'fluoh drive ohos --package camera --json --trace-dir .fluoh/traces/camera/adaptation',
          'fluoh drive android --package camera --json --trace-dir .fluoh/traces/camera/adaptation',
          'fluoh run web --package camera --json --trace-dir .fluoh/traces/camera/adaptation',
          'fluoh package handoff --package camera --json',
          'fluoh package check --package camera --report <report-path> --json',
        ]),
      );
      final commandQueue = (report['commandQueue'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(
        commandQueue,
        contains(
          allOf(
            containsPair('command', 'fluoh package docs refresh --dry-run'),
            containsPair('mutating', isFalse),
            containsPair('requiresApproval', isFalse),
          ),
        ),
      );
      expect(
        commandQueue,
        contains(
          allOf(
            containsPair('command', 'fluoh package docs refresh'),
            containsPair('mutating', isTrue),
            containsPair('requiresApproval', isTrue),
          ),
        ),
      );
      expect(
        stringList(report['finalCheckCommands']),
        containsAll([
          'git diff --check',
          'fluoh verify --package camera --json --trace-dir .fluoh/traces/camera/adaptation',
          'fluoh build ohos --package camera --auto-sign --json --trace-dir .fluoh/traces/camera/adaptation',
          'fluoh devices --platform ohos --json',
          'fluoh emulators --platform ohos --json',
          'fluoh run ohos --package camera --auto-emulator --json --trace-dir .fluoh/traces/camera/adaptation',
          'fluoh drive ohos --package camera --json --trace-dir .fluoh/traces/camera/adaptation',
          'fluoh drive android --package camera --json --trace-dir .fluoh/traces/camera/adaptation',
          'fluoh package status --package camera',
          'fluoh package handoff --package camera --json',
          'fluoh package check --package camera --report <report-path> --json',
        ]),
      );
      final deliveryGate = report['deliveryGate'] as Map<String, Object?>;
      expect(deliveryGate['status'], 'active');
      expect(
        stringList(deliveryGate['finalCheckCommands']),
        contains(
          'fluoh drive ohos --package camera --json --trace-dir .fluoh/traces/camera/adaptation',
        ),
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
        stringList(report['deliveryChecks']),
        containsAll([
          contains('.fluoh/reports/camera/report-<timestamp>.md'),
          contains('Record verify, status, and package check results'),
          contains('Review public API compatibility'),
        ]),
      );
      expect(
        report['reportCommand'],
        'python3 <skill-dir>/scripts/new_report.py . --scope camera --package camera',
      );
      expect(
        report['summaryCommand'],
        'python3 <skill-dir>/scripts/new_summary.py . --scope camera --package camera',
      );
      expect(
        report['scenarioCommand'],
        'python3 <skill-dir>/scripts/new_scenario.py . --scope camera --package camera --platform <platform> --name <scenario-name>',
      );
      expect(
        report['sessionInspectCommand'],
        'python3 <skill-dir>/scripts/inspect_session.py <session-file> --wait 30 --expect-platform <platform>',
      );
    },
    skip: Platform.isWindows ? 'uses POSIX test executables' : false,
  );
}
