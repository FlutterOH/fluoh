# Automation Evidence Flow

Use this workflow when a package or app needs AI-owned functional evidence
beyond launch smoke tests: UI taps, permission prompts, file pickers, camera,
microphone, location, media, deep links, external app callbacks, lifecycle
behavior, error paths, or multi-step forms.

## Commands

Start with a dry-run when selecting devices, session paths, trace paths, or
checking coverage readiness:

```sh
fluoh automate --platform <platform> --package <name> --dry-run --json
fluoh automate --platform <platform> --package <name> --scenario <path> --json
fluoh automate --platform all --package <name> --trace-dir .fluoh/traces/<name>/mobile-automation --json
```

For live Flutter attach evidence on supported platforms, write and inspect a
live `flutterRunSession` JSON file:

```sh
fluoh run --platform android --package <name> \
  --session-file .fluoh/run-sessions/<name>/android-session.json --json
python3 <skill-dir>/scripts/inspect_session.py \
  .fluoh/run-sessions/<name>/android-session.json --wait 30 \
  --expect-platform android --require-vm-service
```

Use the preflight `scenarioCommand` and `sessionInspectCommand` when available.

## Evidence Rules

- `fluoh run` launch success is smoke evidence only.
- Prefer `integration_test/` when available.
- Prefer `fluoh automate --scenario <path> --json` for AI-assisted scenarios
  with structured actions.
- Use manual-assisted interaction only as a fallback when automation cannot
  operate or observe the target, and only mark it passed after tool-readable
  evidence verifies the user-completed flow.
- Do not judge visual correctness unless the package is specifically visual.
- Do not rely on screenshot recognition as the primary assertion. Screenshots
  and recordings are supporting artifacts only.
- Primary evidence should be Flutter debug output, VM Service/session output,
  widget or component tree state, semantics tree, integration-test output,
  accessibility text, visible status text, semantic labels, stable test keys,
  command JSON, hilog, or app log markers.

## Platform Support

`fluoh automate --scenario` can execute supported actions across mobile
platforms:

- Android: text and coordinate taps, coordinate swipes and drags, permission
  allow/deny prompts, text/log/session assertions, input text, and key presses.
- iOS: coordinate taps, swipes and drags, text taps/assertions, and permission
  prompt allow/deny clicks through the built-in XCTest runner when `bundleId`
  is present, plus run-output log and session assertions. If Xcode or
  `xcodebuild` is unavailable, record the environment blocker in the report.
- OHOS: coordinate/text taps, coordinate swipes and drags, waits, permission
  actions, and hilog assertions.

Read `diagnostics[].details.repairHints` before editing and rerun the same
scenario command after exposing stable labels, semantics, status text, or log
markers.

## Coverage Policy

Before marking a Package adaptation ready, build a coverage matrix from the
upstream public API, example entry points, declared platform interfaces,
manifest permissions, and platform feature classes. Every applicable row must
have automation, `integration_test`, manual-assisted tool-readable evidence, or
an explicit `notApplicable` or `blocked` reason.

For runtime permissions, do not validate only one representative permission.
Inventory every permission the package exposes on each supported platform, then
cover each grant path and each deny/error path that can change package
behavior. Put these rows in scenario `coverage` metadata.

Read these JSON fields from dry-run and real automation output:

- `automation.coveragePolicy.coverageSummary`
- `inventory`
- `capabilityCoverage`
- `manifestPermissionCoverage`
- `pathCoverage`
- `scenarioEvidence`
- `qualityGates`
- `repairLoop`
- `automation.deliveryRecommendation`
- `automation.repairPlan.nextStep`
- `automation.repairQueue`

Only `readyForAutomation: true` means the matrix is ready to execute.
`needsMaintainerDecision` means structurally ready rows still need explicit
handoff evidence. Final ready reports must show zero not-ready quality gates,
such as `ready=8, notReady=0`, with irrelevant gates recorded as
`notApplicable` and a reason.

## Repair Loop

Use `inventory` as the first local evidence source for test-gap analysis. When
the existing-test-baseline, capability-inventory-coverage, or
manifest-permission-coverage gate is not ready, add or repair tests, scenarios,
example controls, manifest declarations, or explicit blocked/notApplicable rows
before reporting ready.

Follow `automation.repairPlan.nextStep` as the current machine-consumable
action, then expand `automation.repairQueue` when you need the ordered backlog.
Common queue types:

- `testCoverage`: create or expand the printed `expectedTestPath` and run the
  printed `testCommand`.
- `scenarioCoverage`: add the printed `suggestedCoverage` rows to a scenario.
- `permissionCoverage`: add grant and denied/error rows for the printed
  manifest permission.
- `pathCoverage`: add missing success or negative/error behavior rows.
- `scenarioEvidence`: add a printed verification action such as `assertText`,
  `waitText`, `assertLog`, or `assertSession`.
- `needsExecution`: run the concrete commands in the execution repair queue.
- `needsMaintainerDecision`: document the handoff or environment blocker.

After editing tests or scenarios, run the printed validation command or
`automation.rerunCommand` instead of reconstructing it from memory.
