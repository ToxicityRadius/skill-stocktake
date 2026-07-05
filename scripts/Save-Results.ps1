[CmdletBinding()]
param([Parameter(Mandatory)][Alias('ResultsPath')][string]$StatePath, [Parameter(Mandatory)][string]$EvaluationPath, [int]$LockTimeoutSeconds = 30)
$ErrorActionPreference = 'Stop'
$python = (Get-Command python -ErrorAction Stop).Source
$argsList = @('-m', 'skill_stocktake', 'save', '--state', $StatePath, '--evaluation', $EvaluationPath, '--lock-timeout', [string]$LockTimeoutSeconds)
Push-Location (Split-Path -Parent $PSScriptRoot)
try { & $python @argsList; if ($LASTEXITCODE) { exit $LASTEXITCODE } } finally { Pop-Location }
