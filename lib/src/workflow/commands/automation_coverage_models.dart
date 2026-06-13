part of 'workflow_commands.dart';

class _ScenarioEvidence {
  const _ScenarioEvidence({required this.scenario});

  final AutomationScenario scenario;

  int get coveredCoverageItemCount =>
      scenario.coverage.where((item) => item.status == 'covered').length;

  int get explanatoryCoverageItemCount =>
      scenario.coverage.length - coveredCoverageItemCount;

  bool get needsReview =>
      coveredCoverageItemCount > 0 && verificationActions.isEmpty;

  List<String> get verificationActions {
    return [
      for (final action in scenario.steps)
        if (_isScenarioVerificationAction(action.action)) action.action,
    ];
  }

  Map<String, Object?> toJson() {
    final actions = verificationActions;
    return {
      'platform': scenario.platform,
      'scenario': scenario.name,
      'path': scenario.path.path,
      'coverageItemCount': scenario.coverage.length,
      'coveredCoverageItemCount': coveredCoverageItemCount,
      'explanatoryCoverageItemCount': explanatoryCoverageItemCount,
      'status': needsReview ? 'needsEvidenceAssertions' : 'readyForReview',
      'verificationActions': actions,
      if (needsReview)
        'repair':
            'Add at least one tool-readable verification action after the interaction flow, such as assertText, waitText, assertLog, or assertSession.',
      if (needsReview)
        'suggestedActions': const [
          {'action': 'assertText'},
          {'action': 'assertLog'},
          {'action': 'assertSession'},
        ],
    };
  }
}

bool _isScenarioVerificationAction(String action) {
  const verificationActions = {
    'assertText',
    'waitText',
    'assertLog',
    'assertSession',
  };
  return verificationActions.contains(action);
}

class _CapabilityCoverage {
  _CapabilityCoverage({required this.capability});

  final _AutomationCapability capability;
  final Set<String> _statuses = <String>{};
  final Set<String> _scenarios = <String>{};
  final Set<String> _paths = <String>{};

  bool get needsReview => _scenarios.isEmpty;

  void add(
    AutomationScenarioCoverageItem item, {
    required AutomationScenario scenario,
  }) {
    _statuses.add(item.status);
    _scenarios.add(scenario.path.path);
    final path = item.path?.trim();
    if (path != null && path.isNotEmpty) {
      _paths.add(path);
    }
  }

  Map<String, Object?> toJson() {
    return {
      'category': capability.category,
      'item': capability.coverageItem,
      'source': capability.source,
      'inventoryPath': capability.path,
      'status': needsReview ? 'needsCapabilityCoverageRows' : 'readyForReview',
      'paths': _sorted(_paths),
      'statuses': _sorted(_statuses),
      'scenarioPaths': _sorted(_scenarios),
      'scenarioCount': _scenarios.length,
      if (needsReview)
        'suggestedCoverage': [
          {
            'category': capability.category,
            'item': capability.coverageItem,
            'path': 'success',
            'status': 'covered',
          },
          {
            'category': capability.category,
            'item': capability.coverageItem,
            'path': 'error',
            'status': 'covered',
          },
        ],
      if (needsReview)
        'repair':
            'Add scenario coverage or integration-test evidence for this package capability, or mark it notApplicable or blocked with a note.',
    };
  }

  List<String> _sorted(Set<String> values) {
    return values.toList()..sort();
  }
}

bool _coverageMatchesCapability(
  AutomationScenarioCoverageItem item,
  _AutomationCapability capability,
) {
  if (_normalizedCoveragePath(item.item) !=
      _normalizedCoveragePath(capability.coverageItem)) {
    return false;
  }
  final coverageCategory = _normalizedCapabilityCategory(item.category);
  if (coverageCategory == 'capability') {
    return true;
  }
  return coverageCategory == _normalizedCapabilityCategory(capability.category);
}

String _normalizedCapabilityCategory(String category) {
  final normalized = _normalizedCoveragePath(category);
  return switch (normalized) {
    'api' || 'publicapi' || 'packageapi' => 'publicapi',
    'methodchannel' || 'platformcall' || 'nativecall' => 'methodchannel',
    'example' || 'exampleflow' || 'exampleentrypoint' => 'exampleflow',
    'capability' || 'feature' => 'capability',
    _ => normalized,
  };
}

