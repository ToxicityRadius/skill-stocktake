import json
import os
import socket
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path


def create_run(work: dict, *, mode: str) -> dict:
    if mode not in {"full", "quick", "resume"}:
        raise ValueError(f"invalid run mode: {mode}")
    inventory = work.get("inventory", work)
    skills = inventory.get("skills", [])
    now = datetime.now(timezone.utc).isoformat()
    return {
        "schema_version": 4,
        "project_root": work.get("project_root", inventory.get("project_root")),
        "last_completed": None,
        "active_run": {
            "run_id": str(uuid.uuid4()), "mode": mode, "status": "in_progress",
            "started_at": now, "updated_at": now,
            "pending_ids": [item["logical_id"] for item in skills], "evaluated_ids": [], "removed_ids": [], "skills": {},
        },
        "privacy": inventory.get("privacy", {"usage_scanned": False, "report_redaction": True}),
    }


def validate_state(state: dict) -> None:
    if state.get("schema_version") != 4:
        raise ValueError("state schema must be 4")
    if not state.get("project_root"):
        raise ValueError("state requires project_root")


def save_state(path: Path, state: dict, *, lock_timeout: float = 30) -> None:
    validate_state(state)
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    lock = Path(str(path) + ".lock")
    deadline = time.monotonic() + lock_timeout
    descriptor = None
    while descriptor is None:
        try:
            descriptor = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
        except FileExistsError:
            if time.monotonic() >= deadline:
                raise TimeoutError(f"timed out waiting for state lock: {lock}")
            time.sleep(0.05)
    try:
        os.write(descriptor, json.dumps({"pid": os.getpid(), "host": socket.gethostname(), "created_at": datetime.now(timezone.utc).isoformat()}).encode())
        os.close(descriptor); descriptor = None
        temporary = path.with_name(f".{path.name}.{uuid.uuid4().hex}.tmp")
        with temporary.open("w", encoding="utf-8", newline="\n") as stream:
            json.dump(state, stream, indent=2)
            stream.flush(); os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if descriptor is not None:
            os.close(descriptor)
        lock.unlink(missing_ok=True)
