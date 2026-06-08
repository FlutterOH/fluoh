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
  kind, Git state, package branch metadata, package example platforms, selected
  package, selected SDK, upgrade checks, suggested next commands, and
  `reportCommand` and `summaryCommand`. It is read-only. Use
  `--fluoh-command <path>` or
  `FLUOH_BIN=<path>` when the agent must validate a local fluoh checkout instead
  of the `fluoh` found on `PATH`.
- Report skeleton:
  `python3 <skill-dir>/scripts/new_report.py <project-path> --scope <scope>
  [--package <name>] [--recommendation ready|needs-maintainer-decision|blocked]`
  creates
  `.fluoh/reports/<report-group>/ai-report-YYYYMMDD-HHMMSS.md`
  from `references/report-template.md`. `<report-group>` is the package slug
  when `--package` is supplied and otherwise the scope slug. Fill the generated
  report with actual command evidence before the final response.
- Monorepo summary skeleton:
  `python3 <skill-dir>/scripts/new_summary.py <project-path> --scope <scope>
  [--package <name>]...` creates
  `.fluoh/reports/<scope-slug>/summary-YYYYMMDD-HHMMSS.md` with a
  package matrix, command evidence table, repository state, Fluoh Feedback, and
  next actions. Use it alongside per-package reports for multi-package
  monorepos.
- Report check:
  `python3 <skill-dir>/scripts/check_report.py <report-path>` prints JSON and
  fails when a report is missing required sections, command evidence, delivery
  checklist state, concrete Fluoh Feedback content, or still contains
  placeholders.
- Feedback collection:
  `python3 <skill-dir>/scripts/collect_feedback.py <trace-dir-or-manifest>`
  prints one JSON object with trace summaries, deduplicated feedback candidates,
  and a Markdown table fragment for the report's `Fluoh Feedback` section.
- Scenario skeleton:
  `python3 <skill-dir>/scripts/new_scenario.py <project-path> --platform <platform>
  --name <scenario-name> [--package <name>] [--app]` creates a local
  `.fluoh/scenarios/<package-or-scope>/...md` scenario from the bundled
  interaction template, including platform run and supported session-inspection
  command hints.
- Session inspector:
  `python3 <skill-dir>/scripts/inspect_session.py <session-file> --wait 30
  --expect-platform <platform> [--require-vm-service]` reads a live
  `flutterRunSession` JSON file from `fluoh run --session-file` and reports
  launch state, VM Service URI, target, output log, attach hints, and a
  machine-readable recommendation.
