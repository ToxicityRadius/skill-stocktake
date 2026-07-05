import json
import tempfile
import unittest
from pathlib import Path

from skill_stocktake.state import create_run, save_state


class StateWorkflows(unittest.TestCase):
    def test_create_run_uses_inventory_ids(self):
        work = {"schema_version": 4, "project_root": "/repo", "skills": [{"logical_id": "s-1"}, {"logical_id": "s-2"}]}
        state = create_run(work, mode="full")
        self.assertEqual(state["active_run"]["pending_ids"], ["s-1", "s-2"])
        self.assertEqual(state["schema_version"], 4)

    def test_save_state_is_atomic_and_refuses_live_lock(self):
        with tempfile.TemporaryDirectory() as temp:
            target = Path(temp) / "results.json"
            state = {"schema_version": 4, "project_root": temp, "last_completed": None, "active_run": None}
            save_state(target, state)
            self.assertEqual(json.loads(target.read_text())["schema_version"], 4)
            lock = Path(str(target) + ".lock")
            lock.write_text("locked", encoding="utf-8")
            with self.assertRaises(TimeoutError):
                save_state(target, state, lock_timeout=0)


if __name__ == "__main__":
    unittest.main()
