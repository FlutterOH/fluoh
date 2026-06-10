import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../context/fluoh_environment.dart';
import '../platform/ohos/ohos_toolchain.dart';
import '../sdk/flutter_runner.dart';
import '../sdk/sdk_manager.dart';
import '../schema/yaml_utils.dart';
import 'ios_xctest_project.dart';
import 'workflow_result.dart';

part 'automation_scenario_android.dart';
part 'automation_scenario_driver.dart';
part 'automation_scenario_ios.dart';
part 'automation_scenario_ohos.dart';

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

  /// Converts the coverage item to JSON.
  Map<String, Object?> toJson() {
    return {
      'category': category,
      'item': item,
      if (path != null) 'path': path,
      'status': status,
      if (note != null) 'note': note,
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

/// Reads an automation scenario from YAML, JSON, or a Markdown YAML block.
Future<AutomationScenario> readAutomationScenario(
  File file, {
  required Directory workingDirectory,
}) async {
  final resolved = file.isAbsolute
      ? file
      : File('${workingDirectory.path}/${file.path}');
  final content = await resolved.readAsString();
  final source = _scenarioSource(content, path: resolved.path);
  final Object? decoded;
  if (source.trimLeft().startsWith('{')) {
    decoded = jsonDecode(source);
  } else {
    decoded = parseYamlMap(source, label: resolved.path);
  }
  final json = jsonObject(decoded, resolved.path);
  final platform = _requiredScenarioString(json, 'platform');
  final stepsValue = json['steps'] ?? json['actions'];
  if (stepsValue is! List || stepsValue.isEmpty) {
    throw FormatException('Scenario ${resolved.path} must contain steps.');
  }
  final steps = [
    for (var index = 0; index < stepsValue.length; index += 1)
      _readScenarioAction(stepsValue[index], index + 1, resolved.path),
  ];
  return AutomationScenario(
    path: resolved,
    name: optionalString(json, 'name') ?? _scenarioNameFromPath(resolved),
    platform: platform,
    steps: steps,
    coverage: _readScenarioCoverage(json['coverage'], steps, resolved.path),
  );
}

/// Runs [scenario] against [target].
Future<AutomationScenarioRunResult> runAutomationScenario({
  required AutomationScenario scenario,
  required WorkflowTargetResult target,
  required FluohEnvironment environment,
  required String nextCommand,
}) async {
  if (!target.passed) {
    return AutomationScenarioRunResult(
      scenario: scenario,
      status: 'skipped',
      exitCode: target.exitCode,
      actions: const [],
      reason: 'workflow target did not pass before scenario execution',
    );
  }
  final context = _ScenarioExecutionContext.fromTarget(
    scenario: scenario,
    target: target,
    environment: environment,
  );
  if (context.targetId == null) {
    final diagnostic = WorkflowDiagnostic(
      code: '${scenario.platform}.scenario_target_missing',
      message: 'Scenario target id is missing.',
      details: {
        'scenario': scenario.path.path,
        'platform': scenario.platform,
        'target': target.toJson()['target'],
      },
      nextCommand: nextCommand,
    );
    return AutomationScenarioRunResult(
      scenario: scenario,
      status: 'failed',
      exitCode: 1,
      actions: const [],
      reason: diagnostic.message,
      diagnostic: diagnostic,
    );
  }

  final actions = <AutomationScenarioActionResult>[];
  var appForegroundedForUi = false;
  var foregroundAttempted = false;
  for (final action in scenario.steps) {
    if (!appForegroundedForUi &&
        !foregroundAttempted &&
        _shouldAutoForegroundScenarioApp(context, action)) {
      foregroundAttempted = true;
      final foregroundResult = await _foregroundScenarioAppIfNeeded(
        context,
        action,
        nextCommand: nextCommand,
      );
      if (foregroundResult != null) {
        actions.add(foregroundResult);
        if (foregroundResult.status == 'failed') {
          final diagnostic = WorkflowDiagnostic(
            code: '${scenario.platform}.scenario_foregroundApp_failed',
            message: 'Scenario action foregroundApp failed.',
            details: {
              'scenario': scenario.path.path,
              'action': {
                'action': 'foregroundApp',
                'beforeAction': action.toJson(),
              },
              'result': foregroundResult.toJson(),
              if (foregroundResult.repairHints.isNotEmpty)
                'repairHints': foregroundResult.repairHints,
            },
            nextCommand: nextCommand,
          );
          return AutomationScenarioRunResult(
            scenario: scenario,
            status: 'failed',
            exitCode: 1,
            actions: actions,
            reason: foregroundResult.reason,
            diagnostic: diagnostic,
          );
        }
        appForegroundedForUi = foregroundResult.status == 'passed';
      }
    }
    final result = await _runScenarioAction(
      action,
      context: context,
      nextCommand: nextCommand,
    );
    actions.add(result);
    if (result.status == 'failed') {
      final diagnostic = WorkflowDiagnostic(
        code: '${scenario.platform}.scenario_${action.action}_failed',
        message: 'Scenario action ${action.action} failed.',
        details: {
          'scenario': scenario.path.path,
          'action': action.toJson(),
          'result': result.toJson(),
          if (result.repairHints.isNotEmpty) 'repairHints': result.repairHints,
        },
        nextCommand: nextCommand,
      );
      return AutomationScenarioRunResult(
        scenario: scenario,
        status: 'failed',
        exitCode: 1,
        actions: actions,
        reason: result.reason,
        diagnostic: diagnostic,
      );
    }
    if (action.action == 'launchApp' && result.status == 'passed') {
      appForegroundedForUi = true;
      foregroundAttempted = true;
    } else if (action.action == 'clearAppData' && result.status == 'passed') {
      appForegroundedForUi = false;
      foregroundAttempted = false;
    }
  }
  return AutomationScenarioRunResult(
    scenario: scenario,
    status: 'passed',
    exitCode: 0,
    actions: actions,
  );
}

String _scenarioSource(String content, {required String path}) {
  final trimmed = content.trimLeft();
  if (!path.endsWith('.md') ||
      trimmed.startsWith('{') ||
      trimmed.startsWith('kind:') ||
      trimmed.startsWith('schema:') ||
      trimmed.startsWith('name:') ||
      trimmed.startsWith('platform:')) {
    return content;
  }
  final blocks = RegExp(
    r'```(?:yaml|yml)\s*\n([\s\S]*?)\n```',
    multiLine: true,
  ).allMatches(content);
  for (final block in blocks) {
    final source = block.group(1) ?? '';
    if (source.contains('fluoh.automationScenario') ||
        source.contains('steps:') ||
        source.contains('actions:')) {
      return source;
    }
  }
  throw FormatException(
    'Markdown scenario $path must include a yaml code block with steps.',
  );
}

String _requiredScenarioString(Map<String, Object?> json, String key) {
  final value = optionalString(json, key);
  if (value == null || value.trim().isEmpty) {
    throw FormatException('Scenario must contain $key.');
  }
  return value.trim();
}

String _scenarioNameFromPath(File file) {
  final name = file.uri.pathSegments.isEmpty
      ? file.path
      : file.uri.pathSegments.last;
  final dot = name.lastIndexOf('.');
  return dot == -1 ? name : name.substring(0, dot);
}

AutomationScenarioAction _readScenarioAction(
  Object? value,
  int index,
  String path,
) {
  final json = jsonObject(value, '$path steps[$index]');
  final timeoutSeconds = _optionalInt(json['timeoutSeconds']) ?? 5;
  return AutomationScenarioAction(
    action: _requiredScenarioString(json, 'action'),
    index: index,
    text: optionalString(json, 'text') ?? optionalString(json, 'contains'),
    labels: _stringList(json['labels']),
    match: optionalString(json, 'match') ?? 'contains',
    x: _optionalInt(json['x']) ?? _optionalInt(json['startX']),
    y: _optionalInt(json['y']) ?? _optionalInt(json['startY']),
    endX: _optionalInt(json['endX']) ?? _optionalInt(json['toX']),
    endY: _optionalInt(json['endY']) ?? _optionalInt(json['toY']),
    durationMilliseconds:
        _optionalInt(json['durationMilliseconds']) ??
        _optionalInt(json['durationMs']),
    value: optionalString(json, 'value') ?? optionalString(json, 'status'),
    keyCode: optionalString(json, 'keyCode'),
    permission: optionalString(json, 'permission'),
    bundleId:
        optionalString(json, 'bundleId') ??
        optionalString(json, 'appId') ??
        optionalString(json, 'packageName'),
    abilityName: optionalString(json, 'abilityName'),
    timeout: Duration(seconds: timeoutSeconds),
    optional: json['optional'] == true,
    repairHints: [
      ..._stringList(json['repairHints']),
      ..._repairHintFromMap(json['repair']),
    ],
  );
}

List<String> _repairHintFromMap(Object? value) {
  if (value is Map) {
    return [
      if (value['message'] case final message?)
        if (message.toString().trim().isNotEmpty) message.toString().trim(),
      if (value['suggestion'] case final suggestion?)
        if (suggestion.toString().trim().isNotEmpty)
          suggestion.toString().trim(),
    ];
  }
  return const [];
}

List<AutomationScenarioCoverageItem> _readScenarioCoverage(
  Object? value,
  List<AutomationScenarioAction> steps,
  String path,
) {
  final explicit = _explicitScenarioCoverage(value, path);
  if (explicit.isNotEmpty) {
    return explicit;
  }
  final inferred = <String, AutomationScenarioCoverageItem>{};
  for (final action in steps) {
    final permission = action.permission?.trim();
    if (permission == null || permission.isEmpty) {
      continue;
    }
    final path = switch (action.action) {
      'allowPermission' => 'grant',
      'denyPermission' => 'deny',
      'resetPermission' => 'reset',
      _ => null,
    };
    if (path == null) {
      continue;
    }
    final key = 'permission:$permission:$path';
    inferred[key] = AutomationScenarioCoverageItem(
      category: 'permission',
      item: permission,
      path: path,
    );
  }
  return inferred.values.toList();
}

List<AutomationScenarioCoverageItem> _explicitScenarioCoverage(
  Object? value,
  String path,
) {
  if (value == null) {
    return const [];
  }
  if (value is List) {
    return [
      for (var index = 0; index < value.length; index += 1)
        _readCoverageItem(value[index], '$path coverage[$index]'),
    ];
  }
  if (value is Map) {
    final json = jsonObject(value, '$path coverage');
    final items = json['items'] ?? json['matrix'];
    if (items is List) {
      return [
        for (var index = 0; index < items.length; index += 1)
          _readCoverageItem(items[index], '$path coverage.items[$index]'),
      ];
    }
    return [_readCoverageItem(json, '$path coverage')];
  }
  throw FormatException('Scenario $path coverage must be a map or list.');
}

AutomationScenarioCoverageItem _readCoverageItem(Object? value, String label) {
  final json = jsonObject(value, label);
  final category =
      optionalString(json, 'category') ??
      optionalString(json, 'class') ??
      optionalString(json, 'capability');
  final item =
      optionalString(json, 'item') ??
      optionalString(json, 'name') ??
      optionalString(json, 'permission');
  if (category == null || category.trim().isEmpty) {
    throw FormatException('$label must contain category.');
  }
  if (item == null || item.trim().isEmpty) {
    throw FormatException('$label must contain item.');
  }
  final status = _coverageStatus(optionalString(json, 'status'), label);
  final note = optionalString(json, 'note') ?? optionalString(json, 'reason');
  if ((status == 'blocked' || status == 'notApplicable') &&
      (note == null || note.trim().isEmpty)) {
    throw FormatException(
      '$label status $status must include a non-empty note or reason.',
    );
  }
  return AutomationScenarioCoverageItem(
    category: category.trim(),
    item: item.trim(),
    path:
        optionalString(json, 'path') ??
        optionalString(json, 'case') ??
        optionalString(json, 'flow'),
    status: status,
    note: note?.trim(),
  );
}

String _coverageStatus(String? value, String label) {
  final status = value?.trim();
  if (status == null || status.isEmpty) {
    return 'covered';
  }
  const supported = {'covered', 'notApplicable', 'blocked'};
  if (!supported.contains(status)) {
    throw FormatException(
      '$label status must be covered, notApplicable, or blocked.',
    );
  }
  return status;
}

List<String> _stringList(Object? value) {
  if (value is List) {
    return [
      for (final item in value)
        if (item.toString().trim().isNotEmpty) item.toString().trim(),
    ];
  }
  if (value is String && value.trim().isNotEmpty) {
    return [value.trim()];
  }
  return const [];
}

int? _optionalInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is String) {
    return int.tryParse(value.trim());
  }
  return null;
}

