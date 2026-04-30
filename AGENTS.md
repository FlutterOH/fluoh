# Repository Guidelines

## Project Structure & Module Organization

This is a Dart CLI package for FlutterOH workflows. `bin/fluoh.dart` is the executable entry point and delegates to the public API in `lib/fluoh.dart`. Implementation code lives in `lib/src/`, grouped by domain: `cli/`, `context/`, `sdk/`, `source/`, `deps/`, `adapter/`, `doctor/`, `update/`, `upgrade/`, and `use/`. Tests live in `test/`, with command tests under `test/commands/`, domain tests such as `test/sdk/`, integration coverage under `test/integration/`, shared helpers in `test/helpers/`, and static fixtures in `test/fixtures/`. Homebrew packaging is in `Formula/`, and pub.dev publishing automation is in `.github/workflows/publish.yml`.

## Build, Test, and Development Commands

- `dart pub get`: install package dependencies from `pubspec.yaml`.
- `dart run bin/fluoh.dart --help`: run the CLI locally without global activation.
- `dart format .`: apply standard Dart formatting.
- `dart analyze`: run static analysis using `package:lints/recommended`.
- `dart test`: run the full `package:test` suite.
- `dart pub publish --dry-run`: validate package metadata before publishing.

For release checks, run format, analysis, tests, and the publish dry run before tagging. Tags matching `vX.Y.Z` trigger the publish workflow.

## Coding Style & Naming Conventions

Use idiomatic Dart formatted by `dart format` with two-space indentation. Keep file names in `snake_case.dart`, classes and enums in `PascalCase`, and functions, fields, variables, and command names in `lowerCamelCase`. Prefer focused command classes and domain helpers in the matching `lib/src/<domain>/` directory. Public exports should remain intentional in `lib/fluoh.dart`; keep internal implementation details under `lib/src/`.

## Testing Guidelines

Tests use `package:test`. Name files `*_test.dart` and write behavior-oriented test names such as `test('lists, installs, reports current, and removes SDKs', ...)`. Use `test/helpers/fluoh_test_context.dart` for isolated environments and add fixtures under `test/fixtures/` when command behavior depends on repositories or generated source indexes. There is no explicit coverage threshold, but every command or parser behavior change should include a focused regression test.

## Commit & Pull Request Guidelines

The current history only establishes `Initial commit`, so use concise imperative commit subjects, optionally scoped, for example `sdk: handle missing release dates`. Pull requests should describe the user-visible behavior change, list verification commands run, link related issues, and call out release or publishing impact. Include CLI output snippets when they clarify behavior; screenshots are usually unnecessary for this repository.

## Security & Configuration Tips

Do not commit local caches, credentials, or machine-specific SDK paths. The CLI stores runtime state under `$FLUOH_HOME` or `$HOME/.fluoh`; tests should use temporary directories instead of real user configuration.
