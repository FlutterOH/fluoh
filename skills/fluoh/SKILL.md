---
name: fluoh
description: Use this skill when adapting Flutter apps or Flutter package repositories to FlutterOH/OHOS with the fluoh CLI, or when maintaining FlutterOH Source data with fluoh source checks. Trigger for requests like making a project support OHOS, adapting a third-party Flutter package for FlutterOH, running fluoh doctor/verify/build/run/source check diagnostics, interpreting fluoh JSON nextCommand/diagnostics, prechecking a FlutterOH/source pull request, or producing a FlutterOH adaptation report.
---

# fluoh

Use `fluoh` as the deterministic toolchain and this skill as the AI orchestration
layer. The CLI owns SDK selection, dependency rewrites, doctor checks, package
repository setup, build/run execution, signing, and JSON diagnostics. The agent
owns code inspection, implementation, test updates, diagnostic routing, and the
completion report.

## Helper Scripts

Bundled scripts are optional, agent-neutral shortcuts. They use only the Python
standard library and do not replace the `fluoh --json` diagnostic contract.

- Preflight:
  `python3 <skill-dir>/scripts/preflight.py <project-path> [--package <name>]`
  prints one JSON object with the installed `fluoh --version` result, workspace
  kind, Git state, registered packages, package example platforms, selected
  package, selected SDK, upgrade checks, suggested next commands, and
  `reportCommand`. It is read-only.
- Report skeleton:
  `python3 <skill-dir>/scripts/new_report.py <project-path> --scope <scope>
  [--package <name>] [--recommendation ready|needs-maintainer-decision|blocked]`
  creates `.fluoh/ai-report-<scope>-YYYYMMDD-HHMMSS.md` from
  `references/report-template.md`. Fill the generated report with actual command
  evidence before the final response.
- Report check:
  `python3 <skill-dir>/scripts/check_report.py <report-path>` prints JSON and
  fails when a report is missing required sections, command evidence, delivery
  checklist state, or still contains placeholders.
- Scenario skeleton:
  `python3 <skill-dir>/scripts/new_scenario.py <project-path> --platform <platform>
  --name <scenario-name> [--package <name>] [--app]` creates a local
  `.fluoh/scenarios/...md` scenario from the bundled interaction template.
- Session inspector:
  `python3 <skill-dir>/scripts/inspect_session.py <session-file> --wait 30
  --expect-platform <platform> [--require-vm-service]` reads a live
  `flutterRunSession` JSON file from `fluoh run --session-file` and reports
  launch state, VM Service URI, target, output log, attach hints, and a
  machine-readable recommendation.
- Interaction scenario template:
  copy `references/interaction-scenario-template.md` to
  `.fluoh/scenarios/<package-or-app>-<platform>-<name>.md` when a UI or device
  capability flow needs device-side functional verification.

## AI-Driven Default Flow

Use this skill as the primary interface for both existing Flutter apps and
third-party package adaptation. The user should only need a short request such
as:

```text
Use $fluoh to install fluoh if needed and adapt this Flutter project for OHOS.
Use $fluoh to adapt <upstream-git-url> for FlutterOH, SDK 3.35.
```

Then:

1. Install the `fluoh` CLI if it is missing.
2. Run read-only preflight when possible.
3. For package adaptation, resolve setup values before any mutating package
   command or implementation edit: the FlutterOH package `repository` URL or
   path, `git-author-name`, `git-author-email`, SDK line, package selection, and
   output path. Use user-provided values, `fluoh.yaml`, local Git config, or
   documented defaults. Ask only when a required value is missing, contradictory,
   or would change public repository or author identity; otherwise proceed and
   record the resolved values in progress output and the report.
4. Inspect preflight `upgradeChecks`. Stop for schema migration blockers. If
   package generated docs are stale, or preflight could not confirm them with
   dry-run, run `fluoh package docs refresh --dry-run`; then run
   `fluoh package docs refresh` before implementation edits when the worktree is
   clean and the task is not review-only.
5. Create a package repository with `fluoh package create <upstream>` only when
   the user provided an upstream Git URL and no package repository exists, and
   pass resolved `--repository`, `--git-author-name`, and `--git-author-email`
   values when available.
