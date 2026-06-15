---
name: fluoh
description: Use this skill when adapting Flutter apps or Flutter package repositories to FlutterOH/OHOS with the fluoh CLI, or when maintaining FlutterOH Source data with fluoh source checks. Trigger for requests like making a project support OHOS, adapting a third-party Flutter package for FlutterOH, running fluoh doctor/verify/build/run/source check diagnostics, interpreting fluoh JSON nextCommand/diagnostics, prechecking a FlutterOH/source pull request, or producing a FlutterOH adaptation report.
---

# fluoh

Use `fluoh` as the deterministic toolchain and this skill as the AI
orchestration layer. The CLI owns SDK selection, dependency rewrites, doctor
checks, package repository setup, build/run execution, signing, automation
drivers, and JSON diagnostics. The agent owns code inspection, implementation,
test updates, diagnostic routing, repair loops, and the completion report.

Keep the tool/skill boundary explicit. `fluoh` commands provide hands and eyes:
repeatable command execution, target selection, signing/setup shortcuts,
device actions, screenshots and UI/log/session observations, artifact paths,
diagnostics, and machine-readable tool commands. This skill is the brain: it
decides what to inspect, what to fix, which evidence is sufficient, and what
delivery state to report. No single build, run, screenshot, or matrix-smoke
command means "fully tested" unless this skill has reviewed the functional
evidence, coverage matrix, report, and release checks.

Keep this file as the routing surface. Open the referenced workflow file only
when the current request needs it.

## Helper Scripts

The bundled scripts are optional, agent-neutral shortcuts. They use only the
Python standard library and do not replace the `fluoh --json` diagnostic
contract.

- `scripts/preflight.py`: read-only workspace classifier. It reports
  `upgradeChecks`, `suggestedCommands`, `finalCheckCommands`,
  `deliveryChecks`, `automationRunbook`, `deliveryGate`, `reportCommand`,
  `summaryCommand`, `scenarioCommand`, `sessionInspectCommand`, and
  `sessionAttachCommand`.
- `scripts/new_report.py`: creates the canonical report
  `.fluoh/reports/<report-group>/report-<timestamp>.md` from
  `references/report-template.md`.
- `scripts/new_summary.py`: creates a monorepo summary report for
  multi-package work.
- `scripts/check_report.py`: fails when the report is missing required
  evidence, checklist state, Fluoh Feedback, or still has placeholders.
- `scripts/collect_feedback.py`: summarizes trace feedback candidates for the
  report.
- `scripts/new_scenario.py`: creates a local interaction scenario from
  `references/interaction-scenario-template.md`, including the
  `Session attach command` field.
- `scripts/inspect_session.py`: reads a `flutterRunSession` JSON file from
  `fluoh run --session-file` and reports launch state, VM Service URI when
  available, output or hilog logs, `fluoh attach` hints, and the recommended
  next step.

## Request Routing

- Install, update, or reload the skill: if needed, run CLI Setup, run
  `fluoh upgrade`, then run `fluoh skill --path` and reinstall or reload the
  printed skill path, overwriting any existing fluoh skill when the host agent
  supports it. Use `fluoh skill --json` only when script metadata, reference
  paths, `skillVersion`, `installPrompt`, or `upgradePrompt` are needed. If the
  host cannot reload skills now, report that blocker.
- Install or set up fluoh: run the CLI Setup section, then continue with the
  requested workflow.
- Make an existing Flutter app support OHOS: run preflight, then use
  `references/app-project-flow.md`.
- Adapt a third-party package or upstream Git URL: run preflight or
  `fluoh package discover <upstream> --json`, then use
  `references/package-adaptation-flow.md`. Treat each candidate
  `adaptationProfile` as the first capability inventory seed for tests,
  scenarios, risk routing, and maintainer-decision blockers.
- Validate emulator/device UI behavior, permission prompts, or automatic
  coverage repair: use `references/automation-evidence-flow.md`.
- Check or precheck FlutterOH Source data: use
  `references/source-maintenance-flow.md`.
- Review-only requests: stop after read-only commands and dry-runs. Do not
  apply dependency fixes, project writes, releases, pushes, force-pushes, or
  destructive Git operations.

## Start

1. Read the repository `AGENTS.md` first when it exists.
2. Run the CLI Setup section before the first workflow command, or run
   `scripts/preflight.py` to collect the same version and workspace shape.
3. When working inside the fluoh CLI repository itself, use
   `dart run bin/fluoh.dart` only for validating the CLI. For user project
   automation and every JSON diagnostic command, use the installed `fluoh`
   executable because the Dart launcher can print dependency text before fluoh
   starts.
