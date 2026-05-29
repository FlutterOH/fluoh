# Command Design

[简体中文](commands.zh-CN.md)

This document describes the full `fluoh` command surface and the design
boundaries behind each command. It complements [schema.md](schema.md): schema
docs define the data shapes, while this document defines how commands read,
write, and preserve that data.

Command implementations live mostly under `lib/src/<domain>/commands/`, with
top-level wiring in `lib/src/cli/fluoh_command_runner.dart`.

## Command Surface

| Command | Implementation | Purpose |
| --- | --- | --- |
| `fluoh --version` | `lib/src/cli/fluoh_command_runner.dart` | Print the `fluoh` version, Dart version, platform, and repository URL. |
| `fluoh help [command]` | `package:args` command runner | Print global or command-specific usage. |
| `fluoh flutter <args>` | `lib/src/sdk/flutter_command.dart` | Run `flutter` from the SDK selected by the nearest project `fluoh.yaml`. |
| `fluohf <args>` | `bin/fluohf.dart` | Shortcut for `fluoh flutter <args>`. |
| `fluoh source` | `lib/src/source/source_commands.dart` | Command group for data source use and maintenance. |
| `fluoh source list` | `lib/src/source/source_commands.dart` | List configured FlutterOH data sources. |
| `fluoh source add <name> <url-or-path>` | `lib/src/source/source_commands.dart` | Add a local or Git data source to tool config. |
| `fluoh source remove <name>` | `lib/src/source/source_commands.dart` | Remove a non-official data source from tool config. |
| `fluoh source update [name]` | `lib/src/source/source_commands.dart` | Refresh and validate configured source snapshots. |
| `fluoh source validate [path]` | `lib/src/source/source_commands.dart` | Validate a local source repository without registering it. |
| `fluoh source init <path>` | `lib/src/source/source_commands.dart` | Create a local source repository template. |
| `fluoh source sync [path]` | `lib/src/source/source_commands.dart` | Import released FlutterOH package repository metadata into a source repository. |
| `fluoh sdk` | `lib/src/sdk/sdk_commands.dart` | Command group for local Flutter OHOS SDK caches. |
| `fluoh sdk list` | `lib/src/sdk/sdk_commands.dart` | List remote SDK versions and installed SDK caches. |
| `fluoh sdk install <version-or-series>` | `lib/src/sdk/sdk_commands.dart` | Install an SDK version into `$FLUOH_HOME/sdks`. |
| `fluoh sdk current` | `lib/src/sdk/sdk_commands.dart` | Print the SDK selected for the current project. |
| `fluoh sdk remove <version-or-series>` | `lib/src/sdk/sdk_commands.dart` | Remove an installed SDK cache. |
| `fluoh sdk use <version-or-series>` | `lib/src/sdk/sdk_use_command.dart` | Select an SDK for the current Flutter project. |
| `fluoh deps` | `lib/src/deps/commands/deps_command.dart` | Command group for project dependencies. |
| `fluoh deps get` | `lib/src/deps/commands/deps_get_command.dart` | Run `flutter pub get` for projects and package examples. |
| `fluoh deps check` | `lib/src/deps/commands/dependency_plan_commands.dart` | Report dependency FlutterOH adaptation status. |
| `fluoh deps fix` | `lib/src/deps/commands/dependency_plan_commands.dart` | Apply recommended FlutterOH dependency changes. |
| `fluoh deps upgrade` | `lib/src/deps/commands/deps_upgrade_command.dart` | Upgrade existing FlutterOH dependency replacements only. |
| `fluoh package` | `lib/src/package/commands/package_command.dart` | Command group for FlutterOH package repositories. |
| `fluoh package create <upstream>` | `lib/src/package/commands/package_create_command.dart` | Initialize a FlutterOH package repository. |
| `fluoh package add <package-path>` | `lib/src/package/commands/package_add_command.dart` | Register another package in a FlutterOH package repository. |
| `fluoh package sync` | `lib/src/package/commands/package_sync_command.dart` | Merge upstream into the current OHOS package branch. |
| `fluoh package release` | `lib/src/package/commands/package_release_command.dart` | Check, tag, and optionally push FlutterOH package releases. |
| `fluoh package status` | `lib/src/package/commands/package_status_command.dart` | Summarize package release readiness. |
| `fluoh verify` | `lib/src/workflow/workflow_commands.dart` | Run pub get, analysis, and tests for a project or package repository. |
| `fluoh build --platform <platform>` | `lib/src/workflow/workflow_commands.dart` | Build a project or package example. |
| `fluoh run --platform <platform>` | `lib/src/workflow/workflow_commands.dart` | Build, install, launch, and diagnose an app. |
| `fluoh doctor` | `lib/src/doctor/doctor_command.dart` | Diagnose environment, native tools, and optional project state. |
| `fluoh devices` | `lib/src/platform/platform_commands.dart` | List connected OHOS, Android, iOS, and macOS targets. |
| `fluoh emulators` | `lib/src/platform/platform_commands.dart` | List and launch local OHOS, Android, iOS, and macOS emulators or simulators. |
| `fluoh upgrade` | `lib/src/upgrade/upgrade_command.dart` | Upgrade the installed `fluoh` CLI. |

