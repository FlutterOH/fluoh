part of 'platform_environment.dart';

Future<PlatformDoctorReport> _inspectAndroid(
  FluohEnvironment environment,
) async {
  final env = environment.processEnvironment;
  final sdkRoot = _androidSdkRoot(env);
  final adb = await _findExecutable(
    environment: env,
    environmentKey: 'FLUOH_ANDROID_ADB',
    candidates: [if (sdkRoot != null) '${sdkRoot.path}/platform-tools/adb'],
    fallbackName: 'adb',
  );
  final emulator = await _findExecutable(
    environment: env,
    environmentKey: 'FLUOH_ANDROID_EMULATOR',
    candidates: [if (sdkRoot != null) '${sdkRoot.path}/emulator/emulator'],
    fallbackName: 'emulator',
  );
  final avdManager = await _findExecutable(
    environment: env,
    environmentKey: 'FLUOH_ANDROID_AVDMANAGER',
    candidates: [
      if (sdkRoot != null)
        '${sdkRoot.path}/cmdline-tools/latest/bin/avdmanager',
      if (sdkRoot != null) '${sdkRoot.path}/tools/bin/avdmanager',
    ],
    fallbackName: 'avdmanager',
  );
  final java = await _findExecutable(
    environment: env,
    environmentKey: 'FLUOH_JAVA',
    candidates: [
      ..._androidStudioBundledJavaCandidates(env),
      if (_nonEmpty(env['JAVA_HOME'])) '${env['JAVA_HOME']!.trim()}/bin/java',
    ],
    fallbackName: 'java',
  );
  final adbVersion = await _toolVersion(
    adb,
    const ['version'],
    environment: env,
    parser: _adbVersion,
  );
  final emulatorVersion = await _toolVersion(
    emulator,
    const ['-version'],
    environment: env,
    parser: _androidEmulatorVersion,
  );
  final avdManagerVersion = await _toolVersion(avdManager, const [
    '--version',
  ], environment: env);
  final javaVersion =
      await _toolVersion(
        java,
        const ['-version'],
        environment: env,
        parser: _javaVersion,
      ) ??
      await _javaReleaseFileVersion(java);
  final androidPlatform = await _latestAndroidPlatform(sdkRoot);
  final buildToolsVersion = await _latestBuildToolsVersion(sdkRoot);
  final licensesAccepted = await _androidLicensesAccepted(sdkRoot);

  return PlatformDoctorReport(
    platform: FluohPlatform.android,
    checks: [
      PlatformToolCheck(
        id: 'android.sdk',
        label: 'Android SDK',
        ok: sdkRoot != null && await sdkRoot.exists(),
        message: sdkRoot == null
            ? 'ANDROID_SDK_ROOT or ANDROID_HOME is not set'
            : await sdkRoot.exists()
            ? 'Android SDK root exists'
            : 'Android SDK root does not exist',
        path: sdkRoot?.path,
        version: buildToolsVersion,
      ),
      PlatformToolCheck(
        id: 'android.platform',
        label: 'Android platform',
        ok: androidPlatform != null && buildToolsVersion != null,
        message: androidPlatform == null
            ? 'No Android platform package was found'
            : buildToolsVersion == null
            ? 'No Android build-tools package was found'
            : 'Android platform and build-tools were found',
        version: androidPlatform,
        details: _optionalDetail('buildTools', buildToolsVersion),
      ),
      _toolCheck(
        id: 'android.adb',
        label: 'adb',
        executable: adb,
        version: adbVersion,
        missingMessage: 'adb was not found in the Android SDK or PATH',
      ),
      _toolCheck(
        id: 'android.emulator',
        label: 'Android emulator',
        executable: emulator,
        version: emulatorVersion,
        missingMessage:
            'Android emulator was not found in the Android SDK or PATH',
      ),
      _toolCheck(
        id: 'android.avdmanager',
        label: 'avdmanager',
        executable: avdManager,
        version: avdManagerVersion,
        missingMessage:
            'avdmanager was not found; emulator creation may require Android Studio.',
      ),
      _toolCheck(
        id: 'android.java',
        label: 'Java',
        executable: java,
        version: javaVersion,
        missingMessage:
            'Java was not found in Android Studio, JAVA_HOME, or PATH',
        details: {
          if (java != null)
            'androidStudioBundledJdk': _isAndroidStudioBundledJdk(java.path),
        },
      ),
      PlatformToolCheck(
        id: 'android.licenses',
        label: 'Android licenses',
        ok: licensesAccepted == true,
        message: licensesAccepted == true
            ? 'All Android licenses accepted'
            : 'Android licenses were not found',
      ),
    ],
  );
}

