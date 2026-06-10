# Schema Design

[简体中文](schema.zh-CN.md)

This document describes the canonical YAML and JSON data shapes used by
`fluoh`. Schema parsing and rendering live under `lib/src/schema/`; Source
loading and cache validation live under `lib/src/source/`.

## Schema Version

Every YAML schema uses `schema: 1`. Commands validate only the current
canonical shape.

`kind` is required in all `fluoh.yaml` files:

| Kind | Owner | Purpose |
| --- | --- | --- |
| `project` | Flutter project | Selected SDK and dependency rewrite policy. |
| `package` | FlutterOH package adaptation repository | Current adaptation branch metadata. |
| `source` | Source root | Source metadata, SDK index, and Manifest routes. |
| `manifest` | Source package Manifest | Released package adaptation records. |

State owners:

| Owner | Purpose |
| --- | --- |
| Project | A local Flutter project selected by the user. |
| Package | A FlutterOH package adaptation repository and branch. |
| Source | A published or local Source such as `FlutterOH/source`. |
| Manifest | A per-package file routed from a Source root. |

## Shared Rules

- Complete Flutter OHOS SDK versions must match
  `<major>.<minor>.<patch>-ohos-...`. SDK lines are derived from the first two
  numeric components, for example `3.35.8-ohos-1.0.1 -> 3.35`.
- Source root `name` values are non-empty tokens without whitespace. Source
  Manifest route names and `package.name` values are Dart package names.
- Package paths are normalized relative paths using `/`, with non-empty path
  segments and no parent-directory traversal.
- `package.path: .` is the default and can be omitted in canonical output.
- Upstream versions and FlutterOH release versions follow pub semver.
- `upstream.commit` is a full 40-character hexadecimal Git commit hash.
- Release status values are `compatible`, `experimental`, and `broken`.
  `compatible` is the default and is omitted in canonical output.
- Consumer commands use only `compatible` releases by default.

## Project `fluoh.yaml`

```yaml
schema: 1
kind: project

sdk:
  version: 3.35.8-ohos-1.0.1

dependencyPolicy:
  pubspecSection: dependency_overrides
  versionChanges: compatible
```

Rules:

- `sdk.version` is required and must exist in the merged Source SDK index.
- `dependencyPolicy` is required.
- `dependencyPolicy.pubspecSection` is `dependency_overrides` or
  `dependencies`.
- `dependencyPolicy.versionChanges` is `compatible` or `any`.
- Dependency release status visibility is command-scoped, not persisted in
  project schema. `deps check`, `deps fix`, and `deps upgrade` default to
  compatible Source releases and can include non-compatible releases with
  `--all-release-statuses`.

## Package `fluoh.yaml`

Package `fluoh.yaml` describes one package adaptation branch. Source Manifests
own release history, imported from canonical package release tags.

```yaml
schema: 1
kind: package

sdk:
  version: 3.35.8-ohos-1.0.1

repository:
  git:
    url: https://github.com/FlutterOH/camera.git
    branch: ohos/3.35/camera

upstream:
  git:
    url: https://github.com/flutter/packages.git
    branch: main

package:
  name: camera
  path: packages/camera/camera
  release:
    version: 0.2.0
    upstream:
      version: 0.20.0
      ref: camera-v0.20.0
      commit: "0123456789abcdef0123456789abcdef01234567"
    status: experimental
```

Rules:

- `kind` must be `package`.
- `sdk.version` is required and must exist in the merged Source SDK index for
  commands that consume SDK data.
- `repository.git.url` and `repository.git.branch` are required.
- `repository.git.branch` must use
  `ohos/<sdkLine>/<package.name>`, for example `ohos/3.35/camera`.
- `upstream.git.url` and `upstream.git.branch` are required.
- `package.name` is required.
- `package.path` is the path in both the adaptation repository and upstream
  repository.
- `package.release.version` is required and follows pub semver.
- `package.release.upstream.version` and `package.release.upstream.commit` are
  required. `package.release.upstream.ref` is optional.
- `package.release.status` is optional. Omitted or `compatible` means the
  branch is ready for normal consumption; use `experimental` or `broken` only
  for non-default states.

Canonical package release tags use this fixed format:

```text
<package>-<upstream.version>-ohos-<sdkLine>-<release.version>
```

For example:

```text
camera-0.11.0-ohos-3.35-1.0.1
```

`fluoh source sync` uses this fixed tag format.
When the Source root declares `sdk.versions`, sync imports only package release
tags whose SDK line is represented by those SDK versions. Tags for newer SDK
lines are skipped until the Source root adds the matching SDK version.

## Source Root `fluoh.yaml`

Source root `fluoh.yaml` describes the Source itself, optional SDK data, and
routes to per-package Manifests.

```yaml
schema: 1
kind: source
name: flutteroh
description: Flutter OHOS SDK and package adaptation source.

repository:
  git:
    url: https://github.com/FlutterOH/source.git

sdk:
  git:
    url: https://gitcode.com/CPF-Flutter/flutter_flutter.git
  versions:
    - 3.35.8-ohos-0.0.2
    - 3.35.8-ohos-0.0.3
    - 3.35.8-ohos-1.0.1

manifests:
  - name: camera
  - name: webview
```

Rules:

- `kind` must be `source`.
- `name` is required and must be a non-empty token without whitespace.
- `description` is optional Source self-description.
- `repository.git.url` is optional Source self-description.
- `sdk` and `manifests` are both optional and may be empty while a Source is
  being prepared.
- If `sdk` is present, `sdk.git.url` is required.
- `sdk.versions` lists complete installable SDK versions in ascending semantic
  version order. It may be omitted while the Source is being prepared; canonical
  output writes `versions: []` for an empty SDK index.
- `sdk.versions[]` entries are unique.
- `manifests[].name` is required, unique, and maps to
  `manifests/<name>/fluoh.yaml`. Canonical output sorts routes by name.

## Source Manifest `fluoh.yaml`

A Source Manifest describes exactly one package. It contains release records by
SDK line. `fluoh source sync` imports these records from canonical package
release tags; maintainers may add advisory and maintenance metadata.

```yaml
schema: 1
kind: manifest

repository:
  git:
    url: https://github.com/FlutterOH/camera.git

upstream:
  git:
    url: https://github.com/flutter/packages.git

package:
  name: camera
  path: packages/camera/camera
  maintenance:
    frozen: true
    note: Upstream now supports OHOS natively.
  advisory:
    message: Prefer upstream camera when OHOS native support is available.
    alternatives:
      - name: camera_ohos
        reason: Provides native OHOS support.
        url: https://pub.dev/packages/camera_ohos
  sdks:
    "3.35":
      releases:
        - version: 0.1.0
          upstream:
            version: 0.11.0
            ref: camera-v0.11.0
            commit: "0123456789abcdef0123456789abcdef01234567"
        - version: 0.2.0
          upstream:
            version: 0.20.0
            ref: camera-v0.20.0
            commit: "0123456789abcdef0123456789abcdef01234567"
          status: experimental
```

Rules:

- The route name is owned by the Source root `manifests[].name`, and it must
  match `package.name`.
- `kind` must be `manifest`.
- `repository.git.url` and `upstream.git.url` are required.
- Source Manifest repository and upstream blocks contain Git URLs; branch and
  path are owned by Package metadata and release tags.
- `package` is required and describes exactly one package.
- `package.path` is the path in both repositories and defaults to `.`.
- One Source Manifest has one `package.path` for all release records. `source
  sync` skips release tags whose Package metadata declares a different path.
- `package.maintenance.frozen` is optional and defaults to `false`.
- `package.maintenance.note` is optional.
- `package.advisory` is optional user guidance. Machine release status remains
  owned by `releases[].status`.
- `package.advisory.message` is optional. `package.advisory.alternatives[]` is
  optional; each alternative requires `name` and may include `reason` and `url`.
- `package.sdks` is required and contains at least one SDK line.
- `package.sdks.<sdkLine>.releases[]` is the release history for that SDK line
  and contains at least one release record.
- Each Package SDK line must exist in the merged Source SDK index used by the
  consuming command.
- Release records for the same SDK line use unique `upstream.version` and
  `version` pairs.
- Release tags are derived from the fixed package release tag rule.
- `releases[].version` and `releases[].upstream.version` are required.
- `releases[].upstream.ref` is optional.
- `releases[].upstream.commit` is required.
- `releases[].status` is optional. Omitted means `compatible`.
- Canonical output sorts SDK lines ascending. Releases within a line are sorted
  oldest first by upstream version and release version, so new releases are
  appended after older records.

## Generated Markdown Sections

Generated `FLUOH.md` and `AGENTS.md` package repository guidance is versioned
separately from YAML schema. Generated sections are delimited by Markdown
comments:

```text
<!-- fluoh:generated:start id=<section> template=<templateVersion> -->
...
<!-- fluoh:generated:end id=<section> -->
```

Only matching generated sections are tool-owned. Hand-written content around
them is user-owned and must be preserved.

## Source Cache And Lock Files

Tool configuration and merged Source state are JSON files, not `fluoh.yaml`
schemas.

- `config.json` records configured Source aliases, paths, URLs, and priorities.
- `sources.lock.json` records the merged Source snapshot used by project
  commands.
- Lock entries include `"fingerprint"` data so `fluoh` can detect Source
  changes.
- Lock entries include `"packageRoutes"` so dependency commands can find
  `manifests/<name>/fluoh.yaml` data without scanning every Source.
- Package records expose machine fields such as `upstreamVersion` after Source
  data is merged.

## `config.json`

Tool config stays JSON because it is machine-owned runtime state:

