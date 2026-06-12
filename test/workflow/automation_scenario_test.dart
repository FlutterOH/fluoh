import 'dart:io';

import 'package:fluoh/src/workflow/automation_scenario.dart';
import 'package:test/test.dart';

void main() {
  test('reads markdown scenarios with steps and coverage', () async {
    final root = await Directory.systemTemp.createTemp('fluoh_scenario_test_');
    addTearDown(() => root.delete(recursive: true));
    final file = File('${root.path}/camera-flow.md');
    await file.writeAsString('''
# Camera flow

```yaml
name: Camera flow
platform: ohos
steps:
  - action: assertText
    text: Camera ready
coverage:
  - category: publicApi
    item: CameraController
    path: success
```
''');

    final scenario = await readAutomationScenario(file, workingDirectory: root);

    expect(scenario.name, 'Camera flow');
    expect(scenario.platform, 'ohos');
    expect(scenario.steps.single.action, 'assertText');
    expect(scenario.steps.single.text, 'Camera ready');
    expect(scenario.coverage.single.item, 'CameraController');
  });

  test('rejects actions aliases in scenario files', () async {
    final root = await Directory.systemTemp.createTemp('fluoh_scenario_test_');
    addTearDown(() => root.delete(recursive: true));
    final file = File('${root.path}/actions_alias.yaml');
    await file.writeAsString('''
platform: android
actions:
  - action: assertText
    text: Ready
''');

    expect(
      readAutomationScenario(file, workingDirectory: root),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('must contain steps'),
        ),
      ),
    );
  });
}
