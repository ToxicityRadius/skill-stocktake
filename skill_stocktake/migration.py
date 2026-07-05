import copy


def migrate_v3(state: dict) -> dict:
    if state.get("schema_version") != 3:
        raise ValueError("only schema v3 can be migrated")
    migrated = copy.deepcopy(state)
    migrated["schema_version"] = 4
    migrated.setdefault("privacy", {"usage_scanned": False, "report_redaction": True})
    completed = migrated.get("last_completed") or {}
    for record in (completed.get("skills") or {}).values():
        record.setdefault("security", {"status": "not_scanned", "risk_level": "unknown", "findings": []})
    return migrated
