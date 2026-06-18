# Command Design

[简体中文](commands.zh-CN.md)

This document describes the full `fluoh` command surface and the design
boundaries behind each command. It complements [schema.md](schema.md): schema
docs define the data shapes, while this document defines how commands read,
write, and preserve that data.

Command implementations live mostly under `lib/src/<domain>/commands/`, with
top-level wiring in `lib/src/cli/fluoh_command_runner.dart`.

## End-to-End Workflows

AI-driven support is the primary end-to-end path. The bundled
`skills/fluoh` workflow classifies the workspace, confirms the resolved scope,
then runs `fluoh` commands. This document defines those command contracts;
detailed agent routing, report wording, and repair ordering live in
`skills/fluoh/SKILL.md` and `skills/fluoh/references/`.

### AI-Driven Support

Start by installing or refreshing the skill in the agent:

```text
Run `fluoh skill --path`, install the printed path as the fluoh skill, and
overwrite any existing installation. Use
https://github.com/FlutterOH/fluoh/tree/main/skills/fluoh only when fluoh is
not installed yet.
```

Then give the agent the goal in one short request:

```text
Use $fluoh to install fluoh if needed and add FlutterOH support to this Flutter project.
Use $fluoh to port <upstream-git-url> for FlutterOH, SDK 3.35.
Use $fluoh to continue implementing FlutterOH support for <package-name>.
Use $fluoh to precheck this FlutterOH Source change.
```

When the CLI is missing, the skill handles installation. Agents can inspect the
bundled local skill path, helper scripts, and report templates with:

```text
Run `fluoh skill --path`, install the printed path as a skill, then reload skills if needed.
```

Agents use read-only preflight to present the final scope for user approval and
collect context before applying changes. Release, push, force-push, destructive
Git operations, and external publishing remain separate maintainer decisions.
The skill version follows the CLI package version; after `fluoh upgrade`,
reinstall or reload the path printed by `fluoh skill --path`.

### Add FlutterOH Support to an App Project Manually

Use this sequence from an existing Flutter project when the goal is to build or
run the app with the FlutterOH SDK on the `ohos` platform without an AI agent:

```sh
fluoh task start --type appSupport --scope <scope> --json
fluoh source update
fluoh sdk use 3.35 --pub-get
fluoh deps check --json
fluoh deps fix --dry-run --json
fluoh deps fix
fluoh deps get
fluoh doctor --platform ohos --project --json --strict
fluoh build ohos --auto-sign --json --trace
fluoh devices --platform ohos --json
fluoh emulators --platform ohos --json
fluoh run ohos --auto-emulator --json --trace
fluoh run ohos --device-id <id> --json --trace
fluoh drive ohos --json --trace
fluoh report create --scope <scope> --json
python3 <skill-dir>/scripts/check_report.py <report-path>
```

`fluoh task start` creates the current task workspace for traces, screenshots,
run sessions, and reports. `fluoh sdk use` creates `ohos/` by default when the
project does not already have one. Use `--no-init-ohos` only when another
workflow owns platform creation. If no device or emulator is available, use
`fluoh build ohos --auto-sign --json` as build-only evidence and follow the
JSON diagnostic `nextCommand` for the next local setup step.

## Command Surface

Root help keeps CLI utility commands under `Fluoh`
(`skill`, `doctor`, `flutter`, and `upgrade`), then lists
`SDK & Metadata` before project workflows because SDK and Source state often
gate support. `Project` contains top-level app project commands: `create`
and `deps`. `Package` contains the `package` repository command group.
`Workflow` contains shared execution and evidence commands in the order `plan`,
`verify`, `build`, `run`, `attach`, `drive`, `report`, and `clean`. `Devices`
contains target inventory and launch helpers: `devices` owns connected target
discovery, and `emulators` owns emulator or simulator launch.

