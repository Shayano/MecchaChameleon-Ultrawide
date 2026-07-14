# MECCHA CHAMELEON - Ultrawide (21:9 / 32:9) Setup

One-click setup that makes **MECCHA CHAMELEON** display correctly on ultrawide
monitors (21:9, 32:9, ...) in fullscreen, without the zoomed-in / cropped view.

- **Game:** MECCHA CHAMELEON (Steam app 4704690), Unreal Engine 5.6
- **What you get:** native-resolution fullscreen + a working in-game Field of View
  slider so the picture is no longer zoomed on wide screens.

> This is an **installer/setup tool**. It does not contain the mod code itself.
> It downloads the required components from their official sources (see Credits)
> and wires everything up for you, then sets your resolution.

---

## Why this is needed

On a wide screen the game looks zoomed in / cropped. Things worth knowing:

- The game runs on UE5.6, whose engine default is already
  `AspectRatio_MaintainYFOV`, and the game does not override it. So the popular
  "create an `Engine.ini` with `AspectRatioAxisConstraint=...`" trick does
  **nothing** here - that value is already active.
- The zoom comes from a **fixed first-person camera FOV** baked into the game,
  which no `.ini` file can change.
- The only reliable fix is a runtime mod that widens the camera FOV. That is
  exactly what **FOVControl** (by Amikiir) does, via **UE4SS**. This repo just
  automates installing them and sets your resolution.

Result: **Hor+** ("horizontal plus") - you keep the vertical view and gain real
image on the sides. Note the unmodded game never letterboxes: it already fills
the whole panel, just zoomed in. The slider turns that magnification into
actual field of view.

---

## Requirements

- Windows, MECCHA CHAMELEON installed via Steam.
- Internet connection for the first install (components are downloaded).
- PowerShell 5+ (ships with Windows).

---

## Install

1. Download the latest release zip and extract it anywhere.
2. **Close the game.**
3. Right-click `Install-Ultrawide.ps1` -> Run with PowerShell.
   Or from a terminal:
   ```
   powershell -ExecutionPolicy Bypass -File .\Install-Ultrawide.ps1
   ```

The script will:
- locate your MECCHA CHAMELEON install via Steam (or pass `-GameRoot "<path>"`),
- download UE4SS (the official current build that supports UE5.6),
- download FOVControl and its UE5.6 signature fix from Amikiir's repo,
- extend it locally so the FOV also applies to the spectator / death cam
  (upstream only widens your own first-person camera),
- install everything into the game's `Binaries\Win64`,
- set your resolution to your monitor's native resolution in fullscreen
  (override with `-ResX` / `-ResY`, or set `-FullscreenMode 0|1|2`).

Useful options:
```
-GameRoot "D:\SteamLibrary\steamapps\common\MECCHA CHAMELEON"
-ResX 5120 -ResY 1440        # force a resolution
-FullscreenMode 1            # 0 = exclusive, 1 = borderless (default), 2 = windowed
-DefaultFov 110              # starting FOV written for first launch (60-140)
-SkipResolution              # do not touch GameUserSettings.ini
```

---

## Usage

1. Launch MECCHA CHAMELEON from Steam. A small UE4SS console window opens next to
   it (this is normal). It should print `[FOVControl] ... loaded`.
2. Check the resolution in the in-game settings (native, fullscreen).
3. Go to **Settings -> General -> Field of View** and set the slider to taste.
   For 32:9, somewhere around **110-120** is a good start.
   - Set it from the slider at least once: the value is saved by the game, so it
     persists across sessions and is no longer overridden when you open the menu.
   - Backup hotkeys (optional): `F5` = FOV down, `F6` = FOV up. Console: `fov 110`.

---

## Multiplayer / anti-cheat

- The game ships **no kernel anti-cheat** (no EasyAntiCheat / BattlEye); it uses
  the RedpointEOS online SDK with anti-cheat disabled.
- FOVControl is **client-side and view-only**: it changes only your own camera's
  field of view, no gameplay, no replication.
- Still, this is an online game. Test offline / in a private session first, and be
  considerate in public lobbies. Use at your own risk.

---

## Uninstall

```
powershell -ExecutionPolicy Bypass -File .\Uninstall-Ultrawide.ps1
```
- `-ModOnly` removes only FOVControl and keeps UE4SS.
- Otherwise it removes `dwmapi.dll` and the `ue4ss\` folder from `Binaries\Win64`.

No game files are ever modified, so uninstalling fully restores the original game.

---

## After a game update

If a patch changes the game executable, UE4SS may stop loading (the signature
changes). Check FOVControl for an updated signature:
https://github.com/TakoKylo/MecchaChameleon-FOVControl

---

## Credits

This project is only an installer and some documentation. The actual work that
makes the FOV adjustable belongs to others:

- **FOVControl** - the in-game FOV slider and the UE5.6 signature fix - by
  **Amikiir**: https://github.com/TakoKylo/MecchaChameleon-FOVControl
  Please star / support the original mod.
- **UE4SS (RE-UE4SS)** - the scripting runtime that makes it all possible (MIT):
  https://github.com/UE4SS-RE/RE-UE4SS

If you are Amikiir and would prefer this installer not download your files, open
an issue and it will be changed.

## License

The installer and docs in this repo are MIT (see `LICENSE`). Third-party
components keep their own licenses and are not redistributed here.
