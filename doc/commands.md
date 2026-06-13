# Command Design

[简体中文](commands.zh-CN.md)

This document describes the full `fluoh` command surface and the design
boundaries behind each command. It complements [schema.md](schema.md): schema
docs define the data shapes, while this document defines how commands read,
write, and preserve that data.

Command implementations live mostly under `lib/src/<domain>/commands/`, with
top-level wiring in `lib/src/cli/fluoh_command_runner.dart`.

## End-to-End Workflows

AI-driven adaptation is the primary end-to-end path. The bundled
`skills/fluoh` workflow classifies the workspace, confirms the resolved scope,
then runs `fluoh` commands. This document defines those command contracts;
detailed agent routing, report wording, and repair ordering live in
`skills/fluoh/SKILL.md` and `skills/fluoh/references/`.

### AI-Driven Adaptation

Start by installing or refreshing the skill in the agent:

```text
Run `fluoh skill --json`, install the returned localPath as the fluoh skill, and overwrite any existing installation. Use https://github.com/FlutterOH/fluoh/tree/main/skills/fluoh only when fluoh is not installed yet.
```

Then give the agent the goal in one short request:

```text
Use $fluoh to install fluoh if needed and adapt this Flutter project for OHOS.
Use $fluoh to adapt <upstream-git-url> for FlutterOH, SDK 3.35.
Use $fluoh to continue adapting <package-name> for OHOS.
Use $fluoh to precheck this FlutterOH Source change.
```

When the CLI is missing, the skill handles installation. Agents can inspect the
bundled local skill path, helper scripts, and report templates with:

```text
Run `fluoh skill --json`, install the returned localPath as a skill, then reload skills if needed.
```

Agents use read-only preflight to present the final scope for user approval and
collect context before applying changes. Release, push, force-push, destructive
Git operations, and external publishing remain separate maintainer decisions.
The skill version follows the CLI package version; after `fluoh upgrade`,
reinstall or reload the path returned by `fluoh skill --json`.

### Add OHOS to an App Project Manually

Use this sequence from an existing Flutter project when the goal is to build or
run the app on OHOS without an AI agent:

```sh
fluoh source update
fluoh sdk use 3.35 --pub-get
fluoh deps check
fluoh deps fix --dry-run
fluoh deps fix
fluoh deps get
fluoh doctor --platform ohos --project
fluoh build ohos --auto-sign
fluoh devices --platform ohos
fluoh emulators --platform ohos
fluoh run ohos --auto-emulator
fluoh run ohos --device-id <id>
fluoh drive all --json
```

`fluoh sdk use` creates `ohos/` by default when the project does not already
have one. Use `--no-init-ohos` only when another workflow owns platform
creation. If no device or emulator is available, use
`fluoh build ohos --auto-sign --json` as build-only evidence and follow the
JSON diagnostic `nextCommand` for the next local setup step.

## Command Surface

Root help keeps CLI utility commands under `Fluoh`
(`skill`, `doctor`, `flutter`, `clean`, and `upgrade`), then lists
`SDK & Metadata` before project workflows because SDK and Source state often
gate adaptation. `Project` contains top-level app project commands: `create`
and `deps`. `Package` contains the `package` repository command group.
`Workflow` contains shared execution and evidence commands in the order `plan`,
`verify`, `build`, `run`, `attach`, `drive`, and `report`. `Devices` contains target
inventory and launch helpers: `devices` owns connected target discovery, and
`emulators` owns emulator or simulator launch.

| Command | Implementation | Purpose |
| --- | --- | --- |
| `fluoh --version` | `lib/src/cli/fluoh_command_runner.dart` | Print the `fluoh` version, Dart version, platform, and repository URL. |
| `fluoh help [command]` | `package:args` command runner | Print global or command-specific usage. |
| `fluoh skill` | `lib/src/cli/skill_command.dart` | Print local path, version, update, and prompt details for the bundled AI skill. |
| `fluoh clean` | `lib/src/clean/clean_command.dart` | Remove cleanable runtime artifacts under `$FLUOH_HOME/cache`. |
| `fluoh create [--sdk <version-or-series>] <args>` | `lib/src/project/create_command.dart` | Create a Flutter project with a FlutterOH SDK and pass remaining arguments to `flutter create`. |
| `fluoh plan app` | `lib/src/workflow/commands/plan_command.dart` | Print a read-only app adaptation plan and command queue. |
| `fluoh plan package` | `lib/src/workflow/commands/plan_command.dart` | Print a read-only package adaptation plan and command queue. |
| `fluoh flutter <args>` | `lib/src/sdk/flutter_command.dart` | Run `flutter` from the SDK selected by the nearest project `fluoh.yaml`. |
| `fluohf <args>` | `bin/fluohf.dart` | Shortcut for `fluoh flutter <args>`. |
| `fluoh source` | `lib/src/source/source_commands.dart` | Command group for package metadata source use and maintenance. |
| `fluoh source list` | `lib/src/source/source_commands.dart` | List configured FlutterOH package metadata sources. |
| `fluoh source add <name> <url-or-path>` | `lib/src/source/source_commands.dart` | Add a local or Git package metadata source to tool config. |
| `fluoh source remove <name>` | `lib/src/source/source_commands.dart` | Remove a non-official package metadata source from tool config. |
| `fluoh source update [name]` | `lib/src/source/source_commands.dart` | Refresh and validate configured source snapshots. |
| `fluoh source init <path>` | `lib/src/source/source_commands.dart` | Create a local source repository template. |
| `fluoh source sync [path]` | `lib/src/source/source_commands.dart` | Import released FlutterOH package repository metadata into a source repository. |
| `fluoh source check [source]` | `lib/src/source/source_check_command.dart` | Validate Source files and verify declared Package releases. Use `--schema-only` for local YAML/index validation. |
| `fluoh sdk` | `lib/src/sdk/sdk_commands.dart` | Command group for local FlutterOH SDK caches. |
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
| `fluoh package list` | `lib/src/package/commands/package_list_command.dart` | List FlutterOH packages from configured sources. |
| `fluoh package create <upstream>` | `lib/src/package/commands/package_create_command.dart` | Initialize a FlutterOH package repository. |
| `fluoh package discover <upstream>` | `lib/src/package/commands/package_discover_command.dart` | Discover Flutter plugin packages that may need OHOS adaptation. |
| `fluoh package add <package-path>` | `lib/src/package/commands/package_add_command.dart` | Create another package adaptation branch in a FlutterOH package repository. |
| `fluoh package queue <package-path>...` | `lib/src/package/commands/package_queue_command.dart` | Resolve a read-only multi-package adaptation queue for a monorepo. |
| `fluoh package sync` | `lib/src/package/commands/package_sync_command.dart` | Merge the selected upstream package release into the current OHOS package branch. |
| `fluoh package status` | `lib/src/package/commands/package_status_command.dart` | Summarize package release readiness. |
| `fluoh package handoff` | `lib/src/package/commands/package_handoff_command.dart` | Summarize package branch state, evidence, and next commands for AI handoff. |
| `fluoh package version` | `lib/src/package/commands/package_version_command.dart` | Update package release version metadata. |
| `fluoh package docs refresh` | `lib/src/package/commands/package_docs_command.dart` | Refresh generated package repository documentation. |
| `fluoh package check` | `lib/src/package/commands/package_release_command.dart` | Run release checks without creating tags. |
| `fluoh package release` | `lib/src/package/commands/package_release_command.dart` | Complete a FlutterOH package release. |
| `fluoh verify` | `lib/src/workflow/commands/verify_command.dart` | Run pub get, analysis, and tests for a project or package repository. |
| `fluoh build <platform>` | `lib/src/workflow/commands/build_command.dart` | Build a project or package example. |
| `fluoh run <platform>` | `lib/src/workflow/commands/run_command.dart` | Prepare the platform, launch with `flutter run`, and diagnose an app. |
| `fluoh attach <platform>` | `lib/src/workflow/commands/attach_command.dart` | Attach Flutter debug tooling to a `flutterRunSession`, VM Service URI, or device id. |
| `fluoh drive <platform>` | `lib/src/workflow/commands/drive_command.dart` | Run mobile app automation scenarios and evidence checks on OHOS, Android, and iOS targets. |
| `fluoh report create` | `lib/src/workflow/commands/report_command.dart` | Create an ignored local AI adaptation report from trace manifests and automation JSON. |
| `fluoh doctor` | `lib/src/doctor/doctor_command.dart` | Diagnose environment, native tools, and optional project state. |
| `fluoh devices` | `lib/src/platform/platform_target_commands.dart` | List connected Flutter targets, including OHOS, Android, iOS, Web, and host-supported desktop targets. |
| `fluoh emulators` | `lib/src/platform/platform_target_commands.dart` | List and launch local emulators and simulators for OHOS, Android, and iOS; desktop and Web platforms do not provide emulators. |
| `fluoh upgrade` | `lib/src/upgrade/upgrade_command.dart` | Upgrade the installed `fluoh` CLI. |

