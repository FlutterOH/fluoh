# fluoh

Command-line tools for the FlutterOH ecosystem. `fluoh` manages Flutter OHOS SDK versions, checks OHOS dependency adapter status, and helps third-party package maintainers create FlutterOH pub repositories.

[简体中文](README.zh-CN.md) | [Contributing](CONTRIBUTING.md)

## Why fluoh

FlutterOH projects usually need consistent SDK selection, dependency compatibility checks, and repeatable pub repository conventions. `fluoh` turns those workflows into a small set of CLI commands.

Core capabilities:

- Install and switch Flutter OHOS SDKs with FVM-compatible project files.
- Check dependencies against FlutterOH data sources and generate OHOS adapter replacements.
- Initialize third-party FlutterOH pub repositories with OHOS branches and release tags.
- Support pub repository remote configuration, pub.dev automated publishing, and Homebrew installation.

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
fluoh sdk use 3.22 --pub-get
fluoh deps check
fluoh deps fix --yes
fluoh doctor
```

`fluoh sdk use` installs the selected Flutter OHOS SDK and writes `.fvmrc`, `.fvm/flutter_sdk`, and `fluoh.yaml`. After that you can keep using FVM or run project commands through `.fvm/flutter_sdk/bin/flutter`.

## Common Workflows

### Switch Flutter OHOS SDK

List SDK releases and select an exact SDK tag for the current project:

```sh
fluoh source update
fluoh sdk list
fluoh sdk use 3.35.8-ohos-0.0.3 --pub-get
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

Generated pub repositories keep the upstream default branch clean, keep the upstream repository as `upstream`, and set `origin` to `git@github.com:FlutterOH/<package>.git` by default. FlutterOH changes are committed only on `ohos/<sdk-tag>` branches. To choose the final push target:

```sh
fluoh pub create https://github.com/upstream/package.git \
  --sdk 3.35.8-ohos-0.0.3 \
  --repository git@github.com:FlutterOH/package.git
```

## Command Overview

| Command | Purpose |
| --- | --- |
| `fluoh sdk ...` | List, install, and remove local Flutter OHOS SDKs. |
| `fluoh sdk use <version>` | Switch the SDK for the current Flutter project. |
| `fluoh deps check` | Check OHOS compatibility for project dependencies. |
| `fluoh deps fix` | Write adapted dependency replacements. |
| `fluoh deps update` | Upgrade existing OHOS-adapted dependency versions in the current project. |
| `fluoh pub ...` | Create, sync, adapt, and release third-party FlutterOH pub repositories. |
| `fluoh source ...` | Manage FlutterOH data sources. |
| `fluoh doctor` | Diagnose CLI version, SDK, FVM, OHOS directory, and dependency status. |
| `fluoh upgrade` | Upgrade the `fluoh` CLI itself. |

`fluoh deps update` and `fluoh upgrade` are intentionally different: `deps update` upgrades OHOS-adapted dependencies in the current project; `upgrade` upgrades the CLI tool itself.

## Data Sources

`fluoh` uses the official FlutterOH data source by default:

```text
https://github.com/FlutterOH/pub.git
```

You can also use an internal team data source:

```sh
fluoh source add internal https://github.com/example/flutteroh-pub.git --priority 200
fluoh source update
```

Sources are layered by priority. An internal source can provide only `packages/registry.yaml` and `packages/manifests/*.yaml` to add team adapters while SDK releases continue to come from the official source. Any source except the official `flutteroh` source can be removed:

```sh
fluoh source remove internal
```

Remote sources are cached as the latest validated snapshot under `FLUOH_HOME`;
`fluoh` does not keep Git history in the source cache. Local path sources are
also copied into the same cache so later edits to the original directory do not
change the configured source until it is added again.

## Contributing

Local development, testing, pub.dev publishing, Homebrew formula maintenance, and pre-commit checks are documented in [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT
