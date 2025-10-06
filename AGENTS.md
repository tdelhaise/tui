# Repository Guidelines

## Project Structure & Module Organization
This Swift 6 package is organised under `Sources/`, with each feature in its own module: the `App` target hosts the `TUICommand` entry point, `TextUserInterfaceApp` owns the ncurses event loop, `Editors` and `Workspace` model buffers, `Utilities` centralises logging/helpers, and `CNcursesShims` exposes the C bridge. Networking code for language servers lives in `LSPClient`. Tests reside in `Tests/AppTests`, mirroring the module under test; add peer directories if you introduce new targets.

## Build, Test, and Development Commands
Use `swift build` for a debug build and to validate dependencies. Run the CLI with `swift run tui [path/to/file]` to launch the ncurses UI and optionally open a file. Execute `swift test` (or `swift test --parallel`) before every push; it boots XCTest suites in `Tests/`.
Pass `--theme` (`default`, `high-contrast`) and `--keymap` (`standard`, `alternate`) to align the UI palette and shortcuts with your terminal preferences; e.g. `swift run tui --theme high-contrast --keymap alternate README.md`.

## Coding Style & Naming Conventions
Follow Swift API Design Guidelines: `UpperCamelCase` types, `lowerCamelCase` functions and properties, and thoughtfully named async methods. Existing files use tab indentation—match the surrounding style instead of rewriting. Keep imports ordered (Foundation/NIO first, internal modules next), restrict line length to ~100 characters, and let compiler availability checks guard platform-specific ncurses code.

## Testing Guidelines
All automated checks use XCTest; group related assertions inside `XCTContext.runActivity`. Name test files `<Module>Tests.swift` and methods `test_…` to keep discovery consistent. Aim to cover new command paths (parsing options, buffer navigation) and regression-proof edge cases such as window resizing or missing LSP executables. Use `swift test --filter ModuleTests.test_case` when iterating locally.

## Commit & Pull Request Guidelines
History favours compact, descriptive commit titles (e.g. “First build that work”); continue using a single imperative sentence under 72 characters, optionally prefixing the touched module. Reference issues or context in the body when needed. Pull requests should describe user-visible behaviour, note platform impacts (macOS vs Linux ncurses), include repro steps or screenshots for TUI changes, and link to failing tests the change fixes. Confirm `swift test` output and mention any skipped checks in the PR description.

## Platform Notes
macOS builds link against `ncurses`, while Linux uses `ncursesw`; ensure those packages exist before running `swift build`. For LSP features, validate the `--clangd` and `--sourcekit` paths locally and stub them in CI to avoid blocking the main command. Keep locale-aware behaviour in mind when handling text rendering.

## UI Shortcuts
- `Ctrl+S` saves the active buffer to its backing file; invocation with `swift run tui path/to/file` seeds the document path.
- `/` enters the incremental search prompt. Use `Ctrl+T` to toggle case sensitivity, `Ctrl+W` to constrain whole words, `Enter` to jump, `Esc` to cancel, and `n`/`N` to repeat the search forward/backward.
- `:` opens the command palette; use `:write` to save the current file or `:write <path>` to perform Save As. Type to filter, press `Enter` to execute, or `Esc` to close.
- Line numbers render in a left gutter coloured via the active `TUITheme`; monochrome is used if colours are unavailable.
- `F7` steps back through the navigation history and `F8` steps forward. The footer reflects history state when active.
- `Shift+Arrow` extends the selection while moving; plain arrows clear the selection.
- `Home`/`End` (and their Shift variants) jump to the start/end of the current line.
- `v` toggles selection anchoring at the cursor, `y` copies, `x` cuts, and `p` pastes using the in-memory clipboard.
- `Option+Arrow` (or `Option+f`/`Option+b`) hops whole words; add Shift to grow a word-sized selection.
- Copy/cut/paste emit notifications via `NotificationServices` (osascript on macOS, `notify-send` on Linux); override the service in tests to avoid spawning processes.
- Status bar displays cursor position, selection length, and any active overlays; ensure updates stay under the terminal width.

## Milestone Playbooks
- **M0 — Editor Baseline**: extend `Sources/Editors/EditorBuffer.swift` with cursor movement helpers (line/word/buffer jumps), selection and copy/paste buffers, and integrate scroll tracking with `TextUserInterfaceApp`. Add regression tests in `Tests/AppTests` covering boundary navigation, UTF-8 handling, and viewport clamping.
- **M0 Tooling**: introduce lightweight fixtures under `Tests/Fixtures/` for sample documents and add helper builders in Utilities to generate buffers for tests.
- **M5.1 — NotificationService**: wire `NotificationServices.shared()` through UI surfaces that need alerts (background task completion, Codex hand-offs). Provide platform shims under `Sources/Utilities` for macOS (NSUserNotification/UNUserNotification) and Linux (D-Bus). Keep `LoggingNotificationService` available for headless environments.
- **Task Runner Prep**: when adding command palette entries, route build/test/format shortcuts through SwiftPM (`swift build`, `swift test`, `swift format`) and document common presets in this file.

## Testing & QA Playbook Additions
- Use `swift test` locally; when the sandbox blocks cache directories, rerun with `SWIFT_MODULE_CACHE_PATH=$(pwd)/.swift-module-cache`. If failures persist, escalate the command.
- Add unit coverage for each new editor operation and NotificationService backend. Stub external dependencies (D-Bus, UNUserNotification) behind protocols so tests stay deterministic.
- Prefer `XCTExpectFailure` to mark known gaps instead of commenting out tests.
