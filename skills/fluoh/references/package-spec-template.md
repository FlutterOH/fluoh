# <package> FlutterOH Spec

Use this template for `doc/fluoh/<package>/spec.md` after `fluoh package new`,
`fluoh package port`, or `fluoh package add` creates the branch-local spec.
Replace every `SPEC-TODO:` line and angle-bracket placeholder before
implementation. The spec follows the package branch, because API behavior and
FlutterOH SDK compatibility can differ by SDK line.

## Package

| Field | Value |
| --- | --- |
| Name | `<package>` |
| Origin | `created|ported` |
| Package path | `<package-path>` |
| FlutterOH SDK | `<sdk-version>` |
| SDK line | `<sdk-line>` |
| Branch | `ohos/<sdk-line>/<package>` |
| Source or upstream | SPEC-TODO: created spec source, or ported upstream repository URL. |
| Source version/ref/commit | SPEC-TODO: created spec revision, or ported upstream version/ref/commit. |

## Package Contract

- Purpose: SPEC-TODO: State the user-facing job this package must perform.
- Non-goals: SPEC-TODO: State intentionally unsupported behavior.
- Target platforms: SPEC-TODO: List every platform in scope, including
  implementation targets, preserved upstream platforms, unsupported platforms,
  and platforms blocked by host/toolchain or vendor constraints.
- Compatibility promise: SPEC-TODO: State whether public Dart API and
  existing upstream platform behavior must match upstream exactly.
- Acceptance evidence: SPEC-TODO: Name the command, test, scenario, screenshot,
  log, or manual-assisted evidence required before delivery.

## Public API

| API | Type | Inputs | Outputs/errors | Platform scope | Test/evidence |
| --- | --- | --- | --- | --- | --- |
| `<public-api>` | SPEC-TODO | SPEC-TODO | SPEC-TODO | SPEC-TODO | `<test-or-evidence>` |

## Platform Behavior

| Scope entry | Platform | Role | Expected behavior | Difference/risk |
| --- | --- | --- | --- | --- |
| `<scope-entry>` | ohos/android/ios/web/macos/linux/windows | implementationTarget/preserveBaseline/unsupported/manualRequired/notApplicable | SPEC-TODO | SPEC-TODO |

## Platform API Mapping

| Scope entry | Platform | Native/API basis | Permission/configuration | Device/signing constraint | Source |
| --- | --- | --- | --- | --- | --- |
| `<scope-entry>` | ohos | SPEC-TODO | SPEC-TODO | SPEC-TODO | SPEC-TODO |
| `<scope-entry>` | android/ios/web/macos/linux/windows | SPEC-TODO | SPEC-TODO | SPEC-TODO | SPEC-TODO |

## Examples

| Flow | Screen/control | Expected visible result | Automation hook |
| --- | --- | --- | --- |
| SPEC-TODO | SPEC-TODO | SPEC-TODO | SPEC-TODO |

## Tests and Evidence

| Scenario | Method | Platforms | Expected assertion | Status |
| --- | --- | --- | --- | --- |
| SPEC-TODO | unit/integration/drive/manual-assisted | SPEC-TODO | SPEC-TODO | planned |

## Support Scope Seeds

Use these rows to initialize `doc/fluoh/<package>/scope.yaml`.
Create one row for every target platform in scope for each P0 scope entry.

| Scope entry | Priority | Platform | Role | Decision | Reason/source | Test case |
| --- | --- | --- | --- | --- | --- | --- |
| `<scope-entry>` | P0 | ohos | implementationTarget | supported/degraded/unsupported/manualRequired/notApplicable | SPEC-TODO | SPEC-TODO |
| `<scope-entry>` | P0 | android/ios/web/macos/linux/windows | preserveBaseline | preserved/unsupported/manualRequired/notApplicable | SPEC-TODO | SPEC-TODO |

## Upstream Review Notes

For ported packages, record the reviewed upstream version/ref/commit, exported
Dart libraries, platform-interface or channel contract, example behavior,
tests, permissions, configuration, and existing platform implementation notes.
For created packages, record the confirmed user requirements and API decisions.

- SPEC-TODO: Reviewed baseline and decisions.

## Maintainer Decisions

- SPEC-TODO: Public API breaks, unsupported behavior, SDK line choices,
  signing/device constraints, external service requirements, or release
  decisions that require maintainer approval.
