---
name: fluoh
description: Use this skill when adding or maintaining FlutterOH support for Flutter apps and Flutter package repositories with the fluoh CLI, or when maintaining FlutterOH Source data with fluoh source checks. Trigger for requests like making a project FlutterOH-ready, porting a third-party Flutter package for FlutterOH, running fluoh doctor/verify/build/run/source check diagnostics, interpreting fluoh JSON nextAction/nextCommand/diagnostics, prechecking a FlutterOH/source pull request, or producing a FlutterOH support report.
---

# fluoh

Use `fluoh` as the deterministic workflow state machine. The agent is a
short-loop repair worker: read one machine result, do the one requested action,
then rerun the tool-provided validation command. Do not maintain a parallel
long checklist in chat when a `fluoh` JSON field, report, or helper script can
own that state.

Prefer `nextAction` when present. It is the single state exit for AI loops:

- `ready`: stop implementation work and report the ready evidence; use
  `nextAction.nextCommands` for release-readiness commands only after the
  implementation action and bundled report check are ready.
- `commandRequired`: run `nextAction.command`, then rerun
  `nextAction.rerunCommand` when present.
- `editRequired`: inspect only the named blocker/details, make the smallest
  code or project edit, then run `nextAction.rerunCommand`.
- `blocked`: stop and report the blocker; do not invent extra workflow steps.

For `fluoh package next --json`, read `qualityProfile`,
`visualPageReadiness`, `evidenceSummary`, `notes`, `remainingRisks`, and
`failureStreak` as context, but still execute only `nextAction`. Treat
`quality.functional_surface_missing` and notes issues as reportable quality
risks, not a separate self-invented checklist. Treat
`failureStreak.blocking: true` or `nextAction.type: blocked` as a hard stop
for automatic repair.
When `qualityProfile.example.existingPlatforms` lists Android, iOS, macOS,
Linux, Web, or Windows, `package next` adds platform-policy
`existing-<platform>-regression` phases. Run those exact `nextAction` commands;
they may be build or run commands depending on the platform. Existing Android
and host-supported iOS examples also add
`existing-<platform>-automation-dry-run` and
`existing-<platform>-automation-run` phases. Do not collapse these phases to
launch smoke; selecting the FlutterOH SDK can regress existing examples even
when OHOS work passes.

Keep this file as the routing surface. Open referenced workflow files only
when the current request needs their domain details.

## Helper Scripts

The bundled scripts are optional shortcuts around the JSON contract:

- `scripts/preflight.py`: read-only classifier. It reports `upgradeChecks`,
  `suggestedCommands`, `finalCheckCommands`, `deliveryChecks`,
  `automationRunbook`, `deliveryGate`, `reportCommand`, `summaryCommand`,
  `scenarioCommand`, `sessionInspectCommand`, and `sessionAttachCommand`.
  When the selected `fluoh` executable is ready, it uses `fluoh plan app` or
  `fluoh plan package` as the primary command queue source. If
  `--fluoh-command` or `FLUOH_BIN` selects an executable other than `fluoh`,
  prefer `executableCommandQueue`, `executableFinalCheckCommands`, and
  `executableReportCommand` for actual execution while treating
  `commandQueue` as the canonical workflow description.
- `scripts/new_report.py`: creates a report under the current local task,
  `.fluoh/tasks/<task-id>/reports/report-<timestamp>.md`, from
  `references/report-template.md`.
- `scripts/new_summary.py`: creates a monorepo summary report.
- `scripts/check_report.py`: validates required evidence and checklist gates.
- `scripts/collect_feedback.py`: summarizes trace feedback candidates.
- `scripts/new_scenario.py`: creates a local interaction scenario from
  `references/interaction-scenario-template.md`, including the
  `Session attach command` field.
- `scripts/inspect_session.py`: inspects a `flutterRunSession` JSON file and
  reports launch/session state, logs, attach hints, and a recommended next
  step.

