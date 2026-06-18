part of 'doctor_command_test.dart';

void _registerDoctorCommandPlatformTests() {
  test('doctor JSON includes structured connected device targets', () async {
    final environment = await createTestEnvironment();
    final androidSdk = await _writeAndroidSdkFixture(environment.homeDirectory);
    await _writeExecutable(File('${androidSdk.path}/platform-tools/adb'), '''
if [ "\$1" = "version" ]; then
  printf "Android Debug Bridge version 1.0.41\\n"
  exit 0
fi
if [ "\$1" = "devices" ]; then
  printf "List of devices attached\\nshort-id device model:A\\nvery-long-device-id device model:Pixel_35\\n"
  exit 0
fi
exit 0
''');
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
      processEnvironment: _androidDoctorEnvironment(
        environment,
        androidSdk,
        javaHome,
      ),
    );

    final result = await _runDoctorCommand(
      environment: doctorEnvironment,
      versionMetadataProvider: () async =>
          const DoctorVersionMetadata(latestVersion: packageVersion),
      arguments: const ['doctor', '--platform', 'android', '--json'],
    );

    expect(result.exitCode, 0);
    final report = jsonDecode(result.stdout.single) as Map<String, Object?>;
    expect(report, containsPair('schema', 1));
    expect(report, containsPair('command', 'doctor'));
    expect(report, containsPair('exitCode', 0));
    expect(report, containsPair('project', false));
    final checks = (report['checks'] as List<Object?>)
        .cast<Map<String, Object?>>();
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
    expect(checks.where((check) => check['group'] == 'project'), isEmpty);
    final connected = checks.firstWhere(
      (check) => check['id'] == 'connected.devices',
    );
    final data = connected['data'] as Map<String, Object?>;
    final targets = (data['targets'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(
      targets,
      contains(
        allOf(
          containsPair('name', 'A (mobile)'),
          containsPair('id', 'short-id'),
          containsPair('platform', 'android'),
          containsPair('summary', 'device'),
        ),
      ),
    );
    expect(result.stderr, isEmpty);
  });

  test('doctor connected device rows are not auto-wrapped', () async {
    final environment = await createTestEnvironment();
    final androidSdk = await _writeAndroidSdkFixture(environment.homeDirectory);
    final longId = 'android-${'x' * 120}';
    await _writeExecutable(File('${androidSdk.path}/platform-tools/adb'), '''
if [ "\$1" = "version" ]; then
  printf "Android Debug Bridge version 1.0.41\\n"
  exit 0
fi
if [ "\$1" = "devices" ]; then
  printf "List of devices attached\\n$longId device model:Pixel_8_Pro_Maximum_Length\\n"
  exit 0
fi
exit 0
''');
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
      processEnvironment: _androidDoctorEnvironment(
        environment,
        androidSdk,
        javaHome,
      ),
    );

    final result = await _runDoctorCommand(
      environment: doctorEnvironment,
      versionMetadataProvider: () async =>
          const DoctorVersionMetadata(latestVersion: packageVersion),
      arguments: const ['doctor', '--platform', 'android'],
    );

    expect(result.exitCode, 0);
    expect(
      result.stdout,
      contains(
        contains(
          'Pixel 8 Pro Maximum Length (mobile) • $longId • android • device',
        ),
      ),
    );
    expect(result.stderr, isEmpty);
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
    expect(_normalizeOutput(result.stdout.join('\n')), contains('Xcode at'));
    expect(
      _normalizeOutput(result.stdout.join('\n')),
      contains('home/Xcode.app'),
    );
    expect(result.stdout.join('\n'), contains('Xcode 16.2'));
    expect(result.stdout.join('\n'), contains('Build 16C5032a'));
    expect(result.stdout.join('\n'), contains('CocoaPods version 1.16.2'));
    expect(result.stderr, isEmpty);
  });

  test('reports macOS native tooling details in plain output', () async {
    final environment = await createTestEnvironment();
    final xcode = Directory('${environment.homeDirectory.path}/Xcode.app');
    await xcode.create(recursive: true);
    final xcrun = File('${environment.homeDirectory.path}/bin/xcrun');
    await _writeExecutable(xcrun, '''
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
    final doctorEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: environment.workingDirectory,
      processEnvironment: {
        ...environment.processEnvironment,
        'DEVELOPER_DIR': xcode.path,
        'FLUOH_XCRUN': xcrun.path,
      },
    );

    final result = await _runDoctorCommand(
      environment: doctorEnvironment,
      versionMetadataProvider: () async =>
          const DoctorVersionMetadata(latestVersion: packageVersion),
      arguments: const ['doctor', '--platform', 'macos'],
    );

    expect(result.exitCode, 0);
    expect(_normalizeOutput(result.stdout.join('\n')), contains('Xcode at'));
    expect(
      _normalizeOutput(result.stdout.join('\n')),
      contains('home/Xcode.app'),
    );
    expect(result.stdout.join('\n'), contains('Xcode 16.2'));
    expect(result.stdout.join('\n'), contains('Build 16C5032a'));
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
      expect(report, containsPair('schema', 1));
      expect(report, containsPair('command', 'doctor'));
      expect(report, containsPair('ok', false));
      expect(report, containsPair('exitCode', 1));
      expect(report, containsPair('project', true));
      expect(report['issueCount'], isNonZero);
      expect(report, containsPair('state', 'blocked'));
      final nextAction = report['nextAction'] as Map<String, Object?>;
      expect(nextAction, containsPair('type', 'blocked'));
      expect(nextAction, containsPair('phase', 'doctor'));
      expect(nextAction, containsPair('reason', 'doctor_warnings'));
      expect(
        nextAction,
        containsPair('rerunCommand', 'fluoh doctor --project --json --strict'),
      );
      final failingChecks = nextAction['failingChecks'] as List<Object?>;
      expect(
        failingChecks,
        contains(
          allOf(
            containsPair('id', 'project.flutter'),
            containsPair('title', 'Flutter project'),
          ),
        ),
      );
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

  test('checks only selected project platform directories', () async {
    final environment = await createTestEnvironment();
    await writeFlutterProjectFixture(environment.workingDirectory);
    await Directory(
      '${environment.workingDirectory.path}/android',
    ).create(recursive: true);

    final result = await _runDoctorCommand(
      environment: environment,
      versionMetadataProvider: () async =>
          const DoctorVersionMetadata(latestVersion: packageVersion),
      arguments: const [
        'doctor',
        '--project',
        '--platform',
        'android',
        '--json',
      ],
    );

    expect(result.exitCode, 0);
    final report = jsonDecode(result.stdout.single) as Map<String, Object?>;
    final checks = report['checks'] as List<Object?>;
    final projectCheck = checks.cast<Map<String, Object?>>().singleWhere(
      (check) => check['id'] == 'project.flutter',
    );

    expect(projectCheck, containsPair('status', 'warning'));
    expect(
      projectCheck['details'],
      contains('android platform directory exists'),
    );
    expect(
      projectCheck['details'],
      isNot(contains('Missing ohos platform directory')),
    );
    expect(
      projectCheck['details'],
      isNot(contains('Missing ios platform directory')),
    );
    expect(
      projectCheck['data'],
      containsPair(
        'platformDirectories',
        containsPair('android', {'path': 'android', 'exists': true}),
      ),
    );
    expect(result.stderr, isEmpty);
  });

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
    expect(result.stdout.join('\n'), contains('broken:'));
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
        contains('[✓] OpenHarmony toolchain - develop for OHOS devices'),
      );
      expect(
        _normalizeOutput(result.stdout.join('\n')),
        contains('OpenHarmony SDK version 5.0.1'),
      );
      expect(
        RegExp(
          'OpenHarmony SDK version 5\\.0\\.1',
        ).allMatches(_normalizeOutput(result.stdout.join('\n'))).length,
        1,
      );
      expect(
        _normalizeOutput(result.stdout.join('\n')),
        contains('OpenHarmony SDK at'),
      );
      expect(
        result.stdout.join('\n'),
        anyOf(contains('hdc version 1.2.3'), contains('hdc found')),
      );
      expect(result.stdout.join('\n'), contains('Emulator version 6.0.2.200'));
      expect(result.stdout.join('\n'), isNot(contains('Emulator found')));
      expect(result.stderr, isEmpty);
    },
  );

  test('warns when OpenHarmony emulator binary is missing', () async {
    final environment = await createTestEnvironment();
    final devEco = await _writeDevEcoFixture(environment.homeDirectory);
    await File('${devEco.path}/Contents/tools/emulator/Emulator').delete();
    final doctorEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: environment.workingDirectory,
      processEnvironment: {
        ...environment.processEnvironment,
        'FLUOH_DEVECO_STUDIO': devEco.path,
      },
    );

    final result = await _runDoctorCommand(
      environment: doctorEnvironment,
      versionMetadataProvider: () async =>
          const DoctorVersionMetadata(latestVersion: packageVersion),
      arguments: const ['doctor', '--platform', 'ohos', '--json'],
    );

    expect(result.exitCode, 0);
    final report = jsonDecode(result.stdout.single) as Map<String, Object?>;
    final checks = (report['checks'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final ohos = checks.firstWhere((check) => check['id'] == 'ohos.toolchain');
    expect(ohos, containsPair('status', 'warning'));
    final details = (ohos['details'] as List<Object?>).join('\n');
    expect(details, contains('Emulator was not found at'));
    final data = ohos['data'] as Map<String, Object?>;
    final tools = data['tools'] as Map<String, Object?>;
    expect(tools.keys, unorderedEquals(['openHarmonySdk', 'hdc', 'emulator']));
    expect(
      tools['emulator'],
      allOf(isA<Map<String, Object?>>(), containsPair('missing', true)),
    );
    expect(result.stderr, isEmpty);
  });
}
