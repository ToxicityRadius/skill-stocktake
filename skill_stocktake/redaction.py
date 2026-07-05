from pathlib import Path


class PathRedactor:
    def __init__(self, *, home: str, project: str, codex_home: str, plugin_cache: str | None = None):
        candidates = [
            (project, "$PROJECT"),
            (codex_home, "$CODEX_HOME"),
            (plugin_cache, "$PLUGIN_CACHE"),
            (home, "$HOME"),
        ]
        self._roots = sorted(
            ((str(Path(value)), replacement) for value, replacement in candidates if value),
            key=lambda item: len(item[0]),
            reverse=True,
        )

    def redact(self, value: str) -> str:
        normalized = str(value).replace("\\", "/")
        for root, replacement in self._roots:
            candidate = root.replace("\\", "/").rstrip("/")
            if normalized == candidate or normalized.startswith(candidate + "/"):
                return replacement + normalized[len(candidate):]
        return normalized
