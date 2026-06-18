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

from preflight_guidance import (
    support_plan_command,
    automation_runbook,
    command_arg,
    command_queue,
    delivery_gate,
    delivery_checks,
    feedback_command,
    flutter_package_output,
    report_check_command,
    report_command,
    scenario_command,
    session_attach_command,
    session_inspect_command,
    slug,
    summary_command,
)


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


def run_fluoh_plan(
    fluoh_command: list[str],
    plan_command: str | None,
    cwd: Path,
) -> dict[str, Any] | None:
    if not plan_command:
        return None
    args = shlex.split(plan_command)
    if args and args[0] == "fluoh":
        args = args[1:]
    if not args:
        return None
    result = run([*fluoh_command, *args], cwd, timeout=30)
    payload: dict[str, Any] | None = None
    if result.get("stdout"):
        try:
            decoded = json.loads(str(result["stdout"]))
            if isinstance(decoded, dict):
                payload = decoded
        except json.JSONDecodeError:
            payload = None
    plan = payload.get("plan") if payload else None
    return {
        "ok": result.get("ok") is True and isinstance(plan, dict),
        "command": plan_command,
        "exitCode": result.get("exitCode"),
        "stdout": result.get("stdout"),
        "stderr": result.get("stderr"),
        "plan": plan if isinstance(plan, dict) else None,
    }


def commands_from_plan_queue(plan: dict[str, Any]) -> list[str]:
    queue = plan.get("queue")
    if not isinstance(queue, list):
        return []
    commands: list[str] = []
    for item in queue:
        if isinstance(item, dict) and isinstance(item.get("command"), str):
            commands.append(item["command"])
    return commands


def display_command(command: list[str]) -> str:
    return " ".join(shlex.quote(part) for part in command)


def rewrite_fluoh_command(command: str, fluoh_display: str) -> str:
    if fluoh_display == "fluoh":
        return command
    return re.sub(r"^fluoh(?=\s|$)", fluoh_display, command)


def rewrite_fluoh_commands(value: Any, fluoh_display: str) -> Any:
    if isinstance(value, str):
        return rewrite_fluoh_command(value, fluoh_display)
    if isinstance(value, list):
        return [rewrite_fluoh_commands(item, fluoh_display) for item in value]
    if isinstance(value, dict):
        return {
            key: rewrite_fluoh_commands(item, fluoh_display)
            for key, item in value.items()
        }
    return value


def executable_delivery_gate(value: Any, fluoh_display: str) -> Any:
    if not isinstance(value, dict):
        return value
    rewritten = dict(value)
    if "finalCheckCommands" in rewritten:
        rewritten["finalCheckCommands"] = rewrite_fluoh_commands(
            rewritten["finalCheckCommands"], fluoh_display
        )
    if "reportCommand" in rewritten:
        rewritten["reportCommand"] = rewrite_fluoh_commands(
            rewritten["reportCommand"], fluoh_display
        )
    return rewritten


def fluoh_setup_status(fluoh: dict[str, Any]) -> dict[str, Any]:
    if fluoh.get("ok") is True:
        return {
            "status": "ready",
            "classification": "working",
            "hints": [],
        }
    stderr = str(fluoh.get("stderr") or "")
    stdout = str(fluoh.get("stdout") or "")
    combined = f"{stdout}\n{stderr}"
    hints = [
        "Run CLI setup before following commandQueue.",
        "Do not classify fluoh launcher failures as package implementation failures.",
    ]
    classification = "unavailable"
    if (
        "update_engine_version.sh" in combined
        or "engine.stamp.tmp" in combined
        or "engine.realm" in combined
    ):
        classification = "dart-pub-shim-flutter-cache-permission"
        hints.extend(
            [
                "The fluoh executable appears to be a Dart pub global shim using Flutter's dart wrapper.",
                "Use a native/Homebrew fluoh executable, set FLUOH_BIN to a working fluoh, or pass --fluoh-command with a local checkout command.",
                "When validating the fluoh repository itself, use dart run bin/fluoh.dart.",
            ]
        )
    elif "No such file" in combined or "not found" in combined:
        classification = "missing-executable"
        hints.append(
            "Install fluoh, or set FLUOH_BIN/--fluoh-command to the executable path."
        )
    return {
        "status": "needs-cli-setup",
        "classification": classification,
        "hints": hints,
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
        return {"status": "unsupported-schema", "version": version, "currentVersion": 1}
    if version > 1:
        return {"status": "requires-newer-fluoh", "version": version, "currentVersion": 1}
    return {"status": "current", "version": version, "currentVersion": 1}


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
    package_name: str | None = None,
    auto_sign: bool = False,
) -> str:
    package_part = f" --package {package_name}" if package_name else ""
    auto_sign_part = " --auto-sign" if auto_sign else ""
    return f"fluoh build {platform}{package_part}{auto_sign_part} --json --trace"


