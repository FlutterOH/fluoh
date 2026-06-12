part of 'automation_scenario.dart';

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