- Interaction scenario template:
  copy `references/interaction-scenario-template.md` to
  `.fluoh/scenarios/<package-or-app>/<platform>-<name>.md` when a UI or device
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
   command or implementation edit: the FlutterOH package repository name,
   `repository` URL or path, `git-author-name`, `git-author-email`, SDK line,
   package selection, upstream target when specified, output path, and any
   explicitly required `flutter create --org` value.
   `fluoh package create` always requires `--repository-name`; for a single
   selected monorepo package, the CLI can suggest a path-based candidate when
   `--repository-name` is missing, but the agent must still pass an explicit
   resolved name. Treat `repository`, Git author identity, SDK line, package
   selection, upstream target, and output path as AI
   automation setup inputs: use
   user-provided values, `fluoh.yaml`, local Git config only after the user
   explicitly agrees to reuse it, or documented defaults that do not change
   public identity. Ask when any setup input is missing or contradictory; do not
   run `fluoh package create` with guessed repository URLs or author identity.
   Record the resolved values in progress output and the report. Prefer
   `fluoh package create <upstream> --repository-name <repository-name> --plan
   --json` to generate the final setup confirmation payload before any writes.
   When the plan contains `implementationRecommendation`, present it in the
   final setup confirmation and use it as the preferred federated path: keep the
   Source route on the app-facing package, create the recommended
   `<package>_ohos` implementation package, add the missing platform
   `default_package` entry, and add the implementation dependency with the
   recommended relative path.
   Inspect `plan.warnings[]` before creating the repository; for
   `package.dart_sdk_incompatible`, keep the selected latest upstream target by
   default and adapt the package to the selected FlutterOH SDK. Start by
   adjusting `pubspec.yaml` `environment.sdk` and example config only when the
   code can support the selected Dart version, then replace newer Dart
   language, SDK API, or dependency usage until `fluoh verify` passes. Use
   `policy.suggestedEnvironmentSdkConstraint` when present as the first
   pubspec constraint candidate. Treat `latestCompatible` as informational
   only; do not pass it with `--upstream-version` unless the maintainer
   explicitly approves an older upstream baseline. For
   `package.default_branch_version_unreleased`, keep the selected release tag
   by default; pass `--upstream-ref <branch>` only when the maintainer
   explicitly approves adapting the unreleased default-branch snapshot.
   For example OHOS scaffolding, omit `--org` by default so fluoh can infer the
   organization from existing Android, iOS, or macOS example metadata; pass
   `--org <organization>` only when the user, upstream docs, or a previous
   failed run identifies the required organization.
   When the user provides a multi-package upstream repository URL but does not
   name a package or `--package-path`, run
   `fluoh package discover <upstream> --json` before setup confirmation. Present
   the discovered Flutter plugin packages missing `ohos`, including package
   names, paths, declared platforms, and `createCommand` values. When a
   candidate contains `implementationRecommendation`, present it as the
   preferred federated path: create the recommended platform implementation
   package, add the missing platform `default_package` entry to the app-facing
   package, and add the implementation dependency instead of treating the
   app-facing package alone as the implementation target. Treat candidates with
   `recommended: false` as context, not default adaptation choices, including
   `covered_by_federated_app_facing_package`, `test_fixture`, and
   `platform_specific_helper_package`; follow `recommended: true` and the
   default `queueCommand` unless the user explicitly selects a context package.
   Then wait for
   the user to choose the package path or implementation recommendation. If
   discovery returns no candidates, ask for an explicit package path or report
   that no Flutter plugin missing `ohos` was found. Do not treat an omitted
   package path as authorization to adapt every package in a monorepo.
4. After CLI setup and read-only preflight, before making project, package, or
   Source file changes, local Git configuration changes, checkpoint commits, or
   implementation edits, present a final setup confirmation and wait for explicit user approval.
   The confirmation must list the adaptation kind,
   working directory, output directory when applicable, SDK version or line,
   package name and path when applicable, FlutterOH repository URL or path, Git
   author identity when commits may be created, explicit `--org` override when
   one will be passed, the mutating commands or file edits that will run, and
   operations that will not run without separate
   approval such as release, push, force-push, or destructive Git commands. You
   may skip this pause only when the user already explicitly approved the same
   resolved setup in the current task.
5. Inspect preflight `upgradeChecks`. Stop for schema migration blockers. If
   package generated docs are stale, or preflight could not confirm them with
   dry-run, run `fluoh package docs refresh --dry-run`; then run
   the refresh command reported by preflight before implementation edits when
   the task is not review-only. Prefer the normal
   `fluoh package docs refresh` on a clean worktree; use
   `fluoh package docs refresh --allow-dirty` only when preflight reports that
   explicit dirty-refresh command, such as immediately after `package create`
   has produced an uncommitted generated baseline.
6. Create a package repository with
   `fluoh package create <upstream> --repository-name <repository-name>` only
   when the user provided an upstream Git URL, no package repository exists, and
   the setup gate is complete. For AI-driven creation, always pass resolved
   `--repository`, `--git-author-name`, and `--git-author-email` values; these
   are optional CLI conveniences for manual users, not optional automation
   inputs. If the user names an upstream package version, pass
   `--upstream-version <version>`; otherwise let create/add/sync choose the
   latest valid release tag after fetching upstream tags. For `sync`, never
   request a lower upstream version; mark the current adaptation `broken`
   instead.
   When a package was selected from discovery, pass the selected
   `--package-path` to `package create` and record the discovery command and
   selected candidate in the report.
   If a real run reports ambiguous Flutter example organization, rerun
   create/add with the organization required by the upstream example or use the
   fluoh-inferred default when it is printed by the command.
