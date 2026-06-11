import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

import '../../cli/argument_validation.dart';
import '../../cli/command_usage.dart';
import '../../cli/fluoh_command_runner.dart';
import '../../cli/machine_output.dart';
import '../../cli/terminal_output.dart';
import '../../context/fluoh_environment.dart';
import '../../schema/yaml_utils.dart';

/// Top-level `fluoh report` command group.
class ReportCommand extends FluohCommand<int> {
  /// Creates the report command group.
  ReportCommand({
    required FluohEnvironment environment,
    required OutputWriter stdout,
    TerminalOutput? output,
  }) : _output = output ?? TerminalOutput(stdout: stdout) {
    addSubcommand(
      ReportCreateCommand(
        environment: environment,
        stdout: stdout,
        output: _output,
      ),
    );
  }

  final TerminalOutput _output;

  @override
  String get name => 'report';

  @override
  String get description => 'Create local AI adaptation reports.';

  @override
  String get usage => '$description\n\n$_usageWithoutDescription';

  @override
  void printUsage() {
    _output.write(usage);
  }

  @override
  Never usageException(String message) {
    throw UsageException(message, _usageWithoutDescription);
  }

  String get _usageWithoutDescription {
    return [
      'Usage: $invocation',
      argParser.usage,
      '',
      formatCommandUsage(
        subcommands,
        sections: const [
          CommandUsageSection('Reports:', ['create']),
        ],
        isSubcommand: true,
        lineLength: argParser.usageLineLength,
        style: _output.style,
      ),
      '',
      'Run "${runner!.executableName} help" to see global options.',
    ].join('\n');
  }
}

/// Creates a local AI adaptation report from collected evidence.
class ReportCreateCommand extends FluohCommand<int> {
  /// Creates the report creation command.
  ReportCreateCommand({
    required this.environment,
    required this.stdout,
    TerminalOutput? output,
  }) : _output = output ?? TerminalOutput(stdout: stdout) {
    argParser
      ..addOption(
        'scope',
        valueHelp: 'name',
        help:
            'Report scope. Defaults to --package, then pubspec package name or app.',
      )
      ..addOption('package', valueHelp: 'name', help: 'Package name.')
      ..addOption(
        'output',
        valueHelp: 'path',
        help:
            'Report path. Defaults to .fluoh/reports/<scope>/ai-report-....md.',
      )
      ..addMultiOption(
        'trace-dir',
        valueHelp: 'path',
        help: 'Trace directory, trace.json, or directory containing traces.',
      )
      ..addMultiOption(
        'automation-json',
        valueHelp: 'path',
        help: 'Saved fluoh drive --json output to include.',
      )
      ..addOption(
        'recommendation',
        allowed: const ['ready', 'needs-maintainer-decision', 'blocked'],
        defaultsTo: 'blocked',
        help: 'Release recommendation to write.',
      )
      ..addFlag('json', negatable: false, help: 'Print the result as JSON.');
  }

  /// Runtime environment.
  final FluohEnvironment environment;

  /// JSON output writer.
  final OutputWriter stdout;

  final TerminalOutput _output;

  @override
  String get name => 'create';

  @override
  String get description =>
      'Create an AI adaptation report from trace and automation JSON.';

  @override
  Future<int> run() async {
    expectNoArguments(argResults!, usageException);
    final scope = _scope();
    final report = await _composeReport(
      environment: environment,
      scope: scope,
      packageName: argResults!.option('package')?.trim(),
      tracePaths: argResults!.multiOption('trace-dir'),
      automationPaths: argResults!.multiOption('automation-json'),
      recommendation: argResults!.option('recommendation') ?? 'blocked',
    );
    final output = _resolveReportOutput(scope);
    await output.parent.create(recursive: true);
    await output.writeAsString(report.content);
    if (argResults!.flag('json')) {
      writeMachineOutput(
        stdout,
        command: 'report create',
        ok: true,
        exitCode: 0,
        fields: {
          'changed': true,
          'report': output.path,
          'scope': scope,
          'commandRows': report.commandRows,
          'automationRows': report.automationRows,
          'interactionRows': report.interactionRows,
        },
      );
    } else {
      _output.success('Report created');
      _output.info('Report: ${_output.style.path(output.path)}');
      _output.next(
        'Run python3 <skill-dir>/scripts/check_report.py ${output.path}',
      );
    }
    return 0;
  }

