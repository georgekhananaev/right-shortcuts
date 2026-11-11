import Foundation
@testable import RightShortcutsCore
import Testing

@Suite("Published pages")
struct PublishedPagesTests {
    /// The app and its App Store listing both link to these pages. Each is a file in the
    /// repository, so moving or deleting one would leave a dead link in a shipped build.
    @Test(arguments: [AppIdentity.privacyPolicyURL, AppIdentity.supportURL])
    func linkedPageIsAFileInTheRepository(_ link: URL) throws {
        #expect(link.scheme == "https")
        #expect(link.host() == "github.com")

        let parts = link.path().components(separatedBy: "/blob/main/")
        try #require(parts.count == 2, "The link should point at a file on the main branch")
        let page = Self.repositoryRoot.appendingPathComponent(parts[1])
        let text = try String(contentsOf: page, encoding: .utf8)
        #expect(text.contains(AppIdentity.displayName))
    }

    /// Tests/CoreTests/<this file>, three levels below the repository's root.
    private static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
}
