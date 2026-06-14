# fluoh Interaction Scenario

Use this template for `.fluoh/scenarios/<package-or-app>/<platform>-<name>.md`
when a device-side functional flow cannot be fully covered by `integration_test/`.
The goal is functional correctness, not visual appearance, unless the package
is specifically visual.

## Metadata

- Scope:
- Package or app:
- Platform: ohos | android | ios | macos | linux | web | windows
- Target requirement: emulator | simulator | device | host | browser
- Required local tools:
- Observation mode: integration_test | flutter-debug | widget-tree |
  semantics-tree | accessibility | visible-text | log-marker |
  screenshot-supporting
- Related command:
- Session file command, when supported:
- Session inspect command, when supported:
- Session attach command, when supported:

## Preconditions

- Selected FlutterOH SDK:
- Example path:
- Required permissions:
- Required test files, fixtures, media, URLs, accounts, or local services:
- Required Flutter debug output, widget/component state, semantic labels,
  visible status text, test keys, or log markers:
- Network requirement: none | local | internet

## Coverage Matrix

List every package capability this scenario covers. For any capability category,
write one row for every exposed or requestable item on every supported platform,
and add separate rows for grant, deny, success, failure, or error paths when the
package reports different states. Do not sample a representative item when the
package exposes more.

| Category | Item | Path | Status | Evidence |
| --- | --- | --- | --- | --- |
| publicApi | ExampleController | success | covered | Scenario drives the API through the example and asserts status/log output |
| publicApi | formatValue | error | covered | Scenario or integration test asserts invalid-input handling |
| methodChannel | openPicker | error | notApplicable | Covered by a package test because the host callback is mocked |
| platformChannel | sample/events | success | blocked | Repair item: add native stream fixture or scenario evidence |
| exampleFlow | main | success | covered | Launch and assertion prove the example entry point works |
| permission | camera | grant | covered | Scenario action and log/status assertion |
| permission | camera | deny | covered | Scenario action and denied status assertion |
| permission | photos | grant | blocked | Repair item: use a target/profile that exposes the permission, or mark notApplicable only if the platform has no such behavior |

Status must be one of `covered`, `notApplicable`, or `blocked`.
`notApplicable` rows must include a non-empty `note` or `reason` explaining why
the behavior does not exist on this platform. `blocked` rows are repair backlog,
not release-ready coverage.
`fluoh drive --dry-run --json` reports these rows under
`automation.coveragePolicy.scenarioCoverage` and also emits
`coverageSummary`, `inventory`, `capabilityCoverage`,
`manifestPermissionCoverage`, `pathCoverage`, `scenarioEvidence`,
`qualityGates`, and `repairLoop` so the AI loop can detect missing rows,
generic capability gaps, manifest permissions, low test coverage, missing
assertions, and behavior-path gaps, patch the smallest surface, rerun the same
command, and refresh the matrix.
`inventory.tests.coverageBaseline` flags missing, weak, or low package tests
before the scenario matrix is considered release-ready. Weak package tests are
existing tests that leave one or more `missingDeclarations` from their matching
library file unexercised; naming a declaration only in a string, description,
or expected log marker is not enough.
`capabilityCoverage` lists discovered public API entries from top-level library
files and local exports, top-level functions, getters, variables, platform
channel declarations and calls, and example entry points. Copy its
`suggestedCoverage` rows into the scenario or mark the row `notApplicable`
only when that capability does not exist on the selected platform.
`manifestPermissionCoverage` lists each selected-platform manifest permission,
its normalized `coverageItem`, and suggested coverage rows when grant/success
or denied/error paths are missing. Each applicable `category`/`item` should
include both a successful path and a denied, cancelled, failure, or error path;
use `notApplicable` only when a path does not exist on the selected platform.
Every scenario with `covered` rows should include at least one tool-readable
verification action such as `assertText`, `waitText`, `assertLog`, or
`assertSession`; clicks alone are not evidence. Scenarios whose rows are only
`notApplicable` do not need runtime assertions, but those rows still need
concrete reasons. Scenarios with `blocked` rows should stay in the repair queue.

## Scenario

| Step | Action | Expected result | Evidence |
| --- | --- | --- | --- |
| 1 | Launch the example screen | Ready state or functional status is observable | Debug output, widget/semantics tree, visible text, accessibility dump, or log marker |
| 2 | ... | ... | ... |

## Executable Automation Block

When the flow can be operated by `fluoh drive`, keep one YAML block in this
file and run it with:

```sh
fluoh drive <platform> --package <name> --scenario <this-file> --json
```

```yaml
kind: fluoh.automationScenario
schema: 1
name: permission happy path
platform: android
coverage:
  - category: permission
    item: camera
    path: grant
  - category: permission
    item: camera
    path: deny
steps:
  - action: tapText
    labels: [Open camera]
    repairHints:
      - Expose a stable visible label, semantics label, or log marker for the trigger.
  - action: allowPermission
    labels: [Allow]
    repairHints:
      - Trigger the runtime permission request before this step.
  - action: assertLog
    contains: camera permission granted
    repairHints:
      - Emit a structured app log marker after the permission result is handled.
  - action: assertSession
    status: passed
```

Supported first-pass actions:

- Android: `clearAppData`, `launchApp`, coordinate `tap`, `swipe`, `drag`,
  `tapText`, `waitText`, `assertText`, `allowPermission`, `denyPermission`,
  `inputText`, `press`, `captureScreenshot`/`screenshot`, `assertLog`,
  `assertSession`, `wait`.
  Text actions match UIAutomator text, content description, resource id, or
  resource id suffix. Screenshot actions save a local file under
  `.fluoh/evidence/screenshots/`; custom `outputPath` may be a file name such
  as `main.png` or a relative path that stays inside that directory.
- iOS: `resetPermission`, coordinate `tap`, `swipe`, `drag`, `tapText`,
  `waitText`, `assertText`, `allowPermission`, `denyPermission`,
  `captureScreenshot`/`screenshot`, `assertLog`, `assertSession`, `wait`.
  `resetPermission` uses `xcrun simctl privacy` and requires `bundleId` plus
  `permission`. `tapText`, `waitText`, and `assertText` use the built-in XCTest
  runner to match app UI by label, identifier, or value. Coordinate `tap`,
  `swipe`, and `drag` also use the built-in XCTest runner and require
  `bundleId`. Prefer `assertText`, `waitText`, and `assertSession` for state
  produced by post-launch UI interactions; bounded Flutter run log capture may
  not include `debugPrint` output emitted after scenario actions. `assertLog`
  checks captured Flutter run output and is best for startup markers or other
  output known to be inside the captured log window. For
  repeatable simulator runs, prefer
  `fluoh drive ios --auto-emulator`; iOS auto-emulator selection
  prefers iPhone simulators over iPad simulators and waits for
  `xcrun simctl bootstatus <udid> -b` after startup. `allowPermission` and
  `denyPermission` click the
  visible system permission prompt through the same runner when `bundleId` is
  present. The runner uses Xcode/`xcodebuild` and writes a temporary helper
  project under `.fluoh/cache/automation/ios-xctest`. If XCTest cannot run
  in the current environment, record that blocker instead of treating the
  package behavior as fixed.
- OHOS: `clearAppData`, `launchApp`, coordinate `tap`, `swipe`, `drag`,
  `tapText`, `waitText`, `assertText`, `allowPermission`, `denyPermission`,
  `captureScreenshot`/`screenshot`, `assertLog`, and `wait`.
  `assertLog` checks captured or live hilog.
  Text and permission actions use `uitest dumpLayout` visible/component text,
  original text, description, id, or key.
  `launchApp` accepts `bundleId` or `packageName` and optional `abilityName`
  (defaults to `EntryAbility`).

For Android and iOS, prefer visible text, semantic labels, or session status
over post-action log markers whenever the scenario needs to prove a tap, swipe,
permission result, or form submission changed app state. Use `assertLog` only
when the relevant marker is guaranteed to be present in the captured run output.
Use screenshots as supporting evidence for inspection or handoff, not as the
primary pass/fail assertion unless the package is specifically visual.
After a successful mobile run, capture at least one screenshot or equivalent
UI-state artifact and repair the demo first if it is blank, stuck on splash, or
not on the expected functional screen.

`coverage` metadata is included in `fluoh drive --dry-run --json` and real
run JSON. Use it to make AI package adaptation auditable: every applicable
package API, permission, picker, media flow, callback, lifecycle path, and
negative path should have a `covered`, `notApplicable`, or `blocked` row before
the package is marked ready for review. `blocked` rows keep the package out of
release readiness until repaired.

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
- Screenshots or screen recordings, required after mobile run:
- HAP/APK/app build path when relevant:
- Hilog or run output path:
- Actual result:
- Release impact: ready | needs maintainer decision | blocked