7. Route to the app or package flow from preflight JSON.
8. Run `fluoh` commands in JSON mode whenever supported. For `verify`, `build`,
   and `run`, also pass `--trace-dir
   .fluoh/traces/<package-or-scope>/<session-id>` for the current adaptation
   loop when the command supports it. The manifest for that session is
   `.fluoh/traces/<package-or-scope>/<session-id>/trace.json`; reuse the same
   directory so command invocations accumulate. Inspect `nextCommand`,
   `diagnostics`, trace `feedbackCandidates`, `dirtyAfterVerify`,
   `workingTreeChanges`, and log tails before editing.
9. Make the smallest code or project-file changes needed for the next clean
   verification result.
10. Run feedback collection on the trace session, then verify and write the
    completion report before the final response.

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
- "Adapt this Git URL/package for FlutterOH": when the user provides a
  multi-package upstream URL without naming a package, run
  `fluoh package discover <upstream> --json` and present the package choices
  first; otherwise create or enter a package repository, then use the Package
  Adaptation Flow.
- "Continue/fix/check <package-name>": run preflight with
  `--package <package-name>` to confirm the requested package matches the
  current package branch.
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
   - Package adaptation repo: `fluoh.yaml` has `kind: package` and a
     single `package` entry for the current branch.
   - Dart package/tooling repo: `project.kind: dart-package`; do not run App or
     Package adaptation commands unless the user points to a Flutter project or
     package.
   - New package adaptation: user provides an upstream Git URL and no generated
     package repository exists yet.
4. Before package adaptation writes or package repository creation, resolve the
   adaptation setup. For a new repository, derive or use `repository-name`,
   `repository`, `git-author-name`, `git-author-email`, SDK line, selected
   package path, and output path, then pass the resolved repository name as
   `fluoh package create <upstream> --repository-name <repository-name>`. If
   the upstream is a possible monorepo and the user did not provide a package
   name or path, run `fluoh package discover <upstream> --json`, present the
   `discovery.candidates[]` names, paths, platforms, and `createCommand`
   values, and wait for the user to choose one. If discovery finds no
   candidates, ask for an explicit package path before treating the root package
   as the target. If the user specifies an upstream package version, include
   `--upstream-version <version>`; otherwise rely on the latest valid release
   tag, not upstream HEAD. When syncing an existing package branch, only specify
   the same or a newer upstream version. For a single selected monorepo package, a
   missing-name CLI error can provide a suggested name from the package path,
   but do not rely on implicit naming. For AI-driven new repository creation,
   use the resolved repository name to form or confirm the output directory,
   commonly `../packages/<repository-name>` when the user requested a sibling
   `packages` directory. For an existing package repository, read
   `repository.git.url`
   from `fluoh.yaml` and `git config --local --get user.name` / `user.email`.
   Ask for any missing or contradictory setup value. When values are complete,
   run `fluoh package create <upstream> --repository-name <repository-name>
   --plan --json` with the same resolved options and use that machine-readable
   plan as the final setup confirmation. Inspect `plan.warnings[]` before
   continuing; do not ignore SDK/upstream compatibility warnings just because
   the plan command succeeded. For SDK warnings, continue by adapting package
   config and code to the selected FlutterOH SDK after setup is approved. Do
   not downgrade upstream versions to clear a warning unless the maintainer
   explicitly approves an older baseline. For default-branch version warnings,
   keep the selected release tag unless the maintainer explicitly approves
   `--upstream-ref <branch>` for an unreleased snapshot. Wait for explicit
   approval before configuring local Git author, running mutating commands, or
   editing implementation files.