Package support scopes live at
`doc/fluoh/<package>/scope.yaml`. They are support-scope records
edited by the agent or maintainer after reading the public Dart API, target
platform behavior, existing implementations, examples, tests, and platform API
sources. The CLI checks that P0 scope entries have per-platform support
decisions, implementation plan status where implementation is required, test
cases, and functional or regression evidence; it does not decide API
equivalence by itself.
Branch-local package requirements, API design, platform behavior, platform API
mapping, example flows, and test plans live at
`doc/fluoh/<package>/spec.md`. Use
`references/package-spec-template.md` as the fill-in shape when reviewing that
spec. `FLUOH.md` is generated quick context that links the spec and support
scope; do not use it as the detailed design document.
For both spec-first and upstream-first package work, extract or confirm the
package contract before implementation: package purpose, public Dart API,
platform behavior, platform API mapping, example flows, test expectations, and
acceptance evidence. Keep that contract in the branch-local spec and mirror P0
scope entries into the support scope as a platform matrix.
After `fluoh package upstream sync` on a ported package, update the spec to the
current upstream version and commit before continuing implementation.
Visual page-readiness evidence lives under the current task at
`.fluoh/tasks/<task-id>/evidence/visual-readiness.yaml`. Write it only after
opening the captured mobile screenshot or equivalent UI-state evidence and
confirming the functional demo page is visible, usable, and not blank, splash
only, hidden, or just a template shell.

## Request Routing

- Install, update, or reload the skill: if needed, run CLI Setup, run
  `fluoh upgrade`, then run `fluoh skill --path` and reinstall or reload the
  printed path, overwriting any existing fluoh skill when supported. Use
  `fluoh skill --json` only for metadata such as `skillVersion`,
  `upgradePrompt`, script paths, or reference paths.
- Install or set up fluoh: run CLI Setup, then continue.
- Add FlutterOH support to an existing Flutter app: run preflight, then use
  `references/app-project-flow.md`. App work uses `fluoh create . --platforms`
  for project skeleton/platform files and `fluoh deps` for dependency
  compatibility; do not route apps through package lifecycle commands.
- Create a new FlutterOH package from a user spec: use `fluoh package new`
  after the public API, platform matrix, example behavior, and test
  expectations are clear, then use `references/package-support-flow.md`.
- Port a third-party package or upstream Git URL: run preflight or
  `fluoh package discover <upstream> --json`, create the package repository
  with `fluoh package port <upstream>`, then use
  `references/package-support-flow.md`.
- Sync a ported package to a newer upstream baseline: use
  `fluoh package upstream check` or `fluoh package upstream sync`. These
  commands are not available for `origin.kind: created`; Source metadata sync
  remains `fluoh source sync` for both created and ported packages.
- Validate emulator/device UI behavior, permission prompts, or automation
  coverage repair: use `references/automation-evidence-flow.md`.
- Check or precheck FlutterOH Source data: use
  `references/source-maintenance-flow.md`.
- Review-only requests: stop after read-only commands and dry-runs.

## Start

1. Read repository `AGENTS.md` when it exists.
2. Run CLI Setup before the first workflow command, or run
   `scripts/preflight.py` to collect the same version and workspace shape.
3. Inside the fluoh CLI repository, use `dart run bin/fluoh.dart` only for
   validating fluoh itself. For user project automation and every strict JSON
   diagnostic command, use the installed `fluoh` executable.
4. Route by preflight `project.kind`, selected package, `upgradeChecks`,
   `finalCheckCommands`, `deliveryChecks`, `automationRunbook`, and
   `deliveryGate`.
5. In a package repository, run `fluoh package next --json` or
   `fluoh package next --package <name> --json` and follow `nextAction`.
   If it asks for `package scope init` or a support scope edit,
   maintain `doc/fluoh/<package>/scope.yaml` before implementation
   work. `package scope init` imports concrete rows from the spec's
   `Support Scope Seeds` table by default; use `--no-from-spec` only when that
   table is stale or intentionally empty.
6. If no SDK is recorded and the user did not specify one, run
   `fluoh sdk list` and choose the latest stable FlutterOH SDK line.

## CLI Setup

1. Run `fluoh --version`.
2. If `fluoh` is missing and the user asked to use `$fluoh`, set up fluoh.
   This setup step does not authorize project, package, Source, or Git state
   changes.
3. Select a `fluoh` executable in this order for strict JSON automation:
   native/Homebrew, compiled current-repo exe, then Dart pub global shim. Set
   `FLUOH_BIN` or pass `--fluoh-command` when the chosen executable is not
   first on `PATH`.
