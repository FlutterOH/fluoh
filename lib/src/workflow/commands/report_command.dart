import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

import '../../cli/argument_validation.dart';
import '../../cli/command_usage.dart';
import '../../cli/fluoh_command_runner.dart';
import '../../cli/machine_output.dart';
import '../../cli/terminal_output.dart';
import '../../context/fluoh_environment.dart';
import '../../package/package_scope.dart';
import '../../schema/yaml_utils.dart';
import '../../task/task_workspace.dart';
import '../platform_workflow_policy.dart';

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
  String get description => 'Create a local AI support report.';

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

/// Creates a local AI support report from collected evidence.
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
        help: 'Report path. Defaults to the current task report.',
      )
      ..addOption('task', valueHelp: 'id', help: 'Task workspace id.')
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
        valueHelp: 'recommendation',
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
      'Create an AI support report from trace and automation JSON.';

  @override
  Future<int> run() async {
    expectNoArguments(argResults!, usageException);
    final scope = _scope();
    final packageName = argResults!.option('package')?.trim();
    final task = await TaskWorkspace(environment).resolveOrCreate(
      taskId: argResults!.option('task')?.trim(),
      type: 'report',
      scopeName: scope,
      packageName: packageName,
    );
    final tracePaths = argResults!.multiOption('trace-dir');
    final effectiveTracePaths = tracePaths.isEmpty
        ? await _defaultTracePaths(task)
        : tracePaths;
    final report = await _composeReport(
      environment: environment,
      scope: scope,
      packageName: packageName,
      tracePaths: effectiveTracePaths,
      automationPaths: argResults!.multiOption('automation-json'),
      recommendation: argResults!.option('recommendation') ?? 'blocked',
    );
    final output = _resolveReportOutput(scope, task);
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
          'task': task.toJson(environment.workingDirectory),
          'commandRows': report.commandRows,
          'automationRows': report.automationRows,
          'interactionRows': report.interactionRows,
          if (report.supportScope != null)
            'supportScope': report.supportScope!.toJson(),
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

  File _resolveReportOutput(String scope, FluohTask task) {
    final output = argResults!.option('output')?.trim();
    if (output != null && output.isNotEmpty) {
      final file = File(output);
      return file.isAbsolute
          ? file
          : File('${environment.workingDirectory.path}/$output');
    }
    return File('${task.reportsDirectory.path}/report.md');
  }
}

Future<List<String>> _defaultTracePaths(FluohTask task) async {
  final traces = task.tracesDirectory;
  if (!await traces.exists()) {
    return const [];
  }
  await for (final entity in traces.list(recursive: true, followLinks: false)) {
    if (entity is File && entity.path.endsWith('/trace.json')) {
      return [traces.path];
    }
  }
  return const [];
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
  final explicitAutomation = <Map<String, Object?>>[];
  for (final raw in automationPaths) {
    explicitAutomation.add(
      await _readJsonObject(_resolveFile(environment, raw)),
    );
  }
  final allAutomation = [
    ...explicitAutomation,
    ..._automationEvidenceFromTraces(traces),
  ];
  final releaseAutomation = _latestAutomationCoverageEvidence(allAutomation);
  final commandRows = _commandRows(traces, explicitAutomation);
  final automationGates = _automationCoverageGates(releaseAutomation);
  final automationRows = _automationCoverageRows(automationGates);
  final automationGatesReady = _automationGatesReady(
    automationGates,
    releaseAutomation,
  );
  final interactionRows = _interactionRows(releaseAutomation);
  final feedbackRows = _feedbackRows(traces);
  final packageValue = packageName?.isNotEmpty == true ? packageName! : '';
  final scopeStatus = packageValue.isEmpty
      ? null
      : await inspectPackageScope(
          repository: environment.workingDirectory,
          packageName: packageValue,
        );
  final generatedAt = DateTime.now().toIso8601String();
  return _ComposedReport(
    content: _englishReportContent(
      environment: environment,
      scope: scope,
      packageValue: packageValue,
      generatedAt: generatedAt,
      recommendation: recommendation,
      traceCount: traces.length,
      automationCount: releaseAutomation.length,
      commandRows: commandRows,
      automationRows: automationRows,
      automationGates: automationGates,
      automationGatesReady: automationGatesReady,
      interactionRows: interactionRows,
      feedbackRows: feedbackRows,
      scopeStatus: scopeStatus,
      automation: releaseAutomation,
      diagnosticAutomation: allAutomation,
      traces: traces,
    ),
    commandRows: commandRows.length,
    automationRows: automationRows.length,
    interactionRows: interactionRows.length,
    supportScope: scopeStatus,
  );
}

