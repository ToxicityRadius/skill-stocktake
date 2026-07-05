Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:SchemaVersion = 3
$script:EngineVersion = '3.0.0'

function New-StocktakeDiagnostic {
    param(
        [Parameter(Mandatory)][string]$Code,
        [Parameter(Mandatory)][string]$Message,
        [string]$Path = '',
        [ValidateSet('info', 'warning', 'error')][string]$Severity = 'warning'
    )
    [pscustomobject][ordered]@{ code = $Code; severity = $Severity; path = $Path; message = $Message }
}

function Get-NormalizedPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    if ($full.Length -gt 3) { $full = $full.TrimEnd([char[]]@('\', '/')) }
    $full.ToLowerInvariant()
}

function Get-StableHash {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        (($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join '')
    } finally {
        $sha.Dispose()
    }
}

function Get-FileSha256 {
    param([Parameter(Mandatory)][string]$Path)
    (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Get-CodexConfigSettings {
    param([string]$ConfigPath)
    $settings = [ordered]@{ plugin_enabled = @{}; disabled_skill_paths = @(); fallback_names = @(); project_doc_max_bytes = 32768 }
    if ([string]::IsNullOrWhiteSpace($ConfigPath) -or -not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { return [pscustomobject]$settings }
    $lines = @(Get-Content -LiteralPath $ConfigPath -ErrorAction Stop)
    $section = ''
    $skillPath = $null
    $skillEnabled = $null
    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^\[plugins\."([^"]+)"\]$') { $section = 'plugin:' + $Matches[1]; continue }
        if ($trimmed -eq '[[skills.config]]') {
            if (-not [string]::IsNullOrWhiteSpace($skillPath) -and $skillEnabled -eq $false) { $settings.disabled_skill_paths += $skillPath }
            $section = 'skill'; $skillPath = $null; $skillEnabled = $null; continue
        }
        if ($trimmed -match '^\[') {
            if ($section -eq 'skill' -and -not [string]::IsNullOrWhiteSpace($skillPath) -and $skillEnabled -eq $false) { $settings.disabled_skill_paths += $skillPath }
            $section = ''; $skillPath = $null; $skillEnabled = $null; continue
        }
        if ($section -like 'plugin:*' -and $trimmed -match '^enabled\s*=\s*(true|false)\s*$') {
            $settings.plugin_enabled[$section.Substring(7).ToLowerInvariant()] = ($Matches[1] -eq 'true')
        } elseif ($section -eq 'skill' -and $trimmed -match '^path\s*=\s*["''](.+)["'']\s*$') {
            $skillPath = $Matches[1]
        } elseif ($section -eq 'skill' -and $trimmed -match '^enabled\s*=\s*(true|false)\s*$') {
            $skillEnabled = ($Matches[1] -eq 'true')
        } elseif ($trimmed -match '^project_doc_fallback_filenames\s*=\s*\[(.*)\]\s*$') {
            $settings.fallback_names = @([regex]::Matches($Matches[1], '["'']([^"'']+)["'']') | ForEach-Object { $_.Groups[1].Value })
        } elseif ($trimmed -match '^project_doc_max_bytes\s*=\s*(\d+)\s*$') {
            $settings.project_doc_max_bytes = [int]$Matches[1]
        }
    }
    if ($section -eq 'skill' -and -not [string]::IsNullOrWhiteSpace($skillPath) -and $skillEnabled -eq $false) { $settings.disabled_skill_paths += $skillPath }
    [pscustomobject]$settings
}

function Get-DirectoryChain {
    param([Parameter(Mandatory)][string]$ProjectRoot, [Parameter(Mandatory)][string]$CurrentWorkingDirectory)
    $root = [System.IO.Path]::GetFullPath($ProjectRoot).TrimEnd([char[]]@('\', '/'))
    $cwd = [System.IO.Path]::GetFullPath($CurrentWorkingDirectory).TrimEnd([char[]]@('\', '/'))
    if ($cwd -ne $root -and -not $cwd.StartsWith($root + [System.IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { return @($root) }
    $result = [System.Collections.Generic.List[string]]::new()
    $current = [System.IO.DirectoryInfo]::new($cwd)
    while ($null -ne $current) {
        $result.Add($current.FullName)
        if ($current.FullName.TrimEnd([char[]]@('\', '/')).Equals($root, [StringComparison]::OrdinalIgnoreCase)) { break }
        $current = $current.Parent
    }
    @($result | Sort-Object { $_.Length })
}

function Get-CodexPluginRuntimeMap {
    param([string]$PluginInventoryPath, [switch]$AllowCli)
    $map = @{}
    $raw = $null
    if (-not [string]::IsNullOrWhiteSpace($PluginInventoryPath) -and (Test-Path -LiteralPath $PluginInventoryPath -PathType Leaf)) {
        $raw = Get-Content -Raw -LiteralPath $PluginInventoryPath
    } elseif ($AllowCli -and $null -ne (Get-Command codex -ErrorAction SilentlyContinue)) {
        try { $raw = (& codex plugin list --json 2>$null) -join [Environment]::NewLine } catch { $raw = $null }
    }
    if ([string]::IsNullOrWhiteSpace([string]$raw)) { return $map }
    try { $parsed = $raw | ConvertFrom-Json } catch { return $map }
    foreach ($plugin in @($parsed.installed)) {
        if ([string]::IsNullOrWhiteSpace([string]$plugin.pluginId)) { continue }
        $map[[string]$plugin.pluginId.ToLowerInvariant()] = [pscustomobject]@{ installed = [bool]$plugin.installed; enabled = [bool]$plugin.enabled; version = [string]$plugin.version }
    }
    $map
}

function Unquote-SkillScalar {
    param([string]$Value)
    $trimmed = $Value.Trim()
    if ($trimmed.Length -ge 2 -and $trimmed[0] -eq '"' -and $trimmed[$trimmed.Length - 1] -eq '"') {
        try { return ($trimmed | ConvertFrom-Json) } catch { return $trimmed.Substring(1, $trimmed.Length - 2) }
    }
    if ($trimmed.Length -ge 2 -and $trimmed[0] -eq "'" -and $trimmed[$trimmed.Length - 1] -eq "'") {
        return $trimmed.Substring(1, $trimmed.Length - 2).Replace("''", "'")
    }
    $comment = [regex]::Match($trimmed, '^(.*?)(?:\s+#.*)?$')
    $comment.Groups[1].Value.Trim()
}

function ConvertFrom-SkillFrontmatter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content,
        [string]$Path = ''
    )

    $diagnostics = [System.Collections.Generic.List[object]]::new()
    $normalized = $Content.TrimStart([char]0xFEFF).Replace("`r`n", "`n").Replace("`r", "`n")
    $lines = $normalized -split "`n", -1
    if ($lines.Count -lt 3 -or $lines[0].Trim() -ne '---') {
        $diagnostics.Add((New-StocktakeDiagnostic -Code 'missing_frontmatter' -Message 'SKILL.md must begin with YAML frontmatter.' -Path $Path -Severity error))
        return [pscustomobject][ordered]@{ Name = $null; Description = $null; IsValid = $false; Diagnostics = $diagnostics }
    }

    $end = -1
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq '---') { $end = $i; break }
    }
    if ($end -lt 0) {
        $diagnostics.Add((New-StocktakeDiagnostic -Code 'unclosed_frontmatter' -Message 'YAML frontmatter has no closing delimiter.' -Path $Path -Severity error))
        return [pscustomobject][ordered]@{ Name = $null; Description = $null; IsValid = $false; Diagnostics = $diagnostics }
    }

    $values = @{}
    $seen = @{}
    $i = 1
    while ($i -lt $end) {
        $line = $lines[$i]
        if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#')) { $i++; continue }
        if ($line -match '^\s+') { $i++; continue }
        $match = [regex]::Match($line, '^([A-Za-z0-9_-]+):\s*(.*)$')
        if (-not $match.Success) {
            $diagnostics.Add((New-StocktakeDiagnostic -Code 'invalid_frontmatter_line' -Message "Unrecognized frontmatter line $($i + 1)." -Path $Path -Severity error))
            $i++
            continue
        }
        $key = $match.Groups[1].Value.ToLowerInvariant()
        if ($seen.ContainsKey($key)) {
            $diagnostics.Add((New-StocktakeDiagnostic -Code 'duplicate_field' -Message "Duplicate frontmatter field '$key'." -Path $Path -Severity error))
        }
        $seen[$key] = $true
        $raw = $match.Groups[2].Value.Trim()
        if ($raw -match '^([|>])([+-]?)$') {
            $style = $Matches[1]
            $block = [System.Collections.Generic.List[string]]::new()
            $i++
            while ($i -lt $end) {
                $candidate = $lines[$i]
                if ($candidate -match '^\s+' -or [string]::IsNullOrWhiteSpace($candidate)) {
                    $block.Add($candidate)
                    $i++
                    continue
                }
                break
            }
            $nonBlank = @($block | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            $indent = 0
            if ($nonBlank.Count -gt 0) {
                $indent = ($nonBlank | ForEach-Object { ([regex]::Match($_, '^\s*')).Value.Length } | Measure-Object -Minimum).Minimum
            }
            $clean = @($block | ForEach-Object {
                if ($_.Length -ge $indent) { $_.Substring($indent).TrimEnd() } else { '' }
            })
            if ($style -eq '>') {
                $paragraphs = (($clean -join "`n") -split "`n\s*`n") | ForEach-Object { (($_ -split "`n") -join ' ').Trim() }
                $values[$key] = ($paragraphs -join "`n").TrimEnd()
            } else {
                $values[$key] = ($clean -join "`n").TrimEnd()
            }
            continue
        }
        $values[$key] = Unquote-SkillScalar -Value $raw
        $i++
    }

    $name = if ($values.ContainsKey('name')) { [string]$values['name'] } else { $null }
    $description = if ($values.ContainsKey('description')) { [string]$values['description'] } else { $null }
    if ([string]::IsNullOrWhiteSpace($name)) {
        $diagnostics.Add((New-StocktakeDiagnostic -Code 'missing_name' -Message 'Frontmatter requires a non-empty name.' -Path $Path -Severity error))
    } elseif ($name -notmatch '^[a-z0-9][a-z0-9-]{0,63}$') {
        $diagnostics.Add((New-StocktakeDiagnostic -Code 'invalid_name' -Message "Skill name '$name' must use lowercase letters, digits, and hyphens and be at most 64 characters." -Path $Path -Severity error))
    }
    if ([string]::IsNullOrWhiteSpace($description)) {
        $diagnostics.Add((New-StocktakeDiagnostic -Code 'missing_description' -Message 'Frontmatter requires a non-empty description.' -Path $Path -Severity error))
    }
    $hasError = @($diagnostics | Where-Object severity -eq 'error').Count -gt 0
    [pscustomobject][ordered]@{ Name = $name; Description = $description; IsValid = -not $hasError; Diagnostics = $diagnostics }
}

function Test-OpenAiSkillMetadata {
    param([Parameter(Mandatory)][string]$SkillDirectory, [Parameter(Mandatory)][string]$SkillName, [switch]$StrictInterface)
    $path = Join-Path $SkillDirectory 'agents\openai.yaml'
    $errors = [System.Collections.Generic.List[string]]::new()
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $errors }
    $content = Get-Content -Raw -LiteralPath $path
    if ($StrictInterface) {
        $short = [regex]::Match($content, '(?m)^\s*short_description:\s*["''](.+?)["'']\s*$')
        if (-not $short.Success -or $short.Groups[1].Value.Length -lt 25 -or $short.Groups[1].Value.Length -gt 64) { $errors.Add('short_description must be 25-64 characters.') }
        $prompt = [regex]::Match($content, '(?m)^\s*default_prompt:\s*["''](.+?)["'']\s*$')
        if (-not $prompt.Success -or $prompt.Groups[1].Value.IndexOf('$' + $SkillName, [StringComparison]::OrdinalIgnoreCase) -lt 0) { $errors.Add('default_prompt must mention $' + $SkillName + ' explicitly.') }
    }
    foreach ($icon in [regex]::Matches($content, '(?m)^\s*icon_(?:small|large):\s*["''](.+?)["'']\s*$')) {
        $iconPath = Join-Path $SkillDirectory $icon.Groups[1].Value
        if (-not (Test-Path -LiteralPath $iconPath -PathType Leaf)) { $errors.Add("Referenced icon does not exist: $($icon.Groups[1].Value)") }
    }
    $errors
}

function Get-BundleFingerprint {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$SkillDirectory)
    $base = [System.IO.Path]::GetFullPath($SkillDirectory).TrimEnd([char[]]@('\', '/'))
    $baseItem = Get-Item -LiteralPath $base -Force
    if (($baseItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 -and $baseItem.PSObject.Properties.Name -contains 'Target' -and $null -ne $baseItem.Target) {
        $target = [string]@($baseItem.Target)[0]
        if (-not [System.IO.Path]::IsPathRooted($target)) { $target = Join-Path (Split-Path -Parent $base) $target }
        $base = [System.IO.Path]::GetFullPath($target).TrimEnd([char[]]@('\', '/'))
    }
    $entries = [System.Collections.Generic.List[string]]::new()
    $files = Get-ChildItem -LiteralPath $base -Recurse -File -Force -ErrorAction Stop | Where-Object {
        $relative = $_.FullName.Substring($base.Length).TrimStart([char[]]@('\', '/'))
        $relative -notmatch '(^|[\\/])(\.git|node_modules|__pycache__)([\\/]|$)' -and
        $relative -notmatch '(^|[\\/])(results\.json|evaluation\.json)$' -and
        $relative -notmatch '\.(tmp|lock)$'
    }
    foreach ($file in ($files | Sort-Object FullName)) {
        $relative = $file.FullName.Substring($base.Length).TrimStart([char[]]@('\', '/')).Replace('\', '/').ToLowerInvariant()
        $entries.Add("${relative}:$((Get-FileSha256 -Path $file.FullName))")
    }
    Get-StableHash -Text ($entries -join "`n")
}

function Get-ManagedSkillRoots {
    [CmdletBinding()]
    param(
        [string]$PluginCacheRoot,
        [string]$ConfigPath = (Join-Path $HOME '.codex\config.toml'),
        [string]$PluginInventoryPath,
        [switch]$AllowPluginCli
    )
    $roots = [System.Collections.Generic.List[object]]::new()
    if ([string]::IsNullOrWhiteSpace($PluginCacheRoot) -or -not (Test-Path -LiteralPath $PluginCacheRoot -PathType Container)) { return $roots }
    $cacheFull = [System.IO.Path]::GetFullPath($PluginCacheRoot).TrimEnd([char[]]@('\', '/'))
    $candidates = @(Get-ChildItem -LiteralPath $PluginCacheRoot -Recurse -Directory -Force -ErrorAction SilentlyContinue | Where-Object {
        $relative = $_.FullName.Substring($cacheFull.Length).TrimStart([char[]]@('\', '/'))
        $_.Name -eq 'skills' -and $relative -notmatch '(?i)(^|[\\/])(plugin-backup[^\\/]*|plugin-install[^\\/]*|backup-[^\\/]*|staging|node_modules|tests?|fixtures?)([\\/]|$)'
    })
    $groups = @{}
    foreach ($candidate in $candidates) {
        $versionDir = $candidate.Parent
        $pluginDir = $versionDir.Parent
        if ($null -eq $pluginDir) { continue }
        $originDir = $pluginDir.Parent
        $origin = if ($originDir) { $originDir.Name } else { 'managed' }
        $key = if ($origin -in @('openai-curated', 'openai-curated-remote')) { ('curated-family|' + $pluginDir.Name).ToLowerInvariant() } else { ($origin + '|' + $pluginDir.Name).ToLowerInvariant() }
        if (-not $groups.ContainsKey($key)) { $groups[$key] = [System.Collections.Generic.List[object]]::new() }
        $groups[$key].Add([pscustomobject]@{
            path = $candidate.FullName
            version = $versionDir.Name
            plugin = $pluginDir.Name
            origin = $origin
            mtime = $candidate.LastWriteTimeUtc
            remote_installed = ($origin -eq 'openai-curated-remote' -and (Test-Path -LiteralPath (Join-Path $pluginDir.FullName '.codex-remote-plugin-install.json') -PathType Leaf))
        })
    }
    $config = Get-CodexConfigSettings -ConfigPath $ConfigPath
    $runtimePlugins = Get-CodexPluginRuntimeMap -PluginInventoryPath $PluginInventoryPath -AllowCli:$AllowPluginCli
    foreach ($key in ($groups.Keys | Sort-Object)) {
        $items = @($groups[$key])
        $preferred = @($items | Where-Object remote_installed)
        if ($preferred.Count -eq 0) { $preferred = $items }
        $selected = @($preferred | Where-Object version -eq 'latest' | Select-Object -First 1)
        if ($selected.Count -eq 0) { $selected = @($preferred | Sort-Object mtime, version -Descending | Select-Object -First 1) }
        if ($selected.Count -gt 0) {
            $item = $selected[0]
            $configOrigin = if ($item.origin -eq 'openai-curated-remote') { 'openai-curated' } else { $item.origin }
            $pluginId = ($item.plugin + '@' + $configOrigin).ToLowerInvariant()
            $runtimeKnown = $runtimePlugins.ContainsKey($pluginId)
            $isDisabled = ($config.plugin_enabled.ContainsKey($pluginId) -and -not $config.plugin_enabled[$pluginId]) -or ($runtimeKnown -and -not $runtimePlugins[$pluginId].enabled)
            $roots.Add([pscustomobject][ordered]@{
                source = "managed:$($item.origin):$($item.plugin)"
                ownership = 'managed-read-only'
                path = $item.path
                plugin_id = $pluginId
                enabled = -not $isDisabled
                selection = if ($isDisabled) { 'disabled' } elseif ($runtimeKnown -and $runtimePlugins[$pluginId].enabled) { 'runtime-confirmed' } elseif ($item.remote_installed) { 'remote-install-record' } elseif ($item.version -eq 'latest') { 'explicit-latest' } else { 'best-effort-current' }
            })
        }
    }
    $roots
}

function Get-SkillInventory {
    [CmdletBinding()]
    param(
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
        [switch]$SkipReverseReferences
    )

    $projectFull = [System.IO.Path]::GetFullPath($ProjectRoot)
    $cwdFull = [System.IO.Path]::GetFullPath($CurrentWorkingDirectory)
    $config = Get-CodexConfigSettings -ConfigPath $ConfigPath
    $rootSpecs = [System.Collections.Generic.List[object]]::new()
    $rootSpecs.Add([pscustomobject]@{ source = 'system'; ownership = 'system-read-only'; path = (Join-Path $HomeRoot '.codex\skills\.system'); selection = 'configured' })
    $rootSpecs.Add([pscustomobject]@{ source = 'global-codex'; ownership = 'user'; path = (Join-Path $HomeRoot '.codex\skills'); selection = 'compatibility' })
    $rootSpecs.Add([pscustomobject]@{ source = 'global-agents'; ownership = 'user'; path = (Join-Path $HomeRoot '.agents\skills'); selection = 'configured' })
    $chainIndex = 0
    foreach ($directory in @(Get-DirectoryChain -ProjectRoot $projectFull -CurrentWorkingDirectory $cwdFull)) {
        $chainIndex++
        $rootSpecs.Add([pscustomobject]@{ source = "project-codex:$chainIndex"; ownership = 'project'; path = (Join-Path $directory '.codex\skills'); selection = 'compatibility' })
        $rootSpecs.Add([pscustomobject]@{ source = "project-agents:$chainIndex"; ownership = 'project'; path = (Join-Path $directory '.agents\skills'); selection = 'configured' })
    }
    foreach ($adminRoot in @($(if ($env:OS -eq 'Windows_NT') { Join-Path $env:ProgramData 'Codex\skills' } else { '/etc/codex/skills' }))) {
        if (-not [string]::IsNullOrWhiteSpace($adminRoot)) { $rootSpecs.Add([pscustomobject]@{ source = 'admin'; ownership = 'admin-read-only'; path = $adminRoot; selection = 'configured' }) }
    }
    $defaultPluginCache = Join-Path $HOME '.codex\plugins\cache'
    $allowPluginCli = -not [string]::IsNullOrWhiteSpace($PluginCacheRoot) -and (Get-NormalizedPath -Path $PluginCacheRoot) -eq (Get-NormalizedPath -Path $defaultPluginCache)
    foreach ($managed in @(Get-ManagedSkillRoots -PluginCacheRoot $PluginCacheRoot -ConfigPath $ConfigPath -PluginInventoryPath $PluginInventoryPath -AllowPluginCli:$allowPluginCli)) { $rootSpecs.Add($managed) }
    $additionalIndex = 0
    foreach ($root in @($AdditionalSkillRoot)) {
        if (-not [string]::IsNullOrWhiteSpace($root)) {
            $additionalIndex++
            $rootSpecs.Add([pscustomobject]@{ source = "managed:additional:$additionalIndex"; ownership = 'managed-read-only'; path = $root; selection = 'explicit' })
        }
    }

    $instances = [System.Collections.Generic.List[object]]::new()
    $diagnostics = [System.Collections.Generic.List[object]]::new()
    $summary = [ordered]@{}
    foreach ($spec in $rootSpecs) {
        $found = Test-Path -LiteralPath $spec.path -PathType Container
        $count = 0
        if ($spec.PSObject.Properties.Name -contains 'enabled' -and -not $spec.enabled) {
            $diagnostics.Add((New-StocktakeDiagnostic -Code 'plugin_disabled' -Message "Plugin '$($spec.plugin_id)' is installed or cached but disabled and was excluded from active inventory." -Path $spec.path -Severity info))
            $summary[$spec.source] = [pscustomobject][ordered]@{ found = $found; path = $spec.path; count = 0; ownership = $spec.ownership; selection = $spec.selection }
            continue
        }
        if ($spec.ownership -eq 'managed-read-only' -and $spec.selection -eq 'best-effort-current') {
            $diagnostics.Add((New-StocktakeDiagnostic -Code 'managed_activation_inferred' -Message 'Managed plugin activation was inferred from the newest available bundle because no explicit current marker was found.' -Path $spec.path -Severity info))
        }
        if ($found) {
            $files = @()
            try {
                $files = @(Get-ChildItem -LiteralPath $spec.path -Recurse -Filter 'SKILL.md' -File -Force -ErrorAction Stop | Where-Object {
                    $relative = $_.FullName.Substring(([System.IO.Path]::GetFullPath($spec.path).TrimEnd([char[]]@('\', '/'))).Length).TrimStart([char[]]@('\', '/'))
                    $relative -notmatch '(?i)(^|[\\/])(tests?|fixtures?|examples?|assets|references|scripts|evals|evaluations|node_modules|plugin-backup[^\\/]*)([\\/]|$)' -and
                    -not ($spec.source -eq 'global-codex' -and $relative -match '(?i)^\.system[\\/]')
                } | Sort-Object FullName)
                foreach ($link in @(Get-ChildItem -LiteralPath $spec.path -Directory -Force -ErrorAction SilentlyContinue | Where-Object { ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 })) {
                    $linkedSkill = Join-Path $link.FullName 'SKILL.md'
                    if (Test-Path -LiteralPath $linkedSkill -PathType Leaf) { $files += Get-Item -LiteralPath $linkedSkill -Force }
                }
                $files = @($files | Sort-Object FullName -Unique)
            } catch {
                $diagnostics.Add((New-StocktakeDiagnostic -Code 'root_unreadable' -Message $_.Exception.Message -Path $spec.path -Severity error))
            }
            foreach ($file in $files) {
                try {
                    $content = Get-Content -Raw -LiteralPath $file.FullName -ErrorAction Stop
                    $normalizedFile = Get-NormalizedPath -Path $file.FullName
                    if (@($config.disabled_skill_paths | Where-Object { (Get-NormalizedPath -Path $_) -eq $normalizedFile }).Count -gt 0) {
                        $diagnostics.Add((New-StocktakeDiagnostic -Code 'skill_disabled' -Message 'Skill is disabled by configuration and was excluded from active inventory.' -Path $file.FullName -Severity info))
                        continue
                    }
                    $metadata = ConvertFrom-SkillFrontmatter -Content $content -Path $file.FullName
                    foreach ($diagnostic in @($metadata.Diagnostics)) { $diagnostics.Add($diagnostic) }
                    $rootFull = [System.IO.Path]::GetFullPath($spec.path).TrimEnd([char[]]@('\', '/'))
                    $relative = $file.FullName.Substring($rootFull.Length).TrimStart([char[]]@('\', '/')).Replace('\', '/')
                    $directory = $file.Directory.FullName
                    if ($metadata.IsValid) {
                        $strictMetadata = $spec.ownership -in @('user', 'project')
                        foreach ($metadataError in @(Test-OpenAiSkillMetadata -SkillDirectory $directory -SkillName $metadata.Name -StrictInterface:$strictMetadata)) {
                            $diagnostics.Add((New-StocktakeDiagnostic -Code 'invalid_openai_metadata' -Message $metadataError -Path (Join-Path $directory 'agents\openai.yaml') -Severity warning))
                        }
                    }
                    $instanceId = 'i-' + (Get-StableHash -Text (($spec.source + '|' + $relative).ToLowerInvariant())).Substring(0, 20)
                    $instances.Add([pscustomobject][ordered]@{
                        instance_id = $instanceId
                        logical_name = $metadata.Name
                        description = $metadata.Description
                        metadata_valid = $metadata.IsValid
                        source = $spec.source
                        ownership = $spec.ownership
                        selection = $spec.selection
                        path = $file.FullName
                        skill_directory = $directory
                        relative_path = $relative
                        skill_md_sha256 = Get-FileSha256 -Path $file.FullName
                        bundle_sha256 = Get-BundleFingerprint -SkillDirectory $directory
                        mtime = $file.LastWriteTimeUtc.ToString('o')
                    })
                    $count++
                } catch {
                    $diagnostics.Add((New-StocktakeDiagnostic -Code 'skill_unreadable' -Message $_.Exception.Message -Path $file.FullName -Severity error))
                }
            }
        }
        $summary[$spec.source] = [pscustomobject][ordered]@{ found = $found; path = $spec.path; count = $count; ownership = $spec.ownership; selection = $spec.selection }
    }

    $grouped = [ordered]@{}
    foreach ($instance in $instances) {
        $scope = if ($instance.source -match '^global-') { 'global' } elseif ($instance.source -match '^project-') { ($instance.source -replace '^(project-(?:codex|agents)):.*$','$1') } else { $instance.source }
        $compatibilitySource = $instance.source -match '^(global-(codex|agents)|project-(codex|agents):)'
        $groupKey = if ($compatibilitySource) {
            ($scope + '|' + $instance.relative_path + '|' + $instance.bundle_sha256).ToLowerInvariant()
        } else {
            $instance.instance_id
        }
        if (-not $grouped.Contains($groupKey)) { $grouped[$groupKey] = [System.Collections.Generic.List[object]]::new() }
        $grouped[$groupKey].Add($instance)
    }

    $skills = [System.Collections.Generic.List[object]]::new()
    foreach ($key in $grouped.Keys) {
        $items = @($grouped[$key])
        $primary = $items[0]
        $logicalName = $primary.logical_name
        $primaryScope = if ($primary.source -match '^global-') { 'global' } elseif ($primary.source -match '^project-') { ($primary.source -replace '^(project-(?:codex|agents)):.*$','$1') } else { $primary.source }
        $logicalSeed = if ($items.Count -gt 1) {
            ('mirror|' + $primaryScope + '|' + $primary.relative_path + '|' + [string]$logicalName).ToLowerInvariant()
        } else {
            ('instance|' + $primary.source + '|' + $primary.relative_path + '|' + [string]$logicalName).ToLowerInvariant()
        }
        $locations = @($items | ForEach-Object { $_.path } | Sort-Object -Unique)
        $sources = @($items | ForEach-Object { $_.source } | Sort-Object -Unique)
        $skills.Add([pscustomobject][ordered]@{
            logical_id = 's-' + (Get-StableHash -Text $logicalSeed).Substring(0, 20)
            logical_name = $logicalName
            description = $primary.description
            metadata_valid = $primary.metadata_valid
            ownership = if (@($items | Where-Object ownership -eq 'managed-read-only').Count -gt 0) { 'managed-read-only' } else { $primary.ownership }
            source = $primary.source
            sources = $sources
            selection = $primary.selection
            activation = if ($primary.selection -in @('runtime-confirmed', 'remote-install-record', 'configured', 'compatibility', 'explicit')) { 'confirmed' } elseif ($primary.selection -eq 'disabled') { 'disabled' } else { 'inferred' }
            path = $primary.path
            skill_directory = $primary.skill_directory
            locations = $locations
            bundle_sha256 = $primary.bundle_sha256
            skill_md_sha256 = $primary.skill_md_sha256
            mtime = $primary.mtime
            usage = [pscustomobject][ordered]@{ status = 'not_scanned'; tool_reads_7d = 0; tool_reads_30d = 0; unique_sessions_7d = 0; unique_sessions_30d = 0; last_observed_at = $null }
            reverse_references = @()
        })
    }

    foreach ($nameGroup in @($skills | Where-Object { -not [string]::IsNullOrWhiteSpace($_.logical_name) } | Group-Object logical_name | Where-Object Count -gt 1)) {
        if (@($nameGroup.Group.bundle_sha256 | Sort-Object -Unique).Count -gt 1) {
            $paths = @($nameGroup.Group.path) -join '; '
            $diagnostics.Add((New-StocktakeDiagnostic -Code 'name_collision' -Message "Skill name '$($nameGroup.Name)' resolves to different bundles." -Path $paths -Severity warning))
        }
    }

    $inventoryLines = @($skills | Sort-Object logical_id | ForEach-Object { $_.logical_id + ':' + $_.bundle_sha256 + ':' + (@($_.locations) -join '|') })
    $inventory = [pscustomobject][ordered]@{
        schema_version = $script:SchemaVersion
        engine_version = $script:EngineVersion
        scanned_at = [DateTime]::UtcNow.ToString('o')
        project_root = $projectFull
        current_working_directory = $cwdFull
        inventory_sha256 = Get-StableHash -Text ($inventoryLines -join "`n")
        scan_summary = [pscustomobject]$summary
        diagnostics = $diagnostics
        instances = $instances
        skills = $skills
    }
    if (-not $SkipReverseReferences) {
        $referenceRoots = @(Get-DefaultReferenceSearchRoot -ProjectRoot $projectFull -CurrentWorkingDirectory $cwdFull -HomeRoot $HomeRoot -ConfigPath $ConfigPath) + @($ReferenceSearchRoot)
        $inventory = Add-SkillReverseReferences -Inventory $inventory -SearchRoot @($referenceRoots | Sort-Object -Unique)
    }
    if ($UsageMode -eq 'Sessions') { return Add-SkillUsage -Inventory $inventory -SessionsRoot $SessionsRoot }
    $inventory
}

function Add-SkillUsage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Inventory,
        [Parameter(Mandatory)][string]$SessionsRoot,
        [DateTime]$Now = [DateTime]::UtcNow
    )
    $cutoff30 = $Now.ToUniversalTime().AddDays(-30)
    $cutoff7 = $Now.ToUniversalTime().AddDays(-7)
    $sessionSets = @{}
    foreach ($skill in @($Inventory.skills)) {
        $sessionSets[$skill.logical_id] = [pscustomobject]@{ d7 = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase); d30 = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase) }
        $skill.usage = [pscustomobject][ordered]@{ status = 'available'; tool_reads_7d = 0; tool_reads_30d = 0; unique_sessions_7d = 0; unique_sessions_30d = 0; last_observed_at = $null }
    }
    if (-not (Test-Path -LiteralPath $SessionsRoot -PathType Container)) {
        foreach ($skill in @($Inventory.skills)) { $skill.usage.status = 'unavailable' }
        return $Inventory
    }
    $sessions = @(Get-ChildItem -LiteralPath $SessionsRoot -Recurse -Filter '*.jsonl' -File -ErrorAction SilentlyContinue | Where-Object LastWriteTimeUtc -ge $cutoff30)
    foreach ($session in $sessions) {
        try {
            foreach ($line in [System.IO.File]::ReadLines($session.FullName)) {
                if ($line -notmatch 'function_call' -or $line -notmatch '(?i)skill\.md') { continue }
                try { $entry = $line | ConvertFrom-Json } catch { continue }
                if ($null -eq $entry.payload -or $entry.payload.type -ne 'function_call') { continue }
                $when = [DateTime]::MinValue
                if (-not [DateTime]::TryParse([string]$entry.timestamp, [ref]$when)) { continue }
                $utc = $when.ToUniversalTime()
                if ($utc -lt $cutoff30) { continue }
                $arguments = [string]$entry.payload.arguments
                $arguments = $arguments.Replace('\\', '\')
                foreach ($skill in @($Inventory.skills)) {
                    $matched = $false
                    foreach ($location in @($skill.locations)) {
                        if ($arguments.IndexOf($location, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or $arguments.IndexOf($location.Replace('\', '/'), [StringComparison]::OrdinalIgnoreCase) -ge 0) { $matched = $true; break }
                    }
                    if (-not $matched) { continue }
                    $skill.usage.tool_reads_30d++
                    [void]$sessionSets[$skill.logical_id].d30.Add($session.FullName)
                    if ($utc -ge $cutoff7) {
                        $skill.usage.tool_reads_7d++
                        [void]$sessionSets[$skill.logical_id].d7.Add($session.FullName)
                    }
                    $last = [DateTime]::MinValue
                    if ([string]::IsNullOrWhiteSpace([string]$skill.usage.last_observed_at) -or ([DateTime]::TryParse([string]$skill.usage.last_observed_at, [ref]$last) -and $utc -gt $last.ToUniversalTime())) {
                        $skill.usage.last_observed_at = $utc.ToString('o')
                    }
                }
            }
        } catch {
            $Inventory.diagnostics.Add((New-StocktakeDiagnostic -Code 'session_unreadable' -Message $_.Exception.Message -Path $session.FullName -Severity warning))
        }
    }
    foreach ($skill in @($Inventory.skills)) {
        $skill.usage.unique_sessions_7d = $sessionSets[$skill.logical_id].d7.Count
        $skill.usage.unique_sessions_30d = $sessionSets[$skill.logical_id].d30.Count
    }
    $Inventory
}

function Add-SkillReverseReferences {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Inventory,
        [Parameter(Mandatory)][string[]]$SearchRoot,
        [long]$MaximumFileBytes = 1048576
    )
    foreach ($skill in @($Inventory.skills)) { $skill.reverse_references = @() }
    $files = [System.Collections.Generic.List[object]]::new()
    foreach ($root in @($SearchRoot)) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        $item = Get-Item -LiteralPath $root -Force
        if ($item.PSIsContainer) {
            foreach ($file in @(Get-ChildItem -LiteralPath $item.FullName -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Length -le $MaximumFileBytes -and $_.Extension -in @('.md', '.toml', '.yaml', '.yml', '.json', '.ps1') })) { $files.Add($file) }
        } elseif ($item.Length -le $MaximumFileBytes) { $files.Add($item) }
    }
    foreach ($file in $files) {
        try {
            $content = Get-Content -Raw -LiteralPath $file.FullName
            foreach ($skill in @($Inventory.skills)) {
                if ([string]::IsNullOrWhiteSpace([string]$skill.logical_name)) { continue }
                $isOwnResource = $false
                foreach ($location in @($skill.locations)) {
                    $ownDirectory = (Split-Path -Parent $location).TrimEnd([char[]]@('\', '/')) + [System.IO.Path]::DirectorySeparatorChar
                    if ($file.FullName.StartsWith($ownDirectory, [StringComparison]::OrdinalIgnoreCase)) { $isOwnResource = $true; break }
                }
                if ($isOwnResource) { continue }
                $needle = [string]$skill.logical_name
                $escapedNeedle = [regex]::Escape($needle)
                if ($content.IndexOf('$' + $needle, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or $content -match "(?i)(``|\bskill[:/])$escapedNeedle(``|\b)") {
                    $skill.reverse_references = @($skill.reverse_references) + [pscustomobject][ordered]@{ path = $file.FullName; match = 'name' }
                }
            }
        } catch {
            $Inventory.diagnostics.Add((New-StocktakeDiagnostic -Code 'reference_unreadable' -Message $_.Exception.Message -Path $file.FullName -Severity warning))
        }
    }
    $Inventory
}

function Get-ApplicableInstructionPath {
    [CmdletBinding()]
    param(
        [string]$ProjectRoot = (Get-Location).Path,
        [string]$CurrentWorkingDirectory = (Get-Location).Path,
        [string]$HomeRoot = $HOME,
        [string]$ConfigPath = (Join-Path $HOME '.codex\config.toml')
    )
    $config = Get-CodexConfigSettings -ConfigPath $ConfigPath
    $selected = [System.Collections.Generic.List[string]]::new()
    $globalOverride = Join-Path $HomeRoot '.codex\AGENTS.override.md'
    $globalAgent = Join-Path $HomeRoot '.codex\AGENTS.md'
    if (Test-Path -LiteralPath $globalOverride -PathType Leaf) { $selected.Add([System.IO.Path]::GetFullPath($globalOverride)) }
    elseif (Test-Path -LiteralPath $globalAgent -PathType Leaf) { $selected.Add([System.IO.Path]::GetFullPath($globalAgent)) }

    foreach ($directory in @(Get-DirectoryChain -ProjectRoot $ProjectRoot -CurrentWorkingDirectory $CurrentWorkingDirectory)) {
        $candidates = @((Join-Path $directory 'AGENTS.override.md'), (Join-Path $directory 'AGENTS.md')) + @($config.fallback_names | ForEach-Object { Join-Path $directory $_ })
        $match = @($candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1)
        if ($match.Count -gt 0) { $selected.Add([System.IO.Path]::GetFullPath($match[0])) }
    }

    $result = [System.Collections.Generic.List[string]]::new()
    $bytes = 0
    foreach ($path in $selected) {
        $length = (Get-Item -LiteralPath $path).Length
        if ($bytes + $length -gt $config.project_doc_max_bytes) { break }
        $result.Add($path); $bytes += $length
    }
    $result
}

function Get-DefaultReferenceSearchRoot {
    param([string]$ProjectRoot, [string]$CurrentWorkingDirectory, [string]$HomeRoot, [string]$ConfigPath)
    $candidates = @(
        $ConfigPath,
        (Join-Path $HomeRoot '.codex\skills'),
        (Join-Path $HomeRoot '.agents\skills')
    )
    foreach ($directory in @(Get-DirectoryChain -ProjectRoot $ProjectRoot -CurrentWorkingDirectory $CurrentWorkingDirectory)) {
        $candidates += (Join-Path $directory '.codex\skills'), (Join-Path $directory '.agents\skills')
    }
    $candidates += @(Get-ApplicableInstructionPath -ProjectRoot $ProjectRoot -CurrentWorkingDirectory $CurrentWorkingDirectory -HomeRoot $HomeRoot -ConfigPath $ConfigPath)
    @($candidates | Where-Object { Test-Path -LiteralPath $_ } | ForEach-Object { [System.IO.Path]::GetFullPath($_) } | Sort-Object -Unique)
}

function Get-ContextFingerprint {
    [CmdletBinding()]
    param(
        [string]$ProjectRoot = (Get-Location).Path,
        [string]$CurrentWorkingDirectory = (Get-Location).Path,
        [string]$HomeRoot = $HOME,
        [string]$ConfigPath = (Join-Path $HOME '.codex\config.toml'),
        [string[]]$AdditionalPath = @()
    )
    $paths = [System.Collections.Generic.List[string]]::new()
    foreach ($path in @(
        $ConfigPath
    ) + @(Get-ApplicableInstructionPath -ProjectRoot $ProjectRoot -CurrentWorkingDirectory $CurrentWorkingDirectory -HomeRoot $HomeRoot -ConfigPath $ConfigPath) + @($AdditionalPath)) {
        if (-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path -LiteralPath $path -PathType Leaf)) { $paths.Add([System.IO.Path]::GetFullPath($path)) }
    }
    $entries = @("engine:$script:EngineVersion", "project:$(Get-NormalizedPath -Path $ProjectRoot)", "cwd:$(Get-NormalizedPath -Path $CurrentWorkingDirectory)")
    foreach ($path in @($paths | Sort-Object -Unique)) { $entries += ((Get-NormalizedPath -Path $path) + ':' + (Get-FileSha256 -Path $path)) }
    Get-StableHash -Text ($entries -join "`n")
}

function Get-DefaultStatePath {
    [CmdletBinding()]
    param(
        [string]$ProjectRoot = (Get-Location).Path,
        [string]$StateRoot = (Join-Path $HOME '.codex\state\skill-stocktake')
    )
    $key = (Get-StableHash -Text (Get-NormalizedPath -Path $ProjectRoot)).Substring(0, 16)
    Join-Path (Join-Path $StateRoot $key) 'results.json'
}

function Convert-SkillsObjectToMap {
    param($SkillsObject)
    $map = [ordered]@{}
    if ($null -eq $SkillsObject) { return $map }
    if ($SkillsObject -is [System.Collections.IDictionary]) {
        foreach ($key in $SkillsObject.Keys) { $map[[string]$key] = $SkillsObject[$key] }
    } else {
        foreach ($property in $SkillsObject.PSObject.Properties) { $map[$property.Name] = $property.Value }
    }
    $map
}

function Compare-SkillInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Inventory,
        $State,
        [Parameter(Mandatory)][string]$ContextSha256,
        [DateTime]$Now = [DateTime]::UtcNow
    )
    $added = [System.Collections.Generic.List[string]]::new()
    $changed = [System.Collections.Generic.List[string]]::new()
    $expired = [System.Collections.Generic.List[string]]::new()
    $contextChanged = [System.Collections.Generic.List[string]]::new()
    $removed = [System.Collections.Generic.List[string]]::new()
    $unchanged = [System.Collections.Generic.List[string]]::new()
    $previous = [ordered]@{}
    if ($null -ne $State -and $State.schema_version -eq $script:SchemaVersion -and $null -ne $State.last_completed) {
        $previous = Convert-SkillsObjectToMap -SkillsObject $State.last_completed.skills
    }
    $currentIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($skill in @($Inventory.skills)) {
        [void]$currentIds.Add($skill.logical_id)
        if (-not $previous.Contains($skill.logical_id)) { $added.Add($skill.logical_id); continue }
        $old = $previous[$skill.logical_id]
        if ([string]$old.bundle_sha256 -ne [string]$skill.bundle_sha256) { $changed.Add($skill.logical_id); continue }
        $oldContext = if ($old.PSObject.Properties.Name -contains 'context_sha256') { [string]$old.context_sha256 } elseif ($State.last_completed.PSObject.Properties.Name -contains 'context_sha256') { [string]$State.last_completed.context_sha256 } else { '' }
        if ($oldContext -ne $ContextSha256) { $contextChanged.Add($skill.logical_id); continue }
        $expires = [DateTime]::MinValue
        if (-not [DateTime]::TryParse([string]$old.review_expires_at, [ref]$expires) -or $expires.ToUniversalTime() -le $Now.ToUniversalTime()) { $expired.Add($skill.logical_id); continue }
        $unchanged.Add($skill.logical_id)
    }
    foreach ($id in $previous.Keys) { if (-not $currentIds.Contains([string]$id)) { $removed.Add([string]$id) } }
    $pending = @($added + $changed + $expired + $contextChanged | Sort-Object -Unique)
    $template = [ordered]@{}
    foreach ($id in $pending) {
        $skill = @($Inventory.skills | Where-Object logical_id -eq $id)[0]
        $template[$id] = [pscustomobject][ordered]@{
            logical_id = $id; logical_name = $skill.logical_name; bundle_sha256 = $skill.bundle_sha256; context_sha256 = $ContextSha256
            verdict = $null; confidence = $null; reason = $null; evidence = @(); reviewed_resources = @(); uncertainties = @(); proposal = $null
        }
    }
    [pscustomobject][ordered]@{
        schema_version = $script:SchemaVersion; project_root = $Inventory.project_root; inventory_sha256 = $Inventory.inventory_sha256; context_sha256 = $ContextSha256
        added = $added; changed = $changed; expired = $expired; context_changed = $contextChanged; removed = $removed; unchanged = $unchanged; pending_ids = $pending; evaluation_template = [pscustomobject]$template
    }
}

function Get-StocktakeRecordErrors {
    param([Parameter(Mandatory)][string]$Id, [Parameter(Mandatory)]$Record)
    $errors = [System.Collections.Generic.List[string]]::new()
    $properties = @($Record.PSObject.Properties.Name)
    $verdict = if ($properties -contains 'verdict') { [string]$Record.verdict } else { '' }
    $confidence = if ($properties -contains 'confidence') { [string]$Record.confidence } else { '' }
    $reason = if ($properties -contains 'reason') { [string]$Record.reason } else { '' }
    $evidence = @()
    if ($properties -contains 'evidence') { $evidence = @($Record.evidence) }

    if ($verdict -notmatch '^(Keep|Improve|Update|Retire|Merge into .+)$') { $errors.Add("Record '$Id' has an invalid verdict.") }
    if ($confidence -notin @('high', 'medium', 'low')) { $errors.Add("Record '$Id' has invalid confidence.") }
    if ([string]::IsNullOrWhiteSpace($reason)) { $errors.Add("Record '$Id' requires a reason.") }
    if ($evidence.Count -eq 0) { $errors.Add("Record '$Id' requires evidence.") }

    foreach ($field in @('logical_id', 'logical_name', 'bundle_sha256', 'context_sha256', 'dimensions', 'reviewed_resources', 'uncertainties', 'reviewed_at', 'review_expires_at')) {
        if ($properties -notcontains $field) { $errors.Add("Record '$Id' requires '$field'.") }
    }
    if ($properties -contains 'logical_id' -and [string]$Record.logical_id -ne $Id) { $errors.Add("Record '$Id' has a mismatched logical_id.") }
    foreach ($field in @('bundle_sha256', 'context_sha256')) {
        if ($properties -contains $field -and [string]::IsNullOrWhiteSpace([string]$Record.$field)) { $errors.Add("Record '$Id' requires a non-empty '$field'.") }
    }
    if ($properties -contains 'reviewed_resources' -and @($Record.reviewed_resources).Count -eq 0) { $errors.Add("Record '$Id' requires at least one reviewed resource.") }
    foreach ($entry in $evidence) {
        $entryProperties = @($entry.PSObject.Properties.Name)
        if ($entryProperties -notcontains 'type' -or [string]::IsNullOrWhiteSpace([string]$entry.type) -or $entryProperties -notcontains 'detail' -or [string]::IsNullOrWhiteSpace([string]$entry.detail)) {
            $errors.Add("Record '$Id' contains incomplete evidence.")
        }
        if ($entryProperties -contains 'type' -and [string]$entry.type -notin @('file', 'test', 'runtime', 'primary_source', 'usage', 'dependency', 'collision', 'uncertainty', 'fixture')) {
            $errors.Add("Record '$Id' contains unknown evidence type '$($entry.type)'.")
        }
    }

    $dimensionNames = @('trigger_accuracy', 'actionability', 'integrity', 'scope_concision', 'uniqueness_overlap', 'currency', 'dependency_safety', 'maintainability', 'usefulness')
    if ($properties -contains 'dimensions' -and $null -ne $Record.dimensions) {
        $dimensionProperties = @($Record.dimensions.PSObject.Properties.Name)
        foreach ($dimension in $dimensionNames) {
            if ($dimensionProperties -notcontains $dimension -or [string]$Record.dimensions.$dimension -notin @('pass', 'concern', 'fail', 'unknown')) {
                $errors.Add("Record '$Id' has invalid or missing dimension '$dimension'.")
            } elseif ([string]$Record.dimensions.$dimension -ne 'pass') {
                $mapped = @($evidence | Where-Object {
                    ($_.PSObject.Properties.Name -contains 'dimension' -and [string]$_.dimension -eq $dimension) -or
                    ($_.PSObject.Properties.Name -contains 'dimensions' -and @($_.dimensions) -contains $dimension)
                }).Count -gt 0
                if (-not $mapped) { $errors.Add("Record '$Id' requires evidence mapped to non-pass dimension '$dimension'.") }
            }
        }
    }

    $reviewedAt = [DateTime]::MinValue
    $expiresAt = [DateTime]::MinValue
    $reviewedValid = $properties -contains 'reviewed_at' -and [DateTime]::TryParse([string]$Record.reviewed_at, [ref]$reviewedAt)
    $expiresValid = $properties -contains 'review_expires_at' -and [DateTime]::TryParse([string]$Record.review_expires_at, [ref]$expiresAt)
    if (-not $reviewedValid) { $errors.Add("Record '$Id' has invalid reviewed_at.") }
    if (-not $expiresValid) { $errors.Add("Record '$Id' has invalid review_expires_at.") }
    if ($reviewedValid -and $expiresValid -and $expiresAt.ToUniversalTime() -le $reviewedAt.ToUniversalTime()) { $errors.Add("Record '$Id' review_expires_at must be later than reviewed_at.") }
    if ($reviewedValid -and $expiresValid -and $expiresAt.ToUniversalTime() -gt $reviewedAt.ToUniversalTime().AddDays(365)) { $errors.Add("Record '$Id' review window cannot exceed 365 days.") }

    if ($verdict -ne 'Keep' -and ($properties -notcontains 'proposal' -or $null -eq $Record.proposal)) { $errors.Add("Record '$Id' requires a proposal for verdict '$verdict'.") }
    if ($verdict -ne 'Keep' -and $properties -contains 'proposal' -and $null -ne $Record.proposal) {
        $proposalProperties = @($Record.proposal.PSObject.Properties.Name)
        foreach ($field in @('change', 'verification')) {
            if ($proposalProperties -notcontains $field -or [string]::IsNullOrWhiteSpace([string]$Record.proposal.$field)) { $errors.Add("Record '$Id' proposal requires non-empty '$field'.") }
        }
    }
    if ($confidence -eq 'high') {
        if ($properties -contains 'uncertainties' -and @($Record.uncertainties).Count -gt 0) { $errors.Add("Record '$Id' cannot have high confidence with unresolved uncertainties.") }
        if ($properties -contains 'dimensions' -and @($dimensionNames | Where-Object { [string]$Record.dimensions.$_ -eq 'unknown' }).Count -gt 0) { $errors.Add("Record '$Id' cannot have high confidence with unknown dimensions.") }
    }
    if ($verdict -eq 'Retire' -or $verdict -like 'Merge into *') {
        foreach ($field in @('dependencies', 'replacement', 'removal_impact')) {
            if ($properties -notcontains $field) { $errors.Add("Record '$Id' requires '$field' for merge or retirement.") }
        }
    }
    $errors
}

function Test-StocktakeState {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$State, [switch]$AllowIncomplete)
    $errors = [System.Collections.Generic.List[string]]::new()
    if ($null -eq $State) { $errors.Add('State is null.'); return [pscustomobject]@{ IsValid = $false; Errors = $errors } }
    if ($State.schema_version -ne $script:SchemaVersion) { $errors.Add("Unsupported schema_version '$($State.schema_version)'.") }
    if ([string]::IsNullOrWhiteSpace([string]$State.project_root)) { $errors.Add('project_root is required.') }
    $activeRun = if ($State.PSObject.Properties.Name -contains 'active_run') { $State.active_run } else { $null }
    $lastCompleted = if ($State.PSObject.Properties.Name -contains 'last_completed') { $State.last_completed } else { $null }
    if ($null -ne $activeRun) {
        $run = $activeRun
        if ([string]::IsNullOrWhiteSpace([string]$run.run_id)) { $errors.Add('active_run.run_id is required.') }
        if ([string]$run.mode -notin @('full', 'quick', 'resume')) { $errors.Add('active_run.mode is invalid.') }
        if ([string]$run.status -notin @('in_progress', 'completed')) { $errors.Add('active_run.status is invalid.') }
        foreach ($field in @('inventory_sha256', 'context_sha256', 'started_at', 'updated_at')) {
            if ($run.PSObject.Properties.Name -notcontains $field -or [string]::IsNullOrWhiteSpace([string]$run.$field)) { $errors.Add("active_run.$field is required.") }
        }
        $pending = @($run.pending_ids)
        $evaluated = @($run.evaluated_ids)
        if (@($pending | Group-Object | Where-Object Count -gt 1).Count -gt 0) { $errors.Add('active_run.pending_ids contains duplicates.') }
        if (@($evaluated | Group-Object | Where-Object Count -gt 1).Count -gt 0) { $errors.Add('active_run.evaluated_ids contains duplicates.') }
        if (@($pending | Where-Object { $evaluated -contains $_ }).Count -gt 0) { $errors.Add('An ID cannot be both pending and evaluated.') }
        if (-not $AllowIncomplete -or $run.status -eq 'completed') {
            if ($pending.Count -gt 0) { $errors.Add('Completed state cannot have pending IDs.') }
            $records = Convert-SkillsObjectToMap -SkillsObject $run.skills
            foreach ($id in $evaluated) {
                if (-not $records.Contains($id)) { $errors.Add("Missing evaluated record '$id'."); continue }
                foreach ($recordError in @(Get-StocktakeRecordErrors -Id ([string]$id) -Record $records[$id])) { $errors.Add($recordError) }
            }
            foreach ($recordId in $records.Keys) { if ($evaluated -notcontains $recordId) { $errors.Add("Record '$recordId' is not listed in evaluated_ids.") } }
        }
    } elseif ($null -eq $lastCompleted) {
        $errors.Add('State requires last_completed or active_run.')
    }
    if ($null -ne $lastCompleted) {
        $completedProperties = @($lastCompleted.PSObject.Properties.Name)
        foreach ($field in @('run_id', 'completed_at', 'inventory_sha256', 'context_sha256', 'diagnostics', 'skills')) {
            if ($completedProperties -notcontains $field) { $errors.Add("last_completed.$field is required.") }
        }
        $completedAt = [DateTime]::MinValue
        if ($completedProperties -contains 'completed_at' -and -not [DateTime]::TryParse([string]$lastCompleted.completed_at, [ref]$completedAt)) { $errors.Add('last_completed.completed_at is invalid.') }
        if ($completedProperties -contains 'skills') {
            $completedRecords = Convert-SkillsObjectToMap -SkillsObject $lastCompleted.skills
            foreach ($recordId in $completedRecords.Keys) {
                foreach ($recordError in @(Get-StocktakeRecordErrors -Id ([string]$recordId) -Record $completedRecords[$recordId])) { $errors.Add($recordError) }
            }
        }
    }
    [pscustomobject][ordered]@{ IsValid = ($errors.Count -eq 0); Errors = $errors }
}

function Merge-StocktakeState {
    [CmdletBinding()]
    param($ExistingState, [Parameter(Mandatory)]$IncomingState)
    if ($null -ne $ExistingState) {
        if ($ExistingState.schema_version -ne $IncomingState.schema_version) { throw 'Cannot merge incompatible schema versions.' }
        if ((Get-NormalizedPath -Path $ExistingState.project_root) -ne (Get-NormalizedPath -Path $IncomingState.project_root)) { throw 'Cannot merge state from a different project root.' }
        if ($null -ne $ExistingState.active_run -and $null -ne $IncomingState.active_run -and $ExistingState.active_run.run_id -ne $IncomingState.active_run.run_id) {
            throw 'Incoming run_id does not match the active run.'
        }
    }
    $validation = Test-StocktakeState -State $IncomingState -AllowIncomplete
    if (-not $validation.IsValid) { throw ('Invalid incoming state: ' + (@($validation.Errors) -join '; ')) }
    $lastCompleted = if ($null -ne $ExistingState) { $ExistingState.last_completed } else { $IncomingState.last_completed }
    $active = $IncomingState.active_run
    if ($null -ne $active -and $active.status -eq 'completed') {
        $records = Convert-SkillsObjectToMap -SkillsObject $active.skills
        if ($active.mode -in @('quick', 'resume') -and $null -ne $lastCompleted) {
            $carried = Convert-SkillsObjectToMap -SkillsObject $lastCompleted.skills
            foreach ($id in $records.Keys) { $carried[$id] = $records[$id] }
            foreach ($id in @($active.removed_ids)) { [void]$carried.Remove([string]$id) }
            $records = $carried
        }
        $lastCompleted = [pscustomobject][ordered]@{
            run_id = $active.run_id; completed_at = [DateTime]::UtcNow.ToString('o'); inventory_sha256 = $active.inventory_sha256; context_sha256 = $active.context_sha256; diagnostics = @($active.diagnostics); skills = [pscustomobject]$records
        }
        $active = $null
    }
    $output = [pscustomobject][ordered]@{
        schema_version = $script:SchemaVersion
        engine_version = $script:EngineVersion
        project_root = [System.IO.Path]::GetFullPath($IncomingState.project_root)
        updated_at = [DateTime]::UtcNow.ToString('o')
        last_completed = $lastCompleted
        active_run = $active
    }
    $outputValidation = Test-StocktakeState -State $output -AllowIncomplete
    if (-not $outputValidation.IsValid) { throw ('Merged state is invalid: ' + (@($outputValidation.Errors) -join '; ')) }
    $output
}

function New-StocktakeRun {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Work, [string]$RunId = ([guid]::NewGuid().ToString()), [DateTime]$Now = [DateTime]::UtcNow)
    $mode = [string]$Work.suggested_mode
    if ($mode -notin @('full', 'quick', 'resume')) { throw "Unsupported suggested mode '$mode'." }
    $pending = @($Work.diff.pending_ids)
    [pscustomobject][ordered]@{
        schema_version = $script:SchemaVersion
        project_root = $Work.inventory.project_root
        last_completed = if ($Work.PSObject.Properties.Name -contains 'state' -and $null -ne $Work.state) { $Work.state.last_completed } else { $null }
        active_run = [pscustomobject][ordered]@{
            run_id = if ($mode -eq 'resume' -and $Work.PSObject.Properties.Name -contains 'active_run_id') { $Work.active_run_id } else { $RunId }
            mode = $mode
            status = 'in_progress'
            started_at = $Now.ToUniversalTime().ToString('o')
            updated_at = $Now.ToUniversalTime().ToString('o')
            inventory_sha256 = $Work.inventory.inventory_sha256
            context_sha256 = $Work.context_sha256
            pending_ids = $pending
            evaluated_ids = @()
            removed_ids = @($Work.diff.removed)
            diagnostics = @($Work.inventory.diagnostics)
            skills = [pscustomobject][ordered]@{}
        }
    }
}

function Format-StocktakeReport {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$State, [Parameter(Mandatory)]$Inventory)
    $generation = if ($null -ne $State.last_completed) { $State.last_completed } else { $State.active_run }
    if ($null -eq $generation) { throw 'State has no reportable generation.' }
    $records = Convert-SkillsObjectToMap -SkillsObject $generation.skills
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('# Skill Stocktake Report')
    $lines.Add('')
    $lines.Add("Coverage: $(@($Inventory.skills).Count) logical skills; $(@($Inventory.diagnostics).Count) diagnostics.")
    $lines.Add('')
    $lines.Add('| Skill | Source | Ownership | 7-day sessions | Verdict | Confidence | Reason |')
    $lines.Add('|---|---|---|---:|---|---|---|')
    $ordered = @($records.Values | Sort-Object @{ Expression = { if ($_.verdict -match '^(Retire|Merge)') { 0 } elseif ($_.verdict -in @('Update','Improve')) { 1 } elseif ($_.confidence -eq 'low') { 2 } else { 3 } } }, logical_name)
    foreach ($record in $ordered) {
        $skill = @($Inventory.skills | Where-Object logical_id -eq $record.logical_id | Select-Object -First 1)
        $source = if ($skill.Count -gt 0) { $skill[0].source } else { 'removed' }
        $ownership = if ($skill.Count -gt 0) { $skill[0].ownership } else { 'unknown' }
        $sessions = if ($skill.Count -gt 0) { $skill[0].usage.unique_sessions_7d } else { 0 }
        $reason = ([string]$record.reason).Replace('|', '\|').Replace("`r", ' ').Replace("`n", ' ')
        $lines.Add("| $($record.logical_name) | $source | $ownership | $sessions | $($record.verdict) | $($record.confidence) | $reason |")
    }
    $lines -join [Environment]::NewLine
}

Export-ModuleMember -Function ConvertFrom-SkillFrontmatter, Get-StableHash, Get-BundleFingerprint, Get-ManagedSkillRoots, Get-SkillInventory, Add-SkillUsage, Add-SkillReverseReferences, Get-ApplicableInstructionPath, Get-ContextFingerprint, Get-DefaultStatePath, Compare-SkillInventory, Test-StocktakeState, Merge-StocktakeState, New-StocktakeRun, Format-StocktakeReport
