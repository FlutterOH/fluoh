import 'dart:convert';
import 'dart:io';

import 'package:fluoh/fluoh.dart';
import 'package:test/test.dart';

import '../helpers/fluoh_command_context.dart';

part 'workflow_commands_verify_part.dart';
part 'workflow_commands_package_part.dart';
part 'workflow_commands_package_platform_part.dart';
part 'workflow_commands_project_part.dart';
part 'workflow_commands_project_run_targets_part.dart';
part 'workflow_commands_project_auto_targets_part.dart';
part 'workflow_commands_attach_part.dart';
part 'workflow_commands_drive_plan_part.dart';
part 'workflow_commands_drive_plan_quality_part.dart';
part 'workflow_commands_drive_coverage_part.dart';
part 'workflow_commands_drive_coverage_scenario_part.dart';
part 'workflow_commands_drive_scenario_part.dart';
part 'workflow_commands_drive_scenario_failures_part.dart';
part 'workflow_commands_presets_part.dart';
part 'workflow_commands_presets_diagnostics_part.dart';

const _ohosFlutterDevicesJson =
    '[{"id":"emulator-5554","name":"OHOS Emulator","targetPlatform":"ohos-arm64","isSupported":true,"emulator":true}]';
const _ohosFlutterRunStdout =
    'Flutter run key commands.\n'
    'Debug service listening on http://127.0.0.1:23456/ohos=/\n'
    'Application running.';
const _ohosFlutterRunStdoutByCommand = {
  'devices --machine': _ohosFlutterDevicesJson,
  'run -d emulator-5554 --debug --no-pub': _ohosFlutterRunStdout,
};

void main() {
  _registerWorkflowCommandsVerifyTests();
  _registerWorkflowCommandsPackageTests();
  _registerWorkflowCommandsPackagePlatformTests();
  _registerWorkflowCommandsProjectTests();
  _registerWorkflowCommandsProjectRunTargetTests();
  _registerWorkflowCommandsProjectAutoTargetTests();
  _registerWorkflowCommandsAttachTests();
  _registerWorkflowCommandsDrivePlanTests();
  _registerWorkflowCommandsDrivePlanQualityTests();
  _registerWorkflowCommandsDriveCoverageTests();
  _registerWorkflowCommandsDriveCoverageScenarioTests();
  _registerWorkflowCommandsDriveScenarioTests();
  _registerWorkflowCommandsDriveScenarioFailureTests();
  _registerWorkflowCommandsPresetsTests();
  _registerWorkflowCommandsPresetsDiagnosticsTests();
}

