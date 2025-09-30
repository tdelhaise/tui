# swift-tui-lsp (skeleton)

Swift 6.2-ready TUI + LSP client skeleton targeting macOS and Linux (Ubuntu 24.04).

## Requirements

- Swift 6.2+ (Xcode 26 on macOS 15.7, or Swift 6.2.0 on Ubuntu 24.04)
- ncurses (wide-char). On Ubuntu: `sudo apt-get install libncursesw5-dev`
- (Optional) clangd, sourcekit-lsp

## Build

```bash
swift build
swift run cli-tui run
```

If linking fails for ncurses on Linux, ensure the `libncursesw5-dev` package is installed.

## Notes

- TUI is a minimal ncurses loop with key handling. Press `q` to quit.
- LSPClient streams stdio to/from `clangd` (when found) and logs JSON-RPC messages.
- See `AGENTS.md` for full contributor guidelines.