6. Route to the app or package flow from preflight JSON.
7. Run `fluoh` commands in JSON mode whenever supported, then inspect
   `nextCommand`, `diagnostics`, and log tails before editing.
8. Make the smallest code or project-file changes needed for the next clean
   verification result.
9. Verify and write the completion report before the final response.

## User Request Routing

- "Install/update the skill": prefer the agent's skill installer with
  `https://github.com/FlutterOH/fluoh/tree/main/skills/fluoh`; when `fluoh` is
  already installed, run
  `fluoh skill --json` and follow `localPath`, `skillVersion`,
  `installPrompt`, and `upgradePrompt`.
- "Install/setup fluoh" or any adaptation request where `fluoh` is missing:
  run the CLI Setup flow, then continue.
- "Make this app support OHOS": run preflight in the current Flutter app, then
  use the App Project Flow.
- "Adapt this Git URL/package for FlutterOH": create or enter a package
  repository, then use the Package Adaptation Flow.
- "Continue/fix/check <package-name>": run preflight with
  `--package <package-name>` when the repository has multiple packages.
- "Check/precheck/review a FlutterOH Source PR": use the Source Maintenance
  Flow. Treat the result as deterministic technical evidence, not as an AI
  approval decision.
- "Maintain/update Source data": use
  `fluoh source check [path] --schema-only --json` for local YAML/index gates,
  `fluoh source sync [path]` for generated release records, and normal
  `fluoh source check ... --json` for PR or CI release verification; do not edit
  generated release records when `source sync` is the right source of truth.
- "Only check/review": stop after read-only commands and dry-runs; do not apply
  `deps fix`, writes, releases, pushes, or destructive Git operations.

## Start

1. Read the repository `AGENTS.md` first when it exists.
2. Run the CLI Setup flow before the first workflow command, or run the
   preflight script to collect the same version check with project shape. When
   working inside the fluoh CLI repository itself, use `dart run bin/fluoh.dart`
   only for validating the CLI. Do not use `dart run bin/fluoh.dart ... --json`
   as a machine interface because the Dart launcher can print dependency
   resolution text before fluoh starts; use the installed `fluoh` command for
   user project adaptation and every JSON diagnostic command.
   If the user asks to install or update this skill, run `fluoh skill --json`
   and follow its `localPath`, `skillVersion`, `installPrompt`, and
   `upgradePrompt`; do not assume a fixed agent skill directory.
3. Inspect the current directory, preferably from preflight JSON when the script
   is available:
   - App project: `project.kind: app-project`.
   - Upstream Flutter package: `project.kind: flutter-package`; create a
     FlutterOH package repository first and do not add OHOS implementation files
     directly in the upstream checkout.
   - Package adaptation repo: `fluoh.yaml` registers `packages`.
   - Dart package/tooling repo: `project.kind: dart-package`; do not run App or
     Package adaptation commands unless the user points to a Flutter project or
     package.
   - New package adaptation: user provides an upstream Git URL and no generated
     package repository exists yet.
4. Before package adaptation writes or package repository creation, resolve the
   adaptation setup. For a new repository, derive or use `repository`,
   `git-author-name`, `git-author-email`, SDK line, selected package paths, and
   output path. For an existing package repository, read `repository.git.url`
   from `fluoh.yaml` and `git config --local --get user.name` / `user.email`.
   Ask only for missing or contradictory required values, then configure local
   Git author before creating commits.
5. If preflight reports `needsPackageSelection: true`, build a package queue
   when the user asked for the whole repository, otherwise select one package for
   the current iteration. Rerun preflight with `--package <name>` before running
   package commands, and finish each package's checkpoints before moving to the
   next package.
