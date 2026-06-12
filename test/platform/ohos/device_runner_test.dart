import 'dart:io';

import 'package:fluoh/src/cli/terminal_output.dart';
import 'package:fluoh/src/context/fluoh_environment.dart';
import 'package:fluoh/src/platform/ohos/device_runner.dart';
import 'package:test/test.dart';

part 'device_runner_run_part.dart';
part 'device_runner_failure_part.dart';
part 'device_runner_emulator_part.dart';
part 'device_runner_log_part.dart';

void main() {
  _registerOhosDeviceRunnerRunTests();
  _registerOhosDeviceRunnerFailureTests();
  _registerOhosDeviceRunnerEmulatorTests();
  _registerOhosDeviceRunnerLogTests();
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
  String? emulatorStartupLog,
  String targets = 'emulator-5554\n',
  String? targetsAfterEmulatorStart,
  bool crashHilog = false,
  bool shutdownCrashHilog = false,
  bool flutterMissingPluginHilog = false,
  bool hangClearHilog = false,
  int listTargetsExitCode = 0,
  bool createEmulatorTool = true,
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
  final hdc = File('${root.path}/fake_hdc');
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
if [ "\$1" = "hilog" ] && [ "\$2" = "-r" ]; then
  if [ "${hangClearHilog ? '1' : '0'}" = "1" ]; then
    while true; do
      sleep 1
    done
  fi
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
  if [ "${flutterMissingPluginHilog ? '1' : '0'}" = "1" ]; then
    printf "W A000ff/Flutter: MethodChannel# --> method not implemented\\n"
    printf "E flutter: MissingPluginException(No implementation found for method getTemporaryDirectory on channel plugins.flutter.io/path_provider)\\n"
    exit 0
  fi
  printf "I app started\\n"
  printf "\\377\\n"
  exit 0
fi
exit 1
''');
  await Process.run('chmod', ['+x', hdc.path]);
  await Link('${toolchains.path}/hdc').create(hdc.path);
  if (createEmulatorTool) {
    final emulator = File('${root.path}/fake_emulator');
    final startupLog =
        emulatorStartupLog ??
        '[Info] [EmulatorWindowEvent.cpp(ShowBootAnimation:1007)]'
            'ShowBootAnimation.';
    final startupLogScript =
        '''
if [ -n "\$hvd" ] && [ -n "\$deployed" ]; then
  mkdir -p "\$deployed/\$hvd/Log"
  printf "trace pipe name is: /tmp/%s\\n" "\$trace" > "\$deployed/\$hvd/Log/Emulator.log"
  printf "%s\\n" ${_shellSingleQuote(startupLog)} >> "\$deployed/\$hvd/Log/Emulator.log"
fi
''';
    await emulator.writeAsString('''
#!/bin/sh
printf "%s\\n" "\$*" >> "${emulatorLog?.path ?? '${root.path}/emulator.log'}"
hvd=""
deployed=""
trace=""
while [ "\$#" -gt 0 ]; do
  case "\$1" in
    -hvd)
      shift
      hvd="\$1"
      ;;
    -path)
      shift
      deployed="\$1"
      ;;
    -t)
      shift
      trace="\$1"
      ;;
  esac
  shift
done
$startupLogScript
touch "${emulatorStarted?.path ?? '${root.path}/emulator.started'}"
exit 0
''');
    await Process.run('chmod', ['+x', emulator.path]);
    await Link('${emulatorDirectory.path}/Emulator').create(emulator.path);
  }
  return devEco;
}

Future<Directory> _writeEmulatorList(
  Directory root, {
  List<Map<String, Object?>> emulators = const [
    {'name': 'Huawei_Phone'},
  ],
}) async {
  final deployed = Directory('${root.path}/deployed');
  final encodedItems = <String>[];
  for (final emulator in emulators) {
    final name = emulator['name']! as String;
    final directory = Directory('${deployed.path}/$name')
      ..createSync(recursive: true);
    await File('${directory.path}/config.ini').writeAsString(
      [
        'name=$name',
        if (emulator['apiVersion'] != null)
          'apiVersion=${emulator['apiVersion']}',
        '',
      ].join('\n'),
    );
    encodedItems.add(
      [
        '{"name":"$name"',
        if (emulator['apiVersion'] != null)
          ',"apiVersion":${emulator['apiVersion']}',
        ',"path":"${directory.path}"}',
      ].join(),
    );
  }
  await File(
    '${deployed.path}/lists.json',
  ).writeAsString('[${encodedItems.join(',')}]\n');
  return deployed;
}

String _shellSingleQuote(String value) {
  return "'${value.replaceAll("'", "'\"'\"'")}'";
}
