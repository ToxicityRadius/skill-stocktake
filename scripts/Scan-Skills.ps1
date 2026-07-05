[CmdletBinding()]
param(
    [string]$ProjectRoot = (Get-Location).Path,
    [string]$CurrentWorkingDirectory = (Get-Location).Path,
    [string]$HomeRoot = $HOME,
    [string]$ConfigPath = (Join-Path $HOME '.codex\config.toml'),
    [string]$PluginInventoryPath,
    [string]$PluginCacheRoot = (Join-Path $HOME '.codex\plugins\cache'),
    [ValidateSet('None', 'Sessions')][string]$UsageMode = 'Sessions',
    [string]$SessionsRoot = (Join-Path $HOME '.codex\sessions'),
    [string[]]$AdditionalSkillRoot = @(),
    [string[]]$ReferenceSearchRoot = @(),
    [switch]$SkipUsage,
    [switch]$SkipManaged,
    [switch]$SkipReverseReferences
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'SkillStocktake.psm1') -Force
if ($SkipUsage) { $UsageMode = 'None' }
if ($SkipManaged) { $PluginCacheRoot = '' }

$inventory = Get-SkillInventory -ProjectRoot $ProjectRoot -CurrentWorkingDirectory $CurrentWorkingDirectory -HomeRoot $HomeRoot -ConfigPath $ConfigPath -PluginInventoryPath $PluginInventoryPath -PluginCacheRoot $PluginCacheRoot -UsageMode $UsageMode -SessionsRoot $SessionsRoot -AdditionalSkillRoot $AdditionalSkillRoot -ReferenceSearchRoot $ReferenceSearchRoot -SkipReverseReferences:$SkipReverseReferences
$inventory | ConvertTo-Json -Depth 40
