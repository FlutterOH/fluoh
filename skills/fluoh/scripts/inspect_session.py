#!/usr/bin/env python3
"""Inspect a fluoh live Flutter run session JSON file."""

from __future__ import annotations

import argparse
import json
import time
from pathlib import Path
from typing import Any


def load_json(path: Path) -> tuple[dict[str, Any] | None, str | None]:
    try:
        with path.open(encoding="utf-8") as handle:
            value = json.load(handle)
    except FileNotFoundError:
        return None, "Session file does not exist."
    except json.JSONDecodeError as error:
        return None, f"Session file is not valid JSON: {error}"
    except OSError as error:
        return None, f"Session file cannot be read: {error}"
    if not isinstance(value, dict):
        return None, "Session file must contain one JSON object."
    return value, None


def session_errors(
    session: dict[str, Any],
    *,
    expect_platform: str,
    require_vm_service: bool,
    allow_failed: bool,
) -> list[str]:
    errors: list[str] = []
    if session.get("kind") != "flutterRunSession":
        errors.append("Session kind must be flutterRunSession.")
    if expect_platform and session.get("platform") != expect_platform:
        errors.append(
            f"Expected platform {expect_platform}, found {session.get('platform')!r}."
        )
    if require_vm_service and not session.get("vmServiceUri"):
        errors.append("Session does not include vmServiceUri.")
    if session.get("status") == "failed" and not allow_failed:
        errors.append("Session status is failed.")
    return errors


def should_wait_for_updates(errors: list[str], session: dict[str, Any]) -> bool:
    if errors != ["Session does not include vmServiceUri."]:
        return False
    return session.get("status") not in ("failed", "passed")


def wait_for_session(
    path: Path,
    timeout: float,
    *,
    expect_platform: str,
    require_vm_service: bool,
    allow_failed: bool,
) -> tuple[dict[str, Any] | None, str | None]:
    deadline = time.monotonic() + max(timeout, 0.0)
    last_error = "Session file does not exist."
    while True:
        session, error = load_json(path)
        if session is not None:
            errors = session_errors(
                session,
                expect_platform=expect_platform,
                require_vm_service=require_vm_service,
                allow_failed=allow_failed,
            )
            if not errors or not should_wait_for_updates(errors, session):
                return session, None
            last_error = "; ".join(errors)
            if time.monotonic() >= deadline:
                return session, None
            time.sleep(0.25)
            continue
        else:
            last_error = error or last_error
        if time.monotonic() >= deadline:
            return None, last_error
        time.sleep(0.25)


def age_seconds(path: Path) -> float | None:
    try:
        return max(0.0, time.time() - path.stat().st_mtime)
    except OSError:
        return None


def attach_hints(session: dict[str, Any]) -> list[str]:
    hints: list[str] = []
    uri = session.get("vmServiceUri")
    if isinstance(uri, str) and uri:
        hints.append(f"Attach to Flutter VM Service: {uri}")
        hints.append("Use Flutter inspector, widget tree, semantics, logs, or VM service extensions for functional assertions.")
    output_log = session.get("outputLog")
    if isinstance(output_log, str) and output_log:
        hints.append(f"Inspect run output log: {output_log}")
    if session.get("platform") in {"macos", "linux", "web", "windows"}:
        hints.append("Desktop and Web runs can be checked through host process logs and Flutter debug state.")
    return hints


def recommendation(session: dict[str, Any]) -> str:
    status = session.get("status")
    if status == "failed":
        return "investigate-failure"
    if status == "passed":
        return "run-complete"
    if session.get("vmServiceUri"):
        return "attach-vm-service"
    if session.get("launchDetected"):
        return "inspect-running-output"
    return "wait-for-launch"


def build_report(
    path: Path,
    session: dict[str, Any] | None,
    error: str | None,
    *,
    expect_platform: str,
    require_vm_service: bool,
    allow_failed: bool,
) -> dict[str, Any]:
    errors: list[str] = []
    if error:
        errors.append(error)
    if session is not None:
        errors.extend(
            session_errors(
                session,
                expect_platform=expect_platform,
                require_vm_service=require_vm_service,
                allow_failed=allow_failed,
            )
        )
    ok = not errors
    report: dict[str, Any] = {
        "schema": 1,
        "ok": ok,
        "exitCode": 0 if ok else 1,
        "sessionFile": str(path),
        "exists": path.exists(),
        "ageSeconds": age_seconds(path),
        "errors": errors,
    }
    if session is not None:
        report.update(
            {
                "kind": session.get("kind"),
                "status": session.get("status"),
                "platform": session.get("platform"),
                "processId": session.get("processId"),
                "launchDetected": session.get("launchDetected"),
                "vmServiceUri": session.get("vmServiceUri"),
                "target": session.get("target"),
                "emulator": session.get("emulator"),
                "outputLog": session.get("outputLog"),
                "updatedAt": session.get("updatedAt"),
                "recommendation": recommendation(session),
                "attachHints": attach_hints(session),
            }
        )
    else:
        report["recommendation"] = "missing-session"
        report["attachHints"] = []
    return report


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Inspect a fluoh flutterRunSession JSON file.",
    )
    parser.add_argument("session_file", help="Path passed to fluoh run --session-file")
    parser.add_argument(
        "--wait",
        type=float,
        default=0.0,
        help="Seconds to wait for the session file to appear and become readable",
    )
    parser.add_argument(
        "--expect-platform",
        choices=("android", "ios", "macos", "linux", "web", "windows"),
        default="",
        help="Fail when the session platform differs",
    )
    parser.add_argument(
        "--require-vm-service",
        action="store_true",
        help="Fail until the session includes vmServiceUri",
    )
    parser.add_argument(
        "--allow-failed",
        action="store_true",
        help="Return ok even when the run session status is failed",
    )
    args = parser.parse_args()

    path = Path(args.session_file).expanduser().resolve()
    session, error = wait_for_session(
        path,
        args.wait,
        expect_platform=args.expect_platform,
        require_vm_service=args.require_vm_service,
        allow_failed=args.allow_failed,
    )
    report = build_report(
        path,
        session,
        error,
        expect_platform=args.expect_platform,
        require_vm_service=args.require_vm_service,
        allow_failed=args.allow_failed,
    )
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return int(report["exitCode"])


if __name__ == "__main__":
    raise SystemExit(main())
