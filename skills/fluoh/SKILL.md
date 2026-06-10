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

Keep this file as the routing surface. Open the referenced workflow file only
when the current request needs it.

## Helper Scripts

The bundled scripts are optional, agent-neutral shortcuts. They use only the
Python standard library and do not replace the `fluoh --json` diagnostic
contract.

- `scripts/preflight.py`: read-only workspace classifier. It reports
  `upgradeChecks`, `suggestedCommands`, `finalCheckCommands`,
  `deliveryChecks`, `reportCommand`, `summaryCommand`,
  `scenarioCommand`, and `sessionInspectCommand`.
- `scripts/new_report.py`: creates
  `.fluoh/reports/<report-group>/ai-report-YYYYMMDD-HHMMSS.md` from
  `references/report-template.md`.
- `scripts/new_summary.py`: creates a monorepo summary report for
  multi-package work.
- `scripts/check_report.py`: fails when the report is missing required
  evidence, checklist state, Fluoh Feedback, or still has placeholders.
- `scripts/collect_feedback.py`: summarizes trace feedback candidates for the
  report.
- `scripts/new_scenario.py`: creates a local interaction scenario from
  `references/interaction-scenario-template.md`.
- `scripts/inspect_session.py`: reads a live `flutterRunSession` JSON file
  from `fluoh run --session-file` and reports launch state, VM Service URI,
  output logs, attach hints, and the recommended next step.

## Request Routing

- Install, update, or reload the skill: if needed, run CLI Setup, run
  `fluoh upgrade`, then run `fluoh skill --json` and use `localPath`,
  `skillVersion`, `installPrompt`, and `upgradePrompt` to reinstall or reload
  the returned skill, overwriting any existing fluoh skill when the host agent
  supports it. If the host cannot reload skills now, report that blocker.
- Install or set up fluoh: run the CLI Setup section, then continue with the
  requested workflow.
- Make an existing Flutter app support OHOS: run preflight, then use
  `references/app-project-flow.md`.
- Adapt a third-party package or upstream Git URL: run preflight or
  `fluoh package discover <upstream> --json`, then use
  `references/package-adaptation-flow.md`.
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
   `deliveryChecks`.
6. If the user specified an SDK version or line, use it. Otherwise keep the SDK
   recorded in `fluoh.yaml`; when none is recorded, run `fluoh sdk list` and
   choose the latest stable FlutterOH SDK line.

## CLI Setup

1. Run `fluoh --version`.
2. If `fluoh` is missing and the user asked to use `$fluoh`, set up fluoh, or
   adapt a project/package, install the CLI without another confirmation. This
   setup step does not authorize project, package, Source, or Git state
   changes.
3. Prefer Dart pub when `dart --version` works:
   `dart pub global activate fluoh`.
4. If the Dart global install succeeds but `fluoh` is still not on `PATH`, use
   `$HOME/.pub-cache/bin/fluoh` for this session and tell the user to add
   `$HOME/.pub-cache/bin` to `PATH`.
5. For strict JSON automation, prefer the native/Homebrew executable when it is
   available. Dart pub global shims are acceptable only after confirming a
   `--json` command starts stdout with `{`.
6. On macOS, if Dart is unavailable or the Dart pub shim emits non-JSON startup
   text before JSON diagnostics, and Homebrew is available, run
   `brew tap FlutterOH/fluoh https://github.com/FlutterOH/fluoh.git` and
   `brew install FlutterOH/fluoh/fluoh`. Do not use
   `brew tap FlutterOH/tap` unless that official tap repository is available.
7. If neither Dart nor Homebrew can install the CLI, ask the user to install
   Dart or provide a `fluoh` executable path.
8. After installation, run `fluoh --version`, then continue with preflight.

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

After approval, local code edits, project-file edits, and local checkpoint
commits are allowed when the workflow needs them. Keep release, push,
force-push, and destructive Git operations separately approved.

## Preflight Routing

When using `scripts/preflight.py`, route by the returned JSON:

- Missing path, unknown project, or `dart-package`: do not edit. Ask for the
  project path, or create a package repository only when the user gave an
  upstream Git URL.
- `app-project`: use `references/app-project-flow.md`.
- `flutter-package`: create a FlutterOH package repository first; do not add
  OHOS implementation files directly in the upstream checkout.
- `package-repository`: use `references/package-adaptation-flow.md` and confirm
  the selected package matches the user's request.
- `upgradeChecks`: when preflight requires a newer fluoh, run `fluoh upgrade`,
  refresh the skill with `fluoh skill --json` when the host supports it, then
  handle schema migration and generated-doc refresh blockers before
  implementation edits. Generated `README.md`, `FLUOH.md`, and `AGENTS.md`
  sections are tool-owned; do not edit inside `fluoh:generated` blocks by hand.
- `reportCommand`, `summaryCommand`, `scenarioCommand`, and
  `sessionInspectCommand`: prefer these exact helper commands over
  reconstructing paths manually.

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
- Treat doctor, toolchain, and device diagnostics as local-environment work
  until the local diagnostic is clean.
- Treat build failures, install failures, launch failures, runtime crashes,
  Flutter channel errors, integration-test failures, and package test failures
  as code or project issues only after the local toolchain diagnostic is clean.

## Evidence Loop

Use this loop for app and package work:

1. Run preflight and select exactly one package when selection is required.
2. Run the suggested verify/build/run commands until diagnostics are clean or a
   blocker is explicit.
3. When an interactive flow, permission prompt, file picker, camera, location,
   media, deep link, external app callback, or lifecycle behavior matters, use
   `references/automation-evidence-flow.md`.
4. Make the smallest implementation, scenario, test, or project-file change
   needed for the next clean verification result.
5. Rerun the exact failed command, or the printed rerun/validation command from
   JSON diagnostics.
6. Run `scripts/collect_feedback.py` on the trace session when feedback
   candidates exist.
7. Write and check the report before the final response.

Launch success is smoke evidence. Release-ready interaction evidence must come
from `integration_test`, `fluoh automate --scenario <path> --json`, or
manual-assisted tool-readable verification with a concrete blocker or result.
Do not rely on screenshot recognition as the primary assertion.

## Completion Report

Before the final response, create a local report under:

```text
.fluoh/reports/<report-group>/ai-report-YYYYMMDD-HHMMSS.md
```

For package work, `<report-group>` is normally the package name slug. For
multi-package monorepos, also create a summary report under:

```text
.fluoh/reports/<scope-slug>/summary-YYYYMMDD-HHMMSS.md
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
recommendation requires all applicable checklist items to be done and
`check_report.py` to pass.

The final response should state whether the work is ready, blocked, or needs a
maintainer decision; point to the report path; and list only the remaining
blocking risks.