Future<void> _writePackageManifest(Directory repository) async {
  await File('${repository.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: package

sdk:
  version: 3.35.8-ohos-0.0.3

repository:
  git:
    url: git@github.com:FlutterOH/camera.git
    branch: ohos/3.35/camera

origin:
  kind: ported

upstream:
  git:
    url: https://github.com/flutter/packages.git
    branch: main

package:
  name: camera
  path: .
  release:
    version: 0.1.0
    upstream:
      version: 0.11.0
      commit: "1111111111111111111111111111111111111111"
    status: experimental
''');
}

Future<void> _writeFlutterPackage(
  Directory directory, {
  bool withTests = true,
}) async {
  await Directory('${directory.path}/lib').create(recursive: true);
  await File(
    '${directory.path}/lib/camera.dart',
  ).writeAsString('library camera;\n');
  if (withTests) {
    await Directory('${directory.path}/test').create(recursive: true);
    await File('${directory.path}/test/camera_test.dart').writeAsString('''
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('camera fixture test', () {
    expect(true, isTrue);
  });
}
''');
  }
  await File('${directory.path}/pubspec.yaml').writeAsString('''
name: camera
version: 0.11.0

environment:
  sdk: ^3.0.0

dependencies:
  flutter:
    sdk: flutter

dev_dependencies:
  flutter_test:
    sdk: flutter
''');
}

Future<void> _writeFlutterExample(
  Directory directory, {
  bool withTests = true,
}) async {
  if (withTests) {
    await Directory('${directory.path}/test').create(recursive: true);
  } else {
    await directory.create(recursive: true);
  }
  await File('${directory.path}/pubspec.yaml').writeAsString('''
name: camera_example

environment:
  sdk: ^3.0.0

dependencies:
  flutter:
    sdk: flutter
  camera:
    path: ..

dev_dependencies:
  flutter_test:
    sdk: flutter
''');
  if (withTests) {
    await File('${directory.path}/test/widget_test.dart').writeAsString('''
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('camera example fixture test', () {
    expect(true, isTrue);
  });
}
''');
  }
}

Future<void> _writeWorkflowPlatformDirectories(Directory project) async {
  for (final platform in const [
    'ohos',
    'android',
    'ios',
    'macos',
    'linux',
    'web',
    'windows',
  ]) {
    await Directory('${project.path}/$platform').create(recursive: true);
  }
}

Future<void> _writeWorkflowOhosProject(Directory project) async {
  final ohos = Directory('${project.path}/ohos');
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
  await File('${ohos.path}/build-profile.json5').writeAsString('''
{
  "app": {
    "signingConfigs": [],
    "products": [
      {
        "name": "default",
        "compatibleSdkVersion": 18
      }
    ]
  }
}
''');
}

Future<void> _writeProjectSdkConfig(Directory directory) async {
  await File('${directory.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: project

sdk:
  version: 3.35.8-ohos-0.0.3
dependencyPolicy:
  pubspecSection: dependency_overrides
  versionChanges: compatible
''');
}

Future<void> _writeDartPackage(Directory directory) async {
  await Directory('${directory.path}/lib').create(recursive: true);
  await Directory('${directory.path}/test').create(recursive: true);
  await File(
    '${directory.path}/lib/camera.dart',
  ).writeAsString('library camera;\n');
  await File('${directory.path}/test/camera_test.dart').writeAsString('''
import 'package:test/test.dart';

void main() {
  test('camera fixture test', () {
    expect(true, isTrue);
  });
}
''');
  await File('${directory.path}/pubspec.yaml').writeAsString('''
name: camera
version: 0.11.0

environment:
  sdk: ^3.0.0

dev_dependencies:
  test: ^1.25.0
''');
}

Future<Directory> _createWorkflowSdkSource(
  Directory parent,
  Directory project, {
  Map<String, int> flutterFailures = const {},
  Map<String, List<int>> flutterExitCodeSequences = const {},
  Map<String, String> flutterStdout = const {},
  Map<String, List<String>> flutterStdoutSequences = const {},
  Map<String, String> flutterStderr = const {},
  Map<String, String> flutterSideEffects = const {},
  Map<String, int> dartFailures = const {},
}) async {
  final source = Directory('${parent.path}/package_workflow_source');
  final sdkRepository = Directory('${parent.path}/package_workflow_sdk');
  await sdkRepository.create(recursive: true);
  await _runProcess('git', ['init', '--initial-branch=main'], sdkRepository);
  await _runProcess('git', [
    'config',
    'user.email',
    'fixture@example.com',
  ], sdkRepository);
  await _runProcess('git', ['config', 'user.name', 'Fixture'], sdkRepository);
  await Directory('${sdkRepository.path}/bin').create(recursive: true);
  await _writeTool(
    File('${sdkRepository.path}/bin/flutter'),
    '${project.path}/package_workflow_invocations.txt',
    'flutter',
    failures: flutterFailures,
    exitCodeSequencesByCommand: flutterExitCodeSequences,
    stdoutByCommand: flutterStdout,
    stdoutSequencesByCommand: flutterStdoutSequences,
    stderrByCommand: flutterStderr,
    sideEffectsByCommand: flutterSideEffects,
  );
  await _writeTool(
    File('${sdkRepository.path}/bin/dart'),
    '${project.path}/package_workflow_invocations.txt',
    'dart',
    failures: dartFailures,
  );
  await File('${sdkRepository.path}/README.md').writeAsString('# SDK\n');
  await _runProcess('git', ['add', '.'], sdkRepository);
  await _runProcess('git', ['commit', '-m', 'Initial SDK'], sdkRepository);
  await _runProcess('git', ['tag', '3.35.8-ohos-0.0.3'], sdkRepository);
  await writeSdkSourceFixture(
    source,
    sdkRepository: sdkRepository.path,
    releases: {'3.35.8-ohos-0.0.3': 'stable'},
  );
  return source;
}