class _ScenarioExecutionContext {
  const _ScenarioExecutionContext({
    required this.scenario,
    required this.target,
    required this.environment,
    required this.targetId,
    required this.sessionFile,
    required this.outputLog,
    required this.hilog,
    required this.ohosBundleName,
    required this.ohosAbilityName,
    required this.rebuiltIosApps,
    required this.foregroundedIosSimulators,
    required this.launchedIosApps,
  });

  factory _ScenarioExecutionContext.fromTarget({
    required AutomationScenario scenario,
    required WorkflowTargetResult target,
    required FluohEnvironment environment,
  }) {
    String? targetId;
    File? sessionFile;
    File? outputLog;
    File? hilog;
    String? ohosBundleName;
    String? ohosAbilityName;
    for (final step in target.steps.reversed) {
      targetId ??= _targetIdFromDetails(step.details);
      sessionFile ??= _fileFromDetails(step.details, 'sessionFile');
      outputLog ??= _fileFromDetails(step.details, 'outputLog');
      hilog ??= _fileFromDetails(step.details, 'hilog');
      final launchInfo = step.details['launchInfo'];
      ohosBundleName ??= _stringFromMap(launchInfo, 'bundleName');
      ohosAbilityName ??= _stringFromMap(launchInfo, 'abilityName');
    }
    return _ScenarioExecutionContext(
      scenario: scenario,
      target: target,
      environment: environment,
      targetId: targetId,
      sessionFile: sessionFile,
      outputLog: outputLog,
      hilog: hilog,
      ohosBundleName: ohosBundleName,
      ohosAbilityName: ohosAbilityName,
      rebuiltIosApps: <String>{},
      foregroundedIosSimulators: <String>{},
      launchedIosApps: <String>{},
    );
  }

  final AutomationScenario scenario;
  final WorkflowTargetResult target;
  final FluohEnvironment environment;
  final String? targetId;
  final File? sessionFile;
  final File? outputLog;
  final File? hilog;
  final String? ohosBundleName;
  final String? ohosAbilityName;
  final Set<String> rebuiltIosApps;
  final Set<String> foregroundedIosSimulators;
  final Set<String> launchedIosApps;
}

String? _targetIdFromDetails(Map<String, Object?> details) {
  final target = details['target'];
  if (target is Map && target['id'] is String) {
    return target['id'] as String;
  }
  final targetId = details['targetId'];
  if (targetId is String && targetId.trim().isNotEmpty) {
    return targetId.trim();
  }
  return null;
}

String? _stringFromMap(Object? value, String key) {
  if (value is Map) {
    final raw = value[key];
    if (raw is String && raw.trim().isNotEmpty) {
      return raw.trim();
    }
  }
  return null;
}

File? _fileFromDetails(Map<String, Object?> details, String key) {
  final value = details[key];
  if (value is String && value.trim().isNotEmpty) {
    return File(value.trim());
  }
  return null;
}

Future<AutomationScenarioActionResult> _runScenarioAction(
  AutomationScenarioAction action, {
  required _ScenarioExecutionContext context,
  required String nextCommand,
}) async {
  final driver = _AutomationScenarioPlatformDrivers.forPlatform(
    context.scenario.platform,
  );
  final result = await driver.runAction(
    action,
    context: context,
    nextCommand: nextCommand,
  );
  if (result.status == 'failed' && action.optional) {
    return AutomationScenarioActionResult(
      index: result.index,
      action: result.action,
      status: 'skipped',
      command: result.command,
      reason: result.reason,
      details: result.details,
      repairHints: result.repairHints,
    );
  }
  return result;
}

Future<AutomationScenarioActionResult?> _foregroundScenarioAppIfNeeded(
  _ScenarioExecutionContext context,
  AutomationScenarioAction beforeAction, {
  required String nextCommand,
}) async {
  switch (context.scenario.platform) {
    case 'android':
      var packageName = _firstScenarioBundleId(context);
      packageName ??= await _findAndroidApplicationId(context);
      if (packageName == null || packageName.isEmpty) {
        return null;
      }
      final launch = await _runScenarioAction(
        AutomationScenarioAction(
          action: 'launchApp',
          index: 0,
          bundleId: packageName,
          timeout: beforeAction.timeout,
          repairHints: [
            ...beforeAction.repairHints,
            'Confirm the Android applicationId is declared in android/app/build.gradle or add packageName to the scenario.',
          ],
        ),
        context: context,
        nextCommand: nextCommand,
      );
      return _foregroundActionResult(
        launch,
        platform: 'android',
        beforeAction: beforeAction.action,
        details: {'packageName': packageName},
      );
    case 'ohos':
      final bundleName =
          _firstScenarioBundleId(context) ?? context.ohosBundleName;
      if (bundleName == null || bundleName.isEmpty) {
        return null;
      }
      final abilityName =
          _firstScenarioAbilityName(context) ??
          context.ohosAbilityName ??
          'EntryAbility';
      final launch = await _runScenarioAction(
        AutomationScenarioAction(
          action: 'launchApp',
          index: 0,
          bundleId: bundleName,
          abilityName: abilityName,
          timeout: beforeAction.timeout,
          repairHints: [
            ...beforeAction.repairHints,
            'Confirm the OHOS bundleName and abilityName are present in the scenario or run result launchInfo.',
          ],
        ),
        context: context,
        nextCommand: nextCommand,
      );
      return _foregroundActionResult(
        launch,
        platform: 'ohos',
        beforeAction: beforeAction.action,
        details: {'bundleName': bundleName, 'abilityName': abilityName},
      );
    default:
      return null;
  }
}

AutomationScenarioActionResult _foregroundActionResult(
  AutomationScenarioActionResult launch, {
  required String platform,
  required String beforeAction,
  required Map<String, Object?> details,
}) {
  return AutomationScenarioActionResult(
    index: 0,
    action: 'foregroundApp',
    status: launch.status,
    command: launch.command,
    reason: launch.reason,
    details: {
      'platform': platform,
      'beforeAction': beforeAction,
      ...details,
      if (launch.details.isNotEmpty) 'launch': launch.details,
    },
    repairHints: launch.repairHints,
  );
}

bool _shouldAutoForegroundScenarioApp(
  _ScenarioExecutionContext context,
  AutomationScenarioAction action,
) {
  if (context.scenario.platform != 'android' &&
      context.scenario.platform != 'ohos') {
    return false;
  }
  const uiActions = {
    'tap',
    'swipe',
    'drag',
    'tapText',
    'waitText',
    'assertText',
    'allowPermission',
    'denyPermission',
    'inputText',
    'press',
  };
  return uiActions.contains(action.action);
}

String? _firstScenarioBundleId(_ScenarioExecutionContext context) {
  for (final action in context.scenario.steps) {
    final bundleId = _nonEmptyString(action.bundleId);
    if (bundleId != null) {
      return bundleId;
    }
    if (action.action == 'launchApp' || action.action == 'clearAppData') {
      final value =
          _nonEmptyString(action.value) ?? _nonEmptyString(action.text);
      if (value != null) {
        return value;
      }
    }
  }
  return null;
}

String? _firstScenarioAbilityName(_ScenarioExecutionContext context) {
  for (final action in context.scenario.steps) {
    final abilityName = _nonEmptyString(action.abilityName);
    if (abilityName != null) {
      return abilityName;
    }
  }
  return null;
}

Future<String?> _findAndroidApplicationId(
  _ScenarioExecutionContext context,
) async {
  final roots = _scenarioSearchRoots(context);
  for (final root in roots) {
    for (final file in _androidApplicationGradleFiles(root)) {
      final applicationId = await _readAndroidGradleValue(
        file,
        'applicationId',
      );
      if (applicationId != null) {
        return applicationId;
      }
    }
  }
  for (final root in roots) {
    final manifest = File(
      '${root.path}/android/app/src/main/AndroidManifest.xml',
    );
    final manifestPackage = await _readAndroidManifestPackage(manifest);
    if (manifestPackage != null) {
      return manifestPackage;
    }
  }
  for (final root in roots) {
    for (final file in _androidApplicationGradleFiles(root)) {
      final namespace = await _readAndroidApplicationNamespace(file);
      if (namespace != null) {
        return namespace;
      }
    }
  }
  return null;
}

List<File> _androidApplicationGradleFiles(Directory root) {
  return [
    File('${root.path}/android/app/build.gradle'),
    File('${root.path}/android/app/build.gradle.kts'),
    File('${root.path}/build.gradle'),
    File('${root.path}/build.gradle.kts'),
  ];
}

