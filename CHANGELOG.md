# Changelog

All notable changes to Friday are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Screenshot and snip tool, saved to the Desktop.
- Dashboard usage bars for Claude, Antigravity, Qwen Code, Qoder, Wispr Flow and OpenCode (offline).
- Dashboard history and a WhatsApp unread pop-up.
- `make install`, with stable local signing so macOS permissions survive rebuilds.
- Contributor hardening: license headers, security policy, code of conduct.

### Changed
- The orb is never placed at the bottom of the screen.
- "Open app" also searches `~/Applications`.

### Fixed
- Memory reads files with CRLF line endings.
- Accessibility and privacy fixes.

## [0.2.0] - 2026-11-25

### Added
- 3D ribbon orb, dashboard, connections screen and app icon.
- WhatsApp connection through the Mac app's Dock badge.

### Removed
- Chrome connection.

## [0.1.0] - 2026-11-25

### Added
- Native macOS menu bar assistant foundation.
- Floating panel with a minimize control, shown on launch.
- Single-instance enforcement.

[Unreleased]: https://github.com/DhruvChawla25/Friday/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/DhruvChawla25/Friday/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/DhruvChawla25/Friday/releases/tag/v0.1.0
