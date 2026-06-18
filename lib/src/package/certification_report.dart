import 'dart:io';

const _requiredAutomationCoverageGates = {
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
};

const _interactionEvidenceMethods = {
  'integration_test',
  'ai-assisted',
  'manual-assisted',
};

const _requiredReadyChecklistPhrases = [
  'Existing package/app tests, example tests',
  'Missing or weak functional tests',
  'Target-platform build evidence',
  'Target-platform run evidence',
  'Pub.dev publishability',
  'FlutterOH support',
  'Every existing Android, iOS, macOS, Linux, Web, and Windows platform',
  'Official platform documentation',
  'existing-platform regression risk',
];

final _canonicalReportFileNamePattern = RegExp(r'^(?:report|report-\d+)\.md$');

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
    required this.coveragePolicyStatus,
    required this.readyForAutomation,
    required this.qualityGateSummary,
    required this.automationCoverageRows,
    required this.readyAutomationCoverageRows,
    required this.interactionRows,
    required this.passedInteractionRows,
    required this.passedMobileRunOrDrive,
    required this.postLaunchVisualEvidence,
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

  /// Recorded `automation.coveragePolicy.status` from the report.
  final String? coveragePolicyStatus;

  /// Recorded `automation.coveragePolicy.readyForAutomation` from the report.
  final bool? readyForAutomation;

  /// Recorded `automation.coveragePolicy.qualityGateSummary` from the report.
  final String? qualityGateSummary;

  /// Number of concrete automation coverage gate rows in the report.
  final int automationCoverageRows;

  /// Number of automation coverage gate rows whose status is release-ready.
  final int readyAutomationCoverageRows;

  /// Number of concrete interaction evidence rows in the report.
  final int interactionRows;

  /// Number of interaction evidence rows marked as passed.
  final int passedInteractionRows;

  /// Whether the report includes passed mobile `fluoh run` or `fluoh drive`.
  final bool passedMobileRunOrDrive;

  /// Whether the report records post-launch screenshot or UI-state evidence.
  final bool postLaunchVisualEvidence;

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
      if (coveragePolicyStatus != null)
        'coveragePolicyStatus': coveragePolicyStatus,
      if (readyForAutomation != null) 'readyForAutomation': readyForAutomation,
      if (qualityGateSummary != null) 'qualityGateSummary': qualityGateSummary,
      'automationCoverageRows': automationCoverageRows,
      'readyAutomationCoverageRows': readyAutomationCoverageRows,
      'interactionRows': interactionRows,
      'passedInteractionRows': passedInteractionRows,
      'passedMobileRunOrDrive': passedMobileRunOrDrive,
      'postLaunchVisualEvidence': postLaunchVisualEvidence,
      'errors': errors,
      'warnings': warnings,
    };
  }
}

