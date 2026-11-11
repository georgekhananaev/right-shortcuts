import Foundation
import Testing

@Suite("Bundle requirements")
struct BundleRequirementsTests {
    /// App Store Connect refuses an upload whose Finder extension doesn't declare itself an agent:
    /// "A value for the key 'LSUIElement' in bundle …FinderExtension.appex is required."
    @Test func finderExtensionDeclaresItselfAnAgent() throws {
        let plist = try Self.infoPlist(at: "Resources/FinderExtension/Info.plist")
        #expect(plist["LSUIElement"] as? Bool == true)
    }

    private static func infoPlist(at relativePath: String) throws -> [String: Any] {
        // Tests/CoreTests/<this file>, three levels below the repository's root.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent(relativePath))
        return try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }
}
