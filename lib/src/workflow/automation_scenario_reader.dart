part of 'automation_scenario.dart';

/// Reads an automation scenario file from YAML, Markdown, or JSON.
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
  final stepsValue = json['steps'];
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
