part of 'workflow_commands.dart';

class _AutomationCoveragePolicy {
  const _AutomationCoveragePolicy({
    required this.scenarios,
    required this.inventory,
    required this.platforms,
  });

  final List<AutomationScenario> scenarios;
  final _AutomationInventory inventory;
  final List<String> platforms;

  Map<String, Object?> toJson() {
    final pathCoverage = _coveragePathCoverage();
    final pathCoverageWarnings = [
      for (final group in pathCoverage)
        if (group.needsReview) group.toJson(),
    ];
    final manifestPermissionCoverage = _manifestPermissionCoverage();
    final manifestPermissionWarnings = [
      for (final requirement in manifestPermissionCoverage)
        if (requirement.needsReview) requirement.toJson(),
    ];
    final capabilityCoverage = _capabilityCoverage();
    final capabilityCoverageWarnings = [
      for (final requirement in capabilityCoverage)
        if (requirement.needsReview) requirement.toJson(),
    ];
    final scenarioEvidence = _scenarioEvidence();
    final scenarioEvidenceWarnings = [
      for (final evidence in scenarioEvidence)
        if (evidence.needsReview) evidence.toJson(),
    ];
    final pageReadinessWarnings = [
      for (final evidence in scenarioEvidence)
        if (evidence.needsPageReadiness) evidence.pageReadinessJson(),
    ];
    final coverageSummary = _coverageSummary(
      pathGroupCount: pathCoverage.length,
      pathCoverageWarningCount: pathCoverageWarnings.length,
      capabilityCount: capabilityCoverage.length,
      capabilityCoverageWarningCount: capabilityCoverageWarnings.length,
      manifestPermissionCount: manifestPermissionCoverage.length,
      manifestPermissionWarningCount: manifestPermissionWarnings.length,
      scenarioEvidenceWarningCount: scenarioEvidenceWarnings.length,
      pageReadinessWarningCount: pageReadinessWarnings.length,
    );
    final qualityGates = _qualityGates(
      coverageSummary,
      pathCoverageWarnings,
      capabilityCoverageWarnings,
      manifestPermissionWarnings,
      scenarioEvidenceWarnings,
      pageReadinessWarnings,
    );
    final status = _coveragePolicyStatus(coverageSummary, qualityGates);
    return {
      'schema': 1,
      'status': status,
      'readyForAutomation': status == 'readyForExecution',
      'readyRule':
          'A package adaptation is ready only after every applicable package capability is covered by automation, integration_test, or an explicit notApplicable row. Blocked rows require repair before release readiness.',
      'minimumGates': const [
        {
          'id': 'platform-matrix',
          'required': true,
          'rule':
              'Run every selected mobile platform and keep workflow JSON plus trace or session evidence.',
        },
        {
          'id': 'package-api-inventory',
          'required': true,
          'rule':
              'Inventory public package APIs and example entry points before declaring coverage complete.',
        },
        {
          'id': 'interaction-matrix',
          'required': true,
          'rule':
              'For each applicable interaction class, provide a scenario, integration_test, or manual-assisted tool-readable evidence. Use notApplicable only for behavior that truly does not exist on the platform.',
        },
        {
          'id': 'permission-matrix',
          'requiredWhen': 'package declares or requests runtime permissions',
          'rule':
              'Cover every declared or requestable permission on every supported platform; include grant and deny/error paths when package behavior differs.',
        },
        {
          'id': 'regression-matrix',
          'required': true,
          'rule':
              'Run existing-platform regression checks when local Android, iOS, web, or desktop toolchains are available.',
        },
      ],
      'scenarioCoverage': [
        for (final scenario in scenarios)
          {
            'platform': scenario.platform,
            'scenario': scenario.name,
            'path': scenario.path.path,
            'items': scenario.coverage.map((item) => item.toJson()).toList(),
            if (scenario.coverage.isEmpty)
              'coverageWarning':
                  'Scenario has no coverage metadata. Add coverage entries for every capability item it verifies.',
          },
      ],
      'inventory': inventory.toJson(),
      'coverageSummary': coverageSummary,
      'qualityGateSummary': _qualityGateSummary(qualityGates),
      'scenarioSuggestions': _scenarioSuggestions(),
      'pathCoverage': pathCoverage.map((group) => group.toJson()).toList(),
      'capabilityCoverage': capabilityCoverage
          .map((requirement) => requirement.toJson())
          .toList(),
      'manifestPermissionCoverage': manifestPermissionCoverage
          .map((requirement) => requirement.toJson())
          .toList(),
      'scenarioEvidence': scenarioEvidence
          .map((evidence) => evidence.toJson())
          .toList(),
      'pageReadiness': [
        for (final evidence in scenarioEvidence) evidence.pageReadinessJson(),
      ],
      'qualityGates': qualityGates,
      'repairLoop': const {
        'goal':
            'Repeat diagnose, minimal edit, rerun, and coverage update until every applicable capability row is covered or explicitly notApplicable.',
        'steps': [
          {
            'id': 'read-json-diagnostics',
            'action':
                'Parse command JSON, step diagnostics, repairHints, nextCommand, trace paths, session files, and log tails before editing.',
          },
          {
            'id': 'patch-smallest-surface',
            'action':
                'Make the smallest package, example, scenario, or test change needed to address the current failed or missing evidence row.',
          },
          {
            'id': 'rerun-same-command',
            'action':
                'Rerun the exact nextCommand or scenario command that failed before broadening the test scope.',
          },
          {
            'id': 'refresh-coverage',
            'action':
                'Update scenario coverage metadata and the report so missing and notApplicable rows stay explicit; blocked rows stay in the repair queue.',
          },
        ],
        'stopWhen': [
          'all applicable capability rows have tool-readable evidence',
          'format, analysis, tests, and selected platform automation pass',
          'remaining notApplicable rows are platform-inapplicable behavior with evidence',
        ],
      },
      'interactionClasses': const [
        'permissions',
        'fileOrMediaPickers',
        'cameraOrMicrophone',
        'locationAndSensors',
        'maps',
        'mediaPlaybackOrRecording',
        'deepLinksAndExternalCallbacks',
        'backgroundOrLifecycle',
        'multiStepForms',
        'negativeOrErrorPaths',
      ],
      'capabilityCoverageGuidance':
          'Create coverage rows from the package capability inventory. For each category/item, use explicit path values such as grant, deny, success, failure, cancel, or error. Use notApplicable only when the behavior does not exist on the selected platform; blocked rows require repair.',
    };
  }

