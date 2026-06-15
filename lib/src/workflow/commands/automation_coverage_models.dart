part of 'workflow_commands.dart';

class _ScenarioEvidence {
  const _ScenarioEvidence({required this.scenario});

  final AutomationScenario scenario;

  int get coveredCoverageItemCount =>
      scenario.coverage.where((item) => item.status == 'covered').length;

  int get explanatoryCoverageItemCount =>
      scenario.coverage.length - coveredCoverageItemCount;

  bool get needsReview => evidenceGapCoverageItems.isNotEmpty;

  bool get needsPageReadiness =>
      coveredCoverageItemCount > 0 &&
      launchEvidenceActions.isNotEmpty &&
      pageReadinessActions.isEmpty;

  List<String> get verificationActions {
    return [
      for (final action in scenario.steps)
        if (_isScenarioVerificationAction(action.action)) action.action,
    ];
  }

  List<String> get launchEvidenceActions {
    return [
      for (final action in scenario.steps)
        if (_isScenarioLaunchEvidenceAction(action.action)) action.action,
    ];
  }

  List<String> get interactionActions {
    return [
      for (final action in scenario.steps)
        if (_isScenarioInteractionAction(action.action)) action.action,
    ];
  }

  List<String> get pageReadinessActions {
    return [
      for (final action in scenario.steps)
        if (_isScenarioPageReadinessAction(action.action)) action.action,
    ];
  }

  List<AutomationScenarioCoverageItem> get evidenceGapCoverageItems {
    return [
      for (final binding in coverageEvidenceBindings)
        if (binding.needsReview) binding.item,
    ];
  }

  List<_CoverageEvidenceBinding> get coverageEvidenceBindings {
    return [
      for (final item in scenario.coverage)
        if (item.status == 'covered') _bindingFor(item),
    ];
  }

  Map<String, Object?> pageReadinessJson() {
    return {
      'platform': scenario.platform,
      'scenario': scenario.name,
      'path': scenario.path.path,
      'status': needsPageReadiness
          ? 'needsPageReadinessEvidence'
          : 'readyForReview',
      'launchEvidenceActions': launchEvidenceActions,
      'pageReadinessActions': pageReadinessActions,
      if (needsPageReadiness)
        'repair':
            'Add a page readiness assertion such as assertText, waitText, or assertLog after launch. Screenshots remain supporting evidence only.',
      if (needsPageReadiness)
        'suggestedScenarioPatch': _suggestedScenarioPatch(
          evidenceGapCoverageItems.isEmpty
              ? scenario.coverage
                    .where((item) => item.status == 'covered')
                    .take(1)
                    .toList()
              : evidenceGapCoverageItems,
        ),
    };
  }

  Map<String, Object?> toJson() {
    final actions = verificationActions;
    final launchActions = launchEvidenceActions;
    final interactions = interactionActions;
    final evidenceGaps = evidenceGapCoverageItems;
    final bindings = coverageEvidenceBindings;
    final needsFunctionalEvidence = bindings.any(
      (binding) => binding.missingFunctionalAssertion,
    );
    final needsInteractionEvidence = bindings.any(
      (binding) => binding.missingInteraction,
    );
    return {
      'platform': scenario.platform,
      'scenario': scenario.name,
      'path': scenario.path.path,
      'coverageItemCount': scenario.coverage.length,
      'coveredCoverageItemCount': coveredCoverageItemCount,
      'explanatoryCoverageItemCount': explanatoryCoverageItemCount,
      'status': needsReview ? 'needsFunctionalEvidence' : 'readyForReview',
      'verificationActions': actions,
      'launchEvidenceActions': launchActions,
      'interactionActions': interactions,
      'pageReadinessActions': pageReadinessActions,
      'coverageEvidenceBindings': bindings
          .map((binding) => binding.toJson())
          .toList(),
      if (evidenceGaps.isNotEmpty)
        'evidenceGaps': evidenceGaps.map((item) => item.toJson()).toList(),
      if (needsReview)
        'repair': needsFunctionalEvidence
            ? 'Add a functional tool-readable assertion after the interaction flow. assertSession, launchApp, wait, and screenshots only prove launch or visual sanity, not permission, public API, or behavior coverage.'
            : needsInteractionEvidence
            ? 'Add a real interaction step before the assertion, then rerun drive. Covered permission and behavior rows need action evidence plus a result assertion.'
            : 'Add functional scenario evidence, then rerun drive.',
      if (needsReview)
        'suggestedActions': const [
          {'action': 'tapText'},
          {'action': 'allowPermission'},
          {'action': 'denyPermission'},
          {'action': 'assertText'},
          {'action': 'waitText'},
          {'action': 'assertLog'},
        ],
      if (needsReview)
        'suggestedScenarioPatch': _suggestedScenarioPatch(evidenceGaps),
    };
  }

  _CoverageEvidenceBinding _bindingFor(AutomationScenarioCoverageItem item) {
    final actionsByStep = {
      for (final action in scenario.steps) action.index: action,
    };
    final explicitProblems = <String>[];
    final explicitInteraction = _explicitActionAt(
      actionsByStep,
      item.interactionStep,
      expected: _isScenarioInteractionAction,
      problem: 'interactionStepMustReferenceInteractionAction',
      problems: explicitProblems,
    );
    final explicitAssertion = _explicitActionAt(
      actionsByStep,
      item.assertionStep,
      expected: _isScenarioVerificationAction,
      problem: 'assertionStepMustReferenceFunctionalAssertion',
      problems: explicitProblems,
    );
    final evidenceActions = <AutomationScenarioAction>[];
    for (final step in item.evidenceSteps) {
      final action = actionsByStep[step];
      if (action != null) {
        evidenceActions.add(action);
      }
    }
    AutomationScenarioAction? evidenceAssertion;
    for (final action in evidenceActions) {
      if (_isScenarioVerificationAction(action.action)) {
        evidenceAssertion = action;
        break;
      }
    }
    final interaction = item.interactionStep == null
        ? _inferInteractionAction(item)
        : explicitInteraction;
    final assertion = item.assertionStep == null
        ? evidenceAssertion ?? _inferAssertionAction(after: interaction?.index)
        : explicitAssertion;
    final missingReasons = <String>[
      ...explicitProblems,
      if (_coverageNeedsInteractionAction(item) && interaction == null)
        'missingInteractionStep',
      if (assertion == null) 'missingFunctionalAssertionStep',
    ];
    return _CoverageEvidenceBinding(
      item: item,
      interactionAction: interaction,
      assertionAction: assertion,
      evidenceActions: evidenceActions,
      bindingMode:
          item.interactionStep != null ||
              item.assertionStep != null ||
              item.evidenceSteps.isNotEmpty
          ? 'explicit'
          : 'inferred',
      missingReasons: missingReasons,
    );
  }

  AutomationScenarioAction? _explicitActionAt(
    Map<int, AutomationScenarioAction> actionsByStep,
    int? step, {
    required bool Function(String action) expected,
    required String problem,
    required List<String> problems,
  }) {
    if (step == null) {
      return null;
    }
    final action = actionsByStep[step];
    if (action == null) {
      problems.add('stepNotFound:$step');
      return null;
    }
    if (!expected(action.action)) {
      problems.add('$problem:$step:${action.action}');
      return null;
    }
    return action;
  }

  AutomationScenarioAction? _inferInteractionAction(
    AutomationScenarioCoverageItem item,
  ) {
    if (!_coverageNeedsInteractionAction(item)) {
      return null;
    }
    final expectedAction = _permissionInteractionAction(item.path);
    for (final action in scenario.steps) {
      if (expectedAction != null && action.action != expectedAction) {
        continue;
      }
      if (expectedAction == null &&
          !_isScenarioInteractionAction(action.action)) {
        continue;
      }
      final permission = action.permission?.trim();
      if (permission == null ||
          permission.isEmpty ||
          _normalizedCoveragePath(permission) ==
              _normalizedCoveragePath(item.item)) {
        return action;
      }
    }
    return null;
  }

