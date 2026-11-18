# Changelog

All notable changes to `com.berkterek.framework`. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.3.0] - 2026-11-18

### Added
- `FrameworkDebugCommands` assembly (Editor and development builds only): a registry of dev-only command
  containers that can be listed and run by id (`<Container>.<Member>`), plus a dev-only static accessor for the
  Editor runner.
- `Tools/Framework/Debug Commands/Run` and `List` Editor menu items: read a request from
  `Temp/debug-command.json`, write the outcome to `Temp/debug-command-result.json`, log one
  `[DebugCommands] OK|FAIL` line.
- Optional `FrameworkDebugCommandsSRDebugger` adapter (compiled only with `SRDEBUGGER_ENABLED`) that mirrors
  registered containers into SRDebugger's options panel.
- `LogTag.DebugCommands`.