4. Inspect the current directory from preflight JSON when available:
   `app-project`, `flutter-package`, `package-repository`, `dart-package`, or
   `unknown`.
5. Route by preflight `project.kind`, `selectedPackage`, `examplePlatforms`,
   `upgradeChecks`, `suggestedCommands`, `finalCheckCommands`, and
   `deliveryChecks`, `automationRunbook`, and `deliveryGate`.
6. If the user specified an SDK version or line, use it. Otherwise keep the SDK
   recorded in `fluoh.yaml`; when none is recorded, run `fluoh sdk list` and
   choose the latest stable FlutterOH SDK line.

## CLI Setup

1. Run `fluoh --version`.
2. If `fluoh` is missing and the user asked to use `$fluoh`, set up fluoh, or
   adapt a project/package, install the CLI without another confirmation. This
   setup step does not authorize project, package, Source, or Git state
   changes.
3. If `fluoh --version` exists but fails with Flutter Dart cache startup
   errors such as `update_engine_version.sh`, `engine.stamp.tmp`,
   `engine.realm`, or `Operation not permitted`, classify it as a CLI launcher
   or local sandbox issue, not a project/package issue. Prefer a native or
   Homebrew `fluoh` executable, set `FLUOH_BIN` to a working executable, or
   pass `--fluoh-command` to preflight. When validating the fluoh repository
   itself, use `dart run bin/fluoh.dart`.
4. Prefer Dart pub when `dart --version` works:
   `dart pub global activate fluoh`.
5. If the Dart global install succeeds but `fluoh` is still not on `PATH`, use
   `$HOME/.pub-cache/bin/fluoh` for this session and tell the user to add
   `$HOME/.pub-cache/bin` to `PATH`.
6. For strict JSON automation, prefer the native/Homebrew executable when it is
   available. Dart pub global shims are acceptable only after confirming a
   `--json` command starts stdout with `{`.
7. On macOS, if Dart is unavailable or the Dart pub shim emits non-JSON startup
   text before JSON diagnostics, and Homebrew is available, run
   `brew tap FlutterOH/fluoh https://github.com/FlutterOH/fluoh.git` and
   `brew install FlutterOH/fluoh/fluoh`. Do not use
   `brew tap FlutterOH/tap` unless that official tap repository is available.
8. If neither Dart nor Homebrew can install the CLI, ask the user to install
   Dart or provide a `fluoh` executable path.
9. After installation, run `fluoh --version`, then continue with preflight.

## Adaptation Scope Gate

Treat a request to adapt, fix, make OHOS support, or hand work to AI as
authorization to install or locate the CLI, run read-only preflight, and
discover adaptation values. It is not authorization to change project files,
package repositories, Source files, local Git configuration, or implementation
code.

Before any mutating project, package, Source, Git, or implementation edit,
present a final adaptation scope confirmation and wait for explicit user
approval unless the user already approved the same resolved adaptation scope in
this task. The confirmation must list:

- adaptation kind and working directory;
- output directory when applicable;
- SDK version or SDK line;
- package name and package path when applicable;
- FlutterOH repository URL or path when applicable;
- Git author identity when commits may be created;
- explicit `--org` override when one will be passed;
- mutating commands or file edits that will run;
- operations that will not run without separate approval, such as release,
  push, force-push, destructive Git commands, public API breaks, or manual
  release version overrides.

After approval, local code edits, project-file edits, and phase checkpoint
commits are part of the automatic adaptation workflow. Create small local
commits after completed phases with clean command evidence, such as generated
baseline, selected-SDK baseline, implementation, tests and example
verification, release metadata, and delivery report handoff. Keep release,
push, force-push, destructive Git operations, public API breaks, SDK line
changes, upstream downgrades, and manual release version overrides separately
approved.

## Preflight Routing

When using `scripts/preflight.py`, route by the returned JSON:

- `fluohSetup`: when `status` is `needs-cli-setup`, fix the CLI executable or
  launcher first, rerun preflight, and only then follow `commandQueue`. Do not
  classify launcher or local sandbox failures as project/package
  implementation failures.
- Missing path, unknown project, or `dart-package`: do not edit. Ask for the
  project path, or create a package repository only when the user gave an
  upstream Git URL.
- `app-project`: use `references/app-project-flow.md`.
- `flutter-package`: create a FlutterOH package repository first; do not add
  OHOS implementation files directly in the upstream checkout.
- `package-repository`: use `references/package-adaptation-flow.md` and confirm
  the selected package matches the user's request.
- `upgradeChecks`: when preflight requires a newer fluoh, run `fluoh upgrade`,
  refresh the skill with `fluoh skill --path` when the host supports it, then
  handle schema migration and generated-doc refresh blockers before
  implementation edits. Generated `README.md`, `FLUOH.md`, and `AGENTS.md`
  sections are tool-owned; do not edit inside `fluoh:generated` blocks by hand.
- `reportCommand`, `summaryCommand`, `scenarioCommand`,
  `sessionInspectCommand`, and `sessionAttachCommand`: prefer these exact
  helper commands over reconstructing paths manually.
- `automationRunbook` and `deliveryGate`: treat these as the stop condition.
  Do not end the adaptation until `deliveryGate.readyRequires` is satisfied,
  `deliveryGate.blockedWhen` explains the remaining blocker, or
  `deliveryGate.needsMaintainerDecision` applies.

## JSON Diagnostics

For every `--json` command:

- Invoke the installed `fluoh` executable, not `dart run bin/fluoh.dart`.
- Parse the JSON object before editing.
- Follow top-level or step-level `nextCommand` when present.
- Route by `diagnostics[].code` and inspect `stdoutTail`, `stderrTail`, saved
  logs, and trace manifests before changing code.
- For `verify`, `build`, and `run`, prefer
  `--trace-dir .fluoh/traces/<scope>/<session-id>` during AI-driven loops.
  Reuse the same trace directory for related commands so evidence accumulates.
- Read `dirtyAfterVerify`, `workingTreeChanges`, `feedbackCandidates`, and
  `traceError`; classify findings as fluoh CLI, Source data, AI skill, local
  environment, upstream package, or user project follow-up.
- Read `workflowEvidence` from `build` and `run` as factual tool output.
  `classification: buildOnly` means only artifacts were built.
  `classification: launchSmoke` means the app launched, not that UI behavior
  passed. `fluoh run` automatically attempts a best-effort post-launch
  screenshot for OHOS, Android, and iOS under `details.postLaunchScreenshot`;
  if it is skipped or failed, collect equivalent UI-state evidence with
  `fluoh drive`. Every successful mobile run still needs a tool-readable page
  assertion.
  If the example/demo page is visually stuck, blank, hidden behind splash, or
  otherwise unusable, repair the demo before continuing to broader automation.
  Use `observedEvidence`, `collectedEvidenceKinds`,
  `notCollectedEvidenceKinds`, `workflowContinuations`, and `toolCommands` to
  choose the next run smoke, `fluoh drive --dry-run`, scenario,
  integration-test, report, or check action.
  `collectedEvidenceKinds` means the command collected a result or artifact;
  check `observedEvidence` before treating that result as passed evidence.
  For `observedEvidence.interaction.status`,
  `integrationTestEvidenceFailed` overrides any passed integration-test rows in
  the same matrix, and `partialIntegrationTestEvidence` means only some targets
  produced passed integration-test evidence. Neither status is release-ready.
  OHOS integration steps may include `details.systemPermissionDialogs` when
  `--ohos-permission-dialog-policy allow` handled prompts; use it as prompt
  evidence, then still verify behavior through tests, drive, or assertions.
- Treat doctor, toolchain, and device diagnostics as local-environment work
  until the local diagnostic is clean.
- Treat build failures, install failures, launch failures, runtime crashes,
  Flutter channel errors, integration-test failures, and package test failures
  as code or project issues only after the local toolchain diagnostic is clean.

## Evidence Loop

1. Run preflight and select exactly one package when selection is required.
2. Before final verification, inspect existing package/app tests,
   `integration_test/`, examples, public API, platform interfaces,
   permissions, behavior paths, and official OHOS/platform documentation. If
   the existing tests do not cover the adapted library behavior, add or repair
   focused functional tests first. For package work, start from
   `package discover` or package plan
   `adaptationProfile` categories, required evidence, suggested coverage, and
   blocker policy before adding custom rows.
3. Run the suggested verify/build/run commands until diagnostics are clean or a
   blocker is explicit. Clean build/run JSON is not the end of the workflow.
   After every successful mobile run, inspect `details.postLaunchScreenshot`
   or collect equivalent UI-state evidence, then confirm the example/demo page
   is the expected functional screen. If the page is abnormal, fix it first.
   Inspect `workflowEvidence.notCollectedEvidenceKinds` and
   `workflowEvidence.workflowContinuations` and continue until functional
   evidence, coverage review, report creation, and report checks are handled.