4. If `fluoh --version` fails with Flutter Dart cache startup errors such as
   `update_engine_version.sh`, `engine.stamp.tmp`, `engine.realm`, or
   `Operation not permitted`, treat it as a launcher/sandbox issue and move to
   the next executable source.
5. On macOS, if no native/Homebrew executable is available and Homebrew is
   available, run `brew tap FlutterOH/fluoh https://github.com/FlutterOH/fluoh.git`
   and `brew install FlutterOH/fluoh/fluoh`; do not use
   `brew tap FlutterOH/tap` unless that official tap repository is available.
6. Inside the fluoh repository, if native/Homebrew is unavailable, compile the
   repo and use that executable: `dart compile exe bin/fluoh.dart -o /tmp/fluoh-native`.
   When that executable runs outside the checkout and needs bundled skill
   scripts or `fluoh skill --path`, set `FLUOH_SKILL_PATH` to the checkout's
   `skills/fluoh` directory.
7. Use `dart pub global activate fluoh` only as fallback. If the Dart global
   install succeeds but `fluoh` is not on `PATH`, use
   `$HOME/.pub-cache/bin/fluoh` and tell the user to add it to `PATH`.
8. Dart pub global shims may emit dependency-resolution text before fluoh
   starts; for strict JSON, use them only after confirming stdout starts with
   `{`, otherwise switch to native/Homebrew or compiled repo exe.
9. If none of native/Homebrew, compiled repo exe, or Dart pub global shim works,
   ask the user to install Dart/Homebrew or provide a `fluoh` executable path.
10. After selecting the executable, run `fluoh --version`, then continue.

## Support Scope Gate

Treat a request to add support, fix, make FlutterOH support, or hand work to AI as
authorization to install or locate the CLI, run read-only preflight, and
discover support values. It is not authorization to change project files,
package repositories, Source files, local Git configuration, or implementation
code.

Before any mutating project, package, Source, Git, or implementation edit,
present a final support scope confirmation and wait for explicit user
approval unless the user already approved the same resolved support scope in
this task. The confirmation must list kind, working directory, output
directory, SDK, package, repository URL/path, Git author identity when commits
may be created, mutating commands or edits, and operations that will not run
without separate approval.

After approval, local code edits, project-file edits, and phase checkpoint
commits are allowed when they are the direct response to `nextAction` or a
tool-provided command. Release, push, force-push, destructive Git operations,
public API breaks, SDK line changes, upstream downgrades, and manual release
version overrides still require separate approval.

## Preflight Routing

When using `scripts/preflight.py`, route by the returned JSON:

- `fluohSetup`: fix CLI executable or launcher first, rerun preflight, then
  follow the command queue.
- Missing path, unknown project, or `dart-package`: do not edit. Ask for a
  project path, create a spec-first package only after the user confirms the
  package contract, or port a package repository only when the user gave an
  upstream Git URL.
- `app-project`, `flutter-package`, `package-repository`, and Source tasks:
  use the matching reference file listed in Request Routing.
- `reportCommand`, `summaryCommand`, `scenarioCommand`,
  `sessionInspectCommand`, and `sessionAttachCommand`: prefer these exact
  helper commands over reconstructing paths. If preflight also prints an
  `executable...` variant for the selected local fluoh executable, run that
  variant.
- `automationRunbook` and `deliveryGate`: treat tool-provided
  `deliveryGate.readyRequires`, `blockedWhen`, and `needsMaintainerDecision`
  as the stop-condition source.

## JSON Diagnostics

For every `--json` command:

- Invoke the installed `fluoh` executable, not `dart run bin/fluoh.dart`.
- Parse exactly one JSON object before editing.
- Follow `nextAction` first. If absent, follow top-level or step-level
  `nextCommand`.
- Route by `diagnostics[].code`, `stdoutTail`, `stderrTail`, saved logs, trace
  manifests, `workingTreeChanges`, and `feedbackCandidates`.
- For `package next`, summarize `notes`, `visualPageReadiness`,
  `qualityProfile`, `evidenceSummary`, `reportCheck`, and `remainingRisks`
  only when reporting status or blockers; do not turn them into an independent
  checklist.
