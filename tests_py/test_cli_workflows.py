import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


class CliWorkflows(unittest.TestCase):
    def run_cli(self, *args, cwd=None):
        return subprocess.run([sys.executable, "-m", "skill_stocktake", *args], cwd=cwd, text=True, capture_output=True)

    def test_scan_writes_scoped_inventory_without_usage(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            skill = root / ".agents" / "skills" / "demo"
            skill.mkdir(parents=True)
            (skill / "SKILL.md").write_text("---\nname: demo\ndescription: demo\n---\n", encoding="utf-8")
            result = self.run_cli("scan", "--project-root", str(root), cwd=Path(__file__).parents[1])
            self.assertEqual(result.returncode, 0, result.stderr)
            inventory = json.loads(result.stdout)
            self.assertFalse(inventory["privacy"]["usage_scanned"])
            self.assertEqual(inventory["skills"][0]["logical_name"], "demo")
            self.assertTrue((root / ".skill-stocktake" / "work.json").is_file())

    def test_scan_refuses_existing_artifact_without_force(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            first = self.run_cli("scan", "--project-root", str(root), cwd=Path(__file__).parents[1])
            second = self.run_cli("scan", "--project-root", str(root), cwd=Path(__file__).parents[1])
            self.assertEqual(first.returncode, 0)
            self.assertEqual(second.returncode, 5)

    def test_migrate_creates_v3_backup(self):
        with tempfile.TemporaryDirectory() as temp:
            state = Path(temp) / "results.json"
            state.write_text(json.dumps({"schema_version": 3, "project_root": temp, "last_completed": {"skills": {}}, "active_run": None}), encoding="utf-8")
            result = self.run_cli("migrate", "--state", str(state), cwd=Path(__file__).parents[1])
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(state.read_text())["schema_version"], 4)
            self.assertTrue(state.with_suffix(".json.v3.bak").is_file())

    def test_report_redacts_home(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            state = root / "state.json"
            state.write_text(json.dumps({"schema_version": 4, "project_root": str(root), "last_completed": {"skills": {}}, "active_run": None}), encoding="utf-8")
            result = self.run_cli("report", "--state", str(state), "--project-root", str(root), cwd=Path(__file__).parents[1])
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn(str(Path.home()), result.stdout)

    def test_scan_include_usage_and_managed_plugins_are_integrated(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp); project = base / "project"; home = base / "home"
            project.mkdir(); sessions = home / ".codex" / "sessions"; sessions.mkdir(parents=True)
            skill = home / ".codex" / "plugins" / "cache" / "openai-curated" / "demo" / "latest" / "skills" / "managed"
            skill.mkdir(parents=True)
            (skill / "SKILL.md").write_text("---\nname: managed\ndescription: managed\n---\n")
            (sessions / "one.jsonl").write_text(json.dumps({"session_meta": {"id": "s1"}, "message": "$managed"}) + "\n")
            result = self.run_cli("scan", "--project-root", str(project), "--home-root", str(home), "--include-usage", cwd=Path(__file__).parents[1])
            self.assertEqual(result.returncode, 0, result.stderr)
            inventory = json.loads(result.stdout)
            self.assertTrue(inventory["privacy"]["usage_scanned"])
            managed = next(item for item in inventory["skills"] if item["logical_name"] == "managed")
            self.assertEqual(managed["ownership"], "managed-read-only")
            self.assertEqual(managed["usage"]["unique_sessions_30d"], 1)


if __name__ == "__main__":
    unittest.main()