## Shared Runtime Rules

- Help requests never load source configuration.
- Source lock maintenance has one owner: the Source runtime in
  `lib/src/source/`. Command classes access `$FLUOH_HOME/sources.lock.json`
  through that runtime.
- Commands that change Source configuration or configured snapshots delegate the
  change to the Source runtime. The runtime validates every configured snapshot,
  repairs snapshots when possible, rebuilds the merged lock, and only then
  commits the new local Source state.
- Commands that consume Source data use only the Source runtime's load-index API.
  That API initializes the first default Source configuration and returns
  the existing `sources.lock.json` when its recorded fingerprint is still fresh.
  When the lock is missing or stale, the runtime verifies or repairs configured
  source snapshots, regenerates the lock, and only then returns data.
- `fluoh source` without a subcommand and `fluoh source list` use the same
  Source runtime rebuild path before printing configuration, so users see
  invalid or missing source state before relying on listed sources.
- `fluoh deps get` skips package Source data so dependency resolution remains
  available when source snapshots need repair. `fluoh flutter`, `fluohf`, and
  `fluoh deps get` may still load the Source index through the SDK resolver when
  the selected SDK is missing and selected-SDK installation needs SDK metadata.
- Usage errors and schema format errors return exit code `64`.
- Commands that support `--json` write exactly one machine-readable JSON object
  to stdout. The top-level contract is stable: `schema`, `command`, `ok`, and
  `exitCode` are always present, while command-specific fields such as `checks`,
  `targets`, `packages`, `dependencies`, and `error` remain at the top level.
  Automation should invoke the installed `fluoh` executable, not
  `dart run bin/fluoh.dart ... --json`, because the Dart launcher can print
  dependency-resolution text before the command process starts. For strict
  machine parsing, prefer the native/Homebrew executable. Dart pub global shims
  invoke `dart pub global run`; use them for JSON automation only after
  confirming stdout starts with the JSON object in that environment.
- `verify`, `build`, and `run` can write local AI diagnostic trace manifests
  with `--trace` or `--trace-dir <path>`. Trace data is local evidence, not
  verbose stdout. With `--json`, the JSON object includes a `trace` reference
  with the trace id, directory, and `trace.json` path. If trace writing fails,
  the workflow result and exit code still reflect the underlying command, and
  the JSON object includes `traceError`. Reusing the same `--trace-dir`
  accumulates related command invocations in one session manifest.
- Local AI reports are ignored evidence under `.fluoh/reports/`. The skill
  helper `new_report.py` writes
  `.fluoh/reports/<report-group>/report-<timestamp>.md`, where
  `<report-group>` is the package slug when `--package` is supplied and is
  otherwise the scope slug. The summary helper `new_summary.py` writes
  `.fluoh/reports/<scope-slug>/summary-<timestamp>.md`. Timestamps are Unix
  epoch milliseconds.
- Local trace manifests are ignored evidence under `.fluoh/traces/`. With
  `--trace`, project or multi-target commands write
  `.fluoh/traces/<trace-id>/trace.json`; a single package target writes
  `.fluoh/traces/<package-slug>/<trace-id>/trace.json`. The generated trace id
  is `<command-slug>-YYYYMMDD-HHMMSS-micros`. With `--trace-dir <path>`, the
  manifest is exactly `<path>/trace.json`, relative paths are resolved from the
  working directory, and the trace id is derived from the final directory
  segment. AI adaptation loops should use one stable session directory such as
  `.fluoh/traces/<package-or-scope>/<session-id>` so `verify`,
  `build`, and `run` append to one manifest.
- Command classes should own argument parsing and user-visible output. Reusable
  behavior belongs in domain helpers such as `lib/src/sdk/`, `lib/src/deps/`,
  `lib/src/package/`, and `lib/src/source/`.
- Mutating commands must validate early, preserve unrelated files, and report
  what changed or what the user should do next.

## Command Groups

### `fluoh clean`

`clean` removes only `$FLUOH_HOME/cache`, which contains cleanable runtime
artifacts such as OHOS debug signing material and package run logs. It does not
remove SDK installations, Source snapshots, config, lock files, or project
`.fluoh/` reports. Use `--dry-run` to inspect the cache without deleting it and
`--json` for machine-readable cleanup reports.

### `fluoh create [--sdk <version-or-series>] <args>`

`create` is a project creation wrapper around `flutter create` from a
FlutterOH SDK. It accepts optional fluoh flags such as
`--sdk <version-or-series>` and `--json` before the Flutter arguments. When
`--sdk` is omitted, it selects the latest stable SDK release from configured
Sources, falling back to the newest installed local SDK when Source indexes are
unavailable. The selected SDK is installed on demand.

All non-fluoh arguments are passed to `flutter create` unchanged. After a
successful create, the command writes the new project's `fluoh.yaml` and
`.fluoh/flutter_sdk` so follow-up `fluoh deps`, `fluoh run`, and
`fluoh drive` commands use the same SDK. Use `--` before Flutter arguments
that should not be parsed by fluoh:

```sh
fluoh create --sdk 3.35 -- --org com.example demo_app
fluoh create demo_app --platforms=android,ios,ohos
```

`--json` writes one standard machine-output object to stdout. Human progress and
Flutter child output are suppressed; the child command arguments, exit code, and
stdout/stderr tails are reported under `flutter`. Successful reports also
include the selected `sdk`, created `project`, whether SDK metadata was written,
and the `.fluoh/flutter_sdk` link path.

### `fluoh plan app|package`

`plan app` inspects the current Flutter app project without writing
files. It reports whether the directory looks like a Flutter app, which platform
directories already exist, the selected or requested FlutterOH SDK, and a
structured command queue for dependency checks, OHOS build/run evidence,
OHOS device/emulator discovery, existing-platform regression checks, automation
evidence, and report creation. `build`, `run`, `drive`, and `report create` commands
share one `.fluoh/traces/<scope>/adaptation` session when the underlying
command supports trace output. `--json` writes a single machine-readable object
with `changed: false` and `applied: false`, so AI agents can use it for scope
confirmation before requesting mutating commands. The JSON also includes
`automationRunbook` and `deliveryGate` for the repair loop, terminal states,
final check commands, report check command, and conditions that must be met
before an AI agent can claim `ready`. Ready requires reviewing existing tests
and `integration_test/` coverage before final verification, adding or repairing
missing functional tests, and collecting functional evidence for OHOS plus every
existing platform directory supported by the current host/toolchain. Unsupported
platforms require exact diagnostic evidence and a recorded skip reason.

`plan package` does the same read-only planning for the current
FlutterOH package branch. It reads package `fluoh.yaml`, reports branch and
working-tree state, selected SDK, upstream/release metadata, example platform
directories, and a command queue for generated docs, verification, OHOS
build/run evidence, OHOS device/emulator discovery, unified platform
automation, existing-platform example regressions, handoff, report creation,
and release checks. `verify`, `build`, `run`, `drive`, and `report create` commands
share one `.fluoh/traces/<package>/adaptation` session when supported. The plan
keeps Android, iOS, and OHOS implementation work behind platform-specific steps
while the upper-level queue is called through one `plan package` contract. Its
delivery gate requires the final `package check` to run with
`--report <report-path>` so report certification failures cannot be reduced to
non-blocking warnings.

### `fluoh flutter <args>` and `fluohf <args>`

These commands are pass-through wrappers around the selected FlutterOH SDK.
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
`--strict` is used. Bare `fluoh doctor` checks the fluoh installation, Git and
Dart, configured source snapshots, OpenHarmony SDK tooling, Android SDK and
Java tooling, Chrome/web tooling, and host-supported Apple or desktop tooling.
Plain output streams each check as soon as it completes, so long device
discovery does not make the command appear idle. JSON mode waits for all
checks and writes one machine-readable object.

OpenHarmony toolchain output focuses on SDK path/version, `hdc`, and emulator
version or missing state. When both iOS and macOS are selected, Xcode is checked
and printed once as a combined iOS/macOS toolchain; selecting only one platform
keeps the platform-specific Xcode title. Connected devices use Flutter-style
aligned rows with name, id, platform, and details.

The command intentionally has no `-v` or `--verbose` alias because Dart's
`pub global run` treats verbose flags as pub logging flags when a global
executable falls back to pub, which can print dependency solver output before
fluoh starts. `doctor` also has no separate `--details` mode; plain output
already prints the full human-readable checks, and machine-readable details are
available with `--json`. When the current directory is a Flutter project, it
also checks project shape, selected FlutterOH SDK, and the selected platform
directories only when `-p` or `--project` is passed. Use
`--platform ohos|android|ios|macos|linux|web|windows` to narrow native toolchain and project
platform checks.

Missing or stale state is reported as warnings rather than immediate
remediation. Use platform-scoped strict checks such as
`fluoh doctor --platform ohos --json --strict` when automation needs a native
toolchain gate, and
`fluoh doctor --platform ohos --project --json --strict` when it also needs a
current-project gate. Project
JSON includes `platformDirectories` data for the selected platform set so
automation can decide whether to create or skip OHOS, Android, iOS, macOS,
Linux, Web, or Windows platform projects. `--json` prints the same checks as
machine-readable JSON and includes each check's `id`, `group`, and structured
data when the check has it.

### `fluoh devices` and `fluoh emulators`

`fluoh devices` lists connected OHOS, Android, Web, and targets supported by
the current host by default. It accepts
`--platform all|ohos|android|ios|macos|linux|web|windows` and `--json`; passing
Linux, Windows, iOS, or macOS explicitly turns that platform into the checked
target even when the current host cannot run it. Plain output uses Flutter-style
`Name • id • platform • details` rows and prints platform warnings after
discovered targets.

`fluoh emulators` lists local OHOS, Android, and iOS simulator targets with
`Id • Name • Manufacturer • Platform` rows. macOS, Linux, Web, and Windows are
host or browser targets and report no local emulators. The command accepts the
same `--platform` and `--json` options. `--launch <id-or-name>` starts a local
emulator or simulator and requires selecting a single platform.

### `fluoh upgrade`

