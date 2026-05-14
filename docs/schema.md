# Schema Design

[简体中文](schema.zh-CN.md)

This document describes the YAML and JSON configuration shapes used by `fluoh`.
Parsing and rendering logic lives under `lib/src/schema/`; Source loading and
cache validation logic lives under `lib/src/source/`.

## `fluoh.yaml`

`fluoh.yaml` can appear in multiple directories. Commands select the matching
schema from the execution context, not from the filename alone.

| Owner | Purpose |
| --- | --- |
| Project | Records the selected SDK and dependency rewrite policy for the current project. |
| Package | Records the current maintenance state of a FlutterOH package adaptation repository. |
| Source | Records Source metadata, installable SDK versions, and Manifest routing. |
| Manifest | Records released FlutterOH package adaptation records consumable by projects. |

### Project

Project config stays small:

```yaml
schema: 1

sdk:
  version: 3.35.8-ohos-0.0.3

dependencyPolicy:
  pubspecSection: dependency_overrides
  versionChanges: compatible
```

Rules:

- `schema` is required and currently must be `1`.
- Project config does not use `kind`; commands parse this schema in a project
  context.
- `sdk.version` is the complete Flutter OHOS SDK version selected for the
  current project.
- `dependencyPolicy.pubspecSection` is the pubspec section written by
  `fluoh pub fix`; supported values are `dependency_overrides` and
  `dependencies`, defaulting to `dependency_overrides`.
- `dependencyPolicy.versionChanges` controls the allowed upstream package
  version changes. `compatible` allows exact matches and pub-semver compatible
  upgrades; `any` also allows incompatible changes and downgrades.
- `fluoh_test/` does not own a separate `fluoh.yaml`. Test workspaces search
  upward for the nearest `fluoh.yaml`, usually the project root or Package
  repository root config.

### Package

Package `fluoh.yaml` records the current workflow state of a FlutterOH package
adaptation repository. It is not a history index: it only describes the version
relationship currently maintained or prepared on the branch. Release tags freeze
historical release records, and `fluoh source sync` aggregates those records
into Source Manifests.

Non-monorepo example:

```yaml
schema: 1
name: webview

sdk:
  version: 3.35.8-ohos-0.0.3

repository:
  git:
    url: https://github.com/FlutterOH/webview.git
    branch: ohos/3.35

upstream:
  git:
    url: https://github.com/example/webview.git
    branch: main

packages:
  webview:
    version: "0.2.0"
    upstreamVersion: "0.11.0"
```

Monorepo example:

```yaml
schema: 1
name: flutter_packages

sdk:
  version: 3.35.8-ohos-0.0.3

repository:
  git:
    url: https://github.com/FlutterOH/packages.git
    branch: ohos/3.35

upstream:
  git:
    url: https://github.com/flutter/packages.git
    branch: main

packages:
  path_provider:
    repository:
      path: packages/path_provider/path_provider
    upstream:
      path: packages/path_provider/path_provider
    version: "0.2.0"
    upstreamVersion: "2.1.5"

  camera:
    repository:
      path: packages/camera/camera
    upstream:
      path: packages/camera/camera
    version: "0.1.0"
    upstreamVersion: "0.11.0"
    status: experimental
```

Rules:

- `schema` is required and currently must be `1`.
- Package config does not use `kind`; commands parse this schema in
  `fluoh pub ...` context.
- `name` is required. It is the logical name of the adaptation repository or
  workspace, not the Dart package name. Single-package repositories usually use
  the package name; monorepos use a stable workspace alias such as
  `flutter_packages`.
- `sdk.version` is required. It is the complete Flutter OHOS SDK version used to
  adapt, test, and release the current package.
- `repository.git.url` is required and is the FlutterOH adaptation repository
  URL or local path.
- `repository.git.branch` is required and is the maintenance branch. Adaptation
  branches are created by Flutter OHOS SDK line, using `ohos/<sdkLine>`. For
  example, SDK `3.35.8-ohos-0.0.3` maps to `ohos/3.35`.
- `repository.git.path` is optional and provides the default path for all
  packages inside the adaptation repository, defaulting to `.`.
- `upstream.git.url` is required and is the original upstream repository URL or
  local path.
- `upstream.git.branch` is optional and is the branch used by `fluoh pub sync`
  when pulling upstream changes, defaulting to `main`.
- `upstream.git.path` is optional and provides the default path for all packages
  inside the upstream repository, defaulting to `.`.
- `packages.<name>.repository.path` is optional and overrides
  `repository.git.path`.
- `packages.<name>.upstream.path` is optional and overrides
  `upstream.git.path`.
