part of 'workflow_commands.dart';

_AutomationPlan _automationPlan({
  required List<String> platforms,
  required String? packageName,
  required bool requestedAllPlatforms,
  required String? deviceId,
  required String? emulatorName,
  required bool autoEmulator,
  required Duration deviceTimeout,
  required Duration logDuration,
  required Directory sessionDirectory,
  required TraceOptions traceOptions,
  required List<AutomationScenario> scenarios,
  required _AutomationInventory inventory,
}) {
  return _AutomationPlan(
    platforms: platforms,
    packageName: packageName,
    requestedAllPlatforms: requestedAllPlatforms,
    deviceId: deviceId,
    emulatorName: emulatorName,
    autoEmulator: autoEmulator,
    deviceTimeout: deviceTimeout,
    logDuration: logDuration,
    sessionDirectory: sessionDirectory,
    traceOptions: traceOptions,
    scenarios: scenarios,
    inventory: inventory,
  );
}

class _AutomationPlan {
  const _AutomationPlan({
    required this.platforms,
    required this.packageName,
    required this.requestedAllPlatforms,
    required this.deviceId,
    required this.emulatorName,
    required this.autoEmulator,
    required this.deviceTimeout,
    required this.logDuration,
    required this.sessionDirectory,
    required this.traceOptions,
    required this.scenarios,
    required this.inventory,
  });

  final List<String> platforms;
  final String? packageName;
  final bool requestedAllPlatforms;
  final String? deviceId;
  final String? emulatorName;
  final bool autoEmulator;
  final Duration deviceTimeout;
  final Duration logDuration;
  final Directory sessionDirectory;
  final TraceOptions traceOptions;
  final List<AutomationScenario> scenarios;
  final _AutomationInventory inventory;

  Map<String, Object?> toJson({
    List<WorkflowTargetResult>? results,
    bool dryRun = false,
  }) {
    final coveragePolicy = _AutomationCoveragePolicy(
      scenarios: scenarios,
      inventory: inventory,
      platforms: platforms,
    ).toJson();
    final checks = [
      for (final platform in platforms)
        _AutomationCheckPlan(
          platform: platform,
          packageName: packageName,
          deviceId: deviceId,
          emulatorName: emulatorName,
          autoEmulator: autoEmulator,
          sessionDirectory: sessionDirectory,
          traceOptions: traceOptions,
        ).toJson(),
    ];
    final executionResults = results ?? const <WorkflowTargetResult>[];
    final rerunCommand = _driveCommand(dryRun: dryRun);
    Map<String, Object?>? deliveryRecommendation;
    List<Map<String, Object?>>? repairQueue;
    if (results != null || dryRun) {
      deliveryRecommendation = _deliveryRecommendation(
        executionResults,
        coveragePolicy,
        dryRun: dryRun,
      );
      repairQueue = _repairQueue(
        executionResults,
        coveragePolicy,
        executionCommand: _driveCommand(dryRun: false),
        dryRun: dryRun,
      );
    }
    return {
      'schema': 1,
      'kind': 'fluoh.mobileAutomation',
      'platforms': platforms,
      'targetSelection': {
        if (requestedAllPlatforms) 'platform': _allWorkflowPlatform,
        if (packageName != null) 'package': packageName,
      },
      'targeting': {
        'autoEmulator': autoEmulator,
        if (deviceId != null) 'device': deviceId,
        if (emulatorName != null) 'emulator': emulatorName,
      },
      'sessionDirectory': sessionDirectory.path,
      if (scenarios.isNotEmpty)
        'scenarios': scenarios.map((scenario) => scenario.toJson()).toList(),
      'trace': {
        'enabled': traceOptions.enabled || traceOptions.directory != null,
        if (traceOptions.directory != null)
          'directory': traceOptions.directory!.path,
      },
      'coveragePolicy': coveragePolicy,
      'rerunCommand': rerunCommand,
      if (deliveryRecommendation != null && repairQueue != null) ...{
        'deliveryRecommendation': deliveryRecommendation,
        'repairQueue': repairQueue,
        'repairPlan': _repairPlan(
          deliveryRecommendation,
          repairQueue,
          rerunCommand: rerunCommand,
        ),
      },
      'inspiredBy': {
        'name': 'callstack/agent-device',
        'url': 'https://github.com/callstack/agent-device',
        'model':
            'boot or select target, launch the app, keep a session, collect compact evidence, then replay or debug from the recorded state',
      },
      'checks': checks,
    };
  }