  String _scope() {
    final option = argResults!.option('scope')?.trim();
    if (option != null && option.isNotEmpty) {
      return option;
    }
    final package = argResults!.option('package')?.trim();
    if (package != null && package.isNotEmpty) {
      return package;
    }
    final pubspec = File('${environment.workingDirectory.path}/pubspec.yaml');
    if (pubspec.existsSync()) {
      try {
        final yaml = parseYamlMap(
          pubspec.readAsStringSync(),
          label: 'pubspec.yaml',
        );
        final name = yaml['name'];
        if (name is String && name.trim().isNotEmpty) {
          return name.trim();
        }
      } on Object {
        // Fall back to the generic app scope when pubspec.yaml is malformed.
      }
    }
    return 'app';
  }

  File _resolveReportOutput(String scope) {
    final output = argResults!.option('output')?.trim();
    if (output != null && output.isNotEmpty) {
      final file = File(output);
      return file.isAbsolute
          ? file
          : File('${environment.workingDirectory.path}/$output');
    }
    final slug = _slug(scope);
    final stamp = _timestamp(DateTime.now());
    return availableReportOutput(
      '${environment.workingDirectory.path}/.fluoh/reports/$slug/ai-report-$stamp.md',
    );
  }
}

/// Returns a report file path that does not overwrite an existing file.
File availableReportOutput(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    return file;
  }
  final dot = path.lastIndexOf('.');
  final stem = dot == -1 ? path : path.substring(0, dot);
  final extension = dot == -1 ? '' : path.substring(dot);
  for (var index = 2; ; index += 1) {
    final candidate = File('$stem-$index$extension');
    if (!candidate.existsSync()) {
      return candidate;
    }
  }
}

Future<_ComposedReport> _composeReport({
  required FluohEnvironment environment,
  required String scope,
  required String? packageName,
  required List<String> tracePaths,
  required List<String> automationPaths,
  required String recommendation,
}) async {
  final traces = <Map<String, Object?>>[];
  for (final raw in tracePaths) {
    for (final manifest in await _traceManifests(environment, raw)) {
      traces.add(await _readJsonObject(manifest));
    }
  }
  final automation = <Map<String, Object?>>[];
  for (final raw in automationPaths) {
    automation.add(await _readJsonObject(_resolveFile(environment, raw)));
  }
  final commandRows = _commandRows(traces, automation);
  final automationRows = _automationCoverageRows(automation);
  final automationGatesReady = _automationGatesReady(automation);
  final interactionRows = _interactionRows(automation);
  final feedbackRows = _feedbackRows(traces);
  final packageValue = packageName?.isNotEmpty == true ? packageName! : '';
  final content = [
    '# fluoh AI Report',
    '',
    '- Scope: $scope',
    '- Repository: ${environment.workingDirectory.path}',
    '- Package: $packageValue',
    '- Upstream version:',
    '- FlutterOH SDK:',
    '- Date: ${DateTime.now().toIso8601String()}',
    '- Recommendation: $recommendation',
    '',
    '## Summary',
    '',
    '- Report composed from ${traces.length} trace manifest(s) and ${automation.length} automation JSON file(s).',
    '',
    '## Changes',
    '',
    '- Review git diff for implementation and project-file changes.',
    '',
    '## Public API / Compatibility',
    '',
    '- Public Dart API changes:',
    '- Dependency constraint changes:',
    '- Non-OHOS regression risk:',
    '',
    '## Commands',
    '',
    '| Command | Exit | Result | Notes |',
    '| --- | --- | --- | --- |',
    if (commandRows.isEmpty)
      '| `fluoh verify --json` | n/a | blocked | No trace or automation command evidence supplied. |'
    else
      ...commandRows.map((row) => row.toMarkdownRow()),
    '',
    '## Delivery Checklist',
    '',
    '- [ ] Diff reviewed; unrelated files, local paths, generated caches, credentials, and private tokens excluded.',
    '- [${commandRows.isEmpty ? ' ' : 'x'}] Commands table includes exit codes and enough evidence to reproduce the decision.',
    '- [ ] OHOS build evidence recorded.',
    '- [ ] OHOS run evidence recorded, or the missing device/emulator blocker is explicit.',
    '- [ ] Android, iOS, macOS, Linux, Web, and Windows regression checks recorded when relevant.',
    '- [${automationGatesReady ? 'x' : ' '}] Real `fluoh drive --json` evidence recorded, with no unresolved ready-blocking gates.',
    '- [${interactionRows.isEmpty ? ' ' : 'x'}] Functional interaction evidence recorded for permission, file, camera, location, media, deep link, external-app, or other device workflows.',
    '- [ ] Public API, dependency constraints, and non-OHOS regression risk reviewed.',
    '- [ ] Remaining risks and release decision are explicit.',
    '',
    '## Platform Matrix',
    '',
    '| Platform | Build | Run | Integration test | Target | Evidence / blocker |',
    '| --- | --- | --- | --- | --- | --- |',
    ..._platformRows(commandRows),
    '',
    '## Automation Coverage',
    '',
    ..._automationSummaryLines(automation),
    '',
    '| Gate | Status | Evidence / blocker |',
    '| --- | --- | --- |',
    if (automationRows.isEmpty)
      '| coverage-inventory | blocked | No automation JSON supplied. |'
    else
      ...automationRows,
    '',
    '## Interaction Evidence',
    '',
    if (interactionRows.isEmpty)
      'No interaction required: no passed scenario evidence was supplied to report create.'
    else ...[
      '| Scenario | Method | Platform | Target | Result | Evidence / blocker |',
      '| --- | --- | --- | --- | --- | --- |',
      ...interactionRows,
    ],
    '',
    '## Diagnostics',
    '',
    ..._diagnosticLines(traces, automation),
    '',
    '## Fluoh Feedback',
    '',
    if (feedbackRows.isEmpty)
      'No fluoh feedback: no trace feedback candidates were supplied.'
    else ...[
      '| ID | Owner | Category | Evidence | Proposed fluoh change | Status |',
      '| --- | --- | --- | --- | --- | --- |',
      ...feedbackRows,
    ],
    '',
    '## Signing',
    '',
    '- Mode:',
    '- Generated HAPs:',
    '- Hilog:',
    '',
    '## Remaining Risks',
    '',
    '- Complete unchecked delivery items before claiming ready.',
    '',
    '## Local State',
    '',
    '- Git status summary:',
    '- Files intentionally left uncommitted:',
    '- Files that must not be committed:',
    '',
    '## Release Decision',
    '',
    'Release recommendation: $recommendation',
    '',
    'Reason: composed report requires final human/agent review before release certification.',
    '',
  ].join('\n');
  return _ComposedReport(
    content: content,
    commandRows: commandRows.length,
    automationRows: automationRows.length,
    interactionRows: interactionRows.length,
  );
}

