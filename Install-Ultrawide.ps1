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
$ProgressPreference = "SilentlyContinue"   # PS 5.1's progress bar slows Invoke-WebRequest downloads drastically
# GitHub requires TLS 1.2+; old Windows 10 / .NET defaults may not offer it
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
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

# The UE4SS proxy contains 'ue4ss' strings (ASCII and UTF-16); the game ships no
# dwmapi.dll of its own. Used to avoid ever backing up our own proxy as if it were
# an original game file (pre-v1.0.2 re-runs did exactly that, and uninstall then
# "restored" a proxy with no ue4ss\ folder, breaking the game launch).
function Test-Ue4ssProxy([string]$path) {
    try {
        $b = [System.IO.File]::ReadAllBytes($path)
        if ([System.Text.Encoding]::ASCII.GetString($b) -match 'ue4ss') { return $true }
        if ([System.Text.Encoding]::Unicode.GetString($b) -match 'ue4ss') { return $true }
    } catch {}
    return $false
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
# 'experimental-latest' is a ROLLING tag: its assets are replaced on every build,
# so no hardcoded asset URL stays valid. Resolve the current name via the GitHub
# API, or scrape the release page when the API is unavailable (e.g. rate-limited).
$ue4ssUrl = $null
try {
    Info "Resolving the current UE4SS build (experimental-latest, UE5.6 capable)..."
    $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/UE4SS-RE/RE-UE4SS/releases/tags/experimental-latest" -Headers $H -TimeoutSec 30
    $a = $rel.assets | Where-Object { $_.name -match '^UE4SS_v.*\.zip$' -and $_.name -notmatch 'zDEV|zCustom|zMap' } | Select-Object -First 1
    if ($a) { $ue4ssUrl = $a.browser_download_url; Info "UE4SS asset: $($a.name)" }
} catch { Warn "GitHub API unreachable, falling back to the release page." }
if (-not $ue4ssUrl) {
    try {
        $html = (Invoke-WebRequest -Uri "https://github.com/UE4SS-RE/RE-UE4SS/releases/expanded_assets/experimental-latest" -Headers $H -TimeoutSec 30 -UseBasicParsing).Content
        # '/UE4SS_v' anchored right after a slash skips the zDEV-UE4SS_... debug asset
        $m = [regex]::Match($html, 'href="([^"]*/releases/download/[^"]*/UE4SS_v[^"/]*\.zip)"')
        if ($m.Success) {
            $ue4ssUrl = $m.Groups[1].Value
            if ($ue4ssUrl -notmatch '^https?://') { $ue4ssUrl = "https://github.com$ue4ssUrl" }
            Info "UE4SS asset (release page): $(Split-Path $ue4ssUrl -Leaf)"
        }
    } catch {}
}
if (-not $ue4ssUrl) { Die "Could not resolve the UE4SS download (GitHub API and release page both unreachable). Check your connection and re-run." }

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

# back up a pre-existing proxy dll if any; first backup wins, since on a re-run
# the current dwmapi.dll is our own proxy and must not clobber the original.
# Never keep or create a backup of the UE4SS proxy itself: pre-v1.0.2 re-runs
# poisoned .bak with our own proxy, and uninstall then "restored" it.
$dwm    = Join-Path $Win64 "dwmapi.dll"
$dwmBak = Join-Path $Win64 "dwmapi.dll.preUW.bak"
if ((Test-Path $dwmBak) -and (Test-Ue4ssProxy $dwmBak)) {
    Remove-Item $dwmBak -Force
    Warn "Discarded a stale dwmapi.dll.preUW.bak (it was our own proxy, not an original file)."
}
if ((Test-Path $dwm) -and -not (Test-Path $dwmBak) -and -not (Test-Ue4ssProxy $dwm)) {
    Copy-Item $dwm $dwmBak -Force
    Warn "Existing dwmapi.dll backed up to dwmapi.dll.preUW.bak"
}
Info "Installing UE4SS into the game..."
Copy-Item $proxy.FullName (Join-Path $Win64 "dwmapi.dll") -Force
$ue4ssDst = Join-Path $Win64 "ue4ss"
if (Test-Path $ue4ssDst) {
    # copying the folder onto an existing one would nest it (ue4ss\ue4ss) and update
    # nothing; merge the contents instead so a re-run really refreshes UE4SS while
    # keeping anything else the user added under ue4ss\ (extra mods, logs)
    Copy-Item (Join-Path $ue4ssSrc "*") $ue4ssDst -Recurse -Force
} else {
    Copy-Item $ue4ssSrc $ue4ssDst -Recurse -Force
}
Ok "UE4SS installed"

# --- download FOVControl + UE5.6 signature fix (by Amikiir) -------------------
$fovBase = "https://raw.githubusercontent.com/TakoKylo/MecchaChameleon-FOVControl/main"
$modScripts = Join-Path $Win64 "ue4ss\Mods\FOVControl\Scripts"
$sigDir     = Join-Path $Win64 "ue4ss\UE4SS_Signatures"
New-Item -ItemType Directory -Force -Path $modScripts, $sigDir | Out-Null

Info "Downloading FOVControl (by Amikiir) + UE5.6 signature fix..."
$mainLua = Join-Path $modScripts "main.lua"
if (Test-Path $mainLua) {
    # keep the pre-run state; most recent backup wins here, unlike dwmapi.dll's
    # first-backup-wins (that one preserves an original the game never re-creates)
    Copy-Item $mainLua "$mainLua.preUW.bak" -Force
    Warn "Existing main.lua backed up to main.lua.preUW.bak (re-apply local edits if you had any)."
}
Invoke-WebRequest -Uri "$fovBase/FOVControl/Scripts/main.lua" -Headers $H -OutFile $mainLua -TimeoutSec 60
Invoke-WebRequest -Uri "$fovBase/UE4SS_Signatures/StaticConstructObject.lua" -Headers $H -OutFile (Join-Path $sigDir "StaticConstructObject.lua") -TimeoutSec 60
Set-Content -Path (Join-Path $Win64 "ue4ss\Mods\FOVControl\enabled.txt") -Value "" -NoNewline
if ((Get-Item $mainLua).Length -lt 2KB) { Die "FOVControl main.lua download looks wrong, aborting." }
Ok "FOVControl + signature fix installed"

# optional: remove the redundant F7 're-apply' hotkey (local edit, not redistributed)
if (-not $KeepF7) {
    # UTF-8 explicitly: PS 5.1's default Get/Set-Content round-trips main.lua's
    # non-ASCII comment bytes through the ANSI code page (mangled on non-Western locales)
    $c = [System.IO.File]::ReadAllText($mainLua)
    $n = [regex]::Replace($c, '(?m)^(\s*)RegisterKeyBind\(Key\.F7,.*$', '$1-- F7 re-apply hotkey removed by MecchaChameleon-Ultrawide setup')
    if ($n -ne $c) { [System.IO.File]::WriteAllText($mainLua, $n, (New-Object System.Text.UTF8Encoding($false))); Info "Removed the redundant F7 hotkey (use -KeepF7 to keep it)." }
}

# --- spectator FOV fix + reliability patches (local edits, not redistributed) --
# Three exact-anchor patches on the freshly downloaded main.lua; if upstream
# changes and an anchor stops matching, the remaining patches still apply and a
# warning is printed instead of failing the install.
#   1. ApplyFOV: no early return without a pawn, and push the FOV into the view
#      target's camera too - fixes the zoomed spectator/death cam.
#   2. Hooks: re-apply on view-target changes, plus a 1s watchdog that quietly
#      re-asserts the FOV (covers loads longer than the possess burst and other
#      game-side resets) and re-adds the settings row if the page wiped it.
#   3. Slider injection: remember the page and retry across its construction
#      window - a single 250ms attempt could run before ScrollBox_0 existed,
#      leaving no FOV row until the next game restart.
$specOld = @'
local function ApplyFOV(verbose)
    local ok, err = pcall(function()
        local pc = GetLocalPlayerController()
        if not pc or not pc:IsValid() then return end
        local pawn = pc.Pawn
        if not pawn or not pawn:IsValid() then return end

        -- the pawn's camera variable is 'FirstPersonCamera' (inherited from
        -- BP_FirstPersonCharacter_Main; confirmed from the class field list)
        local cam = pawn.FirstPersonCamera
        if cam and cam:IsValid() then cam:SetFieldOfView(CurrentFOV) end

        -- PlayerCameraManager.DefaultFOV is the FOV authority when the view
        -- target has no camera component (cLeon pawns). Plain float write (safe);
        -- deliberately NOT SetFOV/LockedFOV, which would break photo zoom.
        pcall(function()
            local cm = pc.PlayerCameraManager
            if cm and cm:IsValid() then cm.DefaultFOV = CurrentFOV end
        end)

        -- keep the game's camera-animation component in sync so its
        -- animations blend back to our FOV instead of the game default
        local cma = pawn.BPC_CameraMoveAnimation
        if cma and cma:IsValid() then cma.DefaultFOV = CurrentFOV end

        if verbose then Log("FOV applied: %.0f", CurrentFOV) end
    end)
    if not ok and verbose then Log("apply failed: %s", tostring(err)) end