/// Validates a package certification report against the release evidence rules.
///
/// Passing reports must contain the generated report sections, completed
/// checklist items, passed `fluoh verify` evidence, target-platform build or
/// run evidence including OHOS for FlutterOH support, the complete automation
/// coverage gate set, and either interaction evidence or an explicit reason
/// that no interaction is required.
Future<PackageCertificationReportResult> validatePackageCertificationReport({
  required File report,
  required String packageName,
  required bool requireOhosRun,
}) async {
  final errors = <String>[];
  final warnings = <String>[];
  final reportNameError = _canonicalReportFileNameError(report);
  if (reportNameError != null) {
    errors.add(reportNameError);
  }
  if (!await report.exists()) {
    return PackageCertificationReportResult(
      reportPath: report.path,
      requiredReport: true,
      certified: false,
      ok: false,
      recommendation: null,
      commandRows: 0,
      passedCommandRows: 0,
      coveragePolicyStatus: null,
      readyForAutomation: null,
      qualityGateSummary: null,
      automationCoverageRows: 0,
      readyAutomationCoverageRows: 0,
      interactionRows: 0,
      passedInteractionRows: 0,
      passedMobileRunOrDrive: false,
      postLaunchVisualEvidence: false,
      errors: [
        ...errors,
        'Certification report does not exist: ${report.path}',
      ],
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
    if (recommendation == 'ready') {
      final missingChecklistPhrases = [
        for (final phrase in _requiredReadyChecklistPhrases)
          if (!checklist.any((item) => item.text.contains(phrase))) phrase,
      ];
      if (missingChecklistPhrases.isNotEmpty) {
        errors.add(
          'Ready certification reports must include delivery checklist items '
          'for: ${missingChecklistPhrases.join(', ')}.',
        );
      }
      if (!_officialPlatformBasisSatisfied(content)) {
        errors.add(
          'Ready certification reports must record official platform '
          'documentation basis, or an explicit '
          '"No official platform basis required: <reason>" statement.',
        );
      }
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
      'Certification report must include passed OHOS build or run evidence as target-platform evidence.',
    );
  }
  if (requireOhosRun && !hasOhosRun) {
    errors.add(
      'Certification report must include passed fluoh run ohos evidence.',
    );
  }
  final mobileVisualRequirements = _mobileVisualRequirements(
    content,
    passedCommandRows,
  );
  final hasMobileRunOrDrive = mobileVisualRequirements.isNotEmpty;
  final interactionRows = _interactionRows(content);
  final passedInteractionRows = [
    for (final row in interactionRows)
      if (row.passed) row,
  ];
  final missingPostLaunchVisualEvidence = _missingPostLaunchVisualEvidence(
    content: content,
    requirements: mobileVisualRequirements,
    passedCommandRows: passedCommandRows,
    passedInteractionRows: passedInteractionRows,
  );
  final hasPostLaunchVisualEvidence = hasMobileRunOrDrive
      ? missingPostLaunchVisualEvidence.isEmpty
      : _hasAnyPostLaunchVisualEvidence(
          content,
          passedCommandRows: passedCommandRows,
          passedInteractionRows: passedInteractionRows,
        );
  if (missingPostLaunchVisualEvidence.isNotEmpty) {
    errors.add(
      'Certification reports with passed mobile fluoh run or drive evidence '
      'must record post-launch screenshot or UI-state evidence. Missing: '
      '${missingPostLaunchVisualEvidence.join(', ')}.',
    );
  }
  final passedManualAssistedWithoutToolEvidence = [
    for (final row in passedInteractionRows)
      if (row.method == 'manual-assisted' && !_hasToolReadableEvidence(row))
        row,
  ];
  if (passedManualAssistedWithoutToolEvidence.isNotEmpty) {
    errors.add(
      'Passed manual-assisted interaction evidence must include '
      'tool-readable confirmation such as logs, meaningful session state '
      'beyond launch, stable text, semantics, test keys, command JSON, hilog, '
      'or app log markers.',
    );
  }
  final passedAiAssistedLaunchOnlyEvidence = [
    for (final row in passedInteractionRows)
      if (row.method == 'ai-assisted' &&
          _isLaunchOnlyEvidence(row.evidenceText.toLowerCase()) &&
          !_hasFunctionalToolEvidence(row.evidenceText.toLowerCase()))
        row,
  ];
  if (passedAiAssistedLaunchOnlyEvidence.isNotEmpty) {
    errors.add(
      'Passed AI-assisted interaction evidence cannot rely on assertSession, '
      'launch, wait, or screenshots alone; add functional assertions such as '
      'assertText, waitText, assertLog, visible text, semantics, test keys, '
      'diagnostic command JSON, hilog, or app log markers.',
    );
  }
  // A prose note under fluoh run is launch evidence; release gating needs the
  // concrete flutter test command row that produced the integration result.
  final passedIntegrationTestWithoutCommandEvidence = [
    for (final row in passedInteractionRows)
      if (row.method == 'integration_test' &&
          !_isIntegrationTestEvidence(row, passedCommandRows))
        row,
  ];
  if (passedIntegrationTestWithoutCommandEvidence.isNotEmpty) {
    errors.add(
      'Passed integration_test interaction evidence must cite and be backed '
      'by a passed flutter test integration_test command row.',
    );
  }
  final hasIntegrationTestEvidence = passedInteractionRows.any(
    (row) => _isIntegrationTestEvidence(row, passedCommandRows),
  );
  final hasManualAssistedToolEvidence = passedInteractionRows.any(
    (row) => row.method == 'manual-assisted' && _hasToolReadableEvidence(row),
  );
  final hasAutomate = passedCommandRows.any(_isAutomationEvidence);
  if (!hasAutomate &&
      !hasIntegrationTestEvidence &&
      !hasManualAssistedToolEvidence) {
    errors.add(
      'Certification report must include passed fluoh drive --json, '
      'integration_test, or manual-assisted tool-readable interaction '
      'evidence.',
    );
  }

  final automationCoverageRows = _automationCoverageRows(content);
  final coverageStatus = _automationCoverageStatus(content);
  final readyAutomationCoverageRows = [
    for (final row in automationCoverageRows)
      if (row.ready) row,
  ];
  if (automationCoverageRows.isEmpty) {
    errors.add(
      'Automation Coverage must include concrete gate rows from '
      'fluoh drive --dry-run --json or real run JSON.',
    );
  }
  final reportedAutomationCoverageGates = {
    for (final row in automationCoverageRows) row.gate,
  };
  final missingAutomationCoverageGates = [
    for (final gate in _requiredAutomationCoverageGates)
      if (!reportedAutomationCoverageGates.contains(gate)) gate,
  ];
  if (missingAutomationCoverageGates.isNotEmpty) {
    errors.add(
      'Automation Coverage is missing required gates: '
      '${missingAutomationCoverageGates.join(', ')}.',
    );
  }
  final unresolvedAutomationCoverageRows = [
    for (final row in automationCoverageRows)
      if (!row.ready) row,
  ];
  if (unresolvedAutomationCoverageRows.isNotEmpty) {
    errors.add(
      'Automation Coverage has unresolved gates: '
      '${unresolvedAutomationCoverageRows.map((row) => '${row.gate} (${row.statusText})').join(', ')}.',
    );
  }
  if (coverageStatus.coveragePolicyStatus != 'readyForExecution') {
    errors.add(
      'Automation Coverage must record coveragePolicy.status: readyForExecution for ready reports.',
    );
  }
  if (coverageStatus.readyForAutomation != true) {
    errors.add(
      'Automation Coverage must record readyForAutomation: true for ready reports.',
    );
  }
  if (!_hasReadyQualityGateSummary(coverageStatus.qualityGateSummary)) {
    errors.add(
      'Automation Coverage must record qualityGateSummary with zero notReady gates for ready reports.',
    );
  }

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

  final feedbackRows = _feedbackRows(content);
  if (feedbackRows.isEmpty && !_hasNoFeedbackStatement(content)) {
    errors.add(
      'Fluoh Feedback must include a concrete row or '
      '"No fluoh feedback: <reason>".',
    );
  }
  final openFeedbackRows = [
    for (final row in feedbackRows)
      if (const {'queued', 'open', 'todo'}.contains(row.statusText)) row,
  ];
  if (openFeedbackRows.isNotEmpty) {
    warnings.add('Fluoh Feedback includes queued or open tool follow-ups.');
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
    coveragePolicyStatus: coverageStatus.coveragePolicyStatus,
    readyForAutomation: coverageStatus.readyForAutomation,
    qualityGateSummary: coverageStatus.qualityGateSummary,
    automationCoverageRows: automationCoverageRows.length,
    readyAutomationCoverageRows: readyAutomationCoverageRows.length,
    interactionRows: interactionRows.length,
    passedInteractionRows: passedInteractionRows.length,
    passedMobileRunOrDrive: hasMobileRunOrDrive,
    postLaunchVisualEvidence: hasPostLaunchVisualEvidence,
    errors: errors,
    warnings: warnings,
  );
}

String? _canonicalReportFileNameError(File report) {
  final name = report.uri.pathSegments.isEmpty
      ? report.path
      : report.uri.pathSegments.last;
  if (_canonicalReportFileNamePattern.hasMatch(name)) {
    return null;
  }
  return 'Certification report filename must be report.md or '
      'report-<timestamp>.md using an integer timestamp.';
}

const _requiredSections = [
  '## Summary',
  '## Changes',
  '## Public API / Compatibility',
  '## Official Platform Basis',
  '## Commands',
  '## Delivery Checklist',
  '## Platform Matrix',
  '## Automation Coverage',
  '## Interaction Evidence',
  '## Diagnostics',
  '## Fluoh Feedback',
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

List<_AutomationCoverageRow> _automationCoverageRows(String content) {
  final section = _sectionContent(content, '## Automation Coverage');
  final rows = <_AutomationCoverageRow>[];
  for (final line in section.split('\n')) {
    final row = _AutomationCoverageRow.fromMarkdown(line);
    if (row != null &&
        !row.row.contains('`...`') &&
        !row.row.contains('| ...')) {
      rows.add(row);
    }
  }
  return rows;
}

List<_FeedbackRow> _feedbackRows(String content) {
  final section = _sectionContent(content, '## Fluoh Feedback');
  final rows = <_FeedbackRow>[];
  for (final line in section.split('\n')) {
    final row = _FeedbackRow.fromMarkdown(line);
    if (row != null) {
      rows.add(row);
    }
  }
  return rows;
}

bool _hasNoFeedbackStatement(String content) {
  final section = _sectionContent(content, '## Fluoh Feedback');
  return RegExp(
    r'^\s*No fluoh feedback\s*:\s*\S.+$',
    multiLine: true,
    caseSensitive: false,
  ).hasMatch(section);
}

bool _officialPlatformBasisSatisfied(String content) {
  final section = _sectionContent(content, '## Official Platform Basis');
  if (section.trim().isEmpty) {
    return false;
  }
  if (RegExp(
    r'^\s*No official platform basis required\s*:\s*\S.+$',
    multiLine: true,
    caseSensitive: false,
  ).hasMatch(section)) {
    return true;
  }
  final normalized = section.toLowerCase();
  final hasPositiveMarker = const [
    'openharmony',
    'ohos',
    'harmonyos',
    'developer.huawei.com',
    'docs.openharmony.cn',
    'official',
    'api reference',
    'sdk api',
  ].any(normalized.contains);
  if (!hasPositiveMarker) {
    return false;
  }
  return !const [
    'todo',
    '...',
    'not checked',
    'not reviewed',
    'missing',
    'blocked',
    'unknown',
  ].any(normalized.contains);
}

_AutomationCoverageStatus _automationCoverageStatus(String content) {
  final section = _sectionContent(content, '## Automation Coverage');
  return _AutomationCoverageStatus(
    coveragePolicyStatus: _automationCoverageField(
      section,
      'coveragePolicy.status',
    ),
    readyForAutomation: _parseBool(
      _automationCoverageField(section, 'readyForAutomation'),
    ),
    qualityGateSummary: _automationCoverageField(section, 'qualityGateSummary'),
  );
}

String? _automationCoverageField(String section, String key) {
  final pattern = RegExp(
    '^\\s*((?:[-*]\\s*)?)`?${RegExp.escape(key)}`?\\s*:\\s*(.+?)\\s*\$',
    multiLine: true,
    caseSensitive: false,
  );
  final matches = pattern.allMatches(section).toList();
  if (matches.isEmpty) {
    return null;
  }
  final match = matches.firstWhere(
    (match) => (match.group(1) ?? '').trim().isNotEmpty,
    orElse: () => matches.first,
  );
  final value = match.group(2)?.trim();
  return value == null || value.isEmpty ? null : value;
}

bool? _parseBool(String? value) {
  if (value == null) {
    return null;
  }
  final normalized = value.trim().toLowerCase();
  if (normalized == 'true') {
    return true;
  }
  if (normalized == 'false') {
    return false;
  }
  return null;
}

bool _hasReadyQualityGateSummary(String? value) {
  if (value == null || value.contains('...')) {
    return false;
  }
  final match = RegExp(
    r'(?:not\s*ready|notready)\s*[:=]\s*(\[[^\]]*\]|[a-z0-9_-]+)',
    caseSensitive: false,
  ).firstMatch(value);
  final token = match?.group(1)?.trim().toLowerCase();
  return const {'0', '[]', 'none', 'empty'}.contains(token);
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
      RegExp(r'(^|\s)fluoh\s+build\s+ohos(\s|$)').hasMatch(command) &&
      command.contains('--auto-sign') &&
      command.contains('--json');
}

bool _isOhosRunEvidence(_CommandRow row) {
  final command = row.command;
  return _containsCommand(command, 'fluoh run') &&
      RegExp(r'(^|\s)fluoh\s+run\s+ohos(\s|$)').hasMatch(command) &&
      command.contains('--json');
}

bool _isMobileRunEvidence(_CommandRow row) {
  final command = row.command;
  return _containsCommand(command, 'fluoh run') &&
      RegExp(
        r'(^|\s)fluoh\s+run\s+(ohos|android|ios|all)(\s|$)',
      ).hasMatch(command) &&
      command.contains('--json');
}

bool _isAutomationEvidence(_CommandRow row) {
  final command = row.command;
  return _containsCommand(command, 'fluoh drive') &&
      command.contains('--json') &&
      !_containsShellToken(command, '--dry-run') &&
      !_containsShellToken(command, '-n') &&
      !_containsExploratorySmokeProfile(command);
}

bool _isMobileAutomationEvidence(_CommandRow row) {
  final command = row.command;
  return _isAutomationEvidence(row) &&
      RegExp(
        r'(^|\s)fluoh\s+drive\s+(ohos|android|ios|all)(\s|$)',
      ).hasMatch(command);
}

bool _isIntegrationTestEvidence(
  _InteractionRow row,
  List<_CommandRow> passedCommandRows,
) {
  if (row.method != 'integration_test' || !row.passed) {
    return false;
  }
  if (!_mentionsIntegrationTestCommand(row.evidenceText)) {
    return false;
  }
  return passedCommandRows.any(_isIntegrationTestCommandEvidence);
}

bool _isIntegrationTestCommandEvidence(_CommandRow row) {
  final command = row.command;
  return _containsCommand(command, 'flutter test') &&
      RegExp(r'(^|\s)integration_test(?:\s|$|/)').hasMatch(command);
}

bool _mentionsIntegrationTestCommand(String value) {
  final normalized = value.toLowerCase();
  return RegExp(
    r'flutter\s+test\s+.*integration_test(?:\s|$|/)',
  ).hasMatch(normalized);
}

bool _hasToolReadableEvidence(_InteractionRow row) {
  final normalized = row.evidenceText.toLowerCase();
  final hasToolMarker = const [
    'flutterrunsession',
    'vm service',
    'session file',
    'session state',
    'session json',
    'output log',
    'outputlog',
    'stdout',
    'stderr',
    'hilog',
    'log marker',
    'app log',
    'assertlog',
    'assertsession',
    'asserttext',
    'waittext',
    'visible text',
    'visible status',
    'stable text',
    'semantic label',
    'semantics',
    'test key',
    'testkey',
    'component state',
    'command json',
    'trace.json',
    'trace manifest',
    'trace file',
    'diagnostics[]',
    'diagnostic code',
  ].any(normalized.contains);
  if (!hasToolMarker) {
    return false;
  }
  if (_isLaunchOnlyEvidence(normalized) &&
      !_hasFunctionalToolEvidence(normalized)) {
    return false;
  }
  return true;
}

bool _isLaunchOnlyEvidence(String normalized) {
  return _mentionsTaskScreenshot(normalized) ||
      const [
        'assertsession',
        'launchapp',
        'capture screenshot',
        'capturescreenshot',
        'post-launch screenshot',
        'post launch screenshot',
        'screenshot only',
        'launched=true',
        'launchdetected true',
        'launchdetected=true',
        'launched the example',
        'launch evidence only',
        'app launched',
        'flutter run launched',
      ].any(normalized.contains);
}

bool _hasFunctionalToolEvidence(String normalized) {
  return const [
    'hilog',
    'log marker',
    'app log',
    'assertlog',
    'asserttext',
    'waittext',
    'visible text',
    'visible status',
    'stable text',
    'semantic label',
    'semantics',
    'test key',
    'testkey',
    'component state',
    'diagnostics[]',
    'diagnostic code',
  ].any(normalized.contains);
}

List<_MobileVisualRequirement> _mobileVisualRequirements(
  String content,
  List<_CommandRow> passedCommandRows,
) {
  final requirements = <_MobileVisualRequirement>[];
  for (final row in passedCommandRows) {
    if (!_isMobileRunEvidence(row) && !_isMobileAutomationEvidence(row)) {
      continue;
    }
    for (final platform in _mobileCommandPlatforms(row.command, content)) {
      requirements.add(
        _MobileVisualRequirement(
          platform: platform,
          command: row.command,
          row: row.row,
        ),
      );
    }
  }
  return requirements;
}

List<String> _mobileCommandPlatforms(String command, String content) {
  final match = RegExp(
    r'(^|\s)fluoh\s+(?:run|drive)\s+(ohos|android|ios|all)(\s|$)',
  ).firstMatch(command);
  final platform = match?.group(2);
  if (platform == null) {
    return const [];
  }
  if (platform != 'all') {
    return [platform];
  }
  final matrixPlatforms = _passedMobileRunMatrixPlatforms(content);
  return matrixPlatforms.isEmpty ? const ['all'] : matrixPlatforms;
}

List<String> _passedMobileRunMatrixPlatforms(String content) {
  final section = _sectionContent(content, '## Platform Matrix');
  final platforms = <String>[];
  for (final line in section.split('\n')) {
    final columns = [
      for (final column in line.trim().split('|')) column.trim(),
    ].where((column) => column.isNotEmpty).toList(growable: false);
    if (columns.length < 4) {
      continue;
    }
    final platform = columns[0].toLowerCase();
    if (!const {'ohos', 'android', 'ios'}.contains(platform)) {
      continue;
    }
    final runStatus = columns[2].toLowerCase();
    final integrationStatus = columns[3].toLowerCase();
    if (runStatus.startsWith('passed') ||
        integrationStatus.startsWith('passed')) {
      platforms.add(platform);
    }
  }
  return platforms;
}

List<String> _missingPostLaunchVisualEvidence({
  required String content,
  required List<_MobileVisualRequirement> requirements,
  required List<_CommandRow> passedCommandRows,
  required List<_InteractionRow> passedInteractionRows,
}) {
  final evidenceRows = [
    for (final row in passedCommandRows) row.row,
    for (final row in passedInteractionRows) row.row,
    ..._passedPlatformMatrixRows(content),
  ];
  return [
    for (final requirement in requirements)
      if (!_hasPostLaunchVisualEvidenceForPlatform(requirement.platform, [
        requirement.row,
        ...evidenceRows,
      ]))
        requirement.label,
  ];
}

bool _hasPostLaunchVisualEvidenceForPlatform(
  String platform,
  List<String> rows,
) {
  return rows.any(
    (row) =>
        _hasPositivePostLaunchVisualEvidence(row) &&
        _visualEvidenceMatchesPlatform(row, platform),
  );
}

bool _hasAnyPostLaunchVisualEvidence(
  String content, {
  required List<_CommandRow> passedCommandRows,
  required List<_InteractionRow> passedInteractionRows,
}) {
  final evidenceRows = [
    for (final row in passedCommandRows) row.row,
    for (final row in passedInteractionRows) row.row,
    ..._passedPlatformMatrixRows(content),
  ];
  return evidenceRows.any(_hasPositivePostLaunchVisualEvidence);
}

List<String> _passedPlatformMatrixRows(String content) {
  final section = _sectionContent(content, '## Platform Matrix');
  final rows = <String>[];
  for (final line in section.split('\n')) {
    final columns = [
      for (final column in line.trim().split('|')) column.trim(),
    ].where((column) => column.isNotEmpty).toList(growable: false);
    if (columns.length < 6) {
      continue;
    }
    final platform = columns[0].toLowerCase();
    if (platform == 'platform' || RegExp(r'^-+$').hasMatch(platform)) {
      continue;
    }
    final statuses = columns.skip(1).take(3).map((value) {
      return value.toLowerCase();
    });
    if (statuses.any((value) => value.startsWith('passed'))) {
      rows.add(line);
    }
  }
  return rows;
}

bool _hasPositivePostLaunchVisualEvidence(String row) {
  final evidence = row.toLowerCase();
  final hasMarker =
      _mentionsTaskScreenshot(evidence) ||
      const [
        'post-launch screenshot',
        'post launch screenshot',
        'postlaunchscreenshot',
        'visualpagereadiness',
        'ui-state',
        'ui state',
        'capture screenshot',
        'capturescreenshot',
        'screenshot path',
        'screenshot:',
        'screen recording',
      ].any(evidence.contains);
  if (!hasMarker) {
    return false;
  }
  if (const [
    'not captured',
    'not collect',
    'not recorded',
    'missing',
    'failed',
    'empty',
    'blocked',
    'skipped',
  ].any(evidence.contains)) {
    return false;
  }
  return true;
}

bool _mentionsTaskScreenshot(String normalized) {
  return normalized.contains('.fluoh/tasks/') &&
      normalized.contains('/evidence/screenshots');
}

bool _visualEvidenceMatchesPlatform(String row, String platform) {
  if (platform == 'all') {
    return true;
  }
  return row.toLowerCase().contains(platform);
}

bool _containsCommand(String command, String expected) {
  return command == expected || command.startsWith('$expected ');
}

bool _containsShellToken(String command, String token) {
  return RegExp('(^|\\s)${RegExp.escape(token)}(\\s|\$)').hasMatch(command);
}

bool _containsExploratorySmokeProfile(String command) {
  return command.contains('--profile exploratory-smoke') ||
      command.contains('--profile=exploratory-smoke');
}

class _ChecklistItem {
  const _ChecklistItem({required this.done, required this.text});

  final bool done;
  final String text;
}

class _MobileVisualRequirement {
  const _MobileVisualRequirement({
    required this.platform,
    required this.command,
    required this.row,
  });

  final String platform;
  final String command;
  final String row;

  String get label => platform == 'all' ? command : '$platform ($command)';
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
    required this.evidenceText,
    required this.row,
  });

  final String method;
  final String resultText;
  final String evidenceText;
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
    if (!_interactionEvidenceMethods.contains(method)) {
      return null;
    }
    return _InteractionRow(
      method: method,
      resultText: columns[4],
      evidenceText: columns[5],
      row: line,
    );
  }
}