## Shared Runtime Rules

- Help requests never load source configuration.
- Source lock maintenance has one owner: the Source runtime in
  `lib/src/source/`. Command classes must not read or write
  `$FLUOH_HOME/sources.lock.json` directly.
- Commands that change Source configuration or configured snapshots delegate the
  change to the Source runtime. The runtime validates every configured source
  snapshot, repairs snapshots when possible, rebuilds the merged lock, and only
  then commits the new local Source state.
- Commands that consume Source data access it only through the Source runtime's
  load-index API. That API bootstraps the first default Source configuration and
  returns a fresh `sources.lock.json` when its recorded fingerprint still
  matches. When the lock is missing, stale, or incompatible, the runtime
  verifies or repairs configured source snapshots and regenerates the lock
  before returning data.
- `fluoh source` without a subcommand and `fluoh source list` use the same
  Source runtime rebuild path before printing configuration, so users see
  invalid or missing source state before relying on listed sources.
- `fluoh deps get` skips package Source data so dependency resolution remains
  available when source snapshots need repair. `fluoh flutter`, `fluohf`, and
  `fluoh deps get` may still load the Source index through the SDK resolver when
  the selected SDK is missing and selected-SDK installation needs SDK metadata.
- Usage errors and schema format errors return exit code `64`.
- Commands that support `--json` write exactly one machine-readable JSON object
  to stdout. The top-level contract is stable across those commands:
  `schemaVersion`, `command`, `ok`, and `exitCode` are always present; command
  specific fields such as `checks`, `targets`, `packages`, `dependencies`, or
  `error` remain at the top level.
- Command classes should own argument parsing and user-visible output. Reusable
  behavior belongs in domain helpers such as `lib/src/sdk/`, `lib/src/deps/`,
  `lib/src/package/`, and `lib/src/source/`.
- Mutating commands must validate early, preserve unrelated files, and report
  what changed or what the user should do next.

## Top-Level Commands

### `fluoh flutter <args>` and `fluohf <args>`

These commands are pass-through wrappers around the selected Flutter OHOS SDK.
They resolve the current project SDK through `SdkManager.currentSdkVersion()`, find
or install the cached SDK, then execute `<sdk>/bin/flutter` with the original
arguments. A single help argument prints `fluoh` wrapper help instead of
forwarding to Flutter.

Design constraints:

- Do not rewrite Flutter arguments.
- Fail with guidance when no SDK is selected.
- Install the selected SDK on demand if the cache is missing.
- Stream Flutter stdout and stderr without adding command-specific semantics.

### `fluoh doctor`

`doctor` is diagnostic and returns success after printing its findings unless
`--strict` is used. Bare `fluoh doctor` checks the fluoh installation, Dart
runtime, configured source snapshots, OpenHarmony tooling, Android SDK tools,
Java, Xcode `xcrun`, `simctl`, and currently connected OHOS, Android, iOS, and macOS devices. The
default plain output prints the full doctor report: one row per category plus
checked tools, source entries, emulator summaries, paths, command summaries,
versions, and per-check timings. Source entries are listed under a stable
`Sources` heading instead of being embedded in the heading. The command
intentionally has no
`-v`, `--verbose`, or `--details` alias because Dart's `pub global run` treats
verbose flags as pub logging flags when a global executable falls back to pub,
which can print dependency solver output before fluoh starts. When the current
directory is a Flutter project, it also checks project shape, selected
FlutterOH SDK, and the selected platform directories only when `-p` or
`--project` is passed. Use `--platform ohos|android|ios|macos` to narrow native
toolchain and project platform checks.