  List<Map<String, Object?>> _scenarioSuggestions({
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

  Map<String, Object?> _coverageSummary({
    required int pathGroupCount,
    required int pathCoverageWarningCount,
    required int capabilityCount,
    required int capabilityCoverageWarningCount,
    required int manifestPermissionCount,
    required int manifestPermissionWarningCount,
    required int scenarioEvidenceWarningCount,
    required int pageReadinessWarningCount,
  }) {
    final statusCounts = <String, int>{
      'covered': 0,
      'notApplicable': 0,
      'blocked': 0,
    };
    final categoryCounts = <String, int>{};
    final scenariosWithoutCoverage = <String>[];
    var itemCount = 0;
    for (final scenario in scenarios) {
      if (scenario.coverage.isEmpty) {
        scenariosWithoutCoverage.add(scenario.path.path);
      }
      for (final item in scenario.coverage) {
        itemCount += 1;
        statusCounts[item.status] = (statusCounts[item.status] ?? 0) + 1;
        categoryCounts[item.category] =
            (categoryCounts[item.category] ?? 0) + 1;
      }
    }
    return {
      'scenarioCount': scenarios.length,
      'itemCount': itemCount,
      'statusCounts': statusCounts,
      'categoryCounts': categoryCounts,
      'scenariosWithoutCoverage': scenariosWithoutCoverage,
      'pathGroupCount': pathGroupCount,
      'pathCoverageWarningCount': pathCoverageWarningCount,
      'capabilityCount': capabilityCount,
      'capabilityCoverageWarningCount': capabilityCoverageWarningCount,
      'manifestPermissionCount': manifestPermissionCount,
      'manifestPermissionWarningCount': manifestPermissionWarningCount,
      'scenarioEvidenceWarningCount': scenarioEvidenceWarningCount,
      'pageReadinessWarningCount': pageReadinessWarningCount,
    };
  }

  String _coveragePolicyStatus(
    Map<String, Object?> coverageSummary,
    List<Map<String, Object?>> qualityGates,
  ) {
    final scenarioCount = coverageSummary['scenarioCount'] as int? ?? 0;
    if (scenarioCount == 0) {
      return 'needsInteractionInventory';
    }
    final hasCoverageGap = qualityGates.any(
      (gate) => _isAutomationCoverageGapStatus(gate['status'] as String? ?? ''),
    );
    if (hasCoverageGap) {
      return 'needsAgentCoverageReview';
    }
    final statusCounts =
        coverageSummary['statusCounts'] as Map<String, Object?>? ??
        const <String, Object?>{};
    final blockedCoverage = statusCounts['blocked'] as int? ?? 0;
    if (blockedCoverage > 0) {
      return 'needsAgentCoverageReview';
    }
    return 'readyForExecution';
  }

  Map<String, Object?> _qualityGateSummary(
    List<Map<String, Object?>> qualityGates,
  ) {
    final statusCounts = <String, int>{};
    final notReady = <Map<String, Object?>>[];
    for (final gate in qualityGates) {
      final status = gate['status'] as String? ?? 'unknown';
      statusCounts[status] = (statusCounts[status] ?? 0) + 1;
      if (status != 'readyForReview') {
        notReady.add({
          if (gate['id'] != null) 'id': gate['id'],
          'status': status,
        });
      }
    }
    return {
      'total': qualityGates.length,
      'ready': statusCounts['readyForReview'] ?? 0,
      'notReady': notReady,
      'statusCounts': statusCounts,
    };
  }

  List<_CoveragePathGroup> _coveragePathCoverage() {
    final groups = <String, _CoveragePathGroup>{};
    for (final scenario in scenarios) {
      for (final item in scenario.coverage) {
        final key = '${item.category}\u0000${item.item}';
        final group = groups.putIfAbsent(
          key,
          () => _CoveragePathGroup(category: item.category, item: item.item),
        );
        group.add(item, scenario: scenario);
      }
    }
    return groups.values.toList()..sort((a, b) {
      final categoryOrder = a.category.compareTo(b.category);
      if (categoryOrder != 0) {
        return categoryOrder;
      }
      return a.item.compareTo(b.item);
    });
  }

  List<_CapabilityCoverage> _capabilityCoverage() {
    final requirements = <_CapabilityCoverage>[];
    for (final capability in inventory.capabilities) {
      final requirement = _CapabilityCoverage(capability: capability);
      for (final scenario in scenarios) {
        for (final item in scenario.coverage) {
          if (_coverageMatchesCapability(item, capability)) {
            requirement.add(item, scenario: scenario);
          }
        }
      }
      requirements.add(requirement);
    }
    requirements.sort((a, b) {
      final categoryOrder = a.capability.category.compareTo(
        b.capability.category,
      );
      if (categoryOrder != 0) {
        return categoryOrder;
      }
      final itemOrder = a.capability.coverageItem.compareTo(
        b.capability.coverageItem,
      );
      if (itemOrder != 0) {
        return itemOrder;
      }
      return a.capability.path.compareTo(b.capability.path);
    });
    return requirements;
  }

  List<_ManifestPermissionCoverage> _manifestPermissionCoverage() {
    final requirements = <_ManifestPermissionCoverage>[];
    for (final permission in inventory.manifestPermissions) {
      if (!platforms.contains(permission.platform)) {
        continue;
      }
      final requirement = _ManifestPermissionCoverage(permission: permission);
      for (final scenario in scenarios) {
        if (scenario.platform != permission.platform) {
          continue;
        }
        for (final item in scenario.coverage) {
          if (item.category.toLowerCase() != 'permission') {
            continue;
          }
          if (_permissionCoverageItem(scenario.platform, item.item) !=
              permission.coverageItem) {
            continue;
          }
          requirement.add(item, scenario: scenario);
        }
      }
      requirements.add(requirement);
    }
    requirements.sort((a, b) {
      final platformOrder = a.permission.platform.compareTo(
        b.permission.platform,
      );
      if (platformOrder != 0) {
        return platformOrder;
      }
      final itemOrder = a.permission.coverageItem.compareTo(
        b.permission.coverageItem,
      );
      if (itemOrder != 0) {
        return itemOrder;
      }
      return a.permission.name.compareTo(b.permission.name);
    });
    return requirements;
  }

  List<_ScenarioEvidence> _scenarioEvidence() {
    return [
      for (final scenario in scenarios) _ScenarioEvidence(scenario: scenario),
    ];
  }

  List<Map<String, Object?>> _qualityGates(
    Map<String, Object?> summary,
    List<Map<String, Object?>> pathCoverageWarnings,
    List<Map<String, Object?>> capabilityCoverageWarnings,
    List<Map<String, Object?>> manifestPermissionWarnings,
    List<Map<String, Object?>> scenarioEvidenceWarnings,
    List<Map<String, Object?>> pageReadinessWarnings,
  ) {
    final scenarioCount = summary['scenarioCount'] as int;
    final itemCount = summary['itemCount'] as int;
    final scenariosWithoutCoverage =
        (summary['scenariosWithoutCoverage'] as List<String>);
    final capabilityCount = summary['capabilityCount'] as int;
    final manifestPermissionCount = summary['manifestPermissionCount'] as int;
    final statusCounts =
        summary['statusCounts'] as Map<String, Object?>? ??
        const <String, Object?>{};
    final blockedCoverage = statusCounts['blocked'] as int? ?? 0;
    return [
      {
        'id': 'coverage-inventory',
        'status': scenarioCount == 0 ? 'needsInventory' : 'readyForReview',
        'repair':
            'Inventory package APIs, example entry points, platform interfaces, permissions, and feature classes before declaring readiness.',
      },
      {
        'id': 'coverage-metadata',
        'status': scenarioCount == 0
            ? 'needsInventory'
            : scenariosWithoutCoverage.isEmpty
            ? 'readyForReview'
            : 'needsRepair',
        'repair':
            'Add coverage metadata to every scenario, or mark truly inapplicable capability rows notApplicable with evidence.',
      },
      {
        'id': 'coverage-items',
        'status': itemCount == 0 ? 'needsCoverageRows' : 'readyForReview',
        'repair':
            'Create one coverage row for every applicable capability item and behavior path.',
      },
      {
        'id': 'capability-inventory-coverage',
        'status': inventory.status == 'unresolved'
            ? 'needsInventory'
            : capabilityCount == 0
            ? 'needsCapabilityInventory'
            : capabilityCoverageWarnings.isEmpty
            ? 'readyForReview'
            : 'needsCapabilityCoverageRows',
        'repair':
            'For every discovered public API, platform call, or example entry point, add matching scenario coverage rows, integration-test evidence, or explicit notApplicable rows for platform-inapplicable behavior.',
        if (capabilityCount > 0)
          'capabilities': inventory.capabilities
              .map((capability) => capability.toJson())
              .toList(),
        if (capabilityCoverageWarnings.isNotEmpty)
          'missingCapabilities': capabilityCoverageWarnings,
      },
      {
        'id': 'blocked-coverage',
        'status': scenarioCount == 0
            ? 'needsInventory'
            : blockedCoverage > 0
            ? 'needsBlockedCoverageRepair'
            : 'readyForReview',
        'repair':
            'Replace blocked coverage rows by fixing the package, repairing the demo, or adding full automation evidence. Use notApplicable only when the behavior does not exist on this platform.',
        if (blockedCoverage > 0) 'blockedCoverageCount': blockedCoverage,
      },
      {
        'id': 'scenario-evidence-assertions',
        'status': scenarioCount == 0
            ? 'needsInventory'
            : itemCount == 0
            ? 'needsCoverageRows'
            : scenarioEvidenceWarnings.isEmpty
            ? 'readyForReview'
            : 'needsFunctionalEvidence',
        'repair':
            'Every scenario with covered rows must include functional evidence after the interaction flow. assertSession, launchApp, wait, and screenshots are launch or visual sanity evidence only.',
        if (scenarioEvidenceWarnings.isNotEmpty)
          'scenarios': scenarioEvidenceWarnings,
      },
      {
        'id': 'page-readiness',
        'status': scenarioCount == 0
            ? 'needsInventory'
            : pageReadinessWarnings.isEmpty
            ? 'readyForReview'
            : 'needsPageReadinessEvidence',
        'repair':
            'Every covered mobile scenario with launch, wait, or screenshot evidence must assert the post-launch functional page state with assertText, waitText, or assertLog.',
        if (pageReadinessWarnings.isNotEmpty)
          'scenarios': pageReadinessWarnings,
      },
      {
        'id': 'existing-test-baseline',
        'status': inventory.status == 'unresolved'
            ? 'needsInventory'
            : inventory.tests.baselineStatus,
        'repair':
            'Inspect existing test and integration_test coverage, then add or expand unit, widget, integration, or scenario evidence before marking the package ready.',
        if (inventory.status != 'unresolved')
          'baseline': inventory.tests.coverageBaseline,
      },
      {
        'id': 'manifest-permission-coverage',
        'status': inventory.status == 'unresolved'
            ? 'needsInventory'
            : manifestPermissionWarnings.isNotEmpty
            ? 'needsPermissionCoverageRows'
            : 'readyForReview',
        'repair':
            'For every runtime permission found in selected Android, iOS, or OHOS manifests, add scenario coverage rows for grant and denied/error behavior paths, or mark rows notApplicable only when the permission has no runtime behavior on that platform.',
        if (manifestPermissionCount > 0)
          'permissions': inventory.manifestPermissions
              .where((permission) => platforms.contains(permission.platform))
              .map((permission) => permission.toJson())
              .toList(),
        if (manifestPermissionWarnings.isNotEmpty)
          'missingPermissions': manifestPermissionWarnings,
      },
      {
        'id': 'behavior-paths',
        'status': scenarioCount == 0
            ? 'needsInventory'
            : itemCount == 0
            ? 'needsCoverageRows'
            : pathCoverageWarnings.isEmpty
            ? 'readyForReview'
            : 'needsPathCoverageReview',
        'repair':
            'For each category/item, declare both a successful path and a denied, cancelled, failure, or error path. Use notApplicable only when a path does not exist on that platform; blocked rows require repair.',
        if (pathCoverageWarnings.isNotEmpty) 'items': pathCoverageWarnings,
      },
    ];
  }
}
