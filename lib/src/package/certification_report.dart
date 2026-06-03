import 'dart:io';

/// Validation result for a fluoh AI package certification report.
///
/// The report is optional for baseline release checks, but when a maintainer
/// supplies one this result records whether the report has enough structured
/// evidence for `fluoh package check` or `fluoh package release`.
class PackageCertificationReportResult {
  /// Creates a certification report validation result.
  const PackageCertificationReportResult({
    required this.reportPath,
    required this.requiredReport,
    required this.certified,
    required this.ok,
    required this.recommendation,
    required this.commandRows,
    required this.passedCommandRows,
    required this.interactionRows,
    required this.passedInteractionRows,
    required this.errors,
    required this.warnings,
  });

  /// Absolute or repository-relative path to the report that was validated.
  final String reportPath;

  /// Whether the command required a report for this validation.
  final bool requiredReport;

  /// Whether the supplied report satisfies the certification evidence rules.
  final bool certified;

  /// Whether the release command may continue after report validation.
  final bool ok;

  /// Parsed release recommendation, usually `ready` for passing reports.
  final String? recommendation;

  /// Number of concrete command evidence rows in the report.
  final int commandRows;

  /// Number of command evidence rows whose exit/result values passed.
  final int passedCommandRows;

  /// Number of concrete interaction evidence rows in the report.
  final int interactionRows;

  /// Number of interaction evidence rows marked as passed.
  final int passedInteractionRows;

  /// Validation errors that block the package release check.
  final List<String> errors;

  /// Non-blocking report quality warnings.
  final List<String> warnings;

  /// Converts the result to the machine-output contract used by package JSON.
  Map<String, Object?> toJson() {
    return {
      'required': requiredReport,
      'certified': certified,
      'ok': ok,
      if (reportPath.isNotEmpty) 'report': reportPath,
      if (recommendation != null) 'recommendation': recommendation,
      'commandRows': commandRows,
      'passedCommandRows': passedCommandRows,
      'interactionRows': interactionRows,
      'passedInteractionRows': passedInteractionRows,
      'errors': errors,
      'warnings': warnings,
    };
  }
}

