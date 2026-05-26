# Repository Guidelines

## Project Scope

`fluoh` is a Dart CLI package for FlutterOH workflows. It manages Flutter OHOS SDKs, checks dependency implementation status, rewrites project dependency declarations, and helps maintain third-party FlutterOH package repositories. Keep user-facing behavior predictable: commands should be repeatable, report what changed, and preserve local work when network or GitHub automation fails.

## Repository Layout

- `bin/fluoh.dart`: executable entry point.
- `lib/fluoh.dart`: public package API and command runner export.
- `lib/src/cli/`: command runner wiring.
- `lib/src/context/` and `lib/src/config/`: runtime environment and persisted project/tool configuration.
- `lib/src/schema/`: internal YAML/JSON/text schema models, validation, migration, canonical generation, and pure rewrite rules.
- `lib/src/source/`: FlutterOH data source registry and YAML source loading.
- `lib/src/sdk/`: SDK listing, installation, removal, and release selection.
- `lib/src/deps/`: project dependency analysis and rewrite commands.
- `lib/src/package/`: package repository create, sync, and release workflows.
- `lib/src/doctor/` and `lib/src/upgrade/`: command-specific implementations.
- `test/`: unit, command, integration, fixture, and release artifact tests.
- `docs/schema.md`: current schema design and ownership boundaries.
- `Formula/`: Homebrew packaging.
- `.github/workflows/publish.yml`: pub.dev publishing automation.

## Development Commands

Run these from the repository root:

- `dart pub get`: install dependencies.
- `dart run bin/fluoh.dart --help`: run the CLI locally.
- `dart format .`: apply Dart formatting.
- `dart analyze`: run static analysis.
- `dart test`: run the full test suite.
- `dart pub publish --dry-run`: validate package metadata before publishing.

Before committing, `dart format .`, `dart analyze`, and `dart test` are mandatory. Formatting must be applied and reviewed; analysis and tests must pass.

`.github/workflows/ci.yml` enforces formatting, analysis, and tests on pushes to `main`, version tags, and pull requests. `.github/workflows/publish.yml` must run the same checks before publishing to pub.dev. Keep CI aligned with the documented pre-commit and release requirements.

If a local shell has multiple Dart installations, using an explicit Dart SDK path is fine for local verification, but never commit machine-specific absolute paths.

## Coding Standards

Use idiomatic Dart and keep formatting delegated to `dart format`. File names are `snake_case.dart`; classes, enums, and extensions are `PascalCase`; functions, fields, variables, and command identifiers are `lowerCamelCase`.

Keep command classes focused on argument parsing and user-visible output. Put reusable behavior in the matching domain helper under `lib/src/<domain>/`. Keep internal implementation under `lib/src/`; only export intentional public API from `lib/fluoh.dart`.

Prefer structured parsing for YAML, lockfile, and source index data. Avoid ad hoc string edits when a local parser or helper already exists. When pubspec text must be rewritten, preserve unrelated user content and add regression tests for the exact layout being changed.

Commands that modify a project or package repository must be conservative:

- Fail before destructive writes when validation is incomplete.
- Preserve local repositories and working trees on network, GitHub, or push failures.
- Do not delete user-owned directories unless they are known `fluoh` artifacts.
- Print concise summaries of changes and next steps.

## Testing Standards

Use `package:test`. Name test files `*_test.dart` and write behavior-oriented test names. Prefer command tests for CLI behavior and focused domain tests for parsers or selection logic.

Use `test/helpers/fluoh_command_context.dart` for isolated temporary homes, projects, and repositories. Put static source indexes and mock repositories under `test/fixtures/`. Do not read or write real user configuration such as `$HOME/.fluoh`.

Every command behavior change, pubspec rewrite, source index rule, SDK selection rule, package workflow, release validation, or publishing artifact change should include a regression test. For documentation or packaging changes, update `test/release/release_artifacts_test.dart` when the expected release surface changes.

Documentation and generated-guidance tests should protect stable release contracts and structure, not exact prose. They should verify that the feature or workflow is usable, not that every description keeps the same wording.

- Prefer structured parsing for generated YAML, JSON, Markdown sections, and command output when a parser or local helper is available.
- Assert stable contracts: required files, schema keys, package names, versions, paths, command names, links, headings, non-empty generated sections, and positive/negative workflow outcomes.
- Avoid broad `contains(...)` checks for full sentences, explanatory paragraphs, translated wording, comments, or guidance prose. Short stable tokens are acceptable when they are part of the contract, such as command names, schema keys, release tags, or file names.
- For generated README, FLUOH, AGENTS, schema, and command-design documents, check structure and required anchors rather than prose details. This keeps documentation editable for clarity without brittle test failures.
- For CLI output, assert the exit code, changed files or parsed result, and essential next-step command when needed. Do not require incidental progress text or descriptive wording unless that exact message is the behavior under test.

## Documentation Standards

`README.md` is the primary public document and should stay user-facing in English. `README.zh-CN.md` is the Simplified Chinese public document. Keep installation, quick start, core workflows, and command overview aligned between them.

Contributor and maintainer details belong in `CONTRIBUTING.md` and `CONTRIBUTING.zh-CN.md`, not in the public README. Keep both contribution documents aligned when changing development, verification, commit, release, or packaging rules.

`AGENTS.md` is for coding agents and maintainers working inside the repository. It should summarize current project conventions and link behavior through concrete files or commands, not duplicate long user documentation.

## Commit and PR Standards

Use Conventional Commits:

```text
<type>(<scope>): <subject>
```

Use scopes such as `sdk`, `deps`, `package`, `source`, `docs`, `ci`, `test`, or `release` when helpful. Common types are `feat`, `fix`, `docs`, `test`, `refactor`, `chore`, and `ci`. Keep the first line within 72 characters.

Pull requests should describe user-visible behavior, list verification commands, link related issues, and call out release or publishing impact. Include CLI output snippets when they clarify behavior.

## Release and Packaging Standards

Before publishing, run format, analysis, tests, and `dart pub publish --dry-run`. Version metadata must stay aligned across `pubspec.yaml`, `lib/src/version.dart`, `CHANGELOG.md`, and `Formula/fluoh.rb`.

Version tags use `vX.Y.Z` and must match `pubspec.yaml`. The GitHub Actions workflow publishes to pub.dev through OIDC; the package admin must keep the pub.dev automated publishing settings aligned with `FlutterOH/fluoh`, tag pattern `v{{version}}`, and environment `pub.dev`.

The Homebrew formula currently installs from the pub.dev archive. Update its archive URL and version when releasing a new package version, and sync it to the official FlutterOH tap when that tap is available.

## Security and Local State

Do not commit credentials, private tokens, local caches, IDE metadata, generated build output, or machine-specific SDK paths. Runtime state belongs under `$FLUOH_HOME` or `$HOME/.fluoh`; tests must use temporary directories.

For this tool repository, commit-time cleanup mainly means removing machine-specific absolute paths produced by local runs, such as SDK paths, home directories, temporary directories, generated `local.properties` content, and tool cache paths.

Before committing, run `git status --short --ignored=matching`, `git diff --check`, and scan staged changes for local absolute paths, credentials, and private tokens.