| Command | Implementation | Purpose |
| --- | --- | --- |
| `fluoh --version` | `lib/src/cli/fluoh_command_runner.dart` | Print the `fluoh` version, Dart version, platform, and repository URL. |
| `fluoh help [command]` | `package:args` command runner | Print global or command-specific usage. |
| `fluoh skill` | `lib/src/cli/skill_command.dart` | Print local path, version, update, and prompt details for the bundled AI skill. |
| `fluoh create [--sdk <version-or-series>] <args>` | `lib/src/project/create_command.dart` | Create or refresh an app/module Flutter project skeleton with a FlutterOH SDK and pass remaining arguments to `flutter create`. |
| `fluoh plan app` | `lib/src/workflow/commands/plan_command.dart` | Inspect the current Flutter app and print a read-only FlutterOH support command queue. |
| `fluoh plan package` | `lib/src/workflow/commands/plan_command.dart` | Inspect the current package branch and print a read-only support command queue. |
| `fluoh flutter <args>` | `lib/src/sdk/flutter_command.dart` | Run `flutter` from the SDK selected by the nearest project `fluoh.yaml`. |
| `fluohf <args>` | `bin/fluohf.dart` | Shortcut for `fluoh flutter <args>`. |
| `fluoh source` | `lib/src/source/source_commands.dart` | Command group for package metadata source use and maintenance. |
| `fluoh source list` | `lib/src/source/source_commands.dart` | List FlutterOH package metadata Sources enabled on this machine. |
| `fluoh source stats [--sdk <version-or-line>]` | `lib/src/source/source_commands.dart` | Summarize package coverage by FlutterOH SDK version or line. |
| `fluoh source enable <name> <url-or-path>` | `lib/src/source/source_commands.dart` | Enable a local or Git Source for this machine. |
| `fluoh source disable <name>` | `lib/src/source/source_commands.dart` | Disable a non-official package metadata Source for this machine. |
| `fluoh source update [name]` | `lib/src/source/source_commands.dart` | Refresh local snapshots for configured Sources. |
| `fluoh source init <path>` | `lib/src/source/source_commands.dart` | Create a local source repository template. |
| `fluoh source register <package-repo>` | `lib/src/source/source_commands.dart` | Add the first released FlutterOH package branch to a Source repository. |
| `fluoh source sync [path]` | `lib/src/source/source_commands.dart` | Import later releases for packages already routed by a Source repository. |
| `fluoh source check [source]` | `lib/src/source/source_check_command.dart` | Validate Source files and verify declared Package releases. Use `--schema-only` for local YAML/index validation. |
| `fluoh sdk` | `lib/src/sdk/sdk_commands.dart` | Command group for local FlutterOH SDK caches. |
| `fluoh sdk list` | `lib/src/sdk/sdk_commands.dart` | List remote SDK versions and installed SDK caches. |
| `fluoh sdk install <version-or-series>` | `lib/src/sdk/sdk_commands.dart` | Install an SDK version into `$FLUOH_HOME/sdks`. |
| `fluoh sdk current` | `lib/src/sdk/sdk_commands.dart` | Print the SDK selected for the current project. |
| `fluoh sdk remove <version-or-series>` | `lib/src/sdk/sdk_commands.dart` | Remove an installed SDK cache. |
| `fluoh sdk use <version-or-series>` | `lib/src/sdk/sdk_use_command.dart` | Select an SDK for the current Flutter project. |
| `fluoh deps` | `lib/src/deps/commands/deps_command.dart` | Command group for project dependencies. |
| `fluoh deps get` | `lib/src/deps/commands/deps_get_command.dart` | Run `flutter pub get` for projects and package examples. |
| `fluoh deps check` | `lib/src/deps/commands/dependency_plan_commands.dart` | Report dependency FlutterOH support status. |
| `fluoh deps fix` | `lib/src/deps/commands/dependency_plan_commands.dart` | Apply recommended FlutterOH dependency changes. |
| `fluoh deps upgrade` | `lib/src/deps/commands/deps_upgrade_command.dart` | Upgrade existing FlutterOH dependency replacements only. |
| `fluoh package` | `lib/src/package/commands/package_command.dart` | Command group for FlutterOH package repositories. |
| `fluoh package list` | `lib/src/package/commands/package_list_command.dart` | List FlutterOH packages from configured sources. |
| `fluoh package new <name>` | `lib/src/package/commands/package_new_command.dart` | Create a spec-first FlutterOH package repository on an SDK-line branch. |
| `fluoh package port <upstream>` | `lib/src/package/commands/package_port_command.dart` | Port an upstream Flutter package to a FlutterOH package repository on an SDK-line branch. |
| `fluoh package discover <upstream>` | `lib/src/package/commands/package_discover_command.dart` | Discover Flutter plugin packages that may need FlutterOH support. |
| `fluoh package add <package-path>` | `lib/src/package/commands/package_add_command.dart` | Create another package branch in an existing FlutterOH package repository. |
| `fluoh package queue <package-path>...` | `lib/src/package/commands/package_queue_command.dart` | Resolve a read-only multi-package support queue for a monorepo. |
| `fluoh package upstream check` | `lib/src/package/commands/package_upstream_command.dart` | Check the selected upstream package release for a ported package branch. |
| `fluoh package upstream sync` | `lib/src/package/commands/package_upstream_command.dart` | Merge the selected upstream package release into the current FlutterOH package branch. |
| `fluoh package scope` | `lib/src/package/commands/package_scope_command.dart` | Maintain the package support scope used for support planning and evidence gates. |
| `fluoh package next` | `lib/src/package/commands/package_next_command.dart` | Report the next package implementation action. |
| `fluoh package status` | `lib/src/package/commands/package_status_command.dart` | Summarize package release readiness. |
| `fluoh package handoff` | `lib/src/package/commands/package_handoff_command.dart` | Summarize package branch state, evidence, and next commands for AI handoff. |
| `fluoh package version` | `lib/src/package/commands/package_version_command.dart` | Update package release version metadata. |
| `fluoh package check` | `lib/src/package/commands/package_release_command.dart` | Run release checks without creating tags. |
| `fluoh package release` | `lib/src/package/commands/package_release_command.dart` | Complete a FlutterOH package release. |
| `fluoh verify` | `lib/src/workflow/commands/verify_command.dart` | Run pub get, analysis, and tests for a project or package repository. |
| `fluoh build <platform>` | `lib/src/workflow/commands/build_command.dart` | Build a project or package example. |
| `fluoh run <platform>` | `lib/src/workflow/commands/run_command.dart` | Prepare the platform, launch with `flutter run`, and diagnose an app. |
| `fluoh attach <platform>` | `lib/src/workflow/commands/attach_command.dart` | Attach Flutter debug tooling to a `flutterRunSession`, VM Service URI, or device id. |
| `fluoh drive <platform>` | `lib/src/workflow/commands/drive_command.dart` | Run mobile app automation scenarios and evidence checks on OHOS, Android, and iOS targets. |
| `fluoh report create` | `lib/src/workflow/commands/report_command.dart` | Create an ignored local AI support report from trace manifests and automation JSON. |
| `fluoh task` | `lib/src/task/task_command.dart` | Manage project-local task workspaces under `.fluoh/tasks/`. |
| `fluoh clean` | `lib/src/workflow/commands/clean_command.dart` | Remove cleanable output from the current task workspace. |
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
  Workflow commands such as `verify`, `build`, `run`, and `drive` also include
  a top-level `nextAction` when they fail. It gives automation one recovery
  command to run next, or marks the failure as blocked. Detailed target and step
  diagnostics remain under `targets`.
  Automation should invoke the installed `fluoh` executable, not
  `dart run bin/fluoh.dart ... --json`, because the Dart launcher can print
  dependency-resolution text before the command process starts. For strict
  machine parsing, prefer the native/Homebrew executable. Dart pub global shims
  invoke `dart pub global run`; use them for JSON automation only after
  confirming stdout starts with the JSON object in that environment.
  When using a compiled current-repo executable from outside the checkout, set
  `FLUOH_SKILL_PATH` to the checkout's `skills/fluoh` directory so `skill`
  metadata and bundled report helper scripts resolve without falling back to a
  pub global shim.
