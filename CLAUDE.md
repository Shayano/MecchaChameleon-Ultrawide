# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A two-script PowerShell **installer/setup tool** that makes the Steam game *MECCHA
CHAMELEON* (app 4704690, Unreal Engine 5.6) render correctly on ultrawide screens
(21:9, 32:9). It does **not** contain any mod code. At runtime it downloads
third-party components from their official sources and wires them into the game's
binaries folder, then sets the resolution. The whole repo is just
`Install-Ultrawide.ps1`, `Uninstall-Ultrawide.ps1`, and docs.

## Commands

```powershell
# Install (auto-detects the game via Steam)
powershell -ExecutionPolicy Bypass -File .\Install-Ultrawide.ps1

# Install with a forced game path / resolution / options
powershell -ExecutionPolicy Bypass -File .\Install-Ultrawide.ps1 `
  -GameRoot "D:\SteamLibrary\steamapps\common\MECCHA CHAMELEON" `
  -ResX 5120 -ResY 1440 -FullscreenMode 1 -DefaultFov 110

# Uninstall (full, or -ModOnly to keep UE4SS)
powershell -ExecutionPolicy Bypass -File .\Uninstall-Ultrawide.ps1
powershell -ExecutionPolicy Bypass -File .\Uninstall-Ultrawide.ps1 -ModOnly
```

There is no build, test, or lint setup, this is plain PowerShell 5+ (ships with
Windows). Test changes by running the script against a real game install; both
scripts refuse to run while `PenguinHotel-Win64-Shipping.exe` is running.

## How the fix works (the domain knowledge that matters)

- The game's zoomed-in look on wide screens is **not** an aspect-ratio constraint
  problem. UE5.6 already defaults to `AspectRatio_MaintainYFOV` and the game does
  not override it, so the common `Engine.ini` `AspectRatioAxisConstraint` trick is
  a no-op here.
- The zoom comes from a **fixed first-person camera FOV baked into the game**,
  which no `.ini` can change. The only reliable fix is a runtime mod
  (**FOVControl** by Amikiir, running on **UE4SS**) that widens the camera FOV.
  Result is Hor+ ("horizontal plus").
- This repo automates installing UE4SS + FOVControl and sets the resolution. Keep
  this distinction in mind: the value here is the *installer logic and the correct
  diagnosis*, not the FOV code itself.
- **Why a runtime mod is acceptable for this online game:** it ships no kernel
  anti-cheat (no EasyAntiCheat / BattlEye), it uses the RedpointEOS online SDK with
  anti-cheat disabled. FOVControl is client-side and view-only, it changes only the
  local camera FOV, with no gameplay effect and no replication. It is still an
  online game, so the README advises testing offline / in a private session first.

## Install flow (Install-Ultrawide.ps1)

1. **Locate the game.** `Find-SteamPath` reads Steam's path from three registry
   keys (`HKCU\Software\Valve\Steam`, two `HKLM` variants). `Find-GameRoot` then
   parses `steamapps\libraryfolders.vdf` for additional library folders and checks
   each for `...\MECCHA CHAMELEON\Chameleon\Binaries\Win64\PenguinHotel-Win64-Shipping.exe`.
   `-GameRoot` overrides detection entirely.
2. **Download UE4SS** (MIT) from the `experimental-latest` GitHub release of
   `UE4SS-RE/RE-UE4SS` via the GitHub API, with a hardcoded fallback URL if the API
   is unreachable. Extracts `dwmapi.dll` (the proxy DLL) + the `ue4ss\` folder.
3. **Install UE4SS** into `<GameRoot>\Chameleon\Binaries\Win64` (referred to as
   `$Win64` throughout). Pre-existing `dwmapi.dll` is backed up to
   `dwmapi.dll.preUW.bak`.
4. **Download FOVControl** (`main.lua`) and the UE5.6 signature fix
   (`StaticConstructObject.lua`) from `TakoKylo/MecchaChameleon-FOVControl` raw
   GitHub into `ue4ss\Mods\FOVControl\Scripts` and `ue4ss\UE4SS_Signatures`. Writes
   `enabled.txt` and `fov.txt` (the `-DefaultFov` starting value).
5. **Patch out the F7 hotkey** in `main.lua` via regex unless `-KeepF7` is passed
   (FOVControl's redundant "re-apply" bind).
6. **Set resolution** in `%LOCALAPPDATA%\Chameleon\Saved\Config\Windows\GameUserSettings.ini`
   (unless `-SkipResolution`): native resolution via `System.Windows.Forms.Screen`
   if `-ResX/-ResY` not given, plus `FullscreenMode`. Backs up the existing ini to
   `.preUW.bak`, then upserts keys under `[/Script/Engine.GameUserSettings]`.
7. **Verify** the four required files exist and report.

## Conventions and constraints

- **No game files are ever modified.** Everything lands in `Binaries\Win64` as
  added files (`dwmapi.dll`, `ue4ss\`), so uninstall fully restores the game. Keep
  this invariant when editing, it is the project's core safety promise.
- **Nothing third-party is redistributed.** Components are downloaded at runtime
  from official sources. Do not commit downloaded payloads. `.gitignore` already
  excludes `backup/`, `payload/`, `_recon/`, `*.bak`, `*.zip`, `*.log`.
- Both scripts set `$ErrorActionPreference = "Stop"` and use the same colored
  `Ok/Warn/Die` output helpers (Install also adds an `Info` helper; Uninstall has
  none and its label padding differs slightly). `Find-SteamPath`/`Find-GameRoot`
  are duplicated in both scripts, keep them in sync if you change detection logic.
- The path layout is specific: the game folder is `MECCHA CHAMELEON`, but the
  binaries live under a `Chameleon\` subfolder and the exe is
  `PenguinHotel-Win64-Shipping.exe` (the game's internal project name is
  "PenguinHotel"/"Chameleon").
- The game rewrites `GameUserSettings.ini` on exit; only edit it while the game is
  closed, and expect the user may also need to confirm resolution in the in-game
  menu.
- **UE4SS loading is signature-fragile.** It hooks the game through an AOB
  signature (`StaticConstructObject.lua`); a game patch that changes the executable
  can silently stop UE4SS from loading. The fix is a refreshed signature file from
  the `TakoKylo/MecchaChameleon-FOVControl` repo (the README's "after a game
  update" note).

## Licensing note

Installer + docs are MIT. UE4SS (MIT) and FOVControl keep their own licenses and
are credited in `README.md`. Preserve the credits and the "open an issue to opt
out" note for Amikiir if you touch the download URLs.
