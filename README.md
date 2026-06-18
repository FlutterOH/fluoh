<h1 align="center">
  <img src="doc/assets/svg/fluoh-logo.svg" alt="fluoh logo" align="absmiddle">
  fluoh
</h1>

<p align="center">
  FlutterOH-first AI workflows for Flutter apps and packages.
</p>

<p align="center">
  <a href="https://pub.dev/packages/fluoh"><img src="https://img.shields.io/pub/v/fluoh.svg" alt="pub package"></a>
  <a href="https://github.com/FlutterOH/fluoh/actions/workflows/ci.yml"><img src="https://github.com/FlutterOH/fluoh/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="skills/fluoh/SKILL.md"><img src="https://img.shields.io/badge/AI%20skill-skills%2Ffluoh-6f42c1" alt="AI skill"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/FlutterOH/fluoh.svg" alt="License"></a>
</p>

<p align="center">
  <a href="#quick-start">Quick start</a> ·
  <a href="skills/fluoh/SKILL.md">Skill</a> ·
  <a href="doc/commands.md">Commands</a> ·
  <a href="doc/schema.md">Schema</a> ·
  <a href="CONTRIBUTING.md">Contributing</a> ·
  <a href="README.zh-CN.md">简体中文</a>
</p>

<p align="center">
  <img src="doc/assets/svg/readme-hero.svg" alt="fluoh AI support prompt preview">
</p>

## Quick Start

### AI First

For most FlutterOH support work, use the bundled fluoh AI skill. After
confirming the scope, it updates the project or package, runs verification
across the target and preserved platforms, and writes a local report.

Install the bundled skill in your AI agent:

```text
Run `fluoh skill --path`, install the printed path as the fluoh skill, and overwrite any existing installation. Use https://github.com/FlutterOH/fluoh/tree/main/skills/fluoh only when fluoh is not installed yet.
```

Then ask the agent for the workflow you need:

```text
Use $fluoh to install fluoh if needed and add FlutterOH support to this Flutter project.
Use $fluoh to port <upstream-git-url> for FlutterOH.
Use $fluoh to continue implementing FlutterOH support for <package-name>.
Use $fluoh to precheck this FlutterOH Source change.
```

See the [skill](skills/fluoh/SKILL.md) for the AI workflow and the
[command reference](doc/commands.md) for CLI behavior.

### Install fluoh

```sh
dart pub global activate fluoh
```

On macOS, a native install is also available:

```sh
brew tap FlutterOH/fluoh https://github.com/FlutterOH/fluoh.git
brew install FlutterOH/fluoh/fluoh
```

### Existing Flutter App

From the project root:

```sh
cd path/to/existing_app
fluoh sdk use 3.35 --pub-get
fluoh deps check
fluoh deps fix --dry-run
fluoh deps fix
fluoh deps get
fluoh doctor --platform ohos --project
fluoh build ohos --auto-sign
```

Review the `fluoh deps fix --dry-run` output before applying `fluoh deps fix`.

### New Flutter App

Create the project with a FlutterOH SDK:

```sh
fluoh create --sdk 3.35 demo_app --platforms=android,ios,ohos
cd demo_app
```

Then run the existing-app commands starting at `fluoh deps check`.

### Package Maintainers

Create a spec-first FlutterOH package repository, or discover and port an
upstream package repository:

```sh
fluoh package new <name> --repository-name <flutteroh-repo-name>
fluoh package discover <upstream-git-url>
fluoh package port <upstream-git-url> --repository-name <flutteroh-repo-name>
cd <flutteroh-repo-name>
fluoh package next --package <name>
fluoh package status --package <name>
```

`fluoh package next` reports one focused implementation action at a time. Follow
the printed action, rerun it until ready or blocked, then use `package status`,
`package handoff`, and `package check` for release readiness.

Add another package branch from the generated repository when needed:

```sh
fluoh package queue <package-path>...
fluoh package add <package-path>
fluoh verify --package <name>
```

After the first release, register the package branch in Source:

```sh
fluoh source register . --source <source-repo>
```

Run Flutter through the selected FlutterOH SDK:

```sh
fluohf pub get
fluohf run
fluohf build hap
```

## Links

- [Command reference](doc/commands.md)
- [Source schema](doc/schema.md)
- [Contributing and release workflow](CONTRIBUTING.md)
- [Official source data](https://github.com/FlutterOH/source.git)

## License

MIT
