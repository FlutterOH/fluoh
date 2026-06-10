# Package Adaptation Flow

Use this workflow when the user asks to adapt a third-party Flutter package for
FlutterOH/OHOS.

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
fluoh doctor -p --platform ohos --json --strict
fluoh flutter analyze
fluoh verify --package <name> --json --trace-dir <trace-dir>
fluoh run --platform ohos --package <name> --auto-emulator --json --trace-dir <trace-dir>
fluoh build --platform ohos --package <name> --auto-sign --json --trace-dir <trace-dir>
fluoh package status --package <name>
fluoh package version --package <name> --bump patch --status compatible
fluoh package check --package <name> --json
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

## Platform Regression

Run existing-platform checks when corresponding example platform directories
exist and local toolchains are available:

```sh
fluoh doctor --platform android --json --strict
fluoh run --platform android --package <name> --auto-emulator --json
fluoh doctor --platform ios --json --strict
fluoh run --platform ios --package <name> --auto-emulator --json
fluoh doctor --platform macos --json --strict
fluoh run --platform macos --package <name> --json
fluoh doctor --platform web --json --strict
fluoh run --platform web --package <name> --device web-server --json
fluoh build --platform web --package <name> --json
fluoh build --platform linux --package <name> --json
fluoh build --platform windows --package <name> --json
```

For iOS, auto-emulator selection should prefer an iPhone simulator over iPad,
prefer newer runtimes inside the same device class, and wait for
`xcrun simctl bootstatus <udid> -b` before treating the simulator as ready.

Use `fluoh automate --platform all --package <name> --json` when an AI
adaptation loop needs one mobile evidence command for OHOS, Android, and iOS.

## Checkpoints

Create small local commits at completed checkpoints when the workflow needs
commits, such as before package sync, package check, or handoff. Before each
commit, self-review staged paths, commit message, and local Git author
identity. Keep commits local unless the maintainer explicitly asks to push.

Before `fluoh package version`, `fluoh package sync`, or
`fluoh package check`, the implementation checkpoint should be clean. Then
update release metadata, review `fluoh.yaml`, update `FLUOH_CHANGELOG.md`, and
create a release metadata checkpoint when required.

Run `fluoh package release` only when the maintainer approves the release.
