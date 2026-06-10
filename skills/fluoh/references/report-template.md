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

## Changes

- ...

## Public API / Compatibility

- Public Dart API changes:
- Dependency constraint changes:
- Non-OHOS regression risk:

## Commands

| Command | Exit | Result | Notes |
| --- | --- | --- | --- |
| `...` | 0 | passed | ... |

## Delivery Checklist

- [ ] Diff reviewed; unrelated files, local paths, generated caches, credentials, and private tokens excluded.
- [ ] Commands table includes exit codes and enough evidence to reproduce the decision.
- [ ] OHOS build evidence recorded.
- [ ] OHOS run evidence recorded, or the missing device/emulator blocker is explicit.
- [ ] Android, iOS, macOS, Linux, Web, and Windows regression checks recorded when relevant.
- [ ] Real `fluoh automate --json` evidence recorded, with no unresolved ready-blocking gates.
- [ ] Functional interaction evidence recorded for permission, file, camera, location, media, deep link, external-app, or other device workflows.
- [ ] Public API, dependency constraints, and non-OHOS regression risk reviewed.
- [ ] Remaining risks and release decision are explicit.

## Platform Matrix

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
`fluoh automate --dry-run --json` or real `fluoh automate --json`; do not omit
generic gates that are `notApplicable` for the current Package. A `ready`
release certification cannot include unresolved statuses such as
`needsInventory`, `needsCapabilityCoverageRows`, `needsPermissionCoverageRows`,
`needsPathCoverageReview`, `needsEvidenceAssertions`, `blocked`, or `failed`.
Record `automation.coveragePolicy.status`, `readyForAutomation`, and
`qualityGateSummary` before the table so the handoff shows whether coverage is
ready to execute, still missing rows, or waiting on maintainer/environment
decision. Ready reports must show zero not-ready gates, such as
`qualityGateSummary: ready=8, notReady=0`.
When `existing-test-baseline` is not ready, include the concrete
`coverageBaseline.missingPackageTests` and
`coverageBaseline.weakPackageTests` rows that were fixed or remain blocked,
including the printed `testCommand` or accepted alternative command used to
verify each focused Package test.
Also record `automation.repairPlan.nextStep` when any gate is not ready, so the
handoff shows the exact next machine-readable repair action, its `doneWhen`
completion checks, and the `validation` rerun hint. Include
`automation.rerunCommand` whenever the next validation step repeats the same
`automate` invocation.

- coveragePolicy.status: ...
- readyForAutomation: ...
- qualityGateSummary: ...

| Gate | Status | Evidence / blocker |
| --- | --- | --- |
| coverage-inventory | readyForReview | capability inventory reviewed |
| coverage-metadata | readyForReview | every scenario declares coverage metadata or has an explicit no-interaction reason |
| coverage-items | readyForReview | every applicable capability has a coverage row |
| capability-inventory-coverage | readyForReview | all public API/platform/example rows covered or notApplicable |
| scenario-evidence-assertions | readyForReview | scenarios use assertText/waitText/assertLog/assertSession |
| existing-test-baseline | readyForReview | package and integration tests reviewed |
| manifest-permission-coverage | readyForReview | every selected-platform manifest permission is covered or notApplicable |
| behavior-paths | readyForReview | success and negative/error paths are covered or explicitly explained |

## Interaction Evidence

Use `No interaction required: <reason>` only when the package has no
device-side interaction flow such as permission, picker, camera, location,
media, deep link, external app, or host-specific behavior.
Otherwise include at least one concrete row. Use `manual-assisted` when the
user had to operate a device or emulator, and mark it passed only after
tool-readable evidence such as logs, session status, stable text, semantic
labels, or app log markers confirms the result. Scenario notes should live
under `.fluoh/scenarios/<package-or-scope>/`.

| Scenario | Method | Platform | Target | Result | Evidence / blocker |
| --- | --- | --- | --- | --- | --- |
| `...` | integration_test \| AI-assisted \| manual-assisted | OHOS | device-or-emulator | passed | steps, functional assertions, Flutter debug/widget/semantic/log evidence, flutterRunSession/VM Service evidence when available; screenshots optional |

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
- Generated HAPs:
- Hilog:

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
