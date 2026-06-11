#!/usr/bin/env python3
"""Create a local fluoh monorepo adaptation summary report."""

from __future__ import annotations

import argparse
import re
import subprocess
from datetime import datetime
from pathlib import Path


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""


def slug(value: str) -> str:
    normalized = re.sub(r"[^A-Za-z0-9._-]+", "-", value.strip())
    normalized = normalized.strip("-._")
    return normalized or "monorepo"


def clean_scalar(value: str) -> str:
    value = value.split("#", 1)[0].strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
        return value[1:-1]
    return value


def run(command: list[str], cwd: Path) -> str:
    try:
        result = subprocess.run(
            command,
            cwd=str(cwd),
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return ""
    if result.returncode != 0:
        return ""
    return result.stdout.strip()


def infer_repository(root: Path) -> str:
    return run(["git", "remote", "get-url", "origin"], root) or str(root)


def infer_sdk(root: Path) -> str:
    content = read_text(root / "fluoh.yaml")
    in_sdk = False
    for line in content.splitlines():
        if re.match(r"^sdk\s*:\s*(?:#.*)?$", line):
            in_sdk = True
            continue
        if in_sdk and line and not line.startswith((" ", "\t", "#")):
            break
        match = re.match(r"^\s+version\s*:\s*(.+?)\s*$", line)
        if in_sdk and match:
            return clean_scalar(match.group(1))
    return ""


def sdk_line(sdk: str) -> str:
    match = re.match(r"^(\d+)\.(\d+)\.\d+-ohos-.+$", sdk)
    if match:
        return f"{match.group(1)}.{match.group(2)}"
    return ""


def infer_branch(root: Path, package: str, sdk: str) -> str:
    line = sdk_line(sdk)
    if line:
        candidate = f"ohos/{line}/{package}"
        exists = run(["git", "rev-parse", "--verify", candidate], root)
        if exists:
            return candidate
    branches = run(["git", "branch", "--list", f"ohos/*/{package}"], root)
    for line_text in branches.splitlines():
        branch = line_text.replace("*", "", 1).strip()
        if branch:
            return branch
    return ""


def unique_report_path(output_root: Path, name: str) -> Path:
    candidate = output_root / f"{name}.md"
    if not candidate.exists():
        return candidate
    for index in range(2, 1000):
        candidate = output_root / f"{name}-{index}.md"
        if not candidate.exists():
            return candidate
    raise RuntimeError(f"Could not create a unique summary path for {name}")


def package_row(root: Path, package: str, sdk: str) -> dict[str, str]:
    name = package.strip()
    branch = infer_branch(root, name, sdk)
    report_glob = root / ".fluoh" / "reports" / slug(name)
    reports = (
        sorted(
            report
            for report in report_glob.glob("ai-report-*.md")
            if re.match(r"^ai-report-\d{8}-\d{6}(?:-\d+)?\.md$", report.name)
        )
        if report_glob.is_dir()
        else []
    )
    return {
        "package": name,
        "branch": branch or "<branch>",
        "upstream": "<upstream version>",
        "sdk": sdk or "<FlutterOH SDK>",
        "status": "queued",
        "report": reports[-1].relative_to(root).as_posix() if reports else "<report>",
    }


def build_summary(root: Path, scope: str, packages: list[str], sdk: str) -> str:
    now = datetime.now().astimezone().strftime("%Y-%m-%d %H:%M:%S %Z")
    package_names = packages or ["<package>"]
    rows = [package_row(root, package, sdk) for package in package_names]
    table = [
        "| Package | Branch | Upstream version | FlutterOH SDK | Status | Report |",
        "| --- | --- | --- | --- | --- | --- |",
    ]
    for row in rows:
        table.append(
            "| {package} | {branch} | {upstream} | {sdk} | {status} | {report} |".format(
                **row
            )
        )
    package_list = ", ".join(package_names)
    return "\n".join(
        [
            "# fluoh Monorepo Summary",
            "",
            f"- Scope: {scope}",
            f"- Repository: {infer_repository(root)}",
            f"- Packages: {package_list}",
            f"- FlutterOH SDK: {sdk or '<FlutterOH SDK>'}",
            f"- Date: {now}",
            "",
            "## Package Matrix",
            "",
            *table,
            "",
            "## Command Evidence",
            "",
            "| Command | Exit code | Status | Notes |",
            "| --- | ---: | --- | --- |",
            "| `fluoh package queue <package-path>... --json` | <exit> | <status> | queue resolved |",
            "| `fluoh verify --package <name> --json --trace-dir <trace-dir>` | <exit> | <status> | per-package verification |",
            "",
            "## Repository State",
            "",
            "- Current branch: <branch>",
            "- Working tree after latest verify: <clean|dirty>",
            "- Generated files changed: <yes|no>",
            "",
            "## Fluoh Feedback",
            "",
            "| ID | Owner | Category | Evidence | Suggested change | Status |",
            "| --- | --- | --- | --- | --- | --- |",
            "| <id> | <owner> | <category> | <evidence> | <change> | <queued|closed> |",
            "",
            "## Next Actions",
            "",
            "- Finish one package branch checkpoint before moving to the next package.",
            "- Keep the latest upstream target and plan package config/code to the selected FlutterOH SDK unless maintainers explicitly approve an older baseline.",
            "- Link each completed package report from the Package Matrix.",
            "",
        ]
    )


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Create a .fluoh monorepo adaptation summary report.",
    )
    parser.add_argument("path", nargs="?", default=".", help="Project directory")
    parser.add_argument(
        "--scope",
        default="",
        help="Summary scope. Defaults to the project directory name.",
    )
    parser.add_argument(
        "--package",
        action="append",
        default=[],
        help="Package name to include. Repeat for multiple packages.",
    )
    parser.add_argument("--sdk", default="", help="FlutterOH SDK version")
    parser.add_argument(
        "--output-root",
        default="",
        help="Report directory. Defaults to <path>/.fluoh/reports/<scope>.",
    )
    args = parser.parse_args()

    root = Path(args.path).expanduser().resolve()
    if not root.is_dir():
        parser.error(f"Project directory does not exist: {root}")

    scope = args.scope or root.name
    output_root = (
        Path(args.output_root).expanduser().resolve()
        if args.output_root
        else root / ".fluoh" / "reports" / slug(scope)
    )
    output_root.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now().astimezone().strftime("%Y%m%d-%H%M%S")
    report_path = unique_report_path(output_root, f"summary-{timestamp}")
    sdk = args.sdk or infer_sdk(root)
    report_path.write_text(
        build_summary(root, scope, args.package, sdk),
        encoding="utf-8",
    )
    print(report_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
