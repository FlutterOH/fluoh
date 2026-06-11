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
import shutil
import shlex
import subprocess
import sys
from pathlib import Path
from typing import Any


PACKAGE_IMPLEMENTATION_GUIDE_TEMPLATE_VERSION = 2
PACKAGE_AGENTS_INSTRUCTIONS_TEMPLATE_VERSION = 1
PACKAGE_README_ADAPTATION_TEMPLATE_VERSION = 1
PACKAGE_DOC_TEMPLATE_VERSION = max(
    PACKAGE_IMPLEMENTATION_GUIDE_TEMPLATE_VERSION,
    PACKAGE_AGENTS_INSTRUCTIONS_TEMPLATE_VERSION,
    PACKAGE_README_ADAPTATION_TEMPLATE_VERSION,
)
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


def fluoh_command_args(value: str) -> list[str]:
    command = shlex.split(value)
    if not command:
        return ["fluoh"]
    executable = Path(command[0]).expanduser()
    if executable.suffix == ".dart":
        return [dart_executable(), str(executable), *command[1:]]
    if Path(command[0]).name in ("dart", "dart.exe") and len(command) > 1:
        dart_entry = Path(command[1]).expanduser()
        if dart_entry.suffix == ".dart":
            return [dart_executable(), str(dart_entry), *command[2:]]
    return command


def dart_executable() -> str:
    override = os.environ.get("FLUOH_DART_BIN", "").strip()
    if override:
        return str(Path(override).expanduser())
    dart = shutil.which("dart")
    if dart:
        dart_path = Path(dart)
        dart_name = "dart.exe" if os.name == "nt" else "dart"
        flutter_cached_dart = dart_path.parent / "cache" / "dart-sdk" / "bin" / dart_name
        if flutter_cached_dart.exists():
            return str(flutter_cached_dart)
        return str(dart_path)
    return "dart"


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""


def slug(value: str, fallback: str) -> str:
    raw = value.strip()
    if is_placeholder(raw):
        return fallback
    normalized = re.sub(r"[^A-Za-z0-9._-]+", "-", raw)
    normalized = normalized.strip("-._")
    return normalized or fallback


def is_placeholder(value: str) -> bool:
    return value.startswith("<") and value.endswith(">")


def command_arg(value: str) -> str:
    return value if is_placeholder(value) else shlex.quote(value)


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