6. Inspect preflight `upgradeChecks` before implementation edits:
   - If `upgradeChecks.schema.status` is `requires-newer-fluoh`, run
     `fluoh upgrade`, rerun `fluoh skill --json` when the agent copied the
     skill, then rerun preflight.
   - If `upgradeChecks.needsMigration` is true for any other schema status,
     stop and report the migration blocker instead of editing project or
     package code.
   - If `upgradeChecks.packageDocs.hasNewerTemplate` is true, upgrade fluoh,
     refresh copied skill files when needed, and rerun preflight before any
     generated-doc refresh.
   - If `upgradeChecks.packageDocs.needsRefresh` is true, run
     `fluoh package docs refresh --dry-run`. In full adaptation requests,
     run `fluoh package docs refresh` before code edits when the worktree is
     clean; in review-only requests, report the refresh as a proposed change.
   - If `upgradeChecks.packageDocs.needsRefreshUnknown` is true, fix the
     reported dry-run failure and rerun `fluoh package docs refresh --dry-run`
     before assuming generated docs are current.
7. Use preflight `suggestedCommands` for the implementation loop and
   `finalCheckCommands` plus `deliveryChecks` as the final acceptance gate.
   Do not give a ready recommendation until those checks have evidence or an
   explicit blocker in the report.
8. Prefer exact commands shown by generated `AGENTS.md` and `FLUOH.md` in a
   package repository. Use this skill only to choose the next step and keep the
   loop short.
9. If the user specified an SDK version or line, use it. Otherwise keep the SDK
   already recorded in `fluoh.yaml`; when none is recorded, run `fluoh sdk list`
   and choose the latest stable FlutterOH SDK line.
10. Treat a request to "adapt", "fix", "make it support OHOS", or "hand it to
    AI" as authorization to make local code and project-file changes and local
    checkpoint commits when the workflow needs them. Still ask before public API
    breaks, non-default release version policy or manual release version
    overrides, real releases, pushes, or destructive Git operations. Normal
    `fluoh package version --bump patch --status ...` metadata updates in the
    package adaptation flow do not need a separate confirmation.

## CLI Setup

Use this before running workflow commands:

1. Run `fluoh --version`.
2. If `fluoh` is missing and the user asked to use `$fluoh`, set up fluoh, or
   adapt a project/package, install the CLI without another confirmation.
3. Prefer Dart pub when `dart --version` works:
   `dart pub global activate fluoh`.
4. If the Dart global install succeeds but `fluoh` is still not on `PATH`, use
   `$HOME/.pub-cache/bin/fluoh` for this session and tell the user to add
   `$HOME/.pub-cache/bin` to `PATH`.
5. For strict JSON automation, prefer the native/Homebrew executable when it is
   available. Dart pub global shims invoke `dart pub global run`; after using
   one, confirm a `--json` command starts stdout with `{` before parsing it as
   the machine contract.
6. On macOS, if Dart is unavailable or the Dart pub shim emits non-JSON startup
   text before JSON diagnostics, and Homebrew is available, run
   `brew tap FlutterOH/tap` and `brew install fluoh`.
7. If neither Dart nor Homebrew can install the CLI, ask the user to install
   Dart or provide a `fluoh` executable path.
8. After installation, run `fluoh --version`, then continue with preflight.

## Preflight Routing

When using `scripts/preflight.py`, route by the returned JSON:

- `pathExists: false`, `pathIsDirectory: false`, `project.kind: unknown`, or
  `project.kind: dart-package`:
  do not edit. Ask for the project path, or run `fluoh package create
  <upstream>` only when the user gave an upstream Git URL.
- `project.kind: app-project`: run the App Project Flow. Use
  `project.sdkVersion` in `fluoh sdk use` when present.
- `project.kind: flutter-package`: create a FlutterOH package repository from
  the upstream Git URL or local Git repo path, then rerun preflight in the
  generated repository before editing.
- `project.kind: package-repository`: run the Package Adaptation Flow. When
  `needsPackageSelection` is true, choose one `project.packages[].name` before
  running package commands.
- `upgradeChecks`: handle schema and generated-doc upgrade checks before
  implementation edits. Generated `FLUOH.md` and `AGENTS.md` sections are
  tool-owned; do not edit inside `fluoh:generated` blocks by hand.
- Use `project.packages[].examplePlatforms` to decide which Android, iOS, and
  macOS regression checks are relevant.
