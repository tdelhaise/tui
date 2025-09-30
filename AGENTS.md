# Repository Guidelines

## Project Structure & Module Organization
This Swift 6 package is organised under `Sources/`, with each feature in its own module: the `App` target hosts the `TUICommand` entry point, `TextUserInterfaceApp` owns the ncurses event loop, `Editors` and `Workspace` model buffers, `Utilities` centralises logging/helpers, and `CNcursesShims` exposes the C bridge. Networking code for language servers lives in `LSPClient`. Tests reside in `Tests/AppTests`, mirroring the module under test; add peer directories if you introduce new targets.

## Build, Test, and Development Commands
Use `swift build` for a debug build and to validate dependencies. Run the CLI with `swift run tui [path/to/file]` to launch the ncurses UI and optionally open a file. Execute `swift test` (or `swift test --parallel`) before every push; it boots XCTest suites in `Tests/`.

## Coding Style & Naming Conventions
Follow Swift API Design Guidelines: `UpperCamelCase` types, `lowerCamelCase` functions and properties, and thoughtfully named async methods. Existing files use tab indentation—match the surrounding style instead of rewriting. Keep imports ordered (Foundation/NIO first, internal modules next), restrict line length to ~100 characters, and let compiler availability checks guard platform-specific ncurses code.

## Testing Guidelines
All automated checks use XCTest; group related assertions inside `XCTContext.runActivity`. Name test files `<Module>Tests.swift` and methods `test_…` to keep discovery consistent. Aim to cover new command paths (parsing options, buffer navigation) and regression-proof edge cases such as window resizing or missing LSP executables. Use `swift test --filter ModuleTests.test_case` when iterating locally.

## Commit & Pull Request Guidelines
History favours compact, descriptive commit titles (e.g. “First build that work”); continue using a single imperative sentence under 72 characters, optionally prefixing the touched module. Reference issues or context in the body when needed. Pull requests should describe user-visible behaviour, note platform impacts (macOS vs Linux ncurses), include repro steps or screenshots for TUI changes, and link to failing tests the change fixes. Confirm `swift test` output and mention any skipped checks in the PR description.

## Platform Notes
macOS builds link against `ncurses`, while Linux uses `ncursesw`; ensure those packages exist before running `swift build`. For LSP features, validate the `--clangd` and `--sourcekit` paths locally and stub them in CI to avoid blocking the main command. Keep locale-aware behaviour in mind when handling text rendering.
