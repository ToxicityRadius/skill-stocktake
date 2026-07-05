[CmdletBinding()]
param(
    [Parameter(Mandatory)][Alias('ResultsPath')][string]$StatePath,
    [string]$EvaluationPath,
    [Parameter(ValueFromPipeline)][string]$EvaluationJson,
    [switch]$ReplaceIncompatibleState,
    [switch]$ReplaceActiveRun,
    [int]$LockTimeoutSeconds = 30
)

begin {
    $ErrorActionPreference = 'Stop'
    $parts = [System.Collections.Generic.List[string]]::new()
}
process {
    if ($null -ne $EvaluationJson) { $parts.Add($EvaluationJson) }
}
end {
    Import-Module (Join-Path $PSScriptRoot 'SkillStocktake.psm1') -Force
    $raw = if (-not [string]::IsNullOrWhiteSpace($EvaluationPath)) { Get-Content -Raw -LiteralPath $EvaluationPath } else { $parts -join [Environment]::NewLine }
    if ([string]::IsNullOrWhiteSpace($raw)) { throw 'Provide evaluation JSON with -EvaluationPath or on the pipeline.' }
    try { $incoming = $raw | ConvertFrom-Json } catch { throw "Invalid evaluation JSON: $($_.Exception.Message)" }

    $fullStatePath = [System.IO.Path]::GetFullPath($StatePath)
    $mutexName = 'Local\CodexSkillStocktake-' + (Get-StableHash -Text $fullStatePath).Substring(0, 24)
    $mutex = [System.Threading.Mutex]::new($false, $mutexName)
    $acquired = $false
    try {
        try { $acquired = $mutex.WaitOne([TimeSpan]::FromSeconds($LockTimeoutSeconds)) } catch [System.Threading.AbandonedMutexException] { $acquired = $true }
        if (-not $acquired) { throw "Timed out waiting for state lock: $fullStatePath" }

        $existing = $null
        if (Test-Path -LiteralPath $fullStatePath -PathType Leaf) {
            try { $existing = Get-Content -Raw -LiteralPath $fullStatePath | ConvertFrom-Json } catch { throw "Existing state is invalid JSON and was preserved: $($_.Exception.Message)" }
            if ($existing.schema_version -ne 3) {
                if (-not $ReplaceIncompatibleState) { throw "Existing state schema '$($existing.schema_version)' is incompatible. Re-run with -ReplaceIncompatibleState after starting a full audit." }
                if ($incoming.active_run.mode -ne 'full') { throw 'Only a full audit may replace incompatible state.' }
                $existing = $null
            }
            if ($null -ne $existing -and $null -ne $existing.active_run -and $null -ne $incoming.active_run -and $existing.active_run.run_id -ne $incoming.active_run.run_id) {
                if (-not $ReplaceActiveRun) { throw 'Another audit run is active. Resume its run_id or use -ReplaceActiveRun with a new full audit.' }
                if ($incoming.active_run.mode -ne 'full') { throw 'Only a new full audit may replace an active run.' }
                $existing.active_run = $null
            }
        }

        $merged = Merge-StocktakeState -ExistingState $existing -IncomingState $incoming
        $validation = Test-StocktakeState -State $merged -AllowIncomplete
        if (-not $validation.IsValid) { throw ('Merged state is invalid: ' + (@($validation.Errors) -join '; ')) }

        $parent = Split-Path -Parent $fullStatePath
        if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        $temp = Join-Path $parent ((Split-Path -Leaf $fullStatePath) + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
        $backup = Join-Path $parent ((Split-Path -Leaf $fullStatePath) + '.' + [guid]::NewGuid().ToString('N') + '.bak')
        try {
            $json = $merged | ConvertTo-Json -Depth 45
            [System.IO.File]::WriteAllText($temp, $json, [System.Text.UTF8Encoding]::new($false))
            if (Test-Path -LiteralPath $fullStatePath -PathType Leaf) {
                [System.IO.File]::Replace($temp, $fullStatePath, $backup, $true)
                if (Test-Path -LiteralPath $backup -PathType Leaf) { [System.IO.File]::Delete($backup) }
            } else {
                [System.IO.File]::Move($temp, $fullStatePath)
            }
        } finally {
            if (Test-Path -LiteralPath $temp -PathType Leaf) { [System.IO.File]::Delete($temp) }
        }
        Get-Content -Raw -LiteralPath $fullStatePath
    } finally {
        if ($acquired) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}
