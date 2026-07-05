[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\SkillStocktake.psm1'
if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
    throw "Required module does not exist: $modulePath"
}
Import-Module -Name $modulePath -Force

$script:Passed = 0
$script:Failed = 0

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Equal {
    param($Expected, $Actual, [string]$Message)
    if ($Expected -ne $Actual) { throw "$Message Expected=[$Expected] Actual=[$Actual]" }
}

function Assert-Contains {
    param([object[]]$Collection, $Expected, [string]$Message)
    if ($Collection -notcontains $Expected) { throw "$Message Missing=[$Expected]" }
}

function It {
    param([string]$Name, [scriptblock]$Test)
    try {
        & $Test
        $script:Passed++
        Write-Host "PASS $Name"
    } catch {
        $script:Failed++
        Write-Host "FAIL $Name :: $($_.Exception.Message)" -ForegroundColor Red
    }
}

$fixtureRoot = Join-Path $PSScriptRoot 'fixtures'
$homeRoot = Join-Path $fixtureRoot 'home'
$projectRoot = Join-Path $fixtureRoot 'project'
$pluginRoot = Join-Path $fixtureRoot 'plugins'
$testTempRoot = Join-Path $PSScriptRoot '.tmp'
if (-not (Test-Path -LiteralPath $testTempRoot -PathType Container)) { New-Item -ItemType Directory -Path $testTempRoot -Force | Out-Null }

It 'parses folded and literal YAML descriptions' {
    $folded = Get-Content -Raw -LiteralPath (Join-Path $fixtureRoot 'metadata\folded.md')
    $literal = Get-Content -Raw -LiteralPath (Join-Path $fixtureRoot 'metadata\literal.md')
    $foldedResult = ConvertFrom-SkillFrontmatter -Content $folded -Path 'folded.md'
    $literalResult = ConvertFrom-SkillFrontmatter -Content $literal -Path 'literal.md'
    Assert-True $foldedResult.IsValid 'Folded frontmatter should be valid.'
    Assert-Equal 'First line second line' $foldedResult.Description 'Folded description should join lines.'
    Assert-Equal "First line`nSecond line" $literalResult.Description 'Literal description should preserve newlines.'
}

It 'diagnoses malformed metadata without a folder-name fallback' {
    $content = Get-Content -Raw -LiteralPath (Join-Path $fixtureRoot 'metadata\missing-name.md')
    $result = ConvertFrom-SkillFrontmatter -Content $content -Path 'fallback-folder\SKILL.md'
    Assert-True (-not $result.IsValid) 'Missing name should be invalid.'
    Assert-True ([string]::IsNullOrWhiteSpace([string]$result.Name)) 'Name must not fall back to the directory.'
    Assert-Contains @($result.Diagnostics.code) 'missing_name' 'Missing name diagnostic is required.'
}

It 'accepts nested metadata fields while validating required fields' {
    $content = Get-Content -Raw -LiteralPath (Join-Path $fixtureRoot 'metadata\nested.md')
    $result = ConvertFrom-SkillFrontmatter -Content $content -Path 'nested.md'
    Assert-True $result.IsValid ('Nested metadata should not invalidate required fields: ' + (@($result.Diagnostics.message) -join '; '))
    Assert-Equal 'nested-skill' $result.Name 'Required name should still parse.'
}

It 'changes the bundle fingerprint when only a resource changes' {
    $a = Join-Path $fixtureRoot 'bundles\a'
    $b = Join-Path $fixtureRoot 'bundles\b'
    $skillA = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $a 'SKILL.md')).Hash
    $skillB = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $b 'SKILL.md')).Hash
    Assert-Equal $skillA $skillB 'Fixture SKILL.md files should be identical.'
    Assert-True ((Get-BundleFingerprint -SkillDirectory $a) -ne (Get-BundleFingerprint -SkillDirectory $b)) 'Resource-only change must alter bundle hash.'
}

It 'keeps logical identity stable when only bundle content changes' {
    $common = @{
        ProjectRoot = $projectRoot
        CurrentWorkingDirectory = $projectRoot
        HomeRoot = (Join-Path $fixtureRoot 'empty-home')
        PluginCacheRoot = (Join-Path $fixtureRoot 'empty-plugins')
        UsageMode = 'None'
        SkipReverseReferences = $true
    }
    $first = Get-SkillInventory @common -AdditionalSkillRoot (Join-Path $fixtureRoot 'bundles\a')
    $second = Get-SkillInventory @common -AdditionalSkillRoot (Join-Path $fixtureRoot 'bundles\b')
    $a = @($first.skills | Where-Object logical_name -eq 'bundle-skill')[0]
    $b = @($second.skills | Where-Object logical_name -eq 'bundle-skill')[0]
    Assert-True ($a.bundle_sha256 -ne $b.bundle_sha256) 'Fixture bundles must differ.'
    Assert-Equal $a.logical_id $b.logical_id 'Bundle changes must not replace logical identity.'
}

