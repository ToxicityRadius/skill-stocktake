---
name: skill-stocktake
description: Use when auditing, inventorying, comparing, consolidating, updating, retiring, or checking changes across user, repository, admin, system, or managed Codex skills, especially when activation, overlap, freshness, usage, dependencies, or resumable cached reviews matter.
---

# Skill Stocktake

Audit skills without changing them. Require explicit approval before rewriting, merging, archiving, or removing an audited skill. Treat admin, system, and managed/plugin skills as read-only.

## Prepare

Resolve the installation and project context. `ProjectRoot` is the repository root; `CurrentWorkingDirectory` determines nested skill and instruction scope.

```powershell
$CodexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }
$SkillRoot = Join-Path $CodexHome 'skills\skill-stocktake'
$GitRoot = & git rev-parse --show-toplevel 2>$null
$ProjectRoot = if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($GitRoot)) { $GitRoot } else { (Get-Location).Path }
$CurrentWorkingDirectory = (Get-Location).Path
$StatePath = powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $SkillRoot 'scripts\Get-DefaultStatePath.ps1') -ProjectRoot $ProjectRoot
```

Always read `references/evaluation-rubric.md` before assigning verdicts or constructing records.

## Build the worklist

```powershell
$WorkPath = Join-Path (Get-Location) 'skill-stocktake-work.json'
$RunPath = Join-Path (Get-Location) 'skill-stocktake-run.json'
$WorkJson = powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $SkillRoot 'scripts\Get-SkillDiff.ps1') `
  -StatePath $StatePath -ProjectRoot $ProjectRoot -CurrentWorkingDirectory $CurrentWorkingDirectory -UsageMode Sessions
[System.IO.File]::WriteAllText($WorkPath, ($WorkJson -join [Environment]::NewLine))
powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $SkillRoot 'scripts\New-AuditRun.ps1') -WorklistPath $WorkPath -OutputPath $RunPath | Out-Null
```

Pass `-UsageMode None` when session-history analysis is unnecessary or not approved. Pass `-AdditionalSkillRoot` only for roots confirmed by the current runtime but unavailable through normal discovery.

The inventory distinguishes confirmed, inferred, disabled, and excluded activation. Never call coverage complete when diagnostics report unreadable roots or inferred managed activation.

Follow `suggested_mode`:

- `full`: evaluate every logical skill.
- `quick`: evaluate only `diff.pending_ids` and carry valid unchanged records forward.
- `resume`: continue the exact active run. If inventory or context changed, start a new full run and use `Save-Results.ps1 -ReplaceActiveRun` for its first save.

## Evaluate

Inspect each selected skill's complete `SKILL.md` and only the resources needed to validate its claims. Apply every rubric dimension and map evidence to each `concern`, `fail`, or `unknown` dimension.

Verify changing platform claims with primary sources. Check applicable instruction precedence, activation state, metadata, tool dependencies, and reverse references. Treat usage as supporting evidence only; zero or unavailable usage never independently justifies removal.

Evaluate in batches of about 20. Update the run JSON with complete pending/evaluated lists after each batch. Use multiple agents only when the user explicitly requests them; the parent remains the sole state writer.

## Save safely

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $SkillRoot 'scripts\Save-Results.ps1') -StatePath $StatePath -EvaluationPath $RunPath
```

Schema version 3 validates identity, progress, verdicts, confidence, mapped evidence, proposal fields, freshness, and merge/retirement safeguards. Saving is locked and atomic. Never bypass validation.

## Report

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $SkillRoot 'scripts\Format-Report.ps1') -StatePath $StatePath -WorklistPath $WorkPath
```

Report coverage and diagnostics first, then summary counts, actionable or low-confidence results, the complete table, proposals, and uncertainty. Separate confirmed runtime facts from cache inference. Do not apply proposals during the audit.
