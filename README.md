# tui 

## Description

`tui` is a Swift-first terminal editor and tooling playground. The project grows by layering small, testable capabilities on top of the ncurses core, targeting macOS 15 and Ubuntu 24.

## Roadmap

- [x] **M0 — Editor Baseline**: solid UTF-8 buffer model, full cursor navigation (line/word/buffer jumps), copy/paste hooks, status line, and regression tests in `AppTests`.
- [x] **M0.1 — Editing Comforts**: search prompt with case/whole-word modes, navigation history, and a visible command palette stub.
- [ ] **M0.2 — Visual Refinements**: themable colour pairs, layout helpers for gutters/status bars, and configuration-driven keymaps.
- [ ] **M0.3 — Workspace Awareness**: manage multiple buffers, recent-files list, autosave hooks, and dirty-state indicators exposed via `Workspace`.
- [ ] **M1 — Widget Toolkit**: introduce reusable containers (windows, panes), interactive controls (buttons, lists, tree views), and composable layouts to support richer screens.
- [ ] **M2 — Input Expansion**: mouse support (click, drag, scroll) through `CNcursesShims`, with integration tests exercising macros on macOS and Linux.
- [ ] **M2.1 — Search Enhancements**: add regex/pattern search, search history, and inline result previews using the widget toolkit.
- [ ] **M3 — Syntax Layer**: pluggable token highlighting for Swift/C-family languages, starting with regex heuristics before parser-backed refinements.
- [ ] **M3.1 — Git Foundations**: wrap `libgit2` (or a shim) in a `GitService`, expose repository status in `Workspace`, and cover staging/commit flows with fixture-backed tests.
- [ ] **M3.2 — Git UI**: render branch/status panels, provide stage/unstage/commit commands, and stream diffs directly inside ncurses views.
- [ ] **M3.3 — History & Blame**: line-by-line blame overlays, commit log navigation, and cached metadata updates on background tasks.
- [ ] **M4 — LSP Bridge**: extend `LSPClient` to initialise clangd/sourcekit-lsp, surface diagnostics/completions, and correlate errors with highlighted buffers.
- [ ] **M4.2 — Project Awareness**: detect `Package.swift` vs `.xcodeproj`/`.xcworkspace`, parse target lists, and surface build presets in a project palette.
- [ ] **M4.3 — Command-Line Xcode Integration**: run `xcodebuild` for command-line targets inside a console pane, capture output, and map failures back to diagnostics panels.
- [ ] **M4.4 — Unified Diagnostics**: merge build, LSP, and git warnings into a single diagnostics view with filtering and quick navigation.
- [ ] **M5 — Toolchain Automation**: command palette actions for clang/clang++/swift-format, background task queue for builds/tests, and extensibility hooks for future tool plugins.
- [x] **M5.1 — Collaboration Hooks**: introduce a cross-platform `NotificationService` abstraction (macOS notifications, Linux D-Bus) and document scripts for coordinating external agents such as Codex.
- [ ] **Tooling — Input Fixtures**: capture recorded key sequences into fixtures and replay them in tests to guard future keymap changes.
- [x] **Tooling — Key Capture Mode**: optional runtime flag to log unhandled key events to disk for later analysis.
- [ ] **M5.2 — Agent Prompt Panel**: prototype an optional prompt buffer and command palette entries (`Ask Codex`, `Summarise Diff`) that route through a user-supplied local proxy, keeping API secrets out of the core repo.
- [ ] **M5.3 — Agent Plugin API**: formalise a plugin interface so external assistants can subscribe to `Workspace` events, inject annotations, and trigger toasts without patching the editor.
- [ ] **M5.4 — SwiftPM Task Runner**: surface curated SwiftPM workflows (build, test, format) and allow custom command presets, streaming structured output into `tui`.
- [ ] **M5.5 — Toolchain Bridges**: provide opt-in helpers for invoking CMake/Ninja/Make, packaging reusable shell/Swift scripts instead of bundling new runtimes.


## Requirements

- Swift 6.2+ (Xcode 26 on macOS 15.7, or Swift 6.2.0 on Ubuntu 24.04)
- ncurses (wide-char). On Ubuntu: `sudo apt-get install libncursesw5-dev`
- (Optional) clangd, sourcekit-lsp

## Build

```bash
swift build
swift run tui run
```

If linking fails for ncurses on Linux, ensure the `libncursesw5-dev` package is installed.

## Notes

- TextUserInterfaceApp is a minimal ncurses loop with key handling. Press `q` to quit or `Ctrl+S` to save.
- Use `/` for incremental search and `:` for the command palette stub.
- LSPClient streams stdio to/from `clangd` (when found) and logs JSON-RPC messages.
- See `AGENTS.md` for full contributor guidelines.