  AutomationScenarioAction? _inferAssertionAction({int? after}) {
    for (final action in scenario.steps) {
      if (after != null && action.index <= after) {
        continue;
      }
      if (_isScenarioVerificationAction(action.action)) {
        return action;
      }
    }
    return null;
  }

  Map<String, Object?> _suggestedScenarioPatch(
    List<AutomationScenarioCoverageItem> items,
  ) {
    final coverageUpdates = <Map<String, Object?>>[];
    final steps = <Map<String, Object?>>[];
    var nextStep = scenario.steps.length + 1;
    for (final item in items.take(3)) {
      int? interactionStep;
      if (_coverageNeedsInteractionAction(item)) {
        steps.add(_suggestedTriggerAction(item));
        nextStep += 1;
        interactionStep = nextStep;
        steps.add(_suggestedInteractionAction(item));
        nextStep += 1;
      }
      final assertionStep = nextStep;
      steps.add(_suggestedAssertionAction(item));
      nextStep += 1;
      final coverageUpdate = <String, Object?>{
        ...item.toJson(),
        'assertionStep': assertionStep,
      };
      if (interactionStep != null) {
        coverageUpdate['interactionStep'] = interactionStep;
      }
      coverageUpdates.add(coverageUpdate);
    }
    return {
      'mode': 'updateCoverageRowsAndAppendSteps',
      'path': scenario.path.path,
      'coverageUpdates': coverageUpdates,
      'steps': steps,
      'yaml': _scenarioPatchYaml(coverageUpdates, steps),
      'notes': const [
        'Replace matching coverage rows with coverageUpdates.',
        'Append steps, then adjust TODO labels/log markers to real app output.',
        'Rerun the printed fluoh drive command.',
      ],
    };
  }
}

class _CoverageEvidenceBinding {
  const _CoverageEvidenceBinding({
    required this.item,
    required this.interactionAction,
    required this.assertionAction,
    required this.evidenceActions,
    required this.bindingMode,
    required this.missingReasons,
  });

  final AutomationScenarioCoverageItem item;
  final AutomationScenarioAction? interactionAction;
  final AutomationScenarioAction? assertionAction;
  final List<AutomationScenarioAction> evidenceActions;
  final String bindingMode;
  final List<String> missingReasons;

  bool get needsReview => missingReasons.isNotEmpty;

  bool get missingInteraction => missingReasons.any(
    (reason) =>
        reason == 'missingInteractionStep' ||
        reason.contains('interactionStep'),
  );

  bool get missingFunctionalAssertion => missingReasons.any(
    (reason) =>
        reason == 'missingFunctionalAssertionStep' ||
        reason.contains('assertionStep'),
  );

  Map<String, Object?> toJson() {
    return {
      'coverage': item.toJson(),
      'category': item.category,
      'item': item.item,
      if (item.path != null) 'path': item.path,
      'status': needsReview ? 'needsFunctionalEvidence' : 'readyForReview',
      'bindingMode': bindingMode,
      if (interactionAction != null) ...{
        'interactionStep': interactionAction!.index,
        'interactionAction': interactionAction!.action,
      },
      if (assertionAction != null) ...{
        'assertionStep': assertionAction!.index,
        'assertionAction': assertionAction!.action,
      },
      if (evidenceActions.isNotEmpty)
        'evidenceSteps': [
          for (final action in evidenceActions)
            {'step': action.index, 'action': action.action},
        ],
      if (missingReasons.isNotEmpty) 'missingReasons': missingReasons,
    };
  }
}

bool _isScenarioVerificationAction(String action) {
  const verificationActions = {'assertText', 'waitText', 'assertLog'};
  return verificationActions.contains(action);
}

bool _isScenarioLaunchEvidenceAction(String action) {
  const launchEvidenceActions = {
    'assertSession',
    'launchApp',
    'wait',
    'captureScreenshot',
    'screenshot',
  };
  return launchEvidenceActions.contains(action);
}

