# Package Support Flow

Use this workflow when the user asks to create a new FlutterOH package from a
spec or port a third-party Flutter package to FlutterOH.

## End-to-End Contract

The package support is not complete after repository creation, baseline
verification, HAP build, app launch, or a screenshot. Continue until exactly
one delivery state is justified:

- `ready`: implementation, package tests, target-platform build/run evidence
  including OHOS when in scope, applicable interaction automation,
  existing-platform build/run regression and required
  mobile drive coverage, canonical
  report, `check_report.py`, independent reviewer agent pass with no open
  blocker/high/medium feedback packet items, package handoff, and release
  check all pass.
- `needs maintainer decision`: code and evidence are as complete as the local
  environment allows, but release, publish, push, tag, signing policy, SDK
  line, upstream downgrade, public API break, or release version choice needs a
  maintainer decision.
- `blocked`: a concrete local toolchain, SDK, signing, device/emulator,
  upstream, or automation-evidence blocker remains after running the diagnostic
  command and the printed repair command or `nextCommand`.

Use `scripts/preflight.py` or `fluoh plan package --json` as the initial
machine runbook, then let `fluoh package next --package <name> --json` own the
implementation loop. If preflight reports `fluohSetup.status: needs-cli-setup`,
fix the fluoh executable or launcher and rerun preflight before `commandQueue`.
Execute only the current `nextAction`: run its command, make its required edit,
or stop on `blocked`, then rerun the reported `rerunCommand`. Do not maintain a
parallel checklist that can drift from `package next`, and do not skip `drive`,
report creation, report checks, `package handoff`, or `package check` when they
are emitted by `package next`, preflight, or the final gate.
After `package next` reaches `ready`, use `independent-review-flow.md` to start
a new read-only reviewer agent. Feed its feedback packet back into the support
repair loop, record repair/validation status, and repeat review before
claiming ready.
Treat `fluoh build all` and `fluoh run all` as matrix shortcuts for artifact
and launch-smoke evidence across existing project or package example platform
directories. Parse `workflowEvidence.observedEvidence`,
`collectedEvidenceKinds`, `notCollectedEvidenceKinds`,
`workflowContinuations`, and `toolCommands`; continue through `drive`,
scenario repair, report creation, and report checks before recommending ready.
After each successful mobile `run`, capture at least one screenshot or
equivalent UI-state artifact and verify the example app is on its expected
functional screen. If the demo is blank, stuck on a splash screen, visually
hidden, or otherwise abnormal, repair that demo page before continuing to
permission, gesture, callback, or platform regression automation.

Before final verification, inspect whether existing package tests, example
tests, and `integration_test/` cover the library's public API, platform
interfaces, permission flows, success paths, and denial/error paths. If they do
not, add or repair focused functional tests first. Do not defer missing tests
to the final report unless a concrete upstream, host, device, or toolchain
blocker prevents the test from being written or run.
For interaction packages, every applicable grant, deny, success, failure, and
error path must be automated through `integration_test/`, `fluoh drive`, or
manual-assisted tool-readable evidence. Coverage rows marked `blocked` are
repair backlog, not an acceptable final state.
`assertSession`, launch success, waits, and screenshots are only smoke or
visual sanity evidence. If drive JSON reports `needsFunctionalEvidence`, keep
the implementation AI in the repair loop until the scenario or test performs the
flow and asserts the resulting text, semantics, state, or log marker.
If drive JSON reports `needsPageReadinessEvidence`, repair the demo screen or
scenario until post-launch page state is asserted with text, semantics, or log
evidence instead of a screenshot alone.

## Canonical AI Flow

Use this as the phase map, but let `fluoh package next --package <name> --json`
choose the current action inside the loop:

1. **Resolve scope**: identify whether this is `origin.kind: created`
   (spec-first) or `origin.kind: ported` (upstream-first), output repository,
   package path/name, SDK line, Git author, repository URL/path, and whether the
   package needs a federated FlutterOH implementation package.
2. **Analyze package contract**: before mutating code, extract the package
   purpose, public Dart API, target platform matrix, per-platform behavior,
   platform API mapping candidates, example flows, test expectations, and
   acceptance evidence. For spec-first packages, derive this from the user
   requirements and ask for confirmation when the package contract is
   incomplete or contradictory. For upstream-first packages, derive it from the
   selected upstream version, exported Dart API, platform interface or
   channels, examples, tests, pubspec constraints, and existing platform
   implementations.
