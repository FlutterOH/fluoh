part of 'platform_environment.dart';

/// Inspects native tooling for the requested workflow platforms.
Future<List<PlatformDoctorReport>> inspectPlatformEnvironment({
  required FluohEnvironment environment,
  required List<FluohPlatform> platforms,
}) async {
  final appleToolchain =
      platforms.contains(FluohPlatform.ios) &&
          platforms.contains(FluohPlatform.macos)
      ? await _inspectAppleToolchain(environment.processEnvironment)
      : null;
  return [
    for (final platform in platforms)
      switch (platform) {
        FluohPlatform.android => await _inspectAndroid(environment),
        FluohPlatform.ios => await _inspectIos(
          environment,
          appleToolchain: appleToolchain,
        ),
        FluohPlatform.linux => await _inspectLinux(environment),
        FluohPlatform.macos => await _inspectMacos(
          environment,
          appleToolchain: appleToolchain,
        ),
        FluohPlatform.ohos => await _inspectOhos(environment),
        FluohPlatform.web => await _inspectWeb(environment),
        FluohPlatform.windows => await _inspectWindows(environment),
      },
  ];
}

/// Lists connected device targets for the requested [platforms].
Future<List<PlatformTargetReport>> listPlatformDeviceReports({
  required FluohEnvironment environment,
  required List<FluohPlatform> platforms,
}) async {
  return [
    for (final platform in platforms)
      switch (platform) {
        FluohPlatform.android => await _listAndroidDevices(environment),
        FluohPlatform.ios => await _listIosDevices(environment),
        FluohPlatform.linux => _listLinuxDevices(environment),
        FluohPlatform.macos => await _listMacosDevices(environment),
        FluohPlatform.ohos => await _listOhosDevices(environment),
        FluohPlatform.web => await _listWebDevices(environment),
        FluohPlatform.windows => _listWindowsDevices(environment),
      },
  ];
}

/// Lists local emulator or simulator targets for the requested [platforms].
Future<List<PlatformTargetReport>> listPlatformEmulatorReports({
  required FluohEnvironment environment,
  required List<FluohPlatform> platforms,
}) async {
  return [
    for (final platform in platforms)
      switch (platform) {
        FluohPlatform.android => await _listAndroidEmulators(environment),
        FluohPlatform.ios => await _listIosDevices(
          environment,
          kind: 'emulator',
        ),
        FluohPlatform.linux => _listDesktopEmulators(FluohPlatform.linux),
        FluohPlatform.macos => _listMacosEmulators(),
        FluohPlatform.ohos => await _listOhosEmulators(environment),
        FluohPlatform.web => _listNoEmulators(FluohPlatform.web),
        FluohPlatform.windows => _listDesktopEmulators(FluohPlatform.windows),
      },
  ];
}

/// Starts an emulator or simulator for one platform.
Future<PlatformStartResult> startPlatformEmulator({
  required FluohEnvironment environment,
  required FluohPlatform platform,
  required String? emulator,
}) async {
  return switch (platform) {
    FluohPlatform.android => _startAndroidEmulator(environment, emulator),
    FluohPlatform.ios => _startIosSimulator(environment, emulator),
    FluohPlatform.linux => _startDesktopEmulator(FluohPlatform.linux),
    FluohPlatform.macos => _startMacosEmulator(emulator),
    FluohPlatform.ohos => _startOhosEmulator(environment, emulator),
    FluohPlatform.web => _startNoEmulator(FluohPlatform.web, emulator),
    FluohPlatform.windows => _startDesktopEmulator(FluohPlatform.windows),
  };
}
