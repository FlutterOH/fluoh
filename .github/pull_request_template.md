## Summary

- <!-- Describe the user-visible behavior or maintenance change. -->

## Related issue

- Closes:
- Related:

## Scope

- [ ] CLI behavior
- [ ] JSON contract
- [ ] SDK, Source, or Flutter wrapper workflow
- [ ] Project creation or dependency workflow
- [ ] Package repository workflow
- [ ] App workflow: plan, verify, build, run, attach, drive, or report
- [ ] Devices, emulators, or platform tooling
- [ ] Doctor, clean, upgrade, or skill command
- [ ] Pubspec, Source, package, or release metadata
- [ ] Documentation, generated guidance, or release artifacts
- [ ] GitHub automation, publishing, or packaging

## Behavior and contracts

- [ ] User-visible behavior is described with essential output snippets when useful.
- [ ] Commands that support `--json` still emit exactly one stdout JSON object with `schema`, `command`, `ok`, and `exitCode`.
- [ ] Project or package modifying commands validate before writes and preserve local work on validation, network, GitHub, or push failures.
- [ ] Public Dart APIs and generated guidance have useful doc comments or documentation updates.
- [ ] Behavior changes have focused regression tests, or the test gap is explained below.

## Verification

- [ ] `dart format .`
- [ ] `dart analyze`
- [ ] `dart test`
- [ ] `dart pub publish --dry-run` for publishing metadata or packaging changes.

## Release impact

- [ ] No release or packaging impact.
- [ ] Updates release artifacts, pub.dev metadata, Homebrew packaging, or documented release behavior.
- [ ] Version metadata stays aligned across `pubspec.yaml`, `lib/src/version.dart`, `CHANGELOG.md`, and `Formula/fluoh.rb`.
- [ ] Documentation or release surface changes update `test/release/release_artifacts_test.dart`.

## Reviewer notes

- <!-- Add migration notes, follow-ups, test gaps, or reviewer context. -->
