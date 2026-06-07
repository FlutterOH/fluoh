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

## Interaction Evidence

Use `No interaction required: <reason>` only when the package has no
device-side interaction flow such as permission, picker, camera, location,
media, deep link, external app, or host-specific behavior.
Otherwise include at least one concrete row. Scenario notes should live under
`.fluoh/scenarios/<package-or-scope>/`.

| Scenario | Method | Platform | Target | Result | Evidence / blocker |
| --- | --- | --- | --- | --- | --- |
| `...` | integration_test \| AI-assisted \| manual | OHOS | device-or-emulator | passed | steps, functional assertions, Flutter debug/widget/semantic/log evidence, flutterRunSession/VM Service evidence when available; screenshots optional |

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