String _englishReportContent({
  required FluohEnvironment environment,
  required String scope,
  required String packageValue,
  required String generatedAt,
  required String recommendation,
  required int traceCount,
  required int automationCount,
  required List<_CommandEvidence> commandRows,
  required List<String> automationRows,
  required List<_AutomationCoverageGate> automationGates,
  required bool automationGatesReady,
  required List<String> interactionRows,
  required List<String> feedbackRows,
  required PackageScopeStatus? scopeStatus,
  required List<Map<String, Object?>> traces,
  required List<Map<String, Object?>> automation,
  required List<Map<String, Object?>> diagnosticAutomation,
}) {
  return [
    '# fluoh AI Report',
    '',
    '- Scope: $scope',
    '- Repository: ${environment.workingDirectory.path}',
    '- Package: $packageValue',
    '- Upstream version:',
    '- FlutterOH SDK:',
    '- Date: $generatedAt',
    '- Recommendation: $recommendation',
    '',
    '## Summary',
    '',
    '- Report composed from $traceCount trace manifest(s) and $automationCount automation evidence object(s).',
    '- AI owns support changes, command execution, evidence collection, report composition, and the release recommendation.',
    '- The maintainer owns the final publish, push, tag, store, or release approval decision.',
    '',
    '## Support Responsibility',
    '',
    '- AI automation completes implementation, verification, repair loops, platform evidence, and release readiness recommendation.',
    '- Human approval is reserved for the final release decision after reviewing the machine-readable evidence.',
    '- `manual-assisted` means a person operated the device or emulator, but pass/fail still requires tool-readable confirmation such as logs, meaningful session state beyond launch, stable text, semantics, test keys, command JSON, hilog, or app log markers.',
    '',
    '## Changes',
    '',
    '- Review git diff for implementation and project-file changes.',
    '',
    '## Public API / Compatibility',
    '',
    '- Public Dart API changes:',
    '- Dependency constraint changes:',
    '- Existing-platform regression risk:',
    '',
    '## Official Platform Basis',
    '',
    '- Official platform documentation basis:',
    '- Impact on implementation and tests:',
    '',
    '## Support Scope',
    '',
    ..._supportScopeLines(scopeStatus),
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
    '- [ ] Existing package/app tests, example tests, and `integration_test/` were inspected against public API, platform interfaces, permissions, and behavior paths before final verification.',
    '- [${scopeStatus?.complete == true ? 'x' : ' '}] P0 support scope includes per-platform support decisions, platform API basis or reasons, implementation plans where required, test cases, and functional or regression evidence.',
    '- [ ] Missing or weak functional tests were added or repaired before final verification, or a concrete blocker is recorded.',
    '- [ ] Official platform documentation basis was reviewed before implementation, or a concrete unavailable/not-applicable reason is recorded.',
    '- [ ] Target-platform build evidence recorded, including OHOS when in scope.',
    '- [ ] Target-platform run evidence recorded, or the missing device/emulator blocker is explicit.',
    '- [ ] Pub.dev publishability checked with `dart pub publish --dry-run`, or a concrete not-applicable reason is recorded.',
    '- [ ] FlutterOH support checked with fluoh verify/build/run/drive/report gates.',
    '- [ ] Android, iOS, macOS, Linux, Web, and Windows regression checks recorded when relevant.',
    '- [ ] Every existing Android, iOS, macOS, Linux, Web, and Windows platform was functionally checked when supported by the current host/toolchain, or exact diagnostic evidence and skip reason are recorded.',
    '- [${automationGatesReady ? 'x' : ' '}] Interaction automation evidence recorded through a passed `flutter test integration_test -d <device>` command or real `fluoh drive --json`, with no unresolved ready-blocking gates.',
    '- [${interactionRows.isEmpty ? ' ' : 'x'}] Functional interaction evidence recorded for permission, file, camera, location, media, deep link, external-app, or other device workflows.',
    '- [ ] Public API, dependency constraints, and existing-platform regression risk reviewed.',
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
    ..._automationSummaryLines(automation, automationGates),
    '',
    '| Gate | Status | Evidence / blocker |',
    '| --- | --- | --- |',
    ...automationRows,
    '',
    '## Interaction Evidence',
    '',
    '| Scenario | Method | Platform | Target | Result | Evidence / blocker |',
    '| --- | --- | --- | --- | --- | --- |',
    if (interactionRows.isEmpty)
      '| `functional-interaction-evidence` | AI-assisted | ${_escapeCell(_selectedInteractionPlatform(commandRows))} | n/a | blocked | No passed scenario, integration_test, or manual-assisted tool-readable evidence was supplied to report create. |'
    else
      ...interactionRows,
    '',
    '## Diagnostics',
    '',
    ..._diagnosticLines(traces, diagnosticAutomation),
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
    'Reason: AI-generated evidence and recommendation still require final maintainer release approval before publishing.',
    '',
  ].join('\n');
}

