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


PACKAGE_DOC_TEMPLATE_VERSION = 1
PACKAGE_IMPLEMENTATION_GUIDE_SECTION = "package-implementation-guide"
PACKAGE_AGENTS_INSTRUCTIONS_SECTION = "package-agents-instructions"
PACKAGE_README_ADAPTATION_SECTION = "package-readme-adaptation"


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


def generated_section_state(content: str, section_id: str) -> dict[str, Any]:
    template_match = re.search(
        rf"<!--\s*fluoh:generated:start\s+id={re.escape(section_id)}\s+template=(\d+)\s*-->",
        content,
    )
    if template_match:
        template_version = int(template_match.group(1))
        if template_version < PACKAGE_DOC_TEMPLATE_VERSION:
            status = "stale"
        elif template_version > PACKAGE_DOC_TEMPLATE_VERSION:
            status = "newer"
        else:
            status = "current"
        return {
            "sectionId": section_id,
            "status": status,
            "version": template_version,
            "currentVersion": PACKAGE_DOC_TEMPLATE_VERSION,
        }
    return {
        "sectionId": section_id,
        "status": "missing",
        "version": None,
        "currentVersion": PACKAGE_DOC_TEMPLATE_VERSION,
    }


def schema_state(fluoh_yaml: Path, content: str) -> dict[str, Any]:
    if not fluoh_yaml.exists():
        return {"status": "missing-file", "version": None, "currentVersion": 1}
    value = top_level_scalar(content, "schema")
    if value is None:
        return {"status": "missing", "version": None, "currentVersion": 1}
    try:
        version = int(value)
    except ValueError:
        return {"status": "invalid", "version": value, "currentVersion": 1}
    if version < 1:
        return {"status": "unsupported-old", "version": version, "currentVersion": 1}
    if version > 1:
        return {"status": "requires-newer-fluoh", "version": version, "currentVersion": 1}
    return {"status": "current", "version": version, "currentVersion": 1}


def package_docs_dry_run_state(root: Path, fluoh_command: list[str]) -> dict[str, Any]:
    result = run(
        [*fluoh_command, "package", "docs", "refresh", "--dry-run"],
        root,
        timeout=30,
    )
    state: dict[str, Any] = {
        "ok": result["ok"],
        "exitCode": result["exitCode"],
        "needsRefresh": None,
        "files": [],
    }
    stdout = result["stdout"]
    if result["ok"]:
        if "Package docs would be refreshed" in stdout:
            state["needsRefresh"] = True
            state["files"] = [
                line.split("-", 1)[1].strip()
                for line in stdout.splitlines()
                if line.strip().startswith("-")
            ]
        elif "Package docs are current" in stdout:
            state["needsRefresh"] = False
    else:
        state["stderr"] = result["stderr"]
    return state


def append_command(checks: dict[str, Any], command: str) -> None:
    if command not in checks["commands"]:
        checks["commands"].append(command)


def package_entries(content: str, root: Path) -> list[dict[str, Any]]:
    if top_level_key(content, "package"):
        package: dict[str, Any] = {"name": None, "path": None}
        in_package = False
        for line in content.splitlines():
            if re.match(r"^package\s*:\s*$", line):
                in_package = True
                continue
            if in_package and line and not line.startswith((" ", "\t", "#")):
                break
            if not in_package:
                continue
            name_match = re.match(r"^  name\s*:\s*(.+?)\s*$", line)
            if name_match:
                package["name"] = clean_scalar(name_match.group(1))
                continue
            path_match = re.match(r"^  path\s*:\s*(.+?)\s*$", line)
            if path_match:
                package["path"] = clean_scalar(path_match.group(1))
        if package["name"]:
            path = package["path"]
            package_root = root / path if path else root
            example_root = package_root / "example"
            package["examplePlatforms"] = {
                "ohos": (example_root / "ohos").is_dir(),
                "android": (example_root / "android").is_dir(),
                "ios": (example_root / "ios").is_dir(),
                "macos": (example_root / "macos").is_dir(),
            }
            return [package]
        return []

    return []


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
    package_adaptation = (
        top_level_scalar(content, "kind") == "package"
        or top_level_key(content, "package")
    )
    has_example = (root / "example" / "pubspec.yaml").is_file()
    has_app_entry = (root / "lib" / "main.dart").is_file()
    has_flutter = is_flutter_pubspec(pubspec_content)
    has_flutter_plugin = is_flutter_plugin_pubspec(pubspec_content)
    if package_adaptation:
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
        "hasPackageBranch": package_adaptation,
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
        "sdkVersion": sdk_version(content),
        "platformDirectories": {
            "ohos": (root / "ohos").is_dir(),
            "android": (root / "android").is_dir(),
            "ios": (root / "ios").is_dir(),
            "macos": (root / "macos").is_dir(),
        },
    }


