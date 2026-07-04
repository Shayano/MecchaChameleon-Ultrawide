# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.2] - 2026-07-04

### Fixed
- **Re-running the installer now actually updates UE4SS.** With an existing
  `ue4ss\` folder, the old copy step created a useless nested `ue4ss\ue4ss` and
  left every installed file untouched, while the final verification still passed.
  Contents are now merged in place, preserving anything else you added under
  `ue4ss\` (extra mods, logs).
- **Replaced the dead UE4SS fallback URL.** `experimental-latest` is a rolling
  release whose assets are replaced on every build, so the hardcoded fallback zip
  had gone 404. When the GitHub API is unreachable (e.g. rate-limited), the
  installer now resolves the asset from the release page instead, and fails with
  a clear message if both paths are down.
- **`main.lua` is backed up to `main.lua.preUW.bak` before re-download**, so a
  re-run no longer silently destroys local edits to FOVControl.
- **A re-run no longer overwrites `dwmapi.dll.preUW.bak` with our own proxy DLL**
  (the first backup wins), so uninstall restores the true original file.
- Uninstall now removes `dwmapi.dll.preUW.bak` after restoring it.

### Changed
- Faster downloads on Windows PowerShell 5.1 (progress bar suppressed) and TLS
  1.2 explicitly enabled for older Windows 10 setups.

## [1.0.1] - 2026-06-29

### Fixed
- **Native resolution detection no longer returns DPI-scaled values.** The
  installer now makes itself DPI-aware (`SetProcessDPIAware()`) before reading the
  primary monitor bounds, so it detects the physical resolution (e.g. 1920x1200
  instead of 1536x960 at 125% scaling), with a `Win32_VideoController` fallback.
- **`GameUserSettings.ini` is no longer corrupted on a freshly created
  (single-line) config.** The file is now always read as an array, so the
  `[/Script/Engine.GameUserSettings]` header is preserved instead of being shredded
  into stray characters.
- **The key upsert no longer mangles the file when the section header is the last
  line.** The section is rebuilt deterministically (replace-in-place plus
  insert-missing keys, with duplicates removed) and written as UTF-8 without BOM,
  matching what Unreal Engine writes.

### Changed
- Added `CLAUDE.md` with contributor guidance. No runtime impact.

## [1.0.0] - 2026-06-17

### Added
- Initial release: one-click ultrawide (21:9 / 32:9) setup for MECCHA CHAMELEON.
  Installs UE4SS and FOVControl into the game's `Binaries\Win64`, downloading the
  components from their official sources at runtime, and sets native-resolution
  fullscreen via `GameUserSettings.ini`. No game files are modified, and a full
  uninstall is supported.

[1.0.2]: https://github.com/Shayano/MecchaChameleon-Ultrawide/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/Shayano/MecchaChameleon-Ultrawide/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/Shayano/MecchaChameleon-Ultrawide/releases/tag/v1.0.0
