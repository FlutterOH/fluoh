import 'dart:convert';
import 'dart:io';

import 'package:fluoh/fluoh.dart';
import 'package:test/test.dart';

import '../helpers/fluoh_command_context.dart';

void main() {
  test('devices lists Android targets as JSON', () async {
    final environment = await createTestEnvironment();
    final androidSdk = await _writeAndroidSdkFixture(
      environment.homeDirectory,
      adbScript: '''
if [ "\$1" = "devices" ]; then
  printf "List of devices attached\\nandroid-1 device model:Pixel_8\\n"
  exit 0
fi
exit 1
''',
    );
    final commandEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: environment.workingDirectory,
      processEnvironment: {
        ...environment.processEnvironment,
        'ANDROID_HOME': androidSdk.path,
      },
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['devices', '--platform', 'android', '--json'],
        environment: commandEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('schemaVersion', 1));
    expect(report, containsPair('command', 'devices'));
    expect(report, containsPair('ok', true));
    final platforms = report['platforms'] as List<Object?>;
    final android = platforms.single as Map<String, Object?>;
    final targets = android['targets'] as List<Object?>;
    expect(
      targets,
      contains(
        allOf(
          containsPair('id', 'android-1'),
          containsPair('name', 'Pixel 8'),
          containsPair('kind', 'device'),
        ),
      ),
    );
    expect(stderr, isEmpty);
  });

  test('emulators lists Android AVDs as JSON', () async {
    final environment = await createTestEnvironment();
    final androidSdk = await _writeAndroidSdkFixture(
      environment.homeDirectory,
      emulatorScript: '''
if [ "\$1" = "-list-avds" ]; then
  printf "Pixel_8_API_35\\n"
  exit 0
fi
exit 1
''',
    );
    final commandEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: environment.workingDirectory,
      processEnvironment: {
        ...environment.processEnvironment,
        'ANDROID_HOME': androidSdk.path,
      },
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['emulators', '--platform', 'android', '--json'],
        environment: commandEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('schemaVersion', 1));
    expect(report, containsPair('command', 'emulators'));
    final platforms = report['platforms'] as List<Object?>;
    final android = platforms.single as Map<String, Object?>;
    final targets = android['targets'] as List<Object?>;
    expect(
      targets,
      contains(
        allOf(
          containsPair('id', 'Pixel_8_API_35'),
          containsPair('kind', 'emulator'),
        ),
      ),
    );
    expect(stderr, isEmpty);
  });

  test('plain target output wraps long device rows', () async {
    final environment = await createTestEnvironment();
    final longId = 'android-${'x' * 120}';
    final androidSdk = await _writeAndroidSdkFixture(
      environment.homeDirectory,
      adbScript:
          '''
if [ "\$1" = "devices" ]; then
  printf "List of devices attached\\n$longId device model:Pixel_8_Pro_Maximum_Length\\n"
  exit 0
fi
exit 1
''',
    );
    final commandEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: environment.workingDirectory,
      processEnvironment: {
        ...environment.processEnvironment,
        'ANDROID_HOME': androidSdk.path,
      },
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['devices', '--platform', 'android'],
        environment: commandEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(stdout.where((line) => line.length > 80), isEmpty);
    expect(stdout.join('\n'), contains('Pixel 8 Pro Maximum Length'));
    expect(stderr, isEmpty);
  });

  test(
    'devices lists iOS physical devices and booted simulators only',
    () async {
      final environment = await createTestEnvironment();
      final xcrun = await _writeXcrunFixture(
        environment.homeDirectory,
        simctlDevicesJson: _simctlDevicesJson,
        devicectlDevicesJson: _devicectlDevicesJson,
      );
      final commandEnvironment = FluohEnvironment(
        homeDirectory: environment.homeDirectory,
        workingDirectory: environment.workingDirectory,
        processEnvironment: {
          ...environment.processEnvironment,
          'FLUOH_XCRUN': xcrun.path,
        },
      );
      final stdout = <String>[];
      final stderr = <String>[];

      expect(
        await runFluoh(
          ['devices', '--platform', 'ios'],
          environment: commandEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final output = stdout.join('\n');
      expect(output, contains('Office iPhone'));
      expect(output, contains('WIRELESS-DEVICE-UDID'));
      expect(output, contains('iPhone 15 Pro'));
      expect(output, isNot(contains('iPhone 15 Mini')));
      expect(output, isNot(contains('Booted')));
      expect(output, isNot(contains('Shutdown')));
      expect(stderr, isEmpty);
    },
  );

  test('emulators hides iOS simulator states in plain output', () async {
    final environment = await createTestEnvironment();
    final xcrun = await _writeXcrunFixture(
      environment.homeDirectory,
      simctlDevicesJson: _simctlDevicesJson,
      devicectlDevicesJson: '{"result":{"devices":[]}}',
    );
    final commandEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: environment.workingDirectory,
      processEnvironment: {
        ...environment.processEnvironment,
        'FLUOH_XCRUN': xcrun.path,
      },
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['emulators', '--platform', 'ios'],
        environment: commandEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final output = stdout.join('\n');
    expect(output, contains('iPhone 15 Pro'));
    expect(output, contains('iPhone 15 Mini'));
    expect(output, isNot(contains('Booted')));
    expect(output, isNot(contains('Shutdown')));
    expect(stdout.where((line) => line.trim().endsWith('emulator')), isEmpty);
    expect(stderr, isEmpty);
  });
}

Future<Directory> _writeAndroidSdkFixture(
  Directory root, {
  String adbScript = 'exit 0\n',
  String emulatorScript = 'exit 0\n',
}) async {
  final sdk = Directory('${root.path}/android-sdk');
  await _writeExecutable(File('${sdk.path}/platform-tools/adb'), adbScript);
  await _writeExecutable(File('${sdk.path}/emulator/emulator'), emulatorScript);
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

Future<File> _writeXcrunFixture(
  Directory root, {
  required String simctlDevicesJson,
  required String devicectlDevicesJson,
}) async {
  final xcrun = File('${root.path}/bin/xcrun');
  await _writeExecutable(xcrun, '''
if [ "\$1" = "simctl" ] && [ "\$2" = "list" ]; then
  cat <<'JSON'
$simctlDevicesJson
JSON
  exit 0
fi
if [ "\$1" = "devicectl" ] && [ "\$2" = "list" ]; then
  cat <<'JSON'
$devicectlDevicesJson
JSON
  exit 0
fi
exit 1
''');
  return xcrun;
}

const _simctlDevicesJson = '''
{
  "devices": {
    "com.apple.CoreSimulator.SimRuntime.iOS-17-5": [
      {
        "name": "iPhone 15 Pro",
        "udid": "BOOTED-SIM-UDID",
        "state": "Booted",
        "isAvailable": true
      },
      {
        "name": "iPhone 15 Mini",
        "udid": "SHUTDOWN-SIM-UDID",
        "state": "Shutdown",
        "isAvailable": true
      }
    ]
  }
}
''';

const _devicectlDevicesJson = '''
{
  "result": {
    "devices": [
      {
        "identifier": "WIRELESS-DEVICE-UDID",
        "deviceProperties": {
          "name": "Office iPhone",
          "osVersionNumber": "17.5"
        },
        "hardwareProperties": {
          "platform": "iOS",
          "marketingName": "iPhone 15"
        },
        "connectionProperties": {
          "transportType": "network",
          "pairingState": "paired",
          "tunnelState": "connected"
        }
      }
    ]
  }
}
''';
