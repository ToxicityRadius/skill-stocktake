import hashlib
import re
from pathlib import Path


def _inside(path: Path, root: Path) -> bool:
    try:
        path.relative_to(root)
        return True
    except ValueError:
        return False


def discover_skills(roots, *, allow_symlink_roots=[]) -> dict:
    allowed = [Path(item).resolve() for item in allow_symlink_roots]
    skills, diagnostics = [], []
    for raw_root in roots:
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
            skills.append({"logical_id": logical_id, "logical_name": name, "path": str(skill_file), "security": {"status": "not_scanned", "risk_level": "unknown", "findings": []}})
    return {"schema_version": 4, "skills": skills, "diagnostics": diagnostics, "privacy": {"usage_scanned": False, "report_redaction": True}}
