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
  <img src="https://img.shields.io/badge/diagnostics-JSON-blue" alt="JSON diagnostics">
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

Ask your AI agent to install the skill:

```text
Install the fluoh skill from https://github.com/FlutterOH/fluoh/tree/main/skills, overwriting any existing installation.
```

Then use one of these prompts:

```text
Use $fluoh to install fluoh if needed and adapt this Flutter project for OHOS.
Use $fluoh to adapt <upstream-git-url> for FlutterOH.
Use $fluoh to continue adapting <package-name> for OHOS.
```

If `fluoh` is already installed:

```text
Run `fluoh skill --json`, install the returned localPath as a skill, then reload skills if needed.
```

After `fluoh upgrade`, run `fluoh skill --json` again and reload the returned
path. Workflow details live in the [skill](skills/fluoh/SKILL.md) and
[command reference](doc/commands.md).

## Manual Fallback

Install the CLI and run the app flow yourself:

```sh
dart pub global activate fluoh
fluoh sdk use 3.35 --pub-get
fluoh deps check
fluoh deps fix
fluoh doctor -p --platform ohos
fluoh build --platform ohos --auto-sign
```

macOS install:

```sh
brew tap FlutterOH/tap
brew install fluoh
```

Package workflow:

```sh
fluoh package discover <upstream-git-url> --json
fluoh package create <upstream-git-url> --repository-name <flutteroh-repo-name>
fluoh verify
fluoh package status
```

Add more packages from the generated repository:

```sh
fluoh package queue
fluoh package add
fluoh verify
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