end
'@
$specNew = @'
local function ApplyFOV(verbose)
    local ok, err = pcall(function()
        local pc = GetLocalPlayerController()
        if not pc or not pc:IsValid() then return end

        -- own pawn - may be absent while dead/spectating, so no early return:
        -- the camera-manager and view-target paths below must still run
        local pawn = pc.Pawn
        if pawn and pawn:IsValid() then
            -- the pawn's camera variable is 'FirstPersonCamera' (inherited from
            -- BP_FirstPersonCharacter_Main; confirmed from the class field list)
            local cam = pawn.FirstPersonCamera
            if cam and cam:IsValid() then cam:SetFieldOfView(CurrentFOV) end

            -- keep the game's camera-animation component in sync so its
            -- animations blend back to our FOV instead of the game default
            local cma = pawn.BPC_CameraMoveAnimation
            if cma and cma:IsValid() then cma.DefaultFOV = CurrentFOV end
        end

        -- PlayerCameraManager.DefaultFOV is the FOV authority when the view
        -- target has no camera component (cLeon pawns). Plain float write (safe);
        -- deliberately NOT SetFOV/LockedFOV, which would break photo zoom.
        pcall(function()
            local cm = pc.PlayerCameraManager
            if cm and cm:IsValid() then cm.DefaultFOV = CurrentFOV end
        end)

        -- SPECTATOR/DEATH CAM: when viewing another actor, ITS camera component
        -- wins over DefaultFOV and still carries the baked-in narrow FOV, so the
        -- spectated view stays zoomed. Push our FOV into the view target's camera
        -- too (client-side, view-only - nothing replicates).
        pcall(function()
            local vt = nil
            pcall(function() vt = pc:GetViewTarget() end)
            if not (vt and vt:IsValid()) then
                pcall(function() vt = pc.PlayerCameraManager.ViewTarget.Target end)
            end
            if vt and vt:IsValid() then
                local vcam = vt.FirstPersonCamera
                if vcam and vcam:IsValid() then
                    vcam:SetFieldOfView(CurrentFOV)
                else
                    -- generic fallback: any camera component on the view target,
                    -- but ONLY for pawns (spectated players / spectator pawns).
                    -- Scripted view targets (fixed cutscene or scripted-shot
                    -- camera actors) keep their designed FOV.
                    local isPawn = false
                    pcall(function()
                        local pawnClass = StaticFindObject("/Script/Engine.Pawn")
                        isPawn = pawnClass and pawnClass:IsValid() and vt:IsA(pawnClass)
                    end)
                    if isPawn then
                        local camClass = StaticFindObject("/Script/Engine.CameraComponent")
                        if camClass and camClass:IsValid() then
                            local comp = vt:GetComponentByClass(camClass)
                            if comp and comp:IsValid() then comp:SetFieldOfView(CurrentFOV) end
                        end
                    end
                end
            end
        end)

        if verbose then Log("FOV applied: %.0f", CurrentFOV) end
    end)
    if not ok and verbose then Log("apply failed: %s", tostring(err)) end
