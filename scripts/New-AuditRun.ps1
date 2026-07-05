[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$WorklistPath,
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'SkillStocktake.psm1') -Force
$work = Get-Content -Raw -LiteralPath $WorklistPath | ConvertFrom-Json
$run = New-StocktakeRun -Work $work
$json = $run | ConvertTo-Json -Depth 45
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $parent = Split-Path -Parent ([System.IO.Path]::GetFullPath($OutputPath))
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    [System.IO.File]::WriteAllText([System.IO.Path]::GetFullPath($OutputPath), $json, [System.Text.UTF8Encoding]::new($false))
}
$json
