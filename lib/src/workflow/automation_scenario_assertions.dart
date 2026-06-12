part of 'automation_scenario.dart';

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
        'Run drive on Android or iOS, or pass --session-dir so fluoh can write the session file.',
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

Future<AutomationScenarioActionResult> _assertOhosSession(
  AutomationScenarioAction action,
  _ScenarioExecutionContext context,
) async {
  final expected = action.value ?? action.text;
  final captured = await _readOptionalFile(context.hilog);
  final launchInfo = {
    if (context.ohosBundleName != null) 'bundleName': context.ohosBundleName,
    if (context.ohosAbilityName != null) 'abilityName': context.ohosAbilityName,
    if (context.targetId != null) 'targetId': context.targetId,
  };
  if (expected != null && expected.isNotEmpty) {
    final launchText = jsonEncode(launchInfo);
    if (!_matches(launchText, expected, action.match) &&
        (captured == null || !_matches(captured, expected, action.match))) {
      return _failedAction(
        action,
        'OHOS run evidence did not contain $expected',
        details: {
          'launchInfo': launchInfo,
          if (context.hilog != null) 'hilog': context.hilog!.path,
          if (captured != null) 'hilogTail': _tail(captured),
        },
        repairHints: [
          ...action.repairHints,
          'Assert a value present in OHOS launchInfo or emit a stable hilog marker.',
        ],
      );
    }
  }
  return _passedAction(
    action,
    details: {
      'source': 'ohosRunEvidence',
      'launchInfo': launchInfo,
      if (context.hilog != null) 'hilog': context.hilog!.path,
      if (captured != null) 'hilogTail': _tail(captured),
    },
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
