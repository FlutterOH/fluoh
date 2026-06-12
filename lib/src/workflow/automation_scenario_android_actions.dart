part of 'automation_scenario.dart';

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