Future<_AppleToolchain> _inspectAppleToolchain(Map<String, String> env) async {
  final xcrun = await _xcrun(env);
  final developerDir = await _xcodeDeveloperDirectory(env);
  final xcrunVersion = await _toolVersion(
    xcrun,
    const ['--version'],
    environment: env,
    parser: _xcrunVersion,
  );
  final xcodeBuild = xcrun == null
      ? null
      : await _runTool(xcrun.path, const [
          'xcodebuild',
          '-version',
        ], environment: env);
  final xcodeOutput = xcodeBuild == null || xcodeBuild.exitCode != 0
      ? ''
      : '${xcodeBuild.stdout}\n${xcodeBuild.stderr}';
  return _AppleToolchain(
    xcrun: xcrun,
    developerDir: developerDir,
    xcrunVersion: xcrunVersion,
    xcodeVersion: xcodeOutput.isEmpty ? null : _xcodeVersion(xcodeOutput),
    xcodeBuildVersion: xcodeOutput.isEmpty
        ? null
        : _xcodeBuildVersion(xcodeOutput),
  );
}

class _AppleToolchain {
  const _AppleToolchain({
    required this.xcrun,
    required this.developerDir,
    required this.xcrunVersion,
    required this.xcodeVersion,
    required this.xcodeBuildVersion,
  });

  final io.File? xcrun;
  final String? developerDir;
  final String? xcrunVersion;
  final String? xcodeVersion;
  final String? xcodeBuildVersion;
}

Future<PlatformDoctorReport> _inspectIos(
  FluohEnvironment environment, {
  _AppleToolchain? appleToolchain,
}) async {
  final env = environment.processEnvironment;
  final apple = appleToolchain ?? await _inspectAppleToolchain(env);
  final xcrun = apple.xcrun;
  final simctl = xcrun == null
      ? _CommandRun(exitCode: 1, stdout: '', stderr: 'xcrun not found')
      : await _runTool(xcrun.path, const [
          'simctl',
          'list',
          'devices',
          'available',
          '--json',
        ], environment: env);
  final cocoaPods = await _findExecutable(
    environment: env,
    environmentKey: 'FLUOH_COCOAPODS',
    candidates: const [],
    fallbackName: 'pod',
  );
  final cocoaPodsVersion = await _toolVersion(cocoaPods, const [
    '--version',
  ], environment: env);

  return PlatformDoctorReport(
    platform: FluohPlatform.ios,
    checks: [
      _toolCheck(
        id: 'ios.xcrun',
        label: 'xcrun',
        executable: xcrun,
        version: apple.xcrunVersion,
        missingMessage:
            'xcrun was not found; install Xcode command line tools.',
      ),
      PlatformToolCheck(
        id: 'ios.xcode',
        label: 'Xcode',
        ok: apple.developerDir != null,
        message: apple.developerDir == null
            ? 'Xcode developer directory was not found'
            : 'Xcode developer directory exists',
        path: apple.developerDir,
        version: apple.xcodeVersion,
        details: _optionalDetail('buildVersion', apple.xcodeBuildVersion),
      ),
      PlatformToolCheck(
        id: 'ios.simctl',
        label: 'simctl',
        ok: simctl.exitCode == 0,
        message: simctl.exitCode == 0
            ? 'simctl can list available simulators'
            : 'simctl could not list available simulators',
        command: xcrun == null
            ? null
            : [xcrun.path, 'simctl', 'list', 'devices', 'available', '--json'],
      ),
      _toolCheck(
        id: 'ios.cocoapods',
        label: 'CocoaPods',
        executable: cocoaPods,
        version: cocoaPodsVersion,
        missingMessage:
            'CocoaPods was not found; iOS plugin builds may require it.',
      ),
    ],
  );
}