`upgrade` upgrades the CLI installation, not project dependencies. It executes
`brew upgrade fluoh` for Homebrew installs or
`dart pub global activate fluoh` for Dart global installs. Local source
checkouts are refused because replacing a checkout is a user-owned decision.
The bundled skill is versioned with the CLI; after upgrading, rerun
`fluoh skill --json` and reinstall or reload the returned skill path in the
agent that copied it.

## Source Commands

Source commands are split into consumer commands that manage configured
snapshots and maintainer commands that edit source repositories. A source
snapshot is the validated local copy of a Source stored under
`$FLUOH_HOME/sources/<name>`.

### Consumer Commands

`fluoh source list` first asks the Source runtime to ensure configured source
snapshots and `sources.lock.json` are usable, then reads `$FLUOH_HOME/config.json`
and prints each configured source name and display value. Empty configuration is
a warning, not an error. `--json` prints the same configured source list with
source names, display values, cache paths, URLs, and priorities.

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
  priority replaces lower priority records for the same group. Default consumer
  indexes include only `compatible` release records. `deps check`, `deps fix`,
  and `deps upgrade` can include non-compatible records for a single run with
  `--all-release-statuses`.
- Same-priority records with the same derived tag but different repository
  or path are an error. Different tags in the same group can coexist, and the
  dependency planner selects the best eligible release record for the project
  policy.
- Package-level upstream URL and advisory text come from the highest priority
  source that defines the package.

`fluoh source remove <name>` removes a user Source from tool config. The official
Source alias `flutteroh` is tool-owned with priority `0`. The command owns only
the config entry being removed. Lock maintenance is delegated to the Source
runtime.

`fluoh source update [name]` refreshes all sources or one named source. Selected
Git sources are cloned again, and selected `file:` sources are copied again from
their configured local directories. The Source runtime then validates every
configured source snapshot because the lock is a merged index over all
configured sources. Git transport failures are reported as sync failures with
retry guidance, while cloned source content that fails schema validation keeps
the source validation diagnostic.

Source mutation commands pass the candidate config or snapshot state to the
Source runtime. If validation or lock generation fails, the runtime preserves
the previous usable config, snapshots, and lock.

### Maintainer Commands

`fluoh source check [path] --schema-only` validates a local Source repository
without reading or writing `$FLUOH_HOME/config.json`, source snapshots, or
`sources.lock.json`. When `path` is omitted, the current directory is used. The
command checks the Source root schema, SDK metadata, Manifest routes, Manifest
names, package route/name consistency, package release records, and whether the
package index can be built. It does not read Git diffs, fetch SDK tags, clone
package repositories, or verify declared releases; release metadata updates
remain the job of `fluoh source sync`.
`--schema-only` is a local Source check mode, so it cannot be combined with
diff, release, work-root, or Package verification options.

`fluoh source init <path>` creates a source root `fluoh.yaml`, a
`manifests/example/fluoh.yaml` commented Manifest template, and a README. It is
conservative when those files already exist and reports the template as
skipped. The generated `fluoh.yaml` is a valid empty Source scaffold with
commented repository, SDK, and Manifest routing examples so maintainers can
uncomment the needed sections.
Maintainers edit Manifest files directly for advisory and maintenance notes;
release records are generated by `fluoh source sync`.

`fluoh source sync [path]` reads Manifest routes from the Source root, uses each
Manifest `repository.git.url` as the FlutterOH package repository, discovers
release tags with `git ls-remote --tags`, compares them with current Source
release records, then opens a package repository only when selected tags are not
already recorded. It reads the Package `fluoh.yaml` frozen under those new tags
and writes historical release records into same-name package Manifest routes.
When `path` is omitted, the current directory is used. Source metadata must come
from released
adaptation records, not in-progress repository state. When `<path>` is one of
the configured source snapshots under `$FLUOH_HOME/sources/<name>`, sync is
treated as a configured Source snapshot mutation and the Source runtime rebuilds
the merged lock. When `<path>` is a maintainer checkout outside the configured
snapshots, the local lock is not changed; run `fluoh source update <name>` after
publishing or copying the Source into a configured snapshot. Use
`--manifest <name>` or `--package <name>` to target sync discovery, and
`--concurrency <n>` to bound parallel tag discovery for large Sources. `--json`
prints synced and skipped package records plus a `plan` with `knownTags`,
`discoveredTags`, `tagsToSync`, `skippedTags`, and per-route status. When the
Source root declares `sdk.versions`, tags whose SDK line is not represented by
those SDK versions are skipped with reason `sdk-line-not-in-source`. Tags with
missing or invalid Package `fluoh.yaml`, tag/metadata mismatches, or a
`package.path` that differs from the current Source Manifest are also skipped
per tag and reported in `skippedTags` instead of aborting the whole sync.
Release tags are treated as immutable records derived from release metadata;
moving an existing tag is not auto-synced and should be handled by publishing a
new release tag or by manual maintenance.

`fluoh source check [source]` is a read-only verification command for Source
maintainers and CI. When `source` is omitted, the current directory is checked.
`source` may be a local Source checkout path or a GitHub pull request URL. The
command validates Source files, detects changed Manifest routes, then verifies
declared Package release references. Release verification clones referenced
FlutterOH package repositories, checks declared release tags, reads the Package
manifest branch at each tag, and runs
`fluoh package check --package <name> --json` at the tagged commits. Source
metadata import and file updates remain the job of `fluoh source sync`.
The JSON output includes `recommendation`, `changeType`, `affectedManifests`,
`changedReleaseRecords`, `releaseCheckPlan`, `skippedReleaseChecks`,
`sdkChecks`, `changedFiles`, `errors`, `warnings`, and the supporting
checkout/check details. By default the command checks Manifest files changed
from `--base-ref`. When only the Source root `fluoh.yaml` changed, it compares
Manifest route names between the base ref and HEAD, checks only added or removed
routes, checks added SDK tags with `git ls-remote --tags`, and keeps SDK-only root
metadata changes scoped to the root file. For changed Manifest files it
compares release records against the base ref and verifies only added or
modified release records, package additions, SDK-line additions, repository
changes, or `package.path` changes. PR diff checks validate the
Source root plus only the affected Manifest routes; explicit full audits,
diff-fallback checks, and push/manual `--skip-release-checks` checks validate
all Manifest routes. Advisory-only, maintenance-only, and deleted release
records are YAML-only checks. If the target is not a Git worktree
or the diff cannot be read, it falls back to every Manifest route and reports a
warning. Pass `--all` for explicit full audits that should check every Manifest
route, and pass `--skip-release-checks` when CI should validate Source YAML and
changed-route selection without cloning Package repositories.
Full audits can be narrowed with `--manifest <name>`, `--package <name>`,
`--shard <index>/<total>`, `--concurrency <n>`, and
`--max-release-checks <n>`. `--all` and `--base-ref` are mutually exclusive.
Treat `ready` as a technical check pass, `blocked` as non-mergeable until errors
are fixed, and `needs-maintainer-decision` as a manual decision signal. Pull
request automation should use the command as a check plus comment; final
approval and merge remain maintainer-owned.

## SDK Commands

`fluoh sdk list` merges remote source releases with locally installed SDK
caches. If source indexes are unavailable but local SDKs exist, it still lists
the local entries. `--json` prints SDK entries with version, channel,
installation state, and status.

`fluoh sdk install <version-or-series>` accepts an exact SDK version or a series
such as `3.35`. Series selection prefers the latest stable version. The manager
clones the SDK repository into `$FLUOH_HOME/sdks/<version>`, checks out the
matching Git tag, and deletes a partial destination on failure.

`fluoh sdk current` reads the current project SDK version. If no SDK is selected
it prints a warning and returns exit code `1`. `--json` reports whether a
selection exists and the selected version when present.

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
lockfile. By default only `compatible` Source release records are considered.
Pass `--all-release-statuses` to also consider experimental and broken
releases. `--json` prints the same plan as machine-readable JSON.

`fluoh deps fix` applies recommended FlutterOH adaptation changes from the
dependency plan. It writes to either `dependency_overrides` or direct dependency
declarations according to `dependencyPolicy.pubspecSection`. Version mismatches
are skipped unless `dependencyPolicy.versionChanges` is `any`; non-compatible
release statuses are skipped unless the command uses `--all-release-statuses`.
`--dry-run` or `-n` prints the plan without modifying `pubspec.yaml`. `--json`
prints the same plan as machine-readable JSON with change summaries, applied
count, and dry-run flag. Before writing, it validates the generated YAML and
restores the original `pubspec.yaml` if validation or writing fails.

`fluoh deps upgrade` is narrower than `deps fix`: it upgrades existing FlutterOH
dependency replacements and does not add new replacements. It uses the same
version-change policy, command-scoped release status option, and dry-run
behavior. `--json` prints the dependency plan, change summaries, applied count,
and dry-run flag without human progress text.

## Package Repository Commands

`fluoh package list` is a source-consuming query command. It lists package names
advertised by configured sources, along with compatible SDK lines and source
aliases. It reads through the Source runtime, so it initializes or refreshes the
Source lock when needed. `--json` prints the same list as machine-readable JSON.

The remaining commands maintain FlutterOH package repositories. They assume Git
repositories and are intentionally strict about branch and working tree state.

The AI implementation loop for these commands is split between the routing
skill in `skills/fluoh/SKILL.md` and the detailed workflows in
`skills/fluoh/references/`, so user documentation stays short and every agent
uses one maintained workflow entry point.

### Adaptation Workflow

Adaptation is maintained by package branch and FlutterOH SDK line, not SDK
patch version. For example, complete SDK `3.35.8-ohos-0.0.3` maps to SDK line
`3.35`, and package `camera` is maintained on `ohos/3.35/camera`.

Recommended flow:

1. Select a complete SDK version.
2. Derive the SDK line from that SDK version.
3. Create or switch to `ohos/<sdkLine>/<package>`.
4. Record the currently adapted upstream package version and FlutterOH
   adaptation package version in Package `fluoh.yaml`.
5. Before adding OHOS code, run verifications with the selected SDK, including
   `fluoh deps get`, `fluoh flutter analyze`, and existing package tests or
   example builds. Fix non-OHOS platform regressions first.
6. Use `status: experimental` while adaptation is in progress. Omit `status`
   when the release is complete and recommended; omitted means `compatible`.
7. `fluoh package version` updates the adaptation package release version and
   status.
8. `fluoh package check` runs the final local gate without creating tags.
9. `fluoh package release` creates the release tag, freezing the code, tests, and
   Package `fluoh.yaml`.
10. `fluoh source sync` imports per-package Source Manifests from release tags.

`fluoh package create <upstream>` clones the upstream repository, selects one
package, creates a FlutterOH branch such as `ohos/3.35/camera`, configures the
SDK and remotes, writes `fluoh.yaml`, generated docs, changelog scaffolding,
and agent instructions, then stages generated files. If the selected package
has an existing Flutter example, the command adds OHOS platform files and
example SDK config. It never commits.
With no `--package-path`, only the repository root package is selected. For
monorepos, keep one adaptation repository per upstream repository and add more
package branches with `fluoh package add <package-path>`. `package create` and
`package add` select the latest valid upstream release tag by default; use
`--upstream-version` for a specific package release and `--upstream-ref` only
when release tags cannot identify the target snapshot.
The command requires `--repository-name <repository-name>`, which supplies the
default output directory and default FlutterOH origin URL when those options are
omitted. Package identity still comes from `package.name`.
Options include `--package-path`, `--upstream-version`, `--upstream-ref`,
`--output`, `--repository-name`, `--sdk`, `--repository`,
`--git-author-name`, `--git-author-email`, `--org`, `--plan`, and `--json`.
Git author options configure only the new repository's local Git identity.
`--org` overrides the organization passed to `flutter create` for example OHOS
platform creation.
`--plan --json` performs the clone-and-resolve phase in a temporary directory,
prints a single machine-readable plan object, and does not create repositories,
write files, stage files, or commit. The plan includes `warnings[]` for cases
such as Dart SDK incompatibility, default-branch unreleased versions, and
federated implementation recommendations.

`fluoh package discover <upstream> --json` shallow-clones the upstream
repository into a temporary directory, scans non-example `pubspec.yaml` files,
and reports Flutter plugin packages whose `flutter.plugin.platforms` do not
declare `ohos`. It is read-only and does not create a package repository,
configure remotes, checkout branches, or write project files. JSON output
includes the filter, inspected pubspec count, valid Flutter plugin count,
candidate and recommended counts, candidate package names, paths, versions,
declared platforms, federated `default_package` declarations, missing
platforms, per-candidate `createCommand`, federated
`implementationRecommendation` details when an app-facing plugin should grow a
new platform implementation package such as `<package>_ohos`, a multi-package
`queueCommand`, and non-fatal `issues[]`. The default `queueCommand` contains
only recommended candidates; existing Android, iOS, Web, Linux, macOS, or
Windows implementation packages referenced by an app-facing package's
`default_package` entries, or in the same federated family such as
`<package>_android`, remain visible but are marked
`covered_by_federated_app_facing_package` with
`coveredByImplementationRecommendations[]`. Test fixture plugins and
platform-specific helper plugins remain visible as context with roles such as
`test_fixture` or `platform_specific_helper`, but are also excluded from the
default queue. Use it when an AI or maintainer receives a monorepo upstream URL
without an explicit package path and needs a short package selection list before
running `package create`. Pass
`--include-existing-platform` to include Flutter plugins that already declare
the requested `--missing-platform`, which defaults to `ohos`.

