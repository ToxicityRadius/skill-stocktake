[CmdletBinding()]
param(
    [string]$ProjectRoot = (Get-Location).Path,
    [string]$HomeRoot = $HOME,
    [string]$CurrentWorkingDirectory = (Get-Location).Path,
    [string]$ConfigPath,
    [string]$PluginInventoryPath,
    [string]$PluginCacheRoot,
    [ValidateSet('None', 'Sessions')][string]$UsageMode = 'None',
    [string]$SessionsRoot,
    [string[]]$AdditionalSkillRoot = @(),
    [string[]]$ReferenceSearchRoot = @(),
    [switch]$SkipUsage,
    [switch]$SkipManaged,
    [switch]$SkipReverseReferences,
    [switch]$Force
)
$ErrorActionPreference = 'Stop'
$python = (Get-Command python -ErrorAction Stop).Source
$argsList = @('-m', 'skill_stocktake', 'scan', '--project-root', $ProjectRoot, '--home-root', $HomeRoot, '--no-artifact')
if ($ConfigPath) { $argsList += @('--config', $ConfigPath) }
if ($PluginInventoryPath) { $argsList += @('--plugin-inventory', $PluginInventoryPath) }
if ($PluginCacheRoot) { $argsList += @('--plugin-cache-root', $PluginCacheRoot) }
if ($SessionsRoot) { $argsList += @('--sessions-root', $SessionsRoot) }
foreach ($root in $AdditionalSkillRoot) { $argsList += @('--additional-skill-root', $root) }
foreach ($root in $ReferenceSearchRoot) { $argsList += @('--reference-search-root', $root) }
if ($UsageMode -eq 'Sessions' -and -not $SkipUsage) { $argsList += '--include-usage' }
if ($SkipManaged) { $argsList += '--skip-managed' }
if ($Force) { $argsList += '--force' }
Push-Location (Split-Path -Parent $PSScriptRoot)
try { & $python @argsList; if ($LASTEXITCODE) { exit $LASTEXITCODE } } finally { Pop-Location }