Future<PlatformDoctorReport> _inspectMacos(
  FluohEnvironment environment, {
  _AppleToolchain? appleToolchain,
}) async {
  final apple =
      appleToolchain ??
      await _inspectAppleToolchain(environment.processEnvironment);

  return PlatformDoctorReport(
    platform: FluohPlatform.macos,
    checks: [
      PlatformToolCheck(
        id: 'macos.host',
        label: 'macOS host',
        ok: io.Platform.isMacOS,
        message: io.Platform.isMacOS
            ? 'Running on macOS'
            : 'macOS desktop builds require a macOS host',
        version: normalizeAppleOperatingSystemVersion(
          io.Platform.operatingSystemVersion,
        ),
      ),
      _toolCheck(
        id: 'macos.xcrun',
        label: 'xcrun',
        executable: apple.xcrun,
        version: apple.xcrunVersion,
        missingMessage:
            'xcrun was not found; install Xcode command line tools.',
      ),
      PlatformToolCheck(
        id: 'macos.xcode',
        label: 'Xcode',
        ok: apple.developerDir != null,
        message: apple.developerDir == null
            ? 'Xcode developer directory was not found'
            : 'Xcode developer directory exists',
        path: apple.developerDir,
        version: apple.xcodeVersion,
        details: _optionalDetail('buildVersion', apple.xcodeBuildVersion),
      ),
    ],
  );
}

Future<PlatformDoctorReport> _inspectLinux(FluohEnvironment environment) async {
  final env = environment.processEnvironment;
  final clang = await _findExecutable(
    environment: env,
    environmentKey: 'FLUOH_LINUX_CLANG',
    candidates: const [],
    fallbackName: 'clang++',
  );
  final cmake = await _findExecutable(
    environment: env,
    environmentKey: 'FLUOH_LINUX_CMAKE',
    candidates: const [],
    fallbackName: 'cmake',
  );
  final ninja = await _findExecutable(
    environment: env,
    environmentKey: 'FLUOH_LINUX_NINJA',
    candidates: const [],
    fallbackName: 'ninja',
  );
  final pkgConfig = await _findExecutable(
    environment: env,
    environmentKey: 'FLUOH_LINUX_PKG_CONFIG',
    candidates: const [],
    fallbackName: 'pkg-config',
  );
  return PlatformDoctorReport(
    platform: FluohPlatform.linux,
    checks: [
      PlatformToolCheck(
        id: 'linux.host',
        label: 'Linux host',
        ok: io.Platform.isLinux,
        message: io.Platform.isLinux
            ? 'Running on Linux'
            : 'Linux desktop builds require a Linux host',
        version: io.Platform.isLinux
            ? io.Platform.operatingSystemVersion.trim()
            : null,
      ),
      _toolCheck(
        id: 'linux.clang',
        label: 'clang++',
        executable: clang,
        version: await _toolVersion(clang, const [
          '--version',
        ], environment: env),
        missingMessage:
            'clang++ was not found; Linux desktop builds require a C++ compiler.',
      ),
      _toolCheck(
        id: 'linux.cmake',
        label: 'CMake',
        executable: cmake,
        version: await _toolVersion(cmake, const [
          '--version',
        ], environment: env),
        missingMessage:
            'CMake was not found; Linux desktop builds require CMake.',
      ),
      _toolCheck(
        id: 'linux.ninja',
        label: 'Ninja',
        executable: ninja,
        version: await _toolVersion(ninja, const [
          '--version',
        ], environment: env),
        missingMessage:
            'Ninja was not found; Linux desktop builds require Ninja.',
      ),
      _toolCheck(
        id: 'linux.pkg-config',
        label: 'pkg-config',
        executable: pkgConfig,
        version: await _toolVersion(pkgConfig, const [
          '--version',
        ], environment: env),
        missingMessage:
            'pkg-config was not found; Linux plugin builds may require it.',
      ),
    ],
  );
}

