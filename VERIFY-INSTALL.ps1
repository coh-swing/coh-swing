[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TargetRepo,

    [string]$KitRoot = $PSScriptRoot
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

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Read-Text([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing required file: $Path"
    }
    return [IO.File]::ReadAllText($Path)
}

$target = Resolve-Directory $TargetRepo 'TargetRepo'
$kit = Resolve-Directory $KitRoot 'KitRoot'

$assetManifestPath = Join-Path $kit 'integration\asset-manifest.json'
$sourceManifestPath = Join-Path $kit 'integration\manifest.json'
$patchPath = Join-Path $kit 'integration\webswing-v1.patch'

Assert-True (Test-Path -LiteralPath $assetManifestPath -PathType Leaf) "Integration asset manifest has not been built: $assetManifestPath"
Assert-True (Test-Path -LiteralPath $sourceManifestPath -PathType Leaf) "Integration source manifest has not been built: $sourceManifestPath"
Assert-True (Test-Path -LiteralPath $patchPath -PathType Leaf) "Integration patch has not been built: $patchPath"

$assets = Get-Content -Raw -LiteralPath $assetManifestPath | ConvertFrom-Json
$source = Get-Content -Raw -LiteralPath $sourceManifestPath | ConvertFrom-Json

Assert-True ([int]$assets.animationCount -eq 29) "Expected 29 production animation dependencies in asset manifest."
Assert-True ([int]$assets.payloadFileCount -eq 35) "Expected 35 production payload files in asset manifest."

$badAssets = @()
foreach ($entry in @($assets.files)) {
    $path = Join-Path $target (([string]$entry.target) -replace '/', '\')
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $badAssets += "$($entry.target) (missing)"
        continue
    }
    $actual = Get-Sha256 $path
    $expected = ([string]$entry.sha256).ToLowerInvariant()
    if ($actual -ne $expected) {
        $badAssets += "$($entry.target) (hash mismatch)"
    }
}
Assert-True ($badAssets.Count -eq 0) ("Runtime payload validation failed:`n  " + ($badAssets -join "`n  "))

$player = Join-Path $target 'bin\data\sequencers\player.txt'
$playerText = Read-Text $player
$includeLine = [regex]::Escape([string]$assets.playerInclude)
$includeCount = [regex]::Matches($playerText, "(?im)^\s*$includeLine\s*$").Count
Assert-True ($includeCount -eq 1) "player.txt must contain exactly one '$($assets.playerInclude)' include; found $includeCount."

$include = Join-Path $target 'bin\data\sequencers\cohsourcedev_webswing.inc'
$includeText = Read-Text $include
Assert-True ($includeText -match 'COHSOURCEDEV_WEBSWING_MAIN_V1') 'Production sequencer does not reference COHSOURCEDEV_WEBSWING_MAIN_V1.'
Assert-True ($includeText -match '(?i)NINJA_HOP\s+82\s+98') 'Exact production front-flip window NINJA_HOP 82 98 is missing.'
Assert-True ($includeText -match '(?i)NINJA_JUMP\s+66\s+88') 'Exact production back-flip window NINJA_JUMP 66 88 is missing.'

$toggleSource = Read-Text (Join-Path $target 'MapServer\src\entity\entGameActions.c')
$backendPos = $toggleSource.IndexOf('setWebSwingBackend(e, 1)', [StringComparison]::Ordinal)
$enablePos = $toggleSource.IndexOf('setWebSwing(e, 1)', [StringComparison]::Ordinal)
Assert-True ($backendPos -ge 0) 'Production toggle is missing setWebSwingBackend(e, 1).'
Assert-True ($enablePos -ge 0) 'Production toggle is missing setWebSwing(e, 1).'
Assert-True ($backendPos -lt $enablePos) 'Production toggle must queue Sky-Assisted before enabling Web Swing.'

$clientCmd = Read-Text (Join-Path $target 'Game\src\cmdparse\cmdgame.c')
Assert-True ($clientCmd -match '(?i)webswingstyle') 'Client command source does not expose webswingstyle.'

$tray = Read-Text (Join-Path $target 'Game\src\UI\uiTray.c')
Assert-True ($tray -match '(?i)Web Swing') 'Tray source does not contain the Web Swing player-facing control.'

$icon = Join-Path $target 'bin\data\texture_library\GUI\Icons\COHSOURCEDEV_WebSwing_WebIcon.texture'
$bytes = [IO.File]::ReadAllBytes($icon)
Assert-True ($bytes.Length -ge 20) 'Production tray icon is too short.'
$width = [BitConverter]::ToInt32($bytes, 8)
$height = [BitConverter]::ToInt32($bytes, 12)
$flags = [BitConverter]::ToInt32($bytes, 16)
Assert-True ($width -eq 32 -and $height -eq 32) "Production tray icon must be 32x32; found ${width}x${height}."
Assert-True ($flags -eq 0x100c2) ("Production tray icon flags must be 0x100c2; found 0x{0:x}." -f $flags)

# Verify that the source patch is now reverse-applicable. This is a clean,
# cheap signal that the target contains the complete generated source delta.
$reverse = @(& git -C $target apply --reverse --check $patchPath 2>&1)
$reverseCode = $LASTEXITCODE
Assert-True ($reverseCode -eq 0) ("Installed source does not match the generated Web Swing patch:`n" + ($reverse -join "`n"))

Write-Host ''
Write-Host 'WEB SWING INSTALL VERIFY PASS'
Write-Host ("  source patch ......... PASS ({0} files)" -f [int]$source.sourceFileCount)
Write-Host ("  runtime payload ...... PASS ({0} files)" -f [int]$assets.payloadFileCount)
Write-Host '  production animations  PASS (29)'
Write-Host '  player include ........ PASS'
Write-Host '  exact flips ........... PASS'
Write-Host '  Sky-before-enable ..... PASS'
Write-Host '  visual style command .. PASS'
Write-Host '  tray integration ...... PASS'
Write-Host '  icon 32x32/flags ...... PASS'