end
'@
$hookOld = @'
-- reapply whenever the player (re)possesses a pawn: spawn, respawn, level load
RegisterHook("/Script/Engine.PlayerController:ClientRestart", function(self)
    ApplyBurst()
end)
'@
$hookNew = @'
-- reapply whenever the player (re)possesses a pawn: spawn, respawn, level load
RegisterHook("/Script/Engine.PlayerController:ClientRestart", function(self)
    ApplyBurst()
end)

-- MecchaChameleon-Ultrawide local patch: reapply when the view target changes
-- (death cam, spectating another player) - the burst also covers blend time
local okSpec = pcall(function()
    RegisterHook("/Script/Engine.PlayerController:ClientSetViewTarget", function(self)
        ApplyBurst()
    end)
end)
if okSpec then
    Log("spectator FOV patch active")
else
    Log("spectator hook unavailable - view-target FOV still applied on possess/slider")
end

-- MecchaChameleon-Ultrawide local patch: 1-second watchdog.
-- * Quietly re-asserts the FOV: covers level loads longer than the possess
--   burst and any game-side reset, so the value no longer unsticks until the
--   menu is reopened. The game's own camera animations still win while they
--   play (they write per tick and blend back to our DefaultFOV), and photo /
--   zoom features go through the camera manager's locked FOV, which overrides
--   these writes anyway.
-- * Heals the settings slider: if the page rebuilt its row list (tab switch,
--   settings reset) and wiped the injected row, it is re-added within a second
--   instead of staying gone until the next game restart.
local function UW_SliderState(page)
    local hasScroll, hasSlider = false, false
    pcall(function()
        local scroll = page.ScrollBox_0
        if not (scroll and scroll:IsValid()) then return end
        hasScroll = true
        for i = 0, scroll:GetChildrenCount() - 1 do
            local child = scroll:GetChildAt(i)
            pcall(function()
                if child.SaveValueKey:ToString() == "FOV" then hasSlider = true end
            end)
            if hasSlider then break end
        end
    end)
    return hasScroll, hasSlider