  String _driveCommand({required bool dryRun}) {
    final platform = requestedAllPlatforms
        ? _allWorkflowPlatform
        : platforms.single;
    final parts = [
      'fluoh',
      'drive',
      platform,
      if (packageName != null) ...['--package', packageName!],
      if (deviceId != null) ...['--device-id', deviceId!],
      if (emulatorName != null) ...['--emulator', emulatorName!],
      if (deviceId == null && emulatorName == null)
        autoEmulator ? '--auto-emulator' : '--no-auto-emulator',
      '--device-timeout',
      deviceTimeout.inSeconds.toString(),
      '--log-duration',
      logDuration.inSeconds.toString(),
      '--session-dir',
      sessionDirectory.path,
      for (final scenario in scenarios) ...['--scenario', scenario.path.path],
      if (traceOptions.enabled && traceOptions.directory == null) '--trace',
      if (traceOptions.directory != null) ...[
        '--trace-dir',
        traceOptions.directory!.path,
      ],
      if (dryRun) '--dry-run',
      '--json',
    ];
    return parts.map(_workflowShellQuote).join(' ');
  }

  Map<String, Object?> _repairPlan(
    Map<String, Object?> deliveryRecommendation,
    List<Map<String, Object?>> repairQueue, {
    required String rerunCommand,
  }) {
    final firstItem = repairQueue.isEmpty ? null : repairQueue.first;
    return {
      'schema': 1,
      'status': deliveryRecommendation['status'],
      'recommendation': deliveryRecommendation['recommendation'],
      'ready': deliveryRecommendation['ready'],
      'queueLength': repairQueue.length,
      'nextStep': firstItem == null
          ? {
              'kind': 'none',
              'action':
                  'No repair item remains. Prepare the final report review with the recorded automation evidence.',
            }
          : _repairPlanNextStep(firstItem, rerunCommand: rerunCommand),
    };
  }

  Map<String, Object?> _repairPlanNextStep(
    Map<String, Object?> item, {
    required String rerunCommand,
  }) {
    final type = item['type'] as String?;
    final nextAction = item['nextAction'];
    if (nextAction is Map<String, Object?>) {
      return {
        'kind': nextAction['kind'] ?? 'applyNextAction',
        'sourceType': type,
        'action': _repairPlanAction(type),
        if (item['gate'] != null) 'gate': item['gate'],
        if (item['status'] != null) 'status': item['status'],
        if (item['platform'] != null) 'platform': item['platform'],
        if (item['category'] != null) 'category': item['category'],
        if (item['item'] != null) 'item': item['item'],
        if (item['permission'] != null) 'permission': item['permission'],
        if (item['coverageItem'] != null) 'coverageItem': item['coverageItem'],
        'nextAction': nextAction,
        'doneWhen': _repairPlanDoneWhen(type, item),
        'validation': _repairPlanValidation(
          type,
          item,
          rerunCommand: rerunCommand,
        ),
      };
    }
    if (type == 'execution') {
      return {
        'kind': 'executeAutomation',
        'sourceType': type,
        'action':
            'Run the planned drive automation command and keep the resulting JSON evidence before reporting ready.',
        if (item['nextCommands'] != null) 'nextCommands': item['nextCommands'],
        'doneWhen': _repairPlanDoneWhen(type, item),
        'validation': _repairPlanValidation(
          type,
          item,
          rerunCommand: rerunCommand,
        ),
      };
    }
    if (type == 'diagnostic') {
      return {
        'kind': item['nextCommand'] == null
            ? 'fixDiagnostic'
            : 'fixDiagnosticAndRerun',
        'sourceType': type,
        'action':
            'Fix the failed target or scenario diagnostic, then rerun the printed nextCommand.',
        if (item['target'] != null) 'target': item['target'],
        if (item['step'] != null) 'step': item['step'],
        if (item['code'] != null) 'code': item['code'],
        if (item['message'] != null) 'message': item['message'],
        if (item['repairHints'] != null) 'repairHints': item['repairHints'],
        if (item['nextCommand'] != null) 'nextCommand': item['nextCommand'],
        'doneWhen': _repairPlanDoneWhen(type, item),
        'validation': _repairPlanValidation(
          type,
          item,
          rerunCommand: rerunCommand,
        ),
      };
    }
    if (type == 'coverageBlocked') {
      return {
        'kind': 'repairBlockedCoverage',
        'sourceType': type,
        'action':
            'Fix the package or demo, add full automation evidence, or mark the row notApplicable only when the behavior does not exist on this platform.',
        if (item['platform'] != null) 'platform': item['platform'],
        if (item['scenario'] != null) 'scenario': item['scenario'],
        if (item['path'] != null) 'path': item['path'],
        if (item['coverage'] != null) 'coverage': item['coverage'],
        'doneWhen': _repairPlanDoneWhen(type, item),
        'validation': _repairPlanValidation(
          type,
          item,
          rerunCommand: rerunCommand,
        ),
      };
    }
    if (type == 'coverage') {
      return {
        'kind': 'completeCoverageGate',
        'sourceType': type,
        'action':
            'Complete the reported coverage gate before executing automation or reporting ready.',
        if (item['gate'] != null) 'gate': item['gate'],
        if (item['status'] != null) 'status': item['status'],
        if (item['repair'] != null) 'repair': item['repair'],
        'doneWhen': _repairPlanDoneWhen(type, item),
        'validation': _repairPlanValidation(
          type,
          item,
          rerunCommand: rerunCommand,
        ),
      };
    }
    return {
      'kind': 'inspectRepairQueueItem',
      'sourceType': type ?? 'unknown',
      'action':
          'Inspect the first repairQueue item, make the smallest required edit, then rerun the same automation command.',
      'item': item,
      'doneWhen': _repairPlanDoneWhen(type, item),
      'validation': _repairPlanValidation(
        type,
        item,
        rerunCommand: rerunCommand,
      ),
    };
  }

