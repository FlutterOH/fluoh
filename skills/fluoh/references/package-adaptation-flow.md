# Package Adaptation Flow

Use this workflow when the user asks to adapt a third-party Flutter package for
FlutterOH/OHOS.

## End-to-End Contract

The package adaptation is not complete after repository creation, baseline
verification, HAP build, app launch, or a screenshot. Continue until exactly
one delivery state is justified:

- `ready`: implementation, package tests, OHOS build/run, applicable
  interaction automation, existing-platform regressions, package handoff,
  release check, canonical report, and `check_report.py` all pass.
- `needs maintainer decision`: code and evidence are as complete as the local
  environment allows, but release, publish, push, tag, signing policy, SDK
  line, upstream downgrade, public API break, or release version choice needs a
  maintainer decision.
- `blocked`: a concrete local toolchain, SDK, signing, device/emulator,
  upstream, or automation-evidence blocker remains after running the diagnostic
  command and the printed repair command or `nextCommand`.

Use `scripts/preflight.py` or `fluoh plan package --json` as the machine
runbook. Execute `commandQueue`/`queue` in order, parse every JSON result,
follow diagnostics `nextCommand`, make the smallest owned fix, and rerun the
failed command. Do not skip `drive`, `report create`, `package handoff`,
`package check`, or `check_report.py` when applicable.

## Setup

For a new package repository, resolve the FlutterOH repository name, output
path, repository URL or path, local Git author name and email, SDK line,
package path, upstream version when specified, and explicit `flutter create
--org` value when one is required.

When the upstream may be a monorepo and the user did not provide a package name
or package path, run:

```sh
fluoh package discover <upstream> --json
```

Present discovered Flutter plugin packages missing `ohos`, including package
names, paths, declared platforms, and `createCommand` values. If a candidate
contains `implementationRecommendation`, prefer the federated path: create the
recommended `<package>_ohos` implementation package, add the missing platform
`default_package` entry to the app-facing package, and add the implementation
dependency with the recommended relative path.

For a new repository, first run a plan:

```sh
fluoh package create <upstream-git-url> --sdk <sdk-version-or-line> \
  --repository-name <flutteroh-repo-name> \
  --repository <flutteroh-repo-url-or-path> \
  --git-author-name <name> --git-author-email <email> \
  --package-path <path> --plan --json
```

Use the plan as the final adaptation scope confirmation and wait for explicit
approval before running the mutating create command, `fluoh package add`,
`fluoh package docs refresh`, local Git author changes, or implementation
edits.

For an existing package repository, read `repository.git.url` from `fluoh.yaml`
and local Git author identity from `git config --local --get user.name` and
`git config --local --get user.email`. Ask for any missing or contradictory
adaptation value before mutating files.

Before implementation edits, inspect preflight `upgradeChecks`. If generated
package docs are stale, run `fluoh package docs refresh --dry-run`, then run the
refresh command reported by preflight. Prefer `fluoh package docs refresh` on a
clean worktree; use `fluoh package docs refresh --allow-dirty` only when
preflight reports that explicit dirty-refresh command.

## Repository Rules

- `fluoh package create` always gets an explicit `--repository-name` in AI
  automation.
- AI-driven creation always passes resolved `--repository`,
  `--git-author-name`, and `--git-author-email`; never pass only one author
  option.
- If the user wants to reuse local Git config, read it, show the resolved name
  and email, and treat that as the explicit author identity.
- Omitted package paths mean the root package only, not every package in a
  monorepo.
- Omitted upstream targets resolve to the latest valid release tag after
  fetching upstream tags, not to upstream HEAD when release tags exist.
- Use `--upstream-version <version>` only when adapting a specific same-or-newer
  upstream version. If the current upstream version is unusable, mark it
  `broken` instead of downgrading without maintainer approval.
- Use one FlutterOH adaptation repository per upstream repository by default.
  For multiple packages, use `fluoh package queue <package-path>... --json`,
  adapt one branch at a time, and use `fluoh package add <package-path>` for
  additional package branches.
- Prefer a fresh clone or separate Git worktree per existing package branch
  when verifying multiple branches.

## Implementation Loop

Run these checks one package at a time:

```sh
fluoh deps get
fluoh doctor --platform ohos --project --json --strict
fluoh flutter analyze
fluoh verify --package <name> --json --trace-dir <trace-dir>
fluoh build ohos --package <name> --auto-sign --json --trace-dir <trace-dir>
fluoh devices --platform ohos --json
fluoh emulators --platform ohos --json
fluoh run ohos --package <name> --auto-emulator --json --trace-dir <trace-dir>
fluoh drive ohos --package <name> --json --trace-dir <trace-dir>
# When emitted by preflight/plan for existing supported mobile examples:
fluoh drive android --package <name> --json --trace-dir <trace-dir>
fluoh drive ios --package <name> --json --trace-dir <trace-dir>
fluoh package status --package <name>
fluoh report create --scope <name> --package <name> --trace-dir <trace-dir> --json
fluoh package handoff --package <name> --json
fluoh package check --package <name> --report <report-path> --json
python3 <skill-dir>/scripts/check_report.py <report-path>
```

Rules:

- Read generated `README.md`, `AGENTS.md`, `FLUOH.md`,
  `FLUOH_CHANGELOG.md`, and `fluoh.yaml` before editing.
- Keep upstream public Dart APIs and non-OHOS behavior unless the user approves
  a breaking change.
- Establish the selected-SDK baseline before adding OHOS code.
- Fix non-OHOS regressions first when existing Android, iOS, macOS, Linux, Web,
  Windows, tests, or examples already exist.
- Implement OHOS code near the package path recorded in `fluoh.yaml`.
- Extend package tests or examples when behavior changes.
- Example apps are functional harnesses: expose operations, expected results,
  pass/fail status, and failure hints for automated or AI-assisted checks.
- Every failing command enters the repair loop: parse JSON diagnostics and log
  tails, inspect trace feedback candidates, patch the smallest owned issue,
  rerun the failed command or its `nextCommand`, and record the command/result
  in the report.
- `fluoh run ohos --package <name> ...` owns the OHOS Flutter platform loop:
  debug signing preparation, `flutter run`, run/session diagnostics, and
  `example/integration_test/` execution on the selected target when present.
  Use `fluoh attach ohos --session-file <path>` for Flutter debug attach when
  a live session exposes a VM Service URI or target id.
  Use hdc/hilog through `fluoh drive --scenario` or lower-level debug
  diagnostics, not as the primary run path.

## Platform Regression

Run existing-platform checks when corresponding example platform directories
exist and local toolchains are available:

```sh
fluoh doctor --platform android --json --strict
fluoh run android --package <name> --auto-emulator --json
fluoh doctor --platform ios --json --strict
fluoh run ios --package <name> --auto-emulator --json
fluoh doctor --platform macos --json --strict
fluoh run macos --package <name> --json
fluoh doctor --platform web --json --strict
fluoh run web --package <name> --json
fluoh build web --package <name> --json
fluoh build linux --package <name> --json
fluoh build windows --package <name> --json
```

For iOS, auto-emulator selection should prefer an iPhone simulator over iPad,
prefer newer runtimes inside the same device class, and wait for
`xcrun simctl bootstatus <udid> -b` before treating the simulator as ready.

Use the per-platform `fluoh drive <platform> --package <name> --json` commands
emitted by preflight or `fluoh plan package --json`. OHOS is part of the
adaptation target; Android and iOS drive commands are included only when the
example platform exists and the local host can run the target.

## Delivery Gate

Before the final response:

- Run the preflight or plan `finalCheckCommands` after the last implementation
  edit.
- Create or update the canonical report under `.fluoh/reports/`.
- Run `python3 <skill-dir>/scripts/check_report.py <report-path>` against the
  canonical report and fix every failure.
- Ensure `fluoh package handoff --package <name> --json` sees the current
  branch, trace, report paths, and next commands.
- Ensure `fluoh package check --package <name> --report <report-path> --json`
  passes for `ready`, or records the remaining maintainer decision or blocker
  in the report.
- Review the diff for unrelated files, machine-local paths, generated caches,
  credentials, and private tokens.

Create small local checkpoint commits automatically after completed phases with
clean command evidence. Typical phases are generated baseline, selected-SDK
baseline, implementation, tests and example verification, release metadata, and
delivery report handoff. Before each commit, review `git status --short`, run
`git diff --check`, stage only intentional tracked files, and keep `.fluoh`
reports/traces, caches, credentials, signing secrets, and machine-local paths
out of commits. Push, force-push, release, tag, public API breaks, upstream
downgrades, SDK line changes, signing policy changes, and manual release
version overrides still require separate maintainer approval. Run
`fluoh package release` only when the maintainer approves the release.