- `fluoh task start` creates `.fluoh/tasks/<task-id>/` and updates
  `.fluoh/current-task.json`. Task directories are local, ignored, and
  cleanable. They group traces, reports, command output, screenshots, logs,
  run sessions, and scratch files by support task instead of by artifact type.
- `verify`, `build`, `run`, and `drive` can write local AI diagnostic trace
  manifests with `--trace` or `--trace-dir <path>`. With `--trace`, the command
  uses the current task or creates one, then writes under
  `.fluoh/tasks/<task-id>/traces/`. With `--trace-dir <path>`, the manifest is
  exactly `<path>/trace.json` for explicit debugging. Trace data is local
  evidence, not verbose stdout. With `--json`, the JSON object includes a
  `trace` reference with task metadata, trace id, directory, and `trace.json`
  path. If trace writing fails, the workflow result and exit code still reflect
  the underlying command, and the JSON object includes `traceError`.
- Local AI reports are ignored evidence under the current task's
  `reports/` directory. `fluoh report create` defaults to
  `.fluoh/tasks/<task-id>/reports/report.md`; the helper `new_report.py` and
  summary helper also write under the current task.
- Command classes should own argument parsing and user-visible output. Reusable
  behavior belongs in domain helpers such as `lib/src/sdk/`, `lib/src/deps/`,
  `lib/src/package/`, and `lib/src/source/`.
- Mutating commands must validate early, preserve unrelated files, and report
  what changed or what the user should do next.

## Command Groups

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
structured command queue for dependency checks, target-platform build/run evidence,
OHOS device/emulator discovery, existing-platform build/run regression checks,
mobile existing-platform automation evidence, and report creation. The queue
starts a local task, and later `build`, `run`, `drive`, and `report create`
commands use that current task for trace and report output. `--json` writes a single machine-readable object
with `changed: false` and `applied: false`, so AI agents can use it for scope
confirmation before requesting mutating commands. The JSON also includes
`automationRunbook` and `deliveryGate` for the repair loop, terminal states,
final check commands, report check command, and conditions that must be met
before an AI agent can claim `ready`. Ready requires reviewing existing tests
and `integration_test/` coverage before final verification, adding or repairing
missing functional tests, collecting functional evidence for OHOS, collecting
platform-policy build/run regression evidence for every existing platform
directory supported by the current host/toolchain, and collecting Android/iOS
drive dry-run plus drive-run evidence when those existing mobile examples are
supported by the host. Unsupported platforms require exact diagnostic evidence
and a recorded skip reason.
The bundled skill preflight uses this plan output as the primary command queue
when the installed `fluoh` executable is available, and falls back to its local
classifier only when CLI setup is not ready.

`plan package` does the same read-only planning for the current
FlutterOH package branch. It reads package `fluoh.yaml`, reports branch and
working-tree state, selected SDK, upstream/release metadata, example platform
directories, and a command queue whose implementation-loop entry is
`fluoh package next --package <name> --json`. Package implementation work is
not expanded into a second linear verify/build/run/drive queue here; `package
next` owns spec review, support scope planning, OHOS and existing-platform
commands, visual page-readiness, report creation, and report-check sequencing
through `nextAction`. The plan queue then keeps only release-readiness summary,
handoff, and `package check --report <report-path>` steps after `package next`
is ready. The delivery gate still lists concrete final check commands,
including `package next`, selected-SDK verification, platform evidence,
`check_report.py`, handoff, and `package check`, so report certification
failures cannot be reduced to non-blocking warnings.

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
data when the check has it. `--json --strict` also includes `state` and a
single `nextAction`: `ready` when all strict checks pass, or `blocked` with
warning check details and a rerun command when local environment or project
repair is required.

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
`fluoh skill --path` and reinstall or reload the printed skill path in the
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

`fluoh source stats [--sdk <version-or-line>]` reads the merged Source SDK and
package indexes and summarizes how many package records are compatible,
experimental, or broken for each FlutterOH SDK version or line. It does not
change config, snapshots, lock files, or Source repository content. `--json`
prints the same package counts plus package names grouped by status.

