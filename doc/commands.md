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
`skills/fluoh` workflow decides whether the workspace is an app project or a
package adaptation repository, then drives the deterministic `fluoh` commands.
Those commands own the auditable steps: `sdk use` owns SDK selection, the stable
IDE link, and default OHOS platform creation; `deps` owns FlutterOH dependency
replacements; `doctor` owns environment and project diagnostics; and `build` or
`run` owns signing, target selection, launch, logs, and JSON failure routing.

### AI-Driven Adaptation

Start by asking the agent to install the skill:

```text
Install the fluoh skill from https://github.com/FlutterOH/fluoh/tree/main/skills/fluoh.
```

Then hand work to the agent with a short request:

```text
Use $fluoh to install fluoh if needed and adapt this Flutter project for OHOS.
Use $fluoh to adapt <upstream-git-url> for FlutterOH, SDK 3.35.
Use $fluoh to continue adapting <package-name> for OHOS.
```

The skill installs the CLI when `fluoh --version` fails, preferring
`dart pub global activate fluoh` and falling back to Homebrew on macOS when Dart
is not available. If the CLI is already installed, agents can discover the
bundled local skill path and helper script commands with:

```text
Run `fluoh skill --json`, install the returned localPath as a skill, then reload skills if needed.
```

The JSON result also exposes helper script argv for preflight, report creation,
report checking, and functional scenario creation, plus reference template
paths for reports and interaction scenarios.

Before implementation edits, agents must inspect preflight `upgradeChecks`.
Schema blockers stop the flow until `fluoh` is upgraded or metadata is migrated.
Package repositories with missing, legacy, or stale generated docs should run
`fluoh package docs refresh --dry-run`, then `fluoh package docs refresh` when
the worktree is clean and the request is not review-only. If preflight reports
that the docs refresh state is unknown because dry-run failed, run the dry-run
successfully before assuming generated docs are current.

The skill version follows the `fluoh` CLI package version. Updating the CLI with
`fluoh upgrade` updates the bundled skill files; agents that copied the skill
should rerun `fluoh skill --json` and reinstall or reload the returned path.
The agent writes `.fluoh/ai-report-...md` with a delivery checklist before
finishing. Review the diff, the report, and any device-only behavior before
release.

### Add OHOS to an App Project Manually

Use this path from an existing Flutter project when the goal is to make the
project build or run on OHOS without an AI agent:

```sh
fluoh source update
fluoh sdk use 3.35 --pub-get
fluoh deps check
fluoh deps fix --dry-run
fluoh deps fix
fluoh deps get
fluoh doctor -p --platform ohos
fluoh build --platform ohos --auto-sign
fluoh devices --platform ohos
fluoh run --platform ohos --device <id>
```

`fluoh sdk use` creates `ohos/` by default when the project does not already
have one. Use `--no-init-ohos` only when another workflow owns platform
creation. If no device or emulator is available, keep
`fluoh build --platform ohos --auto-sign --json` as build-only evidence and use
the JSON diagnostic `nextCommand` for the next local setup step.

## Command Surface

| Command | Implementation | Purpose |
| --- | --- | --- |
| `fluoh --version` | `lib/src/cli/fluoh_command_runner.dart` | Print the `fluoh` version, Dart version, platform, and repository URL. |
| `fluoh help [command]` | `package:args` command runner | Print global or command-specific usage. |
| `fluoh skill` | `lib/src/cli/skill_command.dart` | Print local path, version, update, and prompt details for the bundled AI skill. |
| `fluoh clean` | `lib/src/clean/clean_command.dart` | Remove cleanable runtime artifacts under `$FLUOH_HOME/cache`. |
| `fluoh flutter <args>` | `lib/src/sdk/flutter_command.dart` | Run `flutter` from the SDK selected by the nearest project `fluoh.yaml`. |
| `fluohf <args>` | `bin/fluohf.dart` | Shortcut for `fluoh flutter <args>`. |
| `fluoh source` | `lib/src/source/source_commands.dart` | Command group for data source use and maintenance. |
| `fluoh source list` | `lib/src/source/source_commands.dart` | List configured FlutterOH data sources. |
| `fluoh source add <name> <url-or-path>` | `lib/src/source/source_commands.dart` | Add a local or Git data source to tool config. |
| `fluoh source remove <name>` | `lib/src/source/source_commands.dart` | Remove a non-official data source from tool config. |
| `fluoh source update [name]` | `lib/src/source/source_commands.dart` | Refresh and validate configured source snapshots. |
| `fluoh source init <path>` | `lib/src/source/source_commands.dart` | Create a local source repository template. |
| `fluoh source sync [path]` | `lib/src/source/source_commands.dart` | Import released FlutterOH package repository metadata into a source repository. |
| `fluoh source check [source]` | `lib/src/source/source_check_command.dart` | Validate Source files and verify declared Package releases. Use `--schema-only` for local YAML/index validation. |
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
| `fluoh package list` | `lib/src/package/commands/package_list_command.dart` | List FlutterOH packages from configured sources. |
| `fluoh package create <upstream>` | `lib/src/package/commands/package_create_command.dart` | Initialize a FlutterOH package repository. |
| `fluoh package add <package-path>` | `lib/src/package/commands/package_add_command.dart` | Register another package in a FlutterOH package repository. |
| `fluoh package sync` | `lib/src/package/commands/package_sync_command.dart` | Merge upstream into the current OHOS package branch. |
| `fluoh package status` | `lib/src/package/commands/package_status_command.dart` | Summarize package release readiness. |
| `fluoh package version` | `lib/src/package/commands/package_version_command.dart` | Update package release version metadata. |
| `fluoh package docs refresh` | `lib/src/package/commands/package_docs_command.dart` | Refresh generated package repository documentation. |
| `fluoh package check` | `lib/src/package/commands/package_release_command.dart` | Run release checks without creating tags. |
| `fluoh package release` | `lib/src/package/commands/package_release_command.dart` | Complete a FlutterOH package release. |
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
  load-index API. That API initializes the first default Source configuration and
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
  `error` remain at the top level. Automation should invoke the installed
  `fluoh` executable, not `dart run bin/fluoh.dart ... --json`, because the Dart
  launcher can print dependency-resolution text before the command process
  starts. For strict machine parsing, prefer the native/Homebrew executable.
  Dart pub global shims invoke `dart pub global run`; use them for JSON
  automation only after confirming the command stdout starts with the JSON
  object in that environment.
- Command classes should own argument parsing and user-visible output. Reusable
  behavior belongs in domain helpers such as `lib/src/sdk/`, `lib/src/deps/`,
  `lib/src/package/`, and `lib/src/source/`.
- Mutating commands must validate early, preserve unrelated files, and report
  what changed or what the user should do next.

## Top-Level Commands

### `fluoh clean`

`clean` removes only `$FLUOH_HOME/cache`, which contains cleanable runtime
artifacts such as OHOS debug signing material and package run logs. It does not
remove SDK installations, Source snapshots, config, lock files, or project
`.fluoh/` reports. Use `--dry-run` to inspect the cache without deleting it and
`--json` for machine-readable cleanup reports.

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
`--strict` is used. Bare `fluoh doctor` checks the fluoh installation, Git and
Dart, configured source snapshots, OpenHarmony SDK tooling, Android SDK and
Java tooling, Apple Xcode tooling, and currently connected OHOS, Android, iOS,
and macOS devices. Plain output streams each check as soon as it completes, so
long device discovery does not make the command appear idle. JSON mode waits
for all checks and writes one machine-readable object.

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
`--platform ohos|android|ios|macos` to narrow native toolchain and project
platform checks.

Missing or stale state is reported as warnings rather than immediate
remediation. Use `fluoh doctor --json --strict` when automation needs a native
toolchain gate, and `fluoh doctor -p --json --strict` when it also needs
a current-project gate. Project JSON includes `platformDirectories` data for
the selected platform set so automation can decide whether to create or skip
OHOS, Android, or iOS platform projects. `--json` prints the same checks as
machine-readable JSON and includes each check's `id`, `group`, and structured
data when the check has it.

### `fluoh devices` and `fluoh emulators`

`fluoh devices` lists connected OHOS, Android, iOS, and macOS targets. It
accepts `--platform all|ohos|android|ios|macos` and `--json`. Plain output uses
Flutter-style `Name • id • platform • details` rows and prints platform
warnings after discovered targets.

`fluoh emulators` lists local OHOS, Android, iOS simulator, and macOS emulator
targets with `Id • Name • Manufacturer • Platform` rows. It accepts the same
`--platform` and `--json` options. `--launch <id-or-name>` starts a local
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
command checks the Source root schema, `environment.fluoh`, SDK metadata,
Manifest routes, Manifest names, duplicate packages, package release records,
and whether the package index can be built. It does not read Git diffs, fetch
SDK tags, clone package repositories, or verify declared releases; release
metadata updates remain the job of `fluoh source sync`. `--schema-only` is a
local Source check mode, so it cannot be combined with diff, release, work-root,
or Package verification options.

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
and aggregates historical release records into Manifest files. When `path` is
omitted, the current directory is used. Source metadata must come from released
adaptation records, not in-progress repository state. When `<path>` is one of
the configured source snapshots under `$FLUOH_HOME/sources/<name>`, sync is
treated as a configured Source snapshot mutation and the Source runtime rebuilds
the merged lock. When `<path>` is a maintainer checkout outside the configured
snapshots, the local lock is not changed; run `fluoh source update <name>` after
publishing or copying the Source into a configured snapshot. Use
`--manifest <name>` or `--package <name>` to target sync discovery, and
`--concurrency <n>` to bound parallel tag discovery for large Sources. `--json`
prints synced and skipped package records plus a `plan` with `knownTags`,
`discoveredTags`, `tagsToSync`, and per-route status. Release tags are treated
as immutable records derived from release metadata; moving an existing tag is not
auto-synced and should be handled by publishing a new release tag or by manual
maintenance.

`fluoh source check [source]` is a read-only verification command for Source
maintainers and CI. When `source` is omitted, the current directory is checked.
`source` may be a local Source checkout path or a GitHub pull request URL. The
command validates Source files, detects changed Manifest routes, then verifies
declared Package release references. Release verification clones referenced
FlutterOH package repositories, checks declared release tags, reads the Package
manifest branch at each tag, and runs
`fluoh package check --package <name> --json` at the tagged commits. It does not
import Package metadata or write Source files; use `fluoh source sync` for that.
The JSON output includes `recommendation`, `changeType`, `affectedManifests`,
`changedReleaseRecords`, `releaseCheckPlan`, `skippedReleaseChecks`,
`sdkChecks`, `changedFiles`, `errors`, `warnings`, and the supporting
checkout/check details. By default the command checks Manifest files changed
from `--base-ref`. When only the Source root `fluoh.yaml` changed, it compares
Manifest route names between the base ref and HEAD, checks only added or removed
routes, checks added SDK tags with `git ls-remote --tags`, and does not expand
SDK-only root metadata changes to every Manifest. For changed Manifest files it
compares release records against the base ref and verifies only added or
modified release records, package additions, SDK-line additions, repository
changes, or repository/upstream package path changes. PR diff checks validate the
Source root plus only the affected Manifest routes; explicit full audits,
diff-fallback checks, and push/manual `--skip-release-checks` checks validate
all Manifest routes. Advisory-only, maintenance-only, and deleted release
records do not clone Package repositories. If the target is not a Git worktree
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
lockfile. `--json` prints the same plan as machine-readable JSON.

`fluoh deps fix` applies recommended FlutterOH adaptation changes from the
dependency plan. It writes to either `dependency_overrides` or direct dependency
declarations according to `dependencyPolicy.pubspecSection`. Version mismatches
are skipped unless `dependencyPolicy.versionChanges` is `any`. `--dry-run` or
`-n` prints the plan without modifying `pubspec.yaml`. `--json` prints the same
plan as machine-readable JSON with change summaries, applied count, and dry-run
flag. Before writing, it validates the generated YAML and restores the original
`pubspec.yaml` if validation or writing fails.

`fluoh deps upgrade` is narrower than `deps fix`: it upgrades existing FlutterOH
dependency replacements and does not add new replacements. It uses the same
version-change policy and dry-run behavior. `--json` prints the dependency plan,
change summaries, applied count, and dry-run flag without human progress text.

## Package Repository Commands

`fluoh package list` is a source-consuming query command. It lists package names
advertised by configured sources, along with compatible SDK lines and source
aliases. It reads through the Source runtime, so it initializes or refreshes the
Source lock when needed. `--json` prints the same list as machine-readable JSON.

