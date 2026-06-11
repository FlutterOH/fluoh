# Repository Guidelines

## Project Scope

`fluoh` is a Dart CLI package for FlutterOH workflows. It manages FlutterOH SDKs, checks dependency implementation status, rewrites project dependency declarations, runs platform build and device workflows, and helps maintain third-party FlutterOH package repositories. Keep user-facing behavior predictable: commands should be repeatable, report what changed, and preserve local work when network or GitHub automation fails.

## Repository Layout

- `bin/fluoh.dart`: main executable entry point.
- `bin/fluohf.dart`: shortcut entry point for `fluoh flutter <args>`.
- `lib/fluoh.dart`: public package API and command runner export.
- `lib/src/cli/`: command runner wiring, usage formatting, machine output, and bundled skill metadata.
- `lib/src/context/` and `lib/src/config/`: runtime environment and persisted project/tool configuration.
- `lib/src/schema/`: internal YAML/JSON/text schema models, validation, canonical generation, and pure rewrite rules.
- `lib/src/source/`: FlutterOH Source registry, source snapshot loading, validation, sync, and lock maintenance.
- `lib/src/project/create_command.dart`: top-level `create` command entry point.
- `lib/src/sdk/`: SDK listing, installation, removal, selection, and Flutter wrapper commands.
- `lib/src/platform/`: cross-platform target discovery, emulator/simulator helpers, and OHOS toolchain helpers.
- `lib/src/deps/`: project dependency analysis, policy, plan, pubspec rewrite helpers, and top-level `deps` command entry points.
- `lib/src/workflow/commands/`: workflow command entry points for `plan`, `verify`, `build`, `run`, `drive`, and `report`.
- `lib/src/workflow/`: shared workflow result models, automation scenarios, and platform automation helpers.
- `lib/src/clean/`: cleanup of tool-owned cache artifacts.
- `lib/src/package/`: package repository create, sync, and release workflows.
- `lib/src/doctor/` and `lib/src/upgrade/`: command-specific implementations.
- `skills/fluoh/`: bundled AI agent workflow, helper scripts, and report templates.
- `test/`: unit, command, integration, fixture, and release artifact tests.
- `doc/commands.md` and `doc/commands.zh-CN.md`: command design, command surface, workflow, and state ownership docs.
- `doc/schema.md`: current schema design and ownership boundaries.
- `Formula/`: Homebrew packaging.
- `.github/workflows/`: CI, issue/PR maintenance, and pub.dev publishing automation.

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

User-facing CLI output should distinguish sentence text from field-like values. Do not add a trailing period to short status fragments, paths, URLs, versions, identifiers, command names, or values after labels such as `SDK path: ...`, `Dart version ...`, `Branch ...`, or `No SDK selected`. Use punctuation only for complete explanatory sentences, multi-sentence guidance, help text, and raw tool output that is intentionally preserved.

Prefer structured parsing for YAML, lockfile, and source index data. Avoid ad hoc string edits when a local parser or helper already exists. When pubspec text must be rewritten, preserve unrelated user content and add regression tests for the exact layout being changed.

Commands that modify a project or package repository must be conservative:

- Fail before destructive writes when validation is incomplete.
- Preserve local repositories and working trees on network, GitHub, or push failures.
- Do not delete user-owned directories unless they are known `fluoh` artifacts.
- Print concise summaries of changes and next steps.

Commands that support `--json` must use the shared machine-output contract:
write exactly one JSON object to stdout with top-level `schema`,
`command`, `ok`, and `exitCode`, then keep command-specific fields at the top
level. Keep human progress text off stdout/stderr while JSON mode is active.

## Command Surface and State Ownership

Top-level commands are wired in `lib/src/cli/fluoh_command_runner.dart`. Keep the command table in `doc/commands.md` and `doc/commands.zh-CN.md` aligned when adding, removing, renaming, or moving commands.

- Fluoh commands: `skill`, `flutter`, `doctor`, `clean`, and `upgrade`; `fluohf` is the `flutter` shortcut.
- SDK and Metadata commands: `sdk` and `source`.
- Project commands: `create` and `deps`.
- Package commands: `package` owns package repository lifecycle, handoff, and release tasks.
- Workflow commands: `plan`, `verify`, `build`, `run`, `drive`, and `report`.
- Device commands: `devices` and `emulators`.

State must have one owner. Do not bypass these owners in command implementations or tests:

- `$FLUOH_HOME/config.json`: Source configuration and first default Source initialization through `lib/src/source/`.
- `$FLUOH_HOME/sources/<name>` and `$FLUOH_HOME/sources.lock.json`: Source runtime snapshots and lock generation in `lib/src/source/`.
- `$FLUOH_HOME/sdks/<version>`: SDK install, remove, and on-demand wrapper setup in `lib/src/sdk/`.
- `$FLUOH_HOME/cache/`: cleanable runtime artifacts produced by workflow, platform, and package commands; cleanup is owned by `fluoh clean`.
- Project `fluoh.yaml` and `.fluoh/flutter_sdk`: SDK selection and dependency workflow configuration.
- Project `pubspec.yaml`: `deps` command entry points under `lib/src/deps/commands/`, using rewrite helpers under `lib/src/deps/`.
- FlutterOH package repository `fluoh.yaml`, generated docs, examples, and release metadata: package workflow commands under `lib/src/package/`.
- Source root and Manifest files: `source init`, `source sync`, and Source validation commands.

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

Command design details belong in `doc/commands.md` and `doc/commands.zh-CN.md`. Keep those files as the source of truth for command behavior, state ownership, workflow sequencing, and machine-readable output details.

AI-driven adaptation routing belongs in `skills/fluoh/SKILL.md`. Detailed app, package, automation, Source, report, and scenario flows belong in `skills/fluoh/references/` and the referenced helper scripts/templates. Keep README links and `fluoh skill` metadata aligned, but do not duplicate the full skill workflow in public docs or this file.

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