class _ComposedReport {
  const _ComposedReport({
    required this.content,
    required this.commandRows,
    required this.automationRows,
    required this.interactionRows,
  });

  final String content;
  final int commandRows;
  final int automationRows;
  final int interactionRows;
}

Future<List<File>> _traceManifests(
  FluohEnvironment environment,
  String rawPath,
) async {
  final path = _resolveFile(environment, rawPath);
  if (path.existsSync()) {
    return [path];
  }
  final directory = _resolveDirectory(environment, rawPath);
  if (!directory.existsSync()) {
    throw FormatException('Trace path ${path.path} does not exist.');
  }
  final direct = File('${directory.path}/trace.json');
  if (direct.existsSync()) {
    return [direct];
  }
  final manifests = <File>[];
  await for (final entity in directory.list(recursive: true)) {
    if (entity is File && entity.path.endsWith('/trace.json')) {
      manifests.add(entity);
    }
  }
  if (manifests.isEmpty) {
    throw FormatException(
      'Trace path ${directory.path} does not contain trace.json.',
    );
  }
  manifests.sort((a, b) => a.path.compareTo(b.path));
  return manifests;
}

File _resolveFile(FluohEnvironment environment, String path) {
  final file = File(path);
  return file.isAbsolute
      ? file
      : File('${environment.workingDirectory.path}/$path');
}

Directory _resolveDirectory(FluohEnvironment environment, String path) {
  final directory = Directory(path);
  return directory.isAbsolute
      ? directory
      : Directory('${environment.workingDirectory.path}/$path');
}

Future<Map<String, Object?>> _readJsonObject(File file) async {
  if (!await file.exists()) {
    throw FormatException('JSON input ${file.path} does not exist.');
  }
  late final String content;
  try {
    content = await file.readAsString();
  } on FileSystemException catch (error) {
    throw FormatException(
      'Could not read JSON input ${file.path}: ${error.message}',
    );
  }
  late final Object? decoded;
  try {
    decoded = jsonDecode(content);
  } on FormatException catch (error) {
    throw FormatException(
      'Could not parse JSON input ${file.path}: ${error.message}',
    );
  }
  if (decoded is! Map<String, Object?>) {
    throw FormatException('${file.path} must contain one JSON object.');
  }
  return decoded;
}