def run_command(
    platform: str,
    package_name: str | None = None,
    auto_emulator: bool = False,
) -> str:
    package_part = f" --package {package_name}" if package_name else ""
    auto_emulator_part = " --auto-emulator" if auto_emulator else ""
    return f"fluoh run {platform}{package_part}{auto_emulator_part} --json --trace"


def ohos_support_commands(
    package_name: str | None = None,
) -> list[str]:
    return [
        doctor_command(OHOS_PLATFORM, project=True, strict=True),
        build_command(
            OHOS_PLATFORM,
            package_name,
            auto_sign=True,
        ),
        devices_command(OHOS_PLATFORM),
        emulators_command(OHOS_PLATFORM),
        run_command(
            OHOS_PLATFORM,
            package_name,
            auto_emulator=True,
        ),
    ]


def regression_run_command(
    platform: str,
    package_name: str | None = None,
) -> str:
    if platform in BUILD_REGRESSION_PLATFORMS:
        return build_command(platform, package_name)
    return run_command(
        platform,
        package_name,
        auto_emulator=platform in AUTO_EMULATOR_REGRESSION_PLATFORMS,
    )


def regression_commands_for_platform(
    platform: str,
    package_name: str | None = None,
) -> list[str]:
    return [
        doctor_command(platform, strict=True),
        regression_run_command(platform, package_name),
    ]


def drive_command(
    platform: str,
    package_name: str | None = None,
    *,
    dry_run: bool = False,
) -> str:
    package_part = f" --package {package_name}" if package_name else ""
    dry_run_part = " --dry-run" if dry_run else ""
    return f"fluoh drive {platform}{package_part}{dry_run_part} --json --trace"


def drive_commands(
    platform: str,
    package_name: str | None = None,
) -> list[str]:
    return [
        drive_command(platform, package_name, dry_run=True),
        drive_command(platform, package_name),
    ]


def host_supports_drive_platform(platform: str) -> bool:
    if platform in {"ohos", "android"}:
        return True
    if platform == "ios":
        return sys.platform == "darwin"
    return False


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
    package_support = (
        top_level_scalar(content, "kind") == "package"
        or top_level_key(content, "package")
    )
    has_example = (root / "example" / "pubspec.yaml").is_file()
    has_app_entry = (root / "lib" / "main.dart").is_file()
    has_flutter = is_flutter_pubspec(pubspec_content)
    has_flutter_plugin = is_flutter_plugin_pubspec(pubspec_content)
    if package_support:
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
        "hasPackageBranch": package_support,
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


def upgrade_checks(root: Path, project: dict[str, Any]) -> dict[str, Any]:
    fluoh_yaml = root / "fluoh.yaml"
    content = read_text(fluoh_yaml) if fluoh_yaml.exists() else ""
    schema = schema_state(fluoh_yaml, content)
    checks: dict[str, Any] = {
        "schema": schema,
        "blocksEditing": schema["status"]
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
    elif checks["blocksEditing"]:
        checks["notes"].append(
            "fluoh.yaml is not in the current canonical schema; stop before editing and regenerate metadata."
        )

    return checks


def app_platform_regression_commands(project: dict[str, Any]) -> list[str]:
    platforms = project.get("platformDirectories", {})
    commands: list[str] = []
    for platform in REGRESSION_PLATFORM_ORDER:
        if platforms.get(platform) and host_supports_regression_platform(platform):
            commands.extend(regression_commands_for_platform(platform))
            if platform in {"android", "ios"} and host_supports_drive_platform(platform):
                commands.extend(drive_commands(platform))
    return commands


def selected_package_entry(project: dict[str, Any]) -> dict[str, Any]:
    selected = project.get("selectedPackage")
    for package in project.get("packages", []):
        if package.get("name") == selected:
            return package
    return {}


def package_platform_regression_commands(
    project: dict[str, Any], package_name: str
) -> list[str]:
    package = selected_package_entry(project)
    platforms = package.get("examplePlatforms", {})
    commands: list[str] = []
    for platform in REGRESSION_PLATFORM_ORDER:
        if platforms.get(platform) and host_supports_regression_platform(platform):
            commands.extend(
                regression_commands_for_platform(
                    platform,
                    package_name,
                )
            )
            if platform in {"android", "ios"} and host_supports_drive_platform(platform):
                commands.extend(drive_commands(platform, package_name))
    return commands


def suggested_commands(info: dict[str, Any]) -> list[str]:
    project = info["project"]
    kind = project["kind"]
    upgrade = info.get("upgradeChecks", {})
    upgrade_commands = upgrade.get("commands", [])
    if kind == "app-project":
        sdk = project["sdkVersion"] or "<sdk-version-or-line>"
        scope = slug(project["name"] or "app", "app")
        return [
            *upgrade_commands,
            f"fluoh task start --type appSupport --scope {command_arg(scope)} --json",
            "fluoh source update",
            f"fluoh sdk use {sdk} --pub-get",
            "fluoh deps check --json",
            "fluoh deps fix --dry-run --json",
            "fluoh deps fix",
            "fluoh deps get",
            *ohos_support_commands(),
            *drive_commands(OHOS_PLATFORM),
            *app_platform_regression_commands(project),
            f"fluoh report create --scope {command_arg(project['name'] or 'app')} --json",
            report_check_command(),
        ]
    if kind == "package-repository":
        package = project["selectedPackage"] or "<name>"
        return [
            *upgrade_commands,
            f"fluoh task start --type packageSupport --scope {command_arg(package)} --package {command_arg(package)} --json",
            f"fluoh package next --package {package} --json",
            f"fluoh package status --package {package} --json",
            f"fluoh package handoff --package {package} --json",
            f"fluoh package check --package {package} --report <report-path> --json",
        ]
    if kind == "flutter-package":
        package = project["name"] or "<package-name>"
        output = flutter_package_output(project)
        upstream = shlex.quote(info["cwd"])
        create_base = (
            f"fluoh package port {upstream} --repository-name {package} --output {output} "
            "--repository <flutteroh-repo-url-or-path> "
            "--git-author-name <name> --git-author-email <email> "
            "--sdk <sdk-version-or-line> --package-path ."
        )
        return [
            "Resolve package setup: "
            f"repository-name={package}, output={output}, repository=<flutteroh-repo-url-or-path>, "
            "git-author-name=<name>, git-author-email=<email>, sdk=<sdk-version-or-line>",
            f"{create_base} --plan --json",
            create_base,
            f"cd {output}",
            f"fluoh task start --type packageSupport --scope {package} --package {package} --json",
            f"fluoh package next --package {package} --json",
            f"fluoh package status --package {package} --json",
            f"fluoh package handoff --package {package} --json",
            f"fluoh package check --package {package} --report <report-path> --json",
        ]
    if kind == "dart-package":
        return [
            "This is a Dart package, not a Flutter app or FlutterOH package repository; ask for a Flutter project/package path before editing.",
        ]
    return [
        "Run this from a Flutter project, a FlutterOH package repository, or create one with fluoh package port <upstream> --repository-name <repository-name>.",
    ]


def final_check_commands(info: dict[str, Any]) -> list[str]:
    project = info["project"]
    kind = project["kind"]
    if kind == "app-project":
        return [
            "git diff --check",
            *ohos_support_commands(),
            *drive_commands(OHOS_PLATFORM),
            *app_platform_regression_commands(project),
            report_check_command(),
        ]
    if kind == "package-repository":
        package = project["selectedPackage"] or "<name>"
        return [
            "git diff --check",
            f"fluoh package next --package {package} --json",
            f"fluoh verify --package {package} --json --trace",
            *ohos_support_commands(package),
            *drive_commands(OHOS_PLATFORM, package),
            *package_platform_regression_commands(project, package),
            f"fluoh package status --package {package} --json",
            report_check_command(),
            f"fluoh package handoff --package {package} --json",
            f"fluoh package check --package {package} --report <report-path> --json",
        ]
    if kind == "flutter-package":
        return []
    return []


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
            "package repository before adding platform implementation changes."
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
    parser.add_argument(
        "--json",
        action="store_true",
        help="Print JSON output. This is the default output format.",
    )
    args = parser.parse_args()
    root = Path(args.path).expanduser().resolve()
    command_cwd = root if root.is_dir() else Path.cwd()
    requested_package = args.package.strip() or None
    fluoh_command = fluoh_command_args(args.fluoh_command)
    fluoh_display = display_command(fluoh_command)
    fluoh_result = run([*fluoh_command, "--version"], command_cwd)
    info: dict[str, Any] = {
        "schema": 1,
        "cwd": str(root),
        "pathExists": root.exists(),
        "pathIsDirectory": root.is_dir(),
        "fluohCommand": fluoh_display,
        "fluohCommandArgs": fluoh_command,
        "fluoh": fluoh_result,
        "fluohSetup": fluoh_setup_status(fluoh_result),
        "project": project_info(root, requested_package=requested_package),
        "git": git_state(root),
    }
    info["upgradeChecks"] = upgrade_checks(root, info["project"])
    plan_command = support_plan_command(info["project"])
    info["supportPlanCommand"] = plan_command
    plan_result = (
        run_fluoh_plan(fluoh_command, plan_command, command_cwd)
        if info["fluohSetup"]["status"] == "ready"
        else None
    )
    if plan_result is not None:
        info["supportPlan"] = {
            key: value
            for key, value in plan_result.items()
            if key not in {"stdout", "stderr"}
        }
    plan = plan_result.get("plan") if plan_result and plan_result.get("ok") else None
    if isinstance(plan, dict):
        info["suggestedCommands"] = commands_from_plan_queue(plan)
        info["commandQueue"] = plan.get("queue", [])
        delivery = plan.get("deliveryGate")
        if isinstance(delivery, dict):
            info["finalCheckCommands"] = delivery.get("finalCheckCommands", [])
            info["deliveryGate"] = delivery
        else:
            info["finalCheckCommands"] = final_check_commands(info)
            info["deliveryGate"] = delivery_gate(
                info["project"], info["finalCheckCommands"]
            )
        runbook = plan.get("automationRunbook")
        info["automationRunbook"] = (
            runbook if isinstance(runbook, dict) else automation_runbook(info["project"])
        )
    else:
        info["suggestedCommands"] = suggested_commands(info)
        info["commandQueue"] = command_queue(
            info["suggestedCommands"], info["project"]
        )
        info["finalCheckCommands"] = final_check_commands(info)
        info["automationRunbook"] = automation_runbook(info["project"])
        info["deliveryGate"] = delivery_gate(
            info["project"], info["finalCheckCommands"]
        )
    info["deliveryChecks"] = delivery_checks(info["project"])
    delivery_gate_value = info.get("deliveryGate")
    delivery_report_command = (
        delivery_gate_value.get("reportCommand")
        if isinstance(delivery_gate_value, dict)
        else None
    )
    info["reportCommand"] = (
        delivery_report_command
        if isinstance(delivery_report_command, str)
        else report_command(info["project"])
    )
    info["summaryCommand"] = summary_command(info["project"])
    info["reportCheckCommand"] = report_check_command()
    info["feedbackCommand"] = feedback_command()
    info["sessionInspectCommand"] = session_inspect_command()
    info["sessionAttachCommand"] = session_attach_command()
    info["scenarioCommand"] = scenario_command(info["project"])
    info["notes"] = notes(info["project"])
    if fluoh_display != "fluoh" and info["fluohSetup"]["status"] == "ready":
        info["executableSupportPlanCommand"] = rewrite_fluoh_commands(
            info.get("supportPlanCommand"), fluoh_display
        )
        info["executableSuggestedCommands"] = rewrite_fluoh_commands(
            info.get("suggestedCommands", []), fluoh_display
        )
        info["executableCommandQueue"] = rewrite_fluoh_commands(
            info.get("commandQueue", []), fluoh_display
        )
        info["executableFinalCheckCommands"] = rewrite_fluoh_commands(
            info.get("finalCheckCommands", []), fluoh_display
        )
        info["executableDeliveryGate"] = executable_delivery_gate(
            info.get("deliveryGate"), fluoh_display
        )
        info["executableReportCommand"] = rewrite_fluoh_commands(
            info.get("reportCommand"), fluoh_display
        )
        info["executableSessionAttachCommand"] = rewrite_fluoh_commands(
            info.get("sessionAttachCommand"), fluoh_display
        )
    print(json.dumps(info, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
