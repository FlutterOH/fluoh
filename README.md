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
fluoh pub check
fluoh pub fix
fluoh flutter pub get
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
fluoh pub check
fluoh pub fix
fluoh flutter pub get
```

`fluoh pub check` groups dependencies by compatibility and prints the next step. `fluoh pub fix` updates `pubspec.yaml` with recommended OHOS adapter refs; use `fluoh pub fix --dry-run` to preview changes. By default it writes `dependency_overrides`; set `dependencyPolicy.replacementMode: rewrite` in `fluoh.yaml` when you want to rewrite direct `dependencies` declarations instead. Version-mismatch adapters are skipped unless `dependencyPolicy.versionMismatch` is set to `allow`. Use `fluoh pub upgrade` when a project already uses OHOS adapters and you only want to refresh existing adapter refs.

### Create third-party pub repositories

```sh
fluoh pub create https://github.com/upstream/package.git --sdk 3.35.8-ohos-0.0.3
git commit -m "feat(pub): initialize FlutterOH adapter"
fluoh pub sync
fluoh pub release --push
```

Select a package inside a monorepo:

```sh
fluoh pub create https://github.com/upstream/monorepo.git \
  --package some_package \
  --path packages/some_package \
  --sdk 3.35.8-ohos-0.0.3
```

Generated pub repositories keep the upstream default branch clean, keep the source remote as `upstream`, create an `ohos/<sdk-series>` branch such as `ohos/3.35`, set `origin`, and write FlutterOH metadata, an adaptation guide, FlutterOH release notes, AI agent instructions, and `fluoh_test/` for Flutter packages or plugins. `fluoh pub create` stages generated files but does not commit. Commit before running `pub sync` or `pub release`. `fluoh pub sync` fast-forwards the upstream branch, merges it into the current pub branch, and refreshes only the upstream metadata in `fluoh.yaml`; update the FlutterOH package version after the new adaptation is complete.

`fluoh test init` creates `fluoh_test/test` automated checks and a `fluoh_test/example` app for manual platform verification. `fluoh test run` first runs the adapter package's own Flutter tests when `test/**/*_test.dart` exists, equivalent to `fluoh flutter test` in the package path, then runs `fluoh_test`; `fluoh pub release` verifies the release version, warns when `FLUOH_CHANGELOG.md` does not document the release, and runs tests before creating or pushing a Flutter adapter release tag. FlutterOH/pub source metadata updates should go through a pull request or the scheduled source ingestion process.

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
| `fluoh pub check` | Check OHOS compatibility for project dependencies. |
| `fluoh pub fix` | Add missing OHOS adapter refs and refresh existing ones in `pubspec.yaml`. |
| `fluoh pub upgrade` | Upgrade existing OHOS adapter refs without adding new replacements. |
| `fluoh pub create/sync/release` | Create, sync, and release third-party FlutterOH pub repositories. |
| `fluoh test ...` | Create `fluoh_test` and run package plus `fluoh_test` verification for adapted Flutter packages. |
| `fluoh source ...` | Manage FlutterOH data sources. |
| `fluoh doctor` | Diagnose CLI version, project SDK, and OHOS directory status. |
| `fluoh upgrade` | Upgrade the `fluoh` CLI itself. |

`fluoh pub upgrade` and `fluoh upgrade` are intentionally different: `pub upgrade` refreshes existing OHOS adapter refs in the current project; `upgrade` upgrades the CLI tool itself.

## Data Sources

`fluoh` uses the official FlutterOH data source by default:

```text
https://github.com/FlutterOH/pub.git
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
