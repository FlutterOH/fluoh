import 'dart:io';

import 'package:fluoh/src/cli/terminal_output.dart';
import 'package:fluoh/src/context/fluoh_environment.dart';
import 'package:fluoh/src/platform/ohos/device_runner.dart';
import 'package:test/test.dart';

void main() {
  test('reads launch info from OHOS stage module metadata', () async {
    final root = await Directory.systemTemp.createTemp('fluoh_ohos_run_');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final ohos = await _writeOhosProject(root);

    final launchInfo = await readOhosLaunchInfo(ohos);

    expect(launchInfo.bundleName, 'com.example.camera');
    expect(launchInfo.moduleName, 'entry');
    expect(launchInfo.abilityName, 'EntryAbility');
  });

  test('installs signed HAP, starts ability, and writes hilog', () async {
    final root = await Directory.systemTemp.createTemp('fluoh_ohos_run_');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final home = Directory('${root.path}/home')..createSync(recursive: true);
    final project = Directory('${root.path}/project')
      ..createSync(recursive: true);
    final ohos = await _writeOhosProject(project);
    final hap = File('${project.path}/entry-default-signed.hap')
      ..writeAsStringSync('hap');
    final hdcLog = File('${root.path}/hdc.log');
    final devEco = await _writeDevEcoFixture(root, hdcLog: hdcLog);
    final outputLines = <String>[];

    final result = await runOhosHapsOnDevice(
      environment: FluohEnvironment(
        homeDirectory: home,
        workingDirectory: project,
        processEnvironment: {'FLUOH_DEVECO_STUDIO': devEco.path},
      ),
      ohosDirectory: ohos,
      haps: [hap],
      output: TerminalOutput(stdout: outputLines.add),
      logDuration: const Duration(milliseconds: 10),
    );

    expect(result.passed, isTrue);
    expect(result.diagnostics, isEmpty);
    expect(result.targetId, 'emulator-5554');
    expect(result.logFile, isNotNull);
    expect(result.logFile!.readAsStringSync(), contains('app started'));
    final invocations = hdcLog.readAsStringSync();
    expect(invocations, contains('list targets'));
    expect(invocations, contains('-t emulator-5554 install -r ${hap.path}'));
    expect(
      invocations,
      contains(
        '-t emulator-5554 shell aa start -d 0 -a EntryAbility '
        '-b com.example.camera',
      ),
    );
    expect(invocations, contains('-t emulator-5554 hilog'));
  });

  test('reports missing device targets as a failed run result', () async {
    final root = await Directory.systemTemp.createTemp('fluoh_ohos_run_');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final home = Directory('${root.path}/home')..createSync(recursive: true);
    final project = Directory('${root.path}/project')
      ..createSync(recursive: true);
    final ohos = await _writeOhosProject(project);
    final hap = File('${project.path}/entry-default-signed.hap')
      ..writeAsStringSync('hap');
    final devEco = await _writeDevEcoFixture(
      root,
      hdcLog: File('${root.path}/hdc.log'),
      targets: '[Empty]\n',
    );

    final result = await runOhosHapsOnDevice(
      environment: FluohEnvironment(
        homeDirectory: home,
        workingDirectory: project,
        processEnvironment: {'FLUOH_DEVECO_STUDIO': devEco.path},
      ),
      ohosDirectory: ohos,
      haps: [hap],
      output: TerminalOutput(stdout: (_) {}),
      logDuration: Duration.zero,
    );

    expect(result.passed, isFalse);
    expect(result.reason, contains('No OHOS device target is connected'));
    expect(result.diagnostics, hasLength(1));
    expect(result.diagnostics.single.code, 'ohos.device_missing');
    expect(
      result.diagnostics.single.details,
      containsPair('connectedDevices', isEmpty),
    );
  });

  test('returns diagnostics when runtime crash lines are found', () async {
    final root = await Directory.systemTemp.createTemp('fluoh_ohos_run_');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final home = Directory('${root.path}/home')..createSync(recursive: true);
    final project = Directory('${root.path}/project')
      ..createSync(recursive: true);
    final ohos = await _writeOhosProject(project);
    final hap = File('${project.path}/entry-default-signed.hap')
      ..writeAsStringSync('hap');
    final devEco = await _writeDevEcoFixture(
      root,
      hdcLog: File('${root.path}/hdc.log'),
      crashHilog: true,
    );

    final result = await runOhosHapsOnDevice(
      environment: FluohEnvironment(
        homeDirectory: home,
        workingDirectory: project,
        processEnvironment: {'FLUOH_DEVECO_STUDIO': devEco.path},
      ),
      ohosDirectory: ohos,
      haps: [hap],
      output: TerminalOutput(stdout: (_) {}),
      logDuration: const Duration(milliseconds: 10),
    );

    expect(result.passed, isFalse);
    expect(
      result.findings,
      contains('E CppCrash Process crashed with SIGSEGV'),
    );
    expect(result.diagnostics, hasLength(1));
    expect(result.diagnostics.single.code, 'ohos.runtime_crash');
    expect(
      result.diagnostics.single.details,
      containsPair('findings', result.findings),
    );
  });

  test('drains hilog before classifying runtime crashes', () async {
    final root = await Directory.systemTemp.createTemp('fluoh_ohos_run_');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final home = Directory('${root.path}/home')..createSync(recursive: true);
    final project = Directory('${root.path}/project')
      ..createSync(recursive: true);
    final ohos = await _writeOhosProject(project);
    final hap = File('${project.path}/entry-default-signed.hap')
      ..writeAsStringSync('hap');
    final devEco = await _writeDevEcoFixture(
      root,
      hdcLog: File('${root.path}/hdc.log'),
      shutdownCrashHilog: true,
    );

    final result = await runOhosHapsOnDevice(
      environment: FluohEnvironment(
        homeDirectory: home,
        workingDirectory: project,
        processEnvironment: {'FLUOH_DEVECO_STUDIO': devEco.path},
      ),
      ohosDirectory: ohos,
      haps: [hap],
      output: TerminalOutput(stdout: (_) {}),
      logDuration: const Duration(milliseconds: 10),
    );

    expect(result.passed, isFalse);
    expect(
      result.findings,
      contains('E CppCrash Process crashed with SIGABRT'),
    );
    expect(
      result.logFile!.readAsStringSync(),
      contains('E CppCrash Process crashed with SIGABRT'),
    );
  });

  test('returns diagnostics when hdc target listing fails', () async {
    final root = await Directory.systemTemp.createTemp('fluoh_ohos_run_');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final home = Directory('${root.path}/home')..createSync(recursive: true);
    final project = Directory('${root.path}/project')
      ..createSync(recursive: true);
    final ohos = await _writeOhosProject(project);
    final hap = File('${project.path}/entry-default-signed.hap')
      ..writeAsStringSync('hap');
    final devEco = await _writeDevEcoFixture(
      root,
      hdcLog: File('${root.path}/hdc.log'),
      listTargetsExitCode: 1,
    );

    final result = await runOhosHapsOnDevice(
      environment: FluohEnvironment(
        homeDirectory: home,
        workingDirectory: project,
        processEnvironment: {'FLUOH_DEVECO_STUDIO': devEco.path},
      ),
      ohosDirectory: ohos,
      haps: [hap],
      output: TerminalOutput(stdout: (_) {}),
      logDuration: Duration.zero,
    );

    expect(result.passed, isFalse);
    expect(result.diagnostics, hasLength(1));
    expect(result.diagnostics.single.code, 'ohos.hdc_targets_failed');
    expect(result.diagnostics.single.details['error'], contains('hdc offline'));
  });

  test('returns diagnostics when launch info is missing', () async {
    final root = await Directory.systemTemp.createTemp('fluoh_ohos_run_');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final home = Directory('${root.path}/home')..createSync(recursive: true);
    final project = Directory('${root.path}/project')
      ..createSync(recursive: true);
    final ohos = await _writeOhosProject(project);
    await File('${ohos.path}/entry/src/main/module.json5').writeAsString('''
{
  "module": {
    "name": "entry",
    "type": "entry"
  }
}
''');
    final hap = File('${project.path}/entry-default-signed.hap')
      ..writeAsStringSync('hap');
    final devEco = await _writeDevEcoFixture(
      root,
      hdcLog: File('${root.path}/hdc.log'),
    );

    final result = await runOhosHapsOnDevice(
      environment: FluohEnvironment(
        homeDirectory: home,
        workingDirectory: project,
        processEnvironment: {'FLUOH_DEVECO_STUDIO': devEco.path},
      ),
      ohosDirectory: ohos,
      haps: [hap],
      output: TerminalOutput(stdout: (_) {}),
      logDuration: Duration.zero,
    );

    expect(result.passed, isFalse);
    expect(result.diagnostics, hasLength(1));
    expect(result.diagnostics.single.code, 'ohos.launch_info_missing');
  });

  test('starts local emulator and waits for hdc target', () async {
    final root = await Directory.systemTemp.createTemp('fluoh_ohos_run_');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final home = Directory('${root.path}/home')..createSync(recursive: true);
    final project = Directory('${root.path}/project')
      ..createSync(recursive: true);
    final ohos = await _writeOhosProject(project);
    final hap = File('${project.path}/entry-default-signed.hap')
      ..writeAsStringSync('hap');
    final hdcLog = File('${root.path}/hdc.log');
    final emulatorLog = File('${root.path}/emulator.log');
    final emulatorStarted = File('${root.path}/emulator.started');
    final deployed = await _writeEmulatorList(root);
    final imageRoot = Directory('${root.path}/Huawei/Sdk')
      ..createSync(recursive: true);
    final devEco = await _writeDevEcoFixture(
      root,
      hdcLog: hdcLog,
      emulatorLog: emulatorLog,
      emulatorStarted: emulatorStarted,
      targets: '[Empty]\n',
      targetsAfterEmulatorStart: 'emulator-5554\n',
    );

    final result = await runOhosHapsOnDevice(
      environment: FluohEnvironment(
        homeDirectory: home,
        workingDirectory: project,
        processEnvironment: {
          'FLUOH_DEVECO_STUDIO': devEco.path,
          'FLUOH_OHOS_EMULATOR_DEPLOYED': deployed.path,
          'FLUOH_HARMONYOS_SDK_ROOT': imageRoot.path,
        },
      ),
      ohosDirectory: ohos,
      haps: [hap],
      output: TerminalOutput(stdout: (_) {}),
      startEmulator: true,
      emulatorName: 'Huawei_Phone',
      deviceTimeout: const Duration(milliseconds: 50),
      logDuration: Duration.zero,
    );

    expect(result.passed, isTrue);
    expect(emulatorStarted.existsSync(), isTrue);
    expect(
      emulatorLog.readAsStringSync(),
      contains('-hvd Huawei_Phone -path ${deployed.path}'),
    );
    expect(hdcLog.readAsStringSync(), contains('list targets'));
  });

  test('classifies fatal OHOS runtime log lines', () {
    expect(
      classifyOhosRuntimeLog('''
I normal line
E CppCrash Process crashed with SIGSEGV
E app FATAL EXCEPTION: main
'''),
      [
        'E CppCrash Process crashed with SIGSEGV',
        'E app FATAL EXCEPTION: main',
      ],
    );
  });

  test('ignores non-fatal FlutterOH method channel startup noise', () {
    expect(
      classifyOhosRuntimeLog(
        'DartMessenger --> Uncaught exception in binary message listener',
      ),
      isEmpty,
    );
  });
}

Future<Directory> _writeOhosProject(Directory root) async {
  final ohos = Directory('${root.path}/ohos');
  await Directory('${ohos.path}/AppScope').create(recursive: true);
  await Directory('${ohos.path}/entry/src/main').create(recursive: true);
  await File('${ohos.path}/AppScope/app.json5').writeAsString('''
{
  "app": {
    "bundleName": "com.example.camera"
  }
}
''');
  await File('${ohos.path}/entry/src/main/module.json5').writeAsString('''
{
  "module": {
    "name": "entry",
    "type": "entry",
    "mainElement": "EntryAbility",
    "abilities": [
      {
        "name": "EntryAbility",
        "exported": true,
        "skills": [
          {
            "entities": ["entity.system.home"],
            "actions": ["action.system.home"]
          }
        ]
      }
    ]
  }
}
''');
  return ohos;
}

Future<Directory> _writeDevEcoFixture(
  Directory root, {
  required File hdcLog,
  File? emulatorLog,
  File? emulatorStarted,
  String targets = 'emulator-5554\n',
  String? targetsAfterEmulatorStart,
  bool crashHilog = false,
  bool shutdownCrashHilog = false,
  int listTargetsExitCode = 0,
}) async {
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
  final hdc = File('${toolchains.path}/hdc');
  await hdc.writeAsString('''
#!/bin/sh
printf "%s\\n" "\$*" >> "${hdcLog.path}"
if [ "\$1" = "list" ] && [ "\$2" = "targets" ]; then
  if [ "$listTargetsExitCode" != "0" ]; then
    printf "hdc offline\\n" >&2
    exit $listTargetsExitCode
  fi
  if [ -n "${emulatorStarted?.path ?? ''}" ] && [ -f "${emulatorStarted?.path ?? ''}" ]; then
    printf "${targetsAfterEmulatorStart ?? targets}"
    exit 0
  fi
  printf "$targets"
  exit 0
fi
if [ "\$1" = "-t" ]; then
  shift 2
fi
if [ "\$1" = "install" ]; then
  exit 0
fi
if [ "\$1" = "shell" ]; then
  printf "start ability successfully\\n"
  exit 0
fi
if [ "\$1" = "hilog" ]; then
  if [ "${shutdownCrashHilog ? '1' : '0'}" = "1" ]; then
    trap 'printf "E CppCrash Process crashed with SIGABRT\\n"; exit 0' INT TERM
    while true; do
      sleep 1
    done
  fi
  if [ "${crashHilog ? '1' : '0'}" = "1" ]; then
    printf "E CppCrash Process crashed with SIGSEGV\\n"
    exit 0
  fi
  printf "I app started\\n"
  printf "\\377\\n"
  exit 0
fi
exit 1
''');
  await Process.run('chmod', ['+x', hdc.path]);
  final emulator = File('${emulatorDirectory.path}/Emulator');
  await emulator.writeAsString('''
#!/bin/sh
printf "%s\\n" "\$*" >> "${emulatorLog?.path ?? '${root.path}/emulator.log'}"
touch "${emulatorStarted?.path ?? '${root.path}/emulator.started'}"
exit 0
''');
  await Process.run('chmod', ['+x', emulator.path]);
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
