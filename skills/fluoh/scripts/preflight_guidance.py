"""Guidance helpers for fluoh skill preflight output."""

from __future__ import annotations

import re
import shlex
from typing import Any


def is_placeholder(value: str) -> bool:
    return value.startswith("<") and value.endswith(">")


def slug(value: str, fallback: str) -> str:
    raw = value.strip()
    if is_placeholder(raw):
        return fallback
    normalized = re.sub(r"[^A-Za-z0-9._-]+", "-", raw)
    normalized = normalized.strip("-._")
    return normalized or fallback


def command_arg(value: str) -> str:
    return value if is_placeholder(value) else shlex.quote(value)


def flutter_package_output(project: dict[str, Any]) -> str:
    package = project["name"] or "<package-name>"
    if package == "<package-name>":
        return "../<package-name>_ohos"
    return f"../{package}_ohos"


def adapt_plan_command(project: dict[str, Any]) -> str | None:
    if project["kind"] == "app-project":
        sdk = project["sdkVersion"]
        if sdk:
            return f"fluoh plan app --sdk {command_arg(sdk)} --json"
        return "fluoh plan app --json"
    if project["kind"] == "package-repository":
        package = project["selectedPackage"] or "<name>"
        return f"fluoh plan package --package {command_arg(package)} --json"
    return None


def command_queue(
    commands: list[str],
    project: dict[str, Any],
) -> list[dict[str, Any]]:
    return [command_queue_item(command, project) for command in commands]


def command_queue_item(command: str, project: dict[str, Any]) -> dict[str, Any]:
    phase = command_phase(command)
    mutating = command_mutates(command)
    item: dict[str, Any] = {
        "phase": phase,
        "command": command,
        "mutating": mutating,
        "requiresApproval": mutating,
        "expectedEvidence": command_expected_evidence(command, phase),
        "mustCompleteForDelivery": command_must_complete(command, project),
        "failureAction": command_failure_action(command),
    }
    if command.startswith("Resolve package setup:"):
        item["mutating"] = False
        item["requiresApproval"] = False
        item["kind"] = "setup-inputs"
    if project["kind"] in {"app-project", "package-repository", "flutter-package"}:
        item["adaptationKind"] = (
            "package" if project["kind"] != "app-project" else "app"
        )
    return item


def command_must_complete(command: str, project: dict[str, Any]) -> bool:
    kind = project["kind"]
    if kind not in {"app-project", "package-repository", "flutter-package"}:
        return False
    if command.startswith("Resolve package setup") or command.startswith("cd "):
        return False
    if "--dry-run" in command or "--plan" in command:
        return False
    return command_phase(command) in {
        "deps",
        "docs",
        "doctor",
        "verify",
        "target-discovery",
        "platform",
        "automation",
        "regression",
        "report",
        "report-check",
        "handoff",
        "release-check",
    }


def command_failure_action(command: str) -> str:
    if command.startswith("Resolve package setup"):
        return "resolve setup inputs, then regenerate the plan"
    if command.startswith("cd "):
        return "switch to the generated repository and rerun preflight"
    if "--dry-run" in command or "--plan" in command:
        return "inspect the plan output before running the mutating command"
    if " package handoff " in command:
        return "fix the reported branch, dirty tree, trace, or report gap before continuing"
    if " package check " in command:
        return "fix the release gate finding, rerun the failed command, then rerun package check"
    if " report create " in command:
        return "create or update the report, then run the report check command"
    if "check_report.py" in command:
        return "fix report validation failures, update the report evidence, then rerun report check"
    return "parse JSON diagnostics, make the smallest fix, and rerun this command or its nextCommand"


def command_phase(command: str) -> str:
    if command.startswith("Resolve package setup") or " package create " in command:
        return "setup"
    if command.startswith("cd "):
        return "setup"
    if " source update" in command:
        return "setup"
    if " package docs refresh" in command:
        return "docs"
    if " deps " in command:
        return "deps"
    if " doctor " in command:
        return "doctor"
    if " verify" in command:
        return "verify"
    if " devices " in command or " emulators " in command:
        return "target-discovery"
    if " drive " in command:
        return "automation"
    if " run android " in command or " run ios " in command:
        return "regression"
    if (
        " run macos " in command
        or " run web " in command
        or " build linux " in command
        or " build windows " in command
    ):
        return "regression"
    if " build " in command or " run " in command:
        return "platform"
    if " report create " in command:
        return "report"
    if "check_report.py" in command:
        return "report-check"
    if " package handoff " in command:
        return "handoff"
    if " package status " in command or " package check " in command:
        return "release-check"
    return "other"


