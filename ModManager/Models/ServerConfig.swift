import Foundation

// MARK: - Server Configuration Model (IP & Port)
public struct ServerConfig: Codable, Equatable {
    public var ipAddress: String
    public var port: Int
    public var useHttps: Bool
    public var apiKey: String
    public var isConnected: Bool
    public var lastSyncDate: Date?
    
    public static let defaultIPAddress = "192.168.1.100"
    public static let defaultPort = 8080
    
    public init(
        ipAddress: String = ServerConfig.defaultIPAddress,
        port: Int = ServerConfig.defaultPort,
        useHttps: Bool = false,
        apiKey: String = "",
        isConnected: Bool = false,
        lastSyncDate: Date? = nil
    ) {
        let cleanIP = ipAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        self.ipAddress = cleanIP.isEmpty ? ServerConfig.defaultIPAddress : cleanIP
        self.port = port <= 0 ? ServerConfig.defaultPort : port
        self.useHttps = useHttps
        self.apiKey = apiKey
        self.isConnected = isConnected
        self.lastSyncDate = lastSyncDate
    }
    
    public var isPermanentDefault: Bool {
        return ipAddress == ServerConfig.defaultIPAddress && port == ServerConfig.defaultPort && !useHttps
    }
    
    public static var permanentDefault: ServerConfig {
        ServerConfig(ipAddress: defaultIPAddress, port: defaultPort)
    }
    
    public var baseEndpoint: String {
        let scheme = useHttps ? "https" : "http"
        return "\(scheme)://\(ipAddress):\(port)"
    }
    
    public var baseURL: URL? {
        URL(string: baseEndpoint)
    }
}
