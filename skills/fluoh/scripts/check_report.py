#!/usr/bin/env python3
"""Validate a fluoh AI adaptation report before final delivery."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any


REQUIRED_SECTIONS = (
    "## Summary",
    "## Changes",
    "## Public API / Compatibility",
    "## Commands",
    "## Delivery Checklist",
    "## Platform Matrix",
    "## Automation Coverage",
    "## Interaction Evidence",
    "## Diagnostics",
    "## Fluoh Feedback",
    "## Signing",
    "## Remaining Risks",
    "## Local State",
    "## Release Decision",
)

REQUIRED_AUTOMATION_COVERAGE_GATES = (
    "coverage-inventory",
    "coverage-metadata",
    "coverage-items",
    "capability-inventory-coverage",
    "blocked-coverage",
    "scenario-evidence-assertions",
    "existing-test-baseline",
    "manifest-permission-coverage",
    "behavior-paths",
)

REQUIRED_READY_CHECKLIST_PHRASES = (
    "Existing package/app tests, example tests",
    "Missing or weak functional tests",
    "Every existing Android, iOS, macOS, Linux, Web, and Windows platform",
)

REPORT_FILENAME_PATTERN = re.compile(r"^report-\d+\.md$")


PLACEHOLDER_PATTERNS = (
    r"\|\s*`?\.\.\.`?\s*\|",
    r"^\s*-\s*$",
    r"^\s*-\s*\.\.\.\s*$",
    r"\bn/a\s*\|\s*n/a\s*\|\s*\.\.\.",
)


def report_filename_error(path: Path) -> str | None:
    if REPORT_FILENAME_PATTERN.match(path.name):
        return None
    return "Report filename must match report-<timestamp>.md using an integer timestamp."


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def release_recommendation(content: str) -> str | None:
    match = re.search(r"^Release recommendation:\s*(.+?)\s*$", content, re.MULTILINE)
    if not match:
        return None
    return normalize_recommendation(match.group(1))


def normalize_recommendation(value: str) -> str:
    normalized = value.strip().lower().replace("-", " ").replace("_", " ")
    return re.sub(r"\s+", " ", normalized)


def checklist_items(content: str) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    for match in re.finditer(r"^- \[([ xX])\]\s+(.+?)\s*$", content, re.MULTILINE):
        items.append(
            {
                "done": match.group(1).lower() == "x",
                "text": match.group(2).strip(),
            }
        )
    return items


def command_rows(content: str) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    in_commands = False
    for line in content.splitlines():
        if line.strip() == "## Commands":
            in_commands = True
            continue
        if in_commands and line.startswith("## "):
            break
        if not in_commands:
            continue
        row = parse_command_row(line)
        if row:
            rows.append(row)
    return rows


def parse_command_row(line: str) -> dict[str, str] | None:
    if not re.match(r"^\|\s*`[^`]+`\s*\|", line):
        return None
    columns = [column.strip() for column in line.strip().strip("|").split("|")]
    if len(columns) < 3:
        return None
    command_match = re.match(r"^`([^`]+)`$", columns[0])
    if not command_match:
        return None
    return {
        "command": command_match.group(1).strip(),
        "exit": columns[1],
        "result": columns[2],
        "row": line,
    }


def command_row_passed(row: dict[str, str]) -> bool:
    return row["exit"] == "0" and row["result"].lower() in (
        "passed",
        "ok",
        "success",
    )


def command_contains(command: str, expected: str) -> bool:
    return command == expected or command.startswith(f"{expected} ")


def is_verify_evidence(row: dict[str, str]) -> bool:
    return command_contains(row["command"], "fluoh verify")


def is_ohos_build_evidence(row: dict[str, str]) -> bool:
    command = row["command"]
    return (
        command_contains(command, "fluoh build")
        and re.search(r"(^|\s)fluoh\s+build\s+ohos(\s|$)", command) is not None
        and "--auto-sign" in command
        and "--json" in command
    )


def is_ohos_run_evidence(row: dict[str, str]) -> bool:
    command = row["command"]
    return (
        command_contains(command, "fluoh run")
        and re.search(r"(^|\s)fluoh\s+run\s+ohos(\s|$)", command) is not None
        and "--json" in command
    )


def is_mobile_run_evidence(row: dict[str, str]) -> bool:
    command = row["command"]
    return (
        command_contains(command, "fluoh run")
        and re.search(r"(^|\s)fluoh\s+run\s+(ohos|android|ios|all)(\s|$)", command)
        is not None
        and "--json" in command
    )


def is_automation_evidence(row: dict[str, str]) -> bool:
    command = row["command"]
    return (
        command_contains(command, "fluoh drive")
        and "--json" in command
        and not contains_shell_token(command, "--dry-run")
        and not contains_shell_token(command, "-n")
    )


def is_mobile_automation_evidence(row: dict[str, str]) -> bool:
    command = row["command"]
    return (
        is_automation_evidence(row)
        and re.search(r"(^|\s)fluoh\s+drive\s+(ohos|android|ios|all)(\s|$)", command)
        is not None
    )


def mobile_visual_requirements(
    content: str, passed_command_rows: list[dict[str, str]]
) -> list[dict[str, str]]:
    requirements: list[dict[str, str]] = []
    for row in passed_command_rows:
        if not (is_mobile_run_evidence(row) or is_mobile_automation_evidence(row)):
            continue
        for platform in mobile_command_platforms(row["command"], content):
            requirements.append(
                {"platform": platform, "command": row["command"], "row": row["row"]}
            )
    return requirements


def mobile_command_platforms(command: str, content: str) -> list[str]:
    match = re.search(
        r"(^|\s)fluoh\s+(?:run|drive)\s+(ohos|android|ios|all)(\s|$)",
        command,
    )
    if not match:
        return []
    platform = match.group(2)
    if platform != "all":
        return [platform]
    matrix_platforms = passed_mobile_run_matrix_platforms(content)
    return matrix_platforms or ["all"]


def passed_mobile_run_matrix_platforms(content: str) -> list[str]:
    platforms: list[str] = []
    for row in platform_matrix_rows(content):
        platform = row["platform"].strip().lower()
        if platform not in ("ohos", "android", "ios"):
            continue
        if row["run"].strip().lower().startswith("passed") or row[
            "integration"
        ].strip().lower().startswith("passed"):
            platforms.append(platform)
    return platforms


def is_integration_test_command_evidence(row: dict[str, str]) -> bool:
    command = row["command"]
    return (
        command_contains(command, "flutter test")
        and re.search(r"(^|\s)integration_test(?:\s|$|/)", command) is not None
    )


def mentions_integration_test_command(value: str) -> bool:
    normalized = value.lower()
    return (
        re.search(r"flutter\s+test\s+.*integration_test(?:\s|$|/)", normalized)
        is not None
    )


def is_integration_test_evidence(
    row: dict[str, str], passed_command_rows: list[dict[str, str]]
) -> bool:
    return (
        row["method"].lower() == "integration_test"
        and interaction_row_passed(row)
        and mentions_integration_test_command(row.get("evidence", ""))
        and any(
            is_integration_test_command_evidence(command)
            for command in passed_command_rows
        )
    )


def contains_shell_token(command: str, token: str) -> bool:
    return re.search(rf"(^|\s){re.escape(token)}(\s|$)", command) is not None


def section_content(content: str, heading: str) -> str:
    start = content.find(heading)
    if start == -1:
        return ""
    body_start = content.find("\n", start)
    if body_start == -1:
        return ""
    next_heading = re.search(r"^## ", content[body_start + 1 :], re.MULTILINE)
    if next_heading:
        return content[body_start + 1 : body_start + 1 + next_heading.start()]
    return content[body_start + 1 :]


def interaction_rows(content: str) -> list[dict[str, str]]:
    section = section_content(content, "## Interaction Evidence")
    rows: list[dict[str, str]] = []
    for line in section.splitlines():
        columns = [column.strip() for column in line.strip().strip("|").split("|")]
        if len(columns) >= 6 and columns[1].lower() in (
            "integration_test",
            "ai-assisted",
            "manual-assisted",
        ):
            rows.append(
                {
                    "scenario": columns[0],
                    "method": columns[1],
                    "platform": columns[2],
                    "target": columns[3],
                    "result": columns[4],
                    "evidence": columns[5],
                    "row": line,
                }
            )
    return rows


def automation_coverage_rows(content: str) -> list[dict[str, str]]:
    section = section_content(content, "## Automation Coverage")
    rows: list[dict[str, str]] = []
    for line in section.splitlines():
        columns = split_markdown_row(line)
        if len(columns) < 3:
            continue
        gate = columns[0].strip()
        if not gate or gate.lower() == "gate" or set(gate) <= {"-"}:
            continue
        if gate in ("`...`", "..."):
            continue
        rows.append(
            {
                "gate": gate,
                "status": columns[1],
                "row": line,
            }
        )
    return rows


def automation_coverage_status(content: str) -> dict[str, str | None]:
    section = section_content(content, "## Automation Coverage")
    return {
        "coveragePolicyStatus": automation_section_field(
            section, "coveragePolicy.status"
        ),
        "readyForAutomation": automation_section_field(section, "readyForAutomation"),
        "qualityGateSummary": automation_section_field(section, "qualityGateSummary"),
    }


def automation_section_field(section: str, key: str) -> str | None:
    escaped = re.escape(key)
    matches = list(
        re.finditer(
            rf"^\s*((?:[-*]\s*)?)`?{escaped}`?\s*:\s*(.+?)\s*$",
            section,
            re.IGNORECASE | re.MULTILINE,
        )
    )
    if not matches:
        return None
    match = next(
        (candidate for candidate in matches if candidate.group(1).strip()),
        matches[0],
    )
    value = match.group(2).strip()
    return value or None


def quality_gate_summary_ready(value: str | None) -> bool:
    if value is None or "..." in value:
        return False
    match = re.search(
        r"(?:not\s*ready|notready)\s*[:=]\s*(\[[^\]]*\]|[a-z0-9_-]+)",
        value,
        re.IGNORECASE,
    )
    if not match:
        return False
    return match.group(1).strip().lower() in ("0", "[]", "none", "empty")


def automation_coverage_row_ready(row: dict[str, str]) -> bool:
    normalized = re.sub(r"[^a-z0-9]+", "", row["status"].strip().lower())
    return normalized in (
        "ready",
        "readyforreview",
        "covered",
        "passed",
        "notapplicable",
    )


def interaction_row_passed(row: dict[str, str]) -> bool:
    return row["result"].lower() == "passed"


def manual_assisted_tool_readable(row: dict[str, str]) -> bool:
    evidence = row.get("evidence", "").lower()
    markers = (
        "flutterrunsession",
        "vm service",
        "session file",
        "session state",
        "session json",
        "output log",
        "outputlog",
        "stdout",
        "stderr",
        "hilog",
        "log marker",
        "app log",
        "assertlog",
        "assertsession",
        "asserttext",
        "waittext",
        "visible text",
        "visible status",
        "stable text",
        "semantic label",
        "semantics",
        "test key",
        "testkey",
        "component state",
        "command json",
        "trace.json",
        "trace manifest",
        "trace file",
        "diagnostics[]",
        "diagnostic code",
    )
    if not any(marker in evidence for marker in markers):
        return False
    if is_launch_only_evidence(evidence) and not has_functional_tool_evidence(evidence):
        return False
    return True


def is_launch_only_evidence(evidence: str) -> bool:
    markers = (
        "launched=true",
        "launchdetected true",
        "launchdetected=true",
        "launched the example",
        "launch evidence only",
        "app launched",
        "flutter run launched",
    )
    return any(marker in evidence for marker in markers)


def has_functional_tool_evidence(evidence: str) -> bool:
    markers = (
        "hilog",
        "log marker",
        "app log",
        "assertlog",
        "assertsession",
        "asserttext",
        "waittext",
        "visible text",
        "visible status",
        "stable text",
        "semantic label",
        "semantics",
        "test key",
        "testkey",
        "component state",
        "diagnostics[]",
        "diagnostic code",
    )
    return any(marker in evidence for marker in markers)


def platform_matrix_rows(content: str) -> list[dict[str, str]]:
    section = section_content(content, "## Platform Matrix")
    rows: list[dict[str, str]] = []
    for line in section.splitlines():
        columns = split_markdown_row(line)
        if len(columns) < 6:
            continue
        platform = columns[0].strip()
        if not platform or platform.lower() == "platform" or set(platform) <= {"-"}:
            continue
        rows.append(
            {
                "platform": platform,
                "build": columns[1],
                "run": columns[2],
                "integration": columns[3],
                "row": line,
            }
        )
    return rows


def platform_matrix_row_passed(row: dict[str, str]) -> bool:
    return any(
        row[key].strip().lower().startswith("passed")
        for key in ("build", "run", "integration")
    )


def positive_post_launch_visual_evidence(row: str) -> bool:
    evidence = row.lower()
    markers = (
        ".fluoh/evidence/screenshots",
        "post-launch screenshot",
        "post launch screenshot",
        "postlaunchscreenshot",
        "visualpagereadiness",
        "ui-state",
        "ui state",
        "capture screenshot",
        "capturescreenshot",
        "screenshot path",
        "screenshot:",
        "screen recording",
    )
    if not any(marker in evidence for marker in markers):
        return False
    negative_markers = (
        "not captured",
        "not collect",
        "not recorded",
        "missing",
        "failed",
        "empty",
        "blocked",
        "skipped",
    )
    return not any(marker in evidence for marker in negative_markers)


def has_post_launch_visual_evidence(
    content: str,
    *,
    passed_command_rows: list[dict[str, str]],
    passed_interactions: list[dict[str, str]],
) -> bool:
    evidence_rows = [row["row"] for row in passed_command_rows]
    evidence_rows.extend(row["row"] for row in passed_interactions)
    evidence_rows.extend(
        row["row"]
        for row in platform_matrix_rows(content)
        if platform_matrix_row_passed(row)
    )
    return any(positive_post_launch_visual_evidence(row) for row in evidence_rows)


def missing_post_launch_visual_evidence(
    *,
    content: str,
    requirements: list[dict[str, str]],
    passed_command_rows: list[dict[str, str]],
    passed_interactions: list[dict[str, str]],
) -> list[str]:
    evidence_rows = [row["row"] for row in passed_command_rows]
    evidence_rows.extend(row["row"] for row in passed_interactions)
    evidence_rows.extend(
        row["row"]
        for row in platform_matrix_rows(content)
        if platform_matrix_row_passed(row)
    )
    missing: list[str] = []
    for requirement in requirements:
        platform = requirement["platform"]
        rows = [requirement["row"], *evidence_rows]
        if not has_post_launch_visual_evidence_for_platform(platform, rows):
            command = requirement["command"]
            missing.append(command if platform == "all" else f"{platform} ({command})")
    return missing


def has_post_launch_visual_evidence_for_platform(platform: str, rows: list[str]) -> bool:
    return any(
        positive_post_launch_visual_evidence(row)
        and visual_evidence_matches_platform(row, platform)
        for row in rows
    )


def visual_evidence_matches_platform(row: str, platform: str) -> bool:
    if platform == "all":
        return True
    return platform in row.lower()


def split_markdown_row(line: str) -> list[str]:
    stripped = line.strip()
    if not stripped.startswith("|") or not stripped.endswith("|"):
        return []
    columns: list[str] = []
    current: list[str] = []
    escaped = False
    for char in stripped[1:-1]:
        if escaped:
            current.append(char)
            escaped = False
            continue
        if char == "\\":
            escaped = True
            continue
        if char == "|":
            columns.append("".join(current).strip())
            current = []
            continue
        current.append(char)
    columns.append("".join(current).strip())
    return columns


def feedback_rows(content: str) -> list[dict[str, str]]:
    section = section_content(content, "## Fluoh Feedback")
    rows: list[dict[str, str]] = []
    for line in section.splitlines():
        columns = split_markdown_row(line)
        if len(columns) < 6:
            continue
        row_id = columns[0].strip()
        if not row_id or row_id.lower() == "id" or set(row_id) <= {"-"}:
            continue
        if row_id == "...":
            continue
        rows.append(
            {
                "id": row_id,
                "owner": columns[1],
                "category": columns[2],
                "evidence": columns[3],
                "change": columns[4],
                "status": columns[5],
                "row": line,
            }
        )
    return rows


def no_feedback_statement(content: str) -> bool:
    section = section_content(content, "## Fluoh Feedback")
    return (
        re.search(
            r"^\s*No fluoh feedback\s*:\s*\S.+$",
            section,
            re.IGNORECASE | re.MULTILINE,
        )
        is not None
    )


def placeholder_hits(content: str) -> list[str]:
    hits: list[str] = []
    for pattern in PLACEHOLDER_PATTERNS:
        for match in re.finditer(pattern, content, re.MULTILINE | re.IGNORECASE):
            line_start = content.rfind("\n", 0, match.start()) + 1
            line_end = content.find("\n", match.end())
            if line_end == -1:
                line_end = len(content)
            line = content[line_start:line_end].strip()
            if line and line not in hits:
                hits.append(line)
    return hits


def validate(path: Path, *, require_ohos_run: bool = False) -> dict[str, Any]:
    errors: list[str] = []
    warnings: list[str] = []
    filename_error = report_filename_error(path)
    if filename_error:
        errors.append(filename_error)
    if not path.is_file():
        return {
            "schema": 1,
            "ok": False,
            "report": str(path),
            "errors": [*errors, f"Report file does not exist: {path}"],
            "warnings": [],
        }

    content = read_text(path)
    missing_sections = [
        section for section in REQUIRED_SECTIONS if section not in content
    ]
    if missing_sections:
        errors.append(f"Missing sections: {', '.join(missing_sections)}")

    recommendation = release_recommendation(content)
    if recommendation not in ("ready", "needs maintainer decision", "blocked"):
        errors.append(
            "Release recommendation must be ready, needs maintainer decision, or blocked."
        )

    checklist = checklist_items(content)
    if not checklist:
        errors.append("Delivery checklist is missing.")
    unchecked = [item["text"] for item in checklist if not item["done"]]
    if recommendation == "ready" and unchecked:
        errors.append("Ready reports must complete every delivery checklist item.")
    elif unchecked:
        warnings.append("Some delivery checklist items are not complete.")
    if recommendation == "ready":
        checklist_text = [item["text"] for item in checklist]
        missing_checklist = [
            phrase
            for phrase in REQUIRED_READY_CHECKLIST_PHRASES
            if not any(phrase in item for item in checklist_text)
        ]
        if missing_checklist:
            errors.append(
                "Ready reports must include delivery checklist items for: "
                + ", ".join(missing_checklist)
                + "."
            )

    rows = command_rows(content)
    evidence_rows = [
        row
        for row in rows
        if "`...`" not in row["row"] and not re.search(r"\|\s*\.\.\.\s*$", row["row"])
    ]
    if not evidence_rows:
        errors.append("Commands table must include at least one concrete command row.")
    passed_command_rows = [row for row in evidence_rows if command_row_passed(row)]
    if recommendation == "ready" and not passed_command_rows:
        errors.append("Ready reports must include at least one passed command row.")
    passed_verify = any(is_verify_evidence(row) for row in passed_command_rows)
    passed_ohos_build = any(is_ohos_build_evidence(row) for row in passed_command_rows)
    passed_ohos_run = any(is_ohos_run_evidence(row) for row in passed_command_rows)
    if recommendation == "ready" and not passed_verify:
        errors.append("Ready reports must include passed fluoh verify evidence.")
    if recommendation == "ready" and not (passed_ohos_build or passed_ohos_run):
        errors.append("Ready reports must include passed OHOS build or run evidence.")
    if recommendation == "ready" and require_ohos_run and not passed_ohos_run:
        errors.append(
            "Ready reports must include passed fluoh run ohos evidence."
        )
    passed_automation = any(is_automation_evidence(row) for row in passed_command_rows)
    visual_requirements = mobile_visual_requirements(content, passed_command_rows)
    passed_mobile_run_or_drive = bool(visual_requirements)
    post_launch_visual_evidence = False

    coverage_rows = automation_coverage_rows(content)
    coverage_status = automation_coverage_status(content)
    ready_coverage_rows = [
        row for row in coverage_rows if automation_coverage_row_ready(row)
    ]
    unresolved_coverage_rows = [
        row for row in coverage_rows if not automation_coverage_row_ready(row)
    ]
    if recommendation == "ready" and not coverage_rows:
        errors.append(
            "Automation Coverage must include concrete gate rows from fluoh drive --dry-run --json or real run JSON."
        )
    if recommendation == "ready":
        reported_gates = {row["gate"] for row in coverage_rows}
        missing_gates = [
            gate
            for gate in REQUIRED_AUTOMATION_COVERAGE_GATES
            if gate not in reported_gates
        ]
        if missing_gates:
            errors.append(
                "Automation Coverage is missing required gates: "
                + ", ".join(missing_gates)
                + "."
            )
    if recommendation == "ready" and unresolved_coverage_rows:
        unresolved = ", ".join(
            f"{row['gate']} ({row['status']})" for row in unresolved_coverage_rows
        )
        errors.append(f"Automation Coverage has unresolved gates: {unresolved}.")
    if recommendation == "ready":
        if coverage_status["coveragePolicyStatus"] != "readyForExecution":
            errors.append(
                "Automation Coverage must record coveragePolicy.status: readyForExecution for ready reports."
            )
        ready_value = (coverage_status["readyForAutomation"] or "").lower()
        if ready_value != "true":
            errors.append(
                "Automation Coverage must record readyForAutomation: true for ready reports."
            )
        quality_summary = coverage_status["qualityGateSummary"]
        if (
            quality_summary is None
            or not quality_gate_summary_ready(quality_summary)
        ):
            errors.append(
                "Automation Coverage must record qualityGateSummary with zero notReady gates for ready reports."
            )

    interactions = interaction_rows(content)
    concrete_interactions = [
        row
        for row in interactions
        if "`...`" not in row["row"] and not re.search(r"\|\s*\.\.\.\s*$", row["row"])
    ]
    passed_interactions = [
        row for row in concrete_interactions if interaction_row_passed(row)
    ]
    missing_visual_evidence = missing_post_launch_visual_evidence(
        content=content,
        requirements=visual_requirements,
        passed_command_rows=passed_command_rows,
        passed_interactions=passed_interactions,
    )
    post_launch_visual_evidence = (
        not missing_visual_evidence
        if passed_mobile_run_or_drive
        else has_post_launch_visual_evidence(
            content,
            passed_command_rows=passed_command_rows,
            passed_interactions=passed_interactions,
        )
    )
    if (
        recommendation == "ready"
        and passed_mobile_run_or_drive
        and missing_visual_evidence
    ):
        errors.append(
            "Ready reports with passed mobile fluoh run or drive evidence "
            "must record post-launch screenshot or UI-state evidence. Missing: "
            + ", ".join(missing_visual_evidence)
            + "."
        )
    manual_assisted_without_tool_evidence = [
        row
        for row in passed_interactions
        if row["method"].lower() == "manual-assisted"
        and not manual_assisted_tool_readable(row)
    ]
    if manual_assisted_without_tool_evidence:
        errors.append(
            "Passed manual-assisted interaction evidence must include tool-readable confirmation such as logs, meaningful session state beyond launch, stable text, semantics, test keys, command JSON, hilog, or app log markers."
        )
    # A prose note under fluoh run is launch evidence; release gating needs the
    # concrete flutter test command row that produced the integration result.
    integration_test_without_command_evidence = [
        row
        for row in passed_interactions
        if row["method"].lower() == "integration_test"
        and not is_integration_test_evidence(row, passed_command_rows)
    ]
    if integration_test_without_command_evidence:
        errors.append(
            "Passed integration_test interaction evidence must cite and be backed by a passed flutter test integration_test command row."
        )
    passed_integration_test = any(
        is_integration_test_evidence(row, passed_command_rows)
        for row in passed_interactions
    )
    passed_manual_assisted = any(
        row["method"].lower() == "manual-assisted"
        and manual_assisted_tool_readable(row)
        for row in passed_interactions
    )
    if recommendation == "ready" and not (
        passed_automation or passed_integration_test or passed_manual_assisted
    ):
        errors.append(
            "Ready reports must include passed fluoh drive --json, integration_test, or manual-assisted tool-readable interaction evidence."
        )
    interaction_section = section_content(content, "## Interaction Evidence")
    no_interaction_required = re.search(
        r"^\s*No interaction required\s*:\s*\S.+$",
        interaction_section,
        re.IGNORECASE | re.MULTILINE,
    )
    if not concrete_interactions and not no_interaction_required:
        errors.append(
            "Interaction Evidence must include a concrete row or 'No interaction required: <reason>'."
        )
    elif recommendation == "ready" and concrete_interactions and not passed_interactions:
        errors.append("Ready reports with interaction rows must include a passed row.")

    feedback = feedback_rows(content)
    if not feedback and not no_feedback_statement(content):
        errors.append(
            "Fluoh Feedback must include a concrete row or 'No fluoh feedback: <reason>'."
        )
    open_feedback = [
        row
        for row in feedback
        if row["status"].strip().lower() in ("queued", "open", "todo")
    ]
    if open_feedback:
        warnings.append("Fluoh Feedback includes queued or open tool follow-ups.")

    placeholders = placeholder_hits(content)
    if placeholders:
        errors.append("Report still contains placeholder content.")

    return {
        "schema": 1,
        "ok": not errors,
        "report": str(path),
        "recommendation": recommendation,
        "commandRows": len(evidence_rows),
        "passedCommandRows": len(passed_command_rows),
        "passedVerify": passed_verify,
        "passedOhosBuild": passed_ohos_build,
        "passedOhosRun": passed_ohos_run,
        "passedAutomation": passed_automation,
        "passedMobileRunOrDrive": passed_mobile_run_or_drive,
        "postLaunchVisualEvidence": post_launch_visual_evidence,
        "passedIntegrationTest": passed_integration_test,
        "passedManualAssisted": passed_manual_assisted,
        "coveragePolicyStatus": coverage_status["coveragePolicyStatus"],
        "readyForAutomation": coverage_status["readyForAutomation"],
        "qualityGateSummary": coverage_status["qualityGateSummary"],
        "automationCoverageRows": len(coverage_rows),
        "readyAutomationCoverageRows": len(ready_coverage_rows),
        "interactionRows": len(concrete_interactions),
        "passedInteractionRows": len(passed_interactions),
        "feedbackRows": len(feedback),
        "openFeedbackRows": len(open_feedback),
        "checklistTotal": len(checklist),
        "checklistDone": len(checklist) - len(unchecked),
        "unchecked": unchecked,
        "placeholders": placeholders,
        "errors": errors,
        "warnings": warnings,
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate a fluoh AI adaptation report.",
    )
    parser.add_argument(
        "report",
        help="Path to .fluoh/reports/<scope>/report-<timestamp>.md",
    )
    parser.add_argument(
        "--require-ohos-run",
        action="store_true",
        help="Require passed fluoh run ohos evidence for ready reports.",
    )
    args = parser.parse_args()
    result = validate(
        Path(args.report).expanduser().resolve(),
        require_ohos_run=args.require_ohos_run,
    )
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