class _ComposedReport {
  const _ComposedReport({
    required this.content,
    required this.commandRows,
    required this.automationRows,
    required this.interactionRows,
    required this.supportScope,
  });

  final String content;
  final int commandRows;
  final int automationRows;
  final int interactionRows;
  final PackageScopeStatus? supportScope;
}

List<String> _supportScopeLines(PackageScopeStatus? status) {
  if (status == null) {
    return const [
      '- path: n/a',
      '- exists: false',
      '- planningReady: false',
      '- functionalEvidenceReady: false',
      '- complete: false',
      '- p0: total=0, supportedOrDegraded=0, functionalEvidence=0',
      '',
      'No package support scope supplied: report create did not receive --package.',
    ];
  }
  return [
    '- path: ${status.path}',
    '- exists: ${status.exists}',
    '- planningReady: ${status.planningReady}',
    '- functionalEvidenceReady: ${status.functionalEvidenceReady}',
    '- complete: ${status.complete}',
    '- p0: total=${status.p0Count}, supportedOrDegraded=${status.p0SupportedOrDegradedCount}, functionalEvidence=${status.p0FunctionalEvidenceCount}',
    '',
    if (status.issues.isEmpty)
      'No support scope issues: P0 planning and functional evidence gates are complete.'
    else ...[
      '| Code | Phase | Severity | Scope Entry | Field | Message |',
      '| --- | --- | --- | --- | --- | --- |',
      for (final issue in status.issues)
        '| ${_escapeCell(issue.code)} | ${_escapeCell(issue.phase)} | ${_escapeCell(issue.severity)} | ${_escapeCell(issue.scopeEntry ?? '')} | ${_escapeCell(issue.field ?? '')} | ${_escapeCell(issue.message)} |',
    ],
  ];
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

List<Map<String, Object?>> _automationEvidenceFromTraces(
  List<Map<String, Object?>> traces,
) {
  final automation = <Map<String, Object?>>[];
  for (final trace in traces) {
    final invocations = trace['invocations'];
    if (invocations is List<Object?>) {
      for (final item in invocations) {
        if (item is Map<String, Object?>) {
          final evidence = _automationEvidenceFromInvocation(item);
          if (evidence != null) {
            automation.add(evidence);
          }
        }
      }
      continue;
    }
    final evidence = _automationEvidenceFromInvocation(trace);
    if (evidence != null) {
      automation.add(evidence);
    }
  }
  return automation;
}

Map<String, Object?>? _automationEvidenceFromInvocation(
  Map<String, Object?> invocation,
) {
  final result = invocation['result'];
  if (result is! Map || result['automation'] is! Map) {
    return null;
  }
  return {
    ...Map<String, Object?>.from(result),
    if (invocation['commandLine'] != null)
      'commandLine': invocation['commandLine'],
    if (invocation['command'] != null) 'command': invocation['command'],
    if (invocation['ok'] != null) 'ok': invocation['ok'],
    if (invocation['exitCode'] != null) 'exitCode': invocation['exitCode'],
    if (invocation['createdAt'] != null) 'createdAt': invocation['createdAt'],
  };
}

List<Map<String, Object?>> _latestAutomationCoverageEvidence(
  List<Map<String, Object?>> automation,
) {
  final passthrough = <Map<String, Object?>>[];
  final latestByKey = <String, Map<String, Object?>>{};
  for (final item in automation) {
    if (_automationCoveragePolicy(item) == null) {
      passthrough.add(item);
      continue;
    }
    latestByKey[_automationEvidenceKey(item)] = item;
  }
  return [...passthrough, ...latestByKey.values];
}

Map<Object?, Object?>? _automationCoveragePolicy(Map<String, Object?> item) {
  final automationJson = item['automation'];
  if (automationJson is! Map) {
    return null;
  }
  final coveragePolicy = automationJson['coveragePolicy'];
  return coveragePolicy is Map ? coveragePolicy : null;
}

String _automationEvidenceKey(Map<String, Object?> item) {
  final command = _automationEvidenceCommand(item);
  if (command != null) {
    return _normalizedAutomationEvidenceCommand(command);
  }
  final automationJson = item['automation'];
  if (automationJson is Map) {
    final platforms = automationJson['platforms'];
    final targetSelection = automationJson['targetSelection'];
    final scenarios = automationJson['scenarios'];
    return ['automation', ?platforms, ?targetSelection, ?scenarios].join('|');
  }
  return 'automation:${item.hashCode}';
}

String? _automationEvidenceCommand(Map<String, Object?> item) {
  final commandLine = _nonEmptyString(item['commandLine']);
  if (commandLine != null) {
    return commandLine;
  }
  final automationJson = item['automation'];
  if (automationJson is Map) {
    final rerun = _nonEmptyString(automationJson['rerunCommand']);
    if (rerun != null) {
      return rerun;
    }
  }
  return _normalizedCommand(item['command']);
}

String _normalizedAutomationEvidenceCommand(String command) {
  return command
      .replaceAll(RegExp(r'(^|\s)--dry-run(?=\s|$)'), ' ')
      .replaceAll(RegExp(r'(^|\s)-n(?=\s|$)'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
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
      _automationRerunCommand(item) ??
      _normalizedCommand(item['command']) ??
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

String? _automationRerunCommand(Map<String, Object?> item) {
  final automation = item['automation'];
  if (automation is Map) {
    final rerun = automation['rerunCommand'];
    if (rerun is String && rerun.trim().isNotEmpty) {
      return rerun.trim();
    }
  }
  return null;
}

String? _normalizedCommand(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    return null;
  }
  final command = value.trim();
  if (command == 'drive') {
    return 'fluoh drive --json';
  }
  return command.startsWith('fluoh ') ? command : 'fluoh $command';
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

const _requiredAutomationCoverageGates = [
  'coverage-inventory',
  'coverage-metadata',
  'coverage-items',
  'capability-inventory-coverage',
  'blocked-coverage',
  'scenario-evidence-assertions',
  'page-readiness',
  'existing-test-baseline',
  'manifest-permission-coverage',
  'behavior-paths',
];

const _blockedAutomationCoverageReasons = {
  'coverage-inventory':
      'No complete automation coverage inventory was supplied; run fluoh drive --dry-run --json to generate the required gate set.',
  'coverage-metadata':
      'Scenario coverage metadata is missing or was not supplied.',
  'coverage-items':
      'No scenario, integration_test, or manual-assisted rows were supplied for discovered capabilities.',
  'capability-inventory-coverage':
      'Public API, example flow, and platform capability coverage still need review.',
  'blocked-coverage':
      'Coverage cannot be marked ready until blocked rows are repaired or explicitly classified.',
  'scenario-evidence-assertions':
      'Functional assertions such as assertText, waitText, assertLog, semantics, test keys, or app logs were not supplied.',
  'page-readiness': 'No post-launch page-readiness evidence was supplied.',
  'existing-test-baseline':
      'Existing package, example, and integration test coverage review was not supplied.',
  'manifest-permission-coverage':
      'Manifest permission grant and denied/error path coverage was not supplied.',
  'behavior-paths':
      'Success and negative/error behavior path coverage remains unverified.',
};

List<_AutomationCoverageGate> _automationCoverageGates(
  List<Map<String, Object?>> automation,
) {
  final gates = <_AutomationCoverageGate>[];
  final reportedRequiredGates = <String>{};
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
      final id = _nonEmptyString(gate['id']) ?? '';
      gates.add(
        _AutomationCoverageGate(
          id: id,
          status: _nonEmptyString(gate['status']) ?? '',
          evidence: _nonEmptyString(gate['repair'] ?? gate['evidence']) ?? '',
          generated: false,
        ),
      );
      if (_requiredAutomationCoverageGates.contains(id)) {
        reportedRequiredGates.add(id);
      }
    }
  }
  for (final gate in _requiredAutomationCoverageGates) {
    if (!reportedRequiredGates.contains(gate)) {
      gates.add(_blockedAutomationCoverageGate(gate));
    }
  }
  return gates;
}

_AutomationCoverageGate _blockedAutomationCoverageGate(String gate) {
  return _AutomationCoverageGate(
    id: gate,
    status: 'blocked',
    evidence:
        _blockedAutomationCoverageReasons[gate] ??
        'Required automation coverage gate was not supplied.',
    generated: true,
  );
}

List<String> _automationCoverageRows(List<_AutomationCoverageGate> gates) {
  return [
    for (final gate in gates)
      '| ${_escapeCell(gate.id)} | ${_escapeCell(gate.status)} | ${_escapeCell(gate.evidence)} |',
  ];
}

bool _automationGatesReady(
  List<_AutomationCoverageGate> gates,
  List<Map<String, Object?>> automation,
) {
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
  }
  if (!hasCoveragePolicy) {
    return false;
  }
  final gatesById = {for (final gate in gates) gate.id: gate};
  for (final id in _requiredAutomationCoverageGates) {
    final gate = gatesById[id];
    if (gate == null || !_automationCoverageGateReady(gate)) {
      return false;
    }
  }
  return true;
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
        final platform = _scenarioPlatform(target, step);
        final targetName = _scenarioTargetName(target, platform);
        final evidence = _scenarioEvidence(step);
        rows.add(
          '| `${_escapeCell('${step['name'] ?? ''}')}` | AI-assisted | ${_escapeCell(platform)} | ${_escapeCell(targetName)} | ${_escapeCell('${step['status'] ?? ''}')} | ${_escapeCell(evidence)} |',
        );
      }
    }
  }
  return rows;
}