  List<String> _repairPlanDoneWhen(String? type, Map<String, Object?> item) {
    final gate = item['gate'];
    final category = item['category'];
    final coverageItem = item['coverageItem'] ?? item['item'];
    final code = item['code'];
    return switch (type) {
      'diagnostic' => [
        if (code != null) 'diagnostic $code no longer appears',
        'the failed target or scenario step passes',
      ],
      'execution' => [
        'the planned automation command exits successfully',
        'real drive JSON includes passed targets and retained evidence',
      ],
      'coverageBlocked' => [
        'the blocked row is replaced by covered automation evidence or a valid notApplicable row',
        'the same drive command no longer reports coverageBlocked repair items',
      ],
      'coverage' => [
        if (gate != null) 'quality gate $gate reports readyForReview',
        'automation.deliveryRecommendation no longer reports needsCoverageReview',
      ],
      'scenarioCoverage' => [
        if (category != null && coverageItem != null)
          '$category/$coverageItem capability coverage reports readyForReview',
        'the scenario coverage row has covered or valid notApplicable status',
      ],
      'permissionCoverage' => [
        if (coverageItem != null)
          'manifest permission coverage for $coverageItem reports readyForReview',
        'grant and denied/error permission paths are covered or valid notApplicable rows explain that no runtime behavior exists on this platform',
      ],
      'pathCoverage' => [
        if (category != null && coverageItem != null)
          '$category/$coverageItem behavior paths report readyForReview',
        'both success and negative/error behavior paths are covered or valid notApplicable rows explain that no runtime behavior exists on this platform',
      ],
      'scenarioEvidence' => [
        'scenarioEvidence reports readyForReview for the scenario',
        'the scenario includes a functional assertion such as assertText, waitText, or assertLog after the interaction flow',
      ],
      'pageReadiness' => [
        'page-readiness reports readyForReview for the scenario',
        'the scenario asserts post-launch functional page state with assertText, waitText, or assertLog',
      ],
      'testCoverage' => [
        if (item['expectedTestPath'] != null)
          'focused package test exists at ${item['expectedTestPath']} or an accepted alternative',
        if (item['testCommand'] != null)
          'focused package test command passes: ${item['testCommand']}',
        'existing-test-baseline reports readyForReview',
      ],
      _ => [
        'the first repairQueue item is resolved',
        'rerunning drive no longer emits the same first repair item',
      ],
    };
  }

  Map<String, Object?> _repairPlanValidation(
    String? type,
    Map<String, Object?> item, {
    required String rerunCommand,
  }) {
    final nextCommand = item['nextCommand'];
    if (nextCommand is String && nextCommand.isNotEmpty) {
      return {'kind': 'command', 'command': nextCommand};
    }
    final nextCommands = item['nextCommands'];
    if (nextCommands is List<Object?> && nextCommands.isNotEmpty) {
      return {'kind': 'commands', 'commands': nextCommands};
    }
    if (type == 'testCoverage') {
      final testCommand = item['testCommand'];
      final acceptedTestCommands = item['acceptedTestCommands'];
      return {
        'kind': 'packageTestsThenDrive',
        if (item['expectedTestPath'] != null)
          'testPath': item['expectedTestPath'],
        if (testCommand is String && testCommand.isNotEmpty)
          'testCommand': testCommand,
        if (acceptedTestCommands is List<Object?> &&
            acceptedTestCommands.isNotEmpty)
          'acceptedTestCommands': acceptedTestCommands,
        'driveCommand': rerunCommand,
        'commands': [
          if (testCommand is String && testCommand.isNotEmpty) testCommand,
          rerunCommand,
        ],
      };
    }
    if (type == 'coverageBlocked') {
      return {'kind': 'reportEvidence', 'driveCommand': rerunCommand};
    }
    return {'kind': 'sameDriveCommand', 'command': rerunCommand};
  }

  String _repairPlanAction(String? type) {
    return switch (type) {
      'scenarioCoverage' =>
        'Add or update scenario coverage rows for the discovered package capability, then rerun drive.',
      'permissionCoverage' =>
        'Add selected-platform permission coverage rows for grant and denied or error paths, then rerun drive.',
      'pathCoverage' =>
        'Add the missing success or negative behavior path rows, then rerun drive.',
      'scenarioEvidence' =>
        'Add functional scenario evidence after the interaction flow, then rerun drive.',
      'pageReadiness' =>
        'Add a post-launch page readiness assertion, then rerun drive.',
      'testCoverage' =>
        'Create or expand the focused package test, then rerun package tests and drive.',
      _ =>
        'Apply the printed nextAction, then rerun the same automation command.',
    };
  }

  Map<String, Object?> _deliveryRecommendation(
    List<WorkflowTargetResult> results,
    Map<String, Object?> coveragePolicy, {
    required bool dryRun,
  }) {
    final failedTargets = [
      for (final result in results)
        if (!result.passed) result.targetName,
    ];
    final coverageSummary =
        coveragePolicy['coverageSummary'] as Map<String, Object?>;
    final statusCounts =
        coverageSummary['statusCounts'] as Map<String, Object?>;
    final blockedCoverage = statusCounts['blocked'] as int? ?? 0;
    final gateStatuses = [
      for (final gate in coveragePolicy['qualityGates'] as List<Object?>)
        (gate as Map<String, Object?>)['status'] as String,
    ];
    final hasCoverageGap = gateStatuses.any(_isAutomationCoverageGapStatus);
    final status = failedTargets.isNotEmpty
        ? 'needsRepair'
        : hasCoverageGap
        ? 'needsCoverageReview'
        : blockedCoverage > 0
        ? 'needsCoverageReview'
        : dryRun
        ? 'needsExecution'
        : 'readyForReportReview';
    final recommendation = switch (status) {
      'readyForReportReview' => 'ready',
      _ => 'blocked',
    };
    return {
      'schema': 1,
      'status': status,
      'recommendation': recommendation,
      'ready': status == 'readyForReportReview',
      'reason': _deliveryRecommendationReason(status),
      'targetSummary': {
        'total': results.length,
        'passed': results.where((result) => result.passed).length,
        'failed': failedTargets.length,
        'executed': !dryRun,
        if (dryRun) 'dryRun': true,
      },
      if (failedTargets.isNotEmpty) 'failedTargets': failedTargets,
      'coverageSummary': coverageSummary,
      'finalReportReminder':
          'Ready only applies to the declared automation evidence. The final report must still prove the package capability inventory is complete.',
    };
  }

  String _deliveryRecommendationReason(String status) {
    return switch (status) {
      'needsRepair' =>
        'One or more workflow targets or scenario actions failed; inspect repairQueue and rerun the exact nextCommand.',
      'needsCoverageReview' =>
        'Automation launched, but coverage inventory, metadata, rows, or blocked behavior paths still need repair.',
      'needsExecution' =>
        'Coverage inventory is complete for the dry run, but selected platform automation has not executed yet.',
      _ =>
        'Selected automation targets passed and declared coverage rows are covered or explicitly not applicable.',
    };
  }

  List<Map<String, Object?>> _repairQueue(
    List<WorkflowTargetResult> results,
    Map<String, Object?> coveragePolicy, {
    required String executionCommand,
    required bool dryRun,
  }) {
    final coverageQueue = _coverageRepairQueue(coveragePolicy);
    final scenarioCoverageQueue = _scenarioCoverageRepairQueue(coveragePolicy);
    final pathCoverageQueue = _pathCoverageRepairQueue(coveragePolicy);
    final scenarioEvidenceQueue = _scenarioEvidenceRepairQueue(coveragePolicy);
    final pageReadinessQueue = _pageReadinessRepairQueue(coveragePolicy);
    final testCoverageQueue = _testCoverageRepairQueue(coveragePolicy);
    final blockedQueue = _blockedCoverageQueue(coveragePolicy);
    final targetQueue = _targetRepairQueue(results);
    return [
      ...targetQueue,
      ...scenarioCoverageQueue,
      ...pathCoverageQueue,
      ...testCoverageQueue,
      ...scenarioEvidenceQueue,
      ...pageReadinessQueue,
      ...blockedQueue,
      ...coverageQueue,
      if (dryRun &&
          coverageQueue.isEmpty &&
          scenarioCoverageQueue.isEmpty &&
          pathCoverageQueue.isEmpty &&
          scenarioEvidenceQueue.isEmpty &&
          pageReadinessQueue.isEmpty &&
          testCoverageQueue.isEmpty &&
          targetQueue.isEmpty &&
          blockedQueue.isEmpty)
        _dryRunExecutionQueue(executionCommand),
    ];
  }

  Map<String, Object?> _dryRunExecutionQueue(String executionCommand) {
    return {
      'type': 'execution',
      'status': 'needsExecution',
      'repair':
          'Dry-run coverage is ready. Execute the selected automation command and keep the resulting JSON evidence before reporting ready.',
      'nextCommands': [
        {'command': executionCommand},
      ],
    };
  }

  List<Map<String, Object?>> _coverageRepairQueue(
    Map<String, Object?> coveragePolicy,
  ) {
    return [
      for (final gate in coveragePolicy['qualityGates'] as List<Object?>)
        if ((gate as Map<String, Object?>)['status'] != 'readyForReview')
          {
            'type': 'coverage',
            'gate': gate['id'],
            'status': gate['status'],
            'repair': gate['repair'],
            if (gate['items'] != null) 'items': gate['items'],
            if (gate['capabilities'] != null)
              'capabilities': gate['capabilities'],
            if (gate['missingCapabilities'] != null)
              'missingCapabilities': gate['missingCapabilities'],
            if (gate['permissions'] != null) 'permissions': gate['permissions'],
            if (gate['missingPermissions'] != null)
              'missingPermissions': gate['missingPermissions'],
            if (gate['baseline'] != null) 'baseline': gate['baseline'],
            if (gate['scenarios'] != null) 'scenarios': gate['scenarios'],
          },
    ];
  }

  List<Map<String, Object?>> _scenarioCoverageRepairQueue(
    Map<String, Object?> coveragePolicy,
  ) {
    Map<String, Object?>? capabilityGate;
    Map<String, Object?>? permissionGate;
    for (final gate in coveragePolicy['qualityGates'] as List<Object?>) {
      final gateJson = gate as Map<String, Object?>;
      switch (gateJson['id']) {
        case 'capability-inventory-coverage':
          capabilityGate = gateJson;
        case 'manifest-permission-coverage':
          permissionGate = gateJson;
      }
    }
    return [
      ..._capabilityCoverageRepairQueue(capabilityGate),
      ..._permissionCoverageRepairQueue(permissionGate),
    ];
  }

  List<Map<String, Object?>> _scenarioCandidates({
    String? platform,
    String? category,
    String? item,
  }) {
    final selectedPlatforms = platform == null ? platforms : [platform];
    final scope = _automationPathSlug(
      inventory.targetName ?? _pathBasename(inventory.rootPath),
    );
    final itemSlug = _automationPathSlug(item ?? category ?? 'coverage');
    return [
      for (final targetPlatform in selectedPlatforms)
        {
          'platform': targetPlatform,
          'path':
              '${inventory.rootPath}/.fluoh/scenarios/$scope/$targetPlatform-$itemSlug.md',
        },
    ];
  }

  String? _stringField(Map<String, Object?> value, String key) {
    final field = value[key];
    return field is String && field.isNotEmpty ? field : null;
  }

  List<Map<String, Object?>> _pathCoverageRepairQueue(
    Map<String, Object?> coveragePolicy,
  ) {
    Map<String, Object?>? pathGate;
    for (final gate in coveragePolicy['qualityGates'] as List<Object?>) {
      final gateJson = gate as Map<String, Object?>;
      if (gateJson['id'] == 'behavior-paths') {
        pathGate = gateJson;
        break;
      }
    }
    final items = pathGate?['items'];
    if (items is! List<Object?> || items.isEmpty) {
      return const [];
    }
    return [
      for (final item in items)
        if (item is Map<String, Object?>)
          _pathCoverageRepairItem(pathGate, item),
    ];
  }

  Map<String, Object?> _pathCoverageRepairItem(
    Map<String, Object?>? gate,
    Map<String, Object?> item,
  ) {
    final scenarioPaths = _objectList(item['scenarioPaths']);
    final scenarioCandidates = scenarioPaths.isEmpty
        ? _scenarioCandidates(
            category: _stringField(item, 'category'),
            item: _stringField(item, 'item'),
          )
        : [
            for (final path in scenarioPaths)
              if (path is String) {'path': path, 'mode': 'update'},
          ];
    final suggestedCoverage = _pathCoverageSuggestedRows(item);
    return {
      'type': 'pathCoverage',
      'gate': 'behavior-paths',
      'status': item['status'] ?? gate?['status'],
      'repair':
          item['repair'] ??
          'Add explicit coverage rows for both success and negative or error behavior paths.',
      'category': item['category'],
      'item': item['item'],
      if (item['paths'] != null) 'paths': item['paths'],
      if (item['statuses'] != null) 'statuses': item['statuses'],
      if (scenarioPaths.isNotEmpty) 'scenarioPaths': scenarioPaths,
      if (item['missingPath'] == true) 'missingPath': true,
      if (item['needsPositivePath'] == true) 'needsPositivePath': true,
      if (item['needsNegativeOrErrorPath'] == true)
        'needsNegativeOrErrorPath': true,
      'suggestedCoverage': suggestedCoverage,
      'scenarioCandidates': scenarioCandidates,
      'nextAction': {
        'kind': 'addScenarioCoverageRows',
        if (scenarioCandidates.length == 1 &&
            scenarioCandidates.single['path'] != null)
          'path': scenarioCandidates.single['path'],
        'scenarioCandidates': scenarioCandidates,
        'coverage': suggestedCoverage,
      },
    };
  }

