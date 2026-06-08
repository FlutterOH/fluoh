import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  const preflightScript = 'skills/fluoh/scripts/preflight.py';
  const reportScript = 'skills/fluoh/scripts/new_report.py';
  const summaryScript = 'skills/fluoh/scripts/new_summary.py';
  const checkReportScript = 'skills/fluoh/scripts/check_report.py';
  const scenarioScript = 'skills/fluoh/scripts/new_scenario.py';
  const inspectSessionScript = 'skills/fluoh/scripts/inspect_session.py';
  const collectFeedbackScript = 'skills/fluoh/scripts/collect_feedback.py';

  Future<Directory> createTempRoot() {
    return Directory.systemTemp.createTemp('fluoh_skill_script_');
  }

  Future<File> writeFakeFluoh(
    Directory root, {
    String docsDryRunOutput = 'Package docs are current',
    int docsDryRunExitCode = 0,
  }) async {
    final tool = File('${root.path}/fluoh');
    await tool.writeAsString('''
#!/bin/sh
if [ "\$1" = "--version" ]; then
  echo "fluoh 9.9.9"
  exit 0
fi
if [ "\$1" = "package" ] && [ "\$2" = "docs" ] && [ "\$3" = "refresh" ] && [ "\$4" = "--dry-run" ]; then
cat <<'EOF'
$docsDryRunOutput
EOF
  exit $docsDryRunExitCode
fi
echo "unexpected args: \$@" >&2
exit 64
''');
    final chmod = await Process.run('chmod', ['+x', tool.path]);
    expect(chmod.exitCode, 0, reason: chmod.stderr.toString());
    return tool;
  }

  Future<File> writeFakeDartRunner(Directory root) async {
    final tool = File('${root.path}/dart-runner');
    await tool.writeAsString('''
#!/bin/sh
if [ "\$1" = "run" ] && [ "\$2" = "bin/fluoh.dart" ] && [ "\$3" = "--version" ]; then
  echo "fluoh 8.8.8"
  exit 0
fi
echo "unexpected args: \$@" >&2
exit 64
''');
    final chmod = await Process.run('chmod', ['+x', tool.path]);
    expect(chmod.exitCode, 0, reason: chmod.stderr.toString());
    return tool;
  }

  Future<File> writeFakeDartExecutable(
    Directory root, {
    required String scriptPath,
    List<String> extraArgs = const [],
  }) async {
    final tool = File('${root.path}/dart');
    final expected = [scriptPath, ...extraArgs, '--version'];
    final checks = [
      for (var i = 0; i < expected.length; i += 1)
        '[ "\$${i + 1}" = "${expected[i]}" ]',
      '[ "\$#" = "${expected.length}" ]',
    ].join(' && ');
    await tool.writeAsString('''
#!/bin/sh
if $checks; then
  echo "fluoh 7.7.7"
  exit 0
fi
echo "unexpected args: \$@" >&2
exit 64
''');
    final chmod = await Process.run('chmod', ['+x', tool.path]);
    expect(chmod.exitCode, 0, reason: chmod.stderr.toString());
    return tool;
  }

  Future<File> writeFakeFlutterDartWrapper(
    Directory root, {
    required String scriptPath,
  }) async {
    final bin = Directory('${root.path}/flutter/bin');
    final cacheBin = Directory('${bin.path}/cache/dart-sdk/bin');
    await cacheBin.create(recursive: true);
    final wrapper = File('${bin.path}/dart');
    await wrapper.writeAsString('''
#!/bin/sh
echo "flutter wrapper should not be used" >&2
exit 65
''');
    final cachedDart = File('${cacheBin.path}/dart');
    await cachedDart.writeAsString('''
#!/bin/sh
if [ "\$1" = "$scriptPath" ] && [ "\$2" = "--version" ]; then
  echo "fluoh 6.6.6"
  exit 0
fi
echo "unexpected cached dart args: \$@" >&2
exit 64
''');
    for (final tool in [wrapper, cachedDart]) {
      final chmod = await Process.run('chmod', ['+x', tool.path]);
      expect(chmod.exitCode, 0, reason: chmod.stderr.toString());
    }
    return wrapper;
  }

  Future<Map<String, Object?>> runPreflight(
    Directory root, {
    required String fluohCommand,
    String? path,
    Map<String, String>? environment,
  }) async {
    final result = await Process.run('python3', [
      preflightScript,
      path ?? root.path,
      '--fluoh-command',
      fluohCommand,
    ], environment: environment);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    return jsonDecode(result.stdout.toString()) as Map<String, Object?>;
  }

  Future<void> runProcess(
    String executable,
    List<String> arguments,
    Directory workingDirectory,
  ) async {
    final result = await Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory.path,
    );
    expect(
      result.exitCode,
      0,
      reason: '$executable ${arguments.join(' ')}\n${result.stderr}',
    );
  }

  List<String> stringList(Object? value) {
    return (value as List<Object?>).cast<String>();
  }

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
      final appRegressionCommands = [
        'fluoh doctor --platform android --json --strict',
        'fluoh run --platform android --auto-emulator --json',
        if (Platform.isLinux) ...[
          'fluoh doctor --platform linux --json --strict',
          'fluoh build --platform linux --json',
        ],
        'fluoh doctor --platform web --json --strict',
        'fluoh run --platform web --device web-server --json',
        if (Platform.isWindows) ...[
          'fluoh doctor --platform windows --json --strict',
          'fluoh build --platform windows --json',
        ],
      ];
      expect(stringList(report['suggestedCommands']), [
        'fluoh source update',
        'fluoh sdk use 3.35.8-ohos-0.0.3 --pub-get',
        'fluoh deps check --json',
        'fluoh deps fix --dry-run',
        'fluoh deps fix',
        'fluoh deps get',
        'fluoh doctor -p --platform ohos --json --strict',
        'fluoh build --platform ohos --auto-sign --json',
        'fluoh devices --platform ohos --json',
        'fluoh emulators --platform ohos --json',
        'fluoh run --platform ohos --auto-emulator --json',
        ...appRegressionCommands,
      ]);
      expect(stringList(report['finalCheckCommands']), [
        'git diff --check',
        'fluoh doctor -p --platform ohos --json --strict',
        'fluoh build --platform ohos --auto-sign --json',
        'fluoh devices --platform ohos --json',
        'fluoh emulators --platform ohos --json',
        'fluoh run --platform ohos --auto-emulator --json',
        ...appRegressionCommands,
      ]);
      expect(
        stringList(report['deliveryChecks']),
        containsAll([
          contains('.fluoh/reports/example_app/ai-report-...md'),
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
        contains(contains('.fluoh/reports/Example-App/ai-report-...md')),
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
        contains('fluoh verify --package camera --json'),
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
        packageDocs['dryRunCommand'],
        'fluoh package docs refresh --dry-run',
      );
      expect(
        stringList(report['suggestedCommands']),
        containsAll([
          'fluoh package docs refresh --dry-run',
          'fluoh package docs refresh',
          'fluoh verify --package camera --json',
          'fluoh run --platform ohos --package camera --auto-emulator --json',
          'fluoh run --platform web --package camera --device web-server --json',
          'fluoh package check --package camera --json',
        ]),
      );
      expect(
        stringList(report['finalCheckCommands']),
        containsAll([
          'git diff --check',
          'fluoh verify --package camera --json',
          'fluoh package status --package camera',
          'fluoh package check --package camera --json',
        ]),
      );
      expect(
        stringList(report['deliveryChecks']),
        containsAll([
          contains('.fluoh/reports/camera/ai-report-...md'),
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
        'fluoh doctor -p --platform ohos --json --strict',
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
      final packageSuggestedCommands = [
        'fluoh verify --package share_plus --json',
        'fluoh run --platform ohos --package share_plus --auto-emulator --json',
        if (Platform.isLinux)
          'fluoh build --platform linux --package share_plus --json',
        'fluoh run --platform web --package share_plus --device web-server --json',
        if (Platform.isWindows)
          'fluoh build --platform windows --package share_plus --json',
      ];
      expect(
        stringList(report['suggestedCommands']),
        containsAll(packageSuggestedCommands),
      );
      expect(
        stringList(report['finalCheckCommands']),
        contains('fluoh verify --package share_plus --json'),
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
          'fluoh verify --package share_plus --json',
          'fluoh run --platform ohos --package share_plus --auto-emulator --json',
          'fluoh package check --package share_plus --json',
        ]),
      );
      expect(
        stringList(selected['finalCheckCommands']),
        containsAll([
          'git diff --check',
          'fluoh verify --package share_plus --json',
          'fluoh package status --package share_plus',
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
        contains('fluoh verify --package <name> --json'),
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

      expect(first.path, isNot(second.path));
      expect(first.existsSync(), isTrue);
      expect(second.existsSync(), isTrue);
      expect(defaultReport.existsSync(), isTrue);
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
          '- Session file command, when supported: fluoh run --platform android --package camera --auto-emulator --session-file .fluoh/run-sessions/camera/android-session.json --json',
        ),
      );
      expect(
        androidContent,
        contains(
          '- Session inspect command, when supported: python3 <skill-dir>/scripts/inspect_session.py .fluoh/run-sessions/camera/android-session.json --wait 30 --expect-platform android',
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
      expect(
        webContent,
        contains('- Target requirement: browser or web-server'),
      );
      expect(
        webContent,
        contains(
          '- Related command: fluoh run --platform web --package camera --device web-server --json',
        ),
      );
      expect(
        webContent,
        contains(
          '- Session file command, when supported: fluoh run --platform web --package camera --device web-server --session-file .fluoh/run-sessions/camera/web-session.json --json',
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
        contains(
          'fluoh run --platform ohos --package camera --auto-emulator --json',
        ),
      );
      expect(
        content,
        contains('- Session file command, when supported: not supported'),
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
                  'fluoh build --platform ohos --package camera --json --trace-dir .fluoh/traces/camera-session',
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
    'simulates a complete AI adaptation evidence flow',
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

      final preflight = await runPreflight(root, fluohCommand: fluoh.path);
      final project = preflight['project'] as Map<String, Object?>;
      final package =
          (project['packages'] as List<Object?>).single as Map<String, Object?>;
      final examplePlatforms =
          package['examplePlatforms'] as Map<String, Object?>;
      expect(project['kind'], 'package-repository');
      expect(project['selectedPackage'], 'camera');
      expect(examplePlatforms['android'], isTrue);
      expect(examplePlatforms['ohos'], isTrue);
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
- Related command: fluoh run --platform android --package camera --auto-emulator --session-file .fluoh/run-sessions/camera/android-session.json --json
- Session file command, when supported: fluoh run --platform android --package camera --auto-emulator --session-file .fluoh/run-sessions/camera/android-session.json --json
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
      await report.writeAsString('''
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

## Changes

- Added OHOS package verification evidence and Android AI-assisted permission scenario evidence.

## Public API / Compatibility

- Public Dart API changes: none
- Dependency constraint changes: none
- Non-OHOS regression risk: Android example run and permission-denied fallback checked

## Commands

| Command | Exit | Result | Notes |
| --- | --- | --- | --- |
| `python3 skills/fluoh/scripts/preflight.py ${root.path} --package camera` | 0 | passed | package repository detected, camera selected |
| `fluoh verify --package camera --json` | 0 | passed | pub get, analyze, and tests passed in simulated evidence |
| `fluoh run --platform ohos --package camera --auto-emulator --json` | 0 | passed | HAP built, signed, installed, launched, and hilog checked |
| `fluoh run --platform android --package camera --auto-emulator --session-file .fluoh/run-sessions/camera/android-session.json --json` | 0 | passed | launch detected and session file written |
| `python3 skills/fluoh/scripts/inspect_session.py .fluoh/run-sessions/camera/android-session.json --wait 1 --expect-platform android --require-vm-service` | 0 | passed | VM Service URI detected for non-visual inspection |
| `fluoh package check --package camera --json` | 0 | passed | release metadata validated |

## Delivery Checklist

- [x] Diff reviewed; unrelated files, local paths, generated caches, credentials, and private tokens excluded.
- [x] Commands table includes exit codes and enough evidence to reproduce the decision.
- [x] OHOS build evidence recorded.
- [x] OHOS run evidence recorded, or the missing device/emulator blocker is explicit.
- [x] Android, iOS, macOS, Linux, Web, and Windows regression checks recorded when relevant.
- [x] Functional interaction evidence recorded for permission, file, camera, location, media, deep link, external-app, or other device workflows.
- [x] Public API, dependency constraints, and non-OHOS regression risk reviewed.
- [x] Remaining risks and release decision are explicit.

## Platform Matrix

| Platform | Build | Run | Integration test | Target | Evidence / blocker |
| --- | --- | --- | --- | --- | --- |
| OHOS | passed | passed | absent | hdc-target | HAP build, signing, launch, hilog evidence |
| Android | passed | passed | absent | emulator-5554 | flutterRunSession and VM Service evidence |
| iOS | not present | not present | absent | no target | example ios directory absent |
| macOS | not present | not present | absent | no target | example macos directory absent |

## Interaction Evidence

| Scenario | Method | Platform | Target | Result | Evidence / blocker |
| --- | --- | --- | --- | --- | --- |
| `${scenario.path}` | AI-assisted | Android | emulator-5554 | passed | camera permission denied fallback verified through VM Service attach hint, semantic label cameraPermissionDenied, log marker camera.permissionDenied, session ${sessionFile.path} |

## Diagnostics

- No unresolved diagnostic remains. Android session recommendation: ${inspectJson['recommendation']}.

## Fluoh Feedback

No fluoh feedback: diagnostics were actionable and no tool or Source gap was found.

## Signing

- Mode: automatic debug signing
- Generated HAPs: camera-ohos-debug.hap
- Hilog: no crash marker detected

## Remaining Risks

- Real camera capture positive path still depends on physical target availability.

## Local State

- Git status summary: simulated temp workspace only
- Files intentionally left uncommitted: ${scenario.path}, ${report.path}, ${sessionFile.path}
- Files that must not be committed: local session logs

## Release Decision

Release recommendation: ready

Reason:
The simulated AI flow completed preflight, build/run evidence, non-visual interaction evidence, session inspection, and package check evidence.
''');

      final check = await Process.run('python3', [
        checkReportScript,
        report.path,
      ]);
      expect(check.exitCode, 0, reason: check.stdout.toString());
      final checkJson =
          jsonDecode(check.stdout.toString()) as Map<String, Object?>;
      expect(checkJson, containsPair('ok', true));
      expect(checkJson, containsPair('recommendation', 'ready'));
      expect(checkJson, containsPair('commandRows', 6));
      expect(checkJson, containsPair('passedCommandRows', 6));
      expect(checkJson, containsPair('interactionRows', 1));
      expect(checkJson, containsPair('passedInteractionRows', 1));
      expect(checkJson['errors'], isEmpty);
    },
    skip: Platform.isWindows ? 'uses POSIX test executables' : false,
  );

  test(
    'check_report fails placeholders and accepts completed ready reports',
    () async {
      final root = await createTempRoot();
      addTearDown(() => root.delete(recursive: true));
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
                '| `fluoh build --platform ohos --package camera --auto-sign --json` | 0 | passed | signed HAP produced |',
          )
          .replaceAll(
            RegExp(r'^- \.\.\.$', multiLine: true),
            '- Evidence recorded',
          )
          .replaceAll('- [ ]', '- [x]')
          .replaceAll(
            'OHOS | skipped | skipped | n/a | n/a | ...',
            'OHOS | passed | passed | n/a | emulator-5554 | HAP built and launched',
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
            '| `...` | integration_test \\| AI-assisted \\| manual-assisted | OHOS | device-or-emulator | passed | steps, functional assertions, Flutter debug/widget/semantic/log evidence, flutterRunSession/VM Service evidence when available; screenshots optional |',
            '| camera preview | manual-assisted | OHOS | emulator-5554 | passed | user tapped capture, then hilog marker camera.captureSuccess confirmed the result |',
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
      expect(completeJson['commandRows'], 2);
      expect(completeJson['passedCommandRows'], 2);
      expect(completeJson['passedVerify'], isTrue);
      expect(completeJson['passedOhosBuild'], isTrue);
      expect(completeJson['passedOhosRun'], isFalse);
      expect(completeJson['interactionRows'], 1);
      expect(completeJson['passedInteractionRows'], 1);
      expect(completeJson['checklistDone'], completeJson['checklistTotal']);

      final manualReport = File('${root.path}/manual-report.md');
      await manualReport.writeAsString(
        content.replaceFirst(
          '| camera preview | manual-assisted | OHOS | emulator-5554 | passed |',
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

      final maintainerDecisionReport = File(
        '${root.path}/maintainer-decision.md',
      );
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

      final failedEvidenceReport = File('${root.path}/failed-ready.md');
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

      final verifyOnlyReport = File('${root.path}/verify-only-ready.md');
      await verifyOnlyReport.writeAsString(
        content.replaceFirst(
          '\n| `fluoh build --platform ohos --package camera --auto-sign --json` | 0 | passed | signed HAP produced |',
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

      final ordinaryEvidenceReport = File('${root.path}/ordinary-ready.md');
      await ordinaryEvidenceReport.writeAsString(
        content.replaceFirst(
          '| `fluoh verify --package camera --json` | 0 | passed | pub get, analyze, tests passed |\n'
              '| `fluoh build --platform ohos --package camera --auto-sign --json` | 0 | passed | signed HAP produced |',
          '| `dart test` | 0 | passed | unit tests passed |',
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
        ]),
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
      final report = File('${root.path}/report.md');
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

## Commands

| Command | Exit | Result | Notes |
| --- | --- | --- | --- |
| `fluoh verify --package camera --json` | 0 | passed | pub get, analyze, tests passed |
| `fluoh build --platform ohos --package camera --auto-sign --json` | 0 | passed | signed HAP produced |

## Delivery Checklist

- [x] Diff reviewed.

## Platform Matrix

| Platform | Build | Run | Integration test | Target | Evidence / blocker |
| --- | --- | --- | --- | --- | --- |
| OHOS | passed | skipped | absent | host | signed build evidence |

## Interaction Evidence

No interaction required: pure Dart package exposes no device-side flow.

## Diagnostics

- None.

## Fluoh Feedback

$defaultFeedback
## Signing

- Mode: automatic debug signing
- Generated HAPs: camera-ohos-debug.hap
- Hilog: none

## Remaining Risks

- None.

## Local State

- Git status summary: clean
- Files intentionally left uncommitted: report.md
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
      final report = File('${root.path}/report.md');
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

## Commands

| Command | Exit | Result | Notes |
| --- | --- | --- | --- |
| `fluoh verify --package pure_dart --json` | 0 | passed | no device APIs |
| `fluoh build --platform ohos --package pure_dart --auto-sign --json` | 0 | passed | signed example HAP produced |

## Delivery Checklist

- [x] Diff reviewed.

## Platform Matrix

| Platform | Build | Run | Integration test | Target | Evidence / blocker |
| --- | --- | --- | --- | --- | --- |
| OHOS | passed | skipped | absent | host | pure Dart package |

## Interaction Evidence

Use `No interaction required: <reason>` only when no device-side flow applies.

## Diagnostics

- None.

## Fluoh Feedback

No fluoh feedback: diagnostics were actionable and no tool or Source gap was found.

## Signing

- Mode: not required
- Generated HAPs: none
- Hilog: none

## Remaining Risks

- None.

## Local State

- Git status summary: clean
- Files intentionally left uncommitted: report.md
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