def command_mutates(command: str) -> bool:
    readonly_tokens = (
        "--dry-run",
        "--plan",
        " deps check ",
        " doctor ",
        " devices ",
        " emulators ",
        " package status ",
        " package handoff ",
        " package check ",
        " package discover ",
        " package queue ",
    )
    if command.startswith("Resolve package setup") or command.startswith("cd "):
        return False
    if any(token in command for token in readonly_tokens):
        return False
    return any(
        token in command
        for token in (
            " sdk use ",
            " source update",
            " deps fix",
            " deps get",
            " build ",
            " run ",
            " drive ",
            " package create ",
            " package docs refresh",
            " report create ",
        )
    )


def command_expected_evidence(command: str, phase: str) -> str:
    if phase == "regression":
        return (
            "existing-platform functional regression evidence, including "
            "run/build result, integration-test or drive evidence when "
            "applicable, or unsupported-host/toolchain blocker"
        )
    if " source update" in command:
        return "source update result"
    if " deps check " in command:
        return "dependency support JSON"
    if " deps fix --dry-run" in command:
        return "dependency rewrite plan"
    if " doctor " in command:
        return "toolchain diagnostic JSON"
    if " devices " in command:
        return "connected target inventory JSON"
    if " emulators " in command:
        return "local emulator inventory JSON"
    if " verify" in command:
        return "pub get, analyze, and test JSON"
    if " build " in command:
        return "build artifact and command JSON"
    if " run " in command:
        return "launch, runtime log, target, and diagnostic JSON"
    if " drive " in command:
        return "automation coverage policy, scenario rows, and repair queue"
    if " report create " in command:
        return "local AI report path"
    if "check_report.py" in command:
        return "canonical report validation JSON"
    if " package handoff " in command:
        return "branch state, reports, traces, and next commands"
    if " package check " in command:
        return "release gate JSON"
    return "command result"


def delivery_checks(project: dict[str, Any]) -> list[str]:
    kind = project["kind"]
    if kind == "app-project":
        scope = slug(project["name"] or "app", "app")
        return [
            "Confirm preflight upgradeChecks has no migration blocker before editing.",
            f"Create or update .fluoh/reports/{scope}/report-<timestamp>.md before the final response.",
            "Before final verification, inspect existing tests and integration tests against app behavior; add or repair missing functional tests before claiming ready.",
            "Record deps, doctor, build, and run command results with exit codes.",
            "Use --auto-emulator for OHOS run so a local emulator is tried before connected devices; record signed build-only evidence only when no local target can be started.",
            "Run functional checks for OHOS and every existing Android, iOS, macOS, Linux, Web, and Windows platform directory when the current host supports it; record exact diagnostic evidence and skip reasons only for unsupported hosts or toolchains.",
            "Review the diff and remove unrelated local paths, generated caches, credentials, and private tokens.",
            "Run the report check command against the canonical report and fix every failure before the final response.",
            "State ready, blocked, or needs maintainer decision in the final response.",
        ]
    if kind == "package-repository":
        package = slug(project["selectedPackage"] or "<name>", "<name>")
        return [
            "Confirm preflight upgradeChecks has no schema migration blocker and generated docs are current or refreshed before editing.",
            f"Create or update .fluoh/reports/{package}/report-<timestamp>.md before the final response.",
            "Before final verification, inspect package tests, example tests, and integration tests against public API, platform interfaces, permissions, and behavior paths; add or repair missing functional tests before claiming ready.",
            f"Record verify, status, and package check results for {package} with exit codes.",
            f"Record OHOS build/run evidence for {package}; use --auto-emulator so a local emulator is tried before connected devices, and explain only the remaining device/build blocker.",
            "Record functional checks for every existing non-OHOS example platform, including Android, iOS, macOS, Linux, Web, and Windows when the current host supports it; record exact diagnostic evidence and skip reasons only for unsupported hosts or toolchains.",
            "Review public API compatibility, dependency constraints, and non-OHOS regression risk.",
            "Review the diff and remove unrelated local paths, generated caches, credentials, and private tokens.",
            "Run the report check command against the canonical report and fix every failure before the final response.",
            "State ready, blocked, or needs maintainer decision in the final response.",
        ]
    if kind == "flutter-package":
        package = slug(project["name"] or "<package-name>", "<package-name>")
        output = flutter_package_output(project)
        return [
            "Create a FlutterOH package repository before editing OHOS implementation files.",
            f"Rerun preflight in {output} before using final check commands.",
            f"Create or update .fluoh/reports/{package}/report-<timestamp>.md in the generated repository before the final response.",
            "Before final verification, inspect package tests, example tests, and integration tests against public API, platform interfaces, permissions, and behavior paths; add or repair missing functional tests before claiming ready.",
            f"Record verify, status, and package check results for {package} with exit codes.",
            f"Record OHOS build/run evidence for {package}; use --auto-emulator so a local emulator is tried before connected devices, and explain only the remaining device/build blocker.",
            "Record functional checks for every existing non-OHOS example platform after repository creation, including Android, iOS, macOS, Linux, Web, and Windows when the current host supports it; record exact diagnostic evidence and skip reasons only for unsupported hosts or toolchains.",
            "Review public API compatibility, dependency constraints, and non-OHOS regression risk.",
            "Run the report check command against the canonical report and fix every failure before the final response.",
            "State ready, blocked, or needs maintainer decision in the final response.",
        ]
    return [
        "Choose a Flutter app project or FlutterOH package repository before editing.",
        "Do not make project changes until preflight can identify the workspace shape.",
    ]