3. **Create or enter repository**: for spec-first packages, run
   `package new --plan --json` and then `package new`; for upstream-first
   packages, run `package discover`, `package port --plan --json`,
   `package port`, or `package add` only after the resolved scope is approved.
   Both origins must create or enter `ohos/<sdkLine>/<package>`.
4. **Record contract**: read `fluoh.yaml`, generated `FLUOH.md`,
   `doc/fluoh/<package>/spec.md`, public Dart API contract, example flows,
   tests, existing platform implementations, and relevant platform API sources
   for every target platform. Replace the generated spec TODOs with the
   reviewed contract before implementation. Use
   `references/package-spec-template.md` as the fill-in structure when the
   generated spec is too sparse. Generated spec TODOs and template placeholders
   are not accepted planning evidence. For ported packages, include the
   upstream version/ref/commit and the upstream API baseline that must be
   preserved.
5. **Plan scope**: initialize and complete
   `doc/fluoh/<package>/scope.yaml` before implementation; P0
   scope entries should be derived from the reviewed spec, public API surface,
   platform operations, examples, permission/configuration needs, and failure
   paths. P0 rows need per-platform support decisions, platform sources,
   implementation plan status where implementation is required, test cases, and
   evidence expectations.
6. **Implement and repair**: follow one `nextAction`; edit only the blocking
   package, example, test, scenario, or metadata surface; rerun the printed
   validation command.
7. **Collect evidence**: complete verify, target-platform build/run including
   OHOS when in scope, visual page-readiness, automation dry-run, functional
   automation run, supported existing-platform build/run regression, and
   mobile existing-platform drive dry-run/run
   coverage. Exploratory smoke is diagnostic only.
8. **Close evidence gaps**: update scope evidence, scenario coverage,
   integration tests, page assertions, report content, official platform basis,
   and blocked/notApplicable reasons until `package next` reaches `ready`.
   `package next` reaches `ready` only after the latest report passes the
   bundled `check_report.py` gate.
9. **Deliver**: after `package next` reaches `ready`, perform independent
   read-only review, repair feedback, then run the release-readiness commands
   from `nextAction.nextCommands`. These include `package status`,
   `package handoff`, and `package check --report` against the report path that
   `package next` validated. Release or push only after maintainer approval.

## Requirements And API Analysis

For spec-first packages, do not treat `package new` as the analysis step. First
shape a package contract from the user's request:

- package name, purpose, non-goals, target platforms, and whether it is a
  Flutter plugin or pure Dart package;
- public Dart libraries, classes, methods, streams, value types, errors,
  async/cancellation behavior, and platform-not-supported behavior;
- per-platform behavior, required native/platform APIs including
  OHOS/OpenHarmony or vendor APIs where applicable,
  permissions, configuration, signing/device-only constraints, preserved
  baselines, unsupported/not-applicable decisions, and expected differences;
- example app screens, controls, expected visible states, failure hints, and
  testable labels or keys;
- unit, integration, scenario, manual-assisted, and existing-platform regression
  evidence required before delivery.

If any of those values are missing, ask for the missing contract or state the
assumptions and get confirmation before running the mutating `package new`
command. After creation, replace the generated spec TODOs with the confirmed
contract using `references/package-spec-template.md` as the structure, then
initialize the support scope from the same rows.

For upstream-first packages, extract the contract from the selected upstream
baseline before implementation. Inspect at least `pubspec.yaml`, exported
`lib/` APIs, platform-interface packages or method-channel/event-channel
names, `android/`, `ios/`, `macos/`, `web/`, `linux/`, `windows/`, `example/`,
`test/`, and `integration_test/` when present. Summarize the upstream API
baseline, existing platform behavior, examples, tests, permission/configuration
requirements, and likely platform API mapping in
`doc/fluoh/<package>/spec.md`. Seed `doc/fluoh/<package>/scope.yaml`
from that spec before writing implementation code.

## Setup

For a new spec-first package repository, resolve package name, package purpose,
public Dart API, target platforms, example flows, test expectations, FlutterOH
repository name, output path, repository URL or path, local Git author name and
email, SDK line, package path, plugin template, and explicit `flutter create
--org` value when one is required. Do not implement until the package contract
is clear enough to seed `doc/fluoh/<package>/scope.yaml`.

For a ported package repository, resolve the FlutterOH repository name, output
path, repository URL or path, local Git author name and email, SDK line,
package path, upstream version when specified, and explicit `flutter create
--org` value when one is required.

When the upstream may be a monorepo and the user did not provide a package name
or package path, run:

```sh
fluoh package discover <upstream> --json
```

Present discovered Flutter plugin packages missing `ohos`, including package
names, paths, declared platforms, `supportProfile`, and `portCommand`
values. Use `supportProfile.categories`, `riskReasons`,
`requiredEvidence`, `suggestedCoverage`, `officialDocsRequired`,
`officialDocTopics`, and `blockerPolicy` as the initial capability inventory:
review the relevant official OHOS/OpenHarmony or vendor SDK documentation
before implementation, then seed package tests and scenario coverage from the
profile before inventing custom rows. If official docs are unavailable, keep
working but record the unavailable source and impact in the report before any
`ready` recommendation. If `complexity` is `external`, first record vendor SDK,
credential, service-account, or store/provider availability; keep the item in
the repair loop until the SDK path works or the report clearly needs a
maintainer decision. If a candidate contains `implementationRecommendation`,
prefer the federated path: create the recommended `<package>_ohos`
implementation package, add the missing platform `default_package` entry to
the app-facing package, and add the implementation dependency with the
recommended relative path.

For a spec-first package repository, first run a plan:

```sh
fluoh package new <package-name> --sdk <sdk-version-or-line> \
  --repository-name <flutteroh-repo-name> \
  --repository <flutteroh-repo-url-or-path> \
  --git-author-name <name> --git-author-email <email> \
  --plan --json
```

For an upstream-first package repository, first run a plan:

```sh
fluoh package port <upstream-git-url> --sdk <sdk-version-or-line> \
  --repository-name <flutteroh-repo-name> \
  --repository <flutteroh-repo-url-or-path> \
  --git-author-name <name> --git-author-email <email> \
  --package-path <path> --plan --json
```

Use the plan as the final support scope confirmation and wait for explicit
approval before running the mutating port command, `fluoh package add`,
local Git author changes, or implementation edits.

For an existing package repository, read `repository.git.url` from `fluoh.yaml`
and local Git author identity from `git config --local --get user.name` and
`git config --local --get user.email`. Ask for any missing or contradictory
support value before mutating files.

Before implementation edits, inspect preflight `upgradeChecks`. New package
branches already get a branch-local `doc/fluoh/<package>/spec.md` and a
freshly rewritten `FLUOH.md` from `package new`, `package port`, or
`package add`; there is no separate generated-context command.

## Repository Rules

- `fluoh package port` always gets an explicit `--repository-name` in AI
  automation.
- Branch-local requirements, API design, platform behavior, and test plans live
  in `doc/fluoh/<package>/spec.md`; use
  `references/package-spec-template.md` as the fill-in structure when needed.
  Generated quick context lives in `FLUOH.md`; metadata stays in `fluoh.yaml`.
  Do not create, rewrite, or stage upstream README or agent-policy files as
  fluoh-owned context.
- AI-driven creation always passes resolved `--repository`,
  `--git-author-name`, and `--git-author-email`; never pass only one author
  option.
- If the user wants to reuse local Git config, read it, show the resolved name
  and email, and treat that as the explicit author identity.
- Omitted package paths mean the root package only, not every package in a
  monorepo.
- Omitted upstream targets resolve to the latest valid release tag after
  fetching upstream tags, not to upstream HEAD when release tags exist.
- Use `--upstream-version <version>` only when specific same-or-newer
  upstream version. If the current upstream version is unusable, mark it
  `broken` instead of downgrading without maintainer approval.
- Use `fluoh package upstream check` and `fluoh package upstream sync` only for
  `origin.kind: ported`. Created packages have no upstream. After upstream
  sync, update `doc/fluoh/<package>/spec.md` so it references the current
  upstream version and commit before continuing `package next`.
- Use one FlutterOH support repository per upstream repository by default.
  For multiple packages, use `fluoh package queue <package-path>... --json`,
  implement one branch at a time, and use `fluoh package add <package-path>` for
  additional package branches.
- Prefer a fresh clone or separate Git worktree per existing package branch
  when verifying multiple branches.

## Implementation Loop

Before implementation work, run the package state machine:

```sh
fluoh package next --package <name> --json
```

`package next` reuses the current local task and creates one when none exists,
so trace, visual-readiness, report, and handoff evidence share one `.fluoh`
task context. This local task state is not package source implementation.

When `nextAction` asks for scope initialization or edits, maintain
`doc/fluoh/<package>/scope.yaml` with the package support scope:

```sh
fluoh package scope init --package <name> --json
fluoh package scope check --package <name> --json
fluoh package scope status --package <name> --json
```

