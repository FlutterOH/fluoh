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
        "expectedEvidence": command_expected_evidence(command),
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


def command_phase(command: str) -> str:
    if command.startswith("Resolve package setup") or " package create " in command:
        return "setup"
    if command.startswith("cd "):
        return "setup"
    if " source update" in command:
        return "setup"
    if " deps " in command:
        return "deps"
    if " doctor " in command:
        return "doctor"
    if " verify" in command:
        return "verify"
    if " devices " in command or " emulators " in command:
        return "target-discovery"
    if " build " in command or " run " in command:
        return "platform"
    if " drive " in command:
        return "automation"
    if " report create " in command:
        return "report"
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


def command_expected_evidence(command: str) -> str:
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
            f"Create or update .fluoh/reports/{scope}/ai-report-...md before the final response.",
            "Record deps, doctor, build, and run command results with exit codes.",
            "Use --auto-emulator for OHOS run so a local emulator is tried before connected devices; record signed build-only evidence only when no local target can be started.",
            "Run Android checks with --auto-emulator and Web browser smoke runs when those platform directories exist; run iOS, macOS, Linux, and Windows checks only on matching hosts, and record exact skip reasons for unavailable hosts.",
            "Review the diff and remove unrelated local paths, generated caches, credentials, and private tokens.",
            "State ready, blocked, or needs maintainer decision in the final response.",
        ]
    if kind == "package-repository":
        package = slug(project["selectedPackage"] or "<name>", "<name>")
        return [
            "Confirm preflight upgradeChecks has no schema migration blocker and generated docs are current or refreshed before editing.",
            f"Create or update .fluoh/reports/{package}/ai-report-...md before the final response.",
            f"Record verify, status, and package check results for {package} with exit codes.",
            f"Record OHOS build/run evidence for {package}; use --auto-emulator so a local emulator is tried before connected devices, and explain only the remaining device/build blocker.",
            "Record Android regression checks with --auto-emulator and Web browser smoke runs when examples exist, plus iOS, macOS, Linux, and Windows checks only on matching hosts; record exact skip reasons for unavailable hosts.",
            "Review public API compatibility, dependency constraints, and non-OHOS regression risk.",
            "Review the diff and remove unrelated local paths, generated caches, credentials, and private tokens.",
            "State ready, blocked, or needs maintainer decision in the final response.",
        ]
    if kind == "flutter-package":
        package = slug(project["name"] or "<package-name>", "<package-name>")
        output = flutter_package_output(project)
        return [
            "Create a FlutterOH package repository before editing OHOS implementation files.",
            f"Rerun preflight in {output} before using final check commands.",
            f"Create or update .fluoh/reports/{package}/ai-report-...md in the generated repository before the final response.",
            f"Record verify, status, and package check results for {package} with exit codes.",
            f"Record OHOS build/run evidence for {package}; use --auto-emulator so a local emulator is tried before connected devices, and explain only the remaining device/build blocker.",
            "Record Android regression checks with --auto-emulator and Web browser smoke runs when examples exist after repository creation, plus iOS, macOS, Linux, and Windows checks only on matching hosts; record exact skip reasons for unavailable hosts.",
            "Review public API compatibility, dependency constraints, and non-OHOS regression risk.",
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