end

LoopAsync(1000, function()
    ExecuteInGameThread(function()
        pcall(function()
            ApplyFOV(false)
            local page = UW_LastPage
            if page and page:IsValid() then
                local hasScroll, hasSlider = UW_SliderState(page)
                if hasScroll and not hasSlider then
                    RegisterSliderHooks() -- no-op once registered
                    InjectSlider(page)
                end
            end
        end)
    end)
    return false
end)
Log("FOV watchdog active (1s)")
'@

$pageOld = @'
local okNotify, errNotify = pcall(function()
    NotifyOnNewObject(PAGE_CLASS_PATH, function(page)
        ExecuteWithDelay(250, function()
            ExecuteInGameThread(function()
                RegisterSliderHooks()
                InjectSlider(page)
            end)
        end)
    end)
end)
'@
$pageNew = @'
local okNotify, errNotify = pcall(function()
    NotifyOnNewObject(PAGE_CLASS_PATH, function(page)
        -- MecchaChameleon-Ultrawide local patch: remember the page for the
        -- watchdog, and retry the injection - a single 250ms attempt can run
        -- before ScrollBox_0 exists on slow loads (InjectSlider is idempotent,
        -- so extra attempts are no-ops once the row is in).
        UW_LastPage = page
        for i, ms in ipairs({ 250, 800, 1600, 3000 }) do
            ExecuteWithDelay(ms, function()
                ExecuteInGameThread(function()
                    -- hooks once per page open (upstream cadence): the retries
                    -- exist for the widget, so a partial hook-registration
                    -- failure is not re-attempted 4x per open
                    if i == 1 then RegisterSliderHooks() end
                    InjectSlider(page)
                end)
            end)
        end
    end)
end)
'@