def upgrade_checks(
    root: Path, project: dict[str, Any], fluoh_command: list[str]
) -> dict[str, Any]:
    fluoh_yaml = root / "fluoh.yaml"
    content = read_text(fluoh_yaml) if fluoh_yaml.exists() else ""
    schema = schema_state(fluoh_yaml, content)
    checks: dict[str, Any] = {
        "schema": schema,
        "needsMigration": schema["status"]
        not in {"current", "missing-file"}
        and project["kind"] in {"app-project", "package-repository"},
        "commands": [],
        "notes": [],
    }
    if schema["status"] == "requires-newer-fluoh":
        append_command(checks, "fluoh upgrade")
        checks["notes"].append(
            "fluoh.yaml declares an unsupported schema; upgrade fluoh before editing."
        )
    elif checks["needsMigration"]:
        checks["notes"].append(
            "fluoh.yaml is not in the current canonical schema; stop before editing and migrate or regenerate metadata."
        )

    if project["kind"] == "package-repository":
        readme_content = read_text(root / "README.md")
        guide_content = read_text(root / "FLUOH.md")
        agents_content = read_text(root / "AGENTS.md")
        docs = {
            "templateVersion": PACKAGE_DOC_TEMPLATE_VERSION,
            "refreshCommand": "fluoh package docs refresh",
            "dryRunCommand": "fluoh package docs refresh --dry-run",
            "sections": [
                {
                    "file": "README.md",
                    **generated_section_state(
                        readme_content, PACKAGE_README_ADAPTATION_SECTION
                    ),
                },
                {
                    "file": "FLUOH.md",
                    **generated_section_state(
                        guide_content, PACKAGE_IMPLEMENTATION_GUIDE_SECTION
                    ),
                },
                {
                    "file": "AGENTS.md",
                    **generated_section_state(
                        agents_content, PACKAGE_AGENTS_INSTRUCTIONS_SECTION
                    ),
                },
            ],
        }
        refresh_statuses = {"missing", "stale"}
        marker_needs_refresh = any(
            section["status"] in refresh_statuses for section in docs["sections"]
        )
        docs["hasNewerTemplate"] = any(
            section["status"] == "newer" for section in docs["sections"]
        )
        docs["dryRun"] = package_docs_dry_run_state(root, fluoh_command)
        docs["needsRefresh"] = not docs["hasNewerTemplate"] and (
            marker_needs_refresh or docs["dryRun"].get("needsRefresh") is True
        )
        docs["needsRefreshUnknown"] = (
            not docs["hasNewerTemplate"]
            and not marker_needs_refresh
            and docs["dryRun"].get("ok") is False
        )
        checks["packageDocs"] = docs
        if docs["hasNewerTemplate"]:
            append_command(checks, "fluoh upgrade")
            checks["notes"].append(
                "Generated package docs were created by a newer template; upgrade fluoh before refreshing."
            )
        elif docs["needsRefresh"]:
            checks["commands"].extend(
                ["fluoh package docs refresh --dry-run", "fluoh package docs refresh"]
            )
            checks["notes"].append(
                "Generated package docs are missing or stale; refresh them before implementation edits."
            )
        if docs["needsRefreshUnknown"]:
            checks["commands"].append("fluoh package docs refresh --dry-run")
            checks["notes"].append(
                "Package docs dry-run did not complete; run it successfully before assuming generated docs are current."
            )
    return checks


