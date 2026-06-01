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
    "## Commands",
    "## Delivery Checklist",
    "## Platform Matrix",
    "## Interaction Evidence",
    "## Diagnostics",
    "## Remaining Risks",
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
    return match.group(1).strip().lower()


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


def command_rows(content: str) -> list[str]:
    rows: list[str] = []
    in_commands = False
    for line in content.splitlines():
        if line.strip() == "## Commands":
            in_commands = True
            continue
        if in_commands and line.startswith("## "):
            break
        if not in_commands:
            continue
        if re.match(r"^\|\s*`[^`]+`\s*\|", line):
            rows.append(line)
    return rows


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


def interaction_rows(content: str) -> list[str]:
    section = section_content(content, "## Interaction Evidence")
    rows: list[str] = []
    for line in section.splitlines():
        columns = [column.strip() for column in line.strip().strip("|").split("|")]
        if len(columns) >= 6 and columns[1].lower() in (
            "integration_test",
            "ai-assisted",
            "manual",
        ):
            rows.append(line)
    return rows


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


def validate(path: Path) -> dict[str, Any]:
    errors: list[str] = []
    warnings: list[str] = []
    if not path.is_file():
        return {
            "schemaVersion": 1,
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
        if "`...`" not in row and not re.search(r"\|\s*\.\.\.\s*$", row)
    ]
    if not evidence_rows:
        errors.append("Commands table must include at least one concrete command row.")

    interactions = interaction_rows(content)
    concrete_interactions = [
        row
        for row in interactions
        if "`...`" not in row and not re.search(r"\|\s*\.\.\.\s*$", row)
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

    placeholders = placeholder_hits(content)
    if placeholders:
        errors.append("Report still contains placeholder content.")

    return {
        "schemaVersion": 1,
        "ok": not errors,
        "report": str(path),
        "recommendation": recommendation,
        "commandRows": len(evidence_rows),
        "interactionRows": len(concrete_interactions),
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
    parser.add_argument("report", help="Path to .fluoh/ai-report-...md")
    args = parser.parse_args()
    result = validate(Path(args.report).expanduser().resolve())
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
