from pathlib import Path


def contained_file(root: Path, candidate: Path) -> bool:
    try:
        root = Path(root).resolve(strict=True)
        resolved = Path(candidate).resolve(strict=True)
        resolved.relative_to(root)
        return resolved.is_file()
    except (OSError, ValueError):
        return False
