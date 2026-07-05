[CmdletBinding()]
param([Parameter(Mandatory)][string]$WorklistPath, [string]$OutputPath, [ValidateSet('full','quick','resume')][string]$Mode = 'full', [switch]$Force)
$ErrorActionPreference = 'Stop'
$python = (Get-Command python -ErrorAction Stop).Source
$argsList = @('-m', 'skill_stocktake', 'new-run', '--worklist', $WorklistPath, '--mode', $Mode)
if ($OutputPath) { $argsList += @('--output', $OutputPath) }
if ($Force) { $argsList += '--force' }
Push-Location (Split-Path -Parent $PSScriptRoot)
try { & $python @argsList; if ($LASTEXITCODE) { exit $LASTEXITCODE } } finally { Pop-Location }
