# fluoh

<p align="center">
  <strong>Make FlutterOH projects boring to configure.</strong>
</p>

<p align="center">
  Pick the SDK. Fix FlutterOH dependency replacements. Run Flutter through the right toolchain.
</p>

<p align="center">
  <a href="https://pub.dev/packages/fluoh"><img src="https://img.shields.io/pub/v/fluoh.svg" alt="pub package"></a>
  <a href="https://github.com/FlutterOH/fluoh/actions/workflows/ci.yml"><img src="https://github.com/FlutterOH/fluoh/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/FlutterOH/fluoh.svg" alt="License"></a>
</p>

<p align="center">
  <a href="README.zh-CN.md">简体中文</a> ·
  <a href="docs/commands.md">Commands</a> ·
  <a href="docs/schema.md">Schema</a> ·
  <a href="CONTRIBUTING.md">Contributing</a>
</p>

`fluoh` is the project-level control plane for FlutterOH. It records the Flutter
OHOS SDK version a project should use, runs Flutter through that SDK, checks pub
dependencies for FlutterOH adaptations, and applies the safe `pubspec.yaml`
changes for you.

```sh
dart pub global activate fluoh

cd your_flutter_project
fluoh source update
fluoh sdk use 3.35 --pub-get
fluoh pub check
fluoh pub fix
fluohf build hap
```

After that, the project has an exact SDK version in `fluoh.yaml`, a stable IDE
SDK path at `.fluoh/flutter_sdk`, and FlutterOH dependency replacements that
match the latest validated snapshot from the official FlutterOH source.

## Why It Exists

FlutterOH projects should not depend on a local checklist:

- Which Flutter OHOS SDK checkout is this project using?
- Did the IDE point at the same SDK as the terminal?
- Do these pub dependencies already have FlutterOH adaptations?
- Are the FlutterOH dependency replacements current, or copied from an old project?

`fluoh` turns those answers into project state and repeatable commands.

## The Daily Loop

```sh
# Select the SDK once per project.
fluoh sdk list
fluoh sdk use 3.35 --pub-get

# Run Flutter through the selected SDK.
fluohf pub get
fluohf run
fluohf build hap

# Keep FlutterOH dependency replacements current.
fluoh pub check
fluoh pub fix --dry-run
fluoh pub fix
fluoh pub get
```

Useful extras:

```sh
fluoh pub upgrade   # upgrade existing FlutterOH dependency replacements only
fluoh clean         # run flutter clean and remove generated fluoh_test output
fluoh doctor        # diagnose sources, SDK selection, and project setup
fluoh upgrade       # upgrade the fluoh CLI
```

`fluoh pub fix` writes `dependency_overrides` by default. Set
`dependencyPolicy.pubspecSection: dependencies` in `fluoh.yaml` when a project
should rewrite direct `dependencies` instead. Incompatible version changes and
downgrades stay skipped unless `dependencyPolicy.versionChanges` is `any`.

## Install

```sh
dart pub global activate fluoh
fluoh --version
```

Make sure Dart's global pub bin directory is on `PATH`:

```sh
export PATH="$HOME/.pub-cache/bin:$PATH"
```

Homebrew on macOS:

```sh
brew tap FlutterOH/tap
brew install fluoh
```

## Maintainers

Most users only need the project commands above. Maintainers also get workflows
for third-party FlutterOH pub repositories and source metadata:

```sh
fluoh pub create
fluoh pub sync
fluoh test init
fluoh test run
fluoh pub release
fluoh source sync
```

See [docs/commands.md](docs/commands.md) for the full command surface and
[CONTRIBUTING.md](CONTRIBUTING.md) for repository, release, and publishing
workflows.

## Source Data

`fluoh` uses the official FlutterOH source by default:

```text
https://github.com/FlutterOH/pub.git
```

`fluoh source update` refreshes the latest validated snapshot under
`FLUOH_HOME`. Source file details are documented in
[docs/schema.md](docs/schema.md).

## License

MIT