- Prefer `--task <task-id>` or the current task for verify/build/run loops.
  When an explicit path is unavoidable, keep it under
  `.fluoh/tasks/<task-id>/traces/...` so report creation can consume evidence
  files.
- Treat doctor, toolchain, and device diagnostics as local-environment work
  until the local diagnostic is clean.
- For `fluoh doctor --json --strict`, follow the top-level `nextAction` when
  present. `blocked` means local environment or project setup must be repaired
  before implementation, build, run, or automation failures should be treated
  as package code issues.
- Treat build, install, launch, runtime, channel, integration-test, and package
  test failures as code/project issues only after local toolchain diagnostics
  are clean.

## Evidence Loop

Run a short deterministic loop:

1. Run preflight or `fluoh package next --json`.
2. Follow one `nextAction`.
3. For `editRequired`, inspect the smallest relevant code surface and edit only
   what the blocker requires.
4. Run `nextAction.rerunCommand`, the failed command, or the printed
   validation command.
5. Repeat until `ready`, `blocked`, or maintainer decision.

Do not decide release readiness from chat memory. Launch success is smoke
evidence only. `fluoh drive --profile exploratory-smoke` is useful for bounded
generic exploration and crash or blank-page discovery, but it is not functional
correctness evidence and does not clear `quality.functional_surface_missing`.
The support scope is the planning and evidence contract: P0 platform rows
must not stay `unknown`; `supported` or `degraded` rows need platform research
sources, implementation plan status, test cases, and functional evidence;
`preserved` rows need baseline sources, regression test cases, and regression
evidence; `unsupported`, `notApplicable`, or `manualRequired` rows need a
reason.
If `nextAction.phase` is `visual-page-readiness`, inspect the screenshot path
or UI-state evidence named by `details.visualPageReadiness`; write
`.fluoh/tasks/<task-id>/evidence/visual-readiness.yaml` with
`kind: fluoh.visualPageReadiness` and `status: passed` only when the functional
page is actually visible and usable. If it is blank, stuck, hidden, or a
template shell, repair the example instead of writing passed evidence. If a UI
tree, semantics dump, or text assertion claims widgets exist but the screenshot
shows a blank or wrong page, treat visual page-readiness as failed and repair
the app before automation.
`manual-assisted` means a person may operate the device, but pass/fail still
needs tool-readable logs, session state beyond launch, stable text, semantics,
test keys, command JSON, hilog, or app log markers. Use
`references/independent-review-flow.md` only when a release/check flow requests
reviewer feedback packets or the user asks for independent review.

## Completion Report

For package repositories, let `fluoh package next --json` emit report creation,
report repair, and report-check actions; do not bypass the package state
machine to hand-fill a ready report. For app projects, prefer
`fluoh report create --json` with trace and automation inputs and avoid
hand-filling gates the CLI can derive. When a package report command is emitted,
pass `--package <name>` so the report records the Support Scope from
`doc/fluoh/<package>/scope.yaml` and emits `supportScope` in JSON.
The generated report includes an `Official Platform Basis` section, but ready
delivery still needs the agent to fill reviewed official platform sources or a
concrete not-applicable reason when the CLI cannot derive it from evidence.
Reports live under:

```text
.fluoh/tasks/<task-id>/reports/report.md
```

`fluoh report create` uses `report.md` by default. The helper
`scripts/new_report.py` creates `report-<timestamp>.md`; both generated
filenames are valid report-check inputs.

For multi-package monorepos, also create:

```text
.fluoh/tasks/<task-id>/reports/summary-<timestamp>.md
```

Prefer preflight `reportCommand` and `summaryCommand`, or run:

```text
python3 <skill-dir>/scripts/new_report.py <project-path> --scope <scope>
python3 <skill-dir>/scripts/new_summary.py <project-path> --scope <scope>
python3 <skill-dir>/scripts/check_report.py <report-path>
```

Use `scripts/check_report.py` as the report gate. The final response should
state ready, blocked, or needs maintainer decision; point to the report path;
and list only remaining blocking risks. Ready reports with a Support Scope
must show complete P0 planning and functional evidence gates.

Use `fluoh package status --json`, `fluoh package check --json`, and
`fluoh package release` only after the implementation loop is ready or the user
explicitly asks for release readiness.