# ReadAllText/WriteAllText: UTF-8 (no BOM) on both PS 5.1 and 7+, unlike Set-Content
$lua = [System.IO.File]::ReadAllText($mainLua)
$applied = 0
foreach ($pair in @(,@($specOld, $specNew)) + @(,@($hookOld, $hookNew)) + @(,@($pageOld, $pageNew))) {
    # here-strings carry this .ps1's CRLF; retry with the file's other EOL style
    foreach ($eol in @("`r`n", "`n")) {
        $o = $pair[0].Replace("`r`n", "`n").Replace("`n", $eol)
        if ($lua.Contains($o)) {
            $lua = $lua.Replace($o, $pair[1].Replace("`r`n", "`n").Replace("`n", $eol))
            $applied++
            break
        }
    }
}
# the three patches are independent and each is safe alone, so a partial apply
# is still strictly better than none (the watchdog guards UW_LastPage being nil)
if ($applied -gt 0) {
    [System.IO.File]::WriteAllText($mainLua, $lua, (New-Object System.Text.UTF8Encoding($false)))
}
if ($applied -eq 3) {
    Ok "Spectator FOV fix + reliability patches applied."
} else {
    Warn "FOV patches: only $applied/3 anchors matched (upstream main.lua changed?). The mod still works, but some fixes (spectator FOV, slider self-heal, FOV watchdog) are missing."
}

# starting FOV for the first launch
Set-Content -Path (Join-Path $Win64 "ue4ss\Mods\FOVControl\fov.txt") -Value ([string]$DefaultFov) -NoNewline

