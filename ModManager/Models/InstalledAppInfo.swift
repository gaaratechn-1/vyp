import Foundation

// MARK: - Installed App Model
public struct InstalledAppInfo: Identifiable, Hashable, Equatable {
    public let bundleID: String
    public let displayName: String
    public let containerPath: String
    public let version: String
    
    public var id: String { bundleID }
    
    public init(
        bundleID: String,
        displayName: String,
        containerPath: String,
        version: String = ""
    ) {
        self.bundleID = bundleID
        self.displayName = displayName.isEmpty ? bundleID : displayName
        self.containerPath = containerPath
        self.version = version
    }
}