Checks are organized into three groups: fluoh and source snapshot health,
platform toolchains for OHOS, Android, iOS, and macOS, and optional current-project
state. Platform titles name both sides of the mapping: OpenHarmony tooling
develops for OHOS devices, Android tooling develops for Android devices, and
Xcode develops for iOS devices.

Missing or stale state is reported as warnings rather than immediate
remediation. Use `fluoh doctor --json --strict` when automation needs a native
toolchain gate, and `fluoh doctor -p --json --strict` when it also needs
a current-project gate. Project JSON includes `platformDirectories` data for
the selected platform set so automation can decide whether to create or skip
OHOS, Android, or iOS platform projects. `--json` prints the same checks as
machine-readable JSON and includes each check's stable `id` and `group`.

### `fluoh upgrade`

`upgrade` upgrades the CLI installation, not project dependencies. It executes
`brew upgrade fluoh` for Homebrew installs or
`dart pub global activate fluoh` for Dart global installs. Local source
checkouts are refused because replacing a checkout is a user-owned decision.

## Source Commands

Source commands are split into consumer commands that manage configured
snapshots and maintainer commands that edit source repositories. A source
snapshot is the validated local copy of a Source stored under
`$FLUOH_HOME/sources/<name>`.

### Consumer Commands

`fluoh source list` first asks the Source runtime to ensure configured source
snapshots and `sources.lock.json` are usable, then reads `$FLUOH_HOME/config.json`
and prints each configured source name and display value. Empty configuration is
a warning, not an error.

`fluoh source add <name> <url-or-path>` validates the source name, refuses to
replace the official source name, and stores a cache path under
`$FLUOH_HOME/sources/<name>`. Local paths are normalized to absolute `file:`
URLs in `$FLUOH_HOME/config.json` so future `source update` runs can refresh the
cache from the original directory. Local paths and `file:` URLs are copied as
validated snapshots. HTTPS/SSH URLs are cloned immediately and validated before
the config entry is saved. `--priority` defaults to `10`, and higher priorities
win when source data overlaps. After the new snapshot is valid, the Source
runtime commits the config entry and regenerated lock together.

Overlap merge rules are explicit:

- SDK releases merge by tag. Higher priority wins; same-priority conflicting
  release records are an error.
- Package release records merge by `package + sdkLine + upstreamVersion`. Higher
  priority replaces lower priority records for the same group. Consumer indexes
  include only `compatible` release records; `experimental` and `broken` records
  remain in Manifest files but do not override a lower-priority compatible
  recommendation.
- Same-priority records with the same derived tag but different repository
  or path are an error. Different tags in the same group can coexist, and the
  dependency planner selects the best compatible release record.
- Package-level upstream URL and advisory text come from the highest priority
  source that defines the package.

`fluoh source remove <name>` removes a non-official source from tool config.
The official Source alias `flutteroh` cannot be removed. The command does not
own unrelated files outside the config entry. Lock maintenance is delegated to
the Source runtime.

`fluoh source update [name]` refreshes all sources or one named source. Selected
Git sources are cloned again, and selected `file:` sources are copied again from
their configured local directories. The Source runtime then validates every
configured source snapshot because the lock is a merged index over all
configured sources.

Source mutation commands pass the candidate config or snapshot state to the
Source runtime. If validation or lock generation fails, the runtime preserves
the previous usable config, snapshots, and lock.

### Maintainer Commands

`fluoh source validate [path]` validates a local Source repository without
reading or writing `$FLUOH_HOME/config.json`, source snapshots, or
`sources.lock.json`. When `path` is omitted, the current directory is used. The
command checks the Source root schema, `environment.fluoh`, SDK metadata,
Manifest routes, Manifest names, duplicate packages, package release records,
and whether the package index can be built. It does not fetch SDK tags or
package repositories; release metadata updates remain the job of
`fluoh source sync`.

`fluoh source init <path>` creates a source root `fluoh.yaml`, a
`manifests/example/fluoh.yaml` commented Manifest template, and a README. It is
conservative when those files already exist and reports the template as
skipped. The generated `fluoh.yaml` is a valid empty Source scaffold with
commented repository, SDK, and Manifest routing examples so maintainers can
uncomment the needed sections.
Maintainers edit Manifest files directly for advisory and maintenance notes;
release records are generated by `fluoh source sync`.

