[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TargetRepo,

    [string]$KitRoot = $PSScriptRoot,

    [switch]$Plan,
    [switch]$AllowDirty,
    [switch]$SkipVerify
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-Directory([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "$Label does not exist or is not a directory: $Path"
    }
    return (Resolve-Path -LiteralPath $Path).Path
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Invoke-Git {
    param(
        [Parameter(Mandatory = $true)][string]$Repo,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& git -C $Repo @Arguments 2>&1)
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    return [pscustomobject]@{ ExitCode = $code; Output = $output }
}

function Write-Utf8NoBom([string]$Path, [string]$Text) {
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    $enc = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($Path, $Text, $enc)
}

function Add-PlayerInclude([string]$PlayerPath, [string]$Include) {
    $bytes = [IO.File]::ReadAllBytes($PlayerPath)
    $text = [Text.Encoding]::UTF8.GetString($bytes)
    $pattern = "(?im)^\s*" + [regex]::Escape($Include) + "\s*$"
    $count = [regex]::Matches($text, $pattern).Count
    if ($count -gt 1) {
        throw "player.txt already contains $count copies of '$Include'. Refusing to guess which duplicate to keep."
    }
    if ($count -eq 1) { return $false }

    $newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $prefix = if ($bytes.Length -eq 0 -or $text.EndsWith("`n")) { '' } else { $newline }
    $append = [Text.Encoding]::ASCII.GetBytes($prefix + $Include + $newline)
    $stream = [IO.File]::Open($PlayerPath, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::Read)
    try { $stream.Write($append, 0, $append.Length) }
    finally { $stream.Dispose() }
    return $true
}

function Get-GitDir([string]$Repo) {
    $r = Invoke-Git -Repo $Repo -Arguments @('rev-parse','--git-dir')
    if ($r.ExitCode -ne 0 -or $r.Output.Count -eq 0) {
        throw "TargetRepo is not a Git working tree: $Repo"
    }
    $raw = [string]$r.Output[0]
    if ([IO.Path]::IsPathRooted($raw)) { return [IO.Path]::GetFullPath($raw) }
    return [IO.Path]::GetFullPath((Join-Path $Repo $raw))
}

function Get-ComponentReport([string]$Repo, [object[]]$Components, [string]$Kit) {
    $rows = @()
    foreach ($component in $Components) {
        $patch = Join-Path $Kit (([string]$component.patch) -replace '/', '\')
        if (-not (Test-Path -LiteralPath $patch -PathType Leaf) -or (Get-Item -LiteralPath $patch).Length -eq 0) {
            $rows += [pscustomobject]@{ id=$component.id; status='NO_CHANGES'; detail='' }
            continue
        }
        $reverse = Invoke-Git -Repo $Repo -Arguments @('apply','--reverse','--check',$patch)
        if ($reverse.ExitCode -eq 0) {
            $rows += [pscustomobject]@{ id=$component.id; status='ALREADY'; detail='' }
            continue
        }
        $normal = Invoke-Git -Repo $Repo -Arguments @('apply','--check',$patch)
        if ($normal.ExitCode -eq 0) {
            $rows += [pscustomobject]@{ id=$component.id; status='APPLIES'; detail='' }
            continue
        }
        $three = Invoke-Git -Repo $Repo -Arguments @('apply','--3way','--check',$patch)
        if ($three.ExitCode -eq 0) {
            $rows += [pscustomobject]@{ id=$component.id; status='3WAY'; detail='' }
            continue
        }
        $detail = (($normal.Output + $three.Output) | Select-Object -Unique | Select-Object -First 12) -join "`n"
        $rows += [pscustomobject]@{ id=$component.id; status='CONFLICT'; detail=$detail }
    }
    return $rows
}

$target = Resolve-Directory $TargetRepo 'TargetRepo'
$kit = Resolve-Directory $KitRoot 'KitRoot'
$gitDir = Get-GitDir $target

foreach ($anchor in @(
    'Common',
    'Game',
    'MapServer',
    'Common\entity\entworldcoll.c',
    'Game\src\UI\uiTray.c',
    'MapServer\src\entity\entGameActions.c'
)) {
    if (-not (Test-Path -LiteralPath (Join-Path $target $anchor))) {
        throw "Target does not look like the expected City of Heroes source tree; missing: $anchor"
    }
}

$manifestPath = Join-Path $kit 'integration\manifest.json'
$assetManifestPath = Join-Path $kit 'integration\asset-manifest.json'
$patchPath = Join-Path $kit 'integration\webswing-v1.patch'
$verifyPath = Join-Path $kit 'VERIFY-INSTALL.ps1'

foreach ($required in @($manifestPath,$assetManifestPath,$patchPath,$verifyPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "The Web Swing package is incomplete; missing required file: $required"
    }
}
if ((Get-Item -LiteralPath $patchPath).Length -eq 0) {
    throw 'The integration source patch is empty.'
}

$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
$assets = Get-Content -Raw -LiteralPath $assetManifestPath | ConvertFrom-Json

$patchHash = Get-Sha256 $patchPath
if ($patchHash -ne ([string]$manifest.patchSha256).ToLowerInvariant()) {
    throw 'Integration patch hash does not match integration/manifest.json.'
}

$trackedStatus = Invoke-Git -Repo $target -Arguments @('status','--porcelain','--untracked-files=no')
if ($trackedStatus.ExitCode -ne 0) {
    throw "Unable to inspect target Git status:`n$($trackedStatus.Output -join "`n")"
}
$dirty = @($trackedStatus.Output | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
if ($dirty.Count -gt 0 -and -not $AllowDirty) {
    throw "Target has tracked changes. Commit/stash them first, or explicitly re-run with -AllowDirty.`n$($dirty -join "`n")"
}

$playerPath = Join-Path $target 'bin\data\sequencers\player.txt'
if (-not (Test-Path -LiteralPath $playerPath -PathType Leaf)) {
    throw "Runtime player sequencer is missing: $playerPath`nInstall/materialize your normal CoH runtime data before installing Web Swing."
}

# Validate payload before touching the target.
$payloadProblems = @()
foreach ($entry in @($assets.files)) {
    $src = Join-Path $kit ('integration\payload\' + (([string]$entry.target) -replace '/', '\'))
    if (-not (Test-Path -LiteralPath $src -PathType Leaf)) {
        $payloadProblems += "$($entry.target) (missing from kit)"
        continue
    }
    $actual = Get-Sha256 $src
    if ($actual -ne ([string]$entry.sha256).ToLowerInvariant()) {
        $payloadProblems += "$($entry.target) (kit hash mismatch)"
    }
}
if ($payloadProblems.Count -gt 0) {
    throw "Integration payload is incomplete or corrupt:`n  $($payloadProblems -join "`n  ")"
}

$reverse = Invoke-Git -Repo $target -Arguments @('apply','--reverse','--check',$patchPath)
$sourceAlreadyInstalled = ($reverse.ExitCode -eq 0)
$applyMode = 'ALREADY'

if (-not $sourceAlreadyInstalled) {
    $normal = Invoke-Git -Repo $target -Arguments @('apply','--check',$patchPath)
    if ($normal.ExitCode -eq 0) {
        $applyMode = 'NORMAL'
    }
    else {
        $three = Invoke-Git -Repo $target -Arguments @('apply','--3way','--check',$patchPath)
        if ($three.ExitCode -eq 0) {
            $applyMode = '3WAY'
        }
        else {
            $componentRows = @(Get-ComponentReport -Repo $target -Components @($manifest.components) -Kit $kit)
            $reportDir = Join-Path $gitDir 'coh-swing\reports'
            New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
            $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
            $reportPath = Join-Path $reportDir "port-report-$stamp.md"
            $head = (Invoke-Git -Repo $target -Arguments @('rev-parse','HEAD')).Output[0]
            $branchResult = Invoke-Git -Repo $target -Arguments @('branch','--show-current')
            $branch = if ($branchResult.Output.Count) { [string]$branchResult.Output[0] } else { '(detached)' }

            $md = New-Object System.Collections.Generic.List[string]
            $md.Add('# Web Swing port report')
            $md.Add('')
            $md.Add("- Target HEAD: $head")
            $md.Add("- Target branch: $branch")
            $md.Add("- Web Swing kit version: $($manifest.featureVersion)")
            $md.Add('')
            $md.Add('No source or runtime files were changed. The full patch could not be applied safely.')
            $md.Add('')
            $md.Add('| Component | Result |')
            $md.Add('|---|---|')
            foreach ($row in $componentRows) {
                $md.Add("| $($row.id) | $($row.status) |")
            }
            $md.Add('')
            foreach ($row in $componentRows | Where-Object { $_.status -eq 'CONFLICT' }) {
                $md.Add("## $($row.id)")
                $md.Add('```text')
                $md.Add([string]$row.detail)
                $md.Add('```')
                $md.Add('')
            }
            $md.Add('Use the component result to merge only the conflicting subsystem(s). Do not copy whole source files over a divergent fork.')
            Write-Utf8NoBom $reportPath (($md -join "`n") + "`n")
            throw "Web Swing does not apply cleanly to this fork. Nothing was changed.`nPort report: $reportPath"
        }
    }
}

Write-Host ''
Write-Host 'WEB SWING INSTALL PLAN'
Write-Host ("  target ............... {0}" -f $target)
Write-Host ("  version .............. {0}" -f $manifest.featureVersion)
Write-Host ("  source mode .......... {0}" -f $applyMode)
Write-Host ("  source files ......... {0}" -f $manifest.sourceFileCount)
Write-Host ("  runtime files ........ {0}" -f $assets.payloadFileCount)
Write-Host ("  animations ........... {0}" -f $assets.animationCount)
Write-Host ("  target dirty ......... {0}" -f ($dirty.Count -gt 0))
Write-Host ''

if ($Plan) {
    Write-Host 'PLAN ONLY - no files changed.'
    exit 0
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupRoot = Join-Path $gitDir "coh-swing\backups\$stamp"
New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null

$backupRecords = New-Object System.Collections.Generic.List[object]

function Backup-TargetFile([string]$Relative) {
    $normalized = $Relative -replace '/', '\'
    $src = Join-Path $target $normalized
    $dst = Join-Path $backupRoot $normalized
    $exists = Test-Path -LiteralPath $src -PathType Leaf
    if ($exists) {
        $parent = Split-Path -Parent $dst
        if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
            New-Item -ItemType Directory -Force -Path $parent | Out-Null
        }
        Copy-Item -LiteralPath $src -Destination $dst -Force
    }
    $script:backupRecords.Add([pscustomobject]@{
        relative = ($Relative -replace '\\','/')
        existed = [bool]$exists
        backup = if ($exists) { $dst } else { $null }
    })
}
$script:backupRecords = $backupRecords

$seen = @{}
foreach ($entry in @($manifest.sourceFiles)) {
    $rel = [string]$entry.path
    if (-not $seen.ContainsKey($rel)) {
        Backup-TargetFile $rel
        $seen[$rel] = $true
    }
}
foreach ($entry in @($assets.files)) {
    $rel = [string]$entry.target
    if (-not $seen.ContainsKey($rel)) {
        Backup-TargetFile $rel
        $seen[$rel] = $true
    }
}
$playerRel = 'bin/data/sequencers/player.txt'
if (-not $seen.ContainsKey($playerRel)) {
    Backup-TargetFile $playerRel
    $seen[$playerRel] = $true
}

function Restore-Backups {
    foreach ($record in @($script:backupRecords)) {
        $dst = Join-Path $target (([string]$record.relative) -replace '/', '\')
        if ([bool]$record.existed) {
            $parent = Split-Path -Parent $dst
            if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
                New-Item -ItemType Directory -Force -Path $parent | Out-Null
            }
            Copy-Item -LiteralPath ([string]$record.backup) -Destination $dst -Force
        }
        elseif (Test-Path -LiteralPath $dst -PathType Leaf) {
            Remove-Item -LiteralPath $dst -Force
        }
    }
}

try {
    if (-not $sourceAlreadyInstalled) {
        $args = if ($applyMode -eq '3WAY') { @('apply','--3way',$patchPath) } else { @('apply',$patchPath) }
        $applied = Invoke-Git -Repo $target -Arguments $args
        if ($applied.ExitCode -ne 0) {
            throw "Source patch failed unexpectedly after preflight:`n$($applied.Output -join "`n")"
        }
    }

    foreach ($entry in @($assets.files)) {
        $rel = [string]$entry.target
        $src = Join-Path $kit ('integration\payload\' + ($rel -replace '/', '\'))
        $dst = Join-Path $target ($rel -replace '/', '\')
        $parent = Split-Path -Parent $dst
        if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
            New-Item -ItemType Directory -Force -Path $parent | Out-Null
        }
        Copy-Item -LiteralPath $src -Destination $dst -Force
    }

    $null = Add-PlayerInclude -PlayerPath $playerPath -Include ([string]$assets.playerInclude)

    if (-not $SkipVerify) {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $verifyPath -TargetRepo $target -KitRoot $kit
        if ($LASTEXITCODE -ne 0) {
            throw "VERIFY-INSTALL.ps1 failed with exit code $LASTEXITCODE"
        }
    }

    $head = (Invoke-Git -Repo $target -Arguments @('rev-parse','HEAD')).Output[0]
    $markerDir = Join-Path $gitDir 'coh-swing'
    New-Item -ItemType Directory -Force -Path $markerDir | Out-Null
    $marker = [ordered]@{
        feature = 'City of Heroes Web Swing'
        version = [string]$manifest.featureVersion
        installedAt = [DateTime]::UtcNow.ToString('o')
        targetHeadBeforeInstall = [string]$head
        sourceApplyMode = $applyMode
        patchSha256 = [string]$manifest.patchSha256
        payloadFileCount = [int]$assets.payloadFileCount
        backup = $backupRoot
    }
    Write-Utf8NoBom (Join-Path $markerDir 'install.json') (($marker | ConvertTo-Json -Depth 5) + "`n")

    Write-Host ''
    Write-Host 'WEB SWING INSTALL PASS'
    Write-Host 'Rebuild a matching Ouroboros client and MapServer from this source tree.'
    Write-Host 'Then launch normally and test /webswingtoggle.'
}
catch {
    Write-Warning "Install failed; restoring every source/runtime file touched by this run."
    Restore-Backups
    throw
}
