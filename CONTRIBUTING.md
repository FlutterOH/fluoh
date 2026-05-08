# Contributing to fluoh

简体中文: [CONTRIBUTING.zh-CN.md](CONTRIBUTING.zh-CN.md)

This document is for `fluoh` contributors and maintainers. General users should start with [README.md](README.md) or [README.zh-CN.md](README.zh-CN.md).

## Local Development

Install dependencies and run the CLI from the repository root:

```sh
dart pub get
dart run bin/fluoh.dart --help
dart run bin/fluoh.dart --version
```

To debug project-level Flutter commands, run them from a Flutter project and
select the SDK first:

```sh
dart /path/to/fluoh/bin/fluoh.dart sdk use 3.35
dart /path/to/fluoh/bin/fluoh.dart flutter --version
```

Use `fluoh flutter ...` after selecting the project SDK with
`fluoh sdk use <version-or-series>` so local tests do not depend on the global
`flutter` binary.

To debug with the installed command name, activate this checkout as a local path
package:

```sh
dart pub global activate --source path . --overwrite
fluoh --version
```

If your shell cannot find `fluoh`, add Dart pub's global executable directory
to `PATH`:

```sh
export PATH="$HOME/.pub-cache/bin:$PATH"
```

Code changes usually do not require reactivation unless executable or package
metadata changed. To debug a published package, activate the hosted version:

```sh
dart pub global activate fluoh --overwrite
dart pub global activate fluoh 0.0.1 --overwrite
fluoh --version
```

Switch back with `dart pub global activate --source path . --overwrite`, or
deactivate `fluoh`:

```sh
dart pub global deactivate fluoh
```

Set `FLUOH_HOME` if you need isolated local configuration and caches:

```sh
FLUOH_HOME=/path/to/cache dart run bin/fluoh.dart source list
```

## Verification

Run and pass these checks before committing:

```sh
dart format .
dart analyze
dart test
```

`dart format .` should not leave unreviewed formatting diffs. GitHub Actions
runs the same checks on pushes to `main`, version tags, and pull requests. The
pub.dev publishing workflow must pass:

- `dart format --output=none --set-exit-if-changed .`
- `dart analyze`
- `dart test`

Before publishing, also run:

```sh
dart pub publish --dry-run
```

If the `dart` command in your shell is unstable, you may explicitly use the Dart SDK bundled with Flutter, but do not commit machine-specific absolute paths.

## Pre-commit Checks

Recommended checks before committing:

```sh
git status --short
git diff --check
```

Also check that staged changes do not contain local absolute paths. Do not commit IDE, system, or build output files such as `.idea/`, `.vscode/`, `.DS_Store`, `.dart_tool/`, `build/`, or `coverage/`.

`pubspec.lock` may be committed for this CLI application. Before publishing, make sure the version metadata in `pubspec.yaml`, `lib/src/version.dart`, `CHANGELOG.md`, and `Formula/fluoh.rb` is consistent.

## Commit Format

Commit messages use Conventional Commits:

```text
<type>(<scope>): <subject>
```

`scope` is optional. Prefer the affected command, module, or documentation area, such as `sdk`, `pub`, `source`, `docs`, or `ci`.

Common `type` values:

- `feat`: New feature or command.
- `fix`: Bug fix.
- `docs`: Documentation change.
- `test`: Test addition or adjustment.
- `refactor`: Code refactor without behavior changes.
- `chore`: Build, dependency, version, or repository maintenance.
- `ci`: GitHub Actions or release pipeline change.

Examples:

```text
feat(pub): configure pub repository remotes
fix(pub): upgrade rewritten OHOS dependencies
docs: add Homebrew installation guide
ci: publish package on version tags
```

Use a concise English subject and keep the first line within 72 characters. Add
a body when background, risk, or verification details are useful.

## GitHub Actions and pub.dev Publishing

This repository publishes to pub.dev through GitHub Actions when a version tag is pushed:

```sh
git tag v0.0.1
git push origin v0.0.1
```

The tag must match the `version` in `pubspec.yaml`. A pub.dev package admin must enable GitHub Actions automated publishing:

- Repository: `FlutterOH/fluoh`
- Tag pattern: `v{{version}}`
- Environment: `pub.dev`

Automated pub.dev publishing only works for an existing package. The first release still requires a maintainer to publish manually:

```sh
dart pub publish
```

## Homebrew Formula

The Homebrew formula lives at [Formula/fluoh.rb](Formula/fluoh.rb). Local verification:

```sh
brew tap FlutterOH/fluoh https://github.com/FlutterOH/fluoh.git
brew install FlutterOH/fluoh/fluoh
fluoh --version
```

When an official `brew tap FlutterOH/tap` is available, sync the formula into the FlutterOH tap repository. The current formula uses the pub.dev archive as its download source; update the archive URL and version whenever releasing a new version.

## Pub Repository Workflow Maintenance

`fluoh pub create` keeps the upstream default branch clean, keeps the clone source as `upstream`, creates an `ohos/<sdk-series>` pub branch, sets `origin` to the final pub repository push target, and configures the selected Flutter OHOS SDK environment. The default repository URL is derived from the package name:

```sh
git@github.com:FlutterOH/<package>.git
```

If a package needs to be pushed to a dedicated FlutterOH pub repository, pass `--repo` when creating it:

```sh
fluoh pub create https://github.com/upstream/package.git \
  --sdk 3.35.8-ohos-0.0.3 \
  --repo git@github.com:FlutterOH/package.git
```

The command only configures local remotes. It does not create remote repositories and does not depend on GitHub CLI because upstream packages may be hosted outside GitHub. Maintainers must make sure the target remote repository exists before manually pushing branches or release tags.

`fluoh pub create` stages the generated `AGENTS.md`, `FLUOH.md`, `FLUOH_CHANGELOG.md`, `fluoh.yaml`, and `fluoh_test/` when the selected package is a Flutter package or plugin, but intentionally does not create the initial commit. Maintainers can keep adapting and commit everything together. Commit with the maintainer Git identity before running any command that requires a clean worktree:

```sh
git commit -m "feat(pub): initialize FlutterOH adapter"
```

Use `fluoh pub sync` to fast-forward the clean upstream branch from `upstream`, then `fluoh pub adapt` to merge that branch into the current pub branch and refresh `fluoh.yaml`.

Use `fluoh_test/test` for automated adapter checks that must pass before release, and `fluoh_test/example` as the small manual verification app. `fluoh test run` runs the adapter package's own Flutter tests when `test/**/*_test.dart` exists, equivalent to `fluoh flutter test` in the package path, then executes the `fluoh_test` automated checks from the selected Flutter OHOS SDK.

`fluoh pub release` must continue to guarantee:

- It only runs on `ohos/*` branches.
- The current branch matches the `ohos/<sdk-series>` branch inferred from `fluoh.yaml`.
- The worktree is clean.
- The SDK tag comes from configured sources.
- The manifest release version is newer than previous release tags for the same package, upstream version, and SDK.
- Missing or incomplete `FLUOH_CHANGELOG.md` release notes are reported as warnings, not release blockers.
- Package Flutter tests and `fluoh_test` pass through `fluoh test run` for Flutter adapter packages.
- The release tag matches the package, upstream version, SDK tag, and release version recorded in the manifest.

Adapter repository release commands must not write FlutterOH/pub source metadata directly. Register released adapters through a FlutterOH/pub pull request or the scheduled source ingestion process.
