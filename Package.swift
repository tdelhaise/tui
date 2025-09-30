// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.
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
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
    ],
    targets: [
		.target(
			name: "CNcursesShims",
			path: "Sources/CNcursesShims",
			publicHeadersPath: "include",
			linkerSettings: [
				// macOS
				.linkedLibrary("ncurses", .when(platforms: [.macOS])),
				// Linux (Ubuntu 24.04)
				.linkedLibrary("ncursesw", .when(platforms: [.linux]))
			]
		),
        .target(
            name: "Utilities",
            dependencies: [],
			path: "Sources/Utilities"
        ),
        .target(
            name: "TextUserInterfaceApp",
			dependencies: ["CNcursesShims", "Utilities", "Editors", "Workspace" ],
			path: "Sources/TextUserInterfaceApp"
        ),
        .target(
            name: "LSPClient",
            dependencies: [
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOFoundationCompat", package: "swift-nio"),
                "Utilities"
            ],
			path: "Sources/LSPClient"
        ),
        .target(
            name: "Workspace",
            dependencies: ["Utilities"],
			path: "Sources/Workspace"
        ),
        .target(
            name: "Editors",
            dependencies: ["Utilities"],
			path: "Sources/Editors"
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
			dependencies: ["App", "TextUserInterfaceApp", "Editors", "Utilities"],
			resources: [
				.process("Fixtures")
			]
		),
    ]
)