5. After discovery or an explicit user choice, treat an omitted package path as
   root-package selection only; it never means "all packages" for monorepos.
   For monorepos, preserve one FlutterOH
   adaptation repository for the upstream repository and adapt multiple packages
   as separate package branches in that repository. Do not create one adaptation
   repository per package unless the maintainer explicitly asks for split
   repositories. A Package `fluoh.yaml` describes one package branch. For
   multiple package requests, build a read-only package queue with `fluoh
   package queue <package-path>... --json` and finish one package branch
   checkpoint sequence before moving to the next package. Use `fluoh package
   create` for the first package branch and `fluoh package add <package-path>`
   for additional package branches in the same repository. Use `fluoh package
   add <package-path> --plan --json` when you need a final read-only plan for
   one additional package.
   When verifying multiple existing package branches, prefer a fresh clone or
   separate Git worktree per package branch. Platform build tools can leave
   ignored files that are clean on one branch but become untracked after
   switching to another branch. Do not run destructive cleanup commands such as
   `git clean` without explicit maintainer approval.
   Both commands sync the upstream branch and then select the requested version
   or latest valid release tag for that package. If the package branch already
   exists, check it out and use `fluoh package status` or `fluoh package sync`.
   Rerun preflight with `--package <name>` to confirm the current branch package
   before running package commands.
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
     run the refresh command reported by preflight before code edits. Prefer
     `fluoh package docs refresh` when the worktree is clean; use
     `fluoh package docs refresh --allow-dirty` only when preflight suggests it
     for a dirty generated baseline. In review-only requests, report the refresh
     as a proposed change.
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
    AI" as authorization to run CLI setup, read-only preflight, and setup value
    discovery. It is not authorization to change project files, package
    repositories, Source files, local Git configuration, or implementation code
    until the final setup confirmation is approved. After that approval, local
    code and project-file changes plus local checkpoint commits are allowed when
    the workflow needs them. Still ask before public API breaks, non-default
    release version policy or manual release version overrides, real releases,
    pushes, force-pushes, or destructive Git operations. Normal
    `fluoh package version --bump patch --status ...` metadata updates in the
    package adaptation flow do not need a second confirmation after the final
    setup confirmation.

## CLI Setup

Use this before running workflow commands:

1. Run `fluoh --version`.
2. If `fluoh` is missing and the user asked to use `$fluoh`, set up fluoh, or
   adapt a project/package, install the CLI without another confirmation. This
   setup step does not authorize project, package, Source, or Git state changes.
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
   `brew tap FlutterOH/fluoh https://github.com/FlutterOH/fluoh.git` and
   `brew install FlutterOH/fluoh/fluoh`. Do not use `brew tap FlutterOH/tap`
   unless that official tap repository is available.
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
- `project.kind: package-repository`: run the Package Adaptation Flow. Confirm
  `project.selectedPackage` is the package requested by the user before running
  package commands.
- `upgradeChecks`: handle schema and generated-doc upgrade checks before
  implementation edits. Generated `README.md`, `FLUOH.md`, and `AGENTS.md` sections are
  tool-owned; do not edit inside `fluoh:generated` blocks by hand.
- Use `project.packages[].examplePlatforms` to decide which Android, iOS, macOS,
  Linux, Web, and Windows regression checks are relevant.
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
   blocker is explicit. Treat `fluoh verify` integration-test discovery steps as
   runnable evidence prompts, not as passed interaction evidence; execute the
   concrete platform `fluoh run ... --json` command to run `integration_test/`
   where the platform runner supports it.
3. For OHOS, record the `fluoh run --platform ohos ... --json` result as build,
   signing, install, launch, hilog, and crash-diagnostic evidence. If
   `integration_test/` exists or the package has an interactive flow, ask the
   user to complete the blocked device/emulator operation when fluoh cannot
   automate it, then verify the result through hilog, logs, accessible text,
   semantic labels, stable status text, test keys, or other machine-readable
   output. Record this as `manual-assisted` interaction evidence, not as
   automatic `integration_test` evidence.
