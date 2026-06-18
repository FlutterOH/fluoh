import 'dart:io';

import 'package:fluoh/src/context/fluoh_environment.dart';
import 'package:fluoh/src/platform/platform_environment.dart';
import 'package:test/test.dart';

import '../helpers/fluoh_command_context.dart';

void main() {
  test('owns supported platform option parsing', () {
    expect(fluohPlatformCliNames, [
      'ohos',
      'android',
      'ios',
      'macos',
      'linux',
      'web',
      'windows',
    ]);
    expect(fluohPlatformOptionValues, ['all', ...fluohPlatformCliNames]);
    expect(fluohPlatformFromCliName('ohos'), FluohPlatform.ohos);
    expect(fluohPlatformFromCliName('android'), FluohPlatform.android);
    expect(fluohPlatformFromCliName('missing'), isNull);
    expect(fluohPlatformsFromCliOption('web'), [FluohPlatform.web]);

    final defaults = defaultHostFluohPlatforms();
    expect(defaults.take(2).toList(), [
      FluohPlatform.ohos,
      FluohPlatform.android,
    ]);
    expect(defaults, contains(FluohPlatform.web));
    expect(defaults.contains(FluohPlatform.ios), Platform.isMacOS);
    expect(defaults.contains(FluohPlatform.macos), Platform.isMacOS);
    expect(defaults.contains(FluohPlatform.linux), Platform.isLinux);
    expect(defaults.contains(FluohPlatform.windows), Platform.isWindows);
  });

  test('OpenHarmony environment report focuses on SDK tools', () async {
    final environment = await createTestEnvironment();
    final devEco = await _writeDevEcoFixture(environment.homeDirectory);
    final toolEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: environment.workingDirectory,
      processEnvironment: {
        ...environment.processEnvironment,
        'FLUOH_DEVECO_STUDIO': devEco.path,
      },
    );

    final reports = await inspectPlatformEnvironment(
      environment: toolEnvironment,
      platforms: const [FluohPlatform.ohos],
    );

    final report = reports.single;
    expect(report.ok, isTrue);
    expect(report.checks.map((check) => check.id).toList(), [
      'ohos.sdk',
      'ohos.hdc',
      'ohos.emulator',
    ]);
    expect(report.checks[0].version, '5.0.1');
    expect(report.checks[1].version, '1.2.3');
    expect(report.checks[2].version, '6.0.2.200');
  });

  test('normalizes tool and device display versions', () {
    expect(
      normalizeOhosEmulatorVersion('HarmonyOS Emulator :6.0.2.200'),
      '6.0.2.200',
    );
    expect(
      normalizeOhosEmulatorVersion('Emulator version 6.0.2.130'),
      '6.0.2.130',
    );
    expect(
      normalizeAppleOperatingSystemVersion('Version 26.5 (Build 25F71)'),
      '26.5 25F71',
    );
    expect(isWirelessTransport('localNetwork'), isTrue);
    expect(isWirelessTransport('USB'), isFalse);
  });
}

Future<Directory> _writeDevEcoFixture(Directory root) async {
  final devEco = Directory('${root.path}/DevEco-Studio.app');
  final sdk = Directory('${devEco.path}/Contents/sdk/default/openharmony');
  final toolchains = Directory('${sdk.path}/toolchains');
  final lib = Directory('${toolchains.path}/lib');
  final jbr = Directory('${devEco.path}/Contents/jbr/Contents/Home/bin');
  final node = Directory('${devEco.path}/Contents/tools/node/bin');
  final emulatorDirectory = Directory('${devEco.path}/Contents/tools/emulator');
  await lib.create(recursive: true);
  await jbr.create(recursive: true);
  await node.create(recursive: true);
  await emulatorDirectory.create(recursive: true);
  await File(
    '${sdk.path}/oh-uni-package.json',
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
  printf "Ver: 1.2.3\\n"
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

Future<void> _writeExecutable(File file, String script) async {
  await file.parent.create(recursive: true);
  await file.writeAsString('#!/bin/sh\n$script');
  final result = await Process.run('chmod', ['+x', file.path]);
  if (result.exitCode != 0) {
    fail('chmod failed: ${result.stderr}');
  }
}
