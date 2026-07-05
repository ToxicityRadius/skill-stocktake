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


def merge_state(existing: dict | None, incoming: dict) -> dict:
    validate_state(incoming)
    if existing:
        validate_state(existing)
        if Path(existing["project_root"]).resolve() != Path(incoming["project_root"]).resolve():
            raise ValueError("cannot merge state from a different project root")
        old_active, new_active = existing.get("active_run"), incoming.get("active_run")
        if old_active and new_active and old_active.get("run_id") != new_active.get("run_id"):
            raise ValueError("incoming run_id does not match the active run")
    output = dict(incoming)
    active = output.get("active_run")
    if active and active.get("status") == "completed":
        records = dict(active.get("skills", {}))
        previous = (existing or incoming).get("last_completed") or {}
        if active.get("mode") in {"quick", "resume"}:
            carried = dict(previous.get("skills", {}))
            carried.update(records)
            for logical_id in active.get("removed_ids", []):
                carried.pop(logical_id, None)
            records = carried
        output["last_completed"] = {
            "run_id": active.get("run_id"),
            "completed_at": datetime.now(timezone.utc).isoformat(),
            "inventory_sha256": active.get("inventory_sha256"),
            "context_sha256": active.get("context_sha256"),
            "diagnostics": active.get("diagnostics", []),
            "skills": records,
        }
        output["active_run"] = None
    elif existing and output.get("last_completed") is None:
        output["last_completed"] = existing.get("last_completed")
    output["updated_at"] = datetime.now(timezone.utc).isoformat()
    return output


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