`fluoh package queue <package-path>... --json` resolves a read-only
multi-package queue in an existing FlutterOH package repository. It fetches
upstream refs, keeps the current branch checked out, reports each package name,
path, selected upstream target, target `ohos/<sdkLine>/<package>` branch,
whether that branch already exists, SDK/Dart compatibility warnings, and the
next `fluoh package add` or `package status` command. Use it before adapting
multiple packages in one upstream monorepo, then finish one package branch
checkpoint before moving to the next. When running verify/build/run/check
commands across multiple existing package branches, prefer a fresh clone or
separate Git worktree per package branch so ignored platform build artifacts
from one branch cannot become untracked files on the next branch. Do not run
destructive cleanup commands such as `git clean` without explicit maintainer
approval.

`fluoh package add <package-path>` creates another package branch in an existing
FlutterOH package repository. It requires a clean working tree, resolves the
target package on the synchronized upstream branch, checks out the selected
release target commit, creates `ohos/<sdkLine>/<package>`, writes a
single-package `fluoh.yaml` and docs, prepares an existing Flutter example when
present, and stages generated files. It supports `--upstream-version` and
`--upstream-ref` with the same selection rules as package create, plus `--org`
to override the inferred example organization passed to `flutter create`.
`--plan --json` resolves the add plan without checking out, writing project
files, or requiring a clean working tree; the plan includes `warnings[]` with
the same keep-latest SDK compatibility policy as package create. If the target
package branch already exists, it points maintainers to the existing branch,
`fluoh package status`, and `fluoh package sync` instead of creating duplicate
adaptation state. File snapshots protect local state when the command fails.

`fluoh package docs refresh` regenerates the fluoh-owned sections of
`FLUOH.md` and `AGENTS.md` from the current Package `fluoh.yaml` plus the
current checkout's package pubspec. When the selected package is a federated
app-facing plugin with `default_package` declarations and no OHOS platform,
refresh re-derives the same `<package>_ohos` implementation route used by
`package create`, so older generated repositories gain the current AI guidance
after a tool upgrade. Generated sections are identified by `fluoh:generated`
markers that include a stable section id and template version, so future
template upgrades can replace only the owned section while preserving
hand-written content. Existing non-empty `FLUOH_CHANGELOG.md` content is not
rewritten; when the changelog is missing or empty, the command creates initial
release headings from current package metadata with TODO placeholder entries
that must be replaced before release. `--dry-run` reports files that would
change without requiring a clean working tree. Writing requires the recorded
package branch and a clean working tree, does not stage files, and does not
change `fluoh.yaml`. `--allow-dirty` explicitly permits writing generated docs
before a clean checkpoint is available, such as immediately after `package
create`; it still writes only the planned generated documentation files and does
not stage them. `--json` reports `changed`, `applied`, `files`, `dryRun`, and
`allowDirty`.

`fluoh package handoff --json` reads the current package branch, Git status,
latest `.fluoh/traces/**/trace.json`, and `.fluoh/reports/<package>/*.md`
files, then prints a single JSON object with package metadata, current branch,
manifest branch, branch match state, dirty-state summary, evidence paths, the
trace directory that follow-up commands should reuse, and next commands. When a
current-package trace exists, handoff reuses the latest trace directory under
`.fluoh/traces/<package>/`; otherwise it defaults to
`.fluoh/traces/<package>/adaptation`. When a report exists, the next
`package check` command includes `--report <latest-report-path>`. It does not
modify the repository. Use it when an AI task needs to resume, transfer, or
confirm whether the branch is ready for final verify, drive evidence, report
creation, or `package check`.

`fluoh package sync` fetches upstream branches and tags, fast-forwards the
upstream branch recorded in Package `upstream.git.branch`, resolves the package
target from `--upstream-version`, `--upstream-ref`, or the latest valid release
tag, returns to the `repository.git.branch` branch recorded in `fluoh.yaml`,
merges the selected target commit without committing first, updates upstream
metadata in `fluoh.yaml`, stages it, and commits `Sync upstream package` when
changes are present. When no valid release tag exists and no explicit target is
passed, it falls back to the synchronized upstream branch HEAD. If the resolved
target already matches the current branch metadata and commit, `sync` reports
that the package branch already adapts that upstream version and exits without a
commit. `sync` refuses explicit package versions older than the current branch
upstream version; mark the current adaptation `broken` with
`fluoh package version --status broken` instead of downgrading the branch. Merge
conflicts are left for the user to resolve, then `fluoh package sync --continue`
validates staged resolution and finishes. If the interrupted merge used a custom
non-tag ref, pass the same `--upstream-ref` with `--continue`; release tags can
usually be inferred from `MERGE_HEAD`, but non-tag refs cannot. Continue also
verifies that the resolved working-tree package version matches the selected
upstream target before updating `fluoh.yaml`. `--abort` runs `git merge --abort` for an in-progress
sync. `--json` prints the completed sync action list and commit status. Fetch
failures emit `sync.fetch_failed`; merge conflicts emit
`sync.merge_conflict` with conflicted files and the `--continue` next command;
merge failures that do not leave resolvable conflicts emit `sync.merge_failed`.
JSON diagnostics include trimmed stdout and stderr tails when Git produced
useful output.

