from .redaction import PathRedactor


def _clean(value):
    return str(value if value is not None else "").replace("|", "\\|").replace("\r", " ").replace("\n", " ")


def format_report(state, inventory, *, project_root, home, codex_home=None, plugin_cache=None):
    redactor = PathRedactor(home=str(home), project=str(project_root), codex_home=str(codex_home or ""), plugin_cache=str(plugin_cache or ""))
    generation = state.get("last_completed") or state.get("active_run")
    records = (generation or {}).get("skills", {})
    if isinstance(records, list):
        records = {item["logical_id"]: item for item in records}
    by_id = {item["logical_id"]: item for item in inventory.get("skills", [])}
    lines = ["# Skill Stocktake Report", "", f"Project: {redactor.redact(str(state.get('project_root', project_root)))}", f"Schema: {state.get('schema_version')}", f"Usage aggregation: {'enabled' if inventory.get('privacy', {}).get('usage_scanned') else 'disabled'}", "", "## Lifecycle findings", "", "| Skill | Source | Ownership | 7-day sessions | Verdict | Confidence | Security risk | Reason |", "|---|---|---|---:|---|---|---|---|"]
    for logical_id, record in sorted(records.items(), key=lambda pair: str(pair[1].get("logical_name", pair[0]))):
        skill = by_id.get(logical_id, {})
        usage = skill.get("usage", {})
        risk = skill.get("security", {}).get("risk_level", "unknown")
        lines.append(f"| {_clean(record.get('logical_name', skill.get('logical_name', logical_id)))} | {_clean(skill.get('source', 'removed'))} | {_clean(skill.get('ownership', 'unknown'))} | {usage.get('unique_sessions_7d', 0)} | {_clean(record.get('verdict', 'Pending'))} | {_clean(record.get('confidence', 'low'))} | {_clean(risk)} | {_clean(record.get('reason', ''))} |")
    lines += ["", "## Security and diagnostics", "", f"Diagnostics: {len(inventory.get('diagnostics', []))}. Security findings are advisory and separate from lifecycle verdicts."]
    return "\n".join(lines) + "\n"
