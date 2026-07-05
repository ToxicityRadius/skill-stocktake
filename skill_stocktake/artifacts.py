from pathlib import Path


def write_artifact(path: Path, content: str, *, force: bool = False) -> None:
    path = Path(path)
    if path.exists() and not force:
        raise FileExistsError(f"refusing to replace existing artifact: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.tmp")
    temporary.write_text(content, encoding="utf-8")
    temporary.replace(path)
