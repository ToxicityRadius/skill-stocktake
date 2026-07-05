import json
import hashlib
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

from skill_stocktake.discovery import discover_managed_roots, discover_skills
from skill_stocktake.reporting import format_report
from skill_stocktake.state import merge_state
from skill_stocktake.usage import aggregate_usage


class PendingParity(unittest.TestCase):
    def test_single_instance_logical_id_matches_v3_seed(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / "skills"; skill = root / "demo"
            skill.mkdir(parents=True)
            (skill / "SKILL.md").write_text("---\nname: demo\ndescription: demo\n---\n", encoding="utf-8")
            inventory = discover_skills([{"path": root, "source": "project-agents:1", "ownership": "project"}])
            expected = "s-" + hashlib.sha256(b"instance|project-agents:1|demo/skill.md|demo").hexdigest()[:20]
            self.assertEqual(inventory["skills"][0]["logical_id"], expected)

    def test_global_compatibility_mirrors_use_v3_mirror_seed(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp); roots = []
            for source in ("global-codex", "global-agents"):
                root = base / source; skill = root / "demo"
                skill.mkdir(parents=True)
                (skill / "SKILL.md").write_text("---\nname: demo\ndescription: demo\n---\n", encoding="utf-8")
                roots.append({"path": root, "source": source, "ownership": "user"})
            inventory = discover_skills(roots)
            expected = "s-" + hashlib.sha256(b"mirror|global|demo/skill.md|demo").hexdigest()[:20]
            self.assertEqual(len(inventory["skills"]), 1)
            self.assertEqual(inventory["skills"][0]["logical_id"], expected)
            self.assertEqual(len(inventory["skills"][0]["locations"]), 2)

    def test_same_name_different_bundles_remain_distinct_and_emit_collision(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp); roots = []
            for index, body in enumerate(("one", "two"), 1):
                root = base / str(index); skill = root / "demo"
                skill.mkdir(parents=True)
                (skill / "SKILL.md").write_text(f"---\nname: demo\ndescription: demo\n---\n{body}\n", encoding="utf-8")
                roots.append({"path": root, "source": f"additional:{index}", "ownership": "user"})
            inventory = discover_skills(roots)
            self.assertEqual(len(inventory["skills"]), 2)
            self.assertEqual(len({item["logical_id"] for item in inventory["skills"]}), 2)
            self.assertIn("name_collision", {item["code"] for item in inventory["diagnostics"]})

    def test_python_310_compatibility_does_not_import_tomllib(self):
        source = (Path(__file__).parents[1] / "skill_stocktake" / "discovery.py").read_text(encoding="utf-8")
        self.assertNotIn("import tomllib", source)

    def test_powershell_entrypoints_forward_to_python(self):
        root = Path(__file__).parents[1] / "scripts"
        for name in ("Scan-Skills.ps1", "New-AuditRun.ps1", "Save-Results.ps1", "Format-Report.ps1"):
            text = (root / name).read_text(encoding="utf-8-sig")
            self.assertIn("-m', 'skill_stocktake'", text, name)
            self.assertNotIn("Import-Module", text, name)

    def test_managed_discovery_prefers_enabled_remote_install(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            local = root / "openai-curated" / "dual" / "latest" / "skills"
            remote_plugin = root / "openai-curated-remote" / "dual"
            remote = remote_plugin / "2.0.0" / "skills"
            local.mkdir(parents=True); remote.mkdir(parents=True)
            (remote_plugin / ".codex-remote-plugin-install.json").write_text("{}")
            inventory = root / "inventory.json"
            inventory.write_text(json.dumps({"installed": [{"pluginId": "dual@openai-curated", "installed": True, "enabled": True, "version": "2.0.0"}]}))
            roots = discover_managed_roots(root, plugin_inventory_path=inventory)
            self.assertEqual(len(roots), 1)
            self.assertEqual(Path(roots[0]["path"]), remote)
            self.assertEqual(roots[0]["selection"], "runtime-confirmed")

    def test_usage_reads_jsonl_only_when_called_and_counts_unique_sessions(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            now = datetime.now(timezone.utc).isoformat()
            (root / "a.jsonl").write_text("\n".join([
                json.dumps({"timestamp": now, "session_meta": {"id": "one"}}),
                json.dumps({"timestamp": now, "message": "$demo then /demo"}),
                json.dumps({"timestamp": now, "message": "$demo again"}),
            ]))
            usage = aggregate_usage(root, ["demo"], now=datetime.now(timezone.utc))
            self.assertEqual(usage["demo"]["unique_sessions_7d"], 1)
            self.assertEqual(usage["demo"]["mentions_30d"], 3)

    def test_report_contains_lifecycle_security_and_privacy_sections(self):
        inventory = {"skills": [{"logical_id": "s-1", "logical_name": "demo", "source": "user", "ownership": "user", "usage": {"unique_sessions_7d": 2}, "security": {"risk_level": "low"}}], "diagnostics": [], "privacy": {"usage_scanned": True}}
        state = {"schema_version": 4, "project_root": "/repo", "last_completed": {"skills": {"s-1": {"logical_id": "s-1", "logical_name": "demo", "verdict": "Keep", "confidence": "high", "reason": "Current and useful."}}}, "active_run": None}
        report = format_report(state, inventory, project_root="/repo", home="/home/alice")
        self.assertIn("| demo | user | user | 2 | Keep | high | low |", report)
        self.assertIn("Usage aggregation: enabled", report)

    def test_completed_quick_run_merges_records_and_removes_retired_ids(self):
        existing = {"schema_version": 4, "project_root": "/repo", "last_completed": {"skills": {"s-old": {"logical_id": "s-old"}, "s-keep": {"logical_id": "s-keep"}}}, "active_run": None}
        incoming = {"schema_version": 4, "project_root": "/repo", "last_completed": existing["last_completed"], "active_run": {"run_id": "r1", "mode": "quick", "status": "completed", "inventory_sha256": "i", "context_sha256": "c", "diagnostics": [], "removed_ids": ["s-old"], "skills": {"s-new": {"logical_id": "s-new"}}}}
        merged = merge_state(existing, incoming)
        self.assertIsNone(merged["active_run"])
        self.assertEqual(set(merged["last_completed"]["skills"]), {"s-keep", "s-new"})


if __name__ == "__main__":
    unittest.main()
