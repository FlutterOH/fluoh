# Independent Review Flow

Use this flow after the adaptation AI has produced a report and believes the
work is `ready`. This is a host-agent supervision loop, not a fluoh CLI gate.

## Contract

- Start a new independent reviewer agent when the host supports subagents.
- Give the reviewer only the package/app path, report path, relevant trace
  paths, previous feedback packet when one exists, and the task scope. Do not
  give it the adaptation AI's conclusion as ground truth.
- The reviewer is read-only: it may inspect files, diffs, reports, command
  output, traces, screenshots, scenarios, tests, and official-doc basis, but it
  must not edit files, stage, commit, release, push, or repair code.
- The reviewer must check whether the claimed ready state is justified by
  evidence, not whether the implementation looks plausible.
- If findings exist, send the feedback packet back to the adaptation AI as
  repair work, rerun the affected verification/report checks, then start
  another independent review pass. Continue until the reviewer reports pass, a
  maintainer decision is needed, or a concrete blocker remains.
- Record the reviewer verdict and any repaired findings in the report's
  `## Independent Review` section. This section is documentation for the
  supervision loop, not a deterministic `check_report.py` or fluoh CLI gate.
- If the host cannot start subagents, record that supervision blocker in the
  final response and do not claim an independently reviewed ready state.

## Supervisor Feedback Packet

Use a compact packet so feedback survives repair and re-review without relying
on chat memory. Store it in the report's `## Independent Review` section, or in
ignored local state such as `.fluoh/reviews/<scope>/review-<timestamp>.md`
when the table is too large.

| Field | Meaning |
| --- | --- |
| ID | Stable `IR-001` style identifier. Keep the same ID across repair passes. |
| Severity | `blocker`, `high`, `medium`, or `low`. |
| Area | API, platform, docs-basis, tests, example, automation, report, local-state, release. |
| Evidence | File path, report section, command row, trace path, screenshot, or exact missing evidence. |
| Required repair | What the adaptation AI must change or prove. |
| Validation | Command, report row, trace, scenario, or reviewer check that closes it. |
| Status | `open`, `fixed`, `accepted-risk`, `maintainer-decision`, or `blocked`. |

Severity routing:

- `blocker` and `high`: must be repaired and revalidated before `ready`.
- `medium`: repair unless a maintainer-decision or accepted-risk rationale is
  explicit in the report.
- `low`: may remain as residual risk if it does not invalidate the release
  recommendation.

The adaptation AI owns status changes, but the next reviewer owns whether a
`fixed` item has enough evidence to close.

## Reviewer Prompt

Use a prompt like this, filling in the concrete paths:

```text
You are an independent read-only reviewer for a FlutterOH/OHOS adaptation.
Do not edit, stage, commit, release, push, or repair files.

Scope:
- Project/package path: <path>
- Package/app: <name>
- Report: <path>
- Trace/session/scenario paths: <paths or none>
- User goal: <goal>

Review the final diff, report, commands table, official platform basis,
platform matrix, automation coverage, interaction evidence, test coverage,
non-OHOS regression coverage, local state, and remaining risks.

Classify findings as blocker, high, medium, or low. A blocker/high finding
means the adaptation AI must repair and rerun evidence before ready. Prefer
file paths, report section names, command rows, trace paths, and exact missing
evidence over generic advice. If a previous feedback packet exists, verify
each open/fixed item before adding new findings.

Return:
- Verdict: pass | needs-fixes | blocked
- Findings: feedback packet table with ID, severity, area, evidence, required
  repair, validation, and status
- Residual risks if pass
```

## Repair Loop

When the reviewer returns `needs-fixes`, the adaptation AI should:

1. Copy the feedback packet into the report or ignored local review note.
2. Treat blocker/high findings as repair work, not report wording.
3. Repair medium findings, or record maintainer-decision/accepted-risk
   rationale when repair is not appropriate.
4. Patch the smallest owned implementation, example, scenario, test, or report
   issue needed.
5. Rerun the command that proves the repair.
6. Update each feedback item with status and validation evidence.
7. Update the report with new evidence.
8. Run `check_report.py` again.
9. Start a fresh independent reviewer agent pass and include the prior packet.

The reviewer in the next pass should:

1. Close only items whose repair evidence is concrete.
2. Reopen items marked `fixed` when validation is missing or unrelated.
3. Keep IDs stable; use new IDs only for new findings.
4. Avoid relitigating accepted low risks unless new evidence changes impact.

## Stop Conditions

- `pass`: no open blocker/high findings, medium findings are fixed or have a
  documented maintainer-decision/accepted-risk rationale, and residual low
  risks are explicit.
- `needs-fixes`: at least one repairable blocker/high/medium finding remains.
- `blocked`: the next evidence step is impossible because of local toolchain,
  device, upstream, credential, vendor-doc, or maintainer-decision constraints.

Use the final response to report the reviewer verdict and only unresolved
blocking risks.