def report_command(project: dict[str, Any]) -> str:
    if project["kind"] == "package-repository":
        scope = project["selectedPackage"] or "<name>"
        package = scope
        return (
            "python3 <skill-dir>/scripts/new_report.py . "
            f"--scope {command_arg(scope)} --package {command_arg(package)}"
        )
    if project["kind"] == "flutter-package":
        package = project["name"] or "<package-name>"
        output = flutter_package_output(project)
        return (
            f"python3 <skill-dir>/scripts/new_report.py {command_arg(output)} "
            f"--scope {command_arg(package)} --package {command_arg(package)}"
        )
    scope = project["name"] or "app"
    return (
        "python3 <skill-dir>/scripts/new_report.py . "
        f"--scope {command_arg(scope)}"
    )


def summary_command(project: dict[str, Any]) -> str:
    if project["kind"] == "package-repository":
        scope = project["selectedPackage"] or "monorepo"
        package = project["selectedPackage"] or "<name>"
        return (
            "python3 <skill-dir>/scripts/new_summary.py . "
            f"--scope {command_arg(scope)} --package {command_arg(package)}"
        )
    if project["kind"] == "flutter-package":
        package = project["name"] or "<package-name>"
        output = flutter_package_output(project)
        return (
            f"python3 <skill-dir>/scripts/new_summary.py {command_arg(output)} "
            f"--scope {command_arg(package)} --package {command_arg(package)}"
        )
    scope = project["name"] or "app"
    return (
        "python3 <skill-dir>/scripts/new_summary.py . "
        f"--scope {command_arg(scope)}"
    )


def report_check_command() -> str:
    return "python3 <skill-dir>/scripts/check_report.py <report-path>"


def quality_gates(project: dict[str, Any]) -> list[dict[str, Any]]:
    kind = project["kind"]
    active = kind in {"app-project", "package-repository", "flutter-package"}
    adaptation_kind = "app" if kind == "app-project" else "package"
    return [
        {
            "id": "functional-test-baseline",
            "requiredForReady": active,
            "description": (
                f"Before final verification, inspect existing {adaptation_kind} "
                "tests and integration tests against public API, platform "
                "interfaces, example flows, permissions, and behavior paths; "
                "add or repair missing functional tests before claiming ready."
            ),
        },
        {
            "id": "complete-existing-platform-matrix",
            "requiredForReady": active,
            "description": (
                "Do not validate only OHOS. Run functional verification for "
                "OHOS and every existing non-OHOS platform directory when the "
                "current host/toolchain supports it; otherwise record the "
                "diagnostic command, unsupported environment reason, and "
                "remaining blocker in the report."
            ),
        },
        {
            "id": "behavior-evidence-not-smoke",
            "requiredForReady": active,
            "description": (
                "Ready evidence must validate library behavior through package "
                "tests, integration_test, real fluoh drive JSON, or "
                "manual-assisted tool-readable assertions; build, launch, "
                "screenshot, or run-all smoke evidence is insufficient alone. "
                "After each mobile run, capture a screenshot or equivalent "
                "UI-state artifact and repair abnormal demo pages before "
                "continuing to full automation."
            ),
        },
    ]