List<_CommandEvidence> _commandRows(
  List<Map<String, Object?>> traces,
  List<Map<String, Object?>> automation,
) {
  final rows = <_CommandEvidence>[];
  for (final trace in traces) {
    final invocations = trace['invocations'];
    if (invocations is! List<Object?>) {
      rows.add(_commandEvidence(trace));
      continue;
    }
    for (final item in invocations) {
      if (item is Map<String, Object?>) {
        rows.add(_commandEvidence(item));
      }
    }
  }
  for (final item in automation) {
    rows.add(_commandEvidence(item));
  }
  return rows;
}

_CommandEvidence _commandEvidence(Map<String, Object?> item) {
  final command =
      item['commandLine'] as String? ??
      item['command'] as String? ??
      'fluoh drive --json';
  final exitCode = item['exitCode']?.toString() ?? 'n/a';
  final ok = item['ok'];
  final passed = ok is bool ? ok : exitCode == '0';
  return _CommandEvidence(
    command: command,
    exitCode: exitCode,
    status: passed ? 'passed' : 'failed',
    note: _rowNote(item),
  );
}

String _rowNote(Map<String, Object?> item) {
  final result = item['result'];
  if (result is Map && result['trace'] is Map) {
    return 'trace ${(result['trace'] as Map)['manifest'] ?? ''}'.trim();
  }
  final trace = item['trace'];
  if (trace is Map && trace['manifest'] != null) {
    return 'trace ${trace['manifest']}';
  }
  return '';
}

List<String> _automationCoverageRows(List<Map<String, Object?>> automation) {
  final rows = <String>[];
  for (final item in automation) {
    final automationJson = item['automation'];
    final coveragePolicy = automationJson is Map
        ? automationJson['coveragePolicy']
        : null;
    if (coveragePolicy is! Map) {
      continue;
    }
    final qualityGates = coveragePolicy['qualityGates'];
    if (qualityGates is! List<Object?>) {
      continue;
    }
    for (final gate in qualityGates) {
      if (gate is! Map) {
        continue;
      }
      rows.add(
        '| ${_escapeCell('${gate['id'] ?? ''}')} | ${_escapeCell('${gate['status'] ?? ''}')} | ${_escapeCell('${gate['repair'] ?? gate['evidence'] ?? ''}')} |',
      );
    }
  }
  return rows;
}

bool _automationGatesReady(List<Map<String, Object?>> automation) {
  var hasCoveragePolicy = false;
  for (final item in automation) {
    final automationJson = item['automation'];
    final coveragePolicy = automationJson is Map
        ? automationJson['coveragePolicy']
        : null;
    if (coveragePolicy is! Map) {
      continue;
    }
    hasCoveragePolicy = true;
    if (coveragePolicy['readyForAutomation'] != true) {
      return false;
    }
    final qualityGates = coveragePolicy['qualityGates'];
    if (qualityGates is! List<Object?> || qualityGates.isEmpty) {
      return false;
    }
    for (final gate in qualityGates) {
      if (gate is! Map || gate['status'] != 'readyForReview') {
        return false;
      }
    }
  }
  return hasCoveragePolicy;
}

List<String> _interactionRows(List<Map<String, Object?>> automation) {
  final rows = <String>[];
  for (final item in automation) {
    final targets = item['targets'];
    if (targets is! List<Object?>) {
      continue;
    }
    for (final target in targets) {
      if (target is! Map) {
        continue;
      }
      final steps = target['steps'];
      if (steps is! List<Object?>) {
        continue;
      }
      for (final step in steps) {
        if (step is! Map ||
            !'${step['name'] ?? ''}'.startsWith('automation-scenario-')) {
          continue;
        }
        rows.add(
          '| `${_escapeCell('${step['name'] ?? ''}')}` | AI-assisted | ${_escapeCell('${target['platform'] ?? ''}')} | ${_escapeCell('${target['targetName'] ?? ''}')} | ${_escapeCell('${step['status'] ?? ''}')} | ${_escapeCell('${step['reason'] ?? step['path'] ?? ''}')} |',
        );
      }
    }
  }
  return rows;
}