class _FeedbackRow {
  const _FeedbackRow({required this.id, required this.statusText});

  final String id;
  final String statusText;

  static _FeedbackRow? fromMarkdown(String line) {
    if (!line.trimLeft().startsWith('|')) {
      return null;
    }
    final columns = [
      for (final column in line.trim().split('|')) column.trim(),
    ].where((column) => column.isNotEmpty).toList(growable: false);
    if (columns.length < 6) {
      return null;
    }
    final id = columns[0].trim();
    if (id.isEmpty ||
        id.toLowerCase() == 'id' ||
        id == '...' ||
        RegExp(r'^-+$').hasMatch(id)) {
      return null;
    }
    return _FeedbackRow(id: id, statusText: columns[5].trim().toLowerCase());
  }
}

class _AutomationCoverageStatus {
  const _AutomationCoverageStatus({
    required this.coveragePolicyStatus,
    required this.readyForAutomation,
    required this.qualityGateSummary,
  });

  final String? coveragePolicyStatus;
  final bool? readyForAutomation;
  final String? qualityGateSummary;
}

class _AutomationCoverageRow {
  const _AutomationCoverageRow({
    required this.gate,
    required this.statusText,
    required this.row,
  });

  final String gate;
  final String statusText;
  final String row;

  bool get ready {
    final normalized = statusText.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]+'),
      '',
    );
    return const {
      'ready',
      'readyforreview',
      'covered',
      'passed',
      'notapplicable',
    }.contains(normalized);
  }

  static _AutomationCoverageRow? fromMarkdown(String line) {
    final columns = [
      for (final column in line.trim().split('|')) column.trim(),
    ].where((column) => column.isNotEmpty).toList(growable: false);
    if (columns.length < 3) {
      return null;
    }
    final gate = columns[0];
    final normalizedGate = gate.toLowerCase();
    if (normalizedGate == 'gate' || gate.startsWith('---')) {
      return null;
    }
    return _AutomationCoverageRow(
      gate: gate,
      statusText: columns[1],
      row: line,
    );
  }
}
