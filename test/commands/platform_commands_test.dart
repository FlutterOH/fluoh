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
    expect(report, containsPair('schema', 1));
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
          containsPair('displayName', 'Pixel 8 (mobile)'),
          containsPair('displayPlatform', 'android'),
          containsPair('category', 'mobile'),
          containsPair('summary', 'device'),
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
    expect(report, containsPair('schema', 1));
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
          containsPair('displayName', 'Pixel 8 API 35'),
          containsPair('displayPlatform', 'android'),
          containsPair('category', 'mobile'),
          containsPair('manufacturer', 'Google'),
        ),
      ),
    );
    expect(stderr, isEmpty);
  });

  test('plain target output uses Flutter-style device rows', () async {
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

    final output = stdout.join('\n');
    expect(output, contains('Found 1 connected device:'));
    expect(
      output,
      contains(
        'Pixel 8 Pro Maximum Length (mobile) • $longId • android • device',
      ),
    );
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

  test('devices discovers iOS wireless devices from xcdevice', () async {
    final environment = await createTestEnvironment();
    final xcrun = await _writeXcrunFixture(
      environment.homeDirectory,
      simctlDevicesJson: '{"devices":{}}',
      devicectlDevicesJson: '{"result":{"devices":[]}}',
      xcdeviceDevicesJson: _xcdeviceDevicesJson,
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
        ['devices', '--platform', 'ios', '--json'],
        environment: commandEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    final platforms = report['platforms'] as List<Object?>;
    final ios = platforms.single as Map<String, Object?>;
    final targets = ios['targets'] as List<Object?>;
    expect(
      targets,
      contains(
        allOf(
          containsPair('id', 'XCDEVICE-WIRELESS-UDID'),
          containsPair('name', 'Desk iPhone'),
          containsPair('kind', 'device'),
        ),
      ),
    );
    expect(
      targets.cast<Map<String, Object?>>().map((target) => target['id']),
      isNot(contains('MAC-UDID')),
    );
    final wireless = targets.cast<Map<String, Object?>>().firstWhere(
      (target) => target['id'] == 'XCDEVICE-WIRELESS-UDID',
    );
    expect(
      wireless,
      allOf(
        containsPair('displayName', 'Desk iPhone (wireless) (mobile)'),
        containsPair('displayPlatform', 'ios'),
        containsPair('category', 'mobile'),
        containsPair('connection', 'wireless'),
        containsPair('summary', 'iOS 18.5'),
      ),
    );
    expect(
      wireless['details'],
      allOf(
        containsPair('source', 'xcdevice'),
        containsPair('transport', 'network'),
      ),
    );
    stdout.clear();

    expect(
      await runFluoh(
        ['devices', '--platform', 'ios'],
        environment: commandEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );
    expect(
      stdout.join('\n'),
      contains('Desk iPhone (wireless) (mobile) • XCDEVICE-WIRELESS-UDID'),
    );
    expect(stderr, isEmpty);
  });

  test('plain device output uses consistent list rows', () async {
    final environment = await createTestEnvironment();
    final androidSdk = await _writeAndroidSdkFixture(
      environment.homeDirectory,
      adbScript: '''
if [ "\$1" = "devices" ]; then
  printf "List of devices attached\\n"
  exit 0
fi
exit 1
''',
    );
    final xcrun = await _writeXcrunFixture(
      environment.homeDirectory,
      simctlDevicesJson: '{"devices":{}}',
      devicectlDevicesJson: _devicectlDevicesJson,
      devicectlStdoutJson: false,
      xcdeviceDevicesJson: _duplicateXcdeviceOfficeIphoneJson,
    );
    final commandEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: environment.workingDirectory,
      processEnvironment: {
        ...environment.processEnvironment,
        'ANDROID_HOME': androidSdk.path,
        'FLUOH_XCRUN': xcrun.path,
      },
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['devices', '--platform', 'all'],
        environment: commandEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      Platform.isMacOS ? 0 : 1,
    );

    final output = stdout.join('\n');
    expect(output, isNot(contains('Checking for wireless devices...')));
    expect(output, contains('Found 1 wirelessly connected device:'));
    expect(
      output,
      contains('  Office iPhone (wireless) (mobile) • WIRELESS-DEVICE-UDID'),
    );
    expect(output, contains('iOS 17.5 21F79'));
    expect(output, isNot(contains('XCTRACE-DUPLICATE-UDID')));
    if (Platform.isMacOS) {
      expect(output, contains('Found 1 connected device:'));
      expect(output, contains('macOS (desktop)'));
      expect(output, contains('macOS (desktop) • macos • darwin-'));
      expect(output, matches(RegExp(r'macOS .+ darwin-')));
    } else {
      expect(output, contains('macOS desktop targets require a macOS host'));
    }
    expect(stderr, isEmpty);
  });

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
    expect(output, contains('Id'));
    expect(output, contains('Manufacturer'));
    expect(output, contains('Apple'));
    expect(output, contains('iPhone 15 Pro'));
    expect(output, contains('iPhone 15 Mini'));
    expect(output, isNot(contains('Booted')));
    expect(output, isNot(contains('Shutdown')));
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
  bool devicectlStdoutJson = true,
  String xcdeviceDevicesJson = '[]',
}) async {
  final xcrun = File('${root.path}/bin/xcrun');
  final devicectlStdoutJsonScript = devicectlStdoutJson
      ? '''
  cat <<'JSON'
$devicectlDevicesJson
JSON
  exit 0
'''
      : '''
  printf "Unknown option --json\\n" >&2
  exit 64
''';
  await _writeExecutable(xcrun, '''
if [ "\$1" = "simctl" ] && [ "\$2" = "list" ]; then
  cat <<'JSON'
$simctlDevicesJson
JSON
  exit 0
fi
if [ "\$1" = "devicectl" ] && [ "\$2" = "list" ]; then
  if [ "\$4" = "--json-output" ]; then
    cat > "\$5" <<'JSON'
$devicectlDevicesJson
JSON
    exit 0
  fi
$devicectlStdoutJsonScript
fi
if [ "\$1" = "xcdevice" ] && [ "\$2" = "list" ]; then
  cat <<'JSON'
$xcdeviceDevicesJson
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

const _xcdeviceDevicesJson = '''
[
  {
    "identifier": "XCDEVICE-WIRELESS-UDID",
    "name": "Desk iPhone",
    "modelName": "iPhone 16",
    "platform": "com.apple.platform.iphoneos",
    "operatingSystemVersion": "18.5",
    "interface": "network",
    "available": true,
    "simulator": false
  },
  {
    "identifier": "MAC-UDID",
    "name": "Work Mac",
    "platform": "com.apple.platform.macosx",
    "available": true,
    "simulator": false
  }
]
''';

const _duplicateXcdeviceOfficeIphoneJson = '''
[
  {
    "identifier": "XCTRACE-DUPLICATE-UDID",
    "name": "Office iPhone",
    "modelName": "iPhone 15",
    "platform": "com.apple.platform.iphoneos",
    "operatingSystemVersion": "17.5 (21F79)",
    "interface": "usb",
    "available": true,
    "simulator": false
  }
]
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
          "transportType": "localNetwork",
          "pairingState": "paired",
          "tunnelState": "connected"
        }
      }
    ]
  }
}
''';