/// Validates a package certification report against the release evidence rules.
///
/// Passing reports must contain the generated report sections, completed
/// checklist items, passed `fluoh verify` evidence, passed OHOS build or run
/// evidence, and either interaction evidence or an explicit reason that no
/// interaction is required.
Future<PackageCertificationReportResult> validatePackageCertificationReport({
  required File report,
  required String packageName,
  required bool requireOhosRun,
}) async {
  final errors = <String>[];
  final warnings = <String>[];
  if (!await report.exists()) {
    return PackageCertificationReportResult(
      reportPath: report.path,
      requiredReport: true,
      certified: false,
      ok: false,
      recommendation: null,
      commandRows: 0,
      passedCommandRows: 0,
      interactionRows: 0,
      passedInteractionRows: 0,
      errors: ['Certification report does not exist: ${report.path}'],
      warnings: const [],
    );
  }

  final content = await report.readAsString();
  for (final section in _requiredSections) {
    if (!content.contains(section)) {
      errors.add('Missing report section: $section');
    }
  }

  final recommendation = _releaseRecommendation(content);
  if (recommendation != 'ready') {
    errors.add('Certification reports must use release recommendation: ready.');
    if (recommendation != null && recommendation.isNotEmpty) {
      errors.add(
        'Report recommendation "$recommendation" can be kept as handoff '
        'evidence, but it cannot be used as release certification for '
        'fluoh package check --report or fluoh package release --report.',
      );
    }
  }

  final checklist = _checklistItems(content);
  if (checklist.isEmpty) {
    errors.add('Delivery checklist is missing.');
  } else {
    final unchecked = [
      for (final item in checklist)
        if (!item.done) item.text,
    ];
    if (unchecked.isNotEmpty) {
      errors.add(
        'Certification reports must complete every delivery checklist item.',
      );
    }
  }

  final commandRows = _commandRows(content);
  final concreteCommandRows = [
    for (final row in commandRows)
      if (!row.command.contains('...') && !row.row.contains('| ...')) row,
  ];
  if (concreteCommandRows.isEmpty) {
    errors.add('Commands table must include concrete command evidence.');
  }
  final passedCommandRows = [
    for (final row in concreteCommandRows)
      if (row.passed) row,
  ];
  if (concreteCommandRows.isNotEmpty && passedCommandRows.isEmpty) {
    errors.add('Commands table must include passed command evidence.');
  }

  final hasVerify = passedCommandRows.any(
    (row) => _containsCommand(row.command, 'fluoh verify'),
  );
  if (!hasVerify) {
    errors.add(
      'Certification report must include passed fluoh verify evidence.',
    );
  }

  final hasOhosBuild = passedCommandRows.any(_isOhosBuildEvidence);
  final hasOhosRun = passedCommandRows.any(_isOhosRunEvidence);
  if (!hasOhosBuild && !hasOhosRun) {
    errors.add(
      'Certification report must include passed OHOS build or run evidence.',
    );
  }
  if (requireOhosRun && !hasOhosRun) {
    errors.add(
      'Certification report must include passed fluoh run --platform ohos evidence.',
    );
  }

  final interactionRows = _interactionRows(content);
  final passedInteractionRows = [
    for (final row in interactionRows)
      if (row.passed) row,
  ];
  final interactionSection = _sectionContent(
    content,
    '## Interaction Evidence',
  );
  final noInteractionRequired = RegExp(
    r'^\s*No interaction required\s*:\s*\S.+$',
    multiLine: true,
    caseSensitive: false,
  ).hasMatch(interactionSection);
  if (interactionRows.isEmpty && !noInteractionRequired) {
    errors.add(
      'Interaction Evidence must include a concrete row or '
      '"No interaction required: <reason>".',
    );
  } else if (interactionRows.isNotEmpty && passedInteractionRows.isEmpty) {
    errors.add(
      'Certification report interaction evidence must include a passed row.',
    );
  }

  final placeholders = _placeholderHits(content);
  if (placeholders.isNotEmpty) {
    errors.add('Certification report still contains placeholder content.');
  }

  if (!content.contains(packageName)) {
    warnings.add('Report does not mention package $packageName.');
  }

  return PackageCertificationReportResult(
    reportPath: report.path,
    requiredReport: true,
    certified: errors.isEmpty,
    ok: errors.isEmpty,
    recommendation: recommendation,
    commandRows: concreteCommandRows.length,
    passedCommandRows: passedCommandRows.length,
    interactionRows: interactionRows.length,
    passedInteractionRows: passedInteractionRows.length,
    errors: errors,
    warnings: warnings,
  );
}

const _requiredSections = [
  '## Summary',
  '## Changes',
  '## Public API / Compatibility',
  '## Commands',
  '## Delivery Checklist',
  '## Platform Matrix',
  '## Interaction Evidence',
  '## Diagnostics',
  '## Signing',
  '## Remaining Risks',
  '## Local State',
  '## Release Decision',
];

String? _releaseRecommendation(String content) {
  final match = RegExp(
    r'^Release recommendation:\s*(.+?)\s*$',
    multiLine: true,
  ).firstMatch(content);
  return match?.group(1)?.trim().toLowerCase();
}

List<_ChecklistItem> _checklistItems(String content) {
  return [
    for (final match in RegExp(
      r'^- \[([ xX])\]\s+(.+?)\s*$',
      multiLine: true,
    ).allMatches(content))
      _ChecklistItem(
        done: match.group(1)!.toLowerCase() == 'x',
        text: match.group(2)!.trim(),
      ),
  ];
}

List<_CommandRow> _commandRows(String content) {
  final section = _sectionContent(content, '## Commands');
  final rows = <_CommandRow>[];
  for (final line in section.split('\n')) {
    final row = _CommandRow.fromMarkdown(line);
    if (row != null) {
      rows.add(row);
    }
  }
  return rows;
}