Future<String?> _readAndroidGradleValue(File file, String key) async {
  if (!await file.exists()) {
    return null;
  }
  try {
    final content = await file.readAsString();
    return _gradleStringValue(content, key);
  } on FileSystemException {
    return null;
  }
}

Future<String?> _readAndroidApplicationNamespace(File file) async {
  if (!await file.exists()) {
    return null;
  }
  try {
    final content = await file.readAsString();
    if (!_isAndroidApplicationGradle(content)) {
      return null;
    }
    return _gradleStringValue(content, 'namespace');
  } on FileSystemException {
    return null;
  }
}

bool _isAndroidApplicationGradle(String content) {
  return content.contains('com.android.application') ||
      content.contains('com.android.dynamic-feature');
}

String? _gradleStringValue(String content, String key) {
  final match = RegExp(
    "\\b${RegExp.escape(key)}\\s*(?:\\(|=)?\\s*[\"']([^\"']+)[\"']",
  ).firstMatch(content);
  final value = match?.group(1)?.trim();
  return value == null || value.isEmpty ? null : value;
}

Future<String?> _readAndroidManifestPackage(File file) async {
  if (!await file.exists()) {
    return null;
  }
  try {
    final content = await file.readAsString();
    final match = RegExp(r'\bpackage\s*=\s*"([^"]+)"').firstMatch(content);
    final value = match?.group(1)?.trim();
    return value == null || value.isEmpty ? null : value;
  } on FileSystemException {
    return null;
  }
}

