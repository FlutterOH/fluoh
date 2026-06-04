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

Ask your AI agent to install the skill first:

```text
Install the fluoh skill from https://github.com/FlutterOH/fluoh/tree/main/skills/fluoh.
```

Then type one request for an app or a package:

```text
Use $fluoh to install fluoh if needed and adapt this Flutter project for OHOS.
Use $fluoh to adapt <upstream-git-url> for FlutterOH.
Use $fluoh to continue adapting <package-name> for OHOS.
```

The skill checks `fluoh --version`, installs the CLI when it is missing, runs
read-only setup checks, asks for final setup confirmation before project or
package changes, follows JSON diagnostics, edits the project or package,
verifies the result, and saves `.fluoh/ai-report-...md` with a delivery
checklist.
It prefers `dart pub global activate fluoh`, with Homebrew as the macOS
fallback.

If you already have the CLI installed, an agent can discover the bundled local
skill path and helper script commands with:

```text
Run `fluoh skill --json`, install the returned localPath as a skill, then reload skills if needed.
```

The skill version follows the `fluoh` CLI version. To update it, run
`fluoh upgrade`, then ask the agent to run `fluoh skill --json` again and
reinstall or reload the returned path.

## Manual Fallback

When you need to install or drive the CLI yourself:

```sh
dart pub global activate fluoh
fluoh sdk use 3.35 --pub-get
fluoh deps check
fluoh deps fix
fluoh doctor -p --platform ohos
fluoh build --platform ohos --auto-sign
```

macOS alternative:

```sh
brew tap FlutterOH/tap
brew install fluoh
```

The Homebrew formula installs native executables, which are preferred for
strict `--json` automation because they do not invoke `dart pub global run`.

For package maintainers:

```sh
fluoh package create <upstream-git-url> --repository-name <flutteroh-repo-name>
fluoh verify
fluoh package status
```

For monorepos, pass one `--package-path <path>` to create the first package
branch. Omitting `--package-path` selects only the repository root package; it
never means all packages. To adapt another package in the same repository, run
`fluoh package add <package-path>` from the generated repository; it creates a
separate `ohos/<sdkLine>/<package>` branch for that package.
`--repository-name` is required for every new package repository; when a single
package path is selected, the CLI can suggest a candidate if it is omitted.

Use `fluohf` to run Flutter through the selected FlutterOH SDK:

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