- `packages.<name>.version` is required and is the FlutterOH adaptation release
  version. It uses numeric dot-separated parts such as `1` or `0.1.0` and has
  no `v` prefix.
- `packages.<name>.upstreamVersion` is required and is the upstream package
  version adapted by the current package.
- `packages.<name>.status` is optional. Omitted means `compatible`; write
  `experimental` or `broken` only for in-progress or known-bad adaptations.

### Source

Source root `fluoh.yaml` describes the Source itself, available SDK origin, and
Manifest file routing. It does not contain package names, package paths, package
versions, upstream versions, advisories, or maintenance state.

Layout:

```text
fluoh.yaml
manifests/
  flutter_packages/fluoh.yaml
  webview/fluoh.yaml
```

Root file example:

```yaml
schema: 1
kind: source
name: flutteroh
description: Flutter OHOS SDK and package adaptation source.

repository:
  git:
    url: https://github.com/FlutterOH/pub.git

environment:
  fluoh: ">=0.1.0"

sdk:
  git:
    url: https://gitcode.com/openharmony-tpc/flutter_flutter.git
  versions:
    - 3.35.8-ohos-0.0.3
    - 3.35.8-ohos-0.0.2

manifests:
  - name: flutter_packages
  - name: webview
```

Rules:

- `schema` is required and currently must be `1`.
- `kind` is required and must be `source`.
- `name` is required. It is Source self-description and does not need to match
  the local Source alias in `config.json`.
- `description` is optional.
- `repository.git.url` is required and can be an HTTPS URL, SSH URL, `file:`
  URL, or local path.
- `environment.fluoh` is optional and defines the minimum `fluoh` version.
- `sdk` and `manifests` are both optional. A Source can be an empty scaffold
  with neither SDK versions nor Manifest routes; it is valid but contributes no
  data during merge.
- Sources that provide an SDK install index must include `sdk.git.url`.
  `sdk.versions` may be empty while maintainers are preparing a Source.
- `sdk.versions` records complete installable stable SDK versions.
- `manifests` is optional. When present, it may be an empty list while
  maintainers are preparing a Source.
- `manifests[].name` is required and unique. It maps to
  `manifests/<name>/fluoh.yaml`.
- Package names are derived from the `packages` keys in Manifest files during
  Source validation. A package name must not appear in more than one Manifest.

### Manifest

Manifest files record released FlutterOH package adaptation records consumable
by projects. `fluoh source sync` can aggregate them from Package release tags,
and maintainers can manually add `advisory` and `maintenance`.

Non-monorepo example:

```yaml
schema: 1
kind: manifest
name: webview

repository:
  git:
    url: https://github.com/FlutterOH/webview.git

upstream:
  git:
    url: https://github.com/example/webview.git
    branch: main

packages:
  webview:
    sdks:
      "3.35":
        releases:
          - version: "0.2.0"
            upstreamVersion: "0.11.0"
```

Monorepo example:

```yaml
schema: 1
kind: manifest
name: flutter_packages

repository:
  git:
    url: https://github.com/FlutterOH/packages.git

upstream:
  git:
    url: https://github.com/flutter/packages.git
    branch: main

packages:
  path_provider:
    repository:
      path: packages/path_provider/path_provider
    upstream:
      path: packages/path_provider/path_provider

    maintenance:
      status: frozen
      reason: Upstream now supports OHOS natively.

    advisory:
      message: Prefer upstream path_provider for new projects.
      alternatives:
        - name: path_provider_ohos
          reason: Provides native OHOS support.
          url: https://pub.dev/packages/path_provider_ohos

    sdks:
      "3.35":
        releases:
          - version: "0.1.0"
            upstreamVersion: "2.1.5"
          - version: "0.2.0"
            upstreamVersion: "2.1.5"
            status: experimental

  camera:
    repository:
      path: packages/camera/camera
    upstream:
      path: packages/camera/camera
    sdks:
      "3.35":
        releases:
          - version: "0.2.0"
            upstreamVersion: "0.11.0"
```

Rules:

- `schema` is required and currently must be `1`.
- `kind` is required and must be `manifest`.
- `name` is required and must match the Source root `manifests[].name`.
- `repository.git.url` is required and is the FlutterOH adaptation repository
  URL or local path.
- `repository.git.path` is optional and provides the default path for all
  packages inside the adaptation repository, defaulting to `.`.
- `upstream.git.url` is required and is the original upstream repository URL or
  local path.
- `upstream.git.branch` is optional and defaults to `main`; `fluoh source sync`
  copies it from Package `upstream.git.branch`.