4. For Android, iOS, macOS, Linux, Web, and Windows, run with a live session file
   when an agent needs to inspect the running app:

   ```sh
   fluoh run --platform android --package <name> \
     --session-file .fluoh/run-sessions/<name>/android-session.json --json
   python3 <skill-dir>/scripts/inspect_session.py \
     .fluoh/run-sessions/<name>/android-session.json --wait 30 \
     --expect-platform android --require-vm-service
   ```

   `fluoh run` automatically runs `flutter test integration_test -d <device>`
   for current projects and package examples when an `integration_test/`
   directory exists and the platform target supports it. Use the resulting
   command row, `vmServiceUri`, output log, widget/component tree, semantics
   tree, stable text, test keys, or log markers as primary evidence.
5. Fill `.fluoh/reports/<package-or-scope>/ai-report-...md` with the exact
   commands, exit codes, platform matrix, scenario path, interaction evidence,
   remaining risks, and release recommendation.
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
fluoh emulators --platform ohos --json
fluoh run --platform ohos --auto-emulator --json
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
- For OHOS run evidence, prefer `--auto-emulator` so fluoh starts a local
  DevEco emulator before falling back to connected real devices. Keep signed
  HAP build-only evidence only when no local target can be started.
- For explicit real target runs, use `--device <id>` from
  `fluoh devices --platform ohos --json`. Use `--emulator <name>` only when the
  target was selected from `fluoh emulators --platform ohos --json`; when
  multiple OHOS emulators expose API metadata, cover both the lowest and highest
  API versions before claiming broad compatibility.

## Package Adaptation Flow

Use this when the user asks to adapt a third-party Flutter package.

When starting from upstream:

```sh
fluoh package create <upstream-git-url> --sdk <sdk-version-or-line> \
  --repository-name <flutteroh-repo-name> \
  --repository <flutteroh-repo-url-or-path> \
  --git-author-name <name> --git-author-email <email> \
  --package-path <path>
cd <generated-repo>
```

Before running this command, complete the AI setup gate: resolve the FlutterOH
repository name, output path, repository URL or path recorded for the adaptation,
local Git author name and email, SDK line, package paths, and upstream package
version when specified. Omitted package paths mean the root package only, not
every package in a monorepo. Omitted upstream targets resolve to the latest
valid release tag for the selected package after fetching upstream tags, not to
upstream HEAD when release tags exist. Ask when any value is missing or
contradictory. When every value is resolved, first run the same command with
`--plan --json`; use the returned plan as the final setup confirmation and wait
for explicit user approval before running
`fluoh package create`, `fluoh package add`, `fluoh package docs refresh`, or
implementation edits. For multi-package requests, create a package queue and
adapt one branch at a time; use `fluoh package add <package-path>` to create
later package branches from each package's release tag instead of switching
commits manually. Do not omit Git author options in AI-driven creation; if the
user wants to reuse local Git config, read it, show the resolved name and email,
and treat that as the explicit author identity. Never pass only one author
option.

Then run this loop one package at a time:

```sh
fluoh deps get
fluoh doctor -p --platform ohos --json --strict
fluoh verify --package <name> --json
fluoh run --platform ohos --package <name> --auto-emulator --json
fluoh build --platform ohos --package <name> --auto-sign --json
fluoh package status --package <name>
fluoh package version --package <name> --bump patch --status compatible
fluoh package check --package <name> --json
```

## Automatic Adaptation Command Flow

Use this flow as the primary package adaptation loop. The commands decide when
to edit, when to fix local environment, and when work can be handed back.

