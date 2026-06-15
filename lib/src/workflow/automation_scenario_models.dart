part of 'automation_scenario.dart';

/// Returns automation driver metadata for [platform].
Map<String, Object?> automationScenarioPlatformDriverMetadata(String platform) {
  return _AutomationScenarioPlatformDrivers.metadataForPlatform(platform);
}

/// Parsed AI automation scenario.
class AutomationScenario {
  /// Creates an automation scenario.
  const AutomationScenario({
    required this.path,
    required this.name,
    required this.platform,
    required this.steps,
    this.coverage = const [],
  });

  /// Scenario file path.
  final File path;

  /// Scenario display name.
  final String name;

  /// Target platform.
  final String platform;

  /// Ordered scenario actions.
  final List<AutomationScenarioAction> steps;

  /// Functional coverage items claimed by this scenario.
  final List<AutomationScenarioCoverageItem> coverage;

  /// Converts the scenario metadata to JSON.
  Map<String, Object?> toJson() {
    return {
      'path': path.path,
      'name': name,
      'platform': platform,
      if (coverage.isNotEmpty)
        'coverage': coverage.map((item) => item.toJson()).toList(),
      'steps': steps.map((step) => step.toJson()).toList(),
    };
  }
}

/// Functional coverage item represented by an automation scenario.
class AutomationScenarioCoverageItem {
  /// Creates an automation scenario coverage item.
  const AutomationScenarioCoverageItem({
    required this.category,
    required this.item,
    this.path,
    this.status = 'covered',
    this.note,
    this.interactionStep,
    this.assertionStep,
    this.evidenceSteps = const [],
  });

  /// Capability category, such as `permission`, `picker`, or `lifecycle`.
  final String category;

  /// Concrete item inside the category, such as `camera` or `photos`.
  final String item;

  /// Functional path, such as `grant`, `deny`, or `error`.
  final String? path;

  /// Coverage status: `covered`, `notApplicable`, or `blocked`.
  final String status;

  /// Optional human-readable note for reports.
  final String? note;

  /// Step index that performs the interaction for this coverage row.
  final int? interactionStep;

  /// Step index that asserts the functional result for this coverage row.
  final int? assertionStep;

  /// Step indexes that provide additional evidence for this coverage row.
  final List<int> evidenceSteps;

  /// Converts the coverage item to JSON.
  Map<String, Object?> toJson() {
    return {
      'category': category,
      'item': item,
      if (path != null) 'path': path,
      'status': status,
      if (note != null) 'note': note,
      if (interactionStep != null) 'interactionStep': interactionStep,
      if (assertionStep != null) 'assertionStep': assertionStep,
      if (evidenceSteps.isNotEmpty) 'evidenceSteps': evidenceSteps,
    };
  }
}

/// Parsed scenario action.
class AutomationScenarioAction {
  /// Creates an automation action.
  const AutomationScenarioAction({
    required this.action,
    required this.index,
    this.text,
    this.labels = const [],
    this.match = 'contains',
    this.x,
    this.y,
    this.endX,
    this.endY,
    this.durationMilliseconds,
    this.value,
    this.keyCode,
    this.permission,
    this.bundleId,
    this.abilityName,
    this.outputPath,
    this.timeout = const Duration(seconds: 5),
    this.optional = false,
    this.repairHints = const [],
  });

  /// Action name.
  final String action;

  /// 1-based index in the scenario.
  final int index;

  /// Text or selector label.
  final String? text;

  /// Alternative labels for text-based actions.
  final List<String> labels;

  /// Matching mode: `contains`, `exact`, or `regex`.
  final String match;

  /// X coordinate for coordinate taps.
  final int? x;

  /// Y coordinate for coordinate taps.
  final int? y;

  /// End X coordinate for swipe or drag actions.
  final int? endX;

  /// End Y coordinate for swipe or drag actions.
  final int? endY;

  /// Gesture duration for swipe or drag actions.
  final int? durationMilliseconds;

  /// Text value or expected value.
  final String? value;

  /// Key code for press actions.
  final String? keyCode;

  /// Platform permission identifier.
  final String? permission;

  /// App bundle/package id for platform permission APIs.
  final String? bundleId;

  /// OHOS ability name for launch actions.
  final String? abilityName;

  /// Local file path for actions that capture artifacts.
  final String? outputPath;

  /// Polling timeout for wait/assert actions.
  final Duration timeout;

  /// Whether failures should be recorded as skipped.
  final bool optional;

  /// Agent repair hints to return when the action fails.
  final List<String> repairHints;

  /// Converts the action to JSON.
  Map<String, Object?> toJson() {
    return {
      'action': action,
      if (text != null) 'text': text,
      if (labels.isNotEmpty) 'labels': labels,
      if (match != 'contains') 'match': match,
      if (x != null) 'x': x,
      if (y != null) 'y': y,
      if (endX != null) 'endX': endX,
      if (endY != null) 'endY': endY,
      if (durationMilliseconds != null)
        'durationMilliseconds': durationMilliseconds,
      if (value != null) 'value': value,
      if (keyCode != null) 'keyCode': keyCode,
      if (permission != null) 'permission': permission,
      if (bundleId != null) 'bundleId': bundleId,
      if (abilityName != null) 'abilityName': abilityName,
      if (outputPath != null) 'outputPath': outputPath,
      if (timeout != const Duration(seconds: 5))
        'timeoutSeconds': timeout.inSeconds,
      if (optional) 'optional': true,
      if (repairHints.isNotEmpty) 'repairHints': repairHints,
    };
  }
}

/// Result of executing one scenario against one workflow target.
class AutomationScenarioRunResult {
  /// Creates a scenario run result.
  const AutomationScenarioRunResult({
    required this.scenario,
    required this.status,
    required this.exitCode,
    required this.actions,
    this.reason,
    this.diagnostic,
  });

  /// Scenario metadata.
  final AutomationScenario scenario;

  /// Scenario status: `passed`, `failed`, or `skipped`.
  final String status;

  /// Exit code contributed by this scenario.
  final int exitCode;

  /// Action results.
  final List<AutomationScenarioActionResult> actions;

  /// Failure or skip reason.
  final String? reason;

  /// Structured diagnostic when failed.
  final WorkflowDiagnostic? diagnostic;

  /// Converts the run result to JSON.
  Map<String, Object?> toJson() {
    return {
      'scenario': scenario.toJson(),
      'status': status,
      'exitCode': exitCode,
      if (reason != null) 'reason': reason,
      'actions': actions.map((action) => action.toJson()).toList(),
      if (diagnostic != null) 'diagnostic': diagnostic!.toJson(),
    };
  }
}

/// Result for one scenario action.
class AutomationScenarioActionResult {
  /// Creates one action result.
  const AutomationScenarioActionResult({
    required this.index,
    required this.action,
    required this.status,
    this.command,
    this.reason,
    this.details = const {},
    this.repairHints = const [],
  });

  /// 1-based action index.
  final int index;

  /// Action name.
  final String action;

  /// Action status.
  final String status;

  /// Command that was run.
  final String? command;

  /// Failure or skip reason.
  final String? reason;

  /// Structured action details.
  final Map<String, Object?> details;

  /// Repair hints for agents.
  final List<String> repairHints;

  /// Converts the action result to JSON.
  Map<String, Object?> toJson() {
    return {
      'index': index,
      'action': action,
      'status': status,
      if (command != null) 'command': command,
      if (reason != null) 'reason': reason,
      if (details.isNotEmpty) 'details': details,
      if (repairHints.isNotEmpty) 'repairHints': repairHints,
    };
  }
}
