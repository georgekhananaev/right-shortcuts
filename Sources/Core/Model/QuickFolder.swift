import Foundation

/// A favorite folder used by Copy To, Move To and Go To.
public struct QuickFolder: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var path: String
    public var customName: String?

    public init(id: UUID = UUID(), path: String, customName: String? = nil) {
        self.id = id
        self.path = path
        self.customName = customName
    }

    public var name: String {
        if let customName, !customName.isEmpty { return customName }
        let last = (path as NSString).lastPathComponent
        return last.isEmpty ? path : last
    }
}