bool _isScenarioInteractionAction(String action) {
  const interactionActions = {
    'tap',
    'tapText',
    'allowPermission',
    'denyPermission',
    'resetPermission',
    'clearAppData',
    'swipe',
    'drag',
    'inputText',
    'press',
  };
  return interactionActions.contains(action);
}

bool _coverageNeedsInteractionAction(AutomationScenarioCoverageItem item) {
  final category = _normalizedCapabilityCategory(item.category);
  if (category == 'permission') {
    return true;
  }
  return false;
}

bool _isScenarioPageReadinessAction(String action) {
  return _isScenarioVerificationAction(action);
}

String? _permissionInteractionAction(String? path) {
  final normalized = _normalizedCoveragePath(path ?? '');
  if (_isPositiveCoveragePath(normalized) || normalized == 'grant') {
    return 'allowPermission';
  }
  if (_isNegativeOrErrorCoveragePath(normalized) ||
      normalized == 'deny' ||
      normalized == 'denied') {
    return 'denyPermission';
  }
  if (normalized == 'reset') {
    return 'resetPermission';
  }
  return null;
}

Map<String, Object?> _suggestedTriggerAction(
  AutomationScenarioCoverageItem item,
) {
  return {
    'action': 'tapText',
    'labels': ['TODO trigger ${item.item} ${item.path ?? 'flow'}'],
    'repairHints': [
      'Expose a stable label, semantics label, or test key for this trigger.',
    ],
  };
}

Map<String, Object?> _suggestedInteractionAction(
  AutomationScenarioCoverageItem item,
) {
  final action = _permissionInteractionAction(item.path) ?? 'tapText';
  return {
    'action': action,
    if (action == 'allowPermission') 'labels': ['Allow'],
    if (action == 'denyPermission') 'labels': ['Deny'],
    if (action == 'resetPermission') 'permission': item.item,
    if (action == 'tapText')
      'labels': ['TODO operate ${item.item} ${item.path ?? 'flow'}'],
    if (action == 'allowPermission' || action == 'denyPermission')
      'permission': item.item,
    'repairHints': [
      'Use the real platform permission name or prompt label when different.',
    ],
  };
}

Map<String, Object?> _suggestedAssertionAction(
  AutomationScenarioCoverageItem item,
) {
  return {
    'action': 'assertText',
    'labels': ['TODO ${item.item} ${item.path ?? 'result'} result'],
    'repairHints': [
      'Render stable result text, semantics, a test key, or add assertLog with a structured app log marker.',
    ],
  };
}

String _scenarioPatchYaml(
  List<Map<String, Object?>> coverageUpdates,
  List<Map<String, Object?>> steps,
) {
  final buffer = StringBuffer()
    ..writeln('coverage:')
    ..write(_yamlList(coverageUpdates))
    ..writeln('steps:')
    ..write(_yamlList(steps));
  return buffer.toString().trimRight();
}

String _yamlList(List<Map<String, Object?>> values) {
  final buffer = StringBuffer();
  for (final value in values) {
    var first = true;
    for (final entry in value.entries) {
      final prefix = first ? '  - ' : '    ';
      first = false;
      buffer.writeln('$prefix${entry.key}: ${_yamlValue(entry.value)}');
    }
  }
  return buffer.toString();
}

String _yamlValue(Object? value) {
  if (value is List) {
    return '[${value.map(_yamlScalar).join(', ')}]';
  }
  return _yamlScalar(value);
}

String _yamlScalar(Object? value) {
  if (value == null) {
    return 'null';
  }
  if (value is num || value is bool) {
    return value.toString();
  }
  final string = value.toString().replaceAll("'", "''");
  return "'$string'";
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
            'Add scenario coverage or integration-test evidence for this package capability, or mark it notApplicable only when the behavior does not exist on this platform.',
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
    'runtimepermission' || 'permissions' => 'permission',
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
            'Add selected-platform scenario coverage for this manifest permission, including grant and denied/error behavior paths, or mark a path notApplicable only when the permission has no runtime behavior on this platform.',
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
            'Add explicit coverage rows for both success and denied, cancelled, failure, or error behavior paths; use notApplicable only when a path does not exist on this platform.',
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
