part of 'doctor_command_test.dart';

void _registerDoctorCommandEnvironmentTests() {
  test('reports full environment and project status with --project', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    await writeFlutterProjectFixture(environment.workingDirectory);
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'enable', 'fixture', source.path],
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
    expect(stdout, contains('    • Missing android platform directory'));
    expect(stdout, contains('    • Missing web platform directory'));
    if (Platform.isMacOS) {
      expect(stdout, contains('    • Missing ios platform directory'));
      expect(stdout, contains('    • Missing macos platform directory'));
    } else {
      expect(
        stdout.join('\n'),
        isNot(contains('Missing ios platform directory')),
      );
      expect(
        stdout.join('\n'),
        isNot(contains('Missing macos platform directory')),
      );
    }
    if (Platform.isLinux) {
      expect(stdout, contains('    • Missing linux platform directory'));
    } else {
      expect(
        stdout.join('\n'),
        isNot(contains('Missing linux platform directory')),
      );
    }
    if (Platform.isWindows) {
      expect(stdout, contains('    • Missing windows platform directory'));
    } else {
      expect(
        stdout.join('\n'),
        isNot(contains('Missing windows platform directory')),
      );
    }
    expect(stdout.join('\n'), contains('[!] Sources'));
    expect(_normalizeOutput(stdout.join('\n')), contains('fixture: file://'));
    expect(_normalizeOutput(stdout.join('\n')), contains('flutteroh: file://'));
    expect(stdout.join('\n'), contains('Android toolchain'));
    if (Platform.isMacOS) {
      expect(stdout.join('\n'), contains('Xcode - develop for iOS and macOS'));
      expect(
        stdout.join('\n'),
        isNot(contains('Xcode - develop for macOS desktop')),
      );
    } else {
      expect(
        stdout.join('\n'),
        isNot(contains('Xcode - develop for iOS and macOS')),
      );
    }
    expect(stdout.join('\n'), contains('Chrome - develop for the web'));
    expect(
      stdout.join('\n'),
      contains('[!] OpenHarmony toolchain - develop for OHOS devices'),
    );
    expect(stdout, contains('    • OpenHarmony SDK toolchains were not found'));
    expect(stdout.join('\n'), contains('Doctor found issues in '));
    expect(stdout.join('\n'), contains(' categories.'));
    _expectInOrder(stdout.join('\n'), [
      '[✓] fluoh ($packageVersion, on ',
      '[!] Sources',
      '[!] OpenHarmony toolchain - develop for OHOS devices',
      'Android toolchain',
      if (Platform.isMacOS) 'Xcode - develop for iOS and macOS',
      if (Platform.isLinux) 'Linux toolchain',
      'Chrome - develop for the web',
      if (Platform.isWindows) 'Windows toolchain',
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
    expect(result.stdout, contains('    • Missing android platform directory'));
    expect(result.stdout, contains('    • Missing web platform directory'));
    if (Platform.isMacOS) {
      expect(result.stdout, contains('    • Missing ios platform directory'));
      expect(result.stdout, contains('    • Missing macos platform directory'));
    } else {
      expect(
        result.stdout.join('\n'),
        isNot(contains('Missing ios platform directory')),
      );
      expect(
        result.stdout.join('\n'),
        isNot(contains('Missing macos platform directory')),
      );
    }
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
    expect(result.stdout.join('\n'), isNot(contains('[!] Flutter project')));
    expect(
      result.stdout.join('\n'),
      isNot(contains('[!] OHOS project platform')),
    );
    expect(result.stderr, isEmpty);
  });

  test(
    'default JSON checks only common and host-supported platforms',
    () async {
      final environment = await createTestEnvironment();

      final result = await _runDoctorCommand(
        environment: environment,
        versionMetadataProvider: () async =>
            const DoctorVersionMetadata(latestVersion: packageVersion),
        arguments: const ['doctor', '--json'],
      );

      expect(result.exitCode, 0);
      final report = jsonDecode(result.stdout.single) as Map<String, Object?>;
      expect(report['platforms'], _defaultHostPlatformNames());
      expect(report, isNot(contains('state')));
      expect(report, isNot(contains('nextAction')));
      expect(result.stderr, isEmpty);
    },
  );

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
    expect(result.stdout.join('\n'), contains('fixture:'));
    expect(result.stdout.join('\n'), contains('mirror:'));
    expect(result.stderr, isEmpty);
  });

  test('reports git warning when git exits non-zero', () async {
    final environment = await createTestEnvironment();
    final fakeBin = Directory('${environment.homeDirectory.path}/bin');
    await _writeExecutable(File('${fakeBin.path}/git'), '''
printf "xcrun: error: invalid active developer path\\n" >&2
exit 1
''');
    final doctorEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: environment.workingDirectory,
      processEnvironment: {
        ...environment.processEnvironment,
        'PATH': fakeBin.path,
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
    final checks = report['checks'] as List<Object?>;
    final fluohCheck = checks.cast<Map<String, Object?>>().firstWhere(
      (check) => check['id'] == 'fluoh.installation',
    );
    expect(fluohCheck, containsPair('status', 'warning'));
    expect(
      (fluohCheck['details'] as List<Object?>).join('\n'),
      contains('invalid active developer path'),
    );
    expect(result.stderr, isEmpty);
  });

  test('reports web Chrome tooling with only Chrome detail', () async {
    final environment = await createTestEnvironment();
    final chrome = File('${environment.homeDirectory.path}/bin/google-chrome');
    await _writeExecutable(chrome, '''
if [ "\$1" = "--version" ]; then
  printf "Google Chrome 149.0.7827.103\\n"
  exit 0
fi
exit 0
''');
    final doctorEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: environment.workingDirectory,
      processEnvironment: {
        ...environment.processEnvironment,
        'FLUOH_WEB_CHROME': chrome.path,
      },
    );

    final result = await _runDoctorCommand(
      environment: doctorEnvironment,
      versionMetadataProvider: () async =>
          const DoctorVersionMetadata(latestVersion: packageVersion),
      arguments: const ['doctor', '--platform', 'web'],
    );

    expect(result.exitCode, 0);
    final output = result.stdout.join('\n');
    expect(
      output,
      contains(
        '[✓] Chrome - develop for the web (Google Chrome 149.0.7827.103)',
      ),
    );
    expect(
      _normalizeOutput(output),
      contains(_normalizeOutput('    • Chrome at ${chrome.path}')),
    );
    expect(
      _normalizeOutput(output),
      contains(
        _normalizeOutput(
          'Chrome (web) • chrome • web-javascript • '
          'Google Chrome 149.0.7827.103',
        ),
      ),
    );
    expect(output, contains('[✓] Connected device (1 available)'));
    expect(output, isNot(contains('Web Server (web)')));
    expect(
      output,
      isNot(
        contains('Flutter web builds do not require a native host toolchain'),
      ),
    );
    expect(output, isNot(contains('chrome Google Chrome 149.0.7827.103')));
    expect(output, isNot(contains('Chrome Google Chrome 149.0.7827.103 at')));
    expect(result.stderr, isEmpty);
  });

  test('warns when web Chrome is missing', () async {
    final environment = await createTestEnvironment();
    final missingChrome =
        '${environment.homeDirectory.path}/bin/missing-chrome';
    final doctorEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: environment.workingDirectory,
      processEnvironment: {
        ...environment.processEnvironment,
        'FLUOH_WEB_CHROME': missingChrome,
      },
    );

    final result = await _runDoctorCommand(
      environment: doctorEnvironment,
      versionMetadataProvider: () async =>
          const DoctorVersionMetadata(latestVersion: packageVersion),
      arguments: const ['doctor', '--platform', 'web', '--json', '--strict'],
    );

    expect(result.exitCode, 1);
    final report = jsonDecode(result.stdout.single) as Map<String, Object?>;
    expect(report, containsPair('ok', false));
    expect(report, containsPair('exitCode', 1));
    final nextAction = report['nextAction'] as Map<String, Object?>;
    expect(nextAction, containsPair('type', 'blocked'));
    expect(
      nextAction,
      containsPair(
        'rerunCommand',
        'fluoh doctor --platform web --json --strict',
      ),
    );
    final checks = (report['checks'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final webToolchain = checks.firstWhere(
      (check) => check['id'] == 'web.toolchain',
    );
    expect(webToolchain, containsPair('title', 'Chrome - develop for the web'));
    expect(webToolchain, containsPair('status', 'warning'));
    final data = webToolchain['data'] as Map<String, Object?>;
    final toolChecks = (data['checks'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final chrome = toolChecks.firstWhere(
      (check) => check['id'] == 'web.chrome',
    );
    expect(chrome, containsPair('status', 'warning'));
    expect(
      chrome,
      containsPair(
        'message',
        'Chrome was not found; install Chrome for browser-specific web runs.',
      ),
    );
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
      _normalizeOutput(result.stdout.join('\n')),
      contains(
        _normalizeOutput(
          '[✓] Android toolchain - develop for Android devices (Android SDK version 35.0.1)',
        ),
      ),
    );
    expect(
      _normalizeOutput(result.stdout.join('\n')),
      contains('Android SDK at'),
    );
    expect(
      _normalizeOutput(result.stdout.join('\n')),
      contains('home/android-sdk'),
    );
    expect(
      File('${environment.workingDirectory.path}/fluoh.yaml').existsSync(),
      isFalse,
    );
    expect(result.stdout, contains('    • Emulator version 34.2.0.0'));
    expect(
      result.stdout,
      contains('    • Platform android-36, build-tools 35.0.1'),
    );
    expect(result.stdout.join('\n'), contains('Java binary at:'));
    expect(
      _normalizeOutput(result.stdout.join('\n')),
      contains('home/java/bin/java'),
    );
    expect(
      result.stdout.join('\n'),
      isNot(contains('To override the JDK path')),
    );
    expect(result.stdout, contains('    • Java version 17.0.9'));
    expect(result.stdout, contains('    • All Android licenses accepted'));
    expect(
      result.stdout.join('\n'),
      contains('[✓] Connected device (1 available)'),
    );
    expect(
      result.stdout.join('\n'),
      contains('Pixel 35 (mobile) • emulator-5554 • android • device'),
    );
    expect(result.stderr, isEmpty);
  });

  test('prefers Android Studio bundled Java for Android doctor', () async {
    final environment = await createTestEnvironment();
    final androidSdk = await _writeAndroidSdkFixture(environment.homeDirectory);
    final androidStudioJava = File(
      '${environment.homeDirectory.path}/Applications/Android Studio.app/'
      'Contents/jbr/Contents/Home/bin/java',
    );
    await _writeExecutable(androidStudioJava, '''
if [ "\$1" = "-version" ]; then
  printf 'openjdk version "21.0.3"\\nOpenJDK Runtime Environment (build 21.0.3+9)\\n' >&2
  exit 0
fi
exit 0
''');
    await File(
      '${androidStudioJava.parent.parent.path}/release',
    ).writeAsString('JAVA_VERSION="21.0.3"\n');
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
        'FLUOH_ANDROID_STUDIO':
            '${environment.homeDirectory.path}/Applications/Android Studio.app',
        'HOME': environment.homeDirectory.path,
        'JAVA_HOME': javaHome.path,
      },
    );

    final result = await _runDoctorCommand(
      environment: doctorEnvironment,
      versionMetadataProvider: () async =>
          const DoctorVersionMetadata(latestVersion: packageVersion),
      arguments: const ['doctor', '--platform', 'android'],
    );

    expect(result.exitCode, 0);
    final output = _normalizeOutput(result.stdout.join('\n'));
    expect(output, contains('Applications/Android Studio.app'));
    expect(output, isNot(contains('home/java/bin/java')));
    expect(output, isNot(contains('This is the JDK bundled with')));
    expect(
      output,
      anyOf(
        contains('Java version OpenJDK Runtime Environment (build 21.0.3+9)'),
        contains('Java version 21.0.3'),
      ),
    );
    expect(output, isNot(contains('To override the JDK path')));
    expect(result.stderr, isEmpty);
  });
}
