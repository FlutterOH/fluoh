#!/usr/bin/env python3
"""Read-only fluoh skill preflight.

Prints one JSON object describing the current workspace shape, installed
`fluoh --version` result, Git state, and likely next commands. This script
intentionally does not modify files.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import subprocess
from pathlib import Path
from typing import Any


def run(command: list[str], cwd: Path, timeout: int = 20) -> dict[str, Any]:
    try:
        result = subprocess.run(
            command,
            cwd=str(cwd),
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
        return {
            "ok": result.returncode == 0,
            "exitCode": result.returncode,
            "stdout": result.stdout.strip(),
            "stderr": result.stderr.strip(),
        }
    except FileNotFoundError as error:
        return {
            "ok": False,
            "exitCode": None,
            "stdout": "",
            "stderr": str(error),
        }
    except OSError as error:
        return {
            "ok": False,
            "exitCode": None,
            "stdout": "",
            "stderr": str(error),
        }
    except subprocess.TimeoutExpired as error:
        return {
            "ok": False,
            "exitCode": None,
            "stdout": (error.stdout or "").strip()
            if isinstance(error.stdout, str)
            else "",
            "stderr": f"Timed out after {timeout}s",
        }


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""


def top_level_key(content: str, key: str) -> bool:
    return re.search(rf"^{re.escape(key)}\s*:", content, re.MULTILINE) is not None


def top_level_block(content: str, key: str) -> str:
    lines: list[str] = []
    in_section = False
    for line in content.splitlines():
        if re.match(rf"^{re.escape(key)}\s*:", line):
            in_section = True
            continue
        if in_section and line and not line.startswith((" ", "\t", "#")):
            break
        if in_section:
            lines.append(line)
    return "\n".join(lines)


def section_has_key(content: str, section: str, key: str) -> bool:
    block = top_level_block(content, section)
    return re.search(rf"^\s+{re.escape(key)}\s*:", block, re.MULTILINE) is not None


def is_flutter_pubspec(content: str) -> bool:
    return (
        section_has_key(content, "dependencies", "flutter")
        or section_has_key(content, "dev_dependencies", "flutter_test")
        or top_level_key(content, "flutter")
    )


def is_flutter_plugin_pubspec(content: str) -> bool:
    return re.search(
        r"^\s+plugin\s*:",
        top_level_block(content, "flutter"),
        re.MULTILINE,
    ) is not None


def clean_scalar(value: str) -> str:
    value = value.split("#", 1)[0].strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
        return value[1:-1]
    return value


def top_level_scalar(content: str, key: str) -> str | None:
    match = re.search(
        rf"^{re.escape(key)}\s*:\s*(.+?)\s*$",
        content,
        re.MULTILINE,
    )
    if not match:
        return None
    return clean_scalar(match.group(1)) or None


def package_entries(content: str, root: Path) -> list[dict[str, Any]]:
    packages: list[dict[str, Any]] = []
    current: dict[str, Any] | None = None
    section: str | None = None
    in_packages = False
    for line in content.splitlines():
        if re.match(r"^packages\s*:\s*$", line):
            in_packages = True
            continue
        if in_packages and line and not line.startswith((" ", "\t", "#")):
            break
        match = re.match(r"^  ([A-Za-z0-9_][A-Za-z0-9_-]*)\s*:", line)
        if in_packages and match:
            current = {"name": match.group(1), "path": None}
            packages.append(current)
            section = None
            continue
        if current is None:
            continue
        section_match = re.match(r"^    ([A-Za-z0-9_-]+)\s*:\s*$", line)
        if section_match:
            section = section_match.group(1)
            continue
        path_match = re.match(r"^      path\s*:\s*(.+?)\s*$", line)
        if path_match and section == "repository":
            current["path"] = clean_scalar(path_match.group(1))

    for package in packages:
        path = package["path"]
        package_root = root / path if path else root
        example_root = package_root / "example"
        package["examplePlatforms"] = {
            "ohos": (example_root / "ohos").is_dir(),
            "android": (example_root / "android").is_dir(),
            "ios": (example_root / "ios").is_dir(),
            "macos": (example_root / "macos").is_dir(),
        }
    return packages


def sdk_version(content: str) -> str | None:
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
            return match.group(1)
    return None


def git_state(root: Path) -> dict[str, Any]:
    inside = run(["git", "rev-parse", "--is-inside-work-tree"], root, timeout=10)
    if not inside["ok"] or inside["stdout"] != "true":
        return {"isRepository": False}
    branch = run(["git", "branch", "--show-current"], root, timeout=10)
    status = run(["git", "status", "--short"], root, timeout=10)
    return {
        "isRepository": True,
        "branch": branch["stdout"] if branch["ok"] else None,
        "dirty": bool(status["stdout"].strip()) if status["ok"] else None,
        "statusShort": status["stdout"].splitlines() if status["stdout"] else [],
    }


def project_info(root: Path, requested_package: str | None = None) -> dict[str, Any]:
    fluoh_yaml = root / "fluoh.yaml"
    pubspec = root / "pubspec.yaml"
    content = read_text(fluoh_yaml) if fluoh_yaml.exists() else ""
    pubspec_content = read_text(pubspec) if pubspec.exists() else ""
    packages = package_entries(content, root)
    package_names = [package["name"] for package in packages]
    registers_packages = top_level_key(content, "packages")
    has_example = (root / "example" / "pubspec.yaml").is_file()
    has_app_entry = (root / "lib" / "main.dart").is_file()
    has_flutter = is_flutter_pubspec(pubspec_content)
    has_flutter_plugin = is_flutter_plugin_pubspec(pubspec_content)
    if registers_packages:
        kind = "package-repository"
    elif pubspec.exists() and has_flutter_plugin:
        kind = "flutter-package"
    elif pubspec.exists() and has_flutter and has_example and not has_app_entry:
        kind = "flutter-package"
    elif pubspec.exists() and has_flutter:
        kind = "app-project"
    elif pubspec.exists():
        kind = "dart-package"
    else:
        kind = "unknown"
    if requested_package:
        package_selection_valid = requested_package in package_names
        selected_package = requested_package if package_selection_valid else None
    else:
        package_selection_valid = None
        selected_package = package_names[0] if len(package_names) == 1 else None
    return {
        "kind": kind,
        "pathExists": root.exists(),
        "pathIsDirectory": root.is_dir(),
        "hasPubspec": pubspec.exists(),
        "hasFluohYaml": fluoh_yaml.exists(),
        "registersPackages": registers_packages,
        "name": top_level_scalar(pubspec_content, "name"),
        "isFlutter": has_flutter,
        "isFlutterPlugin": has_flutter_plugin,
        "hasExample": has_example,
        "hasAppEntry": has_app_entry,
        "packageNames": package_names,
        "packages": packages,
        "requestedPackage": requested_package,
        "selectedPackage": selected_package,
        "packageSelectionValid": package_selection_valid,
        "needsPackageSelection": registers_packages
        and len(package_names) > 1
        and selected_package is None,
        "sdkVersion": sdk_version(content),
        "platformDirectories": {
            "ohos": (root / "ohos").is_dir(),
            "android": (root / "android").is_dir(),
            "ios": (root / "ios").is_dir(),
            "macos": (root / "macos").is_dir(),
        },
    }


def suggested_commands(info: dict[str, Any]) -> list[str]:
    project = info["project"]
    kind = project["kind"]
    if kind == "app-project":
        sdk = project["sdkVersion"] or "<sdk-version-or-line>"
        return [
            "fluoh source update",
            f"fluoh sdk use {sdk} --pub-get",
            "fluoh deps check --json",
            "fluoh deps fix --dry-run",
            "fluoh deps fix",
            "fluoh deps get",
            "fluoh doctor -p --platform ohos --json --strict",
            "fluoh build --platform ohos --auto-sign --json",
            "fluoh devices --platform ohos --json",
            "fluoh run --platform ohos --device <id> --json",
        ]
    if kind == "package-repository":
        package = project["selectedPackage"] or "<name>"
        return [
            "fluoh deps get",
            "fluoh doctor -p --json --strict",
            f"fluoh verify --package {package} --json",
            f"fluoh run --platform ohos --package {package} --json",
            f"fluoh build --platform ohos --package {package} --auto-sign --json",
            f"fluoh package status --package {package}",
            f"fluoh package release --package {package} --dry-run --json",
        ]
    if kind == "flutter-package":
        package = project["name"] or "<package-name>"
        output = flutter_package_output(project)
        upstream = shlex.quote(info["cwd"])
        return [
            f"fluoh package create {upstream} --package-path . --output {output}",
            f"cd {output}",
            f"fluoh verify --package {package} --json",
            f"fluoh run --platform ohos --package {package} --json",
            f"fluoh build --platform ohos --package {package} --auto-sign --json",
            f"fluoh package status --package {package}",
            f"fluoh package release --package {package} --dry-run --json",
        ]
    if kind == "dart-package":
        return [
            "This is a Dart package, not a Flutter app or FlutterOH package repository; ask for a Flutter project/package path before editing.",
        ]
    return [
        "Run this from a Flutter project, a FlutterOH package repository, or create one with fluoh package create <upstream>.",
    ]


def final_check_commands(info: dict[str, Any]) -> list[str]:
    project = info["project"]
    kind = project["kind"]
    if kind == "app-project":
        return [
            "git diff --check",
            "fluoh doctor -p --platform ohos --json --strict",
            "fluoh build --platform ohos --auto-sign --json",
            "fluoh devices --platform ohos --json",
            "fluoh run --platform ohos --device <id> --json",
        ]
    if kind == "package-repository":
        package = project["selectedPackage"] or "<name>"
        return [
            "git diff --check",
            f"fluoh verify --package {package} --json",
            f"fluoh package status --package {package}",
            f"fluoh package release --package {package} --dry-run --json",
        ]
    if kind == "flutter-package":
        return []
    return []


def delivery_checks(info: dict[str, Any]) -> list[str]:
    project = info["project"]
    kind = project["kind"]
    if kind == "app-project":
        return [
            "Create or update .fluoh/ai-report-...md before the final response.",
            "Record deps, doctor, build, and run command results with exit codes.",
            "If no OHOS target is available, record the signed build as build-only evidence and explain the missing target.",
            "Review the diff and remove unrelated local paths, generated caches, credentials, and private tokens.",
            "State ready, blocked, or needs maintainer decision in the final response.",
        ]
    if kind == "package-repository":
        package = project["selectedPackage"] or "<name>"
        return [
            f"Create or update .fluoh/ai-report-{package}-...md before the final response.",
            f"Record verify, status, and release dry-run results for {package} with exit codes.",
            f"Record OHOS build/run evidence for {package}, or explain the device/build blocker.",
            "Record relevant Android, iOS, and macOS regression checks when examples exist.",
            "Review public API compatibility, dependency constraints, and non-OHOS regression risk.",
            "Review the diff and remove unrelated local paths, generated caches, credentials, and private tokens.",
            "State ready, blocked, or needs maintainer decision in the final response.",
        ]
    if kind == "flutter-package":
        package = project["name"] or "<package-name>"
        output = flutter_package_output(project)
        return [
            "Create a FlutterOH package repository before editing OHOS implementation files.",
            f"Rerun preflight in {output} before using final check commands.",
            f"Create or update .fluoh/ai-report-{package}-...md in the generated repository before the final response.",
            f"Record verify, status, and release dry-run results for {package} with exit codes.",
            f"Record OHOS build/run evidence for {package}, or explain the device/build blocker.",
            "Review public API compatibility, dependency constraints, and non-OHOS regression risk.",
            "State ready, blocked, or needs maintainer decision in the final response.",
        ]
    return [
        "Choose a Flutter app project or FlutterOH package repository before editing.",
        "Do not make project changes until preflight can identify the workspace shape.",
    ]


def flutter_package_output(project: dict[str, Any]) -> str:
    package = project["name"] or "<package-name>"
    if package == "<package-name>":
        return "../<package-name>_ohos"
    return f"../{package}_ohos"


def report_command(project: dict[str, Any]) -> str:
    if project["kind"] == "package-repository":
        scope = project["selectedPackage"] or "<name>"
        package = scope
        return (
            "python3 <skill-dir>/scripts/new_report.py . "
            f"--scope {scope} --package {package}"
        )
    if project["kind"] == "flutter-package":
        package = project["name"] or "<package-name>"
        output = flutter_package_output(project)
        return (
            f"python3 <skill-dir>/scripts/new_report.py {output} "
            f"--scope {package} --package {package}"
        )
    scope = project["name"] or "app"
    return f"python3 <skill-dir>/scripts/new_report.py . --scope {scope}"


def report_check_command() -> str:
    return "python3 <skill-dir>/scripts/check_report.py <report-path>"


def session_inspect_command() -> str:
    return (
        "python3 <skill-dir>/scripts/inspect_session.py <session-file> "
        "--wait 30 --expect-platform <platform>"
    )


def scenario_command(project: dict[str, Any]) -> str:
    if project["kind"] == "package-repository":
        package = project["selectedPackage"] or "<name>"
        return (
            "python3 <skill-dir>/scripts/new_scenario.py . "
            f"--scope {package} --package {package} "
            "--platform <platform> --name <scenario-name>"
        )
    if project["kind"] == "flutter-package":
        package = project["name"] or "<package-name>"
        output = flutter_package_output(project)
        return (
            f"python3 <skill-dir>/scripts/new_scenario.py {output} "
            f"--scope {package} --package {package} "
            "--platform <platform> --name <scenario-name>"
        )
    scope = project["name"] or "app"
    return (
        "python3 <skill-dir>/scripts/new_scenario.py . "
        f"--scope {scope} --app --platform <platform> --name <scenario-name>"
    )


def notes(project: dict[str, Any]) -> list[str]:
    if not project["pathExists"]:
        return ["Path does not exist."]
    if not project["pathIsDirectory"]:
        return ["Path exists but is not a directory."]
    if project["requestedPackage"] and project["kind"] != "package-repository":
        return ["Package selection is only used inside a package repository."]
    if project["requestedPackage"] and project["packageSelectionValid"] is False:
        names = ", ".join(project["packageNames"]) or "none"
        requested = project["requestedPackage"]
        return [
            f"Requested package {requested!r} is not registered; "
            f"choose one of: {names}."
        ]
    if project["needsPackageSelection"]:
        return [
            "Multiple packages are registered; select one package before "
            "running package commands."
        ]
    if project["kind"] == "flutter-package":
        return [
            "This looks like an upstream Flutter package. Create a FlutterOH "
            "package repository before adding OHOS implementation changes."
        ]
    if project["kind"] == "dart-package":
        return [
            "A pubspec.yaml was found, but this does not look like a Flutter "
            "app or Flutter package."
        ]
    if project["kind"] == "unknown":
        return ["No Flutter app, Flutter package, or package-repository fluoh.yaml was found at this path."]
    return []


def main() -> int:
    parser = argparse.ArgumentParser(description="Read-only fluoh skill preflight.")
    parser.add_argument("path", nargs="?", default=".", help="Project directory")
    parser.add_argument(
        "--fluoh-command",
        default=os.environ.get("FLUOH_COMMAND", "fluoh"),
        help="fluoh executable name or path",
    )
    parser.add_argument(
        "--package",
        default="",
        help="Package name to select in a multi-package repository.",
    )
    args = parser.parse_args()
    root = Path(args.path).expanduser().resolve()
    command_cwd = root if root.is_dir() else Path.cwd()
    requested_package = args.package.strip() or None
    fluoh_command = shlex.split(args.fluoh_command)
    if not fluoh_command:
        fluoh_command = ["fluoh"]
    info: dict[str, Any] = {
        "schemaVersion": 1,
        "cwd": str(root),
        "pathExists": root.exists(),
        "pathIsDirectory": root.is_dir(),
        "fluoh": run([*fluoh_command, "--version"], command_cwd),
        "project": project_info(root, requested_package=requested_package),
        "git": git_state(root),
    }
    info["suggestedCommands"] = suggested_commands(info)
    info["finalCheckCommands"] = final_check_commands(info)
    info["deliveryChecks"] = delivery_checks(info)
    info["reportCommand"] = report_command(info["project"])
    info["reportCheckCommand"] = report_check_command()
    info["sessionInspectCommand"] = session_inspect_command()
    info["scenarioCommand"] = scenario_command(info["project"])
    info["notes"] = notes(info["project"])
    print(json.dumps(info, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
