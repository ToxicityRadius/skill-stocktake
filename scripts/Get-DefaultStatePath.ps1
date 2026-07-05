[CmdletBinding()]
param(
    [string]$ProjectRoot = (Get-Location).Path,
    [string]$StateRoot = (Join-Path $HOME '.codex\state\skill-stocktake')
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'SkillStocktake.psm1') -Force
Get-DefaultStatePath -ProjectRoot $ProjectRoot -StateRoot $StateRoot

