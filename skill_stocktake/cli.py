import argparse


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="skill-stocktake")
    subcommands = parser.add_subparsers(dest="command", required=True)
    for command in ("scan", "diff"):
        item = subcommands.add_parser(command)
        item.add_argument("--project-root", default=".")
        item.add_argument("--include-usage", action="store_true")
        item.add_argument("--allow-symlink-root", action="append", default=[])
        item.add_argument("--artifact-dir", default=".skill-stocktake")
        item.add_argument("--force", action="store_true")
    for command in ("new-run", "save", "report", "migrate", "doctor"):
        subcommands.add_parser(command)
    return parser
