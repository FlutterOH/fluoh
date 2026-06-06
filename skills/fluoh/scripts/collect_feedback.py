#!/usr/bin/env python3
"""Collect fluoh trace feedback candidates for AI delivery reports."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def trace_manifests(path: Path) -> list[Path]:
    if path.is_file():
        return [path]
    if not path.is_dir():
        return []
    direct = path / "trace.json"
    if direct.is_file():
        return [direct]
    return sorted(path.glob("**/trace.json"))


def as_list(value: Any) -> list[Any]:
    return value if isinstance(value, list) else []


def as_dict(value: Any) -> dict[str, Any]:
    return value if isinstance(value, dict) else {}


def candidate_key(item: dict[str, Any]) -> tuple[str, str, str, str]:
    return (
        str(item.get("trace", "")),
        str(item.get("invocationCommand", "")),
        str(item.get("id", "")),
        str(item.get("diagnosticCode", "")),
    )


def collect_manifest(path: Path) -> tuple[dict[str, Any] | None, list[dict[str, Any]]]:
    manifest = read_json(path)
    trace_id = str(manifest.get("id") or path.parent.name)
    feedback: list[dict[str, Any]] = []
    invocations = as_list(manifest.get("invocations"))
    if invocations:
        for index, invocation_raw in enumerate(invocations):
            invocation = as_dict(invocation_raw)
            command = str(invocation.get("command") or "")
            command_line = str(invocation.get("commandLine") or "")
            for candidate_raw in as_list(invocation.get("feedbackCandidates")):
                candidate = as_dict(candidate_raw)
                if not candidate:
                    continue
                feedback.append(
                    {
                        **candidate,
                        "trace": trace_id,
                        "traceManifest": str(path),
                        "invocationIndex": index,
                        "invocationCommand": command,
                        "invocationCommandLine": command_line,
                    }
                )
    else:
        for candidate_raw in as_list(manifest.get("feedbackCandidates")):
            candidate = as_dict(candidate_raw)
            if not candidate:
                continue
            feedback.append(
                {
                    **candidate,
                    "trace": trace_id,
                    "traceManifest": str(path),
                    "invocationIndex": 0,
                    "invocationCommand": str(manifest.get("command") or ""),
                    "invocationCommandLine": str(manifest.get("commandLine") or ""),
                }
            )
    trace = {
        "id": trace_id,
        "manifest": str(path),
        "invocations": len(invocations) if invocations else 1,
        "feedbackCandidates": len(feedback),
    }
    return trace, feedback


def markdown_table(feedback: list[dict[str, Any]]) -> str:
    if not feedback:
        return (
            "No fluoh feedback: diagnostics were actionable and no tool or "
            "Source gap was found."
        )
    lines = [
        "| ID | Owner | Category | Evidence | Proposed fluoh change | Status |",
        "| --- | --- | --- | --- | --- | --- |",
    ]
    for item in feedback:
        evidence = ", ".join(
            part
            for part in (
                str(item.get("trace") or ""),
                str(item.get("invocationCommand") or ""),
                str(item.get("diagnosticCode") or ""),
            )
            if part
        )
        lines.append(
            "| {id} | {owner} | {category} | {evidence} | {change} | queued |".format(
                id=escape_markdown(str(item.get("id") or "")),
                owner=escape_markdown(str(item.get("owner") or "")),
                category=escape_markdown(str(item.get("category") or "")),
                evidence=escape_markdown(evidence),
                change=escape_markdown(str(item.get("suggestedChange") or "")),
            )
        )
    return "\n".join(lines)


def escape_markdown(value: str) -> str:
    return value.replace("|", "\\|").replace("\n", " ").strip()


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Collect feedback candidates from fluoh trace manifests.",
    )
    parser.add_argument(
        "paths",
        nargs="+",
        help="Trace directory, trace.json, or directory containing trace manifests.",
    )
    args = parser.parse_args()

    manifests: list[Path] = []
    missing: list[str] = []
    for raw in args.paths:
        path = Path(raw).expanduser().resolve()
        found = trace_manifests(path)
        if not found:
            missing.append(str(path))
            continue
        manifests.extend(found)

    traces: list[dict[str, Any]] = []
    feedback: list[dict[str, Any]] = []
    errors: list[str] = []
    for manifest in sorted(set(manifests)):
        try:
            trace, candidates = collect_manifest(manifest)
        except (OSError, json.JSONDecodeError) as error:
            errors.append(f"{manifest}: {error}")
            continue
        if trace is not None:
            traces.append(trace)
        feedback.extend(candidates)

    deduped: list[dict[str, Any]] = []
    seen: set[tuple[str, str, str, str]] = set()
    for item in feedback:
        key = candidate_key(item)
        if key in seen:
            continue
        seen.add(key)
        deduped.append(item)

    ok = not missing and not errors
    result = {
        "schema": 1,
        "ok": ok,
        "traces": traces,
        "feedback": deduped,
        "feedbackCount": len(deduped),
        "markdown": markdown_table(deduped),
        "missing": missing,
        "errors": errors,
    }
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