`fluoh source enable <name> <url-or-path>` makes a local or Git Source available on
the current machine. It validates the source name, refuses to replace the
official source name, and stores a cache path under
`$FLUOH_HOME/sources/<name>`. Local paths are normalized to absolute `file:`
URLs in `$FLUOH_HOME/config.json` so future `source update` runs can refresh the
cache from the original directory. Local paths and `file:` URLs are copied as
validated snapshots. HTTPS/SSH URLs are cloned immediately and validated before
the config entry is saved. `--priority` defaults to `10`, and higher priorities
win when source data overlaps. `--json` prints the enabled source name, original
input, normalized URL, cache path, and priority as one machine-readable object.
After the new snapshot is valid, the Source runtime commits the config entry and
regenerated lock together.

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

`fluoh source disable <name>` disables a user Source on the current machine.
The official Source alias `flutteroh` is tool-owned with priority `0`. The
command owns only the disabled config entry. Lock maintenance is delegated to
the Source runtime. `--json` prints the disabled source name and disablement
status as one machine-readable object.

`fluoh source update [name]` refreshes all sources or one named source. Selected
Git sources are cloned again, and selected `file:` sources are copied again from
their configured local directories. The Source runtime then validates every
configured source snapshot because the lock is a merged index over all
configured sources. Git transport failures are reported as sync failures with
retry guidance, while cloned source content that fails schema validation keeps
the source validation diagnostic. `--json` prints the refreshed source count and
source entries as one machine-readable object.

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
support records, not in-progress repository state. When `<path>` is one of
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

`fluoh deps fix` applies recommended FlutterOH support changes from the
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

### Support Workflow

Support is maintained by package branch and FlutterOH SDK line, not SDK
patch version. For example, complete SDK `3.35.8-ohos-0.0.3` maps to SDK line
`3.35`, and package `camera` is maintained on `ohos/3.35/camera`.

Recommended flow:

1. Select a complete SDK version.
2. Derive the SDK line from that SDK version.
3. Create or switch to `ohos/<sdkLine>/<package>` for every FlutterOH package,
   whether the package is spec-first or ported from upstream.
4. Record the package origin in Package `fluoh.yaml`: `created` packages come
   from a local spec, and `ported` packages come from an upstream repository.
   Ported packages also record the currently targeted upstream version/ref and
   commit.
5. Before implementation changes, replace the generated
   `doc/fluoh/<package>/spec.md` TODOs with the reviewed package contract:
   requirements, public API, target platform matrix, platform behavior,
   platform API mapping, examples, test expectations, and acceptance evidence.
   `fluoh package next` treats
   remaining generated spec TODOs and package spec template placeholders as a
   `spec-review` blocker. Agents can use
   `skills/fluoh/references/package-spec-template.md` as the fill-in
   structure.
6. Before implementation changes, initialize and complete the P0 support scope
   with `fluoh package scope init` and `fluoh package scope check`. The support
   scope lives under `doc/fluoh/<package>/scope.yaml` and records a
   scope-entry-by-platform matrix: support decisions, platform sources or
   reasons, implementation plans where required, test cases, and functional or
   regression evidence.
7. Before implementation changes, run verifications with the selected SDK, including
   `fluoh deps get`, `fluoh flutter analyze`, and existing package tests or
   example builds. Fix existing-platform regressions first.
8. Use `status: experimental` while support is in progress. Omit `status`
   when the release is complete and recommended; omitted means `compatible`.
9. `fluoh package version` updates the package support release version and
   status.
10. `fluoh package check` runs the final local gate without creating tags.
11. `fluoh package release` creates the release tag, freezing the code, tests, and
   Package `fluoh.yaml`.
12. Use `fluoh source register` for the first released package branch in a
    Source repository. Later releases are imported with `fluoh source sync`.

`fluoh create` is Flutter-like and project-scoped. It creates or refreshes app
and module skeletons with the selected FlutterOH SDK by forwarding arguments to
`flutter create`, then writes project SDK metadata. It can be used in an
existing app with `fluoh create . --platforms=ohos`, but it does not create
FlutterOH package lifecycle metadata, package branches, release tags, or Source
records.

`fluoh package new <name>` creates a spec-first FlutterOH package repository.
It initializes a `main` branch with a fixed repository-index `README.md`
metadata commit, then creates a package branch such as
`ohos/3.35/my_plugin`, configures the FlutterOH SDK, runs the requested Flutter
package/plugin template, writes `fluoh.yaml` with `origin.kind: created`,
creates `doc/fluoh/<package>/spec.md`, writes generated `FLUOH.md` package
context, and stages generated package-branch files. `--platforms` accepts a
comma-separated list of fluoh workflow platforms: `ohos`, `android`, `ios`,
`macos`, `linux`, `web`, and `windows`. New packages still use the same SDK-line
branch and release rules as ported packages so the Source can resolve different
implementations for different FlutterOH SDK lines. The command does not publish
to pub.dev, push, or create release tags.

