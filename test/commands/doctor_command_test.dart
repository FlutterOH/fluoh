import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:fluoh/fluoh.dart';
import 'package:fluoh/src/doctor/doctor_command.dart';
import 'package:test/test.dart';

import '../helpers/fluoh_command_context.dart';

part 'doctor_command_environment_part.dart';
part 'doctor_command_platform_part.dart';
part 'doctor_command_version_part.dart';

const _currentVersionPublished = '2026-05-01';
const _newerVersion = '99.0.0';

void main() {
  _registerDoctorCommandEnvironmentTests();
  _registerDoctorCommandPlatformTests();
  _registerDoctorCommandVersionTests();
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
  final processEnvironment = {...environment.processEnvironment};
  if (!processEnvironment.containsKey('PATH')) {
    final pathFixture = await _writeDoctorPathFixture(
      environment.homeDirectory,
    );
    processEnvironment['PATH'] = pathFixture.path;
  }
  processEnvironment.putIfAbsent(
    'FLUOH_DEVECO_STUDIO',
    () => '${environment.homeDirectory.path}/missing/DevEco-Studio.app',
  );
  final commandEnvironment = FluohEnvironment(
    homeDirectory: environment.homeDirectory,
    workingDirectory: environment.workingDirectory,
    processEnvironment: processEnvironment,
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

Future<Directory> _writeDoctorPathFixture(Directory root) async {
  final bin = Directory('${root.path}/doctor-bin');
  await _writeExecutable(File('${bin.path}/git'), '''
if [ "\$1" = "--version" ]; then
  printf "git version 2.50.1\\n"
  exit 0
fi
exit 1
''');
  await _writeExecutable(File('${bin.path}/which'), '''
exit 1
''');
  return bin;
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
  ]) {
    await File(path).writeAsString('');
  }
  final hdc = File('${root.path}/fake_hdc');
  await _writeExecutable(hdc, '''
if [ "\$1" = "-v" ]; then
  printf "1.2.3\\n"
  exit 0
fi
exit 0
''');
  await Link('${toolchains.path}/hdc').create(hdc.path);
  final emulator = File('${root.path}/fake_emulator');
  await _writeExecutable(emulator, '''
if [ "\$1" = "-version" ]; then
  printf "HarmonyOS Emulator :6.0.2.200\\n"
  exit 0
fi
exit 0
''');
  await Link('${emulatorDirectory.path}/Emulator').create(emulator.path);
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

Map<String, String> _androidDoctorEnvironment(
  FluohEnvironment environment,
  Directory androidSdk,
  Directory javaHome,
) {
  return {
    ...environment.processEnvironment,
    'ANDROID_HOME': androidSdk.path,
    'FLUOH_ANDROID_ADB': '${androidSdk.path}/platform-tools/adb',
    'FLUOH_ANDROID_EMULATOR': '${androidSdk.path}/emulator/emulator',
    'FLUOH_ANDROID_AVDMANAGER':
        '${androidSdk.path}/cmdline-tools/latest/bin/avdmanager',
    'FLUOH_ANDROID_STUDIO':
        '${environment.homeDirectory.path}/missing/Android Studio.app',
    'FLUOH_JAVA': '${javaHome.path}/bin/java',
    'JAVA_HOME': javaHome.path,
  };
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

List<String> _defaultHostPlatformNames() {
  return [
    'ohos',
    'android',
    if (Platform.isMacOS) ...['ios', 'macos'],
    if (Platform.isLinux) 'linux',
    'web',
    if (Platform.isWindows) 'windows',
  ];
}
