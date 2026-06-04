## Summary

- <!-- Describe the user-visible behavior or maintenance change. -->
- Related issue:

## Behavior and contracts

- [ ] Command behavior, pubspec rewrites, source index rules, SDK selection, package workflows, release validation, or publishing artifacts have regression tests.
- [ ] CLI output changes include essential output snippets when they clarify behavior.
- [ ] `--json` command changes preserve one stdout JSON object with `schema`, `command`, `ok`, and `exitCode`, with no progress text.
- [ ] Project or package modifying commands preserve local work on validation, network, GitHub, or push failures.

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

## Notes

- <!-- Add migration notes, follow-ups, or context that reviewers need. -->