  List<Object?> _objectList(Object? value) {
    return value is List<Object?> ? value : const [];
  }

  List<Map<String, Object?>> _pathCoverageSuggestedRows(
    Map<String, Object?> item,
  ) {
    final category = item['category'];
    final coverageItem = item['item'];
    if (category is! String || coverageItem is! String) {
      return const [];
    }
    final missingPath = item['missingPath'] == true;
    final rows = <Map<String, Object?>>[];
    if (missingPath || item['needsPositivePath'] == true) {
      rows.add({
        'category': category,
        'item': coverageItem,
        'path': 'success',
        'status': 'covered',
      });
    }
    if (missingPath || item['needsNegativeOrErrorPath'] == true) {
      rows.add({
        'category': category,
        'item': coverageItem,
        'path': 'error',
        'status': 'covered',
      });
    }
    return rows;
  }

  List<Map<String, Object?>> _scenarioEvidenceRepairQueue(
    Map<String, Object?> coveragePolicy,
  ) {
    Map<String, Object?>? evidenceGate;
    for (final gate in coveragePolicy['qualityGates'] as List<Object?>) {
      final gateJson = gate as Map<String, Object?>;
      if (gateJson['id'] == 'scenario-evidence-assertions') {
        evidenceGate = gateJson;
        break;
      }
    }
    final scenarios = evidenceGate?['scenarios'];
    if (scenarios is! List<Object?> || scenarios.isEmpty) {
      return const [];
    }
    return [
      for (final scenario in scenarios)
        if (scenario is Map<String, Object?>)
          {
            'type': 'scenarioEvidence',
            'gate': 'scenario-evidence-assertions',
            'status': scenario['status'] ?? evidenceGate?['status'],
            'repair':
                scenario['repair'] ??
                'Add functional evidence after the interaction flow.',
            'platform': scenario['platform'],
            'scenario': scenario['scenario'],
            'path': scenario['path'],
            if (scenario['suggestedActions'] != null)
              'suggestedActions': scenario['suggestedActions'],
            if (scenario['coverageEvidenceBindings'] != null)
              'coverageEvidenceBindings': scenario['coverageEvidenceBindings'],
            if (scenario['suggestedScenarioPatch'] != null)
              'suggestedScenarioPatch': scenario['suggestedScenarioPatch'],
            'nextAction': {
              'kind': 'addScenarioVerificationAction',
              'path': scenario['path'],
              if (scenario['suggestedActions'] != null)
                'actions': scenario['suggestedActions'],
              if (scenario['suggestedScenarioPatch'] != null)
                'scenarioPatch': scenario['suggestedScenarioPatch'],
            },
          },
    ];
  }

  List<Map<String, Object?>> _pageReadinessRepairQueue(
    Map<String, Object?> coveragePolicy,
  ) {
    Map<String, Object?>? readinessGate;
    for (final gate in coveragePolicy['qualityGates'] as List<Object?>) {
      final gateJson = gate as Map<String, Object?>;
      if (gateJson['id'] == 'page-readiness') {
        readinessGate = gateJson;
        break;
      }
    }
    final scenarios = readinessGate?['scenarios'];
    if (scenarios is! List<Object?> || scenarios.isEmpty) {
      return const [];
    }
    return [
      for (final scenario in scenarios)
        if (scenario is Map<String, Object?>)
          {
            'type': 'pageReadiness',
            'gate': 'page-readiness',
            'status': scenario['status'] ?? readinessGate?['status'],
            'repair':
                scenario['repair'] ??
                'Add a page readiness assertion after launch.',
            'platform': scenario['platform'],
            'scenario': scenario['scenario'],
            'path': scenario['path'],
            if (scenario['suggestedScenarioPatch'] != null)
              'suggestedScenarioPatch': scenario['suggestedScenarioPatch'],
            'nextAction': {
              'kind': 'addPageReadinessAssertion',
              'path': scenario['path'],
              if (scenario['suggestedScenarioPatch'] != null)
                'scenarioPatch': scenario['suggestedScenarioPatch'],
            },
          },
    ];
  }