`fluoh source sync [path]` reads Manifest routes from the Source root,
uses each Manifest `repository.git.url` as the FlutterOH package repository, scans
release tags, reads the Package `fluoh.yaml` frozen under each tag, and
aggregates historical release records into Manifest files. When `path` is
omitted, the current directory is used. Source metadata must come from released
adaptation records, not in-progress repository state. When `<path>` is
one of the configured source snapshots under `$FLUOH_HOME/sources/<name>`, sync
is treated as a configured Source snapshot mutation and the Source runtime
rebuilds the merged lock. When `<path>` is a maintainer checkout outside
the configured snapshots, the local lock is not changed; run
`fluoh source update <name>` after publishing or copying the Source into a
configured snapshot. `--json` prints synced and skipped package records as JSON.

## SDK Commands

`fluoh sdk list` merges remote source releases with locally installed SDK
caches. If source indexes are unavailable but local SDKs exist, it still lists
the local entries.

`fluoh sdk install <version-or-series>` accepts an exact SDK version or a series
such as `3.35`. Series selection prefers the latest stable version. The manager
clones the SDK repository into `$FLUOH_HOME/sdks/<version>`, checks out the
matching Git tag, and deletes a partial destination on failure.

`fluoh sdk current` reads the current project SDK version. If no SDK is selected
it prints a warning and returns exit code `1`.

`fluoh sdk remove <version-or-series>` resolves the requested release or exact
local cache version and deletes only the matching SDK directory under
`$FLUOH_HOME/sdks`.

`fluoh sdk use <version-or-series>` is a project mutation command. It requires
the current directory to be a Flutter project, refuses to overwrite FlutterOH
package repository metadata, resolves or installs the SDK, writes the project
`fluoh.yaml`, and updates `.fluoh/flutter_sdk` as a stable IDE SDK path.
By default, it runs the selected SDK's
`flutter create --no-pub --platforms=ohos .` when the project has no `ohos/`
directory. `--no-init-ohos` skips that default initialization. `--pub-get` runs
`flutter pub get` after the switch and any OHOS initialization.

## Dependency Commands

These commands operate on ordinary FlutterOH projects and preserve unrelated
`pubspec.yaml` content.

`fluoh deps get` forwards to selected-SDK `flutter pub get` and accepts extra
arguments. It runs in all primary package directories and existing package
examples that contain a `pubspec.yaml`. It intentionally skips package Source
data so dependency resolution remains available even when source snapshots need
repair. If the selected SDK is missing, the SDK resolver loads the Source index
only for the lookup needed to install that SDK.

`fluoh deps check` reads dependency policy from project `fluoh.yaml`, builds a
dependency plan from configured sources, and groups dependencies into ready,
needs decision, manual action, unavailable, already OK, transitive, and
advisory sections. A fresh Source lock provides package route hints; the command
then reads only the Manifest files that can contain packages from the project
lockfile. `--json` prints the same plan as machine-readable JSON.

`fluoh deps fix` applies recommended FlutterOH adaptation changes from the
dependency plan. It writes to either `dependency_overrides` or direct dependency
declarations according to `dependencyPolicy.pubspecSection`. Version mismatches
are skipped unless `dependencyPolicy.versionChanges` is `any`. `--dry-run` or
`-n` prints the plan without modifying `pubspec.yaml`.

`fluoh deps upgrade` is narrower than `deps fix`: it upgrades existing FlutterOH
dependency replacements and does not add new replacements. It uses the same
version-change policy and dry-run behavior.

## Package Repository Commands

These commands maintain FlutterOH package repositories. They assume Git
repositories and are intentionally strict about branch and working tree state.

### Automatic Adaptation Command Flow

The AI adaptation flow uses a small command set with clear ownership:

1. Repository setup: use `fluoh package create <upstream>` for a new package
   repository, `fluoh package add <package-path>` for additional packages, and
   `fluoh package sync` only after a completed, committed checkpoint when
   upstream needs to be merged.
2. Baseline gates: run `fluoh deps get`,
   `fluoh doctor -p --json --strict`,
   `fluoh flutter analyze`, and the relevant existing package or example tests
   before adding OHOS code. Project warnings point to repository files;
   environment warnings point to local tool or Source setup.
3. Implementation loop: after each meaningful code or metadata change, rerun
   `fluoh deps get` when dependencies or SDK metadata changed, then use
   `fluoh verify --package <name> --json` until pub get, analysis, and
   existing tests pass.
4. OHOS verification: use
   `fluoh run --platform ohos --package <name> --json`, or add
   `--device <id>` for a connected hdc target. If no device is available, use
   `fluoh build --platform ohos --package <name> --auto-sign --json`
   as build-only evidence.