List<_InteractionRow> _interactionRows(String content) {
  final section = _sectionContent(content, '## Interaction Evidence');
  final rows = <_InteractionRow>[];
  for (final line in section.split('\n')) {
    final row = _InteractionRow.fromMarkdown(line);
    if (row != null &&
        !row.row.contains('`...`') &&
        !row.row.contains('| ...')) {
      rows.add(row);
    }
  }
  return rows;
}

String _sectionContent(String content, String heading) {
  final start = content.indexOf(heading);
  if (start < 0) {
    return '';
  }
  final bodyStart = content.indexOf('\n', start);
  if (bodyStart < 0) {
    return '';
  }
  final rest = content.substring(bodyStart + 1);
  final nextHeading = RegExp(r'^## ', multiLine: true).firstMatch(rest);
  if (nextHeading == null) {
    return rest;
  }
  return rest.substring(0, nextHeading.start);
}

List<String> _placeholderHits(String content) {
  final hits = <String>[];
  for (final pattern in const [
    r'\|\s*`?\.\.\.`?\s*\|',
    r'^\s*-\s*$',
    r'^\s*-\s*\.\.\.\s*$',
    r'\bn/a\s*\|\s*n/a\s*\|\s*\.\.\.',
  ]) {
    for (final match in RegExp(
      pattern,
      multiLine: true,
      caseSensitive: false,
    ).allMatches(content)) {
      final lineStart = content.lastIndexOf('\n', match.start) + 1;
      final lineEnd = content.indexOf('\n', match.end);
      final line = content
          .substring(lineStart, lineEnd < 0 ? content.length : lineEnd)
          .trim();
      if (line.isNotEmpty && !hits.contains(line)) {
        hits.add(line);
      }
    }
  }
  return hits;
}

bool _isOhosBuildEvidence(_CommandRow row) {
  final command = row.command;
  return _containsCommand(command, 'fluoh build') &&
      command.contains('--platform ohos') &&
      command.contains('--auto-sign') &&
      command.contains('--json');
}

bool _isOhosRunEvidence(_CommandRow row) {
  final command = row.command;
  return _containsCommand(command, 'fluoh run') &&
      command.contains('--platform ohos') &&
      command.contains('--json');
}

bool _containsCommand(String command, String expected) {
  return command == expected || command.startsWith('$expected ');
}

class _ChecklistItem {
  const _ChecklistItem({required this.done, required this.text});

  final bool done;
  final String text;
}

class _CommandRow {
  const _CommandRow({
    required this.command,
    required this.exitText,
    required this.resultText,
    required this.row,
  });

  final String command;
  final String exitText;
  final String resultText;
  final String row;

  bool get passed {
    return exitText == '0' &&
        const {'passed', 'ok', 'success'}.contains(resultText.toLowerCase());
  }

  static _CommandRow? fromMarkdown(String line) {
    if (!RegExp(r'^\|\s*`[^`]+`\s*\|').hasMatch(line)) {
      return null;
    }
    final columns = [
      for (final column in line.trim().split('|')) column.trim(),
    ].where((column) => column.isNotEmpty).toList(growable: false);
    if (columns.length < 3) {
      return null;
    }
    final command = RegExp(r'^`([^`]+)`$').firstMatch(columns[0])?.group(1);
    if (command == null || command.trim().isEmpty) {
      return null;
    }
    return _CommandRow(
      command: command.trim(),
      exitText: columns[1],
      resultText: columns[2],
      row: line,
    );
  }
}

class _InteractionRow {
  const _InteractionRow({
    required this.method,
    required this.resultText,
    required this.row,
  });

  final String method;
  final String resultText;
  final String row;

  bool get passed {
    return resultText.toLowerCase() == 'passed';
  }

  static _InteractionRow? fromMarkdown(String line) {
    final columns = [
      for (final column in line.trim().split('|')) column.trim(),
    ].where((column) => column.isNotEmpty).toList(growable: false);
    if (columns.length < 6) {
      return null;
    }
    final method = columns[1].toLowerCase();
    if (!const {'integration_test', 'ai-assisted', 'manual'}.contains(method)) {
      return null;
    }
    return _InteractionRow(method: method, resultText: columns[4], row: line);
  }
}