Future<AutomationScenarioActionResult> _runAndroidTextAction(
  AutomationScenarioAction action,
  Future<_ToolRun> Function(List<String> args) adbRun,
) async {
  final labels = _actionLabels(action);
  if (labels.isEmpty) {
    return _failedAction(action, '${action.action} requires text or labels');
  }
  final deadline = DateTime.now().add(action.timeout);
  AndroidUiNode? node;
  String? lastDump;
  do {
    final dump = await _androidUiDump(adbRun);
    if (dump.exitCode != 0) {
      return _failedAction(
        action,
        'Could not dump Android UI',
        command: dump.command,
        details: dump.toDetails(),
        repairHints: action.repairHints,
      );
    }
    lastDump = dump.stdout;
    node = _findAndroidUiNode(
      parseAndroidUiNodes(dump.stdout),
      labels,
      match: action.match,
    );
    if (node != null) {
      break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  } while (DateTime.now().isBefore(deadline));

  if (node == null) {
    return _failedAction(
      action,
      'No Android UI node matched ${labels.join(', ')}',
      details: {
        'labels': labels,
        'match': action.match,
        'uiDumpTail': _tail(lastDump),
      },
      repairHints: [
        ...action.repairHints,
        'Expose stable visible text, content description, or a Flutter integration_test for this scenario.',
      ],
    );
  }
  if (action.action == 'waitText' || action.action == 'assertText') {
    return _passedAction(
      action,
      details: {
        'matchedText': node.label,
        'bounds': node.bounds.toJson(),
        if (node.resourceId != null) 'resourceId': node.resourceId,
      },
    );
  }
  final x = node.bounds.centerX;
  final y = node.bounds.centerY;
  final args = ['shell', 'input', 'tap', '$x', '$y'];
  final result = await adbRun(args);
  return _processActionResult(
    action,
    result,
    'adb ${args.join(' ')}',
    details: {
      'matchedText': node.label,
      'bounds': node.bounds.toJson(),
      if (node.resourceId != null) 'resourceId': node.resourceId,
    },
  );
}

Future<AutomationScenarioActionResult> _tapAndroidPermission(
  AutomationScenarioAction action,
  Future<_ToolRun> Function(List<String> args) adbRun, {
  required bool allow,
}) async {
  final labels = [
    ...action.labels,
    if (action.text != null) action.text!,
    if (allow) ..._androidAllowPermissionLabels,
    if (!allow) ..._androidDenyPermissionLabels,
  ];
  final result = await _runAndroidTextAction(
    AutomationScenarioAction(
      action: 'tapText',
      index: action.index,
      text: action.text,
      labels: labels,
      match: action.match,
      timeout: action.timeout,
      optional: action.optional,
      repairHints: [
        ...action.repairHints,
        if (allow)
          'Trigger the runtime permission request before the allowPermission scenario step.',
        if (!allow)
          'Trigger the runtime permission request before the denyPermission scenario step.',
      ],
    ),
    adbRun,
  );
  return AutomationScenarioActionResult(
    index: action.index,
    action: action.action,
    status: result.status,
    command: result.command,
    reason: result.reason,
    details: {
      ...result.details,
      'labels': labels,
      'permissionAction': allow ? 'allow' : 'deny',
    },
    repairHints: result.repairHints,
  );
}

const _androidAllowPermissionLabels = [
  'While using the app',
  'Allow',
  'OK',
  '允许',
  '仅在使用中允许',
  '使用期间允许',
  '始终允许',
];

const _androidDenyPermissionLabels = [
  "Don’t allow",
  "Don't allow",
  'Deny',
  'Not now',
  '不允许',
  '拒绝',
];

Future<_ToolRun> _androidUiDump(
  Future<_ToolRun> Function(List<String> args) adbRun,
) async {
  final dump = await adbRun(const [
    'shell',
    'uiautomator',
    'dump',
    '/sdcard/fluoh-window.xml',
  ]);
  if (dump.exitCode != 0) {
    return dump;
  }
  return adbRun(const ['exec-out', 'cat', '/sdcard/fluoh-window.xml']);
}

Future<AutomationScenarioActionResult> _assertAndroidLog(
  AutomationScenarioAction action,
  Future<_ToolRun> Function(List<String> args) adbRun,
) async {
  final expected = action.text ?? action.value;
  if (expected == null || expected.isEmpty) {
    return _failedAction(action, 'assertLog requires text, contains, or value');
  }
  final result = await adbRun(const ['logcat', '-d', '-t', '200']);
  if (result.exitCode != 0) {
    return _failedAction(
      action,
      'Could not read Android logcat',
      command: result.command,
      details: result.toDetails(),
      repairHints: action.repairHints,
    );
  }
  if (!_matches(result.stdout, expected, action.match)) {
    return _failedAction(
      action,
      'Android logcat did not contain $expected',
      command: result.command,
      details: {'logcatTail': _tail(result.stdout)},
      repairHints: [
        ...action.repairHints,
        'Add a structured app log marker or expose the expected state through integration_test.',
      ],
    );
  }
  return _passedAction(
    action,
    command: result.command,
    details: {'logcatTail': _tail(result.stdout)},
  );
}

Future<AutomationScenarioActionResult> _runIosTextAction(
  AutomationScenarioAction action,
  _ScenarioExecutionContext context,
) async {
  final bundleId = action.bundleId?.trim();
  if (bundleId == null || bundleId.isEmpty) {
    return _failedAction(
      action,
      '${action.action} requires bundleId for the built-in XCTest iOS text driver',
      details: {'driver': 'xctest'},
      repairHints: [
        ...action.repairHints,
        'Add bundleId to the iOS text scenario action.',
      ],
    );
  }
  final labels = _actionLabels(action);
  if (labels.isEmpty) {
    return _failedAction(action, '${action.action} requires text or labels');
  }
  final installCheck = await _ensureIosAppInstalled(
    context,
    bundleId: bundleId,
  );
  if (!installCheck.passed) {
    return _failedAction(
      action,
      installCheck.reason ?? 'Could not install the iOS app before XCTest',
      command: installCheck.command,
      details: {
        'driver': 'xctest',
        'bundleId': bundleId,
        'appInstall': installCheck.toJson(),
      },
      repairHints: [
        ...action.repairHints,
        'Run fluoh run --platform ios first, or make sure build/ios/iphonesimulator contains the app bundle for this scenario bundleId.',
      ],
    );
  }
  final xcodebuild = await _iosXcodebuild(
    context.environment.processEnvironment,
  );
  if (xcodebuild == null) {
    return _failedAction(
      action,
      'xcodebuild was not found for the built-in XCTest iOS text driver',
      details: {'driver': 'xctest'},
      repairHints: [
        ...action.repairHints,
        'Install the full Xcode app and make it active with xcode-select.',
        'If XCTest is unavailable in this environment, use integration_test or a manual-assisted scenario for this iOS text step.',
      ],
    );
  }

  final project = await writeIosXCTestTextActionProject(
    cacheRoot: Directory(
      '${context.environment.homeDirectory.path}/cache/automation',
    ),
    bundleId: bundleId,
    labels: labels,
    match: action.match,
    timeoutSeconds: action.timeout.inSeconds,
    action: action.action,
  );
  final args = [
    ...xcodebuild.prefixArguments,
    'test',
    '-project',
    project.projectFile.path,
    '-scheme',
    iosXCTestSchemeName,
    '-destination',
    'id=${context.targetId!}',
    '-derivedDataPath',
    project.derivedData.path,
    'CODE_SIGNING_ALLOWED=NO',
  ];
  final result = await _runTool(
    xcodebuild.executable.path,
    args,
    environment: context.environment.processEnvironment,
    workingDirectory: context.environment.workingDirectory,
    timeout: Duration(seconds: action.timeout.inSeconds + 180),
  );
  return _processActionResult(
    action,
    result,
    result.command,
    details: {
      'driver': 'xctest',
      'method': 'xcodebuildTest',
      'project': project.projectFile.path,
      'derivedData': project.derivedData.path,
      'bundleId': bundleId,
      'labels': labels,
      'match': action.match,
      'appInstall': installCheck.toJson(),
    },
  );
}

Future<AutomationScenarioActionResult> _runIosCoordinateAction(
  AutomationScenarioAction action,
  _ScenarioExecutionContext context,
) async {
  final bundleId = action.bundleId?.trim();
  if (bundleId == null || bundleId.isEmpty) {
    return _failedAction(
      action,
      '${action.action} requires bundleId for the built-in XCTest iOS coordinate driver',
      details: {'driver': 'xctest'},
      repairHints: [
        ...action.repairHints,
        'Add bundleId to the iOS coordinate scenario action.',
      ],
    );
  }
  final coordinates = action.action == 'tap'
      ? _tapCoordinates(action)
      : _swipeCoordinates(action);
  if (coordinates == null) {
    return _failedAction(
      action,
      action.action == 'tap'
          ? 'tap requires x and y coordinates'
          : '${action.action} requires x, y, endX, and endY coordinates',
      details: {'driver': 'xctest'},
      repairHints: action.repairHints,
    );
  }
  final installCheck = await _ensureIosAppInstalled(
    context,
    bundleId: bundleId,
  );
  if (!installCheck.passed) {
    return _failedAction(
      action,
      installCheck.reason ?? 'Could not install the iOS app before XCTest',
      command: installCheck.command,
      details: {
        'driver': 'xctest',
        'bundleId': bundleId,
        'appInstall': installCheck.toJson(),
      },
      repairHints: [
        ...action.repairHints,
        'Run fluoh run --platform ios first, or make sure build/ios/iphonesimulator contains the app bundle for this scenario bundleId.',
      ],
    );
  }
  final xcodebuild = await _iosXcodebuild(
    context.environment.processEnvironment,
  );
  if (xcodebuild == null) {
    return _failedAction(
      action,
      'xcodebuild was not found for the built-in XCTest iOS coordinate driver',
      details: {'driver': 'xctest'},
      repairHints: [
        ...action.repairHints,
        'Install the full Xcode app and make it active with xcode-select.',
      ],
    );
  }

  final project = await writeIosXCTestCoordinateActionProject(
    cacheRoot: Directory(
      '${context.environment.homeDirectory.path}/cache/automation',
    ),
    bundleId: bundleId,
    x: coordinates.x,
    y: coordinates.y,
    endX: coordinates.endX,
    endY: coordinates.endY,
    durationMilliseconds: coordinates.durationMilliseconds,
    action: action.action == 'drag' ? 'swipe' : action.action,
  );
  final args = [
    ...xcodebuild.prefixArguments,
    'test',
    '-project',
    project.projectFile.path,
    '-scheme',
    iosXCTestSchemeName,
    '-destination',
    'id=${context.targetId!}',
    '-derivedDataPath',
    project.derivedData.path,
    'CODE_SIGNING_ALLOWED=NO',
  ];
  final result = await _runTool(
    xcodebuild.executable.path,
    args,
    environment: context.environment.processEnvironment,
    workingDirectory: context.environment.workingDirectory,
    timeout: Duration(seconds: action.timeout.inSeconds + 180),
  );
  return _processActionResult(
    action,
    result,
    result.command,
    details: {
      'driver': 'xctest',
      'method': 'xcodebuildTest',
      'bundleId': bundleId,
      'gesture': coordinates.toJson(),
      'project': project.projectFile.path,
      'derivedData': project.derivedData.path,
      'appInstall': installCheck.toJson(),
    },
  );
}

Future<_IosAppInstallCheck> _ensureIosAppInstalled(
  _ScenarioExecutionContext context, {
  required String bundleId,
}) async {
  final targetId = context.targetId;
  if (targetId == null || targetId.trim().isEmpty) {
    return const _IosAppInstallCheck(
      passed: false,
      status: 'missingTarget',
      reason: 'iOS scenario target did not expose a simulator id',
    );
  }
  final xcrun = await _xcrun(context.environment.processEnvironment);
  if (xcrun == null) {
    return const _IosAppInstallCheck(
      passed: false,
      status: 'missingXcrun',
      reason: 'xcrun was not found',
    );
  }
  final foreground = await _foregroundIosSimulatorIfNeeded(
    context,
    targetId: targetId,
  );

  final rebuild = await _rebuildIosSimulatorAppIfNeeded(context, bundleId);
  if (!rebuild.passed) {
    return _IosAppInstallCheck(
      passed: false,
      status: 'prebuildFailed',
      command: rebuild.command,
      reason: rebuild.reason ?? 'flutter build ios --simulator --debug failed',
      details: {
        'bundleId': bundleId,
        'targetId': targetId,
        'foreground': foreground.toJson(),
        'prebuild': rebuild.toJson(),
      },
    );
  }

  final checkArgs = ['simctl', 'get_app_container', targetId, bundleId, 'app'];
  final check = rebuild.performed
      ? null
      : await _runTool(
          xcrun.path,
          checkArgs,
          environment: context.environment.processEnvironment,
          workingDirectory: context.environment.workingDirectory,
        );
  Future<_ToolRun?> launchIfNeeded() async {
    final launchKey = '$targetId:$bundleId';
    if (context.launchedIosApps.contains(launchKey)) {
      return null;
    }
    final launchArgs = ['simctl', 'launch', targetId, bundleId];
    final launch = await _runTool(
      xcrun.path,
      launchArgs,
      environment: context.environment.processEnvironment,
      workingDirectory: context.environment.workingDirectory,
      timeout: const Duration(seconds: 60),
    );
    if (launch.exitCode == 0) {
      context.launchedIosApps.add(launchKey);
    }
    return launch;
  }

  if (check != null && check.exitCode == 0) {
    final launch = await launchIfNeeded();
    return _IosAppInstallCheck(
      passed: launch == null || launch.exitCode == 0,
      status: launch != null && launch.exitCode != 0
          ? 'launchFailed'
          : 'alreadyInstalled',
      command: launch != null && launch.exitCode != 0
          ? launch.command
          : check.command,
      reason: launch != null && launch.exitCode != 0
          ? 'simctl launch failed for $bundleId'
          : null,
      details: {
        'foreground': foreground.toJson(),
        'prebuild': rebuild.toJson(),
        'getAppContainer': check.toDetails(),
        if (launch != null) 'launch': launch.toDetails(),
      },
    );
  }

  final appBundle = await _findIosSimulatorAppBundle(context, bundleId);
  if (appBundle == null) {
    final appBundleCandidates = await _iosSimulatorAppBundleCandidates(context);
    return _IosAppInstallCheck(
      passed: false,
      status: 'missingAppBundle',
      command: check?.command ?? rebuild.command,
      reason:
          'iOS app $bundleId is not installed and no matching simulator app bundle was found under build/ios.',
      details: {
        'bundleId': bundleId,
        'targetId': targetId,
        'foreground': foreground.toJson(),
        'prebuild': rebuild.toJson(),
        if (check != null) 'getAppContainer': check.toDetails(),
        if (appBundleCandidates.isNotEmpty)
          'candidateAppBundles': [
            for (final candidate in appBundleCandidates) candidate.toJson(),
          ],
        'searchedRoots': _iosAppSearchRoots(
          context,
        ).map((root) => root.path).toList(),
      },
    );
  }

  final launchKey = '$targetId:$bundleId';
  _ToolRun? terminate;
  _ToolRun? uninstall;
  if (rebuild.performed) {
    terminate = await _runTool(
      xcrun.path,
      ['simctl', 'terminate', targetId, bundleId],
      environment: context.environment.processEnvironment,
      workingDirectory: context.environment.workingDirectory,
    );
    uninstall = await _runTool(
      xcrun.path,
      ['simctl', 'uninstall', targetId, bundleId],
      environment: context.environment.processEnvironment,
      workingDirectory: context.environment.workingDirectory,
    );
    context.launchedIosApps.remove(launchKey);
  }

  final installArgs = ['simctl', 'install', targetId, appBundle.path];
  final install = await _runTool(
    xcrun.path,
    installArgs,
    environment: context.environment.processEnvironment,
    workingDirectory: context.environment.workingDirectory,
    timeout: const Duration(seconds: 120),
  );
  final launch = install.exitCode == 0 ? await launchIfNeeded() : null;
  return _IosAppInstallCheck(
    passed: install.exitCode == 0 && (launch == null || launch.exitCode == 0),
    status: install.exitCode != 0
        ? 'installFailed'
        : launch != null && launch.exitCode != 0
        ? 'launchFailed'
        : 'installed',
    command: launch != null && launch.exitCode != 0
        ? launch.command
        : install.command,
    reason: install.exitCode != 0
        ? 'simctl install failed for ${appBundle.path}'
        : launch != null && launch.exitCode != 0
        ? 'simctl launch failed for $bundleId'
        : null,
    details: {
      'bundleId': bundleId,
      'targetId': targetId,
      'appBundle': appBundle.path,
      'foreground': foreground.toJson(),
      'prebuild': rebuild.toJson(),
      if (check != null) 'getAppContainer': check.toDetails(),
      if (terminate != null) 'terminate': terminate.toDetails(),
      if (uninstall != null) 'uninstall': uninstall.toDetails(),
      'install': install.toDetails(),
      if (launch != null) 'launch': launch.toDetails(),
    },
  );
}

Future<_IosSimulatorForegroundResult> _foregroundIosSimulatorIfNeeded(
  _ScenarioExecutionContext context, {
  required String targetId,
}) async {
  final mode = context
      .environment
      .processEnvironment['FLUOH_IOS_FOREGROUND_SIMULATOR']
      ?.trim()
      .toLowerCase();
  if (mode == '0' || mode == 'false' || mode == 'off' || mode == 'no') {
    return const _IosSimulatorForegroundResult(status: 'disabled');
  }
  if (context.foregroundedIosSimulators.contains(targetId)) {
    return const _IosSimulatorForegroundResult(status: 'alreadyForegrounded');
  }
  final open = await _openSimulatorTool(context.environment.processEnvironment);
  if (open == null) {
    return const _IosSimulatorForegroundResult(status: 'missingOpen');
  }
  final args = ['-a', 'Simulator', '--args', '-CurrentDeviceUDID', targetId];
  final result = await _runTool(
    open.path,
    args,
    environment: context.environment.processEnvironment,
    workingDirectory: context.environment.workingDirectory,
    timeout: const Duration(seconds: 15),
  );
  if (result.exitCode == 0) {
    context.foregroundedIosSimulators.add(targetId);
  }
  return _IosSimulatorForegroundResult(
    status: result.exitCode == 0 ? 'foregrounded' : 'failed',
    command: result.command,
    details: result.toDetails(),
  );
}

Future<_IosAppPrebuildResult> _rebuildIosSimulatorAppIfNeeded(
  _ScenarioExecutionContext context,
  String bundleId,
) async {
  final key = '${context.targetId}:$bundleId';
  if (context.rebuiltIosApps.contains(key)) {
    return const _IosAppPrebuildResult(passed: true, status: 'alreadyRebuilt');
  }
  final project = await _findIosFlutterProjectForBundle(context, bundleId);
  if (project == null) {
    return const _IosAppPrebuildResult(passed: true, status: 'notFound');
  }
  final sdkVersion = await SdkManager(context.environment).currentSdkVersion();
  if (sdkVersion == null || sdkVersion.trim().isEmpty) {
    return const _IosAppPrebuildResult(passed: true, status: 'noSelectedSdk');
  }
  final flutter = File(
    '${context.environment.sdksDirectory.path}/$sdkVersion/bin/flutter',
  );
  if (!await flutter.exists()) {
    return _IosAppPrebuildResult(
      passed: true,
      status: 'missingSelectedFlutter',
      details: {'flutter': flutter.path, 'sdkVersion': sdkVersion},
    );
  }
  final args = ['build', 'ios', '--simulator', '--debug'];
  final result = await _runTool(
    flutter.path,
    args,
    environment: selectedToolProcessEnvironment(
      environment: context.environment,
      tool: flutter,
    ),
    workingDirectory: project,
    timeout: const Duration(minutes: 10),
  );
  if (result.exitCode == 0) {
    context.rebuiltIosApps.add(key);
  }
  return _IosAppPrebuildResult(
    passed: result.exitCode == 0,
    status: result.exitCode == 0 ? 'rebuilt' : 'failed',
    command: result.command,
    reason: result.exitCode == 0
        ? null
        : 'flutter build ios --simulator --debug failed before XCTest',
    details: {
      'project': project.path,
      'sdkVersion': sdkVersion,
      'flutter': flutter.path,
      ...result.toDetails(),
    },
  );
}

class _IosSimulatorForegroundResult {
  const _IosSimulatorForegroundResult({
    required this.status,
    this.command,
    this.details = const {},
  });

  final String status;
  final String? command;
  final Map<String, Object?> details;

  Map<String, Object?> toJson() {
    return {
      'status': status,
      if (command != null) 'command': command,
      ...details,
    };
  }
}

Future<Directory?> _findIosFlutterProjectForBundle(
  _ScenarioExecutionContext context,
  String bundleId,
) async {
  final candidates = <_IosFlutterProjectCandidate>[];
  for (final root in _iosAppSearchRoots(context)) {
    final pubspec = File('${root.path}/pubspec.yaml');
    final ios = Directory('${root.path}/ios');
    if (!await pubspec.exists() || !await ios.exists()) {
      continue;
    }
    var priority = 20;
    final releaseBundle = Directory(
      '${root.path}/build/ios/iphonesimulator/Runner.app',
    );
    final debugBundle = Directory(
      '${root.path}/build/ios/Debug-iphonesimulator/Runner.app',
    );
    if ((await _iosAppBundleIdentifier(releaseBundle)) == bundleId) {
      priority = 0;
    } else if ((await _iosAppBundleIdentifier(debugBundle)) == bundleId) {
      priority = 10;
    }
    candidates.add(_IosFlutterProjectCandidate(root.absolute, priority));
  }
  if (candidates.isEmpty) {
    return null;
  }
  candidates.sort((a, b) {
    final priority = a.priority.compareTo(b.priority);
    if (priority != 0) {
      return priority;
    }
    return a.directory.path.compareTo(b.directory.path);
  });
  return candidates.first.directory;
}

class _IosFlutterProjectCandidate {
  const _IosFlutterProjectCandidate(this.directory, this.priority);

  final Directory directory;
  final int priority;
}

class _IosAppPrebuildResult {
  const _IosAppPrebuildResult({
    required this.passed,
    required this.status,
    this.command,
    this.reason,
    this.details = const {},
  });

  final bool passed;
  final String status;
  final String? command;
  final String? reason;
  final Map<String, Object?> details;

  bool get performed => status == 'rebuilt';

  Map<String, Object?> toJson() {
    return {
      'status': status,
      if (command != null) 'command': command,
      if (reason != null) 'reason': reason,
      ...details,
    };
  }
}

Future<Directory?> _findIosSimulatorAppBundle(
  _ScenarioExecutionContext context,
  String bundleId,
) async {
  final ordered = await _iosSimulatorAppBundleCandidates(context);
  for (final candidate in ordered) {
    if (candidate.bundleIdentifier == bundleId) {
      return candidate.directory;
    }
  }
  return null;
}

Future<List<_IosAppBundleCandidate>> _iosSimulatorAppBundleCandidates(
  _ScenarioExecutionContext context,
) async {
  final candidates = <_IosAppBundleCandidate>[];
  for (final root in _iosAppSearchRoots(context)) {
    Future<void> addCandidate(String path, int priority) async {
      final candidate = Directory(path);
      if (await candidate.exists()) {
        candidates.add(_IosAppBundleCandidate(candidate.absolute, priority));
      }
    }

    await addCandidate('${root.path}/build/ios/iphonesimulator/Runner.app', 0);
    await addCandidate(
      '${root.path}/build/ios/Debug-iphonesimulator/Runner.app',
      10,
    );
    final buildIos = Directory('${root.path}/build/ios');
    if (await buildIos.exists()) {
      try {
        await for (final entity in buildIos.list(recursive: true)) {
          if (entity is Directory &&
              entity.path.endsWith('.app') &&
              entity.path.contains('iphonesimulator')) {
            candidates.add(
              _IosAppBundleCandidate(
                entity.absolute,
                entity.path.contains('/iphonesimulator/Runner.app')
                    ? 0
                    : entity.path.contains('/Debug-iphonesimulator/')
                    ? 10
                    : 20,
              ),
            );
          }
        }
      } on FileSystemException {
        // Keep the deterministic candidates collected above.
      }
    }
  }

  final unique = <String, _IosAppBundleCandidate>{};
  for (final candidate in candidates) {
    final existing = unique[candidate.directory.path];
    if (existing == null || candidate.priority < existing.priority) {
      unique[candidate.directory.path] = candidate;
    }
  }
  final ordered = unique.values.toList()
    ..sort((a, b) {
      final priority = a.priority.compareTo(b.priority);
      if (priority != 0) {
        return priority;
      }
      return a.directory.path.compareTo(b.directory.path);
    });
  final withBundleIds = <_IosAppBundleCandidate>[];
  for (final candidate in ordered) {
    withBundleIds.add(
      _IosAppBundleCandidate(
        candidate.directory,
        candidate.priority,
        bundleIdentifier: await _iosAppBundleIdentifier(candidate.directory),
      ),
    );
  }
  return withBundleIds;
}

class _IosAppBundleCandidate {
  const _IosAppBundleCandidate(
    this.directory,
    this.priority, {
    this.bundleIdentifier,
  });

  final Directory directory;
  final int priority;
  final String? bundleIdentifier;

  Map<String, Object?> toJson() {
    return {
      'path': directory.path,
      'priority': priority,
      if (bundleIdentifier != null) 'bundleIdentifier': bundleIdentifier,
    };
  }
}

List<Directory> _scenarioSearchRoots(_ScenarioExecutionContext context) {
  final roots = <String, Directory>{
    context.environment.workingDirectory.absolute.path:
        context.environment.workingDirectory.absolute,
  };
  for (final step in context.target.steps.reversed) {
    final path = step.path.trim();
    if (path.isEmpty || path == '.') {
      continue;
    }
    final directory = Directory(
      path.startsWith('/')
          ? path
          : '${context.environment.workingDirectory.path}/$path',
    ).absolute;
    roots[directory.path] = directory;
  }
  return roots.values.toList()..sort((a, b) => a.path.compareTo(b.path));
}

List<Directory> _iosAppSearchRoots(_ScenarioExecutionContext context) {
  return _scenarioSearchRoots(context);
}

Future<String?> _iosAppBundleIdentifier(Directory appBundle) async {
  final infoPlist = File('${appBundle.path}/Info.plist');
  if (!await infoPlist.exists()) {
    return null;
  }
  try {
    final content = await infoPlist.readAsString();
    final match = RegExp(
      r'<key>\s*CFBundleIdentifier\s*</key>\s*<string>([^<]+)</string>',
      multiLine: true,
      dotAll: true,
    ).firstMatch(content);
    final value = match?.group(1)?.trim();
    if (value != null && value.isNotEmpty) {
      return _decodeXmlEntities(value);
    }
  } on FormatException {
    // Binary plists are handled by PlistBuddy below when available.
  } on FileSystemException {
    return null;
  }
  if (!Platform.isMacOS) {
    return null;
  }
  final plistBuddy = File('/usr/libexec/PlistBuddy');
  if (!await plistBuddy.exists()) {
    return null;
  }
  try {
    final result = await Process.run(plistBuddy.path, [
      '-c',
      'Print CFBundleIdentifier',
      infoPlist.path,
    ]).timeout(const Duration(seconds: 5));
    if (result.exitCode == 0) {
      final value = result.stdout.toString().trim();
      if (value.isNotEmpty) {
        return value;
      }
    }
  } on Object {
    return null;
  }
  return null;
}

String _decodeXmlEntities(String value) {
  return value
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');
}

class _IosAppInstallCheck {
  const _IosAppInstallCheck({
    required this.passed,
    required this.status,
    this.command,
    this.reason,
    this.details = const {},
  });

  final bool passed;
  final String status;
  final String? command;
  final String? reason;
  final Map<String, Object?> details;

  Map<String, Object?> toJson() {
    return {
      'status': status,
      if (command != null) 'command': command,
      if (reason != null) 'reason': reason,
      ...details,
    };
  }
}

Future<AutomationScenarioActionResult> _runIosSimulatorPrivacy(
  AutomationScenarioAction action,
  _ScenarioExecutionContext context, {
  required String operation,
}) async {
  final bundleId = action.bundleId;
  final permission = action.permission ?? action.value ?? action.text;
  if (bundleId == null || bundleId.isEmpty || permission == null) {
    return _failedAction(
      action,
      '${action.action} requires bundleId and permission for iOS simctl privacy',
      repairHints: [
        'Add bundleId and permission to the scenario action, or use an iOS UI driver for the runtime prompt.',
      ],
    );
  }
  final xcrun = await _xcrun(context.environment.processEnvironment);
  if (xcrun == null) {
    return _failedAction(action, 'xcrun was not found');
  }
  final args = [
    'simctl',
    'privacy',
    context.targetId!,
    operation,
    permission,
    bundleId,
  ];
  final result = await _runTool(
    xcrun.path,
    args,
    environment: context.environment.processEnvironment,
    workingDirectory: context.environment.workingDirectory,
  );
  return _processActionResult(
    action,
    result,
    '${xcrun.path} ${args.join(' ')}',
    details: {
      'driver': 'simctlPrivacy',
      'operation': operation,
      'bundleId': bundleId,
      'permission': permission,
    },
  );
}

Future<AutomationScenarioActionResult> _tapIosPermission(
  AutomationScenarioAction action,
  _ScenarioExecutionContext context, {
  required bool allow,
}) async {
  final configuredDriver = context
      .environment
      .processEnvironment['FLUOH_IOS_PERMISSION_DRIVER']
      ?.trim()
      .toLowerCase();
  const supportedDrivers = {'simctl', 'xctest', 'xcuitest'};
  if (configuredDriver != null &&
      configuredDriver.isNotEmpty &&
      !supportedDrivers.contains(configuredDriver)) {
    return _failedAction(
      action,
      'Unsupported iOS permission driver $configuredDriver',
      details: {
        'configuredDriver': configuredDriver,
        'supportedDrivers': supportedDrivers.toList(),
      },
      repairHints: [
        ...action.repairHints,
        'Set FLUOH_IOS_PERMISSION_DRIVER to xctest, xcuitest, or simctl.',
      ],
    );
  }
  if (configuredDriver == 'simctl') {
    return _runIosSimulatorPrivacy(
      action,
      context,
      operation: allow ? 'grant' : 'revoke',
    );
  }

  final failures = <Map<String, Object?>>[];
  if (configuredDriver == null ||
      configuredDriver.isEmpty ||
      configuredDriver == 'xctest' ||
      configuredDriver == 'xcuitest') {
    final bundleId = action.bundleId?.trim();
    if (bundleId == null || bundleId.isEmpty) {
      final result = _failedAction(
        action,
        'bundleId is required for the built-in XCTest iOS permission driver',
        details: {'driver': 'xctest'},
        repairHints: [
          ...action.repairHints,
          'Add bundleId to the iOS permission scenario action.',
        ],
      );
      if (configuredDriver == 'xctest' || configuredDriver == 'xcuitest') {
        return result;
      }
      failures.add({
        'driver': 'xctest',
        'reason': result.reason,
        ...result.details,
      });
    } else {
      final result = await _tapIosPermissionWithXCTest(
        action,
        context,
        allow: allow,
      );
      if (result.status == 'passed' ||
          configuredDriver == 'xctest' ||
          configuredDriver == 'xcuitest') {
        return result;
      }
      failures.add({
        'driver': 'xctest',
        'reason': result.reason,
        ...result.details,
      });
    }
  }

  return _failedAction(
    action,
    'No iOS UI automation driver could click the system permission prompt',
    details: {
      'attemptedDrivers': failures,
      'configuredDriver': configuredDriver,
    },
    repairHints: [
      ...action.repairHints,
      'Install the full Xcode toolchain for the built-in XCTest iOS driver.',
      'Trigger the runtime permission request before the ${action.action} scenario step.',
      'Use FLUOH_IOS_PERMISSION_DRIVER=simctl only when simulator privacy state control is acceptable evidence.',
    ],
  );
}

Future<AutomationScenarioActionResult> _tapIosPermissionWithXCTest(
  AutomationScenarioAction action,
  _ScenarioExecutionContext context, {
  required bool allow,
}) async {
  final xcodebuild = await _iosXcodebuild(
    context.environment.processEnvironment,
  );
  if (xcodebuild == null) {
    return _failedAction(
      action,
      'xcodebuild was not found for the built-in XCTest iOS permission driver',
      details: {'driver': 'xctest'},
      repairHints: [
        ...action.repairHints,
        'Install the full Xcode app and make it active with xcode-select.',
        'If UI clicking is unavailable in this environment, use FLUOH_IOS_PERMISSION_DRIVER=simctl only when simulator privacy state control is acceptable evidence.',
      ],
    );
  }

  final labels = _iosPermissionLabels(action, allow: allow);
  final installCheck = await _ensureIosAppInstalled(
    context,
    bundleId: action.bundleId!.trim(),
  );
  if (!installCheck.passed) {
    return _failedAction(
      action,
      installCheck.reason ?? 'Could not install the iOS app before XCTest',
      command: installCheck.command,
      details: {
        'driver': 'xctest',
        'bundleId': action.bundleId,
        'appInstall': installCheck.toJson(),
      },
      repairHints: [
        ...action.repairHints,
        'Run fluoh run --platform ios first, or make sure build/ios/iphonesimulator contains the app bundle for this scenario bundleId.',
      ],
    );
  }
  final project = await writeIosXCTestPermissionProject(
    cacheRoot: Directory(
      '${context.environment.homeDirectory.path}/cache/automation',
    ),
    bundleId: action.bundleId!.trim(),
    labels: labels,
    match: action.match,
    timeoutSeconds: action.timeout.inSeconds,
    allow: allow,
  );
  final args = [
    ...xcodebuild.prefixArguments,
    'test',
    '-project',
    project.projectFile.path,
    '-scheme',
    iosXCTestSchemeName,
    '-destination',
    'id=${context.targetId!}',
    '-derivedDataPath',
    project.derivedData.path,
    'CODE_SIGNING_ALLOWED=NO',
  ];
  final result = await _runTool(
    xcodebuild.executable.path,
    args,
    environment: context.environment.processEnvironment,
    workingDirectory: context.environment.workingDirectory,
    timeout: Duration(seconds: action.timeout.inSeconds + 180),
  );
  return _processActionResult(
    action,
    result,
    result.command,
    details: {
      'driver': 'xctest',
      'method': 'xcodebuildTest',
      'project': project.projectFile.path,
      'derivedData': project.derivedData.path,
      'bundleId': action.bundleId,
      'labels': labels,
      'permissionAction': allow ? 'allow' : 'deny',
      'appInstall': installCheck.toJson(),
    },
  );
}

List<String> _iosPermissionLabels(
  AutomationScenarioAction action, {
  required bool allow,
}) {
  final labels = [
    ...action.labels,
    if (action.text != null) action.text!,
    if (allow) ..._iosAllowPermissionLabels,
    if (!allow) ..._iosDenyPermissionLabels,
  ];
  final seen = <String>{};
  return [
    for (final label in labels)
      if (label.trim().isNotEmpty && seen.add(label.trim())) label.trim(),
  ];
}

const _iosAllowPermissionLabels = [
  'Allow',
  'OK',
  'Allow Once',
  'Allow While Using App',
  'Allow While Using the App',
  '允许',
  '好',
  '允许一次',
  '使用App时允许',
  '使用应用期间允许',
  '仅在使用中允许',
];

const _iosDenyPermissionLabels = [
  "Don’t Allow",
  "Don't Allow",
  'Deny',
  'Not Now',
  'Cancel',
  '不允许',
  '拒绝',
  '暂不',
  '取消',
];

Future<AutomationScenarioActionResult> _assertIosLog(
  AutomationScenarioAction action,
  _ScenarioExecutionContext context,
) async {
  final expected = action.text ?? action.value;
  if (expected == null || expected.isEmpty) {
    return _failedAction(action, 'assertLog requires text, contains, or value');
  }
  final output = await _readOptionalFile(context.outputLog);
  if (output == null) {
    return _failedAction(
      action,
      'iOS flutter run output log is missing',
      repairHints: [
        ...action.repairHints,
        'Run automate on iOS so fluoh can capture the flutter run output log.',
      ],
    );
  }
  if (!_matches(output, expected, action.match)) {
    return _failedAction(
      action,
      'iOS flutter run output did not contain $expected',
      details: {
        'source': 'flutterRunOutput',
        'path': context.outputLog!.path,
        'tail': _tail(output),
      },
      repairHints: [
        ...action.repairHints,
        'Emit a stable structured print or platform log marker for this scenario result.',
      ],
    );
  }
  return _passedAction(
    action,
    details: {
      'source': 'flutterRunOutput',
      'path': context.outputLog!.path,
      'tail': _tail(output),
    },
  );
}

Future<AutomationScenarioActionResult> _withOhosToolchain(
  AutomationScenarioAction action,
  _ScenarioExecutionContext context,
  Future<AutomationScenarioActionResult> Function(
    Future<_ToolRun> Function(List<String> args) hdcRun,
  )
  body,
) async {
  late final OhosToolchain toolchain;
  try {
    toolchain = await locateOhosToolchain(
      environment: context.environment.processEnvironment,
    );
  } on Object catch (error) {
    return _failedAction(action, error.toString());
  }

  Future<_ToolRun> hdcRun(List<String> args) {
    return _runTool(
      toolchain.hdc.path,
      ['-t', context.targetId!, ...args],
      environment: context.environment.processEnvironment,
      workingDirectory: context.environment.workingDirectory,
      timeout: action.timeout,
    );
  }

  return body(hdcRun);
}

Future<AutomationScenarioActionResult> _runOhosTextAction(
  AutomationScenarioAction action,
  Future<_ToolRun> Function(List<String> args) hdcRun,
) async {
  final labels = _actionLabels(action);
  if (labels.isEmpty) {
    return _failedAction(action, '${action.action} requires text or labels');
  }
  final deadline = DateTime.now().add(action.timeout);
  OhosUiNode? node;
  var lastDump = '';
  do {
    final dump = await _ohosUiDump(hdcRun);
    if (dump.exitCode != 0) {
      return _failedAction(
        action,
        'Could not dump OHOS UI',
        command: dump.command,
        details: dump.toDetails(),
        repairHints: action.repairHints,
      );
    }
    lastDump = dump.stdout;
    late final List<OhosUiNode> nodes;
    try {
      nodes = parseOhosUiNodes(dump.stdout);
    } on Object catch (error) {
      return _failedAction(
        action,
        'Could not parse OHOS UI dump',
        command: dump.command,
        details: {
          'error': error.toString(),
          'uiDumpTail': _tail(dump.stdout),
          ...dump.toDetails(),
        },
        repairHints: [
          ...action.repairHints,
          'Confirm `hdc shell uitest dumpLayout` writes a JSON layout file on this target.',
        ],
      );
    }
    node = _findOhosUiNode(nodes, labels, match: action.match);
    if (node != null) {
      break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  } while (DateTime.now().isBefore(deadline));

  if (node == null) {
    return _failedAction(
      action,
      'No OHOS UI node matched ${labels.join(', ')}',
      details: {
        'labels': labels,
        'match': action.match,
        'uiDumpTail': _tail(lastDump),
      },
      repairHints: [
        ...action.repairHints,
        'Expose stable visible text, component text, key, or id in the OHOS UI tree.',
      ],
    );
  }
  if (action.action == 'waitText' || action.action == 'assertText') {
    return _passedAction(
      action,
      details: {
        'matchedText': node.label,
        'bounds': node.bounds.toJson(),
        if (node.id != null) 'id': node.id,
        if (node.key != null) 'key': node.key,
      },
    );
  }
  final x = node.bounds.centerX;
  final y = node.bounds.centerY;
  final result = await hdcRun([
    'shell',
    'uitest',
    'uiInput',
    'click',
    '$x',
    '$y',
  ]);
  return _processActionResult(
    action,
    result,
    result.command,
    details: {
      'matchedText': node.label,
      'bounds': node.bounds.toJson(),
      if (node.id != null) 'id': node.id,
      if (node.key != null) 'key': node.key,
    },
  );
}

Future<AutomationScenarioActionResult> _tapOhosPermission(
  AutomationScenarioAction action,
  Future<_ToolRun> Function(List<String> args) hdcRun, {
  required bool allow,
}) async {
  final labels = [
    ...action.labels,
    if (action.text != null) action.text!,
    if (allow) ..._ohosAllowPermissionLabels,
    if (!allow) ..._ohosDenyPermissionLabels,
  ];
  final result = await _runOhosTextAction(
    AutomationScenarioAction(
      action: 'tapText',
      index: action.index,
      text: action.text,
      labels: labels,
      match: action.match == 'contains' ? 'exact' : action.match,
      timeout: action.timeout,
      optional: action.optional,
      repairHints: [
        ...action.repairHints,
        if (allow)
          'Trigger the OHOS runtime permission request before the allowPermission scenario step.',
        if (!allow)
          'Trigger the OHOS runtime permission request before the denyPermission scenario step.',
      ],
    ),
    hdcRun,
  );
  return AutomationScenarioActionResult(
    index: action.index,
    action: action.action,
    status: result.status,
    command: result.command,
    reason: result.reason,
    details: {
      ...result.details,
      'labels': labels,
      'permissionAction': allow ? 'allow' : 'deny',
    },
    repairHints: result.repairHints,
  );
}

const _ohosAllowPermissionLabels = [
  'permission_dialog_allow_button',
  '本次使用允许',
  '仅使用期间允许',
  '允许',
  'Allow',
  'OK',
  '始终允许',
  '使用期间允许',
  '仅在使用中允许',
];

const _ohosDenyPermissionLabels = [
  'permission_dialog_deny_button',
  '不允许',
  '拒绝',
  'Deny',
  "Don't allow",
  "Don’t allow",
];

Future<_ToolRun> _ohosUiDump(
  Future<_ToolRun> Function(List<String> args) hdcRun,
) async {
  final dump = await hdcRun(const ['shell', 'uitest', 'dumpLayout']);
  if (dump.exitCode != 0) {
    return dump;
  }
  final path = RegExp(
    r'DumpLayout saved to:(\S+)',
  ).firstMatch(dump.stdout)?.group(1);
  if (path == null || path.isEmpty) {
    return _ToolRun(
      command: dump.command,
      exitCode: 1,
      stdout: dump.stdout,
      stderr: 'Could not find OHOS dumpLayout output path.',
    );
  }
  return hdcRun(['shell', 'cat', path]);
}

Future<AutomationScenarioActionResult> _assertOhosLog(
  AutomationScenarioAction action,
  _ScenarioExecutionContext context,
) async {
  final expected = action.text ?? action.value;
  if (expected == null || expected.isEmpty) {
    return _failedAction(action, 'assertLog requires text or value');
  }

  final captured = await _readOptionalFile(context.hilog);
  if (captured != null && _matches(captured, expected, action.match)) {
    return _passedAction(
      action,
      details: {
        'source': 'capturedHilog',
        'path': context.hilog!.path,
        'tail': _tail(captured),
      },
    );
  }

  late final OhosToolchain toolchain;
  try {
    toolchain = await locateOhosToolchain(
      environment: context.environment.processEnvironment,
    );
  } on Object catch (error) {
    return _failedAction(action, error.toString());
  }

  final args = ['-t', context.targetId!, 'shell', 'hilog', '-x', '-z', '1000'];
  final deadline = DateTime.now().add(action.timeout);
  _ToolRun? lastResult;
  do {
    lastResult = await _runTool(
      toolchain.hdc.path,
      args,
      environment: context.environment.processEnvironment,
      workingDirectory: context.environment.workingDirectory,
    );
    if (lastResult.exitCode == 0 &&
        _matches(lastResult.stdout, expected, action.match)) {
      return _passedAction(
        action,
        command: lastResult.command,
        details: {
          'source': 'liveHilog',
          'tail': _tail(lastResult.stdout),
          ...lastResult.toDetails(),
        },
      );
    }
    if (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  } while (DateTime.now().isBefore(deadline));

  return _failedAction(
    action,
    'OHOS hilog did not contain $expected',
    command: lastResult.command,
    details: {
      if (captured != null && context.hilog != null) ...{
        'capturedPath': context.hilog!.path,
        'capturedTail': _tail(captured),
      },
      'liveTail': _tail(lastResult.stdout),
      ...lastResult.toDetails(),
    },
    repairHints: [
      ...action.repairHints,
      'Emit a stable structured log marker for this scenario result.',
    ],
  );
}

Future<AutomationScenarioActionResult> _assertSession(
  AutomationScenarioAction action,
  _ScenarioExecutionContext context,
) async {
  final file = context.sessionFile;
  if (file == null || !await file.exists()) {
    return _failedAction(
      action,
      'flutterRunSession file is missing',
      repairHints: [
        'Run automate on Android or iOS, or pass --session-dir so fluoh can write the session file.',
      ],
    );
  }
  final decoded = jsonDecode(await file.readAsString());
  if (decoded is! Map<String, Object?>) {
    return _failedAction(action, 'flutterRunSession is not a JSON object');
  }
  final expected = action.value ?? action.text;
  if (expected != null && decoded['status'] != expected) {
    return _failedAction(
      action,
      'flutterRunSession status was ${decoded['status']}, expected $expected',
      details: {'sessionFile': file.path, 'session': decoded},
      repairHints: action.repairHints,
    );
  }
  return _passedAction(
    action,
    details: {'sessionFile': file.path, 'session': decoded},
  );
}

Future<AutomationScenarioActionResult> _waitAction(
  AutomationScenarioAction action,
) async {
  await Future<void>.delayed(action.timeout);
  return _passedAction(
    action,
    details: {'waitSeconds': action.timeout.inSeconds},
  );
}

Future<String?> _readOptionalFile(File? file) async {
  if (file == null || !await file.exists()) {
    return null;
  }
  return file.readAsString();
}

AutomationScenarioActionResult _processActionResult(
  AutomationScenarioAction action,
  _ToolRun result,
  String command, {
  Map<String, Object?> details = const {},
}) {
  if (result.exitCode == 0) {
    return _passedAction(
      action,
      command: command,
      details: {...details, ...result.toDetails()},
    );
  }
  return _failedAction(
    action,
    'Command failed with exit code ${result.exitCode}',
    command: command,
    details: {...details, ...result.toDetails()},
    repairHints: action.repairHints,
  );
}

AutomationScenarioActionResult _passedAction(
  AutomationScenarioAction action, {
  String? command,
  Map<String, Object?> details = const {},
}) {
  return AutomationScenarioActionResult(
    index: action.index,
    action: action.action,
    status: 'passed',
    command: command,
    details: details,
  );
}

AutomationScenarioActionResult _failedAction(
  AutomationScenarioAction action,
  String reason, {
  String? command,
  Map<String, Object?> details = const {},
  List<String> repairHints = const [],
}) {
  return AutomationScenarioActionResult(
    index: action.index,
    action: action.action,
    status: 'failed',
    command: command,
    reason: reason,
    details: details,
    repairHints: repairHints.isEmpty ? action.repairHints : repairHints,
  );
}

List<String> _actionLabels(AutomationScenarioAction action) {
  return [
    if (action.text != null && action.text!.trim().isNotEmpty)
      action.text!.trim(),
    ...action.labels,
  ];
}

_GestureCoordinates? _tapCoordinates(AutomationScenarioAction action) {
  final x = action.x;
  final y = action.y;
  if (x == null || y == null) {
    return null;
  }
  return _GestureCoordinates(
    x: x,
    y: y,
    endX: x,
    endY: y,
    durationMilliseconds: action.durationMilliseconds,
  );
}

_GestureCoordinates? _swipeCoordinates(AutomationScenarioAction action) {
  final x = action.x;
  final y = action.y;
  final endX = action.endX;
  final endY = action.endY;
  if (x == null || y == null || endX == null || endY == null) {
    return null;
  }
  return _GestureCoordinates(
    x: x,
    y: y,
    endX: endX,
    endY: endY,
    durationMilliseconds: action.durationMilliseconds,
  );
}

class _GestureCoordinates {
  const _GestureCoordinates({
    required this.x,
    required this.y,
    required this.endX,
    required this.endY,
    this.durationMilliseconds,
  });

  final int x;
  final int y;
  final int endX;
  final int endY;
  final int? durationMilliseconds;

  Map<String, Object?> toJson() {
    return {
      'x': x,
      'y': y,
      'endX': endX,
      'endY': endY,
      if (durationMilliseconds != null)
        'durationMilliseconds': durationMilliseconds,
    };
  }
}

bool _matches(String value, String pattern, String match) {
  return switch (match) {
    'exact' => value == pattern,
    'regex' => RegExp(pattern).hasMatch(value),
    _ => value.contains(pattern),
  };
}

String _tail(String value, {int maxLength = 4000}) {
  if (value.length <= maxLength) {
    return value;
  }
  return value.substring(value.length - maxLength);
}

String _androidInputText(String value) {
  return value
      .replaceAll(r'\', r'\\')
      .replaceAll(' ', '%s')
      .replaceAll('&', r'\&')
      .replaceAll('<', r'\<')
      .replaceAll('>', r'\>');
}

/// Android UI node parsed from UIAutomator XML.
class AndroidUiNode {
  /// Creates an Android UI node.
  const AndroidUiNode({
    required this.label,
    required this.bounds,
    this.resourceId,
  });

  /// Text, content description, resource id, or resource id suffix.
  final String label;

  /// Node bounds.
  final AndroidBounds bounds;

  /// Resource id, when exposed by UIAutomator.
  final String? resourceId;
}

/// Android UI node bounds.
class AndroidBounds {
  /// Creates Android UI bounds.
  const AndroidBounds({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  /// Left coordinate.
  final int left;

  /// Top coordinate.
  final int top;

  /// Right coordinate.
  final int right;

  /// Bottom coordinate.
  final int bottom;

  /// Horizontal center coordinate.
  int get centerX => ((left + right) / 2).round();

  /// Vertical center coordinate.
  int get centerY => ((top + bottom) / 2).round();

  /// Converts bounds to JSON.
  Map<String, Object?> toJson() {
    return {
      'left': left,
      'top': top,
      'right': right,
      'bottom': bottom,
      'centerX': centerX,
      'centerY': centerY,
    };
  }
}

/// Parses UIAutomator XML into text-addressable nodes.
List<AndroidUiNode> parseAndroidUiNodes(String xml) {
  final nodes = <AndroidUiNode>[];
  for (final match in RegExp(r'<node\b[^>]*>').allMatches(xml)) {
    final attrs = _xmlAttributes(match.group(0)!);
    final bounds = _parseAndroidBounds(attrs['bounds']);
    if (bounds == null) {
      continue;
    }
    final resourceId = _nonEmptyString(attrs['resource-id']);
    final labels = <String>{
      ?_nonEmptyString(attrs['text']),
      ?_nonEmptyString(attrs['content-desc']),
      if (resourceId != null && resourceId.contains('/'))
        resourceId.split('/').last,
      ?resourceId,
    };
    for (final label in labels) {
      nodes.add(
        AndroidUiNode(label: label, bounds: bounds, resourceId: resourceId),
      );
    }
  }
  return nodes;
}

AndroidUiNode? _findAndroidUiNode(
  List<AndroidUiNode> nodes,
  List<String> labels, {
  required String match,
}) {
  for (final label in labels) {
    for (final node in nodes) {
      if (_matches(node.label, label, match)) {
        return node;
      }
    }
  }
  return null;
}

Map<String, String> _xmlAttributes(String source) {
  return {
    for (final match in RegExp(
      r'([a-zA-Z0-9_-]+)="([^"]*)"',
    ).allMatches(source))
      match.group(1)!: _xmlUnescape(match.group(2)!),
  };
}

String _xmlUnescape(String value) {
  return value
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');
}

AndroidBounds? _parseAndroidBounds(String? value) {
  if (value == null) {
    return null;
  }
  final match = RegExp(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]').firstMatch(value);
  if (match == null) {
    return null;
  }
  return AndroidBounds(
    left: int.parse(match.group(1)!),
    top: int.parse(match.group(2)!),
    right: int.parse(match.group(3)!),
    bottom: int.parse(match.group(4)!),
  );
}

/// OHOS UI node parsed from `uitest dumpLayout` JSON.
class OhosUiNode {
  /// Creates an OHOS UI node.
  const OhosUiNode({
    required this.label,
    required this.bounds,
    this.id,
    this.key,
  });

  /// Text, original text, description, id, or key.
  final String label;

  /// Node bounds.
  final OhosBounds bounds;

  /// Component id, when exposed.
  final String? id;

  /// Component key, when exposed.
  final String? key;
}

/// OHOS UI node bounds.
class OhosBounds {
  /// Creates OHOS UI bounds.
  const OhosBounds({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  /// Left coordinate.
  final int left;

  /// Top coordinate.
  final int top;

  /// Right coordinate.
  final int right;

  /// Bottom coordinate.
  final int bottom;

  /// Horizontal center coordinate.
  int get centerX => ((left + right) / 2).round();

  /// Vertical center coordinate.
  int get centerY => ((top + bottom) / 2).round();

  /// Converts bounds to JSON.
  Map<String, Object?> toJson() {
    return {
      'left': left,
      'top': top,
      'right': right,
      'bottom': bottom,
      'centerX': centerX,
      'centerY': centerY,
    };
  }
}

/// Parses OHOS `uitest dumpLayout` JSON into text-addressable nodes.
List<OhosUiNode> parseOhosUiNodes(String source) {
  final decoded = jsonDecode(source);
  final nodes = <OhosUiNode>[];

  void visit(Object? value) {
    if (value is! Map) {
      return;
    }
    final attributes = value['attributes'];
    if (attributes is Map) {
      final stringAttributes = <String, String>{
        for (final entry in attributes.entries)
          if (entry.key is String && entry.value != null)
            entry.key as String: entry.value.toString(),
      };
      final bounds = _parseOhosBounds(stringAttributes['bounds']);
      if (bounds != null) {
        final id = _nonEmptyString(stringAttributes['id']);
        final key = _nonEmptyString(stringAttributes['key']);
        final labels = <String>{
          ?_nonEmptyString(stringAttributes['text']),
          ?_nonEmptyString(stringAttributes['originalText']),
          ?_nonEmptyString(stringAttributes['description']),
          ?id,
          ?key,
        };
        for (final label in labels) {
          nodes.add(OhosUiNode(label: label, bounds: bounds, id: id, key: key));
        }
      }
    }
    final children = value['children'];
    if (children is List) {
      for (final child in children) {
        visit(child);
      }
    }
  }

  visit(decoded);
  return nodes;
}

OhosUiNode? _findOhosUiNode(
  List<OhosUiNode> nodes,
  List<String> labels, {
  required String match,
}) {
  for (final label in labels) {
    for (final node in nodes) {
      if (_matches(node.label, label, match)) {
        return node;
      }
    }
  }
  return null;
}

OhosBounds? _parseOhosBounds(String? value) {
  if (value == null) {
    return null;
  }
  final match = RegExp(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]').firstMatch(value);
  if (match == null) {
    return null;
  }
  return OhosBounds(
    left: int.parse(match.group(1)!),
    top: int.parse(match.group(2)!),
    right: int.parse(match.group(3)!),
    bottom: int.parse(match.group(4)!),
  );
}

String? _nonEmptyString(String? value) {
  if (value == null) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

Future<File?> _androidAdb(Map<String, String> environment) async {
  final configured = environment['FLUOH_ANDROID_ADB']?.trim();
  if (configured != null && configured.isNotEmpty) {
    final file = File(configured);
    return await file.exists() ? file : null;
  }
  final sdkRoot = _androidSdkRootPath(environment);
  if (sdkRoot != null && sdkRoot.isNotEmpty) {
    final file = File('$sdkRoot/platform-tools/adb');
    if (await file.exists()) {
      return file;
    }
  }
  final result = await Process.run('which', const ['adb']);
  if (result.exitCode == 0) {
    final path = result.stdout.toString().trim();
    if (path.isNotEmpty) {
      return File(path);
    }
  }
  return null;
}

String? _androidSdkRootPath(Map<String, String> environment) {
  for (final key in const ['ANDROID_SDK_ROOT', 'ANDROID_HOME']) {
    final value = environment[key]?.trim();
    if (value != null && value.isNotEmpty) {
      return value;
    }
  }
  final home = environment['HOME']?.trim();
  if (home != null && home.isNotEmpty) {
    return '$home/Library/Android/sdk';
  }
  return null;
}

Future<File?> _xcrun(Map<String, String> environment) async {
  final configured = environment['FLUOH_XCRUN']?.trim();
  if (configured != null && configured.isNotEmpty) {
    final file = File(configured);
    return await file.exists() ? file : null;
  }
  final result = await Process.run('which', const ['xcrun']);
  if (result.exitCode == 0) {
    final path = result.stdout.toString().trim();
    if (path.isNotEmpty) {
      return File(path);
    }
  }
  return null;
}

Future<File?> _openSimulatorTool(Map<String, String> environment) async {
  final configured = environment['FLUOH_OPEN']?.trim();
  if (configured != null && configured.isNotEmpty) {
    final file = File(configured);
    return await file.exists() ? file : null;
  }
  final configuredXcrun = environment['FLUOH_XCRUN']?.trim();
  if (configuredXcrun != null && configuredXcrun.isNotEmpty) {
    return null;
  }
  if (!Platform.isMacOS) {
    return null;
  }
  final systemOpen = File('/usr/bin/open');
  if (await systemOpen.exists()) {
    return systemOpen;
  }
  final result = await Process.run('which', const ['open']);
  if (result.exitCode == 0) {
    final path = result.stdout.toString().trim();
    if (path.isNotEmpty) {
      return File(path);
    }
  }
  return null;
}

Future<_IosXcodebuildTool?> _iosXcodebuild(
  Map<String, String> environment,
) async {
  final configured = environment['FLUOH_XCODEBUILD']?.trim();
  if (configured != null && configured.isNotEmpty) {
    final file = File(configured);
    return await file.exists()
        ? _IosXcodebuildTool(executable: file, prefixArguments: const [])
        : null;
  }
  final xcrun = await _xcrun(environment);
  if (xcrun != null) {
    return _IosXcodebuildTool(
      executable: xcrun,
      prefixArguments: const ['xcodebuild'],
    );
  }
  final result = await Process.run('which', const ['xcodebuild']);
  if (result.exitCode == 0) {
    final path = result.stdout.toString().trim();
    if (path.isNotEmpty) {
      return _IosXcodebuildTool(
        executable: File(path),
        prefixArguments: const [],
      );
    }
  }
  return null;
}

class _IosXcodebuildTool {
  const _IosXcodebuildTool({
    required this.executable,
    required this.prefixArguments,
  });

  final File executable;
  final List<String> prefixArguments;
}

Future<_ToolRun> _runTool(
  String executable,
  List<String> arguments, {
  required Map<String, String> environment,
  required Directory workingDirectory,
  Duration timeout = const Duration(seconds: 30),
}) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory.path,
    environment: environment,
  );
  final stdoutBuffer = StringBuffer();
  final stderrBuffer = StringBuffer();
  final stdoutDone = _collectToolOutput(process.stdout, stdoutBuffer);
  final stderrDone = _collectToolOutput(process.stderr, stderrBuffer);
  var timedOut = false;
  final exitCode = await process.exitCode.timeout(
    timeout,
    onTimeout: () async {
      timedOut = true;
      process.kill();
      try {
        return await process.exitCode.timeout(const Duration(seconds: 5));
      } on TimeoutException {
        if (!Platform.isWindows) {
          process.kill(ProcessSignal.sigkill);
        }
        return 124;
      }
    },
  );
  try {
    await Future.wait([
      stdoutDone,
      stderrDone,
    ]).timeout(const Duration(seconds: 2));
  } on TimeoutException {
    // The process has been signalled; return the timeout diagnostic instead of
    // blocking the automation loop on unclosed pipes.
  }
  return _ToolRun(
    command: '$executable ${arguments.join(' ')}',
    exitCode: timedOut ? 124 : exitCode,
    stdout: stdoutBuffer.toString(),
    stderr: timedOut && stderrBuffer.toString().trim().isEmpty
        ? 'Command timed out.'
        : stderrBuffer.toString(),
  );
}

Future<void> _collectToolOutput(
  Stream<List<int>> stream,
  StringBuffer buffer,
) async {
  await for (final chunk in stream.transform(utf8.decoder)) {
    buffer.write(chunk);
  }
}

class _ToolRun {
  const _ToolRun({
    required this.command,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final String command;
  final int exitCode;
  final String stdout;
  final String stderr;

  Map<String, Object?> toDetails() {
    return {
      'exitCode': exitCode,
      if (stdout.trim().isNotEmpty) 'stdoutTail': _tail(stdout),
      if (stderr.trim().isNotEmpty) 'stderrTail': _tail(stderr),
    };
  }
}
