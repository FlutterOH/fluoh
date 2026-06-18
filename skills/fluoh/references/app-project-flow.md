# App Project Flow

Use this workflow when the user asks to make an existing Flutter app support
OHOS.

## End-to-End Contract

Use `scripts/preflight.py` or `fluoh plan app --json` as the machine runbook.
App support is not complete after SDK setup, dependency rewrite, HAP
build, launch, or a screenshot. Continue until the delivery gate is satisfied,
an explicit blocker remains, or a maintainer decision is required.
After each successful mobile run, capture at least one screenshot or equivalent
UI-state artifact and verify the app reached the expected functional screen.
If the page is blank, stuck on splash, visually hidden, or otherwise abnormal,
repair that page before continuing to broader automation.

## Commands

```sh
fluoh task start --type appSupport --scope <scope> --json
fluoh source update
fluoh sdk use <sdk-version-or-line> --pub-get
fluoh deps check --json
fluoh deps fix --dry-run --json
fluoh deps fix
fluoh deps get
fluoh doctor --platform ohos --project --json --strict
fluoh build ohos --auto-sign --json --trace
fluoh devices --platform ohos --json
fluoh emulators --platform ohos --json
fluoh run ohos --auto-emulator --json --trace
fluoh drive ohos --json --trace
fluoh report create --scope <scope> --json
python3 <skill-dir>/scripts/check_report.py <report-path>
```

## Rules

- `fluoh sdk use` creates `ohos/` by default when missing. Add
  `--no-init-ohos` only when another workflow owns platform creation.
- Start or reuse one current task before collecting trace, screenshot, run
  session, and report evidence. `fluoh plan app --json` and preflight already
  put `fluoh task start --type appSupport --scope <scope> --json` at the front
  of the command queue.
- Run `fluoh deps fix --dry-run` before writing dependency changes. In
  fully automatic support requests, apply `fluoh deps fix` only after the
  plan contains expected FlutterOH replacements. In review-only requests, stop
  at the dry-run and report proposed changes.
- If `fluoh deps check --json` reports unavailable, blocked, or SDK-mismatch
  dependencies, record them as blockers or maintainer decisions. Do not invent
  package implementations inside the app project unless asked.
- Prefer `fluoh run ohos --auto-emulator --json` so fluoh starts a
  local DevEco emulator before falling back to connected devices.
- Treat successful `fluoh run` as launch smoke only. Follow
  `workflowEvidence.toolCommands` with `fluoh drive`, screenshot capture, page
  assertions, and full interaction automation before claiming ready.
- Every failing JSON command enters the repair loop: parse diagnostics and log
  tails, inspect trace feedback candidates, patch the smallest owned issue,
  rerun the failed command or its `nextCommand`, and record the result.
- When `integration_test/` exists, `fluoh run ohos ...` executes it on the
  selected OHOS target after the launch smoke check.
- For explicit real runs, use `--device-id <id>` from
  `fluoh devices --platform ohos --json`.
- Use `--emulator <name>` only when selected from
  `fluoh emulators --platform ohos --json`.
- When multiple OHOS emulators expose API metadata, cover both the lowest and
  highest API versions before claiming broad compatibility.
- A signed HAP build is build-only evidence when no local target can be
  started.
- Create small local checkpoint commits after completed phases with clean
  command evidence. Push, release, force-push, and destructive Git commands
  still require separate maintainer approval.

## Evidence

Record the commands, exit codes, selected SDK, dependency changes, signing mode,
device or emulator id, `flutterRunSession` path, `flutter run` result,
integration-test result when present, runtime logs, and any remaining
environment blockers in the completion report. HAP paths are build-only
evidence unless the run came from an explicit debug-tool flow.

Before the final response, run the preflight or plan `finalCheckCommands`,
create the canonical report under the current `.fluoh` task, run `check_report.py`
against that report, and state exactly one final state: `ready`, `blocked`, or
`needs maintainer decision`.