The remaining commands maintain FlutterOH package repositories. They assume Git
repositories and are intentionally strict about branch and working tree state.

The AI implementation loop for these commands is intentionally kept in
`skills/fluoh/SKILL.md`, so user documentation stays short and every agent uses
one maintained workflow.

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
7. `fluoh package version` updates the adaptation package release version and
   status.
8. `fluoh package check` runs the final local gate without creating tags.
9. `fluoh package release` creates the release tag, freezing the code, tests, and
   Package `fluoh.yaml`.
10. `fluoh source sync` aggregates Source Manifests from release tags.

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

`fluoh package docs refresh` regenerates the fluoh-owned sections of
`FLUOH.md` and `AGENTS.md` from the current Package `fluoh.yaml`. Generated
sections are identified by `fluoh:generated` markers that include a stable
section id and template version, so future template upgrades can replace only
the owned section while preserving hand-written content. Existing non-empty
`FLUOH_CHANGELOG.md` content is not rewritten; when the changelog is missing or
empty, the command creates initial release headings from current package
metadata. `--dry-run` reports files that would change without requiring a clean
working tree. Writing requires the recorded package branch and a clean working
tree, does not stage files, and does not change `fluoh.yaml`. `--json` reports
`changed`, `applied`, `files`, and `dryRun`.

`fluoh package sync` fetches upstream, fast-forwards the upstream branch recorded
in Package `upstream.git.branch`, returns to the `repository.git.branch` branch
recorded in `fluoh.yaml`, merges the upstream branch without committing first,
updates upstream metadata in `fluoh.yaml`, stages it, and
commits `Sync upstream packages` when changes are present. Merge conflicts are
left for the user to resolve, then `fluoh package sync --continue` validates staged
resolution and finishes. `--abort` runs `git merge --abort` for an in-progress
sync. `--json` prints the completed sync action list and commit status. Fetch
failures emit `sync.fetch_failed`; merge conflicts emit `sync.merge_conflict`
with conflicted files and the `--continue` next command; merge failures that do
not leave resolvable conflicts emit `sync.merge_failed`. JSON diagnostics
include trimmed stdout and stderr tails when Git produced useful output.

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
`flutter run`, captures smoke output under `$FLUOH_HOME/cache/package-runs`, and runs
`flutter test integration_test -d <device>` when the example has an
`integration_test/` directory. When `flutter run` prints a VM Service or debug
service URI, `--json` includes it as `details.vmServiceUri` on the run step so
an AI agent or external tool can attach. Pass `--session-file <path>` on
Android, iOS, or macOS runs to write a live `flutterRunSession` JSON file while
the app is still running; the file is updated with process id, target,
`vmServiceUri`, launch status, final status, and output log path. AI agents can
inspect that file with
`python3 <skill-dir>/scripts/inspect_session.py <session-file> --wait 30 --expect-platform <platform>`
to wait for launch, find the VM Service URI, and decide whether to attach,
inspect logs, or route a failure. Use
`--device <id>` for an already connected target or `--emulator <name>` to
select and start a local emulator or simulator where the platform provides one.
Android, iOS, and macOS current-project runs use the same Flutter device
discovery, platform filtering, run-smoke timeout, and saved output log path as
package examples, but they do not run package example integration tests.
Run-smoke success is only launch evidence. Package workflows that require UI
taps, permission prompts, files, camera, location, media playback, deep links,
or external apps need functional scenario evidence from `integration_test/`
where the platform runner supports it, or from AI-assisted interaction on the
emulator or device. Store scenario notes under `.fluoh/scenarios/<package>-<platform>-<name>.md`
when the flow is not already encoded as `integration_test`; the AI driver
follows that scenario, operates the target with available device or UI tools,
and records step results in `.fluoh/ai-report-...md`. OHOS `fluoh run`
currently builds, signs, installs, launches, and captures hilog, but it does
not automatically traverse example pages or press buttons; record the exercised
functional path, expected result, actual result, device id, Flutter debug or VM
service output when available, widget/component tree state, semantics or
accessibility output, text/log evidence, and optional screenshots. AI-assisted
verification must not depend on image recognition or knowing what the UI looks
like; scenarios should expose component state, visible status text, semantic
labels, stable test keys, command JSON, hilog, or app log markers that a
non-vision agent can read. For most packages the example app is only an
interactive harness for exercising APIs and platform behavior; the acceptance
criteria should be functional results rather than visual layout.
Use the bundled `skills/fluoh/references/interaction-scenario-template.md`
shape for AI-assisted scenario files. Cover whichever classes apply:
permission grant and denial, file or media picker, camera or microphone
capture, location and sensors, maps, media playback or recording, deep links
and external app callbacks, background or lifecycle behavior, multi-step forms,
and negative/error paths. If none apply, the report must say
`No interaction required: <reason>` instead of leaving the section empty.
JSON failures include platform run diagnostics such as `ohos.run_failed`,
`android.run_failed`, `ios.run_failed`, and `macos.run_failed` for
current-project runs, while package examples keep their more specific install,
launch, runtime, and integration-test diagnostics where available.

