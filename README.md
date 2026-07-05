# Skill Stocktake for Codex

Audit an entire Codex skill setup without changing it. Skill Stocktake v4 inventories user, project, system, and active managed/plugin skills; evaluates quality and static security risk; tracks changes; and produces a resumable, evidence-backed report on Windows, macOS, and Linux.

## Highlights

- Discovers skills from `.codex/skills`, `.agents/skills`, project roots, and active plugin bundles.
- Groups exact compatibility mirrors and reports genuine same-name collisions.
- Fingerprints complete skill bundles and applicable instruction/config context.
- Supports full, quick, and resumable audits with schema-validated state.
- Records confidence, evidence, reviewed resources, dependencies, freshness, and proposals.
- Reads session history only with explicit `--include-usage` consent and never retains session content or command arguments.
- Excludes symlinks outside discovered roots unless explicitly allowed.
- Redacts local roots in shareable reports and refuses accidental artifact replacement.
- Locks and atomically saves state so interrupted audits can recover safely.
- Treats managed, system, and admin skills as read-only.

## Requirements

- Codex CLI or Codex app
- Python 3.10+
- PowerShell is optional and required only for deprecated v3-compatible wrappers on Windows.
- Python only for Codex's optional official skill validator

The v4 engine uses only the Python standard library. No package download is required after installing the skill.

## Install

Ask Codex:

```text
$skill-installer install https://github.com/ToxicityRadius/skill-stocktake
```

If installing manually:

```powershell
git clone https://github.com/ToxicityRadius/skill-stocktake.git "$env:TEMP\skill-stocktake"
$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }
$destination = Join-Path $codexHome 'skills\skill-stocktake'
New-Item -ItemType Directory -Force -Path $destination | Out-Null
Copy-Item "$env:TEMP\skill-stocktake\*" -Destination $destination -Recurse -Force
```

Restart Codex after installation so the skill is discovered.

## Use

Invoke the skill explicitly:

```text
$skill-stocktake audit my current setup
```

The workflow creates scoped artifacts under `.skill-stocktake/`, evaluates skills using [`references/evaluation-rubric.md`](references/evaluation-rubric.md), validates state, and formats a redacted report. It never applies merge, retirement, rewrite, or deletion proposals without explicit approval.

Session-history aggregation is disabled by default. Supply `--include-usage` only after the user approves reading recent local Codex sessions.

Direct CLI examples:

```bash
python -m skill_stocktake scan --project-root .
python -m skill_stocktake scan --project-root . --include-usage --force
python -m skill_stocktake doctor
```

## Run tests

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-Tests.ps1
```

```bash
python -m unittest discover -s tests_py -p "test_*.py" -v
```

The suite covers discovery, plugin selection, mirrors, collisions, metadata parsing, bundle/context changes, usage privacy, reverse references, state validation, resumability, locking, and atomic persistence.

## Safety and privacy

- Audits are read-only until a user separately approves a proposed mutation.
- Managed/plugin, system, and admin skills remain read-only.
- Usage results contain aggregate counts only—not prompts, session text, command arguments, secrets, or credentials.
- Merge and retirement proposals require dependency and replacement evidence.
- Static security findings are advisory; a lifecycle verdict of `Keep` is not malware certification.
- Audited code is read as bounded text and is never executed or imported.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Security issues should follow [SECURITY.md](SECURITY.md).

## License

MIT
