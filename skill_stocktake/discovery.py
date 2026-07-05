import hashlib
import json
import re
from pathlib import Path


def _inside(path: Path, root: Path) -> bool:
    try:
        path.relative_to(root)
        return True
    except ValueError:
        return False


def _bundle_hash(root: Path) -> str:
    entries = []
    for path in sorted(item for item in root.rglob("*") if item.is_file() and not any(part in {".git", "__pycache__", "node_modules"} for part in item.relative_to(root).parts)):
        entries.append(path.relative_to(root).as_posix().lower() + ":" + hashlib.sha256(path.read_bytes()).hexdigest())
    return hashlib.sha256("\n".join(entries).encode()).hexdigest()


def _runtime_plugins(path):
    if not path or not Path(path).is_file():
        return {}
    try:
        data = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    return {str(item.get("pluginId", "")).lower(): item for item in data.get("installed", []) if item.get("pluginId")}


def _configured_plugins(path):
    if not path or not Path(path).is_file():
        return {}
    configured = {}
    current = None
    try:
        lines = Path(path).read_text(encoding="utf-8").splitlines()
    except OSError:
        return {}
    for line in lines:
        stripped = line.strip()
        section = re.fullmatch(r'\[plugins\."([^"]+)"\]', stripped)
        if section:
            current = section.group(1).lower()
            configured.setdefault(current, {})
            continue
        if stripped.startswith("["):
            current = None
            continue
        enabled = re.fullmatch(r"enabled\s*=\s*(true|false)\s*(?:#.*)?", stripped, re.IGNORECASE)
        if current and enabled:
            configured[current]["enabled"] = enabled.group(1).lower() == "true"
    return configured


def discover_managed_roots(cache_root, *, config_path=None, plugin_inventory_path=None):
    cache = Path(cache_root)
    if not cache.is_dir():
        return []
    runtime = _runtime_plugins(plugin_inventory_path)
    configured = _configured_plugins(config_path)
    groups = {}
    excluded = re.compile(r"(?i)^(?:plugin-backup.*|plugin-install.*|backup-.*|staging|node_modules|tests?|fixtures?)$")
    for skills in cache.rglob("skills"):
        if not skills.is_dir() or any(excluded.match(part) for part in skills.relative_to(cache).parts):
            continue
        try:
            version_dir, plugin_dir, origin_dir = skills.parent, skills.parent.parent, skills.parent.parent.parent
            origin = origin_dir.name
        except AttributeError:
            continue
        family = "openai-curated" if origin in {"openai-curated", "openai-curated-remote"} else origin
        groups.setdefault((family.lower(), plugin_dir.name.lower()), []).append({
            "path": skills, "version": version_dir.name, "plugin": plugin_dir.name, "origin": origin,
            "remote": origin == "openai-curated-remote" and (plugin_dir / ".codex-remote-plugin-install.json").is_file(),
        })
    result = []
    for (family, plugin), items in sorted(groups.items()):
        preferred = [item for item in items if item["remote"]] or items
        selected = next((item for item in preferred if item["version"] == "latest"), None)
        if selected is None:
            selected = max(preferred, key=lambda item: (item["path"].stat().st_mtime_ns, item["version"]))
        plugin_id = f"{plugin}@{family}"
        runtime_item = runtime.get(plugin_id)
        setting = configured.get(plugin_id, {})
        enabled = bool((runtime_item or {}).get("enabled", True)) and bool(setting.get("enabled", True))
        result.append({
            "source": f"managed:{selected['origin']}:{selected['plugin']}",
            "ownership": "managed-read-only", "path": str(selected["path"]),
            "plugin_id": plugin_id, "enabled": enabled,
            "selection": "disabled" if not enabled else "runtime-confirmed" if runtime_item else "remote-install-record" if selected["remote"] else "explicit-latest" if selected["version"] == "latest" else "best-effort-current",
        })
    return result


def discover_skills(roots, *, allow_symlink_roots=None) -> dict:
    allow_symlink_roots = allow_symlink_roots or []
    allowed = [Path(item).resolve() for item in allow_symlink_roots]
    skills, diagnostics = [], []
    for root_spec in roots:
        raw_root = root_spec.get("path") if isinstance(root_spec, dict) else root_spec
        metadata = root_spec if isinstance(root_spec, dict) else {}
        root = Path(raw_root).resolve()
        if not root.exists():
            continue
        for candidate in sorted(root.iterdir()):
            if not candidate.is_dir():
                continue
            resolved = candidate.resolve()
            if candidate.is_symlink() and not _inside(resolved, root) and not any(_inside(resolved, item) for item in allowed):
                diagnostics.append({"code": "external_symlink_excluded", "severity": "warning", "path": str(candidate), "message": "Symlink target is outside the discovered root."})
                continue
            skill_file = resolved / "SKILL.md"
            if not skill_file.is_file():
                continue
            text = skill_file.read_text(encoding="utf-8-sig", errors="replace")
            match = re.search(r"(?m)^name:\s*[\"']?([^\"'\r\n]+)", text)
            name = match.group(1).strip() if match else candidate.name
            logical_id = "s-" + hashlib.sha256(f"user:{name}".encode()).hexdigest()[:20]
            bundle = _bundle_hash(resolved)
            skills.append({"logical_id": logical_id, "logical_name": name, "path": str(skill_file), "locations": [str(skill_file)], "bundle_sha256": bundle, "source": metadata.get("source", "user"), "ownership": metadata.get("ownership", "user"), "security": {"status": "not_scanned", "risk_level": "unknown", "findings": []}})
    grouped = {}
    for skill in skills:
        key = (skill["logical_name"].lower(), skill["bundle_sha256"])
        if key in grouped:
            grouped[key]["locations"].extend(skill["locations"])
        else:
            grouped[key] = skill
    skills = list(grouped.values())
    return {"schema_version": 4, "skills": skills, "diagnostics": diagnostics, "privacy": {"usage_scanned": False, "report_redaction": True}}