def generated_section_state(
    content: str, section_id: str, current_version: int
) -> dict[str, Any]:
    template_match = re.search(
        rf"<!--\s*fluoh:generated:start\s+id={re.escape(section_id)}\s+template=(\d+)\s*-->",
        content,
    )
    if template_match:
        template_version = int(template_match.group(1))
        if template_version < current_version:
            status = "stale"
        elif template_version > current_version:
            status = "newer"
        else:
            status = "current"
        return {
            "sectionId": section_id,
            "status": status,
            "version": template_version,
            "currentVersion": current_version,
        }
    return {
        "sectionId": section_id,
        "status": "missing",
        "version": None,
        "currentVersion": current_version,
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


def host_supports_regression_platform(platform: str) -> bool:
    if platform in {"android", "web"}:
        return True
    if platform in {"ios", "macos"}:
        return sys.platform == "darwin"
    if platform == "linux":
        return sys.platform.startswith("linux")
    if platform == "windows":
        return sys.platform.startswith("win")
    return False


REGRESSION_PLATFORM_ORDER = ("android", "ios", "macos", "linux", "web", "windows")
AUTO_EMULATOR_REGRESSION_PLATFORMS = {"android", "ios"}
BUILD_REGRESSION_PLATFORMS = {"linux", "windows"}
OHOS_PLATFORM = "ohos"


def doctor_command(platform: str, project: bool = False, strict: bool = False) -> str:
    parts = [
        f"fluoh doctor --platform {platform}",
    ]
    if project:
        parts.append("--project")
    parts.append("--json")
    if strict:
        parts.append("--strict")
    return " ".join(parts)


def devices_command(platform: str) -> str:
    return f"fluoh devices --platform {platform} --json"


def emulators_command(platform: str) -> str:
    return f"fluoh emulators --platform {platform} --json"


def build_command(
    platform: str,
    trace_dir: str,
    package_name: str | None = None,
    auto_sign: bool = False,
) -> str:
    package_part = f" --package {package_name}" if package_name else ""
    auto_sign_part = " --auto-sign" if auto_sign else ""
    return (
        f"fluoh build {platform}{package_part}{auto_sign_part} "
        f"--json --trace-dir {trace_dir}"
    )


def run_command(
    platform: str,
    trace_dir: str,
    package_name: str | None = None,
    auto_emulator: bool = False,
) -> str:
    package_part = f" --package {package_name}" if package_name else ""
    auto_emulator_part = " --auto-emulator" if auto_emulator else ""
    return (
        f"fluoh run {platform}{package_part}{auto_emulator_part} "
        f"--json --trace-dir {trace_dir}"
    )


def ohos_adaptation_commands(
    trace_dir: str,
    package_name: str | None = None,
) -> list[str]:
    return [
        doctor_command(OHOS_PLATFORM, project=True, strict=True),
        build_command(
            OHOS_PLATFORM,
            trace_dir,
            package_name,
            auto_sign=True,
        ),
        devices_command(OHOS_PLATFORM),
        emulators_command(OHOS_PLATFORM),
        run_command(
            OHOS_PLATFORM,
            trace_dir,
            package_name,
            auto_emulator=True,
        ),
    ]


def regression_run_command(
    platform: str,
    trace_dir: str,
    package_name: str | None = None,
) -> str:
    if platform in BUILD_REGRESSION_PLATFORMS:
        return build_command(platform, trace_dir, package_name)
    return run_command(
        platform,
        trace_dir,
        package_name,
        auto_emulator=platform in AUTO_EMULATOR_REGRESSION_PLATFORMS,
    )


def regression_commands_for_platform(
    platform: str,
    trace_dir: str,
    package_name: str | None = None,
) -> list[str]:
    return [
        doctor_command(platform, strict=True),
        regression_run_command(platform, trace_dir, package_name),
    ]


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
                "linux": (example_root / "linux").is_dir(),
                "web": (example_root / "web").is_dir(),
                "windows": (example_root / "windows").is_dir(),
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
            "linux": (root / "linux").is_dir(),
            "web": (root / "web").is_dir(),
            "windows": (root / "windows").is_dir(),
        },
    }