Future<PlatformDoctorReport> _inspectWindows(
  FluohEnvironment environment,
) async {
  final env = environment.processEnvironment;
  final cl = await _findExecutable(
    environment: env,
    environmentKey: 'FLUOH_WINDOWS_CL',
    candidates: const [],
    fallbackName: 'cl',
  );
  final cmake = await _findExecutable(
    environment: env,
    environmentKey: 'FLUOH_WINDOWS_CMAKE',
    candidates: const [],
    fallbackName: 'cmake',
  );
  final ninja = await _findExecutable(
    environment: env,
    environmentKey: 'FLUOH_WINDOWS_NINJA',
    candidates: const [],
    fallbackName: 'ninja',
  );
  return PlatformDoctorReport(
    platform: FluohPlatform.windows,
    checks: [
      PlatformToolCheck(
        id: 'windows.host',
        label: 'Windows host',
        ok: io.Platform.isWindows,
        message: io.Platform.isWindows
            ? 'Running on Windows'
            : 'Windows desktop builds require a Windows host',
        version: io.Platform.isWindows
            ? io.Platform.operatingSystemVersion.trim()
            : null,
      ),
      _toolCheck(
        id: 'windows.cl',
        label: 'MSVC cl.exe',
        executable: cl,
        version: await _toolVersion(cl, const [], environment: env),
        missingMessage:
            'MSVC cl.exe was not found; install Visual Studio with Desktop development with C++.',
      ),
      _toolCheck(
        id: 'windows.cmake',
        label: 'CMake',
        executable: cmake,
        version: await _toolVersion(cmake, const [
          '--version',
        ], environment: env),
        missingMessage:
            'CMake was not found; Windows desktop builds require CMake.',
      ),
      _toolCheck(
        id: 'windows.ninja',
        label: 'Ninja',
        executable: ninja,
        version: await _toolVersion(ninja, const [
          '--version',
        ], environment: env),
        missingMessage:
            'Ninja was not found; Windows desktop builds require Ninja.',
      ),
    ],
  );
}

Future<PlatformDoctorReport> _inspectWeb(FluohEnvironment environment) async {
  final env = environment.processEnvironment;
  final chrome = await _findWebChromeExecutable(env);
  return PlatformDoctorReport(
    platform: FluohPlatform.web,
    checks: [
      const PlatformToolCheck(
        id: 'web.build',
        label: 'Flutter web build',
        ok: true,
        message: 'Flutter web builds do not require a native host toolchain',
      ),
      PlatformToolCheck(
        id: 'web.chrome',
        label: 'Chrome',
        ok: chrome != null,
        message: chrome == null
            ? 'Chrome was not found; install Chrome for browser-specific web runs.'
            : 'Chrome was found for browser-specific smoke runs',
        path: chrome?.path,
        version: await _toolVersion(chrome, const [
          '--version',
        ], environment: env),
        details: {
          'requiredFor': 'browser-specific run smoke',
          'available': chrome != null,
        },
      ),
    ],
  );
}

Future<PlatformDoctorReport> _inspectOhos(FluohEnvironment environment) async {
  final checks = <PlatformToolCheck>[];
  try {
    final toolchain = await locateOhosToolchain(
      environment: environment.processEnvironment,
    );
    final openHarmonyVersion = await _openHarmonySdkVersion(
      toolchain.openHarmonySdk,
    );
    final hdcVersion = await _toolVersion(
      toolchain.hdc,
      const ['-v'],
      environment: environment.processEnvironment,
      parser: _ohosHdcVersion,
      timeout: const Duration(seconds: 5),
    );
    final emulatorVersion = await _toolVersion(
      toolchain.emulator,
      const ['-version'],
      environment: environment.processEnvironment,
      parser: _ohosEmulatorVersion,
      timeout: const Duration(seconds: 5),
    );
    checks.addAll([
      PlatformToolCheck(
        id: 'ohos.sdk',
        label: 'OpenHarmony SDK',
        ok: true,
        message: 'OpenHarmony SDK was found',
        path: toolchain.openHarmonySdk.path,
        version: openHarmonyVersion,
      ),
      _fileCheck(
        id: 'ohos.hdc',
        label: 'hdc',
        file: toolchain.hdc,
        missingMessage: 'hdc was not found in the OpenHarmony toolchain',
        version: hdcVersion,
      ),
      _fileCheck(
        id: 'ohos.emulator',
        label: 'Emulator',
        file: toolchain.emulator,
        missingMessage: 'Emulator was not found at ${toolchain.emulator.path}',
        version: emulatorVersion,
      ),
    ]);
  } on Object catch (error) {
    checks.add(
      PlatformToolCheck(
        id: 'ohos.toolchain',
        label: 'OpenHarmony toolchain',
        ok: false,
        message: error.toString(),
      ),
    );
  }
  return PlatformDoctorReport(platform: FluohPlatform.ohos, checks: checks);
}
