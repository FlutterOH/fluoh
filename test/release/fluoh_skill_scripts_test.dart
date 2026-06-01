import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  const preflightScript = 'skills/fluoh/scripts/preflight.py';
  const reportScript = 'skills/fluoh/scripts/new_report.py';
  const checkReportScript = 'skills/fluoh/scripts/check_report.py';

  Future<Directory> createTempRoot() {
    return Directory.systemTemp.createTemp('fluoh_skill_script_');
  }

  Future<File> writeFakeFluoh(Directory root) async {
    final tool = File('${root.path}/fluoh');
    await tool.writeAsString('''
#!/bin/sh
if [ "\$1" = "--version" ]; then
  echo "fluoh 9.9.9"
  exit 0
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

  Future<Map<String, Object?>> runPreflight(
    Directory root, {
    required String fluohCommand,
    String? path,
  }) async {
    final result = await Process.run('python3', [
      preflightScript,
      path ?? root.path,
      '--fluoh-command',
      fluohCommand,
    ]);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    return jsonDecode(result.stdout.toString()) as Map<String, Object?>;
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

      final report = await runPreflight(root, fluohCommand: fluoh.path);
      final project = report['project'] as Map<String, Object?>;
      final fluohResult = report['fluoh'] as Map<String, Object?>;
      final platforms = project['platformDirectories'] as Map<String, Object?>;

      expect(project['kind'], 'app-project');
      expect(project['name'], 'example_app');
      expect(project['isFlutter'], isTrue);
      expect(project['isFlutterPlugin'], isFalse);
      expect(project['sdkVersion'], '3.35.8-ohos-0.0.3');
      expect(project['needsPackageSelection'], isFalse);
      expect(platforms['ohos'], isTrue);
      expect(platforms['android'], isTrue);
      expect(fluohResult['ok'], isTrue);
      expect(fluohResult['stdout'], 'fluoh 9.9.9');
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
        'fluoh run --platform ohos --device <id> --json',
      ]);
      expect(stringList(report['finalCheckCommands']), [
        'git diff --check',
        'fluoh doctor -p --platform ohos --json --strict',
        'fluoh build --platform ohos --auto-sign --json',
        'fluoh devices --platform ohos --json',
        'fluoh run --platform ohos --device <id> --json',
      ]);
      expect(
        stringList(report['deliveryChecks']),
        containsAll([
          contains('.fluoh/ai-report-...md'),
          contains('Record deps, doctor, build, and run command results'),
          contains('State ready, blocked, or needs maintainer decision'),
        ]),
      );
      expect(
        report['reportCommand'],
        'python3 <skill-dir>/scripts/new_report.py . --scope example_app',
      );
      expect(
        report['reportCheckCommand'],
        'python3 <skill-dir>/scripts/check_report.py <report-path>',
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
        allOf(
          contains('fluoh package create'),
          contains('--package-path .'),
          contains('--output ../camera_ohos'),
        ),
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
name: camera

sdk:
  version: 3.35.8-ohos-0.0.3

packages:
  camera:
    repository:
      path: packages/camera/camera
    upstream:
      path: packages/camera/camera
''');
      await Directory(
        '${root.path}/packages/camera/camera/example/android',
      ).create(recursive: true);
      await Directory(
        '${root.path}/packages/camera/camera/example/ohos',
      ).create(recursive: true);

      final report = await runPreflight(root, fluohCommand: fluoh.path);
      final project = report['project'] as Map<String, Object?>;
      final packages = project['packages'] as List<Object?>;
      final package = packages.single as Map<String, Object?>;
      final examplePlatforms =
          package['examplePlatforms'] as Map<String, Object?>;

      expect(project['kind'], 'package-repository');
      expect(project['packageNames'], ['camera']);
      expect(project['selectedPackage'], 'camera');
      expect(project['needsPackageSelection'], isFalse);
      expect(project['sdkVersion'], '3.35.8-ohos-0.0.3');
      expect(package['path'], 'packages/camera/camera');
      expect(examplePlatforms['ohos'], isTrue);
      expect(examplePlatforms['android'], isTrue);
      expect(
        stringList(report['suggestedCommands']),
        containsAll([
          'fluoh verify --package camera --json',
          'fluoh run --platform ohos --package camera --json',
          'fluoh package release --package camera --dry-run --json',
        ]),
      );
      expect(
        stringList(report['finalCheckCommands']),
        containsAll([
          'git diff --check',
          'fluoh verify --package camera --json',
          'fluoh package status --package camera',
          'fluoh package release --package camera --dry-run --json',
        ]),
      );
      expect(
        stringList(report['deliveryChecks']),
        containsAll([
          contains('.fluoh/ai-report-camera-...md'),
          contains('Record verify, status, and release dry-run results'),
          contains('Review public API compatibility'),
        ]),
      );
      expect(
        report['reportCommand'],
        'python3 <skill-dir>/scripts/new_report.py . --scope camera --package camera',
      );
    },
    skip: Platform.isWindows ? 'uses POSIX test executables' : false,
  );

  test(
    'preflight makes multi-package selection explicit',
    () async {
      final root = await createTempRoot();
      addTearDown(() => root.delete(recursive: true));
      final fluoh = await writeFakeFluoh(root);

      await File('${root.path}/fluoh.yaml').writeAsString('''
schema: 1
name: plugins

sdk:
  version: 3.35.8-ohos-0.0.3

packages:
  camera:
    repository:
      path: packages/camera/camera
    upstream:
      path: packages/camera/camera
  share_plus:
    repository:
      path: packages/share_plus/share_plus
    upstream:
      path: packages/share_plus/share_plus
''');
      await Directory(
        '${root.path}/packages/share_plus/share_plus/example/ios',
      ).create(recursive: true);
      await Directory(
        '${root.path}/packages/share_plus/share_plus/example/macos',
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
      expect(project['packageNames'], ['camera', 'share_plus']);
      expect(project['selectedPackage'], isNull);
      expect(project['needsPackageSelection'], isTrue);
      expect(sharePlusPlatforms['ios'], isTrue);
      expect(sharePlusPlatforms['macos'], isTrue);
      expect(
        stringList(report['suggestedCommands']),
        containsAll([
          'fluoh verify --package <name> --json',
          'fluoh run --platform ohos --package <name> --json',
        ]),
      );
      expect(
        stringList(report['finalCheckCommands']),
        contains('fluoh verify --package <name> --json'),
      );
      expect(
        stringList(report['deliveryChecks']),
        contains(contains('.fluoh/ai-report-<name>-...md')),
      );
      expect(stringList(report['notes']).single, contains('Multiple packages'));
      expect(
        report['reportCommand'],
        'python3 <skill-dir>/scripts/new_report.py . --scope <name> --package <name>',
      );
    },
    skip: Platform.isWindows ? 'uses POSIX test executables' : false,
  );

  test(
    'preflight selects a requested package in a multi-package repository',
    () async {
      final root = await createTempRoot();
      addTearDown(() => root.delete(recursive: true));
      final fluoh = await writeFakeFluoh(root);

      await File('${root.path}/fluoh.yaml').writeAsString('''
schema: 1
name: plugins

sdk:
  version: 3.35.8-ohos-0.0.3

packages:
  camera:
    repository:
      path: packages/camera/camera
  share_plus:
    repository:
      path: packages/share_plus/share_plus
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
        (report['project'] as Map<String, Object?>)['needsPackageSelection'],
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
      expect(project['needsPackageSelection'], isFalse);
      expect(stringList(selected['notes']), isEmpty);
      expect(
        stringList(selected['suggestedCommands']),
        containsAll([
          'fluoh verify --package share_plus --json',
          'fluoh run --platform ohos --package share_plus --json',
          'fluoh package release --package share_plus --dry-run --json',
        ]),
      );
      expect(
        stringList(selected['finalCheckCommands']),
        containsAll([
          'git diff --check',
          'fluoh verify --package share_plus --json',
          'fluoh package status --package share_plus',
          'fluoh package release --package share_plus --dry-run --json',
        ]),
      );
      expect(
        selected['reportCommand'],
        'python3 <skill-dir>/scripts/new_report.py . --scope share_plus --package share_plus',
      );
      expect(
        selected['reportCheckCommand'],
        'python3 <skill-dir>/scripts/check_report.py <report-path>',
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
packages:
  camera:
    repository:
      path: packages/camera/camera
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
      expect(stringList(selected['notes']).single, contains('camera'));
      expect(
        stringList(selected['suggestedCommands']),
        contains('fluoh verify --package <name> --json'),
      );
      expect(
        stringList(selected['deliveryChecks']),
        contains(contains('.fluoh/ai-report-<name>-...md')),
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

      expect(first.path, isNot(second.path));
      expect(first.existsSync(), isTrue);
      expect(second.existsSync(), isTrue);
      expect(
        first.uri.pathSegments.last,
        startsWith('ai-report-camera-plugin-'),
      );
      final content = await first.readAsString();
      expect(content, contains('- Scope: camera plugin'));
      expect(content, contains('- Package: camera'));
      expect(content, contains('- Upstream version: 0.11.0'));
      expect(content, contains('- FlutterOH SDK: 3.35.8-ohos-0.0.3'));
      expect(content, contains('- Recommendation: ready'));
      expect(content, contains('## Delivery Checklist'));
      expect(content, contains('Diff reviewed'));
      expect(content, contains('OHOS build evidence recorded'));
      expect(content, contains('Release recommendation: ready'));
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
            '| `fluoh verify --package camera --json` | 0 | passed | pub get, analyze, tests passed |',
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
      expect(completeJson['commandRows'], 1);
      expect(completeJson['checklistDone'], completeJson['checklistTotal']);
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
}