4. When an interactive flow, permission prompt, file picker, camera, location,
   media, deep link, external app callback, or lifecycle behavior matters, use
   `references/automation-evidence-flow.md`.
   For OHOS grant-path integration tests, use
   `--ohos-permission-dialog-policy allow` only when automatic allow preserves
   test intent; keep repairing missing deny-path or page-readiness assertions.
5. Make the smallest implementation, scenario, test, or project-file change
   needed for the next clean verification result.
6. Rerun the exact failed command, or the printed rerun/validation command from
   JSON diagnostics.
7. Run `scripts/collect_feedback.py` on the trace session when feedback
   candidates exist.
8. Write/check the report, then run `references/independent-review-flow.md`; feed reviewer feedback packets into repairs before `ready`.

Launch success is smoke evidence. Release-ready interaction evidence must come
from a passed `flutter test integration_test -d <device>` command row, real
`fluoh drive --scenario <path> --json`, or manual-assisted tool-readable
verification with a concrete blocker or result. `manual-assisted` is an
operation mode, not a human-only pass; a passed row must still cite logs,
meaningful session state beyond launch, stable text, semantics, test keys,
command JSON, hilog, or app log markers. When `integration_test/` exists,
platform run commands, including OHOS, must execute it and the report must
record the resulting test command and result in the Commands table.
`assertSession`, `launchApp`, `wait`, and screenshots prove launch or visual
sanity only. They cannot satisfy permission grant/deny, public API,
method-channel, platform-channel, example-flow, or negative-path coverage
unless the scenario also performs the relevant interaction and records a
post-interaction functional assertion such as `assertText`, `waitText`, or
`assertLog`.
When `fluoh run all` succeeds, use it only as platform launch-smoke coverage
for the existing project or package example platform directories it selected.
Continue with the printed `fluoh drive all --dry-run --json` or
platform-specific `drive` commands, capture screenshots for each mobile target,
repair any abnormal demo page, then add or repair scenarios until grant, deny,
gestures, and result assertions are fully covered. `blocked` coverage rows are
repair items, not a release-complete state.
Do not focus only on OHOS for package adaptations. Existing Android, iOS,
macOS, Linux, Web, and Windows example/platform directories are in scope for
functional verification. Run the platform commands when the current host and
toolchain support them; otherwise record the exact diagnostic command, host or
toolchain limitation, and skip reason in the report. A `ready` recommendation
requires either passed functional evidence for each existing platform or a
concrete unsupported-environment blocker.
Do not rely on screenshot recognition as the primary assertion; use it as the
mandatory visual sanity check after launch, backed by text, session, log, or
interaction assertions for pass/fail behavior.
If `automation.coveragePolicy.scenarioEvidence` or `repairQueue` reports
`needsFunctionalEvidence`, keep the adaptation loop running: update the
scenario, example app, or test so the adaptation AI can tap/request/deny the
flow and assert the resulting text/log/state, then rerun the printed drive
command. Do not downgrade those rows to ready in the report.
If `page-readiness` reports `needsPageReadinessEvidence`, repair the scenario
or demo page until a post-launch `assertText`, `waitText`, or `assertLog`
proves the functional screen is ready. Use `suggestedScenarioPatch` from JSON
when present so step bindings and TODO assertions stay machine-readable.

## Completion Report

Before the final response, create the local report under:

```text
.fluoh/reports/<report-group>/report-<timestamp>.md
```

For package work, `<report-group>` is normally the package name slug. For
multi-package monorepos, also create a summary report under:

```text
.fluoh/reports/<scope-slug>/summary-<timestamp>.md
```

Prefer preflight `reportCommand` and `summaryCommand`, or run:

```text
python3 <skill-dir>/scripts/new_report.py <project-path> --scope <scope>
python3 <skill-dir>/scripts/new_summary.py <project-path> --scope <scope>
python3 <skill-dir>/scripts/check_report.py <report-path>
```

Complete the report with commands, exit codes, changed files, platform matrix,
automation coverage gates, interaction evidence, diagnostics, Fluoh Feedback,
remaining risks, and release recommendation. Mark every applicable Delivery
Checklist item as done, or leave it unchecked and explain the blocker. A ready
recommendation requires checklist completion, `check_report.py` pass, and no
open blocker/high/medium independent-review feedback.

The AI adaptation loop ends at a release recommendation and evidence report.
The maintainer still makes the final release approval and owns publish, push,
tag, app-store, or package-registry actions.

The final response should state whether the work is ready, blocked, or needs a
maintainer decision; point to the report path; and list only the remaining
blocking risks.