It 'discovers nested repository skills from repository root to current directory' {
    $cwd = Join-Path $projectRoot 'nested\leaf'
    $inventory = Get-SkillInventory -ProjectRoot $projectRoot -CurrentWorkingDirectory $cwd -HomeRoot (Join-Path $fixtureRoot 'empty-home') -PluginCacheRoot (Join-Path $fixtureRoot 'empty-plugins') -UsageMode None -SkipReverseReferences
    Assert-Equal 1 @($inventory.skills | Where-Object logical_name -eq 'nested-repo-skill').Count 'Nested .agents skill should be active for the current directory.'
}

It 'follows a symlinked skill directory' {
    $linkRoot = Join-Path $testTempRoot ('stocktake-link-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $linkRoot -Force | Out-Null
    $linkPath = Join-Path $linkRoot 'linked-bundle'
    try {
        New-Item -ItemType Junction -Path $linkPath -Target (Join-Path $fixtureRoot 'bundles\a') -Force | Out-Null
        $inventory = Get-SkillInventory -ProjectRoot $projectRoot -CurrentWorkingDirectory $projectRoot -HomeRoot (Join-Path $fixtureRoot 'empty-home') -PluginCacheRoot (Join-Path $fixtureRoot 'empty-plugins') -AdditionalSkillRoot $linkRoot -UsageMode None -SkipReverseReferences
        Assert-Equal 1 @($inventory.skills | Where-Object logical_name -eq 'bundle-skill').Count 'Symlinked skill should be inventoried.'
    } finally {
        if (Test-Path -LiteralPath $linkPath) { [System.IO.Directory]::Delete($linkPath) }
        if (Test-Path -LiteralPath $linkRoot) { [System.IO.Directory]::Delete($linkRoot, $true) }
    }
}

It 'excludes explicitly disabled plugins from active inventory' {
    $inventory = Get-SkillInventory -ProjectRoot $projectRoot -CurrentWorkingDirectory $projectRoot -HomeRoot $homeRoot -PluginCacheRoot $pluginRoot -ConfigPath (Join-Path $fixtureRoot 'config\disabled-plugin.toml') -UsageMode None -SkipReverseReferences
    Assert-Equal 0 @($inventory.skills | Where-Object logical_name -eq 'managed-current').Count 'Disabled plugin must not be inventoried as active.'
    Assert-Contains @($inventory.diagnostics.code) 'plugin_disabled' 'Disabled plugin should be reported explicitly.'
}

It 'honors per-skill enabled and disabled configuration exactly' {
    $configPath = Join-Path $testTempRoot ('skill-config-' + [guid]::NewGuid().ToString('N') + '.toml')
    $targetPath = Join-Path $homeRoot '.codex\skills\collision-a\SKILL.md'
    try {
        $enabledConfig = "[[skills.config]]`r`npath = `"$targetPath`"`r`nenabled = true`r`n"
        [System.IO.File]::WriteAllText($configPath, $enabledConfig, [System.Text.UTF8Encoding]::new($false))
        $enabled = Get-SkillInventory -ProjectRoot $projectRoot -CurrentWorkingDirectory $projectRoot -HomeRoot $homeRoot -ConfigPath $configPath -PluginCacheRoot (Join-Path $fixtureRoot 'empty-plugins') -UsageMode None -SkipReverseReferences
        Assert-Equal 2 @($enabled.skills | Where-Object logical_name -eq 'collision-skill').Count 'An explicitly enabled skill must remain active.'
        $disabledConfig = $enabledConfig.Replace('enabled = true', 'enabled = false')
        [System.IO.File]::WriteAllText($configPath, $disabledConfig, [System.Text.UTF8Encoding]::new($false))
        $disabled = Get-SkillInventory -ProjectRoot $projectRoot -CurrentWorkingDirectory $projectRoot -HomeRoot $homeRoot -ConfigPath $configPath -PluginCacheRoot (Join-Path $fixtureRoot 'empty-plugins') -UsageMode None -SkipReverseReferences
        Assert-Equal 1 @($disabled.skills | Where-Object logical_name -eq 'collision-skill').Count 'An explicitly disabled skill must be excluded.'
    } finally {
        if (Test-Path -LiteralPath $configPath) { [System.IO.File]::Delete($configPath) }
    }
}

It 'uses machine-readable plugin inventory to confirm activation' {
    $inventory = Get-SkillInventory -ProjectRoot $projectRoot -CurrentWorkingDirectory $projectRoot -HomeRoot $homeRoot -PluginCacheRoot $pluginRoot -PluginInventoryPath (Join-Path $fixtureRoot 'plugins\inventory.json') -UsageMode None -SkipReverseReferences
    $managed = @($inventory.skills | Where-Object logical_name -eq 'managed-current')[0]
    Assert-Equal 'runtime-confirmed' $managed.selection 'Runtime plugin state should supersede cache inference.'
}

It 'uses override and fallback instruction discovery in root-to-cwd order' {
    $cwd = Join-Path $projectRoot 'nested\leaf'
    $paths = @(Get-ApplicableInstructionPath -ProjectRoot $projectRoot -CurrentWorkingDirectory $cwd -HomeRoot $homeRoot -ConfigPath (Join-Path $fixtureRoot 'config\instructions.toml'))
    Assert-True ($paths[0].EndsWith('.codex\AGENTS.override.md')) 'Global override should replace global AGENTS.md.'
    Assert-True ($paths[1].EndsWith('project\AGENTS.md')) 'Repository instruction should follow global guidance.'
    Assert-True ($paths[2].EndsWith('nested\AGENTS.override.md')) 'Nested override should follow repository guidance.'
    Assert-True ($paths[3].EndsWith('leaf\TEAM_GUIDE.md')) 'Configured fallback should apply at the current directory.'
}

It 'groups compatibility mirrors and keeps content collisions separate' {
    $inventory = Get-SkillInventory -ProjectRoot $projectRoot -HomeRoot $homeRoot -PluginCacheRoot $pluginRoot -UsageMode None
    $shared = @($inventory.skills | Where-Object logical_name -eq 'shared-skill')
    Assert-Equal 1 $shared.Count 'Identical compatibility mirrors should produce one logical skill.'
    Assert-Equal 2 @($shared[0].locations).Count 'Mirror record should retain both paths.'
    $expectedMirrorId = 's-' + (Get-StableHash -Text 'mirror|global|shared-skill/skill.md|shared-skill').Substring(0, 20)
    Assert-Equal $expectedMirrorId $shared[0].logical_id 'Mirror identity must be independent of later inventory iteration state.'
    $collisions = @($inventory.skills | Where-Object logical_name -eq 'collision-skill')
    Assert-Equal 2 $collisions.Count 'Different content with the same name should remain separate.'
    Assert-Contains @($inventory.diagnostics.code) 'name_collision' 'Collision diagnostic is required.'
    Assert-Equal 1 @($inventory.skills | Where-Object logical_name -eq 'container-skill').Count 'Top-level fixture skill should be included.'
    Assert-Equal 0 @($inventory.skills | Where-Object logical_name -eq 'nested-fake-skill').Count 'Nested test fixtures must not be inventoried as skills.'
    Assert-Contains @($inventory.diagnostics.code) 'invalid_openai_metadata' 'Invalid app metadata should be diagnosed.'
}

It 'discovers current managed skills and excludes plugin backups' {
    $inventory = Get-SkillInventory -ProjectRoot $projectRoot -HomeRoot $homeRoot -PluginCacheRoot $pluginRoot -UsageMode None
    Assert-Equal 1 @($inventory.skills | Where-Object logical_name -eq 'managed-current').Count 'Current managed skill should be included.'
    Assert-Equal 0 @($inventory.skills | Where-Object logical_name -eq 'managed-old').Count 'Superseded managed version should be excluded.'
    Assert-Equal 0 @($inventory.skills | Where-Object logical_name -eq 'managed-backup').Count 'Plugin backup should be excluded.'
    Assert-Equal 0 @($inventory.skills | Where-Object logical_name -eq 'managed-install-temp').Count 'Plugin installation staging should be excluded.'
    Assert-Equal 0 @($inventory.skills | Where-Object logical_name -eq 'managed-local-duplicate').Count 'Installed remote plugin should supersede its curated cache duplicate.'
    Assert-Equal 1 @($inventory.skills | Where-Object logical_name -eq 'managed-remote-active').Count 'Installed remote plugin should be selected.'
}

It 'counts reads separately from unique sessions and retains no session content' {
    $inventory = Get-SkillInventory -ProjectRoot $projectRoot -HomeRoot $homeRoot -PluginCacheRoot $pluginRoot -UsageMode None
    $target = @($inventory.skills | Where-Object logical_name -eq 'shared-skill')[0]
    $sessionRoot = Join-Path $testTempRoot ('stocktake-session-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $sessionRoot -Force | Out-Null
    try {
        $sessionPath = Join-Path $sessionRoot 'session.jsonl'
        $argumentText = '{"command":"Get-Content -Raw -LiteralPath ''' + $target.path.Replace('\', '\\') + '''","secret":"must-not-survive"}'
        $lines = @(
            ([ordered]@{ timestamp = [DateTime]::UtcNow.ToString('o'); type = 'response_item'; payload = [ordered]@{ type = 'function_call'; arguments = $argumentText } } | ConvertTo-Json -Compress -Depth 8),
            ([ordered]@{ timestamp = [DateTime]::UtcNow.ToString('o'); type = 'response_item'; payload = [ordered]@{ type = 'function_call'; arguments = $argumentText } } | ConvertTo-Json -Compress -Depth 8)
        )
        [System.IO.File]::WriteAllLines($sessionPath, $lines, [System.Text.UTF8Encoding]::new($false))
        $withUsage = Add-SkillUsage -Inventory $inventory -SessionsRoot $sessionRoot
        $used = @($withUsage.skills | Where-Object logical_name -eq 'shared-skill')[0]
        Assert-Equal 2 $used.usage.tool_reads_7d 'Two reads should be recorded.'
        Assert-Equal 1 $used.usage.unique_sessions_7d 'One unique session should be recorded.'
        Assert-True (($withUsage | ConvertTo-Json -Depth 20) -notmatch 'must-not-survive') 'Raw session arguments must not be retained.'
    } finally {
        if (Test-Path -LiteralPath $sessionRoot) { [System.IO.Directory]::Delete($sessionRoot, $true) }
    }
}

It 'finds reverse references without storing file contents' {
    $inventory = Get-SkillInventory -ProjectRoot $projectRoot -HomeRoot $homeRoot -PluginCacheRoot $pluginRoot -UsageMode None
    $result = Add-SkillReverseReferences -Inventory $inventory -SearchRoot @((Join-Path $fixtureRoot 'references'))
    $shared = @($result.skills | Where-Object logical_name -eq 'shared-skill')[0]
    Assert-Equal 1 @($shared.reverse_references).Count 'Expected one referencing file.'
    Assert-True (($result | ConvertTo-Json -Depth 20) -notmatch 'private-marker') 'Reference content must not be retained.'
}

It 'derives isolated state paths for different projects' {
    $a = Get-DefaultStatePath -ProjectRoot 'C:\work\alpha' -StateRoot 'C:\state'
    $b = Get-DefaultStatePath -ProjectRoot 'C:\work\beta' -StateRoot 'C:\state'
    Assert-True ($a -ne $b) 'Different projects must have different state paths.'
    Assert-True ($a.EndsWith('results.json')) 'State path should target results.json.'
}

It 'detects unchanged and expired records' {
    $inventory = Get-SkillInventory -ProjectRoot $projectRoot -HomeRoot $homeRoot -PluginCacheRoot $pluginRoot -UsageMode None
    $now = [DateTime]::UtcNow
    $records = [ordered]@{}
    foreach ($skill in $inventory.skills) {
        $records[$skill.logical_id] = [pscustomobject][ordered]@{
            logical_id = $skill.logical_id
            bundle_sha256 = $skill.bundle_sha256
            context_sha256 = 'ctx'
            review_expires_at = $now.AddDays(10).ToString('o')
            verdict = 'Keep'
            confidence = 'high'
            reason = 'Fixture result.'
            evidence = @([pscustomobject]@{ type = 'fixture'; detail = 'verified' })
        }
    }
    $state = [pscustomobject][ordered]@{ schema_version = 3; project_root = $inventory.project_root; last_completed = [pscustomobject][ordered]@{ context_sha256 = 'ctx'; skills = [pscustomobject]$records }; active_run = $null }
    $diff = Compare-SkillInventory -Inventory $inventory -State $state -ContextSha256 'ctx' -Now $now
    Assert-Equal 0 @($diff.pending_ids).Count 'Current records should not be scheduled.'
    Assert-Equal @($inventory.skills).Count @($diff.unchanged).Count 'All records should be unchanged.'
    $first = @($state.last_completed.skills.PSObject.Properties)[0].Value
    $first.review_expires_at = $now.AddDays(-1).ToString('o')
    $expired = Compare-SkillInventory -Inventory $inventory -State $state -ContextSha256 'ctx' -Now $now
    Assert-Contains @($expired.expired) $first.logical_id 'Expired record should be scheduled.'
    $first.review_expires_at = $now.AddDays(10).ToString('o')
    $first.bundle_sha256 = 'different-bundle'
    Add-Member -InputObject $state.last_completed.skills -NotePropertyName 's-removed-fixture' -NotePropertyValue ([pscustomobject]@{ logical_id = 's-removed-fixture'; bundle_sha256 = 'old'; context_sha256 = 'ctx'; review_expires_at = $now.AddDays(10).ToString('o') })
    $changed = Compare-SkillInventory -Inventory $inventory -State $state -ContextSha256 'ctx' -Now $now
    Assert-Contains @($changed.changed) $first.logical_id 'Changed bundle should be scheduled.'
    Assert-Contains @($changed.removed) 's-removed-fixture' 'Missing current record should be reported as removed.'
}

It 'validates and merges full state without destroying the last completed generation' {
    $inventory = Get-SkillInventory -ProjectRoot $projectRoot -HomeRoot $homeRoot -PluginCacheRoot $pluginRoot -UsageMode None
    $runId = [guid]::NewGuid().ToString()
    $incoming = [pscustomobject][ordered]@{
        schema_version = 3
        project_root = $inventory.project_root
        active_run = [pscustomobject][ordered]@{
            run_id = $runId
            mode = 'full'
            status = 'in_progress'
            started_at = [DateTime]::UtcNow.ToString('o')
            updated_at = [DateTime]::UtcNow.ToString('o')
            inventory_sha256 = $inventory.inventory_sha256
            context_sha256 = 'ctx'
            pending_ids = @($inventory.skills.logical_id)
            evaluated_ids = @()
            removed_ids = @()
            diagnostics = @()
            skills = [pscustomobject][ordered]@{}
        }
    }
    $validation = Test-StocktakeState -State $incoming -AllowIncomplete
    Assert-True $validation.IsValid ('Valid active run rejected: ' + (@($validation.Errors) -join '; '))
    $existing = [pscustomobject][ordered]@{
        schema_version = 3; project_root = $inventory.project_root; active_run = $null
        last_completed = [pscustomobject][ordered]@{ run_id = 'prior-run'; completed_at = [DateTime]::UtcNow.ToString('o'); inventory_sha256 = 'prior-inventory'; context_sha256 = 'prior-context'; diagnostics = @(); skills = [pscustomobject][ordered]@{}; marker = 'preserve-me' }
    }
    $merged = Merge-StocktakeState -ExistingState $existing -IncomingState $incoming
    Assert-Equal 'preserve-me' $merged.last_completed.marker 'Incomplete run must preserve last completed state.'
    Assert-Equal $runId $merged.active_run.run_id 'Active run should be stored.'
}

It 'rejects stale resume run identifiers and incompatible schemas' {
    $base = [pscustomobject][ordered]@{ schema_version = 3; project_root = 'C:\project'; last_completed = $null; active_run = [pscustomobject]@{ run_id = 'run-a'; mode = 'resume'; status = 'in_progress' } }
    $incoming = [pscustomobject][ordered]@{ schema_version = 3; project_root = 'C:\project'; last_completed = $null; active_run = [pscustomobject]@{ run_id = 'run-b'; mode = 'resume'; status = 'in_progress' } }
    $threw = $false
    try { Merge-StocktakeState -ExistingState $base -IncomingState $incoming | Out-Null } catch { $threw = $_.Exception.Message -match 'run' }
    Assert-True $threw 'Stale resume run should be rejected.'
    $base.active_run.mode = 'full'; $incoming.active_run.mode = 'full'; $threw = $false
    try { Merge-StocktakeState -ExistingState $base -IncomingState $incoming | Out-Null } catch { $threw = $_.Exception.Message -match 'run' }
    Assert-True $threw 'A competing full run should be rejected while another run is active.'
    $invalid = Test-StocktakeState -State ([pscustomobject]@{ schema_version = 99; project_root = 'C:\project' }) -AllowIncomplete
    Assert-True (-not $invalid.IsValid) 'Unknown schema should be invalid.'
}

It 'promotes completed full runs and merges completed quick runs' {
    $dimensions = [pscustomobject][ordered]@{
        trigger_accuracy = 'pass'; actionability = 'pass'; integrity = 'pass'; scope_concision = 'pass'; uniqueness_overlap = 'pass'
        currency = 'pass'; dependency_safety = 'pass'; maintainability = 'pass'; usefulness = 'pass'
    }
    $record = [pscustomobject][ordered]@{
        logical_id = 's-new'; logical_name = 'new-skill'; bundle_sha256 = 'bundle'; context_sha256 = 'ctx'; verdict = 'Keep'; confidence = 'high'; reason = 'Verified fixture.'
        dimensions = $dimensions; evidence = @([pscustomobject]@{ type = 'test'; detail = 'verified' }); reviewed_resources = @('SKILL.md'); uncertainties = @(); proposal = $null
        dependencies = @(); replacement = $null; removal_impact = $null; reviewed_at = [DateTime]::UtcNow.ToString('o'); review_expires_at = [DateTime]::UtcNow.AddDays(30).ToString('o')
    }
    $full = [pscustomobject][ordered]@{
        schema_version = 3; project_root = 'C:\project'; last_completed = $null
        active_run = [pscustomobject][ordered]@{
            run_id = 'full-run'; mode = 'full'; status = 'completed'; started_at = [DateTime]::UtcNow.ToString('o'); updated_at = [DateTime]::UtcNow.ToString('o')
            inventory_sha256 = 'inventory'; context_sha256 = 'ctx'; pending_ids = @(); evaluated_ids = @('s-new'); removed_ids = @(); diagnostics = @(); skills = [pscustomobject]@{ 's-new' = $record }
        }
    }
    $validation = Test-StocktakeState -State $full
    Assert-True $validation.IsValid ('Completed full state should validate: ' + (@($validation.Errors) -join '; '))
    $existing = [pscustomobject][ordered]@{ schema_version = 3; project_root = 'C:\project'; last_completed = [pscustomobject]@{ skills = [pscustomobject]@{ 's-old' = [pscustomobject]@{ logical_id = 's-old' } } }; active_run = $null }
    $promoted = Merge-StocktakeState -ExistingState $existing -IncomingState $full
    Assert-True ($null -eq $promoted.active_run) 'Completed run should clear active_run.'
    Assert-True ($promoted.last_completed.skills.PSObject.Properties.Name -contains 's-new') 'Full completion should promote new record.'
    Assert-True ($promoted.last_completed.skills.PSObject.Properties.Name -notcontains 's-old') 'Full completion should replace old records.'

    $quickRecord = $record.PSObject.Copy()
    $quickRecord.reason = 'Updated fixture.'
    $quick = $full.PSObject.Copy()
    $quick.active_run = $full.active_run.PSObject.Copy()
    $quick.active_run.run_id = 'quick-run'; $quick.active_run.mode = 'quick'; $quick.active_run.skills = [pscustomobject]@{ 's-new' = $quickRecord }; $quick.active_run.removed_ids = @('s-remove')
    $keepRecord = $record.PSObject.Copy(); $keepRecord.logical_id = 's-keep'; $keepRecord.logical_name = 'keep-skill'
    $removeRecord = $record.PSObject.Copy(); $removeRecord.logical_id = 's-remove'; $removeRecord.logical_name = 'remove-skill'
    $baseline = [pscustomobject][ordered]@{
        schema_version = 3; project_root = 'C:\project'; active_run = $null
        last_completed = [pscustomobject]@{ skills = [pscustomobject]@{ 's-keep' = $keepRecord; 's-remove' = $removeRecord; 's-new' = $record } }
    }
    $merged = Merge-StocktakeState -ExistingState $baseline -IncomingState $quick
    Assert-True ($merged.last_completed.skills.PSObject.Properties.Name -contains 's-keep') 'Quick completion should carry unchanged records.'
    Assert-True ($merged.last_completed.skills.PSObject.Properties.Name -notcontains 's-remove') 'Quick completion should drop removed records.'
    Assert-Equal 'Updated fixture.' $merged.last_completed.skills.'s-new'.reason 'Quick completion should replace evaluated records.'
}

It 'rejects completed records missing freshness evidence' {
    $state = [pscustomobject][ordered]@{
        schema_version = 3; project_root = 'C:\project'; last_completed = $null
        active_run = [pscustomobject][ordered]@{
            run_id = 'bad-run'; mode = 'full'; status = 'completed'; started_at = [DateTime]::UtcNow.ToString('o'); updated_at = [DateTime]::UtcNow.ToString('o')
            inventory_sha256 = 'inventory'; context_sha256 = 'ctx'; pending_ids = @(); evaluated_ids = @('s-bad'); removed_ids = @(); diagnostics = @()
            skills = [pscustomobject]@{ 's-bad' = [pscustomobject]@{ logical_id = 's-bad'; verdict = 'Keep'; confidence = 'high'; reason = 'Incomplete.'; evidence = @([pscustomobject]@{ type = 'test'; detail = 'x' }) } }
        }
    }
    $validation = Test-StocktakeState -State $state
    Assert-True (-not $validation.IsValid) 'Completed record without review timestamps and dimensions should be invalid.'
}

It 'rejects invalid last-completed cache generations' {
    $state = [pscustomobject][ordered]@{
        schema_version = 3; project_root = 'C:\project'; active_run = $null
        last_completed = [pscustomobject][ordered]@{
            run_id = 'old-run'; completed_at = [DateTime]::UtcNow.ToString('o'); inventory_sha256 = 'inventory'; context_sha256 = 'ctx'; diagnostics = @()
            skills = [pscustomobject]@{ 's-bad-cache' = [pscustomobject]@{ logical_id = 's-bad-cache'; verdict = 'Keep'; confidence = 'high'; reason = 'Incomplete cache record.' } }
        }
    }
    $validation = Test-StocktakeState -State $state -AllowIncomplete
    Assert-True (-not $validation.IsValid) 'Invalid completed cache records must be rejected even when an active run may be incomplete.'
}

It 'enforces evidence and proposal contracts for actionable verdicts' {
    $dimensions = [pscustomobject][ordered]@{
        trigger_accuracy = 'pass'; actionability = 'fail'; integrity = 'pass'; scope_concision = 'pass'; uniqueness_overlap = 'pass'
        currency = 'pass'; dependency_safety = 'pass'; maintainability = 'pass'; usefulness = 'pass'
    }
    $record = [pscustomobject][ordered]@{
        logical_id = 's-action'; logical_name = 'action'; bundle_sha256 = 'bundle'; context_sha256 = 'ctx'; verdict = 'Improve'; confidence = 'high'; reason = 'Needs a fix.'
        dimensions = $dimensions; evidence = @([pscustomobject]@{ type = 'test'; detail = 'failure reproduced' }); reviewed_resources = @('SKILL.md'); uncertainties = @()
        proposal = [pscustomobject]@{ change = ''; verification = '' }; dependencies = @(); replacement = $null; removal_impact = $null
        reviewed_at = [DateTime]::UtcNow.ToString('o'); review_expires_at = [DateTime]::UtcNow.AddDays(30).ToString('o')
    }
    $state = [pscustomobject][ordered]@{
        schema_version = 3; project_root = 'C:\project'; last_completed = $null
        active_run = [pscustomobject][ordered]@{ run_id = 'contract'; mode = 'full'; status = 'completed'; started_at = [DateTime]::UtcNow.ToString('o'); updated_at = [DateTime]::UtcNow.ToString('o'); inventory_sha256 = 'inventory'; context_sha256 = 'ctx'; pending_ids = @(); evaluated_ids = @('s-action'); removed_ids = @(); diagnostics = @(); skills = [pscustomobject]@{ 's-action' = $record } }
    }
    $validation = Test-StocktakeState -State $state
    Assert-True (-not $validation.IsValid) 'Empty proposal fields and unmapped failure evidence must be rejected.'
}

It 'runs scan, diff, state-path, and save entry points' {
    $skillRoot = Split-Path -Parent $PSScriptRoot
    $scriptRoot = Join-Path $skillRoot 'scripts'
    foreach ($name in @('Scan-Skills.ps1', 'Get-SkillDiff.ps1', 'Save-Results.ps1', 'Get-DefaultStatePath.ps1', 'New-AuditRun.ps1', 'Format-Report.ps1')) {
        Assert-True (Test-Path -LiteralPath (Join-Path $scriptRoot $name) -PathType Leaf) "Missing command wrapper $name."
    }
    $scanRaw = powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Scan-Skills.ps1') -ProjectRoot $projectRoot -HomeRoot $homeRoot -PluginCacheRoot $pluginRoot -UsageMode None -ReferenceSearchRoot (Join-Path $fixtureRoot 'references')
    $scan = $scanRaw | ConvertFrom-Json
    Assert-Equal 1 @($scan.skills | Where-Object logical_name -eq 'managed-current').Count 'Scanner wrapper should include managed skills.'
    Assert-Equal 1 @($scan.skills | Where-Object logical_name -eq 'shared-skill' | Select-Object -ExpandProperty reverse_references).Count 'Scanner wrapper should integrate reverse-reference evidence.'
    $tempRoot = Join-Path $testTempRoot ('stocktake-state-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    try {
        $statePath = Join-Path $tempRoot 'results.json'
        $diffRaw = powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Get-SkillDiff.ps1') -StatePath $statePath -ProjectRoot $projectRoot -HomeRoot $homeRoot -PluginCacheRoot $pluginRoot -UsageMode None
        $diff = $diffRaw | ConvertFrom-Json
        Assert-Equal 'full' $diff.suggested_mode 'Missing state should request full mode.'
        Assert-True (@($diff.diff.pending_ids).Count -gt 0) 'Initial diff should schedule skills.'
        $workPath = Join-Path $tempRoot 'work.json'
        [System.IO.File]::WriteAllText($workPath, ($diff | ConvertTo-Json -Depth 45), [System.Text.UTF8Encoding]::new($false))
        $generatedRunPath = Join-Path $tempRoot 'generated-run.json'
        $generatedRaw = powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'New-AuditRun.ps1') -WorklistPath $workPath -OutputPath $generatedRunPath
        $generated = $generatedRaw | ConvertFrom-Json
        Assert-Equal 3 $generated.schema_version 'Run generator should emit schema version 3.'
        Assert-Equal @($diff.diff.pending_ids).Count @($generated.active_run.pending_ids).Count 'Run generator should preserve the worklist.'
        $pathRaw = powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Get-DefaultStatePath.ps1') -ProjectRoot $projectRoot -StateRoot $tempRoot
        Assert-True ([string]$pathRaw -match 'results\.json') 'State-path wrapper should return results.json.'
        $incoming = [pscustomobject][ordered]@{
            schema_version = 3
            project_root = $diff.inventory.project_root
            last_completed = $null
            active_run = [pscustomobject][ordered]@{
                run_id = [guid]::NewGuid().ToString()
                mode = 'full'
                status = 'in_progress'
                started_at = [DateTime]::UtcNow.ToString('o')
                updated_at = [DateTime]::UtcNow.ToString('o')
                inventory_sha256 = $diff.inventory.inventory_sha256
                context_sha256 = $diff.context_sha256
                pending_ids = @($diff.diff.pending_ids)
                evaluated_ids = @()
                removed_ids = @()
                diagnostics = @($diff.inventory.diagnostics)
                skills = [pscustomobject][ordered]@{}
            }
        }
        $evaluationPath = Join-Path $tempRoot 'evaluation.json'
        [System.IO.File]::WriteAllText($evaluationPath, ($incoming | ConvertTo-Json -Depth 30), [System.Text.UTF8Encoding]::new($false))
        $savedRaw = powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Save-Results.ps1') -StatePath $statePath -EvaluationPath $evaluationPath
        $saved = $savedRaw | ConvertFrom-Json
        Assert-Equal $incoming.active_run.run_id $saved.active_run.run_id 'Save wrapper should persist the active run.'
        Assert-True (Test-Path -LiteralPath $statePath -PathType Leaf) 'State file should exist after save.'
        $reportRaw = powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Format-Report.ps1') -StatePath $statePath -WorklistPath $workPath
        Assert-True (($reportRaw -join "`n") -match 'Skill Stocktake Report') 'Report wrapper should render deterministic Markdown.'
        $incoming.active_run.updated_at = [DateTime]::UtcNow.AddSeconds(1).ToString('o')
        [System.IO.File]::WriteAllText($evaluationPath, ($incoming | ConvertTo-Json -Depth 30), [System.Text.UTF8Encoding]::new($false))
        $savedAgainRaw = powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Save-Results.ps1') -StatePath $statePath -EvaluationPath $evaluationPath
        $savedAgain = $savedAgainRaw | ConvertFrom-Json
        Assert-Equal $incoming.active_run.updated_at $savedAgain.active_run.updated_at 'Second save should atomically replace existing state.'
        $invalidStatePath = Join-Path $tempRoot 'invalid-results.json'
        [System.IO.File]::WriteAllText($invalidStatePath, (([pscustomobject]@{ schema_version = 3; project_root = $projectRoot }) | ConvertTo-Json), [System.Text.UTF8Encoding]::new($false))
        $invalidRejected = $false
        try {
            & (Join-Path $scriptRoot 'Get-SkillDiff.ps1') -StatePath $invalidStatePath -ProjectRoot $projectRoot -HomeRoot $homeRoot -PluginCacheRoot $pluginRoot -UsageMode None | Out-Null
        } catch {
            $invalidRejected = $_.Exception.Message -match 'validation'
        }
        Assert-True $invalidRejected 'Diff wrapper must reject invalid version-3 state with a validation error.'
    } finally {
        if (Test-Path -LiteralPath $tempRoot) { [System.IO.Directory]::Delete($tempRoot, $true) }
    }
}

Write-Host "RESULT passed=$script:Passed failed=$script:Failed"
if ((Test-Path -LiteralPath $testTempRoot -PathType Container) -and @((Get-ChildItem -LiteralPath $testTempRoot -Force)).Count -eq 0) { [System.IO.Directory]::Delete($testTempRoot) }
if ($script:Failed -gt 0) { exit 1 }
