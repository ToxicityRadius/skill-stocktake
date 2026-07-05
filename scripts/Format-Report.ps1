[CmdletBinding()]
param([Parameter(Mandatory)][string]$StatePath, [string]$InventoryPath, [string]$WorklistPath, [string]$OutputPath, [switch]$Force)
$ErrorActionPreference = 'Stop'
$python = (Get-Command python -ErrorAction Stop).Source
$inventory = if ($InventoryPath) { $InventoryPath } elseif ($WorklistPath) { $WorklistPath } else { $null }
$argsList = @('-m', 'skill_stocktake', 'report', '--state', $StatePath)
if ($inventory) { $argsList += @('--inventory', $inventory) }
if ($OutputPath) { $argsList += @('--output', $OutputPath) }
if ($Force) { $argsList += '--force' }
Push-Location (Split-Path -Parent $PSScriptRoot)
try { & $python @argsList; if ($LASTEXITCODE) { exit $LASTEXITCODE } } finally { Pop-Location }