Future<void> _writeTool(
  File tool,
  String logPath,
  String name, {
  Map<String, int> failures = const {},
  Map<String, List<int>> exitCodeSequencesByCommand = const {},
  Map<String, String> stdoutByCommand = const {},
  Map<String, List<String>> stdoutSequencesByCommand = const {},
  Map<String, String> stderrByCommand = const {},
  Map<String, String> sideEffectsByCommand = const {},
}) async {
  final sequenceBuffer = StringBuffer();
  var sequenceIndex = 0;
  for (final entry in exitCodeSequencesByCommand.entries) {
    final countPath = '$logPath.$name.exit.$sequenceIndex.count';
    final cases = StringBuffer();
    for (var index = 0; index < entry.value.length; index += 1) {
      cases.writeln('    $index) exit_code=${entry.value[index]} ;;');
    }
    cases.writeln('    *) exit_code=${entry.value.last} ;;');
    final stdout = stdoutByCommand[entry.key];
    final stderr = stderrByCommand[entry.key];
    sequenceBuffer.writeln('''
if [ "\$*" = ${_shellSingleQuote(entry.key)} ]; then
  count_file=${_shellSingleQuote(countPath)}
  count=0
  if [ -f "\$count_file" ]; then
    count=\$(cat "\$count_file")
  fi
  next=\$((count + 1))
  printf "%s\\n" "\$next" > "\$count_file"
  case "\$count" in
$cases  esac
${stdout == null ? '' : '  printf "%s\\\\n" ${_shellSingleQuote(stdout)}'}
${stderr == null ? '' : '  printf "%s\\\\n" ${_shellSingleQuote(stderr)} >&2'}
  exit "\$exit_code"
fi
''');
    sequenceIndex += 1;
  }
  for (final entry in stdoutSequencesByCommand.entries) {
    final countPath = '$logPath.$name.$sequenceIndex.count';
    final cases = StringBuffer();
    for (var index = 0; index < entry.value.length; index += 1) {
      cases.writeln(
        '    $index) printf "%s\\\\n" '
        '${_shellSingleQuote(entry.value[index])} ;;',
      );
    }
    cases.writeln(
      '    *) printf "%s\\\\n" ${_shellSingleQuote(entry.value.last)} ;;',
    );
    sequenceBuffer.writeln('''
if [ "\$*" = ${_shellSingleQuote(entry.key)} ]; then
  count_file=${_shellSingleQuote(countPath)}
  count=0
  if [ -f "\$count_file" ]; then
    count=\$(cat "\$count_file")
  fi
  next=\$((count + 1))
  printf "%s\\n" "\$next" > "\$count_file"
  case "\$count" in
$cases  esac
  exit ${failures[entry.key] ?? 0}
fi
''');
    sequenceIndex += 1;
  }
  final commandOutputs = stdoutByCommand.entries.map((entry) {
    final stderr = stderrByCommand[entry.key];
    final sideEffect = sideEffectsByCommand[entry.key];
    return '''
if [ "\$*" = ${_shellSingleQuote(entry.key)} ]; then
${sideEffect == null ? '' : '$sideEffect\n'}
  printf "%s\\n" ${_shellSingleQuote(entry.value)}
${stderr == null ? '' : '  printf "%s\\\\n" ${_shellSingleQuote(stderr)} >&2'}
  exit ${failures[entry.key] ?? 0}
fi
''';
  }).join();
  final failureChecks = failures.entries
      .where(
        (entry) =>
            !stdoutByCommand.containsKey(entry.key) &&
            !exitCodeSequencesByCommand.containsKey(entry.key) &&
            !stdoutSequencesByCommand.containsKey(entry.key),
      )
      .map(
        (entry) =>
            '''
if [ "\$*" = ${_shellSingleQuote(entry.key)} ]; then
  exit ${entry.value}
fi
''',
      )
      .join();
  await tool.parent.create(recursive: true);
  final sideEffectChecks = sideEffectsByCommand.entries
      .where(
        (entry) =>
            !stdoutByCommand.containsKey(entry.key) &&
            !exitCodeSequencesByCommand.containsKey(entry.key) &&
            !stdoutSequencesByCommand.containsKey(entry.key),
      )
      .map(
        (entry) =>
            '''
if [ "\$*" = ${_shellSingleQuote(entry.key)} ]; then
${entry.value}
  exit ${failures[entry.key] ?? 0}
fi
''',
      )
      .join();
  await tool.writeAsString('''
#!/bin/sh
printf "%s::$name %s\\n" "\$(pwd)" "\$*" >> "$logPath"
$sequenceBuffer
$commandOutputs
printf "$name stdout\\n"
printf "$name stderr\\n" >&2
$sideEffectChecks
$failureChecks
exit 0
''');
  await _runProcess('chmod', ['+x', tool.path], tool.parent);
}