def upgrade_checks(
    root: Path,
    project: dict[str, Any],
    git: dict[str, Any],
    fluoh_command: list[str],
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
            "templateVersions": {
                "README.md": PACKAGE_README_ADAPTATION_TEMPLATE_VERSION,
                "FLUOH.md": PACKAGE_IMPLEMENTATION_GUIDE_TEMPLATE_VERSION,
                "AGENTS.md": PACKAGE_AGENTS_INSTRUCTIONS_TEMPLATE_VERSION,
            },
            "refreshCommand": "fluoh package docs refresh",
            "allowDirtyRefreshCommand": "fluoh package docs refresh --allow-dirty",
            "dryRunCommand": "fluoh package docs refresh --dry-run",
            "sections": [
                {
                    "file": "README.md",
                    **generated_section_state(
                        readme_content,
                        PACKAGE_README_ADAPTATION_SECTION,
                        PACKAGE_README_ADAPTATION_TEMPLATE_VERSION,
                    ),
                },
                {
                    "file": "FLUOH.md",
                    **generated_section_state(
                        guide_content,
                        PACKAGE_IMPLEMENTATION_GUIDE_SECTION,
                        PACKAGE_IMPLEMENTATION_GUIDE_TEMPLATE_VERSION,
                    ),
                },
                {
                    "file": "AGENTS.md",
                    **generated_section_state(
                        agents_content,
                        PACKAGE_AGENTS_INSTRUCTIONS_SECTION,
                        PACKAGE_AGENTS_INSTRUCTIONS_TEMPLATE_VERSION,
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
            dirty = git.get("dirty") is True
            refresh_command = (
                docs["allowDirtyRefreshCommand"] if dirty else docs["refreshCommand"]
            )
            checks["commands"].extend(
                ["fluoh package docs refresh --dry-run", refresh_command]
            )
            checks["notes"].append(
                "Generated package docs are missing or stale; refresh them before implementation edits."
            )
            if dirty:
                checks["notes"].append(
                    "The worktree is dirty, so use the explicit --allow-dirty docs refresh mode or create a clean checkpoint first."
                )
        if docs["needsRefreshUnknown"]:
            checks["commands"].append("fluoh package docs refresh --dry-run")
            checks["notes"].append(
                "Package docs dry-run did not complete; run it successfully before assuming generated docs are current."
            )
    return checks


def app_platform_regression_commands(
    project: dict[str, Any], trace_dir: str
) -> list[str]:
    platforms = project.get("platformDirectories", {})
    commands: list[str] = []
    for platform in REGRESSION_PLATFORM_ORDER:
        if platforms.get(platform) and host_supports_regression_platform(platform):
            commands.extend(regression_commands_for_platform(platform, trace_dir))
    return commands


def selected_package_entry(project: dict[str, Any]) -> dict[str, Any]:
    selected = project.get("selectedPackage")
    for package in project.get("packages", []):
        if package.get("name") == selected:
            return package
    return {}


def package_platform_regression_commands(
    project: dict[str, Any], package_name: str, trace_dir: str
) -> list[str]:
    package = selected_package_entry(project)
    platforms = package.get("examplePlatforms", {})
    commands: list[str] = []
    for platform in REGRESSION_PLATFORM_ORDER:
        if platforms.get(platform) and host_supports_regression_platform(platform):
            commands.extend(
                regression_commands_for_platform(
                    platform,
                    trace_dir,
                    package_name,
                )
            )
    return commands


def suggested_commands(info: dict[str, Any]) -> list[str]:
    project = info["project"]
    kind = project["kind"]
    upgrade = info.get("upgradeChecks", {})
    upgrade_commands = upgrade.get("commands", [])
    if kind == "app-project":
        sdk = project["sdkVersion"] or "<sdk-version-or-line>"
        trace_dir = f".fluoh/traces/{slug(project['name'] or 'app', 'app')}/adaptation"
        return [
            *upgrade_commands,
            "fluoh source update",
            f"fluoh sdk use {sdk} --pub-get",
            "fluoh deps check --json",
            "fluoh deps fix --dry-run",
            "fluoh deps fix",
            "fluoh deps get",
            *ohos_adaptation_commands(trace_dir),
            f"fluoh drive all --json --trace-dir {trace_dir}",
            *app_platform_regression_commands(project, trace_dir),
            f"fluoh report create --scope {command_arg(project['name'] or 'app')} --trace-dir {trace_dir} --json",
        ]
    if kind == "package-repository":
        package = project["selectedPackage"] or "<name>"
        trace_dir = f".fluoh/traces/{command_arg(package)}/adaptation"
        return [
            *upgrade_commands,
            "fluoh deps get",
            f"fluoh verify --package {package} --json --trace-dir {trace_dir}",
            *ohos_adaptation_commands(trace_dir, package),
            f"fluoh drive all --package {package} --json --trace-dir {trace_dir}",
            *package_platform_regression_commands(project, package, trace_dir),
            f"fluoh package status --package {package}",
            f"fluoh package handoff --package {package} --json",
            f"fluoh report create --scope {command_arg(package)} --package {command_arg(package)} --trace-dir {trace_dir} --json",
            f"fluoh package check --package {package} --json",
        ]
    if kind == "flutter-package":
        package = project["name"] or "<package-name>"
        output = flutter_package_output(project)
        upstream = shlex.quote(info["cwd"])
        trace_dir = f".fluoh/traces/{command_arg(package)}/adaptation"
        return [
            "Resolve package setup: "
            f"repository-name={package}, output={output}, repository=<flutteroh-repo-url-or-path>, "
            "git-author-name=<name>, git-author-email=<email>, sdk=<sdk-version-or-line>",
            f"fluoh package create {upstream} --repository-name {package} --output {output} "
            "--repository <flutteroh-repo-url-or-path> "
            "--git-author-name <name> --git-author-email <email> "
            "--sdk <sdk-version-or-line> --package-path .",
            f"cd {output}",
            f"fluoh verify --package {package} --json --trace-dir {trace_dir}",
            *ohos_adaptation_commands(trace_dir, package),
            f"fluoh drive all --package {package} --json --trace-dir {trace_dir}",
            *package_platform_regression_commands(project, package, trace_dir),
            f"fluoh package status --package {package}",
            f"fluoh package handoff --package {package} --json",
            f"fluoh report create --scope {command_arg(package)} --package {command_arg(package)} --trace-dir {trace_dir} --json",
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
        trace_dir = f".fluoh/traces/{slug(project['name'] or 'app', 'app')}/adaptation"
        return [
            "git diff --check",
            *ohos_adaptation_commands(trace_dir),
            *app_platform_regression_commands(project, trace_dir),
        ]
    if kind == "package-repository":
        package = project["selectedPackage"] or "<name>"
        trace_dir = f".fluoh/traces/{command_arg(package)}/adaptation"
        return [
            "git diff --check",
            f"fluoh verify --package {package} --json --trace-dir {trace_dir}",
            *ohos_adaptation_commands(trace_dir, package),
            *package_platform_regression_commands(project, package, trace_dir),
            f"fluoh package status --package {package}",
            f"fluoh package handoff --package {package} --json",
            f"fluoh package check --package {package} --json",
        ]
    if kind == "flutter-package":
        return []
    return []


def adapt_plan_command(project: dict[str, Any]) -> str | None:
    if project["kind"] == "app-project":
        sdk = project["sdkVersion"]
        if sdk:
            return f"fluoh plan app --sdk {command_arg(sdk)} --json"
        return "fluoh plan app --json"
    if project["kind"] == "package-repository":
        package = project["selectedPackage"] or "<name>"
        return f"fluoh plan package --package {command_arg(package)} --json"
    return None


def command_queue(info: dict[str, Any]) -> list[dict[str, Any]]:
    project = info["project"]
    queue: list[dict[str, Any]] = []
    for command in suggested_commands(info):
        queue.append(command_queue_item(command, project))
    return queue


def command_queue_item(command: str, project: dict[str, Any]) -> dict[str, Any]:
    phase = command_phase(command)
    mutating = command_mutates(command)
    item: dict[str, Any] = {
        "phase": phase,
        "command": command,
        "mutating": mutating,
        "requiresApproval": mutating,
        "expectedEvidence": command_expected_evidence(command),
    }
    if command.startswith("Resolve package setup:"):
        item["mutating"] = False
        item["requiresApproval"] = False
        item["kind"] = "setup-inputs"
    if project["kind"] in {"app-project", "package-repository", "flutter-package"}:
        item["adaptationKind"] = (
            "package" if project["kind"] != "app-project" else "app"
        )
    return item


def command_phase(command: str) -> str:
    if command.startswith("Resolve package setup") or " package create " in command:
        return "setup"
    if command.startswith("cd "):
        return "setup"
    if " source update" in command:
        return "setup"
    if " deps " in command:
        return "deps"
    if " doctor " in command:
        return "doctor"
    if " verify" in command:
        return "verify"
    if " devices " in command or " emulators " in command:
        return "target-discovery"
    if " build " in command or " run " in command:
        return "platform"
    if " drive " in command:
        return "automation"
    if " report create " in command:
        return "report"
    if " package handoff " in command:
        return "handoff"
    if " package status " in command or " package check " in command:
        return "release-check"
    return "other"


def command_mutates(command: str) -> bool:
    readonly_tokens = (
        "--dry-run",
        "--plan",
        " deps check ",
        " doctor ",
        " devices ",
        " emulators ",
        " package status ",
        " package handoff ",
        " package check ",
        " package discover ",
        " package queue ",
    )
    if command.startswith("Resolve package setup") or command.startswith("cd "):
        return False
    if any(token in command for token in readonly_tokens):
        return False
    return any(
        token in command
        for token in (
            " sdk use ",
            " source update",
            " deps fix",
            " deps get",
            " build ",
            " run ",
            " drive ",
            " package create ",
            " package docs refresh",
            " report create ",
        )
    )


def command_expected_evidence(command: str) -> str:
    if " source update" in command:
        return "source update result"
    if " deps check " in command:
        return "dependency support JSON"
    if " deps fix --dry-run" in command:
        return "dependency rewrite plan"
    if " doctor " in command:
        return "toolchain diagnostic JSON"
    if " devices " in command:
        return "connected target inventory JSON"
    if " emulators " in command:
        return "local emulator inventory JSON"
    if " verify" in command:
        return "pub get, analyze, and test JSON"
    if " build " in command:
        return "build artifact and command JSON"
    if " run " in command:
        return "launch, runtime log, target, and diagnostic JSON"
    if " drive " in command:
        return "automation coverage policy, scenario rows, and repair queue"
    if " report create " in command:
        return "local AI report path"
    if " package handoff " in command:
        return "branch state, reports, traces, and next commands"
    if " package check " in command:
        return "release gate JSON"
    return "command result"


def delivery_checks(info: dict[str, Any]) -> list[str]:
    project = info["project"]
    kind = project["kind"]
    if kind == "app-project":
        scope = slug(project["name"] or "app", "app")
        return [
            "Confirm preflight upgradeChecks has no migration blocker before editing.",
            f"Create or update .fluoh/reports/{scope}/ai-report-...md before the final response.",
            "Record deps, doctor, build, and run command results with exit codes.",
            "Use --auto-emulator for OHOS run so a local emulator is tried before connected devices; record signed build-only evidence only when no local target can be started.",
            "Run Android checks with --auto-emulator and Web browser smoke runs when those platform directories exist; run iOS, macOS, Linux, and Windows checks only on matching hosts, and record exact skip reasons for unavailable hosts.",
            "Review the diff and remove unrelated local paths, generated caches, credentials, and private tokens.",
            "State ready, blocked, or needs maintainer decision in the final response.",
        ]
    if kind == "package-repository":
        package = slug(project["selectedPackage"] or "<name>", "<name>")
        return [
            "Confirm preflight upgradeChecks has no schema migration blocker and generated docs are current or refreshed before editing.",
            f"Create or update .fluoh/reports/{package}/ai-report-...md before the final response.",
            f"Record verify, status, and package check results for {package} with exit codes.",
            f"Record OHOS build/run evidence for {package}; use --auto-emulator so a local emulator is tried before connected devices, and explain only the remaining device/build blocker.",
            "Record Android regression checks with --auto-emulator and Web browser smoke runs when examples exist, plus iOS, macOS, Linux, and Windows checks only on matching hosts; record exact skip reasons for unavailable hosts.",
            "Review public API compatibility, dependency constraints, and non-OHOS regression risk.",
            "Review the diff and remove unrelated local paths, generated caches, credentials, and private tokens.",
            "State ready, blocked, or needs maintainer decision in the final response.",
        ]
    if kind == "flutter-package":
        package = slug(project["name"] or "<package-name>", "<package-name>")
        output = flutter_package_output(project)
        return [
            "Create a FlutterOH package repository before editing OHOS implementation files.",
            f"Rerun preflight in {output} before using final check commands.",
            f"Create or update .fluoh/reports/{package}/ai-report-...md in the generated repository before the final response.",
            f"Record verify, status, and package check results for {package} with exit codes.",
            f"Record OHOS build/run evidence for {package}; use --auto-emulator so a local emulator is tried before connected devices, and explain only the remaining device/build blocker.",
            "Record Android regression checks with --auto-emulator and Web browser smoke runs when examples exist after repository creation, plus iOS, macOS, Linux, and Windows checks only on matching hosts; record exact skip reasons for unavailable hosts.",
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
            f"--scope {command_arg(scope)} --package {command_arg(package)}"
        )
    if project["kind"] == "flutter-package":
        package = project["name"] or "<package-name>"
        output = flutter_package_output(project)
        return (
            f"python3 <skill-dir>/scripts/new_report.py {command_arg(output)} "
            f"--scope {command_arg(package)} --package {command_arg(package)}"
        )
    scope = project["name"] or "app"
    return (
        "python3 <skill-dir>/scripts/new_report.py . "
        f"--scope {command_arg(scope)}"
    )


def summary_command(project: dict[str, Any]) -> str:
    if project["kind"] == "package-repository":
        scope = project["selectedPackage"] or "monorepo"
        package = project["selectedPackage"] or "<name>"
        return (
            "python3 <skill-dir>/scripts/new_summary.py . "
            f"--scope {command_arg(scope)} --package {command_arg(package)}"
        )
    if project["kind"] == "flutter-package":
        package = project["name"] or "<package-name>"
        output = flutter_package_output(project)
        return (
            f"python3 <skill-dir>/scripts/new_summary.py {command_arg(output)} "
            f"--scope {command_arg(package)} --package {command_arg(package)}"
        )
    scope = project["name"] or "app"
    return (
        "python3 <skill-dir>/scripts/new_summary.py . "
        f"--scope {command_arg(scope)}"
    )


def report_check_command() -> str:
    return "python3 <skill-dir>/scripts/check_report.py <report-path>"


def feedback_command() -> str:
    return "python3 <skill-dir>/scripts/collect_feedback.py <trace-dir-or-manifest>"


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
            f"--scope {command_arg(package)} --package {command_arg(package)} "
            "--platform <platform> --name <scenario-name>"
        )
    if project["kind"] == "flutter-package":
        package = project["name"] or "<package-name>"
        output = flutter_package_output(project)
        return (
            f"python3 <skill-dir>/scripts/new_scenario.py {command_arg(output)} "
            f"--scope {command_arg(package)} --package {command_arg(package)} "
            "--platform <platform> --name <scenario-name>"
        )
    scope = project["name"] or "app"
    return (
        "python3 <skill-dir>/scripts/new_scenario.py . "
        f"--scope {command_arg(scope)} --app --platform <platform> "
        "--name <scenario-name>"
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
        default=os.environ.get(
            "FLUOH_BIN",
            os.environ.get("FLUOH_COMMAND", "fluoh"),
        ),
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
    fluoh_command = fluoh_command_args(args.fluoh_command)
    info: dict[str, Any] = {
        "schema": 1,
        "cwd": str(root),
        "pathExists": root.exists(),
        "pathIsDirectory": root.is_dir(),
        "fluoh": run([*fluoh_command, "--version"], command_cwd),
        "project": project_info(root, requested_package=requested_package),
        "git": git_state(root),
    }
    info["upgradeChecks"] = upgrade_checks(
        root, info["project"], info["git"], fluoh_command
    )
    info["adaptPlanCommand"] = adapt_plan_command(info["project"])
    info["suggestedCommands"] = suggested_commands(info)
    info["commandQueue"] = command_queue(info)
    info["finalCheckCommands"] = final_check_commands(info)
    info["deliveryChecks"] = delivery_checks(info)
    info["reportCommand"] = report_command(info["project"])
    info["summaryCommand"] = summary_command(info["project"])
    info["reportCheckCommand"] = report_check_command()
    info["feedbackCommand"] = feedback_command()
    info["sessionInspectCommand"] = session_inspect_command()
    info["scenarioCommand"] = scenario_command(info["project"])
    info["notes"] = notes(info["project"])
    print(json.dumps(info, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
