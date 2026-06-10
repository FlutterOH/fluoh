<h1 align="center">
  <img src="doc/assets/svg/fluoh-logo.svg" alt="fluoh logo" align="absmiddle">
  fluoh
</h1>

<p align="center">
  Adapt Flutter apps and packages to OHOS with AI.
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
  <img src="doc/assets/svg/readme-hero.svg" alt="fluoh AI adaptation prompt preview">
</p>

## Quick Start

### AI First

For most app or package adaptation work, start with the bundled skill in your
AI agent. Give AI the goal and it will handle the full path from environment
setup, project inspection, code adaptation, and automated verification to the
local report.

Install the bundled skill in your AI agent:

```text
Install the fluoh skill from https://github.com/FlutterOH/fluoh/tree/main/skills/fluoh, overwriting any existing installation.
```

Then ask the agent for the workflow you need:

```text
Use $fluoh to install fluoh if needed and adapt this Flutter project for OHOS.
Use $fluoh to adapt <upstream-git-url> for FlutterOH.
Use $fluoh to continue adapting <package-name> for OHOS.
```

Before making changes, the agent will explain the adaptation scope, change plan,
and verification path, then continue after confirmation.
The [skill](skills/fluoh/SKILL.md) is the AI entry point; the
[command reference](doc/commands.md) documents the full CLI surface.

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
fluoh doctor -p --platform ohos
fluoh build --platform ohos --auto-sign
```

Review the `deps fix --dry-run` output before applying `deps fix`.

### New Flutter App

Create the project with a Flutter OHOS SDK, then continue from the generated
project root:

```sh
fluoh create --sdk 3.35 demo_app --platforms=android,ios,ohos
cd demo_app
fluoh deps check
fluoh deps fix --dry-run
fluoh deps fix
fluoh deps get
fluoh doctor -p --platform ohos
fluoh build --platform ohos --auto-sign
```

### Package Maintainers

Start by discovering the upstream package and creating a FlutterOH adaptation
repository:

```sh
fluoh package discover <upstream-git-url>
fluoh package create <upstream-git-url> --repository-name <flutteroh-repo-name>
cd <flutteroh-repo-name>
fluoh verify --package <name>
fluoh run --platform ohos --package <name> --auto-emulator
fluoh package status --package <name>
```

Add another package branch from the generated repository:

```sh
fluoh package queue <package-path>...
fluoh package add <package-path>
fluoh verify --package <name>
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