- `upstream.git.path` is optional and provides the default path for all packages
  inside the upstream repository, defaulting to `.`.
- `packages.<name>.repository.path` is optional and overrides
  `repository.git.path`.
- `packages.<name>.upstream.path` is optional and overrides
  `upstream.git.path`.
- `maintenance.status` is optional and defaults to `active`; supported values
  are `active` and `frozen`. `frozen` affects Source maintenance commands only;
  consumer commands can still use existing release records.
- `advisory` is optional package-level user guidance for `fluoh pub check`. It
  does not change machine status.
- `sdks.<sdkLine>` uses the derived Flutter OHOS SDK line, for example `3.35`.
  Consumer commands derive it from the complete project SDK version before
  reading Manifest data.
- `releases` is the historical release record list for the current SDK line.
- `releases[].version` is required and is the FlutterOH adaptation release
  version. It uses numeric dot-separated parts such as `1` or `0.1.0` and has
  no `v` prefix.
- `releases[].upstreamVersion` is required and is the corresponding upstream
  package version.
- `releases[].status` is optional. Omitted means `compatible`; write
  `experimental` or `broken` only for in-progress or known-bad records.
- `fluoh pub check/fix/upgrade` recommends only `compatible` release records by
  default.
- Manifest does not record `native`, `blocked`, or `support` machine statuses.
  Use `advisory` when upstream native support should be explained. If no
  recommended release record exists, the package is naturally unavailable.

SDK line derivation is shared by Package branches, Manifest keys, and release
tags. Take the semantic version segment before `-ohos`, then keep the first two
numeric components:

```text
3.35.8-ohos-0.0.3 -> 3.35
3.35.0-ohos-0.0.1 -> 3.35
```

Complete SDK versions that do not match this shape fail validation.

Release tag strings are derived rather than repeated in Manifest data:

```text
<package>-<upstreamVersion>-ohos-<sdkLine>-<version>
```

For example, package `path_provider`, upstream version `2.1.5`, SDK line
`3.35`, and version `0.2.0` derive:

```text
path_provider-2.1.5-ohos-3.35-0.2.0
```

For the same package, upstream version, and SDK line, every adaptation content
change must increment `version`.

## Adaptation Rules And Workflow

1. Select a complete Flutter OHOS SDK version, for example
   `3.35.8-ohos-0.0.3`.
2. Derive the SDK line from the complete SDK version by taking the first two
   numeric components before `-ohos`, for example `3.35.8-ohos-0.0.3 -> 3.35`.
3. Create or switch to `ohos/<sdkLine>`, for example `ohos/3.35`. Adaptation
   branches are maintained by major SDK line, not SDK patch version.
4. Package `fluoh.yaml` records only the upstream package version and FlutterOH
   adaptation package version currently maintained or prepared on the branch.
5. During adaptation, write `packages.<name>.status` or `releases[].status` as
   `experimental`. When the adaptation is complete and recommended for
   projects, omit `status`; the default is `compatible`.
6. `fluoh pub release` derives a release tag from Package `fluoh.yaml`. The tag
   freezes the code, tests, and config snapshot at release time.
7. `fluoh source sync` scans released tags, reads Package `fluoh.yaml` from
   each tag, and aggregates historical release records into Manifest files.
8. Consumer projects read Project `sdk.version`, derive the SDK line, and look
   for matching `compatible` release records under Manifest
   `sdks.<sdkLine>.releases`.

## Dependency Report And Plan

`fluoh pub check` reads the local resolved Source lock. The lock is regenerated
from Source root and Manifest YAML when source inputs change or the lock is
missing. Generated matrix files are not committed.

Consumer status is based only on release records:

- Exact `compatible` release record for the package version in the lockfile and
  SDK line -> `ready`.
- Pub-semver compatible newer upstream version in the same SDK line ->
  `version upgrade`.
- A package has release records for other SDK lines but not the current SDK line
  -> `SDK mismatch`.
- The version-change policy rejects the current candidate -> `needs decision`.
- No recommended release record exists -> `unavailable`.

`advisory` is shown as guidance and does not change dependency status.

## `config.json`

Tool config remains JSON because it is machine-owned runtime state:

```json
{
  "sources": {
    "flutteroh": {
      "url": "https://github.com/FlutterOH/pub.git",
      "path": "/home/user/.fluoh/sources/flutteroh",
      "priority": 0
    },
    "local": {
      "url": "/Users/user/source/pub",
      "path": "/home/user/.fluoh/sources/local",
      "priority": 10
    }
  }
}
```

Rules:

- The official Source alias is `flutteroh`, its default priority is `0`, and it
  cannot be removed.
- User-added Sources default to priority `10`. Higher values win.
- `url` supports HTTPS URLs, SSH URLs, `file:` URLs, and local paths.
- HTTPS/SSH URLs use Git clone/update. Local paths and `file:` URLs are copied
  into validated Source snapshots.
- `path` is the local cache path.
- Source caches store only the latest validated snapshot. Git history and
  unrelated repository files are not kept.

## `sources.lock.json`

`$FLUOH_HOME/sources.lock.json` is a machine-generated, local-only resolved
Source index. It is derived from `config.json` plus every validated Source
snapshot, then merged by priority so source-consuming commands can read one
stable JSON file instead of reparsing all Source YAML every time.

Example shape:

```json
{
  "generatedBy": "fluoh 0.1.0",
  "generatedAt": "2026-05-13T12:00:00Z",
  "inputs": {
    "toolVersion": "0.1.0",
    "configHash": "hash64:...",
    "sources": [
      {
        "name": "flutteroh",
        "path": "/home/user/.fluoh/sources/flutteroh",
        "url": "https://github.com/FlutterOH/pub.git",
        "priority": 0,
        "snapshotHash": "hash64:..."
      },
      {
        "name": "local",
        "path": "/home/user/.fluoh/sources/local",
        "url": "/Users/user/source/pub",
        "priority": 10,
        "snapshotHash": "hash64:..."
      }
    ]
  },
  "sdk": {
    "versions": {
      "3.35.8-ohos-0.0.3": {
        "source": "flutteroh",
        "priority": 0,
        "versionSeries": "3.35",
        "flutterVersion": "3.35.8",
        "channel": "stable",
        "tag": "3.35.8-ohos-0.0.3",
        "git": {
          "url": "https://gitcode.com/openharmony-tpc/flutter_flutter.git"
        }
      }
    }
  },
  "packages": {
    "path_provider": {
      "source": "flutteroh",
      "priority": 0,
      "repository": {
        "git": {
          "url": "https://github.com/FlutterOH/packages.git"
        },
        "path": "packages/path_provider/path_provider"
      },
      "upstream": {
        "git": {
          "url": "https://github.com/flutter/packages.git",
          "branch": "main"
        },
        "path": "packages/path_provider/path_provider"
      },
      "advisory": {
        "message": "Prefer upstream path_provider for new projects."
      },
      "sdks": {
        "3.35": {
          "releases": [
            {
              "version": "0.2.0",
              "upstreamVersion": "2.1.5",
              "status": "compatible",
              "tag": "path_provider-2.1.5-ohos-3.35-0.2.0",
              "repository": {
                "git": {
                  "url": "https://github.com/FlutterOH/packages.git"
                },
                "path": "packages/path_provider/path_provider"
              },
              "upstream": {
                "git": {
                  "url": "https://github.com/flutter/packages.git",
                  "branch": "main"
                },
                "path": "packages/path_provider/path_provider"
              },
              "source": "flutteroh",
              "priority": 0
            }
          ]
        }
      }
    }
  }
}
```

Rules:

- The lock does not contain a `schema` field. It is disposable generated state,
  and incompatible or stale locks are rebuilt instead of migrated.
- Source root and Manifest YAML remain the only human-edited Source data.
- Source lock maintenance is owned by the Source runtime in `lib/src/source/`.
  Commands must not assemble or partially update the lock themselves.
- The lock is regenerated from scratch by the Source runtime whenever
  `config.json`, any configured Source snapshot, Source merge rules, or the
  `fluoh` tool version changes.
- Source mutation entrypoints, including `fluoh source add`,
  `fluoh source remove`, `fluoh source update`, configured snapshot repairs,
  configured-snapshot `fluoh source sync`, and first default Source bootstrap,
  ask the Source runtime to rebuild the lock.
  Source-consuming flows use the same load-index API, which regenerates the lock
  on demand when it is missing or stale, or when selected-SDK installation needs
  SDK metadata.
- The lock stores normalized defaults and derived fields such as
  `status: compatible`, `upstream.git.branch: main`, SDK line, release tag,
  winning Source alias, priority, and final repository paths.
  Release records also store their own repository URL/path so multiple Sources
  can contribute releases for the same package without losing the release origin
  when the lock is read back.
- Lock generation applies the same priority and conflict rules documented for
  Source commands. Conflicts fail generation before consumer commands read
  partially resolved data.
- Writes use a temporary file plus atomic replacement. If generation fails, the
  previous file is not treated as fresh unless its recorded inputs still match.
