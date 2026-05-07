# fluoh

Command-line tools for the FlutterOH ecosystem. `fluoh` manages Flutter OHOS SDK versions, checks OHOS dependency adapter status, and helps third-party package maintainers create FlutterOH pub repositories.

[简体中文](README.zh-CN.md) | [Contributing](CONTRIBUTING.md)

## Why fluoh

FlutterOH projects usually need consistent SDK selection, dependency compatibility checks, and repeatable pub repository conventions. `fluoh` turns those workflows into a small set of CLI commands.

Core capabilities:

- Install, cache, switch, and run Flutter OHOS SDKs from `fluoh.yaml`.
- Check dependencies against FlutterOH data sources and generate OHOS adapter replacements.
- Initialize third-party FlutterOH pub repositories with OHOS branches and release tags.
- Support pub repository remote configuration and Homebrew installation.

## Installation

Install with Dart:

```sh
dart pub global activate fluoh
fluoh --version
```

Make sure Dart's global pub bin directory is on `PATH`. On macOS and Linux this is usually:

```sh
export PATH="$HOME/.pub-cache/bin:$PATH"
```

Install with Homebrew on macOS:

```sh
brew tap FlutterOH/tap
brew install fluoh
```

## Quick Start

Run these commands from a Flutter project root:

```sh
fluoh source update
fluoh sdk list
fluoh sdk use 3.35
fluoh flutter pub get
fluoh deps check
fluoh deps fix --yes
fluoh doctor
```

`fluoh sdk use` accepts an exact SDK tag or a version series such as `3.35`; a series resolves to the latest stable SDK in that series and records the exact tag in `fluoh.yaml`. Run project Flutter commands through `fluoh flutter ...`, for example `fluoh flutter pub get`, `fluoh flutter run`, or `fluoh flutter build hap`. Add `--pub-get` to `fluoh sdk use` when you want to run the first `pub get` automatically.

## Common Workflows

### Switch Flutter OHOS SDK

Use a version series or exact SDK tag from `fluoh sdk list`:

```sh
fluoh sdk list
fluoh sdk use 3.35
fluoh flutter --version
```

### Check and fix OHOS dependency adapters

```sh
fluoh deps check
fluoh deps fix --yes
fluoh deps update --yes
```

`fluoh deps fix` writes `dependency_overrides` by default. Use `--rewrite` when you want to rewrite direct `dependencies` declarations instead.

### Create third-party pub repositories

```sh
fluoh pub create https://github.com/upstream/package.git --sdk 3.35.8-ohos-0.0.3
git commit -m "feat(pub): initialize FlutterOH adapter"
fluoh pub sync
fluoh pub adapt
fluoh pub release --push
```

Select a package inside a monorepo:

```sh
fluoh pub create https://github.com/upstream/monorepo.git \
  --package some_package \
  --path packages/some_package \
  --sdk 3.35.8-ohos-0.0.3
```

Generated pub repositories keep the upstream default branch clean, keep the source remote as `upstream`, create an `ohos/<sdk-series>` branch such as `ohos/3.35`, set `origin`, and write FlutterOH metadata. `fluoh pub create` stages generated files but does not commit. Commit before running `pub sync`, `pub adapt`, or `pub release`.

To choose the final push target:

```sh
fluoh pub create https://github.com/upstream/package.git \
  --sdk 3.35.8-ohos-0.0.3 \
  --repo git@github.com:FlutterOH/package.git
```

## Command Overview

| Command | Purpose |
| --- | --- |
| `fluoh flutter ...` | Run `flutter` from the SDK selected in `fluoh.yaml`; use this for normal Flutter commands in a FlutterOH project. |
| `fluoh sdk ...` | List, install, remove, and select local Flutter OHOS SDKs. |
| `fluoh sdk use <version-or-series>` | Switch the SDK for the current Flutter project. |
| `fluoh deps check` | Check OHOS compatibility for project dependencies. |
| `fluoh deps fix` | Write adapted dependency replacements. |
| `fluoh deps update` | Upgrade existing OHOS-adapted dependency versions in the current project. |
| `fluoh pub ...` | Create, sync, adapt, and release third-party FlutterOH pub repositories. |
| `fluoh source ...` | Manage FlutterOH data sources. |
| `fluoh doctor` | Diagnose CLI version, SDK, OHOS directory, and dependency status. |
| `fluoh upgrade` | Upgrade the `fluoh` CLI itself. |

`fluoh deps update` and `fluoh upgrade` are intentionally different: `deps update` upgrades OHOS-adapted dependencies in the current project; `upgrade` upgrades the CLI tool itself.

## Data Sources

`fluoh` uses the official FlutterOH data source by default:

```text
https://github.com/FlutterOH/pub
```

You can also create a local source or use an internal team source:

```sh
fluoh source init ./flutteroh-pub-local
fluoh source add local ./flutteroh-pub-local --priority 200
fluoh source add internal https://github.com/example/flutteroh-pub.git --priority 200
fluoh source update
```

`fluoh source init` creates a package-only source template compatible with `FlutterOH/pub`. Sources are layered by priority. Internal or local sources can provide only `packages/repositories.yaml` and `packages/manifests/*.yaml` to add team adapters while SDK releases continue to come from the official source. Any source except the official `flutteroh` source can be removed:

```sh
fluoh source remove internal
```

Remote and local sources are cached as the latest validated snapshot under `FLUOH_HOME`; `fluoh` does not keep Git history in the cache.

## Contributing

Local development, testing, pub.dev publishing, Homebrew formula maintenance, and pre-commit checks are documented in [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT
