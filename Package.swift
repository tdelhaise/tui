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
		.package(url: "https://github.com/apple/swift-log", from: "1.6.0"),
		.package(url: "https://github.com/sushichop/Puppy.git", from: "0.9.0"),
		.package(url: "https://github.com/apple/swift-atomics.git", from: "1.3.0"),
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
            dependencies: [
				.product(name: "Logging", package: "swift-log")
			],
			path: "Sources/Utilities"
        ),
        .target(
            name: "TextUserInterfaceApp",
			dependencies: [
				"CNcursesShims",
				"Utilities",
				"Editors",
				"Workspace",
				.product(name: "Logging", package: "swift-log")
			],
			path: "Sources/TextUserInterfaceApp"
        ),
        .target(
            name: "LSPClient",
            dependencies: [
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOFoundationCompat", package: "swift-nio"),
				.product(name: "Logging", package: "swift-log"),
                "Utilities"
            ],
			path: "Sources/LSPClient"
        ),
        .target(
            name: "Workspace",
            dependencies: [
				"Utilities",
				.product(name: "Logging", package: "swift-log")
			],
			path: "Sources/Workspace"
        ),
        .target(
            name: "Editors",
            dependencies: [
				"Utilities",
				.product(name: "Logging", package: "swift-log")
			],
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
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
				.product(name: "Logging", package: "swift-log"),
				.product(name: "Puppy", package: "puppy")
				
            ],
            linkerSettings: [
                // Link ncurses with the App so the dynamic symbol resolution works.
                .linkedLibrary("ncurses", .when(platforms: [.macOS])),
                .linkedLibrary("ncursesw", .when(platforms: [.linux]))
            ]
        ),
		.testTarget(
			name: "AppTests",
			dependencies: [
				"App",
				"TextUserInterfaceApp",
				"Editors",
				"Utilities",
				.product(name: "Logging", package: "swift-log"),
				.product(name: "Atomics", package: "swift-atomics")
			],
			resources: [
				.process("Fixtures")
			]
		),
    ]
)
