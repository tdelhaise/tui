// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "tui",
    platforms: [
        .macOS(.v15), // macOS 15+ to align with modern Swift toolchains
    ],
    products: [
        .executable(name: "tui", targets: ["App"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.63.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        // System library for ncurses (wide-character). We use a shim header to choose the right include per-OS.
        .systemLibrary(
            name: "CNcurses",
            providers: [
                .apt(["libncursesw5-dev"]), // Ubuntu/Debian
                .brew(["ncurses"])          // macOS via Homebrew (though Xcode SDK also ships one)
            ],
        ),
        .target(
            name: "Utilities",
            dependencies: [],
        ),
        .target(
            name: "TextUserInterfaceApp",
			dependencies: ["CNcurses", "Utilities", "Editors", "Workspace" ],
        ),
        .target(
            name: "LSPClient",
            dependencies: [
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOFoundationCompat", package: "swift-nio"),
                "Utilities"
            ],
        ),
        .target(
            name: "Workspace",
            dependencies: ["Utilities"],
        ),
        .target(
            name: "Editors",
            dependencies: ["Utilities"],
        ),
        .executableTarget(
            name: "App",
            dependencies: [
                "TextUserInterfaceApp",
                "LSPClient",
                "Workspace",
                "Editors",
                "Utilities",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            linkerSettings: [
                // Link ncurses with the App so the dynamic symbol resolution works.
                .linkedLibrary("ncurses", .when(platforms: [.macOS])),
                .linkedLibrary("ncursesw", .when(platforms: [.linux]))
            ]
        ),
        .testTarget(
            name: "AppTests",
            dependencies: ["App"]
        ),
    ]
)