- Use `finalCheckCommands` and `deliveryChecks` as the final acceptance checklist.
- Use `reportCommand` to create the local completion report skeleton.
- Use `reportCheckCommand` after filling the report.
- Use `sessionInspectCommand` to wait for and inspect a live
  `flutterRunSession` file created by `fluoh run --session-file`.
- Use `scenarioCommand` when an interaction flow needs an AI-assisted scenario.

## Complete AI Evidence Loop

Use this loop when adapting a package or app to a release-ready state:

1. Run preflight and pick exactly one package when selection is required.
2. Run the suggested verify/build/run commands until diagnostics are clean or a
   blocker is explicit.
3. For OHOS, record the `fluoh run --platform ohos ... --json` result as build,
   signing, install, launch, hilog, and crash-diagnostic evidence. If the
   package has an interactive flow, perform a separate AI-assisted scenario on
   the target and record functional assertions from hilog, logs, accessible
   text, semantic labels, stable status text, or other machine-readable output.
4. For Android, iOS, and macOS, run with a live session file when an agent needs
   to inspect the running app:

   ```sh
   fluoh run --platform android --package <name> \
     --session-file .fluoh/run-session-android.json --json
   python3 <skill-dir>/scripts/inspect_session.py \
     .fluoh/run-session-android.json --wait 30 \
     --expect-platform android --require-vm-service
   ```

   Use the resulting `vmServiceUri`, output log, widget/component tree,
   semantics tree, stable text, test keys, or log markers as primary evidence.
5. Fill `.fluoh/ai-report-...md` with the exact commands, exit codes, platform
   matrix, scenario path, interaction evidence, remaining risks, and release
   recommendation.
6. Run `python3 <skill-dir>/scripts/check_report.py <report-path>` and do not
   claim `ready` until it passes. If it fails, either collect the missing
   evidence or mark the release decision as blocked or needing a maintainer
   decision. A report whose recommendation is `blocked` or
   `needs maintainer decision` can be kept as handoff evidence, but it must not
   be passed to `fluoh package check --report` or `fluoh package release
   --report` as release certification.

## App Project Flow

Use this when the user asks to make an existing Flutter project support OHOS.

```sh
fluoh source update
fluoh sdk use <sdk-version-or-line> --pub-get
fluoh deps check --json
fluoh deps fix --dry-run
fluoh deps fix              # apply only after reviewing the dry-run plan
fluoh deps get
fluoh doctor -p --platform ohos --json --strict
fluoh build --platform ohos --auto-sign --json
fluoh devices --platform ohos --json
fluoh run --platform ohos --device <id> --json
```

Rules:

- `fluoh sdk use` creates `ohos/` by default when missing. Add
  `--no-init-ohos` only when another workflow owns platform creation.
- Run `deps fix --dry-run` before writing dependency changes. In fully
  automatic adaptation requests, apply `deps fix` after reviewing that the plan
  contains only expected FlutterOH replacements. In review-only requests, stop
  at the dry-run and report the proposed changes.
- If `deps check --json` reports unavailable, blocked, or SDK-mismatch
  dependencies, record them as blockers or maintainer decisions. Do not invent
  package implementations inside the app project unless asked.
- If no OHOS target is available, keep the signed HAP build as build-only
  evidence and record the missing target instead of forcing a run.
- For real target runs, prefer an explicit `--device <id>` from
  `fluoh devices --platform ohos --json`; use `--emulator <name>` only after
  selecting from `fluoh emulators --platform ohos --json`.

## Package Adaptation Flow

Use this when the user asks to adapt a third-party Flutter package.

When starting from upstream:

```sh
fluoh package create <upstream-git-url> --sdk <sdk-version-or-line> \
  --repository <flutteroh-repo-url-or-path> \
  --git-author-name <name> --git-author-email <email>
cd <generated-repo>
```

Before running this command, resolve the repository URL or path recorded for the
FlutterOH adaptation, the local Git author name and email, the SDK line, package
paths, and output path. Ask only when a required value is missing or
contradictory. If author configuration is unavailable, omit both Git author
options; never pass only one.

Then run this loop one package at a time:

```sh
fluoh deps get
fluoh doctor -p --json --strict
fluoh verify --package <name> --json
fluoh run --platform ohos --package <name> --json
fluoh build --platform ohos --package <name> --auto-sign --json
fluoh package status --package <name>
fluoh package version --package <name> --bump patch --status compatible
fluoh package check --package <name> --json
```

## Automatic Adaptation Command Flow

Use this flow as the primary package-adaptation loop. The commands decide when
to edit, when to fix local environment, and when work can be handed back.

1. Repository setup: use `fluoh package create <upstream>` for a new package
   repository with resolved repository and Git author options, use
   `fluoh package add <package-path>` for additional packages, and use
   `fluoh package sync` only after a completed, committed checkpoint when
   upstream needs to be merged.
2. Baseline gates: run `fluoh deps get`,
   `fluoh doctor -p --json --strict`, `fluoh flutter analyze`, and relevant
   existing package or example tests before adding OHOS code. Project warnings
   point to repository files; environment warnings point to local tool or Source
   setup.
3. Implementation loop: after meaningful code or metadata changes, rerun
   `fluoh deps get` when dependencies or SDK metadata changed, then use
   `fluoh verify --package <name> --json` until pub get, analysis, and existing
   tests pass.
4. OHOS verification: use
   `fluoh run --platform ohos --package <name> --json`, or add `--device <id>`
   for a connected hdc target. This proves build, signing, install, launch, and
   hilog diagnostics; it does not prove tappable example workflows by itself.
   If no device is available, use
   `fluoh build --platform ohos --package <name> --auto-sign --json` as
   build-only evidence.
5. Existing-platform regression: when `example/android` exists, run
   `fluoh doctor --platform android --json --strict`, then
   `fluoh run --platform android --package <name> --json`. Do the same for iOS
   and macOS when their example platform directories exist.
6. Interaction verification: for workflows that need UI taps, permission
   prompts, file pickers, camera, location, media, deep links, or external
   apps, run `integration_test/` when available. When deterministic tests do
   not exist, perform an AI-assisted functional pass on the emulator/device:
   follow a short scenario in `.fluoh/scenarios/<package>-<platform>-<name>.md`
   or write the scenario before running it, interact with the app through the
   available device/browser/computer-use tools, assert results through
   Flutter debug or VM service output when available, widget/component tree
   state, semantics tree, integration-test output, accessibility text, visible
   status text, semantic labels, test keys, or structured log markers, and
   record step results, target id, evidence path, and blockers in the report.
   For Android, iOS, and macOS `fluoh run --json` exposes
   `details.vmServiceUri` on the run step when Flutter prints a VM Service or
   debug service URI. Pass `--session-file <path>` on those runs when an AI or
   external inspector needs an attach point before final JSON is printed; fluoh
   writes a live `flutterRunSession` JSON file while the app is still running.
   Then run `inspect_session.py` or the preflight `sessionInspectCommand` to
   wait for launch, read the VM Service URI, and decide whether to attach,
   inspect logs, or route a failure.
   Do not judge whether the UI looks right unless the package is specifically a
   visual package. Do not assume the AI agent can inspect screenshots;
   screenshots and recordings are optional supporting evidence. Use manual
   interaction only as a fallback when AI automation cannot operate or observe
   the target.
7. Diagnostics loop: read `nextCommand`, `diagnostics[].code`, `stdoutTail`,
   `stderrTail`, and saved run logs from JSON output before editing. Fix
   `doctor` failures in local tooling, project warnings in repository
   configuration, and verification failures in the code or example that
   produced the diagnostic.
8. Implementation checkpoint: once implementation, OHOS evidence, and applicable
   existing-platform regression checks are clean or explicitly blocked, create a
   local implementation checkpoint commit. This clean worktree is required before
   `fluoh package version`, `fluoh package sync`, and `fluoh package check`.
9. Release metadata checkpoint: run `fluoh package status --package <name>`,
   update release metadata with `fluoh package version --package <name>` when
   needed, update `FLUOH_CHANGELOG.md`, review `fluoh.yaml`, then create a local
   release metadata checkpoint commit. `fluoh package version` requires a clean
   worktree before it writes metadata, so do not leave implementation changes
   uncommitted before this step.
