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

    placeholders = placeholder_hits(content)
    if placeholders:
        errors.append("Report still contains placeholder content.")

    return {
        "schemaVersion": 1,
        "ok": not errors,
        "report": str(path),
        "recommendation": recommendation,
        "commandRows": len(evidence_rows),
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
