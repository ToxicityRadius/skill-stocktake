import re
from pathlib import Path

from .paths import contained_file

TEXT_EXTENSIONS = {".md", ".txt", ".json", ".yaml", ".yml", ".toml", ".py", ".ps1", ".psm1", ".sh", ".js", ".mjs", ".cjs", ".ts", ".tsx", ".jsx", ".bat", ".cmd"}
RULES = (
    ("SEC001", "download_execute", "high", re.compile(r"(?i)(curl|wget|invoke-webrequest)[^\n|;]*(\||;|&&)\s*(sh|bash|pwsh|powershell|python|node)")),
    ("SEC002", "destructive_command", "high", re.compile(r"(?i)\b(rm\s+-rf|git\s+reset\s+--hard|remove-item\b[^\n]*(?:-recurse|-force))")),
    ("SEC003", "credential_access", "medium", re.compile(r"(?i)(\.ssh[/\\]|credentials|keychain|password\s*=|api[_-]?key\s*=)")),
    ("SEC004", "privilege_escalation", "high", re.compile(r"(?i)\b(sudo|runas|start-process[^\n]*-verb\s+runas)\b")),
    ("SEC005", "persistence", "high", re.compile(r"(?i)(authorized_keys|crontab|schtasks|startup\\|launchagents)")),
    ("SEC006", "obfuscation", "medium", re.compile(r"(?i)(frombase64string|base64\s+-d|eval\s*\(|invoke-expression)")),
)
RISK_ORDER = {"none": 0, "low": 1, "medium": 2, "high": 3, "critical": 4}


def scan_skill_security(root: Path, *, max_file_bytes: int = 1_048_576, max_skill_bytes: int = 10_485_760) -> dict:
    findings, skipped, consumed = [], [], 0
    for path in sorted(Path(root).rglob("*")):
        relative = path.relative_to(root).as_posix()
        if path.suffix.lower() not in TEXT_EXTENSIONS:
            continue
        if not contained_file(root, path):
            skipped.append(relative)
            continue
        size = path.stat().st_size
        if size > max_file_bytes or consumed + size > max_skill_bytes:
            skipped.append(relative)
            continue
        consumed += size
        text = path.read_text(encoding="utf-8", errors="replace")
        for line_number, line in enumerate(text.splitlines(), 1):
            for rule_id, category, severity, pattern in RULES:
                if pattern.search(line):
                    findings.append({"rule_id": rule_id, "category": category, "severity": severity, "path": relative, "line": line_number, "detail": f"matched {rule_id}"})
    risk = max((item["severity"] for item in findings), key=lambda value: RISK_ORDER[value], default="none")
    return {"status": "scanned", "risk_level": risk, "findings": findings, "skipped": skipped}
