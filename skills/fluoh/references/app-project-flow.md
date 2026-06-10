# App Project Flow

Use this workflow when the user asks to make an existing Flutter app support
OHOS.

## Commands

```sh
fluoh source update
fluoh sdk use <sdk-version-or-line> --pub-get
fluoh deps check --json
fluoh deps fix --dry-run
fluoh deps fix
fluoh deps get
fluoh doctor -p --platform ohos --json --strict
fluoh build --platform ohos --auto-sign --json
fluoh devices --platform ohos --json
fluoh emulators --platform ohos --json
fluoh run --platform ohos --auto-emulator --json
fluoh run --platform ohos --device <id> --json
```

## Rules

- `fluoh sdk use` creates `ohos/` by default when missing. Add
  `--no-init-ohos` only when another workflow owns platform creation.
- Run `fluoh deps fix --dry-run` before writing dependency changes. In
  fully automatic adaptation requests, apply `fluoh deps fix` only after the
  plan contains expected FlutterOH replacements. In review-only requests, stop
  at the dry-run and report proposed changes.
- If `fluoh deps check --json` reports unavailable, blocked, or SDK-mismatch
  dependencies, record them as blockers or maintainer decisions. Do not invent
  package implementations inside the app project unless asked.
- Prefer `fluoh run --platform ohos --auto-emulator --json` so fluoh starts a
  local DevEco emulator before falling back to connected devices.
- For explicit real runs, use `--device <id>` from
  `fluoh devices --platform ohos --json`.
- Use `--emulator <name>` only when selected from
  `fluoh emulators --platform ohos --json`.
- When multiple OHOS emulators expose API metadata, cover both the lowest and
  highest API versions before claiming broad compatibility.
- A signed HAP build is build-only evidence when no local target can be
  started.

## Evidence

Record the commands, exit codes, selected SDK, dependency changes, signing mode,
device or emulator id, HAP path, install or launch result, runtime logs, and any
remaining environment blockers in the completion report.