1. Repository setup: use
   `fluoh package create <upstream> --repository-name <repository-name>` for a
   new package repository with resolved repository and Git author options, use
   `fluoh package add <package-path>` to create additional package branches,
   and use `fluoh package sync` only after a completed, committed checkpoint
   when an upstream package release needs to be merged. Use
   `--upstream-version <version>` only when adapting a specific same-or-newer
   upstream version; omitted targets resolve to the latest valid package release
   tag. If the current upstream version is unusable, mark it `broken` with
   `fluoh package version --status broken` instead of downgrading.
2. Baseline gates: run `fluoh deps get`,
   `fluoh doctor -p --platform ohos --json --strict`,
   `fluoh flutter analyze`, and relevant existing package or example tests
   before adding OHOS code. Project warnings point to repository files;
   environment warnings point to local tool or Source setup.
3. Example parity planning: when an example exists, inspect the existing
   Android, iOS, macOS, Linux, Web, Windows, and `integration_test/` flows
   before editing OHOS. Treat them as the functional contract for the OHOS
   example: keep equivalent entry points, labels, permissions, status text,
   expected results, and failure hints unless the platform capability is truly
   unavailable. Do not stop at adding an `ohos/` directory that only launches.
4. Implementation loop: after meaningful code or metadata changes, rerun
   `fluoh deps get` when dependencies or SDK metadata changed, then use
   `fluoh verify --package <name> --json --trace-dir <trace-dir>` until pub
   get, analysis, and existing tests pass.
5. OHOS verification: use
   `fluoh run --platform ohos --package <name> --auto-emulator --json
   --trace-dir <trace-dir>`, or add `--device <id>` for a connected hdc target.
   This proves build, signing, install, launch, and hilog diagnostics; it does
   not prove tappable example workflows by itself. If no local target can be
   started, use
   `fluoh build --platform ohos --package <name> --auto-sign --json --trace-dir
   <trace-dir>` as build-only evidence.
6. Existing-platform regression: when `example/android` exists, run
   `fluoh doctor --platform android --json --strict`, then
   `fluoh run --platform android --package <name> --auto-emulator --json`. For
   iOS, run `fluoh doctor --platform ios --json --strict`, then
   `fluoh run --platform ios --package <name> --auto-emulator --json`. For
   macOS, run `fluoh doctor --platform macos --json --strict`, then
   `fluoh run --platform macos --package <name> --json` on the local host. For
   Web examples, run `fluoh doctor --platform web --json --strict` plus
   `fluoh run --platform web --package <name> --device web-server --json` for
   served web smoke evidence; add
   `fluoh build --platform web --package <name> --json` when a separate web
   compile check is needed, and use Chrome from `fluoh devices --platform web`
   only when browser-specific evidence is required. For Linux and Windows
   examples, run `fluoh doctor --platform linux --json --strict` plus
   `fluoh build --platform linux --package <name> --json`, and
   `fluoh doctor --platform windows --json --strict` plus
   `fluoh build --platform windows --package <name> --json` on matching hosts.
7. Interaction verification: for workflows that need UI taps, permission
   prompts, file pickers, camera, location, media, deep links, or external
   apps, run `integration_test/` when available. When deterministic tests do
   not exist, perform an AI-assisted functional pass on the emulator/device:
   follow a short scenario in `.fluoh/scenarios/<package>/<platform>-<name>.md`
   or write the scenario before running it, interact with the app through the
   available device/browser/computer-use tools, assert results through
   Flutter debug or VM service output when available, widget/component tree
   state, semantics tree, integration-test output, accessibility text, visible
   status text, semantic labels, test keys, or structured log markers, and
   record step results, target id, evidence path, and blockers in the report.
   For Android, iOS, macOS, Linux, Web, and Windows `fluoh run --json` exposes
   `details.vmServiceUri` on the run step when Flutter prints a VM Service or
   debug service URI. Pass `--session-file <path>` on those runs when an AI or
   external inspector needs an attach point before final JSON is printed; fluoh
   writes a live `flutterRunSession` JSON file while the app is still running.
   Then run `inspect_session.py` or the preflight `sessionInspectCommand` to
   wait for launch, read the VM Service URI, and decide whether to attach,
   inspect logs, or route a failure.
   Do not judge whether the UI looks right unless the package is specifically a
   visual package. Do not assume the AI agent can inspect screenshots;
   screenshots and recordings are optional supporting evidence. Use
   manual-assisted interaction only as a fallback when AI automation cannot
   operate or observe the target, and only mark it passed after tool-readable
   evidence verifies the user-completed flow.