class _ManifestPermissionCoverage {
  _ManifestPermissionCoverage({required this.permission});

  final _AutomationManifestPermission permission;
  final Set<String> _paths = <String>{};
  final Set<String> _statuses = <String>{};
  final Set<String> _scenarios = <String>{};
  var _hasPositivePath = false;
  var _hasNegativeOrErrorPath = false;

  bool get needsReview => !_hasPositivePath || !_hasNegativeOrErrorPath;

  void add(
    AutomationScenarioCoverageItem item, {
    required AutomationScenario scenario,
  }) {
    _statuses.add(item.status);
    _scenarios.add(scenario.path.path);
    final path = item.path?.trim();
    if (path == null || path.isEmpty) {
      return;
    }
    _paths.add(path);
    if (_isNegativeOrErrorCoveragePath(path)) {
      _hasNegativeOrErrorPath = true;
    } else if (_isPositiveCoveragePath(path)) {
      _hasPositivePath = true;
    }
  }

  Map<String, Object?> toJson() {
    return {
      'platform': permission.platform,
      'permission': permission.name,
      'coverageItem': permission.coverageItem,
      'source': permission.source,
      'manifestPath': permission.path,
      'status': needsReview ? 'needsPermissionCoverageRows' : 'readyForReview',
      'paths': _sorted(_paths),
      'statuses': _sorted(_statuses),
      'scenarioCount': _scenarios.length,
      if (!_hasPositivePath) 'needsPositivePath': true,
      if (!_hasNegativeOrErrorPath) 'needsNegativeOrErrorPath': true,
      if (needsReview)
        'suggestedCoverage': [
          {
            'category': 'permission',
            'item': permission.coverageItem,
            'path': 'grant',
            'status': 'covered',
          },
          {
            'category': 'permission',
            'item': permission.coverageItem,
            'path': 'deny',
            'status': 'covered',
          },
        ],
      if (needsReview)
        'repair':
            'Add selected-platform scenario coverage for this manifest permission, including grant and denied/error behavior paths, or mark a path notApplicable or blocked with a note.',
    };
  }

  List<String> _sorted(Set<String> values) {
    return values.toList()..sort();
  }
}

class _CoveragePathGroup {
  _CoveragePathGroup({required this.category, required this.item});

  final String category;
  final String item;
  final Set<String> _paths = <String>{};
  final Set<String> _statuses = <String>{};
  final Set<String> _scenarios = <String>{};
  var _hasMissingPath = false;
  var _hasPositivePath = false;
  var _hasNegativeOrErrorPath = false;

  bool get needsReview =>
      _hasMissingPath || !_hasPositivePath || !_hasNegativeOrErrorPath;

  void add(
    AutomationScenarioCoverageItem item, {
    required AutomationScenario scenario,
  }) {
    _statuses.add(item.status);
    _scenarios.add(scenario.path.path);
    final path = item.path?.trim();
    if (path == null || path.isEmpty) {
      _hasMissingPath = true;
      return;
    }
    _paths.add(path);
    if (_isNegativeOrErrorCoveragePath(path)) {
      _hasNegativeOrErrorPath = true;
    } else if (_isPositiveCoveragePath(path)) {
      _hasPositivePath = true;
    }
  }

  Map<String, Object?> toJson() {
    return {
      'category': category,
      'item': item,
      'status': needsReview ? 'needsPathCoverageReview' : 'readyForReview',
      'paths': _sorted(_paths),
      'statuses': _sorted(_statuses),
      'scenarioPaths': _sorted(_scenarios),
      'scenarioCount': _scenarios.length,
      if (_hasMissingPath) 'missingPath': true,
      if (!_hasPositivePath) 'needsPositivePath': true,
      if (!_hasNegativeOrErrorPath) 'needsNegativeOrErrorPath': true,
      if (needsReview)
        'repair':
            'Add explicit coverage rows for both success and denied, cancelled, failure, or error behavior paths; use notApplicable or blocked with a note when a path is intentionally not automated.',
    };
  }

  List<String> _sorted(Set<String> values) {
    return values.toList()..sort();
  }
}

