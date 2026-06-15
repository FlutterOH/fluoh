part of 'automation_scenario.dart';

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
        source.contains('steps:')) {
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
    outputPath:
        optionalString(json, 'outputPath') ??
        optionalString(json, 'path') ??
        optionalString(json, 'file'),
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
      interactionStep: action.index,
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
    interactionStep:
        _optionalInt(json['interactionStep']) ??
        _optionalInt(json['actionStep']),
    assertionStep:
        _optionalInt(json['assertionStep']) ??
        _optionalInt(json['verificationStep']),
    evidenceSteps: _intList(json['evidenceSteps'] ?? json['steps']),
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

List<int> _intList(Object? value) {
  if (value is List) {
    final values = <int>[];
    for (final item in value) {
      final parsed = _optionalInt(item);
      if (parsed != null) {
        values.add(parsed);
      }
    }
    return values;
  }
  if (_optionalInt(value) case final parsed?) {
    return [parsed];
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
