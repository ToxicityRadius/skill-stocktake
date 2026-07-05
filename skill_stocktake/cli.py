import argparse
import json
import shutil
import sys
from pathlib import Path

from .artifacts import write_artifact
from .discovery import discover_managed_roots, discover_skills
from .migration import migrate_v3
from .redaction import PathRedactor
from .security import scan_skill_security
from .state import create_run, merge_state, save_state
from .usage import aggregate_usage
from .reporting import format_report


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="skill-stocktake")
    subcommands = parser.add_subparsers(dest="command", required=True)
    for command in ("scan", "diff"):
        item = subcommands.add_parser(command)
        item.add_argument("--project-root", default=".")
        item.add_argument("--home-root")
        item.add_argument("--config")
        item.add_argument("--plugin-cache-root")
        item.add_argument("--plugin-inventory")
        item.add_argument("--sessions-root")
        item.add_argument("--additional-skill-root", action="append", default=[])
        item.add_argument("--reference-search-root", action="append", default=[])
        item.add_argument("--skip-managed", action="store_true")
        item.add_argument("--include-usage", action="store_true")
        item.add_argument("--allow-symlink-root", action="append", default=[])
        item.add_argument("--artifact-dir", default=".skill-stocktake")
        item.add_argument("--force", action="store_true")
        item.add_argument("--no-artifact", action="store_true", help=argparse.SUPPRESS)
    new_run = subcommands.add_parser("new-run")
    new_run.add_argument("--worklist", required=True)
    new_run.add_argument("--output")
    new_run.add_argument("--mode", choices=("full", "quick", "resume"), default="full")
    new_run.add_argument("--force", action="store_true")
    save = subcommands.add_parser("save")
    save.add_argument("--state", required=True)
    save.add_argument("--evaluation", required=True)
    save.add_argument("--lock-timeout", type=float, default=30)
    report = subcommands.add_parser("report")
    report.add_argument("--state", required=True)
    report.add_argument("--project-root", default=".")
    report.add_argument("--inventory")
    report.add_argument("--output")
    report.add_argument("--force", action="store_true")
    migrate = subcommands.add_parser("migrate")
    migrate.add_argument("--state", required=True)
    subcommands.add_parser("doctor")
    return parser


def _scan(args) -> dict:
    project = Path(args.project_root).resolve()
    home = Path(args.home_root).resolve() if args.home_root else Path.home()
    roots = [
        {"path": project / ".agents" / "skills", "source": "project-agents", "ownership": "project"},
        {"path": project / ".codex" / "skills", "source": "project-codex", "ownership": "project"},
        {"path": home / ".agents" / "skills", "source": "global-agents", "ownership": "user"},
        {"path": home / ".codex" / "skills", "source": "global-codex", "ownership": "user"},
        {"path": home / ".codex" / "skills" / ".system", "source": "system", "ownership": "system-read-only"},
    ]
    roots.extend({"path": Path(item), "source": "additional", "ownership": "user"} for item in args.additional_skill_root)
    if not args.skip_managed:
        cache = Path(args.plugin_cache_root) if args.plugin_cache_root else home / ".codex" / "plugins" / "cache"
        roots.extend(discover_managed_roots(cache, config_path=args.config, plugin_inventory_path=args.plugin_inventory))
    inventory = discover_skills(roots, allow_symlink_roots=args.allow_symlink_root)
    for skill in inventory["skills"]:
        skill["security"] = scan_skill_security(Path(skill["path"]).parent)
    inventory["project_root"] = str(project)
    inventory["privacy"]["usage_scanned"] = bool(args.include_usage)
    if args.include_usage:
        sessions = Path(args.sessions_root) if args.sessions_root else home / ".codex" / "sessions"
        usage = aggregate_usage(sessions, [item["logical_name"] for item in inventory["skills"]])
        for skill in inventory["skills"]:
            skill["usage"] = usage[skill["logical_name"]]
    else:
        for skill in inventory["skills"]:
            skill["usage"] = {"unique_sessions_7d": 0, "unique_sessions_30d": 0, "mentions_30d": 0}
    for skill in inventory["skills"]:
        references = []
        needle = "$" + skill["logical_name"]
        for search_root in args.reference_search_root:
            root = Path(search_root)
            if not root.is_dir():
                continue
            for path in root.rglob("*"):
                if not path.is_file() or path.suffix.lower() not in {".md", ".txt", ".toml", ".yaml", ".yml", ".ps1", ".py"}:
                    continue
                try:
                    if needle.lower() in path.read_text(encoding="utf-8", errors="replace").lower():
                        references.append(str(path))
                except OSError:
                    continue
        skill["reverse_references"] = references
    artifact_dir = Path(args.artifact_dir)
    if not artifact_dir.is_absolute():
        artifact_dir = project / artifact_dir
    payload = json.dumps(inventory, indent=2)
    if not args.no_artifact:
        write_artifact(artifact_dir / "work.json", payload, force=args.force)
    return inventory


def _migrate(path: Path) -> dict:
    old = json.loads(path.read_text(encoding="utf-8"))
    migrated = migrate_v3(old)
    backup = Path(str(path) + ".v3.bak")
    if backup.exists():
        raise FileExistsError(f"migration backup already exists: {backup}")
    shutil.copy2(path, backup)
    write_artifact(path, json.dumps(migrated, indent=2), force=True)
    return migrated


def _report(args) -> str:
    state = json.loads(Path(args.state).read_text(encoding="utf-8"))
    project = str(Path(args.project_root).resolve())
    inventory = json.loads(Path(args.inventory).read_text(encoding="utf-8")) if args.inventory else {"skills": [], "diagnostics": [], "privacy": state.get("privacy", {})}
    report = format_report(state, inventory, project_root=project, home=Path.home(), codex_home=Path.home() / ".codex", plugin_cache=Path.home() / ".codex" / "plugins" / "cache")
    if args.output:
        write_artifact(Path(args.output), report, force=args.force)
    return report


def main(argv=None) -> int:
    args = build_parser().parse_args(argv)
    try:
        if args.command in ("scan", "diff"):
            print(json.dumps(_scan(args), indent=2))
        elif args.command == "migrate":
            print(json.dumps(_migrate(Path(args.state)), indent=2))
        elif args.command == "report":
            print(_report(args), end="")
        elif args.command == "new-run":
            work = json.loads(Path(args.worklist).read_text(encoding="utf-8"))
            run = create_run(work, mode=args.mode)
            payload = json.dumps(run, indent=2)
            if args.output:
                write_artifact(Path(args.output), payload, force=args.force)
            print(payload)
        elif args.command == "save":
            incoming = json.loads(Path(args.evaluation).read_text(encoding="utf-8"))
            existing = json.loads(Path(args.state).read_text(encoding="utf-8")) if Path(args.state).is_file() else None
            state = merge_state(existing, incoming)
            save_state(Path(args.state), state, lock_timeout=args.lock_timeout)
            print(json.dumps(state, indent=2))
        elif args.command == "doctor":
            print(json.dumps({"status": "ok", "schema_version": 4}))
        else:
            raise ValueError(f"{args.command} is not implemented yet")
        return 0
    except FileExistsError as error:
        print(str(error), file=sys.stderr)
        return 5
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(str(error), file=sys.stderr)
        return 3
