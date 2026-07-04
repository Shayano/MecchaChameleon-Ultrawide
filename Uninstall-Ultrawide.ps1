<#
  Uninstall-Ultrawide.ps1
  Removes UE4SS + FOVControl from MECCHA CHAMELEON.
  The game itself was never modified, so this restores it fully.

  Options:
    -GameRoot <path>   Game folder (auto-detected via Steam if omitted)
    -ModOnly           Remove only FOVControl, keep UE4SS and any other mods
#>

[CmdletBinding()]
param(
    [string]$GameRoot,
    [switch]$ModOnly
)

$ErrorActionPreference = "Stop"
function Ok($m){ Write-Host "[ok]        $m" -ForegroundColor Green }
function Warn($m){ Write-Host "[warn]      $m" -ForegroundColor Yellow }
function Die($m){ Write-Host "[error]     $m" -ForegroundColor Red; exit 1 }

function Find-SteamPath {
    foreach ($k in @("HKCU:\Software\Valve\Steam","HKLM:\SOFTWARE\WOW6432Node\Valve\Steam","HKLM:\SOFTWARE\Valve\Steam")) {
        try { $p = Get-ItemProperty -Path $k -ErrorAction Stop; $v = $p.SteamPath; if(-not $v){$v=$p.InstallPath}; if ($v -and (Test-Path $v)) { return ($v -replace '/','\') } } catch {}
    }
    return $null
}
function Find-GameRoot {
    $steam = Find-SteamPath; if (-not $steam) { return $null }
    $libs = @($steam); $vdf = Join-Path $steam "steamapps\libraryfolders.vdf"
    if (Test-Path $vdf) { foreach ($m in [regex]::Matches((Get-Content -Raw $vdf), '"path"\s+"([^"]+)"')) { $libs += ($m.Groups[1].Value -replace '\\\\','\') } }
    foreach ($lib in ($libs | Select-Object -Unique)) {
        $cand = Join-Path $lib "steamapps\common\MECCHA CHAMELEON"
        if (Test-Path (Join-Path $cand "Chameleon\Binaries\Win64\PenguinHotel-Win64-Shipping.exe")) { return $cand }
    }
    return $null
}

if (-not $GameRoot) { $GameRoot = Find-GameRoot }
if (-not $GameRoot) { Die "Could not find the game. Re-run with -GameRoot `"<path>`"" }
$Win64 = Join-Path $GameRoot "Chameleon\Binaries\Win64"

if (Get-Process -Name "PenguinHotel-Win64-Shipping" -ErrorAction SilentlyContinue) { Die "Close the game first." }

if ($ModOnly) {
    $mod = Join-Path $Win64 "ue4ss\Mods\FOVControl"
    if (Test-Path $mod) { Remove-Item $mod -Recurse -Force; Ok "FOVControl removed (UE4SS kept)." } else { Warn "FOVControl already absent." }
    return
}

$proxy = Join-Path $Win64 "dwmapi.dll"
$ue4ss = Join-Path $Win64 "ue4ss"
if (Test-Path $proxy) { Remove-Item $proxy -Force; Ok "dwmapi.dll removed." } else { Warn "dwmapi.dll absent." }
if (Test-Path $ue4ss) { Remove-Item $ue4ss -Recurse -Force; Ok "ue4ss\ removed." } else { Warn "ue4ss\ absent." }

$bak = Join-Path $Win64 "dwmapi.dll.preUW.bak"
if (Test-Path $bak) { Copy-Item $bak $proxy -Force; Remove-Item $bak -Force; Ok "Restored the original dwmapi.dll." }

Ok "Uninstall complete. The game is back to its original state."
Write-Host "Note: your resolution in GameUserSettings.ini was not reverted; change it in the in-game menu if needed."
