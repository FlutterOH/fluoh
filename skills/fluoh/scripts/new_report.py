#!/usr/bin/env python3
"""Create a local fluoh AI adaptation report from the bundled template."""

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


def fenced_template(content: str) -> str:
    match = re.search(r"```md\n(.*?)\n```", content, re.DOTALL)
    if match:
        return match.group(1).strip() + "\n"
    return content.strip() + "\n"


def slug(value: str) -> str:
    normalized = re.sub(r"[^A-Za-z0-9._-]+", "-", value.strip())
    normalized = normalized.strip("-._")
    return normalized or "adaptation"


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
    remote = run(["git", "remote", "get-url", "origin"], root)
    return remote or str(root)


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

    for pattern in (
        r"^sdk\s*:\s*['\"]?([^'\"\s#]+)",
        r"^\s+sdk\s*:\s*['\"]?([^'\"\s#]+)",
        r"^sdkVersion\s*:\s*['\"]?([^'\"\s#]+)",
    ):
        match = re.search(pattern, content, re.MULTILINE)
        if match:
            return clean_scalar(match.group(1))
    return ""


def recommendation_label(value: str) -> str:
    return value.replace("-", " ")


def replace_field(content: str, label: str, value: str) -> str:
    if value == "":
        return content
    return re.sub(
        rf"^- {re.escape(label)}:.*$",
        f"- {label}: {value}",
        content,
        count=1,
        flags=re.MULTILINE,
    )


def build_report(
    template: str,
    root: Path,
    scope: str,
    package: str,
    upstream_version: str,
    sdk: str,
    recommendation: str,
) -> str:
    content = fenced_template(template)
    now = datetime.now().astimezone().strftime("%Y-%m-%d %H:%M:%S %Z")
    fields = {
        "Scope": scope,
        "Repository": infer_repository(root),
        "Package": package,
        "Upstream version": upstream_version,
        "FlutterOH SDK": sdk or infer_sdk(root),
        "Date": now,
        "Recommendation": recommendation_label(recommendation),
    }
    for label, value in fields.items():
        content = replace_field(content, label, value)
    content = re.sub(
        r"^Release recommendation:.*$",
        f"Release recommendation: {recommendation_label(recommendation)}",
        content,
        count=1,
        flags=re.MULTILINE,
    )
    return content


def unique_report_path(output_root: Path, name: str) -> Path:
    candidate = output_root / f"{name}.md"
    if not candidate.exists():
        return candidate
    for index in range(2, 1000):
        candidate = output_root / f"{name}-{index}.md"
        if not candidate.exists():
            return candidate
    raise RuntimeError(f"Could not create a unique report path for {name}")


def default_output_root(root: Path, scope: str, package: str) -> Path:
    group = slug(package or scope)
    return root / ".fluoh" / "reports" / group


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Create a .fluoh AI adaptation report.",
    )
    parser.add_argument("path", nargs="?", default=".", help="Project directory")
    parser.add_argument(
        "--scope",
        default="",
        help="Report scope. Defaults to package name, then directory name.",
    )
    parser.add_argument("--package", default="", help="Package name")
    parser.add_argument("--upstream-version", default="", help="Upstream version")
    parser.add_argument("--sdk", default="", help="FlutterOH SDK version")
    parser.add_argument(
        "--recommendation",
        choices=("ready", "needs-maintainer-decision", "blocked"),
        default="needs-maintainer-decision",
        help="Initial release recommendation",
    )
    parser.add_argument(
        "--output-root",
        default="",
        help="Report directory. Defaults to <path>/.fluoh/reports/<scope>.",
    )
    parser.add_argument(
        "--template",
        default="",
        help="Template path. Defaults to references/report-template.md.",
    )
    args = parser.parse_args()

    root = Path(args.path).expanduser().resolve()
    if not root.is_dir():
        parser.error(f"Project directory does not exist: {root}")

    skill_root = Path(__file__).resolve().parents[1]
    template_path = (
        Path(args.template).expanduser().resolve()
        if args.template
        else skill_root / "references" / "report-template.md"
    )
    if not template_path.is_file():
        parser.error(f"Report template does not exist: {template_path}")

    output_root = (
        Path(args.output_root).expanduser().resolve()
        if args.output_root
        else default_output_root(
            root,
            args.scope or args.package or root.name,
            args.package,
        )
    )
    scope = args.scope or args.package or root.name
    timestamp = datetime.now().astimezone().strftime("%Y%m%d-%H%M%S")
    report_name = f"ai-report-{slug(scope)}-{timestamp}"

    output_root.mkdir(parents=True, exist_ok=True)
    report_path = unique_report_path(output_root, report_name)
    content = build_report(
        read_text(template_path),
        root,
        scope,
        args.package,
        args.upstream_version,
        args.sdk,
        args.recommendation,
    )
    report_path.write_text(content, encoding="utf-8")
    print(report_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
