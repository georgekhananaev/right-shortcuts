// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RightShortcuts",
    platforms: [.macOS(.v14)],
    products: [
        // The Xcode project builds the app and the extension from these.
        .library(name: "RightShortcutsCore", targets: ["RightShortcutsCore"]),
        .library(name: "RightShortcutsActions", targets: ["RightShortcutsActions"]),
    ],
    targets: [
        // Models, menu logic, storage and the extension-to-app bridge. Shared by both executables.
        .target(
            name: "RightShortcutsCore",
            path: "Sources/Core"
        ),
        // Everything that touches the user's files or runs their commands. Used by the app only.
        .target(
            name: "RightShortcutsActions",
            dependencies: ["RightShortcutsCore"],
            path: "Sources/Actions"
        ),
        // The menu bar app: settings UI, permissions and running the actions.
        .executableTarget(
            name: "RightShortcuts",
            dependencies: ["RightShortcutsCore", "RightShortcutsActions"],
            path: "Sources/App",
            linkerSettings: [
                .linkedFramework("FinderSync"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        // The sandboxed Finder Sync extension. It only builds menus and forwards clicks to the app.
        .executableTarget(
            name: "RightShortcutsFinderExtension",
            dependencies: ["RightShortcutsCore"],
            path: "Sources/FinderExtension",
            linkerSettings: [
                .linkedFramework("FinderSync"),
                // App extensions start in NSExtensionMain, not main().
                .unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"]),
            ]
        ),
        .testTarget(
            name: "RightShortcutsCoreTests",
            dependencies: ["RightShortcutsCore"],
            path: "Tests/CoreTests"
        ),
        .testTarget(
            name: "RightShortcutsActionsTests",
            dependencies: ["RightShortcutsActions"],
            path: "Tests/ActionsTests"
        ),
    ]
)