`fluoh package port <upstream>` clones the upstream repository, selects one
package, creates a FlutterOH branch such as `ohos/3.35/camera`, configures the
SDK and remotes, writes `fluoh.yaml` with `origin.kind: ported`, records
upstream version/ref/commit metadata, writes generated `FLUOH.md` package
context, creates `doc/fluoh/<package>/spec.md`, and stages generated files. If
the selected package has an existing Flutter example, the command adds OHOS
platform files and example SDK config. It never commits.
With no `--package-path`, only the repository root package is selected. For
monorepos, keep one support repository per upstream repository and add more
ported package branches with `fluoh package add <package-path>`. `package port`
and `package add` select the latest valid upstream release tag by default; use
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
federated implementation recommendations, plus the selected package
`supportProfile` so AI agents can seed official documentation review,
tests, scenarios, evidence, and external-service blocker checks during scope
confirmation.

`fluoh package discover <upstream> --json` shallow-clones the upstream
repository into a temporary directory, scans non-example `pubspec.yaml` files,
and reports Flutter plugin packages whose `flutter.plugin.platforms` do not
declare `ohos`. It is read-only and does not create a package repository,
configure remotes, checkout branches, or write project files. JSON output
includes the filter, inspected pubspec count, valid Flutter plugin count,
candidate and recommended counts, candidate package names, paths, versions,
declared platforms, federated `default_package` declarations, missing
platforms, per-candidate `supportProfile` capability categories,
complexity, risk reasons, required evidence, suggested coverage seeds,
`officialDocsRequired`, `officialDocTopics`, and `portCommand`, federated
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
running `package port`. Pass
`--include-existing-platform` to include Flutter plugins that already declare
the requested `--missing-platform`, which defaults to `ohos`.

`fluoh package queue <package-path>... --json` resolves a read-only
multi-package queue in an existing FlutterOH package repository. It fetches
upstream refs, keeps the current branch checked out, reports each package name,
path, selected upstream target, target `ohos/<sdkLine>/<package>` branch,
whether that branch already exists, SDK/Dart compatibility warnings, and the
next `fluoh package add` or `package status` command. Use it before porting
multiple packages in one upstream monorepo, then finish one package branch
checkpoint before moving to the next. When running verify/build/run/check
commands across multiple existing package branches, prefer a fresh clone or
separate Git worktree per package branch so ignored platform build artifacts
from one branch cannot become untracked files on the next branch. Do not run
destructive cleanup commands such as `git clean` without explicit maintainer
approval.

`fluoh package scope init --package <name>` creates
`doc/fluoh/<package>/scope.yaml`. The file is a support-scope record, not an
automated verdict: agents and maintainers fill it after reading the public Dart
API, target platform behavior, existing platform implementations, examples,
tests, and platform API sources. By default, init imports concrete rows from
the branch-local spec's `Support Scope Seeds` table; pass `--no-from-spec` when
that table is stale or intentionally empty.
`fluoh package scope check --json` validates that P0 platform rows have support
decisions, platform sources or reasons, implementation plan status where
implementation is required, test cases, and functional or regression evidence.
It exits non-zero while the support scope is incomplete. `fluoh package scope
status --json` prints the same status without failing so handoff scripts can
summarize remaining planning or evidence gaps. All package scope JSON outputs
use `supportScope` for the parsed status object.

`fluoh package add <package-path>` creates another package branch in an existing
FlutterOH package repository. It requires a clean working tree, resolves the
target package on the synchronized upstream branch, checks out the selected
release target commit, creates `ohos/<sdkLine>/<package>`, writes a
single-package `fluoh.yaml` and `FLUOH.md` context, prepares an existing
Flutter example when present, creates `doc/fluoh/<package>/spec.md`, and stages
generated files. It supports
`--upstream-version` and `--upstream-ref` with the same selection rules as
package port, plus `--org` to override the inferred example organization
passed to `flutter create`.
`--plan --json` resolves the add plan without checking out, writing project
files, or requiring a clean working tree; the plan includes `warnings[]` with
the same keep-latest SDK compatibility policy as package port. If the target
package branch already exists, it points maintainers to the existing branch,
`fluoh package status`, and `fluoh package upstream sync` instead of creating duplicate
 support state. File snapshots protect local state when the command fails.

`package new`, `package port`, and `package add` create
`doc/fluoh/<package>/spec.md` only when it is missing. The spec is branch-local
and human/AI-maintained; it owns package requirements, API design, platform
behavior, OHOS API mapping, examples, and test planning. Generated spec TODOs
and package spec template placeholders are not accepted planning evidence;
`fluoh package next` reports them as a `spec-review` action until they are
replaced with the reviewed package contract. Agents can use
`skills/fluoh/references/package-spec-template.md` as the fill-in structure.
The commands also
rewrite the fluoh-owned `FLUOH.md` package context from the current Package
`fluoh.yaml` plus the selected package pubspec. `FLUOH.md` gives the fluoh
skill a compact package snapshot, links the spec and support scope, lists
workflow entry points, includes optional federated routing, and preserves the
FlutterOH Release History section for the current package branch. Existing
release history is kept when the context file is rewritten; the rest of the
file is regenerated. When the selected package is a federated app-facing plugin
with `default_package` declarations and no OHOS platform, `FLUOH.md` includes
the same `<package>_ohos` implementation route used by package discovery.
Release history TODO entries must be replaced before release.