`fluoh verify` runs automated verification for either the current
project or the package recorded in Package `fluoh.yaml`. It runs selected-SDK
`pub get` and `analyze`, uses `flutter` for Flutter packages and `dart` for
non-Flutter packages, and runs tests when `test/**/*_test.dart` exists. In a
package repository it also verifies each top-level Flutter example when
`example/pubspec.yaml` is present. When it finds `integration_test/`, it records
a skipped discovery step with suggested platform `fluoh run ... --json`
commands; this is a prompt to collect device evidence, not passed interaction
evidence. Use `--package <name>` to validate the
requested package name against the current branch. `--json` reports each
project or package under `targets`, with target identity, phase, steps,
diagnostics, and `nextCommand`. Use `--trace` to write a local AI diagnostic
trace under `.fluoh/traces/`, grouped by package as
`.fluoh/traces/<package>/<trace-id>/trace.json` when one package target is
selected, or `--trace-dir <path>` to choose the trace session directory whose
manifest is `<path>/trace.json`. In JSON mode, the command still writes exactly
one object to stdout and includes only a `trace` reference to the local
manifest, or `traceError` when the trace could not be written.
It also reports `dirtyAfterVerify` and `workingTreeChanges` when the target is
inside a Git worktree, so agents can detect generated files or lockfile changes
left by `pub get` before committing. Reuse one `--trace-dir` across an
adaptation loop to accumulate command invocations in one session.

`fluoh build all|ohos|android|ios|macos|linux|web|windows` builds the current
Flutter project or the selected package example. `all` expands to the workflow
platform directories that already exist in the current project root or selected
package `example/`, runs them in order, and records every selected platform
result instead of stopping after the first failed platform. Use a concrete
platform argument to diagnose or intentionally create coverage for a missing
platform directory. iOS builds automatically add `--no-codesign`. OHOS builds
can use `--auto-sign` to generate a temporary local debug signing profile from
the project's or example's requested permissions, patch
`ohos/build-profile.json5` for that build, and restore the original file after
the build. With `build all --auto-sign`, automatic signing is applied only to
platforms that support it. If Flutter leaves a fresh unsigned HAP after Hvigor
signing fails, `fluoh` directly signs that HAP and reports `signingMode:
direct-sign-fallback` plus the installable HAP paths. JSON failures use
platform-specific diagnostic codes such as `ohos.hap_build_failed`,
`android.apk_build_failed`, `ios.build_failed`, `macos.build_failed`,
`linux.build_failed`, `web.build_failed`, and `windows.build_failed` for
both projects and package examples. `--trace` and `--trace-dir <path>` follow
the same local AI diagnostic trace contract as `fluoh verify`. JSON output is
a factual evidence summary, not a release-readiness decision. It includes
`workflowEvidence.classification: buildOnly`, `observedEvidence`,
`collectedEvidenceKinds`, `notCollectedEvidenceKinds`,
`workflowContinuations`, and a `toolCommands` entry for the follow-up run smoke
command when builds pass. `collectedEvidenceKinds` records collected command
results or artifacts; `observedEvidence` records whether they passed, failed,
were skipped, or were blocked.

`fluoh run all|ohos|android|ios|macos|linux|web|windows` prepares the platform
and launches the current project or selected package example through the
selected SDK's `flutter run`. `all` expands to the existing workflow platform
directories in the current project root or selected package `example/`, runs
them in order, and keeps collecting later platform results after an earlier
platform fails. OHOS uses the same Flutter run path as the other platforms;
temporary debug signing preparation and restoration are applied for OHOS runs.
Android and iOS signing, device, emulator, and simulator prerequisites use the
same run-preparation and target-selection layers. Web runs use browser targets
such as Chrome.
When `integration_test/` exists and a concrete target is available, `fluoh run`
also runs `flutter test integration_test -d <device>` on that target. Release
reports should record that passed test command row separately because a plain
`fluoh run --json` row is launch evidence.
`--session-file <path>` writes a `flutterRunSession` file with process, target,
launch, log, and VM Service URI details when available. `fluoh attach` can reuse
that file, or accept `--vm-service-uri <uri>` or `--device-id <id>` directly.
It prefers `flutter attach --debug-uri <uri>` and falls back to
`flutter attach -d <targetId>` unless `--require-vm-service` is set.
Target options are shared across run and drive: use `--device-id <id>` for an
existing target, `--emulator <name>` for a specific local emulator or
simulator, or `--auto-emulator` to prefer local emulators/simulators before
falling back to connected devices. `run all` accepts `--auto-emulator`, but
`--device-id`, `--emulator`, and `--session-file` are single-platform options.
JSON output includes `workflowEvidence.classification: launchSmoke`,
`observedEvidence`, `collectedEvidenceKinds`, `notCollectedEvidenceKinds`,
`workflowContinuations`, and factual interaction evidence observed by that run
command. `collectedEvidenceKinds` may include failed command results; the
pass/fail state is recorded in `observedEvidence`. When mobile platforms launch
successfully, the
`workflowEvidence.toolCommands` list includes the matching `fluoh drive ...
--dry-run --json` command so AI agents can plan taps, gestures, permission
grant/deny paths, screenshots, and result assertions instead of treating launch
as complete.
For `observedEvidence.interaction.status`, `integrationTestEvidenceFailed`
takes precedence over any passed integration-test rows in the same matrix, and
`partialIntegrationTestEvidence` means only some targets produced passed
integration-test evidence. In both cases, continue the repair or evidence loop
instead of treating the run as release-ready.

Run-smoke success only proves launch. Workflows that need UI interaction,
permissions, files, camera, location, media, deep links, or external apps need
functional evidence from a passed `integration_test`, `fluoh drive`, or
`manual-assisted` tool-readable evidence. Manual-assisted is an operation mode;
it still requires logs, session status, stable text, semantic labels, test keys,
command JSON, hilog, or app log markers. If no interaction is required, the
report must state `No interaction required: <reason>`.
Package adaptations must not validate only OHOS. Existing Android, iOS, macOS,
Linux, Web, and Windows package/example platform directories are also required
functional test targets when the current host and toolchain support them;
unsupported targets must be recorded with the diagnostic command and blocker.

Interaction scenarios live under
`.fluoh/scenarios/<package>/<platform>-<name>.md` and use
`skills/fluoh/references/interaction-scenario-template.md` as the action
contract. Scenario Markdown may include fenced YAML with
`kind: fluoh.automationScenario`, `platform`, `steps`, and optional `coverage`
metadata.

