# fluoh Interaction Scenario

Use this template for `.fluoh/scenarios/<package-or-app>/<platform>-<name>.md`
when a device-side functional flow cannot be fully covered by `integration_test/`.
The goal is functional correctness, not visual appearance, unless the package
is specifically visual.

## Metadata

- Scope:
- Package or app:
- Platform: ohos | android | ios | macos
- Target requirement: emulator | simulator | device | host
- Required local tools:
- Observation mode: integration_test | flutter-debug | widget-tree | semantics-tree | accessibility | visible-text | log-marker | screenshot-optional
- Related command:
- Session file command, when supported:
- Session inspect command, when supported:

## Preconditions

- Selected FlutterOH SDK:
- Example path:
- Required permissions:
- Required test files, fixtures, media, URLs, accounts, or local services:
- Required Flutter debug output, widget/component state, semantic labels, visible status text, test keys, or log markers:
- Network requirement: none | local | internet

## Scenario

| Step | Action | Expected result | Evidence |
| --- | --- | --- | --- |
| 1 | Launch the example screen | Ready state or functional status is observable | Flutter debug output, widget/semantics tree, visible text, semantic label, accessibility dump, or log marker |
| 2 | ... | ... | ... |

## Assertions

- Functional success state:
- Flutter debug, widget/component tree, semantics tree, accessibility text, or log marker assertion:
- Error state checked:
- Permission result checked:
- Output file, media, location, callback, or platform result checked:

## Failure Routing

- If a permission prompt does not appear:
- If a picker, camera, map, media, or external app cannot open:
- If the app crashes or freezes:
- If the local target cannot provide this capability:

## Evidence To Record

- Device, emulator, simulator, or host id:
- Text, semantic, accessibility, structured log, or test assertion evidence:
- flutterRunSession JSON status, VM Service URI, or attach result:
- Screenshots or screen recordings, optional:
- HAP/APK/app build path when relevant:
- Hilog or run output path:
- Actual result:
- Release impact: ready | needs maintainer decision | blocked