`scope init` reads concrete rows from the spec's `Support Scope Seeds` table by
default. Use `--no-from-spec` only when the seed table is stale or intentionally
empty.

The support scope is the planning and evidence contract. P0 scope entries must record
per-platform support decisions, platform research sources or
unsupported/not-applicable/manual reasons, implementation plan status where
implementation is required, test cases, and functional or regression evidence
for supported, degraded, or preserved scope entries. The
scope-by-platform matrix is the owned scope contract: every P0 scope entry
must cover every
declared target platform, using `notApplicable`, `unsupported`, or
`manualRequired` with reasons where a platform cannot or should not implement
the scope entry. Do not start implementation
while `scope.planningReady` is false, and do not create a ready report while
`scope.functionalEvidenceReady` is false.

When `package next` emits `nextAction.phase: visual-page-readiness`, open the
screenshot or UI-state artifact named in `details.visualPageReadiness` and
record the result in `.fluoh/tasks/<task-id>/evidence/visual-readiness.yaml`:

```yaml
schema: 1
kind: fluoh.visualPageReadiness
package: <name>
platform: ohos
status: passed
screenshots:
  - .fluoh/tasks/<task-id>/evidence/screenshots/<name>-ohos-post-launch.jpeg
uiStateEvidence: []
result: Functional demo page is visible and usable.
```

Use `status: passed` only when the functional page is actually visible and
usable. If the screen is blank, stuck on splash, visually hidden, or just a
template shell, repair the example and rerun the tool-provided command instead
of writing passed visual evidence.

`package next` usually emits one action at a time from this phase order; do not
run the whole list from memory when `nextAction` points somewhere else:

```sh
fluoh deps get
fluoh doctor --platform ohos --project --json --strict
fluoh flutter analyze
fluoh verify --package <name> --json --trace
fluoh build ohos --package <name> --auto-sign --json --trace
fluoh devices --platform ohos --json
fluoh emulators --platform ohos --json
fluoh run ohos --package <name> --auto-emulator --json --trace
fluoh package next --package <name> --json
# If nextAction.phase is visual-page-readiness, inspect the screenshot or
# UI-state evidence and record visual-readiness.yaml in the current task evidence directory.
fluoh drive ohos --package <name> --json --trace
# When emitted by preflight/plan for existing supported mobile examples:
fluoh drive android --package <name> --json --trace
fluoh drive ios --package <name> --json --trace
fluoh package next --package <name> --json
fluoh package status --package <name> --json
# If nextAction asks for report creation or report repair, follow it and rerun
# package next until nextAction.type is ready.
# host subagent: independent read-only review using independent-review-flow.md.
fluoh package handoff --package <name> --json
fluoh package check --package <name> --report <report-path> --json
```

Rules:

- Read generated `FLUOH.md`, `doc/fluoh/<package>/spec.md`, and `fluoh.yaml`
  before editing.
- Keep upstream public Dart APIs and existing platform behavior unless the user
  approves a breaking change.
- Establish the selected-SDK baseline before adding platform code.
- Fix existing-platform regressions first when Android, iOS, macOS, Linux, Web,
  Windows, tests, or examples already exist.
- Implement platform code near the package path recorded in `fluoh.yaml`;
  FlutterOH implementation files still follow the FlutterOH package layout.
- Extend package tests or examples when behavior changes.
- Example apps are functional harnesses: expose operations, expected results,
  pass/fail status, and failure hints for automated or AI-assisted checks.
- Every failing command enters the repair loop: parse JSON diagnostics and log
  tails, inspect trace feedback candidates, patch the smallest owned issue,
  rerun the failed command or its `nextCommand`, and record the command/result
  in the report.
- Use `fluoh drive ohos --package <name> --profile exploratory-smoke --json`
  only as optional diagnostic evidence for bounded exploration, crash
  discovery, or blank-page discovery. It does not satisfy the required
  automation-run phase or replace scenario, integration-test, or
  manual-assisted functional evidence.