5. Existing-platform regression: when `example/android` exists, run
   `fluoh doctor --platform android --json --strict`, then
   `fluoh run --platform android --package <name> --json`.
   When `example/ios` exists, use the matching iOS doctor command and
   `fluoh run --platform ios --package <name> --json`.
   When `example/macos` exists, use the matching macOS doctor command and
   `fluoh run --platform macos --package <name> --json`.
6. Diagnostics loop: read `nextCommand`, `diagnostics[].code`, `stdoutTail`,
   `stderrTail`, and saved run logs from JSON output before editing. Fix
   `doctor` failures in local tooling, project warnings in
   repository configuration, and verification failures in the code or example
   that produced the diagnostic.
7. Completion report: write `.fluoh/ai-report-<package-or-scope>-YYYYMMDD-HHMMSS.md`
   with commands, results, platform matrix, signing mode, logs, remaining risks,
   and release recommendation.
8. Release gate: run `fluoh package status --package <name>`, the final
   `fluoh verify --package <name>`, and
   `fluoh package release --package <name> --dry-run`. Commit only after the
   relevant gate succeeds; run `fluoh package release --package <name>` when
   the maintainer approves tagging.

### Adaptation Workflow

Adaptation is maintained by Flutter OHOS SDK line, not SDK patch version. For
example, complete SDK `3.35.8-ohos-0.0.3` maps to SDK line `3.35`, and the
adaptation repository branch is `ohos/3.35`.

Recommended flow:

1. Select a complete SDK version.
2. Derive the SDK line from that SDK version.
3. Create or switch to `ohos/<sdkLine>`.
4. Record the currently adapted upstream package version and FlutterOH
   adaptation package version in Package `fluoh.yaml`.
5. Before adding OHOS code, run verifications with the selected SDK, including
   `fluoh deps get`, `fluoh flutter analyze`, and existing package tests or
   example builds. Fix non-OHOS platform regressions first.
6. Use `status: experimental` while adaptation is in progress. Omit `status`
   when the release is complete and recommended; omitted means `compatible`.
7. `fluoh package release` creates the release tag, freezing the code, tests, and
   Package `fluoh.yaml`.
8. `fluoh source sync` aggregates Source Manifests from release tags.

`fluoh package create <upstream>` clones the upstream repository, selects one or
more packages, configures `upstream` and `origin`, creates a Flutter OHOS
SDK line branch such as `ohos/3.35`, configures the Flutter OHOS SDK, writes
`fluoh.yaml`, `FLUOH.md`, `FLUOH_CHANGELOG.md`, and agent instructions, then
stages generated files. When a selected package has an existing Flutter example,
the command adds the OHOS platform to that example, writes example SDK config,
and stages the example changes. The generated guidance tells maintainers to
establish a selected-SDK baseline and fix non-OHOS platform regressions before
implementing OHOS code. Generated agent instructions also ask AI agents to make
small local commits at completed verification checkpoints when maintainers ask
for local commits.
With no `--package-path`, the command selects only the upstream repository root
package. If the upstream repository has a root package plus package subprojects,
pass `--package-path .` and repeat `--package-path <subdir>` for each package
that should be registered.
The generated `fluoh.yaml` includes comments beside the `repository`,
`upstream`, package path, `version`, and `status` fields that maintainers
commonly edit before release. It never commits. Options include repeated
`--package-path`, `--output`, `--sdk`, `--repository`, `--git-author-name`, and
`--git-author-email`. The Git author options configure only the new repository's
local Git `user.name` and `user.email` values for later adaptation commits.

`fluoh package add <package-path>` registers another package in an existing
FlutterOH package repository. It requires a clean working tree and the
maintenance branch recorded by Package `repository.git.branch`, validates
`<package-path>`, optionally verifies `--expected-package`, appends Package
`fluoh.yaml` and docs, prepares an existing Flutter example when present, and
stages generated files. File snapshots protect local state when the command
fails.

`fluoh package sync` fetches upstream, fast-forwards the upstream branch recorded
in Package `upstream.git.branch`, returns to the `repository.git.branch` branch
recorded in `fluoh.yaml`, merges the upstream branch without committing first,
updates upstream metadata in `fluoh.yaml`, stages it, and
commits `Sync upstream packages` when changes are present. Merge conflicts are
left for the user to resolve, then `fluoh package sync --continue` validates staged
resolution and finishes. `--abort` runs `git merge --abort` for an in-progress
sync. `--json` prints the completed sync action list and commit status.