String _scenarioPlatform(Map target, Map step) {
  final direct = _nonEmptyString(target['platform']);
  if (direct != null) {
    return direct;
  }
  final details = step['details'];
  if (details is Map) {
    final scenario = details['scenario'];
    final scenarioPlatform = scenario is Map
        ? _nonEmptyString(scenario['platform'])
        : null;
    if (scenarioPlatform != null) {
      return scenarioPlatform;
    }
  }
  final phasePlatform = _platformFromText(_nonEmptyString(target['phase']));
  if (phasePlatform != null) {
    return phasePlatform;
  }
  return _platformFromText(_nonEmptyString(step['name'])) ?? '';
}

String _scenarioTargetName(Map target, String platform) {
  final steps = target['steps'];
  if (steps is List<Object?>) {
    for (final step in steps) {
      if (step is! Map) {
        continue;
      }
      final details = step['details'];
      if (details is! Map) {
        continue;
      }
      final stepPlatform = _nonEmptyString(details['platform']);
      if (stepPlatform != null && stepPlatform != platform) {
        continue;
      }
      final targetId = _nonEmptyString(details['targetId']);
      if (targetId != null) {
        return targetId;
      }
      final targetDetails = details['target'];
      if (targetDetails is Map) {
        final id = _nonEmptyString(targetDetails['id']);
        if (id != null) {
          return id;
        }
      }
    }
  }
  final direct = _nonEmptyString(target['targetName']);
  if (direct != null) {
    return direct;
  }
  final targetObject = target['target'];
  if (targetObject is Map) {
    final name = _nonEmptyString(targetObject['name']);
    if (name != null) {
      return name;
    }
  }
  return '';
}

