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
    "## Interaction Evidence",
    "## Diagnostics",
    "## Fluoh Feedback",
    "## Signing",
    "## Remaining Risks",
    "## Local State",
    "## Release Decision",
)


PLACEHOLDER_PATTERNS = (
    r"\|\s*`?\.\.\.`?\s*\|",
    r"^\s*-\s*$",
    r"^\s*-\s*\.\.\.\s*$",
    r"\bn/a\s*\|\s*n/a\s*\|\s*\.\.\.",
)


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
        and "--platform ohos" in command
        and "--auto-sign" in command
        and "--json" in command
    )


def is_ohos_run_evidence(row: dict[str, str]) -> bool:
    command = row["command"]
    return (
        command_contains(command, "fluoh run")
        and "--platform ohos" in command
        and "--json" in command
    )


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
            "manual",
        ):
            rows.append(
                {
                    "scenario": columns[0],
                    "method": columns[1],
                    "platform": columns[2],
                    "target": columns[3],
                    "result": columns[4],
                    "row": line,
                }
            )
    return rows


def interaction_row_passed(row: dict[str, str]) -> bool:
    return row["result"].lower() == "passed"


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
    if not path.is_file():
        return {
            "schema": 1,
            "ok": False,
            "report": str(path),
            "errors": [f"Report file does not exist: {path}"],
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
            "Ready reports must include passed fluoh run --platform ohos evidence."
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
        help="Path to .fluoh/reports/<scope>/ai-report-...md",
    )
    parser.add_argument(
        "--require-ohos-run",
        action="store_true",
        help="Require passed fluoh run --platform ohos evidence for ready reports.",
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
