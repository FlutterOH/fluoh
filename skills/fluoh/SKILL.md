---
name: fluoh
description: Use this skill when adapting Flutter apps or Flutter package repositories to FlutterOH/OHOS with the fluoh CLI. Trigger for requests like making a project support OHOS, adapting a third-party Flutter package for FlutterOH, running fluoh doctor/verify/build/run diagnostics, interpreting fluoh JSON nextCommand/diagnostics, or producing a FlutterOH adaptation report.
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
  package, selected SDK, suggested next commands, and `reportCommand`. It is
  read-only.
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
2. Run preflight when possible.
3. Create a package repository with `fluoh package create <upstream>` only when
   the user provided an upstream Git URL and no package repository exists.
4. Route to the app or package flow from preflight JSON.
5. Run `fluoh` commands in JSON mode whenever supported, then inspect
   `nextCommand`, `diagnostics`, and log tails before editing.
6. Make the smallest code or project-file changes needed for the next clean
   verification result.
7. Verify and write the completion report before the final response.

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
- "Only check/review": stop after read-only commands and dry-runs; do not apply
  `deps fix`, writes, releases, pushes, or destructive Git operations.

## Start

1. Read the repository `AGENTS.md` first when it exists.
2. Run the CLI Setup flow before the first workflow command, or run the
   preflight script to collect the same version check with project shape. When
   working inside the fluoh CLI repository itself, use `dart run bin/fluoh.dart`
   only for validating the CLI; use the installed `fluoh` command for user
   project adaptation.
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
4. If preflight reports `needsPackageSelection: true`, select one package for
   the current iteration and rerun preflight with `--package <name>` before
   running package commands.
5. Use preflight `suggestedCommands` for the implementation loop and
   `finalCheckCommands` plus `deliveryChecks` as the final acceptance gate.
   Do not give a ready recommendation until those checks have evidence or an
   explicit blocker in the report.
6. Prefer exact commands shown by generated `AGENTS.md` and `FLUOH.md` in a
   package repository. Use this skill only to choose the next step and keep the
   loop short.
7. If the user specified an SDK version or line, use it. Otherwise keep the SDK
   already recorded in `fluoh.yaml`; when none is recorded, run `fluoh sdk list`
   and choose the latest stable FlutterOH SDK line.
8. Treat a request to "adapt", "fix", "make it support OHOS", or "hand it to
   AI" as authorization to make local code and project-file changes. Still ask
   before public API breaks, release version changes, real releases, pushes, or
   destructive Git operations.

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
5. On macOS, if Dart is unavailable but Homebrew is available, run
   `brew tap FlutterOH/tap` and `brew install fluoh`.
6. If neither Dart nor Homebrew can install the CLI, ask the user to install
   Dart or provide a `fluoh` executable path.
7. After installation, run `fluoh --version`, then continue with preflight.

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
- Use `project.packages[].examplePlatforms` to decide which Android, iOS, and
  macOS regression checks are relevant.
- Use `finalCheckCommands` and `deliveryChecks` as the final acceptance checklist.
- Use `reportCommand` to create the local completion report skeleton.
- Use `reportCheckCommand` after filling the report.

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
fluoh package create <upstream-git-url> --sdk <sdk-version-or-line> [--repository <flutteroh-repo-url>]
cd <generated-repo>
```

Then run this loop one package at a time:

```sh
fluoh deps get
fluoh doctor -p --json --strict
fluoh verify --package <name> --json
fluoh run --platform ohos --package <name> --json
fluoh build --platform ohos --package <name> --auto-sign --json
fluoh package status --package <name>
fluoh package release --package <name> --dry-run --json
```

## Automatic Adaptation Command Flow

Use this flow as the primary package-adaptation loop. The commands decide when
to edit, when to fix local environment, and when work can be handed back.

1. Repository setup: use `fluoh package create <upstream>` for a new package
   repository, `fluoh package add <package-path>` for additional packages, and
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
   for a connected hdc target. If no device is available, use
   `fluoh build --platform ohos --package <name> --auto-sign --json` as
   build-only evidence.
5. Existing-platform regression: when `example/android` exists, run
   `fluoh doctor --platform android --json --strict`, then
   `fluoh run --platform android --package <name> --json`. Do the same for iOS
   and macOS when their example platform directories exist.
6. Diagnostics loop: read `nextCommand`, `diagnostics[].code`, `stdoutTail`,
   `stderrTail`, and saved run logs from JSON output before editing. Fix
   `doctor` failures in local tooling, project warnings in repository
   configuration, and verification failures in the code or example that
   produced the diagnostic.
7. Completion report: write
   `.fluoh/ai-report-<package-or-scope>-YYYYMMDD-HHMMSS.md` with commands,
   results, platform matrix, signing mode, logs, remaining risks, and release
   recommendation.
8. Release gate: run `fluoh package status --package <name>`, the final
   `fluoh verify --package <name>`, and
   `fluoh package release --package <name> --dry-run`. Commit only after the
   relevant gate succeeds; run the real release command only when the maintainer
   approves tagging.

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
- Extend package tests or examples when behavior changes. Example UI should
  expose visible operations, expected results, pass/fail status, and failure
  hints for manual platform checks.
- Use `fluoh run --platform ohos --package <name> --json` when a target exists.
  Use the `build --auto-sign` command as the fallback when no target is
  available.
- Run existing-platform regression checks when corresponding example platform
  directories exist and local toolchains are available:
  `fluoh run --platform android|ios|macos --package <name> --json`.
- Do not run real `fluoh package release`, push, force-push, or destructive Git
  commands unless the user explicitly asks.

## JSON Diagnostics

For every `--json` command:

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
platform evidence, remaining risks, and release recommendation. Mark every
applicable Delivery Checklist item as done, or leave it unchecked and explain
the blocker. A ready recommendation requires all applicable checklist items to
be done.
Run `python3 <skill-dir>/scripts/check_report.py <report-path>` before the final
response; if it fails, fix the report or explain why the remaining blocker is
intentional.

The final response should state whether the work is ready, blocked, or needs a
maintainer decision; point to the report path; and list only the remaining
blocking risks.