- `fluoh run ohos --package <name> ...` owns the OHOS Flutter platform loop:
  debug signing preparation, `flutter run`, run/session diagnostics, and
  `example/integration_test/` execution on the selected target when present.
  Successful mobile `fluoh run` commands also attempt best-effort post-launch
  screenshot capture for OHOS, Android, and iOS and record
  `details.postLaunchScreenshot`. If the field is skipped, failed, partial, or
  absent, collect screenshot or equivalent UI-state evidence with
  `fluoh drive`; always keep a tool-readable page assertion before claiming
  the demo page is ready.
  During OHOS grant-path integration tests, pass
  `--ohos-permission-dialog-policy allow` only when clicking allow preserves
  the test intent. If this happens, the integration step records
  `details.systemPermissionDialogs` with the dialog title, reason, button
  bounds, poll count, and handled count. Use that evidence to explain prompt
  handling, but keep deny/error paths under test or `fluoh drive` control so
  automatic allow does not mask those behaviors.
  Use `fluoh attach ohos --session-file <path>` for Flutter debug attach when
  a live session exposes a VM Service URI or target id.
  Use hdc/hilog through `fluoh drive --scenario` or lower-level debug
  diagnostics, not as the primary run path.

## Platform Regression

Follow the `package next` existing-platform phases when corresponding example
platform directories exist and local toolchains are available. The
`existing-<platform>-regression` phase may be a build or run command depending
on the platform policy. Existing Android and host-supported iOS examples also
require `existing-<platform>-automation-dry-run` and
`existing-<platform>-automation-run`. Do not validate only OHOS unless every
other existing platform is unsupported by the current host or toolchain and
that diagnostic is recorded. Run `doctor` when toolchain status is unknown or a
platform command fails; it is diagnostic evidence, not a substitute for the
trace phase:

```sh
fluoh doctor --platform android --json --strict
fluoh run android --package <name> --auto-emulator --json --trace
fluoh drive android --package <name> --dry-run --json --trace
fluoh drive android --package <name> --json --trace
fluoh doctor --platform ios --json --strict
fluoh run ios --package <name> --auto-emulator --json --trace
fluoh drive ios --package <name> --dry-run --json --trace
fluoh drive ios --package <name> --json --trace
fluoh doctor --platform macos --json --strict
fluoh run macos --package <name> --json --trace
fluoh doctor --platform web --json --strict
fluoh run web --package <name> --json --trace
fluoh build linux --package <name> --json --trace
fluoh build windows --package <name> --json --trace
```

For iOS, auto-emulator selection should prefer an iPhone simulator over iPad,
prefer newer runtimes inside the same device class, and wait for
`xcrun simctl bootstatus <udid> -b` before treating the simulator as ready.

Use the per-platform `fluoh drive <platform> --package <name> --json` commands
emitted by `package next`, preflight, or `fluoh plan package --json`. OHOS is
part of the support target; Android and iOS drive commands are included only
when the example platform exists and the local host can run the target.
When `fluoh run all --package <name> --json` is used as a shortcut, parse
`workflowEvidence.toolCommands` and continue with the emitted `drive --dry-run`
or platform-specific drive commands. Do not substitute launch smoke for taps,
swipes, permission prompt handling, grant/deny assertions, or result checks.
For every platform directory that exists in the package example, record either
passed build/run/integration/drive evidence or the exact unsupported-host or
toolchain diagnostic that prevents execution. A ready recommendation is not
valid when a supported existing platform was skipped.

## Delivery Gate

Before the final response:

- Run the preflight or plan `finalCheckCommands` after the last implementation
  edit.
- Use the canonical report path validated by `package next`. If `package next`
  emits report creation, report repair, or report-check work, follow that
  action and rerun `package next` before claiming ready.
- Run `python3 <skill-dir>/scripts/check_report.py <report-path>` against the
  same report path during final checks and fix every failure through the
  package loop.
- Run `independent-review-flow.md`; repair or explicitly route every
  blocker/high/medium feedback packet item before `ready`.
- Ensure `fluoh package handoff --package <name> --json` sees the current
  branch, trace, report paths, and next commands.
- Ensure `fluoh package check --package <name> --report <report-path> --json`
  passes for `ready`, or records the remaining maintainer decision or blocker
  in the report.
- Review the diff for unrelated files, machine-local paths, generated caches,
  credentials, and private tokens.

Create small local checkpoint commits automatically after completed phases with
clean command evidence. Typical phases are generated baseline, selected-SDK
baseline, implementation, tests and example verification, release metadata, and
delivery report handoff. Before each commit, review `git status --short`, run
`git diff --check`, stage only intentional tracked files, and keep `.fluoh`
reports/traces, caches, credentials, signing secrets, and machine-local paths
out of commits. Push, force-push, release, tag, public API breaks, upstream
downgrades, SDK line changes, signing policy changes, and manual release
version overrides still require separate maintainer approval. Run
`fluoh package release` only when the maintainer approves the release.
