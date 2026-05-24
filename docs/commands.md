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
| `fluoh clean` | `lib/src/clean/clean_command.dart` | Run `flutter clean` and remove generated `fluoh_test` artifacts. |
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
| `fluoh deps get` | `lib/src/deps/commands/deps_get_command.dart` | Run `flutter pub get` for project and `fluoh_test` workspaces. |
| `fluoh deps check` | `lib/src/deps/commands/deps_dependency_commands.dart` | Report dependency FlutterOH adaptation status. |
| `fluoh deps fix` | `lib/src/deps/commands/deps_dependency_commands.dart` | Apply recommended FlutterOH dependency changes. |
| `fluoh deps upgrade` | `lib/src/deps/commands/deps_upgrade_command.dart` | Upgrade existing FlutterOH dependency replacements only. |
| `fluoh package` | `lib/src/package/commands/package_command.dart` | Command group for FlutterOH package repositories. |
| `fluoh package create <upstream>` | `lib/src/package/commands/package_create_command.dart` | Initialize a FlutterOH package repository. |
| `fluoh package add <package-path>` | `lib/src/package/commands/package_add_command.dart` | Register another package in a FlutterOH package repository. |
| `fluoh package sync` | `lib/src/package/commands/package_sync_command.dart` | Merge upstream into the current OHOS package branch. |
| `fluoh package release` | `lib/src/package/commands/package_release_command.dart` | Validate, test, tag, and optionally push FlutterOH package releases. |
| `fluoh test` | `lib/src/testing/test_commands.dart` | Command group for package verification workspaces. |
| `fluoh test init` | `lib/src/testing/test_commands.dart` | Create a `fluoh_test` verification workspace. |
| `fluoh test run` | `lib/src/testing/test_commands.dart` | Run package tests and `fluoh_test` tests. |
| `fluoh doctor` | `lib/src/doctor/doctor_command.dart` | Diagnose local project, source, SDK, and tool state. |
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
  available when source snapshots need repair. `fluoh flutter`, `fluohf`,
  `fluoh clean`, and `fluoh deps get` may still load the Source index through the
  SDK resolver when the selected SDK is missing and selected-SDK installation
  needs SDK metadata.
- Usage errors and schema format errors return exit code `64`.
- Command classes should own argument parsing and user-visible output. Reusable
  behavior belongs in domain helpers such as `lib/src/sdk/`, `lib/src/deps/`,
  `lib/src/package/`, `lib/src/source/`, and `lib/src/testing/`.
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

### `fluoh clean`

`clean` runs selected-SDK `flutter clean` for each primary package directory.
In FlutterOH package repositories, package directories come from Package
`fluoh.yaml`; otherwise the current working directory is used.

After Flutter cleaning, the command deletes generated `fluoh_test` artifacts
such as `.dart_tool`, `.pub-cache`, `build`, `coverage`, and `local.properties`
from root and package-scoped test workspaces. It checks Git tracked files first
and skips artifact directories that contain tracked content.

### `fluoh doctor`

`doctor` is diagnostic and returns success after printing its findings. It
checks the installation method and latest pub.dev version, configured source
snapshots, Flutter project shape, selected project SDK, and the `ohos`
platform directory. Missing or stale state is reported as warnings rather than
immediate remediation.

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
configured snapshot.

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
`--pub-get` runs `flutter pub get` after the switch.

## Dependency Commands

These commands operate on ordinary FlutterOH projects and preserve unrelated
`pubspec.yaml` content.

`fluoh deps get` forwards to selected-SDK `flutter pub get` and accepts extra
arguments. It runs in all primary package directories and discovered
`fluoh_test` workspaces that contain a `pubspec.yaml`. It intentionally skips
package Source data so dependency resolution remains available even when source
snapshots need repair. If the selected SDK is missing, the SDK resolver loads
the Source index only for the lookup needed to install that SDK.

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
5. Before adding OHOS code, run baseline checks with the selected SDK, including
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
`fluoh.yaml`, `FLUOH.md`,
`FLUOH_CHANGELOG.md`, agent instructions, and package-scoped `fluoh_test`
workspaces, then stages generated files. The generated guidance tells
maintainers to establish a selected-SDK baseline and fix non-OHOS platform
regressions before implementing OHOS code.
With no `--package-path`, the command selects only the upstream repository root
package. If the upstream repository has a root package plus package subprojects,
pass `--package-path .` and repeat `--package-path <subdir>` for each package
that should be registered.
The generated `fluoh.yaml` includes comments beside the `repository`,
`upstream`, package path, `version`, and `status` fields that maintainers
commonly edit before release. It never commits. Options include repeated
`--package-path`, `--output`, `--sdk`, and `--repository`.

`fluoh package add <package-path>` registers another package in an existing
FlutterOH package repository. It requires a clean working tree and the maintenance
branch recorded by Package `repository.git.branch`, validates `<package-path>`,
optionally verifies `--expected-package`, appends Package `fluoh.yaml`, docs,
and package-scoped test workspace state, and stages generated files. File
snapshots and workspace rollback protect local state when the command fails.

`fluoh package sync` fetches upstream, fast-forwards the upstream branch recorded
in Package `upstream.git.branch`, returns to the `repository.git.branch` branch
recorded in `fluoh.yaml`, merges the upstream branch without committing first,
updates upstream metadata in `fluoh.yaml`, stages it, and
commits `Sync upstream packages` when changes are present. Merge conflicts are
left for the user to resolve, then `fluoh package sync --continue` validates staged
resolution and finishes. `--abort` runs `git merge --abort` for an in-progress
sync.

`fluoh package release` validates release metadata, checks that the configured SDK
version exists in sources, runs package and `fluoh_test` verification, ensures the
working tree remains clean, creates release tags at HEAD, and optionally pushes
them. Use `--package <name>` for one package or `--all` for every registered
package. Existing tags are accepted only when they already point at HEAD.

## Test Commands

`fluoh test init` creates `fluoh_test` for a Flutter package. In Package
repositories, it creates package-scoped `fluoh_test/<name>` workspaces; with
multiple registered packages, `--package <name>` selects the package. The
command writes a test package and creates an example app with the selected SDK.
`--force` treats the flag as explicit user confirmation to replace the existing
target `fluoh_test` workspace.

`fluoh test run` locates the package and existing test workspace. If the
package has `test/**/*_test.dart`, it runs package `pub get` and Flutter tests
first. It then runs `pub get` and tests inside `fluoh_test`. Non-Flutter
packages are skipped because there is no FlutterOH platform behavior to
validate.

## State Ownership

| State | Owner / Maintenance Entry |
| --- | --- |
| `$FLUOH_HOME/config.json` | `source add`, `source remove`, `source update`, first default Source bootstrap |
| `$FLUOH_HOME/sources/<name>` | `source add`, `source update` |
| `$FLUOH_HOME/sources.lock.json` | Source runtime in `lib/src/source/`; rebuilt after Source mutations, first default Source bootstrap, and load-index checks when stale or when selected-SDK installation needs SDK metadata |
| `$FLUOH_HOME/sdks/<version>` | `sdk install`, `sdk remove`, on-demand Flutter wrappers |
| Project `fluoh.yaml` | `sdk use`, `deps check`, `deps fix`, `deps upgrade` |
| Project `pubspec.yaml` | `deps fix`, `deps upgrade` |
| FlutterOH adaptation repository `fluoh.yaml` | `package create`, `package add`, `package sync`, `package release` validation |
| Source root and Manifest files | `source init`, `source sync` |
| `.fluoh/flutter_sdk` | `sdk use`, `package create` SDK setup |
| `fluoh_test/` | `test init`, `test run`, `package create`, `package add`, `deps get`, `clean`, `package release` |