  List<Map<String, Object?>> _capabilityCoverageRepairQueue(
    Map<String, Object?>? gate,
  ) {
    final missingCapabilities = gate?['missingCapabilities'];
    if (missingCapabilities is! List<Object?> || missingCapabilities.isEmpty) {
      return const [];
    }
    return [
      for (final missing in missingCapabilities)
        if (missing is Map<String, Object?>)
          _capabilityCoverageRepairItem(gate, missing),
    ];
  }

  Map<String, Object?> _capabilityCoverageRepairItem(
    Map<String, Object?>? gate,
    Map<String, Object?> missing,
  ) {
    final scenarioCandidates = _scenarioCandidates(
      category: _stringField(missing, 'category'),
      item: _stringField(missing, 'item'),
    );
    return {
      'type': 'scenarioCoverage',
      'gate': 'capability-inventory-coverage',
      'status': missing['status'] ?? gate?['status'],
      'repair':
          missing['repair'] ??
          'Add scenario coverage rows or integration-test evidence for this package capability.',
      'category': missing['category'],
      'item': missing['item'],
      if (missing['source'] != null) 'source': missing['source'],
      if (missing['inventoryPath'] != null)
        'inventoryPath': missing['inventoryPath'],
      if (missing['suggestedCoverage'] != null)
        'suggestedCoverage': missing['suggestedCoverage'],
      'scenarioCandidates': scenarioCandidates,
      'nextAction': {
        'kind': 'addScenarioCoverageRows',
        'scenarioCandidates': scenarioCandidates,
        if (missing['inventoryPath'] != null)
          'source': missing['inventoryPath'],
        if (missing['suggestedCoverage'] != null)
          'coverage': missing['suggestedCoverage'],
      },
    };
  }

  List<Map<String, Object?>> _permissionCoverageRepairQueue(
    Map<String, Object?>? gate,
  ) {
    final missingPermissions = gate?['missingPermissions'];
    if (missingPermissions is! List<Object?> || missingPermissions.isEmpty) {
      return const [];
    }
    return [
      for (final missing in missingPermissions)
        if (missing is Map<String, Object?>)
          _permissionCoverageRepairItem(gate, missing),
    ];
  }

  Map<String, Object?> _permissionCoverageRepairItem(
    Map<String, Object?>? gate,
    Map<String, Object?> missing,
  ) {
    final scenarioCandidates = _scenarioCandidates(
      platform: _stringField(missing, 'platform'),
      category: 'permission',
      item: _stringField(missing, 'coverageItem'),
    );
    return {
      'type': 'permissionCoverage',
      'gate': 'manifest-permission-coverage',
      'status': missing['status'] ?? gate?['status'],
      'repair':
          missing['repair'] ??
          'Add selected-platform scenario rows for this manifest permission, including grant and denied/error paths.',
      'platform': missing['platform'],
      'permission': missing['permission'],
      'coverageItem': missing['coverageItem'],
      if (missing['manifestPath'] != null)
        'manifestPath': missing['manifestPath'],
      if (missing['suggestedCoverage'] != null)
        'suggestedCoverage': missing['suggestedCoverage'],
      'scenarioCandidates': scenarioCandidates,
      'nextAction': {
        'kind': 'addScenarioCoverageRows',
        'platform': missing['platform'],
        if (scenarioCandidates.length == 1 &&
            scenarioCandidates.single['path'] != null)
          'path': scenarioCandidates.single['path'],
        'scenarioCandidates': scenarioCandidates,
        if (missing['manifestPath'] != null) 'source': missing['manifestPath'],
        if (missing['suggestedCoverage'] != null)
          'coverage': missing['suggestedCoverage'],
      },
    };
  }

