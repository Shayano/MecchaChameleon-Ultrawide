<#
  Install-Ultrawide.ps1
  MECCHA CHAMELEON - ultrawide (21:9 / 32:9) setup.

  Installs UE4SS + Amikiir's FOVControl mod and sets your resolution so the game
  fills an ultrawide screen without the zoomed-in / cropped view.

  This script DOWNLOADS its components from their official sources at runtime; it
  does not bundle third-party code. See README.md / LICENSE for credits.

  Usage:
    powershell -ExecutionPolicy Bypass -File .\Install-Ultrawide.ps1 [options]

  Options:
    -GameRoot <path>     Path to the "MECCHA CHAMELEON" folder (auto-detected via Steam if omitted)
    -ResX <int> -ResY <int>   Force a resolution (default: primary monitor's native resolution)
    -FullscreenMode <0|1|2>   0=exclusive, 1=borderless (default), 2=windowed
    -DefaultFov <60-140>      Starting FOV written for the first launch (default 110)
    -SkipResolution           Do not touch GameUserSettings.ini
    -KeepF7                   Keep FOVControl's redundant F7 "re-apply" hotkey (removed by default)
#>

[CmdletBinding()]
param(
    [string]$GameRoot,
    [int]$ResX = 0,
    [int]$ResY = 0,
    [ValidateSet(0,1,2)][int]$FullscreenMode = 1,
    [ValidateRange(60,140)][int]$DefaultFov = 110,
    [switch]$SkipResolution,
    [switch]$KeepF7
)

$ErrorActionPreference = "Stop"
$H = @{ "User-Agent" = "MecchaChameleon-Ultrawide-Installer" }

function Info($m){ Write-Host "[install] $m" -ForegroundColor Cyan }
function Ok($m){ Write-Host "[ok]      $m" -ForegroundColor Green }
function Warn($m){ Write-Host "[warn]    $m" -ForegroundColor Yellow }
function Die($m){ Write-Host "[error]   $m" -ForegroundColor Red; exit 1 }

# --- locate the game via Steam ------------------------------------------------
function Find-SteamPath {
    foreach ($k in @("HKCU:\Software\Valve\Steam","HKLM:\SOFTWARE\WOW6432Node\Valve\Steam","HKLM:\SOFTWARE\Valve\Steam")) {
        try {
            $p = (Get-ItemProperty -Path $k -ErrorAction Stop)
            $v = $p.SteamPath; if (-not $v) { $v = $p.InstallPath }
            if ($v -and (Test-Path $v)) { return ($v -replace '/','\') }
        } catch {}
    }
    return $null
}

function Find-GameRoot {
    $steam = Find-SteamPath
    if (-not $steam) { return $null }
    $libs = @($steam)
    $vdf = Join-Path $steam "steamapps\libraryfolders.vdf"
    if (Test-Path $vdf) {
        $txt = Get-Content -Raw $vdf
        foreach ($m in [regex]::Matches($txt, '"path"\s+"([^"]+)"')) {
            $libs += ($m.Groups[1].Value -replace '\\\\','\')
        }
    }
    foreach ($lib in ($libs | Select-Object -Unique)) {
        $cand = Join-Path $lib "steamapps\common\MECCHA CHAMELEON"
        if (Test-Path (Join-Path $cand "Chameleon\Binaries\Win64\PenguinHotel-Win64-Shipping.exe")) { return $cand }
    }
    return $null
}

if (-not $GameRoot) {
    Info "Locating MECCHA CHAMELEON via Steam..."
    $GameRoot = Find-GameRoot
}
if (-not $GameRoot) { Die "Could not find the game. Re-run with -GameRoot `"<path to MECCHA CHAMELEON>`"" }

$Win64 = Join-Path $GameRoot "Chameleon\Binaries\Win64"
$Exe   = Join-Path $Win64 "PenguinHotel-Win64-Shipping.exe"
if (-not (Test-Path $Exe)) { Die "Game executable not found under: $Win64" }
Ok "Game found: $GameRoot"

if (Get-Process -Name "PenguinHotel-Win64-Shipping" -ErrorAction SilentlyContinue) {
    Die "The game is running. Close it and run this script again."
}

# --- download + install UE4SS (MIT, official) --------------------------------
$ue4ssFallback = "https://github.com/UE4SS-RE/RE-UE4SS/releases/download/experimental-latest/UE4SS_v3.0.1-970-gbdef46ff.zip"
$ue4ssUrl = $ue4ssFallback
try {
    Info "Resolving the current UE4SS build (experimental-latest, UE5.6 capable)..."
    $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/UE4SS-RE/RE-UE4SS/releases/tags/experimental-latest" -Headers $H -TimeoutSec 30
    $a = $rel.assets | Where-Object { $_.name -match '^UE4SS_v.*\.zip$' -and $_.name -notmatch 'zDEV|zCustom|zMap' } | Select-Object -First 1
    if ($a) { $ue4ssUrl = $a.browser_download_url; Info "UE4SS asset: $($a.name)" }
} catch { Warn "GitHub API unreachable, using fallback UE4SS URL." }

$tmp = Join-Path $env:TEMP ("mc_uw_" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$zip = Join-Path $tmp "ue4ss.zip"
Info "Downloading UE4SS..."
Invoke-WebRequest -Uri $ue4ssUrl -Headers $H -OutFile $zip -TimeoutSec 240
if ((Get-Item $zip).Length -lt 1MB) { Die "UE4SS download looks too small, aborting." }
$ext = Join-Path $tmp "ue4ss_ext"
Expand-Archive -Path $zip -DestinationPath $ext -Force

$proxy = Get-ChildItem $ext -Recurse -Filter "dwmapi.dll" | Select-Object -First 1
if (-not $proxy) { Die "dwmapi.dll not found inside the UE4SS archive." }
$ue4ssSrc = Join-Path $proxy.DirectoryName "ue4ss"
if (-not (Test-Path $ue4ssSrc)) { Die "ue4ss\ folder not found next to dwmapi.dll in the UE4SS archive." }

# back up a pre-existing proxy dll if any
if (Test-Path (Join-Path $Win64 "dwmapi.dll")) {
    Copy-Item (Join-Path $Win64 "dwmapi.dll") (Join-Path $Win64 "dwmapi.dll.preUW.bak") -Force
    Warn "Existing dwmapi.dll backed up to dwmapi.dll.preUW.bak"
}
Info "Installing UE4SS into the game..."
Copy-Item $proxy.FullName (Join-Path $Win64 "dwmapi.dll") -Force
Copy-Item $ue4ssSrc (Join-Path $Win64 "ue4ss") -Recurse -Force
Ok "UE4SS installed"

# --- download FOVControl + UE5.6 signature fix (by Amikiir) -------------------
$fovBase = "https://raw.githubusercontent.com/TakoKylo/MecchaChameleon-FOVControl/main"
$modScripts = Join-Path $Win64 "ue4ss\Mods\FOVControl\Scripts"
$sigDir     = Join-Path $Win64 "ue4ss\UE4SS_Signatures"
New-Item -ItemType Directory -Force -Path $modScripts, $sigDir | Out-Null

Info "Downloading FOVControl (by Amikiir) + UE5.6 signature fix..."
$mainLua = Join-Path $modScripts "main.lua"
Invoke-WebRequest -Uri "$fovBase/FOVControl/Scripts/main.lua" -Headers $H -OutFile $mainLua -TimeoutSec 60
Invoke-WebRequest -Uri "$fovBase/UE4SS_Signatures/StaticConstructObject.lua" -Headers $H -OutFile (Join-Path $sigDir "StaticConstructObject.lua") -TimeoutSec 60
Set-Content -Path (Join-Path $Win64 "ue4ss\Mods\FOVControl\enabled.txt") -Value "" -NoNewline
if ((Get-Item $mainLua).Length -lt 2KB) { Die "FOVControl main.lua download looks wrong, aborting." }
Ok "FOVControl + signature fix installed"

# optional: remove the redundant F7 're-apply' hotkey (local edit, not redistributed)
if (-not $KeepF7) {
    $c = Get-Content -Raw $mainLua
    $n = [regex]::Replace($c, '(?m)^(\s*)RegisterKeyBind\(Key\.F7,.*$', '$1-- F7 re-apply hotkey removed by MecchaChameleon-Ultrawide setup')
    if ($n -ne $c) { Set-Content -Path $mainLua -Value $n -NoNewline; Info "Removed the redundant F7 hotkey (use -KeepF7 to keep it)." }
}

# starting FOV for the first launch
Set-Content -Path (Join-Path $Win64 "ue4ss\Mods\FOVControl\fov.txt") -Value ([string]$DefaultFov) -NoNewline

# --- set resolution -----------------------------------------------------------
if (-not $SkipResolution) {
    if ($ResX -le 0 -or $ResY -le 0) {
        try {
            Add-Type -AssemblyName System.Windows.Forms
            $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
            $ResX = $b.Width; $ResY = $b.Height
        } catch { Warn "Could not detect native resolution; pass -ResX/-ResY. Skipping resolution."; $ResX = 0 }
    }
    if ($ResX -gt 0 -and $ResY -gt 0) {
        $cfgDir = Join-Path $env:LOCALAPPDATA "Chameleon\Saved\Config\Windows"
        $cfg = Join-Path $cfgDir "GameUserSettings.ini"
        New-Item -ItemType Directory -Force -Path $cfgDir | Out-Null
        if (-not (Test-Path $cfg)) {
            @("[/Script/Engine.GameUserSettings]") | Set-Content -Path $cfg -Encoding UTF8
        } else {
            Copy-Item $cfg "$cfg.preUW.bak" -Force
        }
        $lines = Get-Content $cfg
        $kv = [ordered]@{
            "ResolutionSizeX"                  = $ResX
            "ResolutionSizeY"                  = $ResY
            "LastUserConfirmedResolutionSizeX" = $ResX
            "LastUserConfirmedResolutionSizeY" = $ResY
            "FullscreenMode"                   = $FullscreenMode
            "LastConfirmedFullscreenMode"      = $FullscreenMode
        }
        foreach ($key in $kv.Keys) {
            $rx = "^(?i)$([regex]::Escape($key))="
            if ($lines -match $rx) {
                $lines = $lines -replace ($rx + ".*"), "$key=$($kv[$key])"
            } else {
                $idx = ($lines | Select-String -Pattern '^\[/Script/Engine\.GameUserSettings\]' | Select-Object -First 1).LineNumber
                if ($idx) { $lines = $lines[0..($idx-1)] + "$key=$($kv[$key])" + $lines[$idx..($lines.Count-1)] }
                else { $lines += "$key=$($kv[$key])" }
            }
        }
        Set-Content -Path $cfg -Value $lines
        Ok "Resolution set to ${ResX}x${ResY}, FullscreenMode=$FullscreenMode"
        Warn "The game rewrites this file on exit. If it reverts, also set it from the in-game menu (only edit while the game is closed)."
    }
}

# --- verify -------------------------------------------------------------------
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
$req = @(
    (Join-Path $Win64 "dwmapi.dll"),
    (Join-Path $Win64 "ue4ss\UE4SS.dll"),
    (Join-Path $Win64 "ue4ss\UE4SS_Signatures\StaticConstructObject.lua"),
    (Join-Path $Win64 "ue4ss\Mods\FOVControl\Scripts\main.lua")
)
$allOk = $true
Write-Host ""
foreach ($f in $req) { if (Test-Path $f) { Ok (Split-Path $f -Leaf) } else { Warn "MISSING: $f"; $allOk = $false } }
Write-Host ""
if (-not $allOk) { Die "Installation incomplete (see above)." }

Ok "Done."
Write-Host ""
Write-Host "Next steps:" -ForegroundColor White
Write-Host "  1. Launch MECCHA CHAMELEON from Steam (a UE4SS console opens alongside)."
Write-Host "  2. Settings -> General -> Field of View: set the slider to taste (~110-120 for 32:9)."
Write-Host "     Set it from the slider at least once so the game saves it."
Write-Host "  3. First run: test offline / in a private session."
Write-Host ""
Write-Host "Credits: FOV mod by Amikiir (github.com/TakoKylo/MecchaChameleon-FOVControl), UE4SS (RE-UE4SS)."