List<String> _platformRows(List<_CommandEvidence> commandRows) {
  final platforms = const [
    'OHOS',
    'Android',
    'iOS',
    'macOS',
    'Linux',
    'Web',
    'Windows',
  ];
  return [
    for (final platform in platforms)
      '| $platform | ${_platformCommandStatus(commandRows, platform, 'build')} | ${_platformCommandStatus(commandRows, platform, 'run')} | n/a | n/a | composed from command rows |',
  ];
}

String _platformCommandStatus(
  List<_CommandEvidence> rows,
  String platform,
  String verb,
) {
  final token = 'fluoh $verb ${platform.toLowerCase()}';
  final matches = rows.where((row) => row.command.contains(token));
  if (matches.any((row) => row.passed)) {
    return 'passed';
  }
  if (matches.isNotEmpty) {
    return 'failed';
  }
  return 'skipped';
}

List<String> _automationSummaryLines(List<Map<String, Object?>> automation) {
  for (final item in automation) {
    final automationJson = item['automation'];
    final coveragePolicy = automationJson is Map
        ? automationJson['coveragePolicy']
        : null;
    if (coveragePolicy is Map) {
      return [
        '- coveragePolicy.status: ${coveragePolicy['status'] ?? 'unknown'}',
        '- readyForAutomation: ${coveragePolicy['readyForAutomation'] ?? 'unknown'}',
        '- qualityGateSummary: ${coveragePolicy['qualityGateSummary'] ?? 'unknown'}',
      ];
    }
  }
  return const [
    '- coveragePolicy.status: blocked',
    '- readyForAutomation: false',
    '- qualityGateSummary: ready=0, notReady=1',
  ];
}

List<String> _diagnosticLines(
  List<Map<String, Object?>> traces,
  List<Map<String, Object?>> automation,
) {
  final diagnostics = <String>[];
  for (final trace in traces) {
    diagnostics.addAll(_diagnosticsFromObject(trace));
  }
  for (final item in automation) {
    diagnostics.addAll(_diagnosticsFromObject(item));
  }
  if (diagnostics.isEmpty) {
    return const ['- No diagnostics supplied.'];
  }
  return diagnostics.map((item) => '- $item').toList();
}

List<String> _diagnosticsFromObject(Object? value) {
  final items = <String>[];
  void visit(Object? node) {
    if (node is Map) {
      if (node['code'] != null && node['message'] != null) {
        items.add('${node['code']}: ${node['message']}');
      }
      for (final child in node.values) {
        visit(child);
      }
    } else if (node is List) {
      for (final child in node) {
        visit(child);
      }
    }
  }

  visit(value);
  return items;
}

List<String> _feedbackRows(List<Map<String, Object?>> traces) {
  final rows = <String>[];
  for (final trace in traces) {
    final feedback = trace['feedbackCandidates'];
    if (feedback is! List<Object?>) {
      continue;
    }
    for (final item in feedback) {
      if (item is! Map) {
        continue;
      }
      rows.add(
        '| ${_escapeCell('${item['id'] ?? ''}')} | ${_escapeCell('${item['owner'] ?? ''}')} | ${_escapeCell('${item['category'] ?? ''}')} | ${_escapeCell('${trace['id'] ?? ''}')} | ${_escapeCell('${item['suggestedChange'] ?? ''}')} | queued |',
      );
    }
  }
  return rows;
}

String _slug(String value) {
  final slug = value
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
      .replaceAll(RegExp(r'^[-._]+|[-._]+$'), '');
  return slug.isEmpty ? 'report' : slug;
}

String _timestamp(DateTime now) {
  return '${now.year.toString().padLeft(4, '0')}'
      '${now.month.toString().padLeft(2, '0')}'
      '${now.day.toString().padLeft(2, '0')}-'
      '${now.hour.toString().padLeft(2, '0')}'
      '${now.minute.toString().padLeft(2, '0')}'
      '${now.second.toString().padLeft(2, '0')}';
}

String _escapeCell(String value) {
  return value.replaceAll('|', r'\|').replaceAll('\n', ' ').trim();
}

class _CommandEvidence {
  const _CommandEvidence({
    required this.command,
    required this.exitCode,
    required this.status,
    required this.note,
  });

  final String command;
  final String exitCode;
  final String status;
  final String note;

  bool get passed => status == 'passed';

  String toMarkdownRow() {
    return '| `${_escapeCell(command)}` | $exitCode | $status | ${_escapeCell(note)} |';
  }
}