def suggested_commands(info: dict[str, Any]) -> list[str]:
    project = info["project"]
    kind = project["kind"]
    upgrade = info.get("upgradeChecks", {})
    upgrade_commands = upgrade.get("commands", [])
    if kind == "app-project":
        sdk = project["sdkVersion"] or "<sdk-version-or-line>"
        return [
            *upgrade_commands,
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
            *upgrade_commands,
            "fluoh deps get",
            "fluoh doctor -p --json --strict",
            f"fluoh verify --package {package} --json",
            f"fluoh run --platform ohos --package {package} --json",
            f"fluoh build --platform ohos --package {package} --auto-sign --json",
            f"fluoh package status --package {package}",
            f"fluoh package check --package {package} --json",
        ]
    if kind == "flutter-package":
        package = project["name"] or "<package-name>"
        output = flutter_package_output(project)
        upstream = shlex.quote(info["cwd"])
        return [
            "Resolve package setup: "
            f"repository-name={package}, output={output}, repository=<flutteroh-repo-url-or-path>, "
            "git-author-name=<name>, git-author-email=<email>, sdk=<sdk-version-or-line>",
            f"fluoh package create {upstream} --repository-name {package} --output {output} "
            "--repository <flutteroh-repo-url-or-path> "
            "--git-author-name <name> --git-author-email <email> "
            "--sdk <sdk-version-or-line> --package-path .",
            f"cd {output}",
            f"fluoh verify --package {package} --json",
            f"fluoh run --platform ohos --package {package} --json",
            f"fluoh build --platform ohos --package {package} --auto-sign --json",
            f"fluoh package status --package {package}",
            f"fluoh package check --package {package} --json",
        ]
    if kind == "dart-package":
        return [
            "This is a Dart package, not a Flutter app or FlutterOH package repository; ask for a Flutter project/package path before editing.",
        ]
    return [
        "Run this from a Flutter project, a FlutterOH package repository, or create one with fluoh package create <upstream> --repository-name <repository-name>.",
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
            f"fluoh package check --package {package} --json",
        ]
    if kind == "flutter-package":
        return []
    return []


def delivery_checks(info: dict[str, Any]) -> list[str]:
    project = info["project"]
    kind = project["kind"]
    if kind == "app-project":
        return [
            "Confirm preflight upgradeChecks has no migration blocker before editing.",
            "Create or update .fluoh/ai-report-...md before the final response.",
            "Record deps, doctor, build, and run command results with exit codes.",
            "If no OHOS target is available, record the signed build as build-only evidence and explain the missing target.",
            "Review the diff and remove unrelated local paths, generated caches, credentials, and private tokens.",
            "State ready, blocked, or needs maintainer decision in the final response.",
        ]
    if kind == "package-repository":
        package = project["selectedPackage"] or "<name>"
        return [
            "Confirm preflight upgradeChecks has no schema migration blocker and generated docs are current or refreshed before editing.",
            f"Create or update .fluoh/ai-report-{package}-...md before the final response.",
            f"Record verify, status, and package check results for {package} with exit codes.",
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
            f"Record verify, status, and package check results for {package} with exit codes.",
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
            f"Requested package {requested!r} does not match the current "
            f"package branch; current package: {names}."
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
        help="Package name to validate against the current package branch.",
    )
    args = parser.parse_args()
    root = Path(args.path).expanduser().resolve()
    command_cwd = root if root.is_dir() else Path.cwd()
    requested_package = args.package.strip() or None
    fluoh_command = shlex.split(args.fluoh_command)
    if not fluoh_command:
        fluoh_command = ["fluoh"]
    info: dict[str, Any] = {
        "schema": 1,
        "cwd": str(root),
        "pathExists": root.exists(),
        "pathIsDirectory": root.is_dir(),
        "fluoh": run([*fluoh_command, "--version"], command_cwd),
        "project": project_info(root, requested_package=requested_package),
        "git": git_state(root),
    }
    info["upgradeChecks"] = upgrade_checks(root, info["project"], fluoh_command)
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
