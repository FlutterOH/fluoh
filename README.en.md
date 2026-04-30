# fluoh

Command-line tools for the FlutterOH ecosystem. `fluoh` manages Flutter OHOS SDK versions, checks OHOS dependency adapter status, and helps third-party package maintainers create adapter repositories.

[简体中文](README.md) | [Contributing](CONTRIBUTING.en.md)

## Why fluoh

FlutterOH projects usually need consistent SDK selection, dependency compatibility checks, and repeatable adapter repository conventions. `fluoh` turns those workflows into a small set of CLI commands.

Core capabilities:

- Install and switch Flutter OHOS SDKs with FVM-compatible project files.
- Check dependencies against FlutterOH data sources and generate OHOS adapter replacements.
- Initialize third-party package adapter repositories with adapter branches and release tags.
- Support GitHub organization automation, pub.dev automated publishing, and Homebrew installation.

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
fluoh use 3.22 --pub-get
fluoh doctor
fluoh deps check
fluoh deps fix --yes
```

`fluoh use` installs the selected Flutter OHOS SDK and writes `.fvmrc`, `.fvm/flutter_sdk`, and `fluoh.yaml`. After that you can keep using FVM or run project commands through `.fvm/flutter_sdk/bin/flutter`.

## Common Workflows

### Switch Flutter OHOS SDK

List SDK releases and select an SDK line or exact tag for the current project:

```sh
fluoh source update
fluoh sdk list
fluoh use 3.22 --pub-get
```

### Check and fix OHOS dependency adapters

```sh
fluoh deps check
fluoh deps fix --yes
fluoh update --yes
```

`fluoh deps fix` writes `dependency_overrides` by default. Use `--rewrite` when you want to rewrite direct `dependencies` declarations instead.

### Create third-party adapter repositories

```sh
fluoh create https://github.com/upstream/package.git --sdk-line 3.22
fluoh release --push
```

Select a package inside a monorepo:

```sh
fluoh create https://github.com/upstream/monorepo.git \
  --package some_package \
  --path packages/some_package \
  --sdk-line 3.22
```

Create a FlutterOH organization repository and push branches:

```sh
fluoh create https://github.com/upstream/package.git \
  --sdk-line 3.22 \
  --github \
  --org FlutterOH
```

## Command Overview

| Command | Purpose |
| --- | --- |
| `fluoh source ...` | Manage FlutterOH data sources. |
| `fluoh sdk ...` | List, install, and remove local Flutter OHOS SDKs. |
| `fluoh use <version-or-line>` | Switch the SDK for the current Flutter project. |
| `fluoh deps check` | Check OHOS compatibility for project dependencies. |
| `fluoh deps fix` | Write adapted dependency replacements. |
| `fluoh update` | Upgrade existing OHOS-adapted dependency versions in the current project. |
| `fluoh doctor` | Diagnose SDK, FVM, OHOS directory, and dependency status. |
| `fluoh create` | Initialize a FlutterOH third-party adapter repository. |
| `fluoh release` | Create and optionally push an adapter release tag. |
| `fluoh upgrade` | Upgrade the `fluoh` CLI itself. |

`fluoh update` and `fluoh upgrade` are intentionally different: `update` upgrades OHOS-adapted dependencies in the current project; `upgrade` upgrades the CLI tool itself.

## Data Sources

`fluoh` uses the official FlutterOH data source by default:

```text
https://github.com/FlutterOH/pub.git
```

You can also use an internal team data source:

```sh
fluoh source add internal https://github.com/example/flutteroh-pub.git --priority 200
fluoh source use internal
fluoh source update
```

## Contributing

Local development, testing, pub.dev publishing, Homebrew formula maintenance, and pre-commit checks are documented in [CONTRIBUTING.en.md](CONTRIBUTING.en.md).

## License

MIT
