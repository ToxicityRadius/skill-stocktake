import json
import re
from datetime import datetime, timezone, timedelta
from pathlib import Path


def _parse_time(value):
    if not value:
        return None
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00")).astimezone(timezone.utc)
    except ValueError:
        return None


def aggregate_usage(sessions_root, skill_names, *, now=None):
    now = now or datetime.now(timezone.utc)
    results = {name: {"unique_sessions_7d": 0, "unique_sessions_30d": 0, "mentions_30d": 0} for name in skill_names}
    patterns = {name: re.compile(r"(?<![\w-])(?:\$|/)" + re.escape(name) + r"(?![\w-])", re.IGNORECASE) for name in skill_names}
    seen7 = {name: set() for name in skill_names}; seen30 = {name: set() for name in skill_names}
    root = Path(sessions_root)
    if not root.is_dir():
        return results
    for path in root.rglob("*.jsonl"):
        session_id = path.as_posix()
        for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
            try:
                item = json.loads(line)
            except json.JSONDecodeError:
                continue
            meta = item.get("session_meta") or (item.get("payload") or {}).get("session_meta")
            if isinstance(meta, dict) and meta.get("id"):
                session_id = str(meta["id"])
            timestamp = _parse_time(item.get("timestamp") or (item.get("payload") or {}).get("timestamp")) or datetime.fromtimestamp(path.stat().st_mtime, timezone.utc)
            age = now - timestamp
            if age < timedelta(0) or age > timedelta(days=30):
                continue
            text = json.dumps(item, ensure_ascii=False)
            for name, pattern in patterns.items():
                count = len(pattern.findall(text))
                if count:
                    results[name]["mentions_30d"] += count
                    seen30[name].add(session_id)
                    if age <= timedelta(days=7):
                        seen7[name].add(session_id)
    for name in skill_names:
        results[name]["unique_sessions_7d"] = len(seen7[name])
        results[name]["unique_sessions_30d"] = len(seen30[name])
    return results