8. Diagnostics loop: read `nextCommand`, `diagnostics[].code`, `stdoutTail`,
   `stderrTail`, saved run logs, trace manifest `result`, and trace
   `feedbackCandidates` before editing. Fix `doctor` failures in local tooling,
   project warnings in repository configuration, and verification failures in
   the code or example that produced the diagnostic. During
   OHOS runs, treat `ohos.hdc_connection_failed`,
   `ohos.hdc_targets_failed`, and `ohos.hdc_target_unavailable` as device-link
   blockers: follow the diagnostic `nextCommand`, reconnect or restart hdc when
   needed, then rerun the same `fluoh run --platform ohos ... --json` command
   before attempting AI-assisted or manual-assisted interaction evidence.
   For `fluoh package sync --continue`, keep the target package pubspec version from
   the selected upstream target; do not resolve conflicts by leaving the
   previous upstream version in place. If the interrupted sync used a non-tag
   `--upstream-ref`, pass the same ref again with `--continue` because fluoh
   cannot infer non-tag refs from `MERGE_HEAD`.
9. Implementation checkpoint: once implementation, OHOS evidence, and applicable
   existing-platform regression checks are clean or explicitly blocked, create a
   local implementation checkpoint commit. This clean worktree is required before
   `fluoh package version`, `fluoh package sync`, and `fluoh package check`.
10. Release metadata checkpoint: run `fluoh package status --package <name>`,
   update release metadata with `fluoh package version --package <name>` when
   needed, update `FLUOH_CHANGELOG.md`, review `fluoh.yaml`, then create a local
   release metadata checkpoint commit. `fluoh package version` requires a clean
   worktree before it writes metadata, so do not leave implementation changes
   uncommitted before this step.
11. Final report and release gate: rerun the final
    `fluoh verify --package <name>`, write
    `.fluoh/reports/<package-or-scope>/ai-report-YYYYMMDD-HHMMSS.md`
    with commands, results, platform matrix, interaction evidence, diagnostics,
    trace feedback candidates collected with `collect_feedback.py` or an
    explicit no-feedback
    statement, signing mode, logs, remaining risks, and release recommendation,
    then run
    `python3 <skill-dir>/scripts/check_report.py <report-path>`. Because
    `.fluoh/` is local ignored state, the worktree should remain clean for
    `fluoh package check --package <name> --report <report-path>`. Add
    `--require-ohos-run` when a connected target or emulator was available and
    the handoff must prove a passed OHOS launch. The certification report
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

- Read generated `README.md`, `AGENTS.md`, `FLUOH.md`, `FLUOH_CHANGELOG.md`, and
  `fluoh.yaml` before editing.
- If the user asked for multiple packages, adapt one package branch per
  iteration; do not combine multiple packages into one `fluoh.yaml`.
- Preserve upstream public Dart APIs and non-OHOS behavior unless the user
  approves a breaking change.
- Establish a selected-SDK baseline before adding OHOS code. Fix non-OHOS
  regressions first when Android, iOS, macOS, Linux, Web, Windows, tests, or
  examples already exist.
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
  manual-assisted evidence with tool-readable verification.
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
- Use `fluoh run --platform ohos --package <name> --auto-emulator --json` for
  OHOS run evidence, or add `--device <id>` only when no emulator is available.
  Use the `build --auto-sign` command as the fallback only when no local target
  can be started.