`fluoh source register <package-repo> --package <name> --source <path> --json`
registers the first released FlutterOH package branch in a Source repository.
It reads the package repository release tags, loads the tagged Package
`fluoh.yaml`, verifies the release with `fluoh package check`, creates or
updates `manifests/<package>/fluoh.yaml`, and adds the route to the Source root
`manifests[]`. It accepts both `origin.kind: created` and
`origin.kind: ported` package manifests. Created packages use release tags such
as `<package>-ohos-<sdkLine>-<release.version>`; ported packages use
`<package>-<upstream.version>-ohos-<sdkLine>-<release.version>`. `source
register` is for the first Source registration of a package; `source sync` owns
later release imports for packages already routed by the Source.

`fluoh package handoff --json` reads the current package branch, Git status,
current task traces, and current task reports, then prints a single JSON object
with package metadata, current branch, manifest branch, branch match state,
dirty-state summary, evidence paths, the task trace directory that follow-up
commands should reuse, and next commands. The next commands include report
validation before `package check`; when a report exists, `check_report.py` and
`package check` both use the latest report path, and the AI workflow must run
the independent reviewer feedback loop before claiming ready. It does not
modify the repository. Use it when an AI task needs to resume, transfer, or
confirm whether the branch is ready for final verify, drive evidence, report
creation, report validation, independent review, or `package check`.

`fluoh package upstream check` and `fluoh package upstream sync` are available
only when `origin.kind: ported`. Created packages have no upstream; use
`fluoh package next` for implementation work and `fluoh source sync` for Source
metadata. `upstream check` fetches upstream and reports whether the current
package branch already targets the selected upstream target.

`fluoh package upstream sync` fetches upstream branches and tags,
fast-forwards the upstream branch recorded in Package `upstream.git.branch`,
resolves the package target from `--upstream-version`, `--upstream-ref`, or the
latest valid release tag, returns to the `repository.git.branch` branch
recorded in `fluoh.yaml`, merges the selected target commit without committing
first, updates upstream metadata in `fluoh.yaml`, ensures
`doc/fluoh/<package>/spec.md` exists, stages the metadata/spec files, and
commits `Sync upstream package` when changes are present. When no valid release
tag exists and no explicit target is passed, it falls back to the synchronized
upstream branch HEAD. If the resolved target already matches the current branch
metadata and commit, `upstream sync` reports that the package branch already
targets that upstream version and exits without a commit. `upstream sync`
refuses explicit package versions older than the current branch upstream
version; mark the current support `broken` with
`fluoh package version --status broken` instead of downgrading the branch.
After sync, `fluoh package next` requires the branch-local spec to reference the
current upstream version and commit before implementation work continues. Merge
conflicts are left for the user to resolve, then
`fluoh package upstream sync --continue` validates staged resolution and
finishes. If the interrupted merge used a custom non-tag ref, pass the same
`--upstream-ref` with `--continue`; release tags can usually be inferred from
`MERGE_HEAD`, but non-tag refs cannot. Continue also verifies that the resolved
working-tree package version matches the selected upstream target before
updating `fluoh.yaml`. `--abort` runs `git merge --abort` for an in-progress
sync. `--json` prints the completed sync action list and commit status. Fetch
failures emit `package.upstream.fetch_failed`; merge conflicts emit
`package.upstream.merge_conflict` with conflicted files and the `--continue`
next command; merge failures that do not leave resolvable conflicts emit
`package.upstream.merge_failed`. JSON diagnostics include trimmed stdout and
stderr tails when Git produced useful output.

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
diagnostics, and `nextCommand`. When a target fails, the top-level `nextAction`
summarizes the recovery command and rerun command for the next repair loop.
Use `--trace` to write a local AI diagnostic trace under the current task's
`traces/` directory, or `--trace-dir <path>` to choose the trace session
directory whose manifest is `<path>/trace.json`. In JSON mode, the command still writes exactly
one object to stdout and includes only a `trace` reference to the local
manifest, or `traceError` when the trace could not be written.
It also reports `dirtyAfterVerify` and `workingTreeChanges` when the target is
inside a Git worktree, so agents can detect generated files or lockfile changes
left by `pub get` before committing. Reuse one `--trace-dir` across an
implementation loop to accumulate command invocations in one session.

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
OHOS hdc calls have a bounded timeout, so device discovery failures return JSON
diagnostics instead of hanging indefinitely. The default hdc command timeout is
10 seconds; set `FLUOH_OHOS_HDC_TIMEOUT_SECONDS` when local debugging or tests
need a shorter timeout.
When `integration_test/` exists and a concrete target is available, `fluoh run`
also runs `flutter test integration_test -d <device>` on that target. Release
reports should record that passed test command row separately because a plain
`fluoh run --json` row is launch evidence.
For OHOS grant-path integration tests, pass
`--ohos-permission-dialog-policy allow` only when automatic allow preserves the
test intent. The default `disabled` policy leaves system permission prompts
under the test or `fluoh drive` scenario so deny/error paths are not masked.
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
Mobile launch success must be followed by at least one screenshot or equivalent
UI-state capture and a page assertion. If the example app is blank, stuck on a
splash screen, visually hidden, or otherwise abnormal, repair the demo before
continuing to broader automation.
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
Package support work must not validate only OHOS. Existing Android, iOS, macOS,
Linux, Web, and Windows package/example platform directories are also required
functional test targets when the current host and toolchain support them;
unsupported targets must be recorded with the diagnostic command and blocker.