  List<Map<String, Object?>> _testCoverageRepairQueue(
    Map<String, Object?> coveragePolicy,
  ) {
    Map<String, Object?>? testGate;
    for (final gate in coveragePolicy['qualityGates'] as List<Object?>) {
      final gateJson = gate as Map<String, Object?>;
      if (gateJson['id'] == 'existing-test-baseline') {
        testGate = gateJson;
        break;
      }
    }
    final baseline = testGate?['baseline'];
    if (baseline is! Map<String, Object?>) {
      return const [];
    }
    final missingPackageTests = baseline['missingPackageTests'];
    final weakPackageTests = baseline['weakPackageTests'];
    return [
      if (missingPackageTests is List<Object?>)
        for (final missing in missingPackageTests)
          if (missing is Map<String, Object?>)
            {
              'type': 'testCoverage',
              'gate': 'existing-test-baseline',
              'status': baseline['status'],
              'repair':
                  'Create or expand the package test for this public library before relying on example smoke tests or final report prose.',
              'libraryPath': missing['libraryPath'],
              'expectedTestPath': missing['expectedTestPath'],
              if (missing['acceptedTestPaths'] != null)
                'acceptedTestPaths': missing['acceptedTestPaths'],
              if (missing['testCommand'] != null)
                'testCommand': missing['testCommand'],
              if (missing['acceptedTestCommands'] != null)
                'acceptedTestCommands': missing['acceptedTestCommands'],
              'nextAction': {
                'kind': 'createOrExpandPackageTest',
                'source': missing['libraryPath'],
                'path': missing['expectedTestPath'],
                if (missing['testCommand'] != null)
                  'testCommand': missing['testCommand'],
                if (missing['acceptedTestCommands'] != null)
                  'acceptedTestCommands': missing['acceptedTestCommands'],
              },
            },
      if (weakPackageTests is List<Object?>)
        for (final weak in weakPackageTests)
          if (weak is Map<String, Object?>)
            {
              'type': 'testCoverage',
              'gate': 'existing-test-baseline',
              'status': baseline['status'],
              'repair':
                  'Expand the existing package test so it exercises at least one public declaration from the matching library file.',
              'libraryPath': weak['libraryPath'],
              'testPath': weak['testPath'],
              if (weak['publicDeclarations'] != null)
                'publicDeclarations': weak['publicDeclarations'],
              if (weak['exercisedDeclarations'] != null)
                'exercisedDeclarations': weak['exercisedDeclarations'],
              if (weak['missingDeclarations'] != null)
                'missingDeclarations': weak['missingDeclarations'],
              if (weak['testCommand'] != null)
                'testCommand': weak['testCommand'],
              'nextAction': {
                'kind': 'expandPackageTest',
                'source': weak['libraryPath'],
                'path': weak['testPath'],
                if (weak['missingDeclarations'] != null)
                  'publicDeclarations': weak['missingDeclarations'],
                if (weak['missingDeclarations'] != null)
                  'missingDeclarations': weak['missingDeclarations'],
                if (weak['testCommand'] != null)
                  'testCommand': weak['testCommand'],
              },
            },
    ];
  }

  List<Map<String, Object?>> _targetRepairQueue(
    List<WorkflowTargetResult> results,
  ) {
    final queue = <Map<String, Object?>>[];
    for (final target in results) {
      if (target.passed) {
        continue;
      }
      var addedDiagnostic = false;
      for (final step in target.steps) {
        for (final diagnostic in step.diagnostics) {
          addedDiagnostic = true;
          final repairHints = diagnostic.details['repairHints'];
          queue.add({
            'type': 'diagnostic',
            'target': {'kind': target.targetKind, 'name': target.targetName},
            'step': step.name,
            'code': diagnostic.code,
            'message': diagnostic.message,
            if (diagnostic.nextCommand != null)
              'nextCommand': diagnostic.nextCommand,
            ...(repairHints == null
                ? const <String, Object?>{}
                : {'repairHints': repairHints}),
          });
        }
      }
      if (!addedDiagnostic) {
        queue.add({
          'type': 'target',
          'target': {'kind': target.targetKind, 'name': target.targetName},
          if (target.nextCommand != null) 'nextCommand': target.nextCommand,
        });
      }
    }
    return queue;
  }

  List<Map<String, Object?>> _blockedCoverageQueue(
    Map<String, Object?> coveragePolicy,
  ) {
    final queue = <Map<String, Object?>>[];
    for (final scenario
        in coveragePolicy['scenarioCoverage'] as List<Object?>) {
      final scenarioJson = scenario as Map<String, Object?>;
      for (final item in scenarioJson['items'] as List<Object?>) {
        final coverage = item as Map<String, Object?>;
        if (coverage['status'] == 'blocked') {
          queue.add({
            'type': 'coverageBlocked',
            'platform': scenarioJson['platform'],
            'scenario': scenarioJson['scenario'],
            'path': scenarioJson['path'],
            'coverage': coverage,
          });
        }
      }
    }
    return queue;
  }
}

bool _isAutomationCoverageGapStatus(String status) {
  return status == 'needsInventory' ||
      status == 'needsCapabilityInventory' ||
      status == 'needsCoverageRows' ||
      status == 'needsRepair' ||
      status == 'needsCapabilityCoverageRows' ||
      status == 'needsPathCoverageReview' ||
      status == 'needsTests' ||
      status == 'needsPackageTests' ||
      status == 'needsTestCoverageReview' ||
      status == 'needsPermissionCoverageRows' ||
      status == 'needsBlockedCoverageRepair' ||
      status == 'needsEvidenceAssertions' ||
      status == 'needsFunctionalEvidence' ||
      status == 'needsPageReadinessEvidence';
}