`fluoh drive all|ohos|android|ios` is the mobile automation wrapper for target
launch, interaction scenarios, and evidence checks. It follows `fluoh run`
target selection, expands `all` to existing OHOS, Android, and iOS platform
directories, defaults to local emulator/simulator preference, and can run the
current project or the current or selected package branch. Dry-run and real-run
JSON include `deliveryRecommendation`, `repairPlan`, `repairQueue`, and
`automation.coveragePolicy`; real runs also include workflow `targets` and an
`automation` object with launch/session evidence and replay artifacts. The
stable coverage fields are `scenarioCoverage`, `coverageSummary`, `inventory`,
`capabilityCoverage`, `manifestPermissionCoverage`, `pathCoverage`,
`scenarioEvidence`, `qualityGates`, and `repairLoop`. Detailed repair ordering
belongs in the skill and report template.
Real drive runs the same launch and available `integration_test/` steps first;
scenarios execute only for targets whose run and integration-test steps passed.

Executable scenarios support `captureScreenshot` and `screenshot` as supporting
observation actions. Android saves `adb exec-out screencap -p`, iOS saves
`xcrun simctl io <target> screenshot`, and OHOS saves a `snapshot_display`
artifact received through `hdc file recv`. The action result records the local
path and byte count. Screenshots are evidence artifacts; functional pass/fail
should still be backed by tool-readable assertions such as `assertText`,
`assertLog`, `assertSession`, or integration-test output.

Runtime permissions require explicit grant, deny, and differing error-path
coverage on each supported platform, or a reasoned `notApplicable` or `blocked`
row. iOS automation uses the built-in XCTest runner when possible; set
`FLUOH_XCODEBUILD` for explicit Xcode selection and `FLUOH_IOS_PERMISSION_DRIVER`
only when a permission driver must be forced.

JSON failures include platform run diagnostics such as `ohos.run_failed`,
`android.run_failed`, `ios.run_failed`, `macos.run_failed`, `linux.run_failed`,
`web.run_failed`, and `windows.run_failed` for current-project runs, while
package examples keep platform-specific device, run, runtime, and
integration-test diagnostics where available. `--trace` and
`--trace-dir <path>` follow the same local AI diagnostic trace contract as
`fluoh verify`.

`fluoh report create` writes a git-ignored canonical Markdown report under
`.fluoh/reports/<scope>/report-<timestamp>.md` unless `--output` is
provided. With `--output`, the exact path is used for the canonical report. It
accepts one or more `--trace-dir` values and saved
`--automation-json` files, extracts command rows, coverage gates, interaction
evidence, diagnostics, and fluoh feedback candidates, then writes the standard
AI report sections needed by package check and handoff workflows. `--json`
reports the path as `report`. The command owns only local report composition
and release recommendation; the maintainer still owns final release approval
and any publish, push, tag, store, or registry action.

`fluoh package version` updates the release metadata for the current package
in `fluoh.yaml`. Use `--bump patch|minor|major` to increment the FlutterOH
adaptation package version, `--set <version>` to set an exact version, and
`--status experimental|compatible|broken` to set release status. `compatible`
removes the status field because compatible is the default. `--bump` and
`--set` are mutually exclusive. Use `--dry-run` to print the planned change
without writing, and `--json` for machine-readable output.

`fluoh package check` validates release metadata, verifies that the configured
SDK version exists in sources, runs `fluoh verify`, ensures the working tree
remains clean, and reports the release tag that would be created. It never
creates or pushes tags. Use `--package <name>` to validate the requested package
name against the current branch. `--json` prints tags, warnings, certification
state, and verification results. Checks do not require device or AI report evidence by
default; they print a non-blocking warning when no certification report is
provided. Use `--report <path>` to require a
completed `.fluoh/reports/<scope>/report-<timestamp>.md` before passing the check. Certification
reports must be `ready`, complete every delivery checklist item, include passed
`fluoh verify` evidence, include passed OHOS build or run evidence, include
interaction readiness evidence from a passed `fluoh drive --json`, a backed
`flutter test integration_test -d <device>` command row, or
`manual-assisted` tool-readable evidence, include an `Automation Coverage`
section with the complete required automation gate set whose rows are all
ready/covered/passed/notApplicable, and include passed interaction evidence or
an explicit `No interaction required: <reason>`.
Add `--require-ohos-run` when CI or an AI handoff must prove a passed OHOS run
rather than build-only evidence.

`fluoh package release` runs the same validation and verification, then
completes the fluoh package release by creating release tags at HEAD and
optionally pushing them with `--push`. Existing tags are accepted only when they
already point at HEAD. It does not publish to pub.dev.

`fluoh package status` reads Package `fluoh.yaml` and reports release readiness
without mutating the repository. It checks the current branch, clean working
tree, package status, release notes, license warnings, package tests, Flutter
example presence, example OHOS platform, example tests, and tracked files that
contain the local fluoh home path. For federated app-facing plugins with
existing `default_package` declarations but no OHOS platform, it also reports a
readiness blocker for the missing `<package>_ohos` implementation package,
`ohos.default_package`, and dependency route. If `ohos.default_package` is
already declared, status also verifies that the app-facing package depends on
that default package and that the implementation package exists and declares
OHOS. Use `--package <name>` to validate the requested package name against the
current branch, and `--json` for machine-readable output.

## State Ownership

| State | Owner / Maintenance Entry |
| --- | --- |
| `$FLUOH_HOME/config.json` | `source add`, `source remove`, `source update`, first default Source initialization |
| `$FLUOH_HOME/sources/<name>` | `source add`, `source update` |
| `$FLUOH_HOME/sources.lock.json` | Source runtime in `lib/src/source/`; rebuilt after Source mutations, first default Source initialization, and load-index checks when stale or when selected-SDK installation needs SDK metadata |
| `$FLUOH_HOME/sdks/<version>` | `sdk install`, `sdk remove`, on-demand Flutter wrappers |
| `$FLUOH_HOME/cache/` | Cleanable runtime artifacts such as OHOS debug signing material and package run logs |
| Project `.fluoh/run-sessions/` | `drive` and `run --session-file` Flutter run session evidence |
| Project or package `.fluoh/reports/` | `report create` and AI handoff report artifacts |
| Project `fluoh.yaml` | `create`, `sdk use`, `deps check`, `deps fix`, `deps upgrade` |
| Project `pubspec.yaml` | `deps fix`, `deps upgrade` |
| FlutterOH adaptation repository `fluoh.yaml` | `package create`, `package add`, `package sync`, `package status`, `package handoff`, `package version`, `package check`, `package release` validation |
| Package generated docs | `package create`, `package add`, `package docs refresh` |
| Source root and Manifest files | `source init`, `source sync` |
| `.fluoh/flutter_sdk` | `create`, `sdk use`, `package create` SDK setup |
| Package examples | `package create`, `package add`, `deps get`, `verify`, `package check`, `package release` |