Interaction scenarios live under
`doc/fluoh/<package>/scenarios/<platform>-<name>.md` and use
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
`--profile exploratory-smoke` adds a built-in bounded exploration profile that
records session checks, screenshots, a short wait, and an optional generic
scroll gesture. The profile is useful for finding crashes, blank pages, and
obvious launch-smoke regressions, but it is tagged as non-release-gate
exploratory evidence. It does not replace explicit scenario assertions,
`integration_test`, or a documented no-interaction-required reason.

Executable scenarios support `captureScreenshot` and `screenshot` as supporting
observation actions. Android saves `adb exec-out screencap -p`, iOS saves
`xcrun simctl io <target> screenshot`, and OHOS saves a `snapshot_display`
artifact received through `hdc file recv`. The action result records the local
path and byte count. Screenshots are evidence artifacts; functional pass/fail
should still be backed by tool-readable assertions such as `assertText`,
`assertLog`, `assertSession`, or integration-test output.

Runtime permissions require explicit grant, deny, and differing error-path
coverage on each supported platform. Use `notApplicable` only when the behavior
does not exist on that platform; `blocked` rows remain repair backlog and are
not release-ready evidence. iOS automation uses the built-in XCTest runner when
possible. Set `FLUOH_XCODEBUILD` for explicit Xcode selection and
`FLUOH_IOS_PERMISSION_DRIVER` only when a permission driver must be forced.

JSON failures include platform run diagnostics such as `ohos.run_failed`,
`android.run_failed`, `ios.run_failed`, `macos.run_failed`, `linux.run_failed`,
`web.run_failed`, and `windows.run_failed` for current-project runs, while
package examples keep platform-specific device, run, runtime, and
integration-test diagnostics where available. `--trace` and
`--trace-dir <path>` follow the same local AI diagnostic trace contract as
`fluoh verify`.

`fluoh report create` writes a git-ignored canonical Markdown report under the
current task's `reports/` directory unless `--output` is provided. With
`--output`, the exact path is used for the canonical report. It
accepts one or more `--trace-dir` values and saved
`--automation-json` files, extracts command rows, coverage gates, interaction
evidence, diagnostics, and fluoh feedback candidates, then writes the standard
AI report sections needed by package check and handoff workflows. When
`--package <name>` is supplied, it also reads
`doc/fluoh/<package>/scope.yaml` and writes a Support Scope
section plus a `supportScope` JSON summary. Reports also include an
`Official Platform Basis` section and matching delivery checklist item; ready
reports must fill that section with reviewed official platform sources or
an explicit not-applicable reason. `check_report.py` validates that ready
reports with a Support Scope have complete P0 planning and functional
evidence gates. `--json` reports the path as `report`. The command owns only
local report composition and release recommendation; the maintainer still owns
final release approval and any publish, push, tag, store, or registry action.
`check_report.py` and `package check --report` accept both the CLI default
`report.md` and helper-created `report-<timestamp>.md`; other report filenames
are rejected so handoff and release gates can identify generated fluoh reports.

`fluoh clean` removes cleanable output from the current task by default. Use
`--tasks` to remove the whole selected task workspace and `--all` to remove all
task workspaces. It does not remove SDK installations, Source snapshots,
config, lock files, `.fluoh/flutter_sdk`, `fluoh.yaml`, `FLUOH.md`,
`doc/fluoh/`, or Source metadata. Use `--dry-run` to inspect targets without
deleting them and `--json` for machine-readable cleanup reports.

`fluoh package version` updates the release metadata for the current package
in `fluoh.yaml`. Use `--bump patch|minor|major` to increment the FlutterOH
package support version, `--set <version>` to set an exact version, and
`--status experimental|compatible|broken` to set release status. `compatible`
removes the status field because compatible is the default. `--bump` and
`--set` are mutually exclusive. Use `--dry-run` to print the planned change
without writing, and `--json` for machine-readable output.

`fluoh package check` validates release metadata, verifies that the configured
SDK version exists in sources, runs `fluoh verify`, ensures the working tree
remains clean, and reports the release tag that would be created. It never
creates or pushes tags. Use `--package <name>` to validate the requested package
name against the current branch. `--json` prints tags, warnings, certification
state, and verification results. Checks do not require device or AI report
evidence by default; they print a non-blocking warning when no certification
report is provided. Use `--report <path>` to require a completed current-task
report before passing the check.
Certification reports must be `ready`, complete every delivery checklist item,
include passed `fluoh verify` evidence, include target-platform build or run
evidence, and include interaction readiness evidence. That interaction evidence
must come from a passed `fluoh drive --json`, a
`flutter test integration_test -d <device>` command row with supporting
evidence, or `manual-assisted` tool-readable evidence. Reports must also
include an `Automation Coverage` section with the complete required gate set;
every gate row must be ready/covered/passed/notApplicable. Finally, the report
must include passed interaction evidence or an explicit
`No interaction required: <reason>`.
Add `--require-ohos-run` when CI or an AI handoff must prove a passed OHOS run
rather than build-only evidence.

`fluoh package release` runs the same validation and verification, then
completes the fluoh package release by creating release tags at HEAD and
optionally pushing them with `--push`. Existing tags are accepted only when they
already point at HEAD. It does not publish to pub.dev.