bool _isPositiveCoveragePath(String path) {
  if (_isNegativeOrErrorCoveragePath(path)) {
    return false;
  }
  final normalized = _normalizedCoveragePath(path);
  const tokens = [
    'grant',
    'allow',
    'authorize',
    'success',
    'happy',
    'enable',
    'available',
    'select',
    'pick',
    'capture',
    'record',
    'play',
    'read',
    'write',
    'create',
    'update',
    'delete',
    'request',
    'load',
    'save',
    'start',
    'stop',
    'open',
    'callback',
    'valid',
    'accept',
  ];
  return tokens.any(normalized.contains);
}

bool _isNegativeOrErrorCoveragePath(String path) {
  final normalized = _normalizedCoveragePath(path);
  const tokens = [
    'deny',
    'denied',
    'reject',
    'revoke',
    'error',
    'fail',
    'cancel',
    'unavailable',
    'disable',
    'blocked',
    'timeout',
    'exception',
    'unsupported',
    'missing',
    'invalid',
    'unauthorize',
    'forbidden',
    'empty',
    'negative',
  ];
  return tokens.any(normalized.contains);
}

String _normalizedCoveragePath(String path) {
  return path.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
}

class _AutomationCheckPlan {
  const _AutomationCheckPlan({
    required this.platform,
    required this.packageName,
    required this.deviceId,
    required this.emulatorName,
    required this.autoEmulator,
    required this.sessionDirectory,
    required this.traceOptions,
  });

  final String platform;
  final String? packageName;
  final String? deviceId;
  final String? emulatorName;
  final bool autoEmulator;
  final Directory sessionDirectory;
  final TraceOptions traceOptions;

  Map<String, Object?> toJson() {
    final policy = platformWorkflowPolicy(platform);
    final sessionFile = _automationSessionFile(
      platform: platform,
      targetName: packageName ?? '<target>',
      sessionDirectory: sessionDirectory,
    );
    return {
      'platform': platform,
      'command': _automationRunCommand(
        platform: platform,
        packageName: packageName,
        deviceId: deviceId,
        emulatorName: emulatorName,
        autoEmulator: autoEmulator,
        sessionFile: sessionFile,
        traceOptions: traceOptions,
      ),
      'driver': automationScenarioPlatformDriverMetadata(platform),
      'evidence': [
        'fluoh command JSON',
        'trace manifest when --trace or --trace-dir is used',
        ...policy.automationEvidenceItems,
        'integration_test result when integration_test/ exists',
      ],
      'agentLoop': [
        'select or boot local emulator/simulator',
        'build and launch package example or project app',
        'collect run session, logs, diagnostics, and trace references',
        'route failures through nextCommand before editing again',
      ],
      if (sessionFile != null) 'sessionFile': sessionFile.path,
      ...policy.automationMetadata,
    };
  }
}

String _automationRunCommand({
  required String platform,
  required String? packageName,
  required String? deviceId,
  required String? emulatorName,
  required bool autoEmulator,
  required File? sessionFile,
  required TraceOptions traceOptions,
}) {
  final parts = [
    'fluoh',
    'run',
    platform,
    if (packageName != null) ...['--package', packageName],
    if (deviceId != null) ...['--device-id', deviceId],
    if (emulatorName != null) ...['--emulator', emulatorName],
    if (deviceId == null &&
        emulatorName == null &&
        autoEmulator &&
        !_isDesktopRunPlatform(platform))
      '--auto-emulator',
    if (sessionFile != null) ...['--session-file', sessionFile.path],
    if (traceOptions.enabled && traceOptions.directory == null) '--trace',
    if (traceOptions.directory != null) ...[
      '--trace-dir',
      traceOptions.directory!.path,
    ],
    '--json',
  ];
  return parts.map(_workflowShellQuote).join(' ');
}

String _workflowShellQuote(String value) {
  if (value.isEmpty) {
    return "''";
  }
  if (!RegExp(r'''[\s'"\\$`]''').hasMatch(value)) {
    return value;
  }
  return "'${value.replaceAll("'", r"'\''")}'";
}

void _printAutomationPlan(_AutomationPlan plan, TerminalOutput output) {
  output.write('Automation plan:');
  for (final check in plan.toJson()['checks']! as List<Object?>) {
    final item = check as Map<String, Object?>;
    output.write('  ${item['platform']}: ${item['command']}');
  }
}