```json
{
  "sources": {
    "flutteroh": {
      "url": "https://github.com/FlutterOH/source.git",
      "path": "/home/user/.fluoh/sources/flutteroh",
      "priority": 0
    },
    "local": {
      "url": "file:///Users/user/local/source",
      "path": "/home/user/.fluoh/sources/local",
      "priority": 10
    }
  }
}
```

Rules:

- The official Source alias is `flutteroh`, with default priority `0`.
- User-added Sources default to priority `10`. Higher values win.
- Source aliases use letters, numbers, `_`, `.`, or `-`; `.` and `..` are
  reserved.
- `url` supports HTTPS URLs, SSH URLs, and `file:` URLs. `fluoh source add`
  normalizes user-provided local paths to absolute `file:` URLs.
- HTTPS/SSH URLs use Git clone/update. `file:` URLs are copied into validated
  Source snapshots.
- `path` is the local cache path.
- Source caches store only the latest validated snapshot. Git history and
  unrelated repository files are not kept.

## `sources.lock.json`

`$FLUOH_HOME/sources.lock.json` is a machine-generated, local-only resolved SDK
lock manifest plus a compact package routing index. It is derived from
`config.json` and every validated Source snapshot so commands can read stable
JSON instead of reparsing Source YAML every time. Full package entries are not
stored in the lock; package commands use the routing index to find relevant
Manifest files, then read package metadata from the configured Source snapshots
on demand.

Example shape:

```json
{
  "fingerprint": {
    "toolVersion": "0.1.0",
    "sources": [
      {
        "name": "flutteroh",
        "path": "/home/user/.fluoh/sources/flutteroh",
        "url": "https://github.com/FlutterOH/source.git",
        "priority": 0,
        "snapshotHash": "hash64:..."
      },
      {
        "name": "local",
        "path": "/home/user/.fluoh/sources/local",
        "url": "file:///Users/user/local/source",
        "priority": 10,
        "snapshotHash": "hash64:..."
      }
    ]
  },
  "sdk": {
    "sources": {
      "flutteroh": {
        "git": {
          "url": "https://gitcode.com/CPF-Flutter/flutter_flutter.git"
        }
      }
    },
    "versions": {
      "3.35.8-ohos-0.0.2": {
        "source": "flutteroh"
      },
      "3.35.8-ohos-0.0.3": {
        "source": "flutteroh"
      },
      "3.35.8-ohos-1.0.1": {
        "source": "flutteroh"
      }
    }
  },
  "packageRoutes": {
    "flutteroh": {
      "camera": ["3.35"],
      "path_provider": ["3.35"]
    },
    "local": {
      "camera": ["3.35"]
    }
  }
}
```

Rules:

- The lock is disposable generated state without a `schema` field; missing or
  stale locks are rebuilt.
- Source root and Manifest YAML remain the only human-edited Source data.
- Source lock maintenance is owned by the Source runtime in `lib/src/source/`;
  command classes access it through that runtime.
- The lock is regenerated from scratch by the Source runtime whenever
  `config.json`, any configured Source snapshot, SDK merge rules, or the
  `fluoh` tool version changes.
- Each configured Source snapshot contains a generated
  `.fluoh-source-state.json` with the snapshot hash. Normal lock freshness
  checks read that state file instead of recursively hashing the snapshot on
  every command. If the state file is missing, the runtime recalculates the
  snapshot hash and writes a fresh state file.
- Source mutation entrypoints, including `fluoh source add`,
  `fluoh source remove`, `fluoh source update`, configured snapshot repairs,
  configured-snapshot `fluoh source sync`, and first default Source
  initialization, ask the Source runtime to rebuild the lock. Source-consuming
  flows use the same load-index API, which regenerates the lock on demand when
  it is missing or stale, or when selected-SDK installation needs SDK metadata.
- The lock stores SDK repositories once in `sdk.sources`, keyed by Source alias.
  Each resolved SDK release stores the winning Source alias in `sdk.versions`.
  Fields that can be derived from object keys, defaults, or `fingerprint.sources`
  are omitted: source priority is stored only in `fingerprint.sources`, SDK
  `versionSeries` and `flutterVersion` derive from the SDK version key, SDK
  `tag` defaults to the version key, and SDK `channel` defaults to `stable`.
- The lock writes `sdk.versions` in ascending semantic version order.
- The `packageRoutes` index contains Source/package routing and the compatible
  SDK lines seen for each package at that route. Full package metadata remains
  in Source Manifest files.
- Generated lock files use compact-pretty JSON: root sections and large objects
  stay multiline, while short leaf objects and arrays are emitted on one line.
- SDK commands read the SDK lock. Package commands use the package routing
  index to parse only Manifest files that can contain the current project
  packages, then apply package priority and conflict rules in memory.
- Lock generation applies SDK priority and conflict rules documented for Source
  commands. Package priority and conflict rules run when package metadata is
  loaded for dependency workflows.
- Writes use a temporary file plus atomic replacement. A lock is considered fresh
  only when its recorded fingerprint matches the current Source state.
