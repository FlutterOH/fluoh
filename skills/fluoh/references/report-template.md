# fluoh AI Report Template

```md
# fluoh AI Report

- Scope:
- Repository:
- Package:
- Upstream version:
- FlutterOH SDK:
- Date:
- Recommendation: ready | needs maintainer decision | blocked

## Summary

- ...

## Adaptation Responsibility

- AI owns adaptation implementation, project/package rewrites, command
  execution, evidence collection, report composition, and release
  recommendation.
- The maintainer owns final release approval and any publish, push, tag, store, or release action.
- `manual-assisted` means a person operated a device or emulator, but pass/fail
  still requires tool-readable confirmation such as logs, meaningful session
  state beyond launch, stable text, semantics, test keys, command JSON, hilog,
  or app log markers.

## Changes

- ...

## Public API / Compatibility

- Public Dart API changes:
- Dependency constraint changes:
- Non-OHOS regression risk:

## Official Platform Basis

For platform plugins, cite the official OHOS/OpenHarmony or vendor SDK
documentation reviewed before implementation. Include unavailable or
not-applicable dispositions explicitly; do not leave this section blank for a
ready recommendation.

| Topic | Source | Decision / impact |
| --- | --- | --- |
| `...` | official docs URL, SDK API path, or `blocked: <reason>` | implementation and test impact |

## Commands

| Command | Exit | Result | Notes |
| --- | --- | --- | --- |
| `...` | 0 | passed | ... |

## Delivery Checklist

- [ ] Diff reviewed; unrelated files, local paths, generated caches, credentials, and private tokens excluded.
- [ ] Commands table includes exit codes and enough evidence to reproduce the decision.
- [ ] Existing package/app tests, example tests, and `integration_test/` were
  inspected against public API, platform interfaces, permissions, and behavior
  paths before final verification.
- [ ] Missing or weak functional tests were added or repaired before final verification, or a concrete blocker is recorded.
- [ ] Official OHOS/platform documentation basis was reviewed before implementation, or a concrete unavailable/not-applicable reason is recorded.
- [ ] OHOS build evidence recorded.
- [ ] OHOS run evidence recorded, or the missing device/emulator blocker is explicit.
- [ ] Every existing Android, iOS, macOS, Linux, Web, and Windows platform was
  functionally checked when supported by the current host/toolchain, or exact
  diagnostic evidence and skip reason are recorded.
- [ ] Interaction automation evidence recorded through a passed
  `flutter test integration_test -d <device>` command or real
  `fluoh drive --json`, with no unresolved ready-blocking gates.
- [ ] Functional interaction evidence recorded for permission, file, camera, location, media, deep link, external-app, or other device workflows.
- [ ] Public API, dependency constraints, and non-OHOS regression risk reviewed.
- [ ] Remaining risks and release decision are explicit.

## Independent Review

This section records the host-agent supervision loop after `check_report.py`
passes. It is not a fluoh CLI gate; a separate reviewer agent owns the
judgment, and the adaptation AI owns repairs.

- Reviewer agent: not started
- Verdict: pending
- Feedback packet location: pending independent review
- Repair loop: pending independent review

| ID | Severity | Area | Evidence | Required repair | Validation | Status |
| --- | --- | --- | --- | --- | --- | --- |
| IR-000 | info | review | independent review not started | start reviewer agent after `check_report.py` passes | reviewer verdict recorded | pending |

## Platform Matrix

For each platform directory that exists in the package/app or example, record
passed functional evidence: build/run plus `integration_test`, `fluoh drive`, or
tool-readable manual-assisted assertions when behavior requires interaction.
Use `not present` only when the platform directory is absent. Use `skipped` only
with the exact unsupported host/toolchain diagnostic command and blocker.

| Platform | Build | Run | Integration test | Target | Evidence / blocker |
| --- | --- | --- | --- | --- | --- |
| OHOS | skipped | skipped | n/a | n/a | ... |
| Android | not present | not present | n/a | n/a | ... |
| iOS | not present | not present | n/a | n/a | ... |
| macOS | not present | not present | n/a | n/a | ... |
| Linux | not present | not present | n/a | n/a | ... |
| Web | not present | not present | n/a | n/a | ... |
| Windows | not present | not present | n/a | n/a | ... |

## Automation Coverage

Copy the complete required `automation.coveragePolicy.qualityGates` set from
`fluoh drive --dry-run --json` or real `fluoh drive --json`; do not omit
generic gates that are `notApplicable` for the current Package. A `ready`
release certification cannot include unresolved statuses such as
`needsInventory`, `needsCapabilityCoverageRows`, `needsPermissionCoverageRows`,
`needsPathCoverageReview`, `needsFunctionalEvidence`,
`needsPageReadinessEvidence`, `blocked`, or `failed`.
Record `automation.coveragePolicy.status`, `readyForAutomation`, and
`qualityGateSummary` before the table so the handoff shows whether coverage is
ready to execute, still missing rows, or waiting on maintainer/environment
decision. Ready reports must show zero not-ready gates, such as
`qualityGateSummary: ready=10, notReady=0`.
When `existing-test-baseline` is not ready, include the concrete
`coverageBaseline.missingPackageTests` and
`coverageBaseline.weakPackageTests` rows that were fixed or remain blocked,
including the printed `testCommand` or accepted alternative command used to
verify each focused Package test.
Also record `automation.repairPlan.nextStep` when any gate is not ready, so the
handoff shows the exact next machine-readable repair action, its `doneWhen`
completion checks, and the `validation` rerun hint. Include
`automation.rerunCommand` whenever the next validation step repeats the same
`drive` invocation.

- coveragePolicy.status: ...
- readyForAutomation: ...
- qualityGateSummary: ...

| Gate | Status | Evidence / blocker |
| --- | --- | --- |
| coverage-inventory | readyForReview | capability inventory reviewed |
| coverage-metadata | readyForReview | every scenario declares coverage metadata or has an explicit no-interaction reason |
| coverage-items | readyForReview | every applicable capability has a coverage row |
| capability-inventory-coverage | readyForReview | all public API/platform/example rows covered or notApplicable |
| blocked-coverage | readyForReview | no capability row remains blocked; demo defects and missing automation were repaired |
| scenario-evidence-assertions | readyForReview | covered scenarios use functional interaction evidence such as assertText/waitText/assertLog; assertSession and screenshots are launch evidence only |
| page-readiness | readyForReview | post-launch functional page state asserted or no launch scenario required |
| existing-test-baseline | readyForReview | package and integration tests reviewed |
| manifest-permission-coverage | readyForReview | every selected-platform manifest permission is covered or notApplicable |
| behavior-paths | readyForReview | success and negative/error paths are covered or explicitly explained |

## Interaction Evidence

Use `No interaction required: <reason>` only when the package has no
device-side interaction flow such as permission, picker, camera, location,
media, deep link, external app, or host-specific behavior.
Otherwise include at least one concrete row. Use `integration_test` when the
flow is encoded under `integration_test/`; the Commands table must include the
passed `flutter test integration_test -d <device>` command row, whether the
test was run directly or by `fluoh run`. Use `manual-assisted` only when the
user had to operate a device or emulator during adaptation, and mark it passed
only after recording what was checked plus the environment, target id, visible
status, log marker, meaningful session state beyond launch, stable text,
semantics, test keys, command JSON, hilog, app log marker, or other
tool-readable confirmation.
Scenario notes should live under `.fluoh/scenarios/<package-or-scope>/`.

| Scenario | Method | Platform | Target | Result | Evidence / blocker |
| --- | --- | --- | --- | --- | --- |
| `...` | integration_test \| AI-assisted \| manual-assisted | OHOS | device-or-emulator | passed | functional assertions plus debug/semantic/log evidence; screenshot or UI-state evidence for mobile runs |

## Diagnostics

- ...

## Fluoh Feedback

Replace this section with either `No fluoh feedback: <reason>` or concrete
feedback rows from `collect_feedback.py`. If JSON contains `traceError`, record
the local trace-evidence issue here.

| ID | Owner | Category | Evidence | Proposed fluoh change | Status |
| --- | --- | --- | --- | --- | --- |

## Signing

- Mode:
- Generated HAPs (build-only when applicable):
- Run session / output log:
- Hilog (drive/debug scenarios only):

## Remaining Risks

- ...

## Local State

- Git status summary:
- Files intentionally left uncommitted:
- Files that must not be committed:

## Release Decision

Release recommendation: ready | needs maintainer decision | blocked

Reason:
```
