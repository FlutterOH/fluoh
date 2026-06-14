# Automation Evidence Flow

Use this workflow when a package or app needs AI-owned functional evidence
beyond launch smoke tests: UI taps, permission prompts, file pickers, camera,
microphone, location, media, deep links, external app callbacks, lifecycle
behavior, error paths, or multi-step forms.

## Commands

Start with a dry-run when selecting devices, session paths, trace paths, or
checking coverage readiness:

```sh
fluoh drive <platform> --package <name> --dry-run --json
fluoh drive <platform> --package <name> --scenario <path> --json
fluoh drive all --package <name> --trace-dir .fluoh/traces/<name>/mobile-automation --json
```

When a preceding `fluoh build` or `fluoh run` JSON contains
`workflowEvidence`, use it as a factual evidence summary. `buildOnly` means
only artifacts were built. `launchSmoke` means launch was exercised, not that
functional behavior passed. Read `observedEvidence`, `collectedEvidenceKinds`,
`notCollectedEvidenceKinds`, `workflowContinuations`, and `toolCommands`, then
choose the next run smoke, post-launch screenshot review, `drive --dry-run`,
scenario, integration-test, report, or check action. A successful mobile run
must be followed by at least one screenshot or equivalent UI-state capture and
a page assertion. If the example/demo page is blank, stuck on splash, visually
hidden, or otherwise abnormal, repair the demo before broader automation. After
`drive --dry-run` or real drive output, follow `automation.repairPlan.nextStep`.
`collectedEvidenceKinds` records that a result or artifact exists; use
`observedEvidence` to distinguish passed, failed, blocked, and skipped results.
For `observedEvidence.interaction.status`, treat
`integrationTestEvidenceFailed` as failed even when other targets passed, and
treat `partialIntegrationTestEvidence` as incomplete evidence that still needs
repair, drive coverage, or an explicit blocker.

Use `drive all` only when every mobile target is intentionally in scope. For
AI delivery gates, prefer the platform-specific commands emitted by preflight,
`fluoh plan`, or `fluoh package handoff` so missing Android or iOS examples do
not become artificial blockers.

For platform launch evidence, write and inspect a `flutterRunSession` JSON file.
Pass `--require-vm-service` only when the platform run is expected to expose a
Flutter VM Service:

```sh
fluoh run android --package <name> \
  --session-file .fluoh/run-sessions/<name>/android-session.json --json
python3 <skill-dir>/scripts/inspect_session.py \
  .fluoh/run-sessions/<name>/android-session.json --wait 30 \
  --expect-platform android --require-vm-service
fluoh attach android \
  --session-file .fluoh/run-sessions/<name>/android-session.json \
  --require-vm-service
```

Use the preflight `scenarioCommand` and `sessionInspectCommand` when available.
OHOS run writes the same `flutterRunSession` file contract as the other
platforms: command, process id, target id and metadata, launch state, output
log, and VM Service URI when Flutter exposes one. `fluoh attach <platform>`
uses the same session file and falls back to the target id only when strict VM
Service attach is not required. Use `integration_test/` as
the release gate when available, and use `fluoh drive --scenario` only for
flows that are not encoded as integration tests. hdc/hilog output is scenario
or debug-tool evidence, not the primary `fluoh run` contract.

## Evidence Rules

- `fluoh run` launch success is smoke evidence only.
- Every successful mobile `fluoh run` must be followed by screenshot or
  equivalent UI-state evidence that the example/demo reached the expected
  functional screen.
- `fluoh run all` is a launch-smoke matrix shortcut, not full-platform
  functional testing.
- `workflowEvidence.classification: buildOnly` or `launchSmoke` is not a
  readiness decision. Use `notCollectedEvidenceKinds` and
  `workflowContinuations` to decide which evidence still needs collection or
  review before claiming ready.
- Prefer `integration_test/` when available.
- Prefer `fluoh drive --scenario <path> --json` for AI-assisted scenarios
  with structured actions.
- Real `fluoh drive` runs launch and available `integration_test/` evidence
  before scenario actions. If launch or integration tests fail, fix that
  failure first; do not treat a scenario as a substitute for existing tests.
- Use manual-assisted interaction only as a fallback when automation cannot
  operate or observe the target, and only mark it passed after tool-readable
  evidence verifies the user-completed flow. It is an operation mode, not a
  human-only approval.
- Do not rely on screenshot recognition as the primary assertion. Screenshots
  and recordings are mandatory launch sanity artifacts for mobile runs, but
  functional pass/fail still needs assertions such as visible text, session
  state, logs, semantics, or integration-test output.
- Primary evidence should be Flutter debug output, VM Service/session output,
  widget or component tree state, semantics tree, integration-test output,
  accessibility text, visible status text, semantic labels, stable test keys,
  command JSON, hilog, or app log markers.
- Package adaptations must verify every existing platform directory, not only
  OHOS. Treat Android, iOS, macOS, Linux, Web, and Windows as required when the
  package/example declares them and the current host/toolchain can run them.
  Record exact diagnostic evidence and skip reasons for unsupported hosts or
  toolchains.

## Platform Support

`fluoh drive --scenario` can execute supported actions across mobile
platforms:

- Android: text and coordinate taps, coordinate swipes and drags, permission
  allow/deny prompts, text/log/session assertions, input text, key presses, and
  screenshot capture.
- iOS: coordinate taps, swipes and drags, text taps/assertions, and permission
  prompt allow/deny clicks through the built-in XCTest runner when `bundleId`
  is present, plus run-output log, session assertions, and simulator screenshot
  capture. If Xcode or `xcodebuild` is unavailable, record the environment
  blocker in the report.
- OHOS: coordinate/text taps, coordinate swipes and drags, waits, permission
  actions, screenshot capture, and hilog assertions.

Read `diagnostics[].details.repairHints` before editing and rerun the same
scenario command after exposing stable labels, semantics, status text, or log
markers.

## Coverage Policy

Before marking a Package adaptation ready, build a coverage matrix from the
upstream public API, example entry points, declared platform interfaces,
manifest permissions, and platform feature classes. Every applicable row must
have automation, `integration_test`, or manual-assisted tool-readable evidence.
Use `notApplicable` only when the behavior does not exist on that platform.
`blocked` rows are repair items, not release-ready coverage.

Start coverage review before final test execution. Inspect existing package
tests, example tests, and `integration_test/` against the library behavior; if
they do not cover public API calls, platform-channel arguments/results,
permission grants and denials, success paths, and error paths, add or repair
focused tests before running the final matrix.

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
`needsBlockedCoverageRepair` means the package, demo, or scenario automation
must be fixed before release readiness. Final ready reports must show zero
not-ready quality gates, such as `ready=9, notReady=0`; record irrelevant gates
as `notApplicable` with a reason.

## Repair Loop

Use `inventory` as the first local evidence source for test-gap analysis. When
the existing-test-baseline, capability-inventory-coverage, or
manifest-permission-coverage gate is not ready, add or repair tests, scenarios,
example controls, manifest declarations, or explicit notApplicable rows
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
- `coverageBlocked`: repair the implementation, demo, or automation until the
  row is `covered`, or mark it `notApplicable` only when the behavior does not
  exist on the platform.
- `needsExecution`: run the concrete commands in the execution repair queue.

After editing tests or scenarios, run the printed validation command or
`automation.rerunCommand` instead of reconstructing it from memory.