String _scenarioEvidence(Map step) {
  final parts = <String>[];
  void add(Object? value) {
    final text = _nonEmptyString(value);
    if (text != null && !parts.contains(text)) {
      parts.add(text);
    }
  }

  add(step['reason']);
  add(step['path']);
  final details = step['details'];
  if (details is Map) {
    final scenario = details['scenario'];
    if (scenario is Map) {
      final path = _nonEmptyString(scenario['path']);
      if (path != null) {
        add('scenario $path');
      }
    }
    final actions = details['actions'];
    if (actions is List<Object?>) {
      for (final action in actions) {
        if (action is Map) {
          add(_scenarioActionEvidence(action));
        }
      }
    }
  }
  return parts.join('; ');
}

String? _scenarioActionEvidence(Map action) {
  final name = _nonEmptyString(action['action']) ?? 'action';
  final status = _nonEmptyString(action['status']) ?? 'unknown';
  final details = action['details'];
  final detailMap = details is Map ? details : const <Object?, Object?>{};
  final reason = _nonEmptyString(action['reason']);
  if (status != 'passed') {
    return reason == null ? '$name $status' : '$name $status: $reason';
  }
  if (_isScreenshotAction(name)) {
    final path = _nonEmptyString(detailMap['path']);
    if (path != null) {
      final bytes = _nonEmptyString(detailMap['bytes']);
      return bytes == null
          ? 'post-launch screenshot $path'
          : 'post-launch screenshot $path ($bytes bytes)';
    }
    return 'post-launch screenshot captured';
  }
  final sessionFile = _nonEmptyString(detailMap['sessionFile']);
  if (sessionFile != null) {
    return '$name passed with session file $sessionFile';
  }
  final hilog = _nonEmptyString(detailMap['hilog']);
  if (hilog != null) {
    return '$name passed with hilog $hilog';
  }
  final outputLog = _nonEmptyString(detailMap['outputLog']);
  if (outputLog != null) {
    return '$name passed with output log $outputLog';
  }
  if (_isAssertionAction(name)) {
    return '$name passed';
  }
  final command = _nonEmptyString(action['command']);
  if (command != null) {
    return '$name passed via $command';
  }
  return null;
}