Future<Directory> _writeWorkflowDevEcoFixture(
  Directory root, {
  required File hdcLog,
  String targets = 'emulator-5554\n',
  int hdcListTargetsExitCode = 0,
  String hdcListTargetsStderr = '',
  int hdcInstallExitCode = 1,
  String hdcInstallStdout = '',
  String hdcInstallStderr = '',
  int hdcLaunchExitCode = 1,
  String hdcLaunchStdout = '',
  String hdcLaunchStderr = '',
  String hdcHilogStdout = '',
  String hdcAppDeniedLayout = '',
  String hdcPermissionDialogLayout = '',
  String hdcAppGrantedLayout = '',
}) async {
  final devEco = Directory('${root.path}/DevEco-Studio.app');
  final openHarmony = Directory(
    '${devEco.path}/Contents/sdk/default/openharmony',
  );
  final toolchains = Directory('${openHarmony.path}/toolchains');
  final lib = Directory('${toolchains.path}/lib');
  final jbr = Directory('${devEco.path}/Contents/jbr/Contents/Home/bin');
  final node = Directory('${devEco.path}/Contents/tools/node/bin');
  final emulatorDirectory = Directory('${devEco.path}/Contents/tools/emulator');
  await Directory(
    '${openHarmony.path}/previewer/common/resources',
  ).create(recursive: true);
  await lib.create(recursive: true);
  await jbr.create(recursive: true);
  await node.create(recursive: true);
  await emulatorDirectory.create(recursive: true);
  await File('${lib.path}/hap-sign-tool.jar').writeAsString('');
  await File('${lib.path}/OpenHarmony.p12').writeAsString('');
  await File('${lib.path}/OpenHarmonyProfileDebug.pem').writeAsString('');
  await File(
    '${openHarmony.path}/previewer/common/resources/module.json',
  ).writeAsString('{"definePermissions": []}');

  final fakeKeytool = File('${root.path}/fake_keytool');
  await _writeExecutable(fakeKeytool, r'''
#!/usr/bin/env python3
import sys

args = sys.argv[1:]
if "-file" in args:
    index = args.index("-file")
    if index + 1 < len(args):
        with open(args[index + 1], "w", encoding="utf-8") as out:
            out.write("-----BEGIN CERTIFICATE-----\nfixture\n-----END CERTIFICATE-----\n")
''');
  await Link('${jbr.path}/keytool').create(fakeKeytool.path);
  final fakeJava = File('${root.path}/fake_java');
  await _writeExecutable(fakeJava, r'''
#!/usr/bin/env python3
import sys

args = sys.argv[1:]
if "-keystoreFile" in args:
    index = args.index("-keystoreFile")
    if index + 1 < len(args):
        with open(args[index + 1], "w", encoding="utf-8") as store:
            store.write("keystore\n")
if "-outFile" in args:
    index = args.index("-outFile")
    if index + 1 < len(args):
        with open(args[index + 1], "w", encoding="utf-8") as out:
            out.write("-----BEGIN CERTIFICATE-----\nfixture\n-----END CERTIFICATE-----\n")
''');
  await Link('${jbr.path}/java').create(fakeJava.path);
  final fakeNode = File('${root.path}/fake_node');
  await _writeExecutable(fakeNode, '''
#!/bin/sh
root="\$3"
mkdir -p "\$root/material/fd/0" "\$root/material/fd/1" "\$root/material/fd/2" "\$root/material/ac" "\$root/material/ce"
printf "fd0" > "\$root/material/fd/0/fixture"
printf "fd1" > "\$root/material/fd/1/fixture"
printf "fd2" > "\$root/material/fd/2/fixture"
printf "ac" > "\$root/material/ac/fixture"
printf "ce" > "\$root/material/ce/fixture"
printf "00112233445566778899aabbccddeeff\\n"
exit 0
''');
  await Link('${node.path}/node').create(fakeNode.path);
  final fakeHdc = File('${root.path}/fake_hdc');
  await _writeExecutable(fakeHdc, '''
#!/usr/bin/env python3
import os
import sys

log_path = ${jsonEncode(hdcLog.path)}
targets = ${jsonEncode(targets)}
list_targets_exit_code = $hdcListTargetsExitCode
list_targets_stderr = ${jsonEncode(hdcListTargetsStderr)}
install_exit_code = $hdcInstallExitCode
install_stdout = ${jsonEncode(hdcInstallStdout)}
install_stderr = ${jsonEncode(hdcInstallStderr)}
launch_exit_code = $hdcLaunchExitCode
launch_stdout = ${jsonEncode(hdcLaunchStdout)}
launch_stderr = ${jsonEncode(hdcLaunchStderr)}
hilog_stdout = ${jsonEncode(hdcHilogStdout)}
app_denied_layout = ${jsonEncode(hdcAppDeniedLayout)}
permission_dialog_layout = ${jsonEncode(hdcPermissionDialogLayout)}
app_granted_layout = ${jsonEncode(hdcAppGrantedLayout)}
state_path = log_path + ".state"
args = sys.argv[1:]

with open(log_path, "a", encoding="utf-8") as log:
    log.write(" ".join(args) + "\\n")

def read_state():
    try:
        with open(state_path, "r", encoding="utf-8") as state:
            value = state.read().strip()
            if value:
                return value
    except FileNotFoundError:
        pass
    return "app_denied"

def write_state(value):
    with open(state_path, "w", encoding="utf-8") as state:
        state.write(value)

if len(args) >= 2 and args[0] == "list" and args[1] == "targets":
    sys.stdout.write(targets)
    sys.stderr.write(list_targets_stderr)
    raise SystemExit(list_targets_exit_code)

if "install" in args:
    sys.stdout.write(install_stdout)
    sys.stderr.write(install_stderr)
    raise SystemExit(install_exit_code)

if "aa" in args and "start" in args:
    if not read_state():
        write_state("app_denied")
    sys.stdout.write(launch_stdout)
    sys.stderr.write(launch_stderr)
    raise SystemExit(launch_exit_code)

if "aa" in args and "force-stop" in args:
    raise SystemExit(0)

if "bm" in args and "clean" in args:
    write_state("app_denied")
    sys.stdout.write("clean bundle data files successfully.\\n")
    raise SystemExit(0)

if "uitest" in args and "dumpLayout" in args:
    sys.stdout.write("DumpLayout saved to:/data/local/tmp/layout_fixture.json\\n")
    raise SystemExit(0)

if len(args) >= 2 and args[-2] == "cat" and args[-1] == "/data/local/tmp/layout_fixture.json":
    state = read_state()
    if state == "permission_dialog":
        sys.stdout.write(permission_dialog_layout)
    elif state == "app_granted":
        sys.stdout.write(app_granted_layout)
    else:
        sys.stdout.write(app_denied_layout)
    raise SystemExit(0)

if "uitest" in args and "click" in args:
    state = read_state()
    if state == "app_denied":
        write_state("permission_dialog")
    elif state == "permission_dialog":
        write_state("app_granted")
    raise SystemExit(0)

if "uitest" in args and "swipe" in args:
    raise SystemExit(0)

if "uitest" in args and "inputText" in args:
    raise SystemExit(0)

if "uitest" in args and "keyEvent" in args:
    raise SystemExit(0)

if "hilog" in args:
    sys.stdout.write(hilog_stdout)
    raise SystemExit(0)

if "snapshot_display" in args:
    raise SystemExit(0)

if "file" in args and "recv" in args:
    local_path = args[-1]
    os.makedirs(os.path.dirname(local_path), exist_ok=True)
    with open(local_path, "wb") as out:
        out.write(b"fake-ohos-screenshot")
    raise SystemExit(0)

raise SystemExit(1)
''');
  await Link('${toolchains.path}/hdc').create(fakeHdc.path);
  await _writeExecutable(File('${emulatorDirectory.path}/Emulator'), '''
#!/bin/sh
exit 0
''');
  return devEco;
}