def automation_runbook(project: dict[str, Any]) -> dict[str, Any]:
    kind = project["kind"]
    active = kind in {"app-project", "package-repository", "flutter-package"}
    if kind == "flutter-package":
        mode = "setup-then-rerun-preflight"
    elif active:
        mode = "autonomous-to-delivery"
    else:
        mode = "routing-only"
    return {
        "mode": mode,
        "commandSource": "commandQueue",
        "loop": "run, parse, fix, rerun until deliveryGate is satisfied or an explicit blocker remains",
        "qualityGates": quality_gates(project),
        "preCommandChecks": [
            {
                "field": "fluohSetup.status",
                "readyValue": "ready",
                "whenNotReady": "fix the fluoh executable or launcher first, rerun preflight, then follow commandQueue",
            }
        ],
        "executionRules": [
            "If fluohSetup.status is needs-cli-setup, fix the fluoh executable or launcher first and rerun preflight before commandQueue.",
            "Run commandQueue in order after the approved adaptation scope.",
            "Before final verification, inspect whether existing tests cover the package or app behavior; add or repair missing functional tests before running the final test matrix.",
            "Parse every --json result before editing or deciding the next step.",
            "Follow diagnostics.nextCommand when present; otherwise rerun the failed command after the smallest relevant fix.",
            "After every successful mobile run, capture a screenshot or equivalent UI-state artifact and fix abnormal demo pages before continuing.",
            "Do not stop after setup, verify, build, run, or screenshot-only smoke evidence.",
            "Do not focus only on OHOS; every existing platform must have functional evidence or an explicit unsupported-host/toolchain diagnostic blocker.",
            "Do not skip drive, report creation, report check, package handoff, or package check when they are applicable.",
            "Create local checkpoint commits after completed phases when command evidence is clean.",
            "Do not push, release, force-push, or run destructive Git commands without separate maintainer approval.",
        ],
        "checkpointPolicy": {
            "mode": "auto-local-commits",
            "scopeApprovalAuthorizesCommits": True,
            "commitPhases": [
                "generated baseline",
                "selected SDK baseline",
                "implementation",
                "tests and example verification",
                "release metadata",
                "delivery report handoff",
            ],
            "beforeCommit": [
                "run the phase's relevant verification command",
                "review git status --short and git diff --check",
                "stage only intentional tracked files for the phase",
                "exclude .fluoh reports, traces, caches, credentials, signing secrets, and machine-local paths",
            ],
            "afterCommit": [
                "record the commit hash in the AI report Local State section",
                "continue to the next commandQueue phase",
            ],
        },
        "repairLoop": {
            "onFailure": [
                "classify the failure as fluoh CLI, Source data, AI skill, local environment, upstream package, or project/package implementation",
                "read diagnostics, stdoutTail, stderrTail, trace, feedbackCandidates, and traceError",
                "fix the smallest owned issue",
                "rerun the failed command or printed nextCommand",
                "collect feedback candidates into the report when traces report them",
            ],
            "stopOnlyWhen": [
                "deliveryGate.readyRequires is satisfied",
                "deliveryGate.blockedWhen contains the remaining blocker",
                "a maintainer decision listed in deliveryGate.needsMaintainerDecision is required",
            ],
        },
        "active": active,
    }


