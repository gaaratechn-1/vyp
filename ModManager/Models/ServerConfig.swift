import Foundation

// MARK: - Server Configuration Model (IP & Port)
public struct ServerConfig: Codable, Equatable {
    public var ipAddress: String
    public var port: Int
    public var useHttps: Bool
    public var apiKey: String
    public var isConnected: Bool
    public var lastSyncDate: Date?
    
    public init(
        ipAddress: String = "192.168.1.100",
        port: Int = 8080,
        useHttps: Bool = false,
        apiKey: String = "",
        isConnected: Bool = false,
        lastSyncDate: Date? = nil
    ) {
        self.ipAddress = ipAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        self.port = port
        self.useHttps = useHttps
        self.apiKey = apiKey
        self.isConnected = isConnected
        self.lastSyncDate = lastSyncDate
    }
    
    public var baseEndpoint: String {
        let scheme = useHttps ? "https" : "http"
        return "\(scheme)://\(ipAddress):\(port)"
    }
    
    public var baseURL: URL? {
        URL(string: baseEndpoint)
    }
}