String _ohosPermissionExampleLayout(String cameraStatus) {
  return jsonEncode({
    'attributes': {'bounds': '[0,0][1272,2756]'},
    'children': [
      {
        'attributes': {
          'bounds': '[0,563][1272,806]',
          'clickable': 'true',
          'text': 'Permission.camera\n$cameraStatus',
          'originalText': 'Permission.camera\n$cameraStatus',
          'type': 'Button',
        },
        'children': <Object?>[],
      },
    ],
  });
}

String _ohosPermissionDialogLayout() {
  return jsonEncode({
    'attributes': {'bounds': '[0,0][1272,2756]'},
    'children': [
      {
        'attributes': {
          'bounds': '[108,1582][608,1717]',
          'clickable': 'true',
          'id': 'permission_dialog_deny_button',
          'key': 'permission_dialog_deny_button',
          'type': 'Button',
        },
        'children': [
          {
            'attributes': {
              'bounds': '[277,1618][439,1681]',
              'text': '不允许',
              'originalText': '不允许',
              'type': 'Text',
            },
            'children': <Object?>[],
          },
        ],
      },
      {
        'attributes': {
          'bounds': '[664,1582][1164,1717]',
          'clickable': 'true',
          'id': 'permission_dialog_primary_button',
          'key': 'permission_dialog_primary_button',
          'type': 'Button',
        },
        'children': [
          {
            'attributes': {
              'bounds': '[760,1618][1068,1681]',
              'text': '本次使用允许',
              'originalText': '本次使用允许',
              'type': 'Text',
            },
            'children': <Object?>[],
          },
        ],
      },
    ],
  });
}

Future<void> _writeExecutable(File file, String content) async {
  await file.parent.create(recursive: true);
  await file.writeAsString(content);
  await _runProcess('chmod', ['+x', file.path], file.parent);
}

Future<Directory> _writeAndroidSdkFixture(
  Directory root,
  String logPath, {
  String avds = 'Pixel_35',
  Map<String, int> emulatorFailures = const {},
}) async {
  final sdk = Directory('${root.path}/android-sdk');
  await _writeTool(
    File('${sdk.path}/emulator/emulator'),
    logPath,
    'android-emulator',
    failures: emulatorFailures,
    stdoutByCommand: {'-list-avds': avds},
  );
  return sdk;
}

Future<File> _writeAndroidAdbFixture(
  Directory root,
  String logPath, {
  required String uiXml,
  required String logcat,
}) async {
  final adb = File('${root.path}/adb');
  await _writeExecutable(adb, '''
#!/bin/sh
printf "%s\\n" "\$*" >> ${_shellSingleQuote(logPath)}
if [ "\$1" = "-s" ]; then
  shift 2
fi

case "\$*" in
  "shell pm clear com.example.camera")
    exit 0
    ;;
  "shell monkey -p com.example.camera -c android.intent.category.LAUNCHER 1")
    exit 0
    ;;
  "shell uiautomator dump /sdcard/fluoh-window.xml")
    printf "%s\\n" "UI hierarchy dumped to /sdcard/fluoh-window.xml"
    exit 0
    ;;
  "exec-out cat /sdcard/fluoh-window.xml")
    printf "%s\\n" ${_shellSingleQuote(uiXml)}
    exit 0
    ;;
  "shell input tap 60 50")
    exit 0
    ;;
  "shell input swipe 10 20 30 40 250")
    exit 0
    ;;
  "exec-out screencap -p")
    printf "%s" "fake-android-screenshot"
    exit 0
    ;;
  "logcat -d -t 200")
    printf "%s\\n" ${_shellSingleQuote(logcat)}
    exit 0
    ;;
esac

printf "%s\\n" "unsupported adb \$*" >&2
exit 1
''');
  return adb;
}