10. Final report and release gate: rerun the final
    `fluoh verify --package <name>`, write
    `.fluoh/ai-report-<package-or-scope>-YYYYMMDD-HHMMSS.md` with commands,
    results, platform matrix, interaction evidence, signing mode, logs,
    remaining risks, and release recommendation, then run
    `python3 <skill-dir>/scripts/check_report.py <report-path>`. Because
    `.fluoh/` is local ignored state, the worktree should remain clean for
    `fluoh package check --package <name> --report <report-path>`. Add
    `--require-ohos-run` when a connected target or emulator was available and
    the handoff must prove a passed real OHOS launch. The certification report
    must contain passed command rows, not only failed diagnostic rows. Run
    `fluoh package release` only when the maintainer approves the fluoh release.
    Maintainers can still run `fluoh package check` without a certification
    report after their own manual verification; that path is a baseline release
    check, not an AI-certified delivery.
11. Local commit checkpoints: create small local commits at completed
    checkpoints when the workflow needs commits, such as before package sync,
    package check, or handoff. Before each commit, self-review the staged paths,
    commit message, and local Git author identity; stage explicit paths, review
    `git diff --cached`, and keep commits local unless the maintainer explicitly
    asks to push.

Rules:

- Read generated `AGENTS.md`, `FLUOH.md`, `FLUOH_CHANGELOG.md`, and
  `fluoh.yaml` before editing.
- If the repository has multiple packages, pick one package per iteration unless
  the user explicitly asks for `--all`.
- Preserve upstream public Dart APIs and non-OHOS behavior unless the user
  approves a breaking change.
- Establish a selected-SDK baseline before adding OHOS code. Fix non-OHOS
  regressions first when Android, iOS, macOS, tests, or examples already exist.
- Implement OHOS code near the package path recorded in `fluoh.yaml`.
- Extend package tests or examples when behavior changes. Example apps are
  functional harnesses: they should expose operations, expected results,
  pass/fail status, and failure hints for automated or AI-assisted platform
  checks. Prefer machine-readable evidence such as Flutter debug output,
  widget/component tree state, semantics tree, semantic labels, stable text
  status, test keys, and log markers so non-vision AI agents can verify the
  flow without knowing what the UI looks like.
- Treat `fluoh run` launch success as smoke evidence. Release-ready interaction
  evidence must come from `integration_test`, AI-assisted scenario execution, or
  an explicitly accepted manual fallback.
- AI-assisted scenarios must be usable without screenshot recognition. Prefer
  Flutter debug or VM service output, widget/component tree state,
  integration-test assertions, accessibility or semantics tree output, visible
  text, semantic labels, stable test keys, command JSON, hilog, or app log
  markers as primary evidence; screenshots or screen recordings are supporting
  artifacts only.
- Cover the scenario classes that apply to the package: permission prompts,
  file or media pickers, camera and microphone capture, location and sensors,
  maps, media playback/recording, deep links and external app callbacks,
  background or lifecycle behavior, error/denied-permission paths, and
  multi-step forms. Mark irrelevant classes as not applicable in the report
  rather than silently skipping them.
- Use `fluoh run --platform ohos --package <name> --json` when a target exists.
  Use the `build --auto-sign` command as the fallback when no target is
  available.
- Run existing-platform regression checks when corresponding example platform
  directories exist and local toolchains are available:
  `fluoh run --platform android|ios|macos --package <name> --json`.
- Do not run real `fluoh package release`, push, force-push, or destructive Git
  commands unless the user explicitly asks.

## Source Maintenance Flow

Use this when the user asks to check a FlutterOH Source checkout, precheck a
FlutterOH/source pull request, or validate Source data after syncing released
Package repositories.

```sh
# Local YAML/index validation only.
fluoh source check [path] --schema-only --json

# Pull request or changed-route verification.
fluoh source check <source-pr-url> --json
fluoh source check . --json

# Full Source audit.
fluoh source check . --all --json
```

Rules:

- Use `--schema-only` only for local Source paths when the workflow needs pure
  YAML/index validation, such as before or after `fluoh source sync` or manual
  route edits. It does not read Git diffs, fetch SDK tags, clone Package
  repositories, verify declared releases, or touch config, snapshots, or locks.
  It reports `schemaOnly: true` in JSON and rejects PR URLs, diff options,
  release options, work-root options, and Package verification filters.
- Use normal `fluoh source check ... --json` for PR readiness, merge gates, and
  release verification. It is read-only, validates Source YAML, computes changed
  Manifest routes from Git when possible, and verifies declared Package release
  tags with `fluoh package check --package <name> --json`.
- For pull requests, pass the GitHub PR URL directly when available. The command
  clones the Source repository and fetches the PR ref through Git; it does not
  need an AI agent or GitHub API to decide the technical result.
- By default, check only Manifest files changed from `--base-ref`. If only the
  Source root `fluoh.yaml` changed, fluoh compares Manifest route names between
  the base ref and HEAD, checks only added or removed routes, and does not turn
  SDK-only root metadata changes into full Manifest verification.
- Use `--all` for scheduled release-gate jobs. Use `--skip-release-checks` when
  a normal diff-aware check should validate YAML and changed-route selection
  without cloning Package repositories.
- Read the JSON `schemaOnly`, `recommendation`, `errors`, `warnings`,
  `changedFiles`, `checkedManifests`, and `releaseChecks`. `ready` means
  technical checks pass, `blocked` means fix errors before merge, and
  `needs-maintainer-decision` means a human maintainer must decide.
- Source PR automation should publish the JSON summary as a check or comment.
  Do not approve, merge, push, or rewrite Source data automatically.
- Use `fluoh source sync [path]` only to import release records from already
  released FlutterOH Package repositories. Routing, advisory, and maintenance
  metadata remain direct Source/Manifest YAML edits.

## JSON Diagnostics

For every `--json` command:

- Invoke the installed `fluoh` executable, not `dart run bin/fluoh.dart`; the
  JSON stdout contract starts after the fluoh process starts, while Dart's
  launcher may print startup dependency text before then. Prefer native/Homebrew
  executables for strict JSON parsing. Dart pub global shims are acceptable only
  after confirming they do not print pub runner text before the JSON object in
  the current environment.
- Parse the JSON object before editing.
- Keep normal progress text out of stdout/stderr when invoking JSON mode; rely
  on the command's JSON object as the contract.
- Follow top-level or step-level `nextCommand` when present.
- Route by `diagnostics[].code` and inspect `stdoutTail`, `stderrTail`, and
  saved log paths before changing code.
- Treat doctor/toolchain/device diagnostics as local-environment work, not code
  defects.
- Treat `dart.pub_get_failed`, `dart.analysis_failed`, `dart.test_failed`,
  platform build failures, install failures, launch failures, runtime crashes,
  and integration-test failures as code or project issues only after the local
  toolchain diagnostic is clean.

## Completion Report

Before the final response, create a local report under `.fluoh/` using:

```text
.fluoh/ai-report-<package-or-scope>-YYYYMMDD-HHMMSS.md
```

Use local time and do not commit this file. Prefer
the preflight `reportCommand` when available, or run
`python3 <skill-dir>/scripts/new_report.py <project-path> --scope <scope>`;
otherwise use `references/report-template.md` directly.
Complete the report with command output summaries, exit codes, changed files,
platform evidence, interaction evidence, remaining risks, and release
recommendation. Mark every applicable Delivery Checklist item as done, or leave
it unchecked and explain the blocker. A ready recommendation requires all
applicable checklist items to be done.
If no interaction scenario applies, write `No interaction required: <reason>` in
the report's `Interaction Evidence` section. Otherwise include at least one
concrete interaction row; `check_report.py` enforces this before final delivery.
Run `python3 <skill-dir>/scripts/check_report.py <report-path>` before the final
response; if it fails, fix the report or explain why the remaining blocker is
intentional.

The final response should state whether the work is ready, blocked, or needs a
maintainer decision; point to the report path; and list only the remaining
blocking risks.