`fluoh package version` updates the release metadata for a registered package
in `fluoh.yaml`. Use `--bump patch|minor|major` to increment the FlutterOH
adaptation package version, `--set <version>` to set an exact version, and
`--status experimental|compatible|broken` to set release status. `compatible`
removes the status field because compatible is the default. `--bump` and
`--set` are mutually exclusive. Use `--dry-run` to print the planned change
without writing, and `--json` for machine-readable output.

`fluoh package check` validates release metadata, verifies that the configured
SDK version exists in sources, runs `fluoh verify`, ensures the working tree
remains clean, and reports the release tag that would be created. It never
creates or pushes tags. Use `--package <name>` for one package or `--all` for
every registered package. `--json` prints tags, warnings, certification state,
and verification results. Checks do not require device or AI report evidence by
default; they print a non-blocking warning when no certification report is
provided. Use `--report <path>` or `--certification-report <path>` to require a
completed `.fluoh/ai-report-...md` before passing the check. Certification
reports must be `ready`, complete every delivery checklist item, include passed
`fluoh verify` evidence, include passed OHOS build or run evidence, and include
passed interaction evidence or an explicit `No interaction required: <reason>`.
Add `--require-ohos-run` when CI or an AI handoff must prove a passed real OHOS
run rather than build-only evidence.

`fluoh package release` runs the same validation and verification, then
completes the fluoh package release by creating release tags at HEAD and
optionally pushing them with `--push`. Existing tags are accepted only when they
already point at HEAD. It does not publish to pub.dev.

`fluoh package status` reads Package `fluoh.yaml` and reports release readiness
without mutating the repository. It checks the current branch, clean working
tree, package status, release notes, license warnings, package tests, Flutter
example presence, example OHOS platform, example tests, and tracked files that
contain the local fluoh home path. Use `--package <name>` for one package,
`--all` for every package, and `--json` for machine-readable output.

## State Ownership

| State | Owner / Maintenance Entry |
| --- | --- |
| `$FLUOH_HOME/config.json` | `source add`, `source remove`, `source update`, first default Source initialization |
| `$FLUOH_HOME/sources/<name>` | `source add`, `source update` |
| `$FLUOH_HOME/sources.lock.json` | Source runtime in `lib/src/source/`; rebuilt after Source mutations, first default Source initialization, and load-index checks when stale or when selected-SDK installation needs SDK metadata |
| `$FLUOH_HOME/sdks/<version>` | `sdk install`, `sdk remove`, on-demand Flutter wrappers |
| `$FLUOH_HOME/cache/` | Cleanable runtime artifacts such as OHOS debug signing material and package run logs |
| Project `fluoh.yaml` | `sdk use`, `deps check`, `deps fix`, `deps upgrade` |
| Project `pubspec.yaml` | `deps fix`, `deps upgrade` |
| FlutterOH adaptation repository `fluoh.yaml` | `package create`, `package add`, `package sync`, `package status`, `package version`, `package check`, `package release` validation |
| Package generated docs | `package create`, `package add`, `package docs refresh` |
| Source root and Manifest files | `source init`, `source sync` |
| `.fluoh/flutter_sdk` | `sdk use`, `package create` SDK setup |
| Package examples | `package create`, `package add`, `deps get`, `verify`, `package check`, `package release` |
