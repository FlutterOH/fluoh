# Contributing to fluoh

简体中文: [CONTRIBUTING.zh-CN.md](CONTRIBUTING.zh-CN.md)

This document is for `fluoh` contributors and maintainers. General users should start with [README.md](README.md) or [README.zh-CN.md](README.zh-CN.md).

## Local Development

Install dependencies after preparing a Dart SDK:

```sh
dart pub get
```

Run the CLI locally:

```sh
dart run bin/fluoh.dart --help
dart run bin/fluoh.dart --version
```

To debug with the same `fluoh` command users run after installation, globally activate the current source checkout as a local path package from the repository root:

```sh
dart pub global activate --source path . --overwrite
fluoh --version
```

If your shell cannot find `fluoh`, make sure Dart pub's global executable directory is on `PATH`:

```sh
export PATH="$HOME/.pub-cache/bin:$PATH"
```

After this, `fluoh` in your shell points at this repository's source. Code changes usually do not require reactivation; rerun the `dart pub global activate` command when changing executables or package metadata.

To debug a version already published on pub.dev, activate the hosted package:

```sh
dart pub global activate fluoh --overwrite
fluoh --version
```

To debug a specific published version, add the version after the package name:

```sh
dart pub global activate fluoh 0.0.1 --overwrite
fluoh --version
```

After debugging, use `dart pub global activate --source path . --overwrite` to switch back to the local source version, or deactivate the globally activated `fluoh`:

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

`dart format .` should not leave unreviewed formatting diffs. If it changes files, review and include those changes in the commit. `dart analyze` and `dart test` must pass before committing.

GitHub Actions runs the same checks on pushes to `main`, version tags, and pull requests. The pub.dev publishing workflow must pass these checks before publishing:

- `dart format --output=none --set-exit-if-changed .`
- `dart analyze`
- `dart test`

Run this additional check before publishing:

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

Also check that staged changes do not contain local absolute paths. Do not commit local IDE, system, or build output files such as `.idea/`, `.vscode/`, `.DS_Store`, `.dart_tool/`, `build/`, or `coverage/`.

`pubspec.lock` may be committed for this CLI application. Before publishing, make sure the version metadata in `pubspec.yaml`, `lib/src/version.dart`, `CHANGELOG.md`, and `Formula/fluoh.rb` is consistent.

## Commit Format

Commit messages use Conventional Commits:

```text
<type>(<scope>): <subject>
```

`scope` is optional. Prefer the affected command, module, or documentation area, such as `sdk`, `deps`, `pub`, `source`, `docs`, or `ci`.

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
fix(deps): update rewritten OHOS dependencies
docs: add Homebrew installation guide
ci: publish package on version tags
```

Use an imperative or concise English subject. Keep the first line within 72 characters. Add a body after a blank line when background, risk, or verification details are useful.

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
brew tap FlutterOH/fluoh https://github.com/FlutterOH/fluoh
brew install FlutterOH/fluoh/fluoh
fluoh --version
```

When an official `brew tap FlutterOH/tap` is available, sync the formula into the FlutterOH tap repository. The current formula uses the pub.dev archive as its download source; update the archive URL and version whenever releasing a new version.

## Pub Repository Workflow Maintenance

`fluoh pub create` keeps the upstream default branch clean, keeps the clone source as `upstream`, creates an `ohos/<sdk-tag>` pub branch, and sets `origin` to the final pub repository push target. The default is derived from the package name:

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

Use `fluoh pub sync` to fast-forward the clean upstream branch from `upstream`, then `fluoh pub adapt` to merge that branch into the current pub branch and refresh `fluoh.yaml`.

`fluoh pub release` must continue to guarantee:

- It only runs on `ohos/*` branches.
- The current branch matches the pub branch in `fluoh.yaml`.
- The worktree is clean.
- The SDK tag comes from configured sources.
- The release tag matches the package, upstream version, SDK tag, and release version recorded in the manifest.