Future<File> _writeXcrunFixture(
  Directory root,
  String logPath, {
  bool supportsXCTest = false,
  bool iosAppInstalled = true,
  String? simctlDevicesJson,
  String? devicectlDevicesJson,
  String? bootSimulatorId,
}) async {
  final xcrun = File('${root.path}/xcrun');
  await _writeExecutable(xcrun, '''
#!/bin/sh
printf "%s\\n" "\$*" >> ${_shellSingleQuote(logPath)}

case "\$*" in
${simctlDevicesJson == null ? '' : '''
  "simctl list devices available --json")
    cat <<'JSON'
$simctlDevicesJson
JSON
    exit 0
    ;;
'''}
${devicectlDevicesJson == null ? '' : '''
  "devicectl list devices --json")
    cat <<'JSON'
$devicectlDevicesJson
JSON
    exit 0
    ;;
'''}
${bootSimulatorId == null ? '' : '''
  "simctl boot $bootSimulatorId")
    exit 0
    ;;
  "simctl bootstatus $bootSimulatorId -b")
    exit 0
    ;;
'''}
  simctl\\ get_app_container\\ ios-sim\\ *\\ app)
${iosAppInstalled ? '''
    printf "%s\\n" "/tmp/Runner.app"
    exit 0
''' : '''
    printf "%s\\n" "No such file or directory" >&2
    exit 1
'''}
    ;;
  simctl\\ install\\ ios-sim\\ *)
    exit 0
    ;;
  simctl\\ launch\\ ios-sim\\ *)
    printf "%s\\n" "com.example.camera: 12345"
    exit 0
    ;;
  simctl\\ io\\ ios-sim\\ screenshot\\ *)
    for output_path in "\$@"; do :; done
    mkdir -p "\$(dirname "\$output_path")"
    printf "%s" "fake-ios-screenshot" > "\$output_path"
    exit 0
    ;;
  "simctl privacy ios-sim reset camera com.example.camera")
    exit 0
    ;;
  "simctl privacy ios-sim grant camera com.example.camera")
    exit 0
    ;;
${supportsXCTest ? '''
  xcodebuild\\ test*)
    printf "%s\\n" "Test Suite 'PermissionPromptUITests' passed"
    exit 0
    ;;
''' : ''}
esac

printf "%s\\n" "unsupported xcrun \$*" >&2
exit 1
''');
  return xcrun;
}

String _shellSingleQuote(String value) {
  return "'${value.replaceAll("'", "'\"'\"'")}'";
}

Future<void> _runProcess(
  String executable,
  List<String> arguments,
  Directory workingDirectory,
) async {
  final result = await Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory.path,
  );
  if (result.exitCode != 0) {
    fail('$executable ${arguments.join(' ')} failed:\n${result.stderr}');
  }
}