`fluoh package next` reads the current Package repository and reports exactly
one implementation-stage action. It intentionally ignores release-only blockers
such as release capabilities, compatible status, and tracked local paths until the
implementation loop has produced evidence and a report. It first checks the
branch-local spec: missing specs, generated TODO placeholders, package spec
template placeholders, or ported specs that do not reference the current
upstream version/commit produce a `spec-review` edit action. It then checks the
package support scope under
`doc/fluoh/<package>/scope.yaml`: a missing scope produces a
`scope` action, incomplete P0 research/plan/test entries produce an edit
action, and missing P0 functional evidence blocks report creation after the
execution phases pass. A report alone is not enough for `ready`; the command
also requires passed trace evidence for
verify, target-platform build/run, automation dry-run, automation run, and each
existing example platform discovered under the selected package
example, using that platform policy's build/run regression command. Android and
host-supported iOS examples also require existing-platform drive dry-run and
drive-run evidence. With
`--json`, `ok` means the next action was computed successfully; use top-level
`state` and `nextAction.type` to decide whether to run a command, make a
focused edit, stop as blocked, or hand off to release readiness checks. The
latest report is validated by the bundled `check_report.py` before
`nextAction.type` can become `ready`; report failures are returned as a
`report-check` edit action with the checker errors in `nextAction.details`.
When `nextAction.type` is `ready`, `nextAction.nextCommands` lists the
release-readiness commands to run next, including status, handoff, and package
check with the validated report path.
The default automation-run action uses plain `fluoh drive ohos --json` so scenario
or integration-test evidence can satisfy the interaction gate. The optional
`--profile exploratory-smoke` command remains available as bounded diagnostic
evidence, but it does not satisfy functional automation. The JSON object also
includes `evidenceSummary`, `remainingRisks`, and
`failureStreak`. It also includes `scope`, a support-scope status
summary, and `qualityProfile`, a read-only scan of
available functional verification surfaces such as `integration_test` files,
`doc/fluoh/<package>/scenarios/` scenario documents, and existing example
platform directories such as Android, iOS, macOS, Linux, Web, or Windows.
Missing functional surfaces are reported as a non-blocking
`quality.functional_surface_missing` risk so the implementation loop can
distinguish launch-smoke evidence from stronger functional evidence. If the
same traced command fails three times in a row,
`nextAction.type` becomes `blocked` so automation stops instead of repeatedly
editing around the same unresolved failure.
If no current task exists, `package next` creates one so trace,
visual-readiness, and report evidence share a single local task context. It
does not mutate package source files merely to compute `nextAction`.

`fluoh package status` reads Package `fluoh.yaml` and reports release readiness
without mutating the repository. It checks the current branch, clean working
tree, package status, target-platform run evidence, functional interaction evidence,
visual page-readiness after mobile runs, release capabilities, license warnings,
package tests, Flutter example presence, example OHOS platform, example tests,
and tracked files that contain the local fluoh home path. These evidence checks
apply even when the package is already marked `compatible`. For federated
app-facing plugins with
existing `default_package` declarations but no OHOS platform, it also reports a
readiness blocker for the missing `<package>_ohos` implementation package,
`ohos.default_package`, and dependency route. If `ohos.default_package` is
already declared, status also verifies that the app-facing package depends on
that default package and that the implementation package exists and declares
OHOS. Use `--package <name>` to validate the requested package name against the
current branch. With `--json`, the output includes `state` and one
machine-actionable `nextAction` so agents can run a short loop: apply or run
that single action, then rerun `nextAction.rerunCommand`.

## State Ownership

| State | Owner / Maintenance Entry |
| --- | --- |
| `$FLUOH_HOME/config.json` | Local Source enablement through `source enable`, `source disable`, `source update`, first default Source initialization |
| `$FLUOH_HOME/sources/<name>` | Snapshots created by `source enable`, refreshed by `source update` |
| `$FLUOH_HOME/sources.lock.json` | Source runtime in `lib/src/source/`; rebuilt after Source mutations, first default Source initialization, and load-index checks when stale or when selected-SDK installation needs SDK metadata |
| `$FLUOH_HOME/sdks/<version>` | `sdk install`, `sdk remove`, on-demand Flutter wrappers |
| Project `.fluoh/tasks/<task-id>/` | Task-local traces, reports, evidence, logs, sessions, commands, and scratch artifacts; owned by `task` and `clean` |
| Project `.fluoh/current-task.json` | Current task pointer for workflow trace/report/evidence commands |
| Project `fluoh.yaml` | `create`, `sdk use`, `deps check`, `deps fix`, `deps upgrade` |
| Project `pubspec.yaml` | `deps fix`, `deps upgrade` |
| FlutterOH package repository `fluoh.yaml` | `package new`, `package port`, `package add`, `package upstream sync`, `package status`, `package handoff`, `package version`, `package check`, `package release` validation |
| Package branch-local `doc/fluoh/<package>/spec.md` | Created by `package new`, `package port`, and `package add` when missing; maintained by maintainer/AI and reviewed after `package upstream sync` |
| Package generated `FLUOH.md` context | `package new`, `package port`, `package add` |
| Source root and Manifest files | `source init`, `source register`, `source sync` |
| `.fluoh/flutter_sdk` | `create`, `sdk use`, `package new`, `package port` SDK setup |
| Package examples | `package new`, `package port`, `package add`, `deps get`, `verify`, `package check`, `package release` |
