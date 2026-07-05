[CmdletBinding()]
param(
    [Alias('ResultsPath')][string]$StatePath,
    [string]$ProjectRoot = (Get-Location).Path,
    [string]$CurrentWorkingDirectory = (Get-Location).Path,
    [string]$HomeRoot = $HOME,
    [string]$ConfigPath = (Join-Path $HOME '.codex\config.toml'),
    [string]$PluginInventoryPath,
    [string]$PluginCacheRoot = (Join-Path $HOME '.codex\plugins\cache'),
    [ValidateSet('None', 'Sessions')][string]$UsageMode = 'None',
    [string]$SessionsRoot = (Join-Path $HOME '.codex\sessions'),
    [string[]]$AdditionalSkillRoot = @(),
    [string[]]$ReferenceSearchRoot = @(),
    [switch]$SkipManaged,
    [switch]$SkipReverseReferences
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'SkillStocktake.psm1') -Force
if ([string]::IsNullOrWhiteSpace($StatePath)) { $StatePath = Get-DefaultStatePath -ProjectRoot $ProjectRoot }
if ($SkipManaged) { $PluginCacheRoot = '' }

$inventory = Get-SkillInventory -ProjectRoot $ProjectRoot -CurrentWorkingDirectory $CurrentWorkingDirectory -HomeRoot $HomeRoot -ConfigPath $ConfigPath -PluginInventoryPath $PluginInventoryPath -PluginCacheRoot $PluginCacheRoot -UsageMode $UsageMode -SessionsRoot $SessionsRoot -AdditionalSkillRoot $AdditionalSkillRoot -ReferenceSearchRoot $ReferenceSearchRoot -SkipReverseReferences:$SkipReverseReferences
$contextSha256 = Get-ContextFingerprint -ProjectRoot $ProjectRoot -CurrentWorkingDirectory $CurrentWorkingDirectory -HomeRoot $HomeRoot -ConfigPath $ConfigPath
$state = $null
$stateDiagnostic = $null
if (Test-Path -LiteralPath $StatePath -PathType Leaf) {
    try {
        $state = Get-Content -Raw -LiteralPath $StatePath | ConvertFrom-Json
        if ($state.schema_version -ne 3) {
            $stateDiagnostic = [pscustomobject][ordered]@{ code = 'incompatible_state_schema'; severity = 'warning'; path = $StatePath; message = "State schema '$($state.schema_version)' cannot be reused; run a full audit." }
            $state = $null
        } elseif (([System.IO.Path]::GetFullPath($state.project_root)).TrimEnd('\') -ine ([System.IO.Path]::GetFullPath($inventory.project_root)).TrimEnd('\')) {
            throw 'State project_root does not match the requested project.'
        }
        if ($null -ne $state) {
            $stateValidation = Test-StocktakeState -State $state -AllowIncomplete
            if (-not $stateValidation.IsValid) { throw ('State validation failed: ' + (@($stateValidation.Errors) -join '; ')) }
        }
    } catch {
        if ($null -eq $stateDiagnostic) { throw "Cannot read state '$StatePath': $($_.Exception.Message)" }
    }
}

$diff = Compare-SkillInventory -Inventory $inventory -State $state -ContextSha256 $contextSha256
$suggestedMode = if ($null -eq $state) { 'full' } elseif ($null -ne $state.active_run -and $state.active_run.status -eq 'in_progress') { 'resume' } else { 'quick' }
if ($suggestedMode -eq 'resume') {
    if ($state.active_run.inventory_sha256 -ne $inventory.inventory_sha256 -or $state.active_run.context_sha256 -ne $contextSha256) {
        throw 'Inventory or context changed during the active run. Start a new full audit instead of resuming stale work.'
    }
    $diff.pending_ids = @($state.active_run.pending_ids)
}

[pscustomobject][ordered]@{
    schema_version = 3
    state_path = [System.IO.Path]::GetFullPath($StatePath)
    suggested_mode = $suggestedMode
    active_run_id = if ($suggestedMode -eq 'resume') { $state.active_run.run_id } else { $null }
    context_sha256 = $contextSha256
    state_diagnostic = $stateDiagnostic
    diff = $diff
    inventory = $inventory
} | ConvertTo-Json -Depth 45
