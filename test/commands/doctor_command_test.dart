import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:fluoh/fluoh.dart';
import 'package:fluoh/src/doctor/doctor_command.dart';
import 'package:test/test.dart';

import '../helpers/fluoh_command_context.dart';

const _currentVersionPublished = '2026-05-01';
const _newerVersion = '99.0.0';

void main() {
  test('reports full environment and project status with --project', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    await writeFlutterProjectFixture(environment.workingDirectory);
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'add', 'fixture', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    await runFluoh(
      ['sdk', 'use', '3.35.8-ohos-0.0.3', '--no-init-ohos'],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );

    final result = await _runDoctorCommand(
      environment: environment,
      versionMetadataProvider: () async => const DoctorVersionMetadata(
        latestVersion: packageVersion,
        currentVersionPublished: _currentVersionPublished,
      ),
      arguments: const ['doctor', '--project'],
    );
    stdout.addAll(result.stdout);
    stderr.addAll(result.stderr);

    expect(result.exitCode, 0);

    expect(stdout.join('\n'), isNot(contains('Doctor summary:')));
    expect(stdout, isNot(contains('Environment checks:')));
    expect(stdout, isNot(contains('Project checks:')));
    expect(stdout.join('\n'), contains('[✓] fluoh ($packageVersion, on '));
    expect(_normalizeOutput(stdout.join('\n')), contains('locale '));
    expect(stdout, contains('    • Installed with dart pub global activate.'));
    expect(_normalizeOutput(stdout.join('\n')), contains('fluoh home at '));
    expect(stdout.join('\n'), contains('Dart version '));
    expect(
      _normalizeOutput(stdout.join('\n')),
      contains('Dart executable at '),
    );
    expect(
      stdout,
      contains('    • Current version published: $_currentVersionPublished'),
    );
    expect(stdout, contains('    • Up to date'));
    expect(stdout.join('\n'), isNot(contains('\u001b[')));
    expect(stdout.join('\n'), contains('[!] Flutter project'));
    expect(stdout, contains('    • Detected Flutter project'));
    expect(stdout, contains('    • FlutterOH SDK 3.35.8-ohos-0.0.3 selected'));
    expect(stdout, contains('    • Missing ohos platform directory'));
    expect(stdout.join('\n'), contains('[!] Sources'));
    expect(_normalizeOutput(stdout.join('\n')), contains('fixture: file://'));
    expect(_normalizeOutput(stdout.join('\n')), contains('flutteroh: file://'));
    expect(stdout.join('\n'), contains('(not updated)'));
    expect(stdout.join('\n'), contains('Android toolchain'));
    expect(stdout.join('\n'), contains('Xcode - develop for iOS devices'));
    expect(stdout.join('\n'), isNot(contains('Project SDK')));
    expect(stdout.join('\n'), isNot(contains('OHOS project platform')));
    expect(stdout.join('\n'), isNot(contains('Android project platform')));
    expect(stdout.join('\n'), isNot(contains('iOS project platform')));
    expect(
      stdout.join('\n'),
      contains('[!] OpenHarmony toolchain - develop for OHOS devices'),
    );
    expect(
      stdout,
      contains('    • DevEco Studio OpenHarmony tools were not found'),
    );
    expect(stdout.join('\n'), isNot(contains('Dependencies')));
    expect(stdout.join('\n'), isNot(contains('mystery_package')));
    expect(stdout.join('\n'), isNot(contains('camera_platform_interface')));
    expect(stdout.join('\n'), contains('Doctor found issues in '));
    expect(stdout.join('\n'), contains(' categories.'));
    _expectInOrder(stdout.join('\n'), [
      '[✓] fluoh ($packageVersion, on ',
      '[!] Sources',
      '[!] OpenHarmony toolchain - develop for OHOS devices',
      'Android toolchain',
      'Xcode - develop for iOS devices',
      '[!] Flutter project',
    ]);
    expect(stderr, isEmpty);
  });

  test('accepts -p as the project check alias', () async {
    final environment = await createTestEnvironment();
    await writeFlutterProjectFixture(environment.workingDirectory);

    final result = await _runDoctorCommand(
      environment: environment,
      versionMetadataProvider: () async =>
          const DoctorVersionMetadata(latestVersion: packageVersion),
      arguments: const ['doctor', '-p'],
    );

    expect(result.exitCode, 0);
    expect(result.stdout.join('\n'), contains('[!] Flutter project'));
    expect(result.stdout, contains('    • Detected Flutter project'));
    expect(result.stdout, contains('    • No FlutterOH SDK selected'));
    expect(result.stdout, contains('    • Missing ohos platform directory'));
    expect(result.stdout.join('\n'), isNot(contains('Project SDK')));
    expect(result.stderr, isEmpty);
  });

  test('reports non-Flutter projects without modifying files', () async {
    final environment = await createTestEnvironment();
    final stdout = <String>[];
    final stderr = <String>[];

    final result = await _runDoctorCommand(
      environment: environment,
      versionMetadataProvider: () async =>
          const DoctorVersionMetadata(latestVersion: packageVersion),
      arguments: const ['doctor', '--project'],
    );
    stdout.addAll(result.stdout);
    stderr.addAll(result.stderr);

    expect(result.exitCode, 0);

    expect(stdout.join('\n'), contains('[!] Flutter project'));
    expect(
      stdout,
      contains('    • Current directory is not a Flutter project'),
    );
    expect(
      File('${environment.workingDirectory.path}/fluoh.yaml').existsSync(),
      isFalse,
    );
    expect(stderr, isEmpty);
  });

  test('omits project checks by default outside Flutter projects', () async {
    final environment = await createTestEnvironment();

    final result = await _runDoctorCommand(
      environment: environment,
      versionMetadataProvider: () async =>
          const DoctorVersionMetadata(latestVersion: packageVersion),
    );

    expect(result.exitCode, 0);
    expect(result.stdout.join('\n'), isNot(contains('Project checks:')));
    expect(result.stdout.join('\n'), isNot(contains('[-] Project')));
    expect(result.stdout.join('\n'), isNot(contains('[!] Flutter project')));
    expect(result.stdout.join('\n'), isNot(contains('[!] Project SDK')));
    expect(
      result.stdout.join('\n'),
      isNot(contains('[!] OHOS project platform')),
    );
    expect(result.stderr, isEmpty);
  });

  test('shows all available sources', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    await File('${environment.homeDirectory.path}/config.json').writeAsString(
      jsonEncode({
        'sources': {
          'fixture': {'path': source.path, 'priority': 10},
          'mirror': {'path': source.path, 'priority': 20},
        },
      }),
    );

    final result = await _runDoctorCommand(
      environment: environment,
      versionMetadataProvider: () async =>
          const DoctorVersionMetadata(latestVersion: packageVersion),
      arguments: const ['doctor', '--platform', 'ohos'],
    );

    expect(result.exitCode, 0);
    expect(result.stdout.join('\n'), contains('[✓] Sources'));
    expect(result.stdout.join('\n'), isNot(contains('Sources (')));
    expect(result.stdout.join('\n'), contains('fixture:'));
    expect(result.stdout.join('\n'), contains('mirror:'));
    expect(result.stderr, isEmpty);
  });

  test('checks native Android tooling without a selected Flutter SDK', () async {
    final environment = await createTestEnvironment();
    final androidSdk = await _writeAndroidSdkFixture(environment.homeDirectory);
    final javaHome = Directory('${environment.homeDirectory.path}/java');
    await _writeExecutable(File('${javaHome.path}/bin/java'), '''
if [ "\$1" = "-version" ]; then
  printf 'openjdk version "17.0.9"\\n' >&2
  exit 0
fi
exit 0
''');
    final doctorEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: environment.workingDirectory,
      processEnvironment: {
        ...environment.processEnvironment,
        'ANDROID_HOME': androidSdk.path,
        'JAVA_HOME': javaHome.path,
      },
    );

    final result = await _runDoctorCommand(
      environment: doctorEnvironment,
      versionMetadataProvider: () async =>
          const DoctorVersionMetadata(latestVersion: packageVersion),
      arguments: const ['doctor', '--platform', 'android', '--json'],
    );

    expect(result.exitCode, 0);
    final report = jsonDecode(result.stdout.single) as Map<String, Object?>;
    expect(report, containsPair('schemaVersion', 1));
    expect(report, containsPair('command', 'doctor'));
    expect(report, containsPair('exitCode', 0));
    expect(report, containsPair('project', false));
    final checks = report['checks'] as List<Object?>;
    expect(
      checks,
      contains(
        allOf(
          containsPair('id', 'android.toolchain'),
          containsPair('title', 'Android toolchain'),
          containsPair('status', 'ok'),
        ),
      ),
    );
    expect(
      checks,
      isNot(
        contains(
          allOf(
            containsPair('group', 'project'),
            containsPair('title', 'Project SDK'),
          ),
        ),
      ),
    );
    expect(
      File('${environment.workingDirectory.path}/fluoh.yaml').existsSync(),
      isFalse,
    );

    final plainResult = await _runDoctorCommand(
      environment: doctorEnvironment,
      versionMetadataProvider: () async =>
          const DoctorVersionMetadata(latestVersion: packageVersion),
      arguments: const ['doctor', '--platform', 'android'],
    );

    expect(plainResult.exitCode, 0);
    expect(
      _normalizeOutput(plainResult.stdout.join('\n')),
      contains(
        _normalizeOutput(
          '[✓] Android toolchain - develop for Android devices (Android SDK version 35.0.1)',
        ),
      ),
    );
    expect(
      _normalizeOutput(plainResult.stdout.join('\n')),
      contains('Android SDK at'),
    );
    expect(
      _normalizeOutput(plainResult.stdout.join('\n')),
      contains('home/android-sdk'),
    );
    expect(plainResult.stdout, contains('    • Emulator version 34.2.0.0'));
    expect(
      plainResult.stdout,
      contains('    • Platform android-36, build-tools 35.0.1'),
    );
    expect(plainResult.stdout.join('\n'), contains('Java binary at'));
    expect(
      _normalizeOutput(plainResult.stdout.join('\n')),
      contains('home/java/bin/java'),
    );
    expect(plainResult.stdout, contains('    • Java version 17.0.9'));
    expect(plainResult.stdout, contains('    • All Android licenses accepted'));
    expect(
      plainResult.stdout.join('\n'),
      contains('[✓] Connected devices (1 available)'),
    );
    expect(
      plainResult.stdout.join('\n'),
      contains('Pixel 35 - (Android) - emulator - emulator-5554 - device'),
    );
    expect(result.stderr, isEmpty);
    expect(plainResult.stderr, isEmpty);
  });

  test('reports iOS native tooling details in plain output', () async {
    final environment = await createTestEnvironment();
    final xcode = Directory('${environment.homeDirectory.path}/Xcode.app');
    await xcode.create(recursive: true);
    final xcrun = File('${environment.homeDirectory.path}/bin/xcrun');
    final pod = File('${environment.homeDirectory.path}/bin/pod');
    await _writeExecutable(xcrun, '''
if [ "\$1" = "simctl" ]; then
  printf '{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-18-0":[{"name":"iPhone 16","udid":"SIM-1","state":"Shutdown","isAvailable":true}]}}'
  exit 0
fi
if [ "\$1" = "--version" ]; then
  printf "xcrun version 70.\\n"
  exit 0
fi
if [ "\$1" = "xcodebuild" ]; then
  printf "Xcode 16.2\\nBuild version 16C5032a\\n"
  exit 0
fi
exit 0
''');
    await _writeExecutable(pod, '''
if [ "\$1" = "--version" ]; then
  printf "1.16.2\\n"
  exit 0
fi
exit 0
''');
    final doctorEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: environment.workingDirectory,
      processEnvironment: {
        ...environment.processEnvironment,
        'DEVELOPER_DIR': xcode.path,
        'FLUOH_XCRUN': xcrun.path,
        'FLUOH_COCOAPODS': pod.path,
      },
    );

    final result = await _runDoctorCommand(
      environment: doctorEnvironment,
      versionMetadataProvider: () async =>
          const DoctorVersionMetadata(latestVersion: packageVersion),
      arguments: const ['doctor', '--platform', 'ios'],
    );

    expect(result.exitCode, 0);
    expect(
      result.stdout.join('\n'),
      contains('[✓] Xcode - develop for iOS devices (Xcode 16.2)'),
    );
    expect(_normalizeOutput(result.stdout.join('\n')), contains('Xcode at'));
    expect(
      _normalizeOutput(result.stdout.join('\n')),
      contains('home/Xcode.app'),
    );
    expect(result.stdout, contains('    • Build 16C5032a'));
    expect(result.stdout, contains('    • CocoaPods version 1.16.2'));
    expect(result.stderr, isEmpty);
  });

  test(
    'prints json and returns non-zero in strict mode when warnings exist',
    () async {
      final environment = await createTestEnvironment();

      final result = await _runDoctorCommand(
        environment: environment,
        versionMetadataProvider: () async =>
            const DoctorVersionMetadata(latestVersion: packageVersion),
        arguments: const ['doctor', '--project', '--json', '--strict'],
      );

      expect(result.exitCode, 1);
      final report = jsonDecode(result.stdout.single) as Map<String, Object?>;
      expect(report, containsPair('schemaVersion', 1));
      expect(report, containsPair('command', 'doctor'));
      expect(report, containsPair('ok', false));
      expect(report, containsPair('exitCode', 1));
      expect(report, containsPair('project', true));
      expect(report['issueCount'], isNonZero);
      final checks = report['checks'] as List<Object?>;
      expect(
        checks,
        contains(
          allOf(
            containsPair('id', 'project.flutter'),
            containsPair('title', 'Flutter project'),
            containsPair('status', 'warning'),
          ),
        ),
      );
      expect(result.stderr, isEmpty);
    },
  );

  test('reports malformed fluoh.yaml as a warning', () async {
    final environment = await createTestEnvironment();
    await writeFlutterProjectFixture(environment.workingDirectory);
    await File(
      '${environment.workingDirectory.path}/fluoh.yaml',
    ).writeAsString('{');
    final stdout = <String>[];
    final stderr = <String>[];

    final result = await _runDoctorCommand(
      environment: environment,
      versionMetadataProvider: () async =>
          const DoctorVersionMetadata(latestVersion: packageVersion),
      arguments: const ['doctor', '--project'],
    );
    stdout.addAll(result.stdout);
    stderr.addAll(result.stderr);

    expect(result.exitCode, 0);

    expect(stdout.join('\n'), contains('[!] Flutter project'));
    expect(stdout, contains('    • fluoh.yaml is not valid YAML'));
    expect(stderr, isEmpty);
  });

  test('reports invalid source snapshots as warnings', () async {
    final environment = await createTestEnvironment();
    final source = Directory(
      '${environment.homeDirectory.path}/sources/broken',
    );
    await source.create(recursive: true);
    await File('${source.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: source
name: Broken source
repository:
  git:
    url: /tmp/broken
manifests:
  - name: missing
''');
    await File('${environment.homeDirectory.path}/config.json').writeAsString(
      jsonEncode({
        'sources': {
          'broken': {'path': source.path, 'priority': 10},
        },
      }),
    );

    final result = await _runDoctorCommand(
      environment: environment,
      versionMetadataProvider: () async =>
          const DoctorVersionMetadata(latestVersion: packageVersion),
      arguments: const ['doctor'],
    );

    expect(result.exitCode, 0);
    expect(result.stdout.join('\n'), contains('[!] Sources'));
    expect(result.stdout.join('\n'), isNot(contains('Available: broken.')));
    expect(result.stdout.join('\n'), contains('broken:'));
    expect(
      result.stdout.join('\n'),
      contains('Source broken could not be read'),
    );
    expect(result.stderr, isEmpty);
  });

  test(
    'reports healthy OpenHarmony local tools and deployed emulators',
    () async {
      final environment = await createTestEnvironment();
      final devEco = await _writeDevEcoFixture(environment.homeDirectory);
      final deployed = await _writeEmulatorList(environment.homeDirectory);
      final imageRoot = Directory(
        '${environment.homeDirectory.path}/Huawei/Sdk',
      )..createSync(recursive: true);
      final doctorEnvironment = FluohEnvironment(
        homeDirectory: environment.homeDirectory,
        workingDirectory: environment.workingDirectory,
        processEnvironment: {
          ...environment.processEnvironment,
          'FLUOH_DEVECO_STUDIO': devEco.path,
          'FLUOH_OHOS_EMULATOR_DEPLOYED': deployed.path,
          'FLUOH_HARMONYOS_SDK_ROOT': imageRoot.path,
        },
      );

      final result = await _runDoctorCommand(
        environment: doctorEnvironment,
        versionMetadataProvider: () async =>
            const DoctorVersionMetadata(latestVersion: packageVersion),
        arguments: const ['doctor', '--platform', 'ohos'],
      );

      expect(result.exitCode, 0);
      expect(
        result.stdout.join('\n'),
        contains(
          '[✓] OpenHarmony toolchain - develop for OHOS devices (DevEco Studio 5.0.0)',
        ),
      );
      expect(result.stdout.join('\n'), isNot(contains('1 emulator')));
      expect(
        _normalizeOutput(result.stdout.join('\n')),
        contains('DevEco Studio 5.0.0 at'),
      );
      expect(
        _normalizeOutput(result.stdout.join('\n')),
        contains('home/DevEco-Studio.app'),
      );
      expect(result.stdout.join('\n'), contains('OpenHarmony SDK 5.0.1 at'));
      expect(
        _normalizeOutput(result.stdout.join('\n')),
        contains('hap-sign-tool at'),
      );
      expect(result.stdout.join('\n'), contains('hdc 1.2.3 at'));
      expect(
        _normalizeOutput(result.stdout.join('\n')),
        contains('Emulator at'),
      );
      expect(
        result.stdout.join('\n'),
        contains('Local emulators: Huawei_Phone'),
      );
      expect(result.stderr, isEmpty);
    },
  );

  test('reports the current CLI version and available upgrades', () async {
    final environment = await createTestEnvironment();
    final result = await _runDoctorCommand(
      environment: environment,
      versionMetadataProvider: () async =>
          const DoctorVersionMetadata(latestVersion: _newerVersion),
      arguments: const ['doctor'],
    );

    expect(result.exitCode, 0);
    expect(
      result.stdout.join('\n'),
      contains('[!] fluoh ($packageVersion, on '),
    );
    expect(
      result.stdout,
      contains('    • Upgrade available: $_newerVersion; run `fluoh upgrade`'),
    );
    expect(result.stderr, isEmpty);
  });

  test('reports when the CLI is already up to date', () async {
    final environment = await createTestEnvironment();
    final result = await _runDoctorCommand(
      environment: environment,
      versionMetadataProvider: () async => const DoctorVersionMetadata(
        latestVersion: packageVersion,
        currentVersionPublished: _currentVersionPublished,
      ),
      arguments: const ['doctor'],
    );

    expect(result.exitCode, 0);
    expect(
      result.stdout.join('\n'),
      contains('[✓] fluoh ($packageVersion, on '),
    );
    expect(
      result.stdout,
      contains('    • Installed with dart pub global activate.'),
    );
    expect(
      result.stdout,
      contains('    • Current version published: $_currentVersionPublished'),
    );
    expect(result.stdout, contains('    • Up to date'));
    expect(result.stderr, isEmpty);
  });

  test('reports when the latest CLI version cannot be checked', () async {
    final environment = await createTestEnvironment();
    final result = await _runDoctorCommand(
      environment: environment,
      versionMetadataProvider: () async => null,
      arguments: const ['doctor'],
    );

    expect(result.exitCode, 0);
    expect(
      result.stdout.join('\n'),
      contains('[✓] fluoh ($packageVersion, on '),
    );
    expect(
      result.stdout,
      contains('    • Installed with dart pub global activate.'),
    );
    expect(
      result.stdout,
      contains('    • Could not check the latest version from pub.dev.'),
    );
    expect(result.stderr, isEmpty);
  });

  test('rejects details and verbose aliases', () async {
    final environment = await createTestEnvironment();
    final detailsStdout = <String>[];
    final detailsStderr = <String>[];
    final shortStdout = <String>[];
    final shortStderr = <String>[];
    final longStdout = <String>[];
    final longStderr = <String>[];

    final detailsExitCode = await runFluoh(
      const ['doctor', '--details'],
      environment: environment,
      stdout: detailsStdout.add,
      stderr: detailsStderr.add,
    );
    final shortExitCode = await runFluoh(
      const ['doctor', '-v'],
      environment: environment,
      stdout: shortStdout.add,
      stderr: shortStderr.add,
    );
    final longExitCode = await runFluoh(
      const ['doctor', '--verbose'],
      environment: environment,
      stdout: longStdout.add,
      stderr: longStderr.add,
    );

    expect(detailsExitCode, 64);
    expect(detailsStdout, isEmpty);
    expect(
      detailsStderr.join('\n'),
      contains('Could not find an option named "--details".'),
    );
    expect(shortExitCode, 64);
    expect(shortStdout, isEmpty);
    expect(
      shortStderr.join('\n'),
      contains('Could not find an option or flag "-v".'),
    );
    expect(longExitCode, 64);
    expect(longStdout, isEmpty);
    expect(
      longStderr.join('\n'),
      contains('Could not find an option named "--verbose".'),
    );
  });

  test('colors doctor check headings when enabled', () async {
    final environment = await createTestEnvironment();
    await writeFlutterProjectFixture(environment.workingDirectory);
    final result = await _runDoctorCommand(
      environment: environment,
      versionMetadataProvider: () async =>
          const DoctorVersionMetadata(latestVersion: packageVersion),
      enableColor: true,
      arguments: const ['doctor', '--project'],
    );

    expect(result.exitCode, 0);
    expect(
      result.stdout.join('\n'),
      contains('\u001b[32m[✓]\u001b[0m fluoh ($packageVersion, on '),
    );
    expect(
      result.stdout.join('\n'),
      contains('\u001b[33m[!]\u001b[0m Flutter project'),
    );
    expect(
      result.stdout.join('\n'),
      contains(
        '    \u001b[32m•\u001b[0m \u001b[1mDetected Flutter project\u001b[0m',
      ),
    );
    expect(
      result.stdout.join('\n'),
      contains(
        '    \u001b[33m•\u001b[0m \u001b[1mNo FlutterOH SDK selected\u001b[0m',
      ),
    );
    expect(result.stderr, isEmpty);
  });

  test('parses the current version release date from pub.dev metadata', () {
    final metadata = parseFluohVersionMetadata({
      'latest': {'version': _newerVersion},
      'versions': [
        {'version': '0.0.0', 'published': '2026-04-01T08:00:00.000Z'},
        {
          'version': packageVersion,
          'published': '${_currentVersionPublished}T09:30:00.000Z',
        },
      ],
    });

    expect(metadata?.latestVersion, _newerVersion);
    expect(metadata?.currentVersionPublished, _currentVersionPublished);
  });
}

Future<_DoctorRunResult> _runDoctorCommand({
  required FluohEnvironment environment,
  required DoctorVersionMetadataProvider versionMetadataProvider,
  Uri? scriptUri,
  bool enableColor = false,
  List<String> arguments = const ['doctor'],
}) async {
  final stdout = <String>[];
  final stderr = <String>[];
  final commandEnvironment = FluohEnvironment(
    homeDirectory: environment.homeDirectory,
    workingDirectory: environment.workingDirectory,
    processEnvironment: {
      ...environment.processEnvironment,
      if (!environment.processEnvironment.containsKey('FLUOH_DEVECO_STUDIO'))
        'FLUOH_DEVECO_STUDIO':
            '${environment.homeDirectory.path}/missing/DevEco-Studio.app',
    },
  );
  final runner = CommandRunner<int>('fluoh', 'test')
    ..addCommand(
      DoctorCommand(
        environment: commandEnvironment,
        stdout: stdout.add,
        versionMetadataProvider: versionMetadataProvider,
        scriptUriProvider: () =>
            scriptUri ??
            Uri.file(
              '/home/example/.pub-cache/global_packages/fluoh/bin/fluoh.dart',
            ),
        enableColor: enableColor,
      ),
    );

  final exitCode = await runner.run(arguments);
  return _DoctorRunResult(exitCode ?? 0, stdout, stderr);
}

Future<Directory> _writeDevEcoFixture(Directory root) async {
  final devEco = Directory('${root.path}/DevEco-Studio.app');
  final toolchains = Directory(
    '${devEco.path}/Contents/sdk/default/openharmony/toolchains',
  );
  final lib = Directory('${toolchains.path}/lib');
  final jbr = Directory('${devEco.path}/Contents/jbr/Contents/Home/bin');
  final node = Directory('${devEco.path}/Contents/tools/node/bin');
  final emulatorDirectory = Directory('${devEco.path}/Contents/tools/emulator');
  await lib.create(recursive: true);
  await jbr.create(recursive: true);
  await node.create(recursive: true);
  await emulatorDirectory.create(recursive: true);
  await File('${devEco.path}/Contents/Info.plist').writeAsString('''
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
  <key>CFBundleShortVersionString</key>
  <string>5.0.0</string>
</dict>
</plist>
''');
  await File(
    '${devEco.path}/Contents/sdk/default/openharmony/oh-uni-package.json',
  ).writeAsString('{"version":"5.0.1"}');
  for (final path in [
    '${lib.path}/hap-sign-tool.jar',
    '${lib.path}/OpenHarmony.p12',
    '${lib.path}/OpenHarmonyProfileDebug.pem',
    '${jbr.path}/java',
    '${jbr.path}/keytool',
    '${node.path}/node',
    '${toolchains.path}/hdc',
    '${emulatorDirectory.path}/Emulator',
  ]) {
    await File(path).writeAsString('');
  }
  await _writeExecutable(File('${toolchains.path}/hdc'), '''
if [ "\$1" = "-v" ]; then
  printf "1.2.3\\n"
  exit 0
fi
exit 0
''');
  return devEco;
}

Future<Directory> _writeEmulatorList(Directory root) async {
  final deployed = Directory('${root.path}/deployed');
  await Directory('${deployed.path}/Huawei_Phone').create(recursive: true);
  await File(
    '${deployed.path}/Huawei_Phone/config.ini',
  ).writeAsString('name=Huawei_Phone\n');
  await File('${deployed.path}/lists.json').writeAsString('''
[
  {"name": "Huawei_Phone", "path": "${deployed.path}/Huawei_Phone"}
]
''');
  return deployed;
}

Future<Directory> _writeAndroidSdkFixture(Directory root) async {
  final sdk = Directory('${root.path}/android-sdk');
  await Directory('${sdk.path}/platforms/android-36').create(recursive: true);
  await Directory('${sdk.path}/build-tools/35.0.1').create(recursive: true);
  await Directory('${sdk.path}/licenses').create(recursive: true);
  await File(
    '${sdk.path}/licenses/android-sdk-license',
  ).writeAsString('license-hash\n');
  await _writeExecutable(File('${sdk.path}/platform-tools/adb'), '''
if [ "\$1" = "version" ]; then
  printf "Android Debug Bridge version 1.0.41\\n"
  exit 0
fi
if [ "\$1" = "devices" ]; then
  printf "List of devices attached\\nemulator-5554 device product:sdk_gphone model:Pixel_35 device:generic_x86\\n"
  exit 0
fi
exit 0
''');
  await _writeExecutable(File('${sdk.path}/emulator/emulator'), '''
if [ "\$1" = "-version" ]; then
  printf "Android emulator version 34.2.0.0\\n"
  exit 0
fi
if [ "\$1" = "-list-avds" ]; then
  printf "Pixel_35\\n"
  exit 0
fi
exit 0
''');
  await _writeExecutable(
    File('${sdk.path}/cmdline-tools/latest/bin/avdmanager'),
    '''
if [ "\$1" = "--version" ]; then
  printf "12.0\\n"
  exit 0
fi
exit 0
''',
  );
  return sdk;
}

Future<void> _writeExecutable(File file, String script) async {
  await file.parent.create(recursive: true);
  await file.writeAsString('#!/bin/sh\n$script');
  final result = await Process.run('chmod', ['+x', file.path]);
  if (result.exitCode != 0) {
    fail('chmod failed: ${result.stderr}');
  }
}

class _DoctorRunResult {
  const _DoctorRunResult(this.exitCode, this.stdout, this.stderr);

  final int exitCode;
  final List<String> stdout;
  final List<String> stderr;
}

void _expectInOrder(String text, List<String> needles) {
  var previous = -1;
  for (final needle in needles) {
    final index = text.indexOf(needle);
    expect(index, isNonNegative, reason: 'Missing "$needle" in output.');
    expect(index, greaterThan(previous), reason: 'Expected "$needle" later.');
    previous = index;
  }
}

String _normalizeOutput(String value) {
  return value
      .replaceAll(RegExp(r'(?<=[/-])\s+'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