def delivery_gate(
    project: dict[str, Any],
    final_check_commands: list[str],
) -> dict[str, Any]:
    kind = project["kind"]
    active = kind in {"app-project", "package-repository", "flutter-package"}
    gate: dict[str, Any] = {
        "active": active,
        "terminalStates": ["ready", "blocked", "needs-maintainer-decision"],
        "finalCheckCommands": final_check_commands,
        "reportCommand": report_command(project),
        "summaryCommand": summary_command(project),
        "reportCheckCommand": report_check_command(),
        "requiresReportCheckPass": active,
        "readyRequires": [],
        "blockedWhen": [
            "a required local toolchain, SDK, signing, device, emulator, or host platform is unavailable after running the diagnostic command",
            "the selected upstream package cannot be made compatible with the selected FlutterOH SDK without maintainer approval",
            "automation evidence cannot be made tool-readable with the available device or emulator",
        ],
        "needsMaintainerDecision": [
            "release, publish, push, tag, force-push, or destructive Git operation",
            "public API break, upstream downgrade, SDK line change, release version override, or signing policy decision",
        ],
    }
    if not active:
        gate["status"] = "not-applicable"
        gate["readyRequires"] = [
            "preflight identifies a Flutter app project, Flutter package, or FlutterOH package repository"
        ]
        return gate
    if kind == "flutter-package":
        gate["status"] = "setup-required"
        gate["readyRequires"] = [
            "run the package create plan command and confirm the resolved scope",
            "create the FlutterOH package repository",
            "rerun preflight in the generated repository",
            "complete the generated repository deliveryGate before the final response",
        ]
        return gate
    common = [
        "upgradeChecks has no schema, generated-doc, or newer-template blocker",
        "existing tests and integration tests were reviewed against public API, platform interfaces, example flows, permissions, and behavior paths before final verification; missing or weak functional tests were added or a concrete blocker is recorded",
        "each successful mobile run has screenshot or equivalent UI-state evidence, and abnormal demo pages were repaired before continuing",
        "functional evidence validates the library or app behavior, not only build, launch, screenshot, or run-all smoke",
        "OHOS and every existing non-OHOS platform directory has functional build/run/integration/drive evidence when the current host supports it; unsupported platforms have exact diagnostic evidence and skip reasons",
        "every commandQueue item marked mustCompleteForDelivery has passed or has a concrete blocker recorded",
        "finalCheckCommands ran after the last implementation edit",
        "canonical report exists under .fluoh/reports/",
        "reportCheckCommand passes against the canonical report",
        "the final response states exactly one terminal state and only remaining blocking risks",
    ]
    if kind == "package-repository":
        package = project["selectedPackage"] or "<name>"
        gate["status"] = "active"
        gate["readyRequires"] = [
            *common,
            f"fluoh package handoff --package {command_arg(package)} --json reports current branch evidence",
            f"fluoh package check --package {command_arg(package)} --report <report-path> --json passes, or the report clearly records why this needs maintainer decision",
        ]
        return gate
    gate["status"] = "active"
    gate["readyRequires"] = [
        *common,
        "OHOS build and run evidence are recorded, or the final report records the exact local blocker",
        "interaction evidence uses integration_test, real fluoh drive JSON, or tool-readable manual-assisted evidence",
    ]
    return gate


def feedback_command() -> str:
    return "python3 <skill-dir>/scripts/collect_feedback.py <trace-dir-or-manifest>"


def session_inspect_command() -> str:
    return (
        "python3 <skill-dir>/scripts/inspect_session.py <session-file> "
        "--wait 30 --expect-platform <platform>"
    )


def session_attach_command() -> str:
    return "fluoh attach <platform> --session-file <session-file>"


def scenario_command(project: dict[str, Any]) -> str:
    if project["kind"] == "package-repository":
        package = project["selectedPackage"] or "<name>"
        return (
            "python3 <skill-dir>/scripts/new_scenario.py . "
            f"--scope {command_arg(package)} --package {command_arg(package)} "
            "--platform <platform> --name <scenario-name>"
        )
    if project["kind"] == "flutter-package":
        package = project["name"] or "<package-name>"
        output = flutter_package_output(project)
        return (
            f"python3 <skill-dir>/scripts/new_scenario.py {command_arg(output)} "
            f"--scope {command_arg(package)} --package {command_arg(package)} "
            "--platform <platform> --name <scenario-name>"
        )
    scope = project["name"] or "app"
    return (
        "python3 <skill-dir>/scripts/new_scenario.py . "
        f"--scope {command_arg(scope)} --app --platform <platform> "
        "--name <scenario-name>"
    )