bool _isScreenshotAction(String name) {
  final normalized = name.toLowerCase();
  return normalized == 'screenshot' || normalized == 'capturescreenshot';
}

bool _isAssertionAction(String name) {
  final normalized = name.toLowerCase();
  return normalized == 'assertlog' ||
      normalized == 'assertsession' ||
      normalized == 'assertohossession' ||
      normalized == 'asserttext' ||
      normalized == 'waittext';
}

String? _platformFromText(String? value) {
  if (value == null) {
    return null;
  }
  for (final platform in workflowDrivePlatformNames) {
    if (RegExp('(^|-)${RegExp.escape(platform)}(-|\$)').hasMatch(value)) {
      return platform;
    }
  }
  return null;
}

String? _nonEmptyString(Object? value) {
  if (value == null) {
    return null;
  }
  final text = value.toString().trim();
  return text.isEmpty || text == 'null' ? null : text;
}

List<String> _platformRows(List<_CommandEvidence> commandRows) {
  return [
    for (final platform in workflowPlatformNames.map(
      (platform) => platformWorkflowPolicy(platform).label,
    ))
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

List<String> _automationSummaryLines(
  List<Map<String, Object?>> automation,
  List<_AutomationCoverageGate> gates,
) {
  final readyCount = gates.where(_automationCoverageGateReady).length;
  final notReadyCount = gates.length - readyCount;
  final hasGeneratedGates = gates.any((gate) => gate.generated);
  for (final item in automation) {
    final automationJson = item['automation'];
    final coveragePolicy = automationJson is Map
        ? automationJson['coveragePolicy']
        : null;
    if (coveragePolicy is Map) {
      final rawReadyForAutomation =
          coveragePolicy['readyForAutomation'] == true;
      return [
        '- coveragePolicy.status: ${hasGeneratedGates ? 'blocked' : coveragePolicy['status'] ?? 'unknown'}',
        '- readyForAutomation: ${!hasGeneratedGates && notReadyCount == 0 && rawReadyForAutomation}',
        '- qualityGateSummary: ready=$readyCount, notReady=$notReadyCount',
      ];
    }
  }
  return [
    '- coveragePolicy.status: blocked',
    '- readyForAutomation: false',
    '- qualityGateSummary: ready=$readyCount, notReady=$notReadyCount',
  ];
}

bool _automationCoverageGateReady(_AutomationCoverageGate gate) {
  return gate.status == 'readyForReview';
}

String _selectedInteractionPlatform(List<_CommandEvidence> commandRows) {
  for (final platform in workflowDrivePlatformNames) {
    final token = 'fluoh run $platform';
    if (commandRows.any((row) => row.command.contains(token))) {
      return platform;
    }
  }
  return 'n/a';
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

class _AutomationCoverageGate {
  const _AutomationCoverageGate({
    required this.id,
    required this.status,
    required this.evidence,
    required this.generated,
  });

  final String id;
  final String status;
  final String evidence;
  final bool generated;
}
