# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[1.0.1]: https://github.com/Shayano/MecchaChameleon-Ultrawide/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/Shayano/MecchaChameleon-Ultrawide/releases/tag/v1.0.0