- Run existing-platform regression checks when corresponding example platform
  directories exist and local toolchains are available:
  `fluoh run --platform android|ios --package <name> --auto-emulator --json`
  `fluoh run --platform macos --package <name> --json`, and
  `fluoh run --platform web --package <name> --device web-server --json`.
  For Linux and Windows
  examples, run `fluoh build --platform linux|windows --package <name> --json`
  on matching hosts so those desktop projects at least compile without errors.
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
- For `verify`, `build`, and `run`, prefer `--trace-dir <trace-dir>` during
  AI-driven loops. Read the local `trace.json` manifest and classify any
  `feedbackCandidates` as fluoh CLI, Source data, AI skill, local environment,
  upstream package, or user project follow-up before final reporting. If JSON
  includes `traceError`, record it as a local trace-evidence issue without
  changing the command's pass/fail interpretation. For `verify`, inspect
  `dirtyAfterVerify` and `workingTreeChanges`; if verification generated files
  or left the tree dirty, run `git status --short`, review the new files, and
  record whether they are expected generated artifacts or issues to fix.
  Prefer the preflight `feedbackCommand` or run
  `python3 <skill-dir>/scripts/collect_feedback.py <trace-dir-or-manifest>` to
  deduplicate trace candidates and produce the report table fragment.
- Treat doctor/toolchain/device diagnostics as local-environment work, not code
  defects.
- Treat `dart.sdk_constraint_unsatisfied` as a package compatibility task for
  the selected FlutterOH SDK: keep the latest upstream package version, adjust
  `pubspec.yaml` `environment.sdk` and example config only when the code can
  support the selected Dart version, replace newer Dart language, SDK API, or
  dependency usage, then rerun `fluoh verify --package <name> --json`. Use
  `details.sdkConstraint.suggestedEnvironmentSdkConstraint` when present as the
  first pubspec constraint candidate. Do not downgrade upstream unless
  maintainers explicitly approve an older baseline.
- Treat `dart.pub_get_failed`, `dart.analysis_failed`, `dart.test_failed`,
  platform build failures, install failures, launch failures, runtime crashes
  or Flutter channel runtime errors, and integration-test failures as code or
  project issues only after the local toolchain diagnostic is clean.

## Completion Report

Before the final response, create a local report under `.fluoh/reports/` using:

```text
.fluoh/reports/<report-group>/ai-report-YYYYMMDD-HHMMSS.md
```

For package work, `<report-group>` is normally the package name slug. If
`--package` is omitted, it is the scope slug. File names do not repeat the scope
or package slug. The helper scripts append `-2`, `-3`, and so on before `.md`
instead of overwriting same-second outputs.

For multi-package monorepos, also create a summary report under:

```text
.fluoh/reports/<scope-slug>/summary-YYYYMMDD-HHMMSS.md
```

Use local time and do not commit this file. Prefer
the preflight `reportCommand` and `summaryCommand` when available, or run
`python3 <skill-dir>/scripts/new_report.py <project-path> --scope <scope>`;
otherwise use `references/report-template.md` directly.
Complete the report with command output summaries, exit codes, changed files,
platform evidence, interaction evidence, diagnostics, Fluoh Feedback entries
from `collect_feedback.py` or an explicit `No fluoh feedback: <reason>`
statement, remaining risks, and release recommendation. Mark every applicable
Delivery Checklist item as done, or leave it unchecked and explain the blocker.
A ready recommendation requires all applicable checklist items to be done.
If no interaction scenario applies, write `No interaction required: <reason>` in
the report's `Interaction Evidence` section. Otherwise include at least one
concrete interaction row; `check_report.py` enforces this before final delivery.
Run `python3 <skill-dir>/scripts/check_report.py <report-path>` before the final
response; if it fails, fix the report or explain why the remaining blocker is
intentional.

The final response should state whether the work is ready, blocked, or needs a
maintainer decision; point to the report path; and list only the remaining
blocking risks.
