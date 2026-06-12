import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

part 'fluoh_skill_scripts_preflight_part.dart';
part 'fluoh_skill_scripts_report_part.dart';
part 'fluoh_skill_scripts_check_report_part.dart';
part 'fluoh_skill_scripts_misc_part.dart';

const preflightScript = 'skills/fluoh/scripts/preflight.py';
const reportScript = 'skills/fluoh/scripts/new_report.py';
const summaryScript = 'skills/fluoh/scripts/new_summary.py';
const checkReportScript = 'skills/fluoh/scripts/check_report.py';
const scenarioScript = 'skills/fluoh/scripts/new_scenario.py';
const inspectSessionScript = 'skills/fluoh/scripts/inspect_session.py';
const collectFeedbackScript = 'skills/fluoh/scripts/collect_feedback.py';

Future<Directory> createTempRoot() {
  return Directory.systemTemp.createTemp('fluoh_skill_script_');
}

Future<File> writeFakeFluoh(
  Directory root, {
  String docsDryRunOutput = 'Package docs are current',
  int docsDryRunExitCode = 0,
}) async {
  final tool = File('${root.path}/fluoh');
  await tool.writeAsString('''
#!/bin/sh
if [ "\$1" = "--version" ]; then
echo "fluoh 9.9.9"
exit 0
fi
if [ "\$1" = "package" ] && [ "\$2" = "docs" ] && [ "\$3" = "refresh" ] && [ "\$4" = "--dry-run" ]; then
cat <<'EOF'
$docsDryRunOutput
EOF
exit $docsDryRunExitCode
fi
echo "unexpected args: \$@" >&2
exit 64
''');
  final chmod = await Process.run('chmod', ['+x', tool.path]);
  expect(chmod.exitCode, 0, reason: chmod.stderr.toString());
  return tool;
}

Future<File> writeFakeDartRunner(Directory root) async {
  final tool = File('${root.path}/dart-runner');
  await tool.writeAsString('''
#!/bin/sh
if [ "\$1" = "run" ] && [ "\$2" = "bin/fluoh.dart" ] && [ "\$3" = "--version" ]; then
echo "fluoh 8.8.8"
exit 0
fi
echo "unexpected args: \$@" >&2
exit 64
''');
  final chmod = await Process.run('chmod', ['+x', tool.path]);
  expect(chmod.exitCode, 0, reason: chmod.stderr.toString());
  return tool;
}

Future<File> writeFakeDartExecutable(
  Directory root, {
  required String scriptPath,
  List<String> extraArgs = const [],
}) async {
  final tool = File('${root.path}/dart');
  final expected = [scriptPath, ...extraArgs, '--version'];
  final checks = [
    for (var i = 0; i < expected.length; i += 1)
      '[ "\$${i + 1}" = "${expected[i]}" ]',
    '[ "\$#" = "${expected.length}" ]',
  ].join(' && ');
  await tool.writeAsString('''
#!/bin/sh
if $checks; then
echo "fluoh 7.7.7"
exit 0
fi
echo "unexpected args: \$@" >&2
exit 64
''');
  final chmod = await Process.run('chmod', ['+x', tool.path]);
  expect(chmod.exitCode, 0, reason: chmod.stderr.toString());
  return tool;
}

Future<File> writeFakeFlutterDartWrapper(
  Directory root, {
  required String scriptPath,
}) async {
  final bin = Directory('${root.path}/flutter/bin');
  final cacheBin = Directory('${bin.path}/cache/dart-sdk/bin');
  await cacheBin.create(recursive: true);
  final wrapper = File('${bin.path}/dart');
  await wrapper.writeAsString('''
#!/bin/sh
echo "flutter wrapper should not be used" >&2
exit 65
''');
  final cachedDart = File('${cacheBin.path}/dart');
  await cachedDart.writeAsString('''
#!/bin/sh
if [ "\$1" = "$scriptPath" ] && [ "\$2" = "--version" ]; then
echo "fluoh 6.6.6"
exit 0
fi
echo "unexpected cached dart args: \$@" >&2
exit 64
''');
  for (final tool in [wrapper, cachedDart]) {
    final chmod = await Process.run('chmod', ['+x', tool.path]);
    expect(chmod.exitCode, 0, reason: chmod.stderr.toString());
  }
  return wrapper;
}

Future<Map<String, Object?>> runPreflight(
  Directory root, {
  required String fluohCommand,
  String? path,
  Map<String, String>? environment,
}) async {
  final result = await Process.run('python3', [
    preflightScript,
    path ?? root.path,
    '--fluoh-command',
    fluohCommand,
  ], environment: environment);
  expect(result.exitCode, 0, reason: result.stderr.toString());
  return jsonDecode(result.stdout.toString()) as Map<String, Object?>;
}

Future<void> runProcess(
  String executable,
  List<String> arguments,
  Directory workingDirectory,
) async {
  final result = await Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory.path,
  );
  expect(
    result.exitCode,
    0,
    reason: '$executable ${arguments.join(' ')}\n${result.stderr}',
  );
}

List<String> stringList(Object? value) {
  return (value as List<Object?>).cast<String>();
}

void main() {
  _registerFluohSkillScriptsPreflightTests();
  _registerFluohSkillScriptsReportTests();
  _registerFluohSkillScriptsCheckReportTests();
  _registerFluohSkillScriptsMiscTests();
}
