# Skill Stocktake for Codex

Audit an entire Codex skill setup without changing it. Skill Stocktake inventories user, project, system, and active managed/plugin skills; evaluates their quality; tracks changes; and produces a resumable, evidence-backed report.

## Highlights

- Discovers skills from `.codex/skills`, `.agents/skills`, project roots, and active plugin bundles.
- Groups exact compatibility mirrors and reports genuine same-name collisions.
- Fingerprints complete skill bundles and applicable instruction/config context.
- Supports full, quick, and resumable audits with schema-validated state.
- Records confidence, evidence, reviewed resources, dependencies, freshness, and proposals.
- Optionally aggregates recent usage without retaining session content or command arguments.
- Locks and atomically saves state so interrupted audits can recover safely.
- Treats managed, system, and admin skills as read-only.

## Requirements

- Codex CLI or Codex app
- Windows PowerShell 5.1 or PowerShell 7+
- Python only for Codex's optional official skill validator

This implementation is Windows-first because its deterministic helpers are PowerShell scripts.

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

The workflow creates a worklist and resumable run file in the current directory, evaluates skills using [`references/evaluation-rubric.md`](references/evaluation-rubric.md), validates the completed state, and formats a report. It never applies merge, retirement, rewrite, or deletion proposals without explicit approval.

Session-history aggregation is enabled by the documented default workflow. Use `-UsageMode None` with `Get-SkillDiff.ps1` when session analysis is unnecessary or not approved.

## Run tests

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-Tests.ps1
```

The suite covers discovery, plugin selection, mirrors, collisions, metadata parsing, bundle/context changes, usage privacy, reverse references, state validation, resumability, locking, and atomic persistence.

## Safety and privacy

- Audits are read-only until a user separately approves a proposed mutation.
- Managed/plugin, system, and admin skills remain read-only.
- Usage results contain aggregate counts only—not prompts, session text, command arguments, secrets, or credentials.
- Merge and retirement proposals require dependency and replacement evidence.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Security issues should follow [SECURITY.md](SECURITY.md).

## License

MIT