# --- set resolution -----------------------------------------------------------
if (-not $SkipResolution) {
    if ($ResX -le 0 -or $ResY -le 0) {
        # Detect the PHYSICAL native resolution of the PRIMARY monitor. The process
        # must be made DPI-aware FIRST, otherwise Screen.Bounds returns DPI-scaled
        # (logical) pixels - e.g. 1536x960 instead of 1920x1200 at 125% scaling.
        try {
            try {
                Add-Type @"
using System;
using System.Runtime.InteropServices;
public class UWDpi { [DllImport("user32.dll")] public static extern bool SetProcessDPIAware(); }
"@
            } catch {}
            try { [void][UWDpi]::SetProcessDPIAware() } catch {}

            Add-Type -AssemblyName System.Windows.Forms
            $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
            $ResX = [int]$b.Width; $ResY = [int]$b.Height

            # fallback to the active display mode if Screen detection came up empty
            if ($ResX -le 0 -or $ResY -le 0) {
                $vc = Get-CimInstance Win32_VideoController -ErrorAction Stop |
                      Where-Object { $_.CurrentHorizontalResolution } | Select-Object -First 1
                if ($vc) { $ResX = [int]$vc.CurrentHorizontalResolution; $ResY = [int]$vc.CurrentVerticalResolution }
            }
        } catch { Warn "Could not detect native resolution; pass -ResX/-ResY. Skipping resolution."; $ResX = 0 }
    }
    if ($ResX -gt 0 -and $ResY -gt 0) {
        $cfgDir = Join-Path $env:LOCALAPPDATA "Chameleon\Saved\Config\Windows"
        $cfg = Join-Path $cfgDir "GameUserSettings.ini"
        New-Item -ItemType Directory -Force -Path $cfgDir | Out-Null
        if (Test-Path $cfg) {
            Copy-Item $cfg "$cfg.preUW.bak" -Force
        } else {
            New-Item -ItemType File -Force -Path $cfg | Out-Null
        }

        $headerLine = "[/Script/Engine.GameUserSettings]"
        $headerRx   = '^\s*\[/Script/Engine\.GameUserSettings\]\s*$'
        $kv = [ordered]@{
            "ResolutionSizeX"                  = $ResX
            "ResolutionSizeY"                  = $ResY
            "LastUserConfirmedResolutionSizeX" = $ResX
            "LastUserConfirmedResolutionSizeY" = $ResY
            "FullscreenMode"                   = $FullscreenMode
            "LastConfirmedFullscreenMode"      = $FullscreenMode
        }

        # @(...) forces an array even for a 1-line file. A bare Get-Content on a
        # single-line file returns a STRING; the old code's slice $lines[0..(idx-1)]
        # then indexed the string's CHARACTERS, shredding the section header into
        # "[", "/", "[" and breaking the whole .ini.
        $lines = @(Get-Content -LiteralPath $cfg)

        $hasHeader = $false
        foreach ($l in $lines) { if ($l -match $headerRx) { $hasHeader = $true; break } }

        $out = New-Object System.Collections.Generic.List[string]
        if (-not $hasHeader) {
            # No valid header (fresh / empty / previously-corrupted): write a clean
            # section at the top, then keep any leftover NON-key lines so our keys
            # are never stranded under a malformed section.
            $out.Add($headerLine)
            foreach ($key in $kv.Keys) { $out.Add("$key=$($kv[$key])") }
            foreach ($line in $lines) {
                $isOurKey = $false
                foreach ($key in $kv.Keys) {
                    if ($line -match "^(?i)\s*$([regex]::Escape($key))\s*=") { $isOurKey = $true; break }
                }
                if (-not $isOurKey) { $out.Add($line) }
            }
        } else {
            # Valid header present: replace our keys in place, insert any missing
            # ones right after the header, and drop duplicate key lines.
            $exists = @{}
            foreach ($key in $kv.Keys) {
                $krx = "^(?i)\s*$([regex]::Escape($key))\s*="
                foreach ($l in $lines) { if ($l -match $krx) { $exists[$key] = $true; break } }
            }
            $written = @{}
            $insertedMissing = $false
            foreach ($line in $lines) {
                $replaced = $false
                foreach ($key in $kv.Keys) {
                    if ($line -match "^(?i)\s*$([regex]::Escape($key))\s*=") {
                        if (-not $written[$key]) { $out.Add("$key=$($kv[$key])"); $written[$key] = $true }
                        $replaced = $true; break
                    }
                }
                if (-not $replaced) { $out.Add($line) }
                if ((-not $insertedMissing) -and ($line -match $headerRx)) {
                    foreach ($key in $kv.Keys) { if (-not $exists[$key]) { $out.Add("$key=$($kv[$key])") } }
                    $insertedMissing = $true
                }
            }
        }

        # UTF-8 without BOM (what Unreal writes); avoids the PS 5.1 Set-Content
        # BOM/ANSI inconsistency the old code had.
        [System.IO.File]::WriteAllLines($cfg, $out, (New-Object System.Text.UTF8Encoding($false)))
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
Write-Host "  1. Launch MECCHA CHAMELEON from Steam."
Write-Host "  2. Settings -> General -> Field of View: set the slider to taste (~110-120 for 32:9)."
Write-Host "     Set it from the slider at least once so the game saves it."
Write-Host "  3. First run: test offline / in a private session."
Write-Host ""
Write-Host "Credits: FOV mod by Amikiir (github.com/TakoKylo/MecchaChameleon-FOVControl), UE4SS (RE-UE4SS)."
