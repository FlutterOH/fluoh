#!/usr/bin/env python3
"""Create a fluoh AI-assisted interaction scenario from the bundled template."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""


def slug(value: str) -> str:
    normalized = re.sub(r"[^A-Za-z0-9._-]+", "-", value.strip())
    normalized = normalized.strip("-._")
    return normalized or "scenario"


def infer_scope(root: Path) -> str:
    return slug(root.name or "app")


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


def clean_scalar(value: str) -> str:
    value = value.split("#", 1)[0].strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
        return value[1:-1]
    return value


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


def run_command_for(
    platform: str,
    package: str,
    app: bool,
    session_file: str = "",
) -> str:
    session_part = f" --session-file {session_file}" if session_file else ""
    if app:
        if platform == "ohos":
            return f"fluoh run --platform ohos --device <id>{session_part} --json"
        return f"fluoh run --platform {platform} --device <id>{session_part} --json"
    package_part = f" --package {package}" if package else " --package <name>"
    return f"fluoh run --platform {platform}{package_part}{session_part} --json"


def session_file_for(scope: str, platform: str) -> str:
    return f".fluoh/run-sessions/{slug(scope)}/{platform}-session.json"


def session_command_for(platform: str, package: str, app: bool, scope: str) -> str:
    if platform == "ohos":
        return "not supported for ohos run"
    return run_command_for(platform, package, app, session_file_for(scope, platform))


def session_inspect_command_for(platform: str, scope: str) -> str:
    if platform == "ohos":
        return "not supported for ohos run"
    session_file = session_file_for(scope, platform)
    return (
        f"python3 <skill-dir>/scripts/inspect_session.py {session_file} "
        f"--wait 30 --expect-platform {platform}"
    )


def build_scenario(
    template: str,
    root: Path,
    scope: str,
    package: str,
    platform: str,
    name: str,
    app: bool,
) -> str:
    content = template.strip() + "\n"
    fields = {
        "Scope": scope,
        "Package or app": package or scope,
        "Platform": platform,
        "Target requirement": "host" if platform == "macos" else "emulator or device",
        "Related command": run_command_for(platform, package, app),
        "Session file command, when supported": session_command_for(
            platform,
            package,
            app,
            scope,
        ),
        "Session inspect command, when supported": session_inspect_command_for(
            platform,
            scope,
        ),
        "Observation mode": "flutter-debug | widget-tree | log-marker",
        "Selected FlutterOH SDK": infer_sdk(root),
        "Example path": "." if app else "example",
    }
    for label, value in fields.items():
        content = replace_field(content, label, value)
    content = content.replace("# fluoh Interaction Scenario", f"# {name}")
    return content


def unique_path(output_root: Path, name: str) -> Path:
    candidate = output_root / f"{name}.md"
    if not candidate.exists():
        return candidate
    for index in range(2, 1000):
        candidate = output_root / f"{name}-{index}.md"
        if not candidate.exists():
            return candidate
    raise RuntimeError(f"Could not create a unique scenario path for {name}")


def default_output_root(root: Path, scope: str) -> Path:
    return root / ".fluoh" / "scenarios" / slug(scope)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Create a .fluoh AI-assisted interaction scenario.",
    )
    parser.add_argument("path", nargs="?", default=".", help="Project directory")
    parser.add_argument(
        "--platform",
        required=True,
        choices=("ohos", "android", "ios", "macos"),
        help="Target platform for this scenario",
    )
    parser.add_argument("--name", required=True, help="Scenario name")
    parser.add_argument("--scope", default="", help="Scenario scope")
    parser.add_argument("--package", default="", help="Package name")
    parser.add_argument(
        "--app",
        action="store_true",
        help="Create an app-project scenario instead of a package scenario",
    )
    parser.add_argument(
        "--output-root",
        default="",
        help="Scenario directory. Defaults to <path>/.fluoh/scenarios/<scope>.",
    )
    parser.add_argument(
        "--template",
        default="",
        help="Template path. Defaults to references/interaction-scenario-template.md.",
    )
    args = parser.parse_args()

    root = Path(args.path).expanduser().resolve()
    if not root.is_dir():
        parser.error(f"Project directory does not exist: {root}")

    skill_root = Path(__file__).resolve().parents[1]
    template_path = (
        Path(args.template).expanduser().resolve()
        if args.template
        else skill_root / "references" / "interaction-scenario-template.md"
    )
    if not template_path.is_file():
        parser.error(f"Scenario template does not exist: {template_path}")

    scope = args.scope or args.package or infer_scope(root)
    output_root_was_explicit = bool(args.output_root)
    file_name = (
        f"{slug(scope)}-{args.platform}-{slug(args.name)}"
        if output_root_was_explicit
        else f"{args.platform}-{slug(args.name)}"
    )
    output_root = (
        Path(args.output_root).expanduser().resolve()
        if args.output_root
        else default_output_root(root, scope)
    )
    output_root.mkdir(parents=True, exist_ok=True)
    scenario_path = unique_path(output_root, file_name)
    scenario_path.write_text(
        build_scenario(
            read_text(template_path),
            root,
            scope,
            args.package,
            args.platform,
            args.name,
            args.app,
        ),
        encoding="utf-8",
    )
    print(scenario_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
