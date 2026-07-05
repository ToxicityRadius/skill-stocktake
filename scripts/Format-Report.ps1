[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$StatePath,
    [string]$InventoryPath,
    [string]$WorklistPath,
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'SkillStocktake.psm1') -Force
$state = Get-Content -Raw -LiteralPath $StatePath | ConvertFrom-Json
if (-not [string]::IsNullOrWhiteSpace($WorklistPath)) {
    $work = Get-Content -Raw -LiteralPath $WorklistPath | ConvertFrom-Json
    $inventory = $work.inventory
} elseif (-not [string]::IsNullOrWhiteSpace($InventoryPath)) {
    $inventory = Get-Content -Raw -LiteralPath $InventoryPath | ConvertFrom-Json
} else {
    throw 'Provide -WorklistPath or -InventoryPath.'
}
$validation = Test-StocktakeState -State $state -AllowIncomplete
if (-not $validation.IsValid) { throw ('State validation failed: ' + (@($validation.Errors) -join '; ')) }
$report = Format-StocktakeReport -State $state -Inventory $inventory
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $parent = Split-Path -Parent ([System.IO.Path]::GetFullPath($OutputPath))
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    [System.IO.File]::WriteAllText([System.IO.Path]::GetFullPath($OutputPath), $report, [System.Text.UTF8Encoding]::new($false))
}
$report