`fluoh verify` runs automated verification for either the current
project or packages registered in Package `fluoh.yaml`. It runs selected-SDK
`pub get` and `analyze`, uses `flutter` for Flutter packages and `dart` for
non-Flutter packages, and runs tests when `test/**/*_test.dart` exists. In a
package repository it also verifies each top-level Flutter example when
`example/pubspec.yaml` is present. Use `--package <name>` for one package or
`--all` for every registered package. `--json` reports each project or package
under `targets`, with target identity, phase, steps, diagnostics, and
`nextCommand`.

`fluoh build --platform ohos|android|ios|macos` builds the current Flutter project or
the selected package example. iOS builds automatically add `--no-codesign`.
OHOS builds can use `--auto-sign` to generate a temporary local debug signing
profile from the project's or example's requested permissions, patch
`ohos/build-profile.json5` for that build, and restore the original file after
the build. If Flutter leaves a fresh unsigned HAP after Hvigor signing fails,
`fluoh` directly signs that HAP and reports `signingMode:
direct-sign-fallback` plus the installable HAP paths. JSON failures use
platform-specific diagnostic codes such as `ohos.hap_build_failed`,
`android.apk_build_failed`, `ios.build_failed`, and `macos.build_failed` for
both projects and package examples.

`fluoh run --platform ohos|android|ios|macos` builds, installs, launches, and
diagnoses the current project or selected package example. For OHOS projects
and package examples it signs the HAP, installs it with `hdc`, starts the
ability, captures a short hilog, and reports runtime crash patterns. For
Android, iOS, and macOS package examples it launches through the selected SDK's
`flutter run`, captures smoke output under `$FLUOH_HOME/package-runs`, and runs
`flutter test integration_test -d <device>` when the example has an
`integration_test/` directory. Use `--device <id>` for an already connected
target or `--emulator <name>` to select and start a local emulator or simulator
where the platform provides one. Android, iOS, and macOS current-project runs
use the same Flutter device discovery, platform filtering, run-smoke timeout,
and saved output log path as package examples, but they do not run package
example integration tests.
JSON failures include platform run diagnostics such as `ohos.run_failed`,
`android.run_failed`, `ios.run_failed`, and `macos.run_failed` for
current-project runs, while package examples keep their more specific install,
launch, runtime, and integration-test diagnostics where available.

`fluoh package release` validates release metadata, verifies that the configured
SDK version exists in sources, runs `fluoh verify`, ensures the working
tree remains clean, creates release tags at HEAD, and optionally pushes them.
Use `--package <name>` for one package or `--all` for every registered package.
Existing tags are accepted only when they already point at HEAD. `--dry-run`
performs validation and verification without creating or pushing tags. `--json`
prints tags, warnings, and verification results.

`fluoh package status` reads Package `fluoh.yaml` and reports release readiness
without mutating the repository. It checks the current branch, clean working
tree, package status, release notes, license warnings, package tests, Flutter
example presence, example OHOS platform, example tests, and tracked files that
contain the local fluoh home path. Use `--package <name>` for one package,
`--all` for every package, and `--json` for machine-readable output.

## State Ownership

| State | Owner / Maintenance Entry |
| --- | --- |
| `$FLUOH_HOME/config.json` | `source add`, `source remove`, `source update`, first default Source bootstrap |
| `$FLUOH_HOME/sources/<name>` | `source add`, `source update` |
| `$FLUOH_HOME/sources.lock.json` | Source runtime in `lib/src/source/`; rebuilt after Source mutations, first default Source bootstrap, and load-index checks when stale or when selected-SDK installation needs SDK metadata |
| `$FLUOH_HOME/sdks/<version>` | `sdk install`, `sdk remove`, on-demand Flutter wrappers |
| Project `fluoh.yaml` | `sdk use`, `deps check`, `deps fix`, `deps upgrade` |
| Project `pubspec.yaml` | `deps fix`, `deps upgrade` |
| FlutterOH adaptation repository `fluoh.yaml` | `package create`, `package add`, `package sync`, `package status`, `package release` validation |
| Source root and Manifest files | `source init`, `source sync` |
| `.fluoh/flutter_sdk` | `sdk use`, `package create` SDK setup |
| Package examples | `package create`, `package add`, `deps get`, `verify`, `package release` |
