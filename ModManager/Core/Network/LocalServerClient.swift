import Foundation
import Combine

public struct ServerModDTO: Codable, Identifiable {
    public let id: String
    public let name: String
    public let bundleID: String
    public let relativePath: String
    public let version: String
    public let description: String?
    public let downloadURL: String
    public let originalURL: String?
    public let sha256: String?
}

public final class LocalServerClient: ObservableObject {
    public static let shared = LocalServerClient()
    
    @Published public var config: ServerConfig {
        didSet {
            saveConfig()
        }
    }
    
    @Published public var isTestingConnection: Bool = false
    @Published public var connectionStatusMessage: String?
    @Published public var availableServerMods: [ServerModDTO] = []
    
    private let configStorageKey = "com.modmanager.server.config"
    private let session: URLSession
    
    private init() {
        if let data = UserDefaults.standard.data(forKey: configStorageKey),
           let decoded = try? JSONDecoder().decode(ServerConfig.self, from: data) {
            self.config = decoded
        } else {
            self.config = ServerConfig(ipAddress: "192.168.1.100", port: 8080)
        }
        
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 10
        sessionConfig.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: sessionConfig)
    }
    
    private func saveConfig() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: configStorageKey)
        }
    }
    
    /// Prueba la conexión con el servidor local IP:Puerto
    public func testConnection() async -> Bool {
        await MainActor.run {
            self.isTestingConnection = true
            self.connectionStatusMessage = "Conectando a \(config.baseEndpoint)..."
        }
        
        guard let url = URL(string: "\(config.baseEndpoint)/health") else {
            await MainActor.run {
                self.isTestingConnection = false
                self.connectionStatusMessage = "URL inválida"
                self.config.isConnected = false
            }
            return false
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if !config.apiKey.isEmpty {
            request.addValue(config.apiKey, forHTTPHeaderField: "X-API-Key")
        }
        
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                await MainActor.run {
                    self.isTestingConnection = false
                    self.connectionStatusMessage = "Servidor respondió con código de error"
                    self.config.isConnected = false
                }
                return false
            }
            
            let status = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["status"] as? String ?? "OK"
            
            await MainActor.run {
                self.isTestingConnection = false
                self.connectionStatusMessage = "Conexión exitosa (\(status))"
                self.config.isConnected = true
                self.config.lastSyncDate = Date()
                ModLog("Conexión exitosa al servidor local: \(self.config.baseEndpoint)", category: "NET")
            }
            return true
        } catch {
            await MainActor.run {
                self.isTestingConnection = false
                self.connectionStatusMessage = "Fallo de conexión: \(error.localizedDescription)"
                self.config.isConnected = false
                ModLog("Fallo de conexión con \(self.config.baseEndpoint): \(error.localizedDescription)", category: "NET")
            }
            return false
        }
    }
    
    /// Obtiene el catálogo de Mods disponibles en el servidor
    public func fetchAvailableMods() async throws -> [ServerModDTO] {
        guard let url = URL(string: "\(config.baseEndpoint)/api/mods") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        if !config.apiKey.isEmpty {
            request.addValue(config.apiKey, forHTTPHeaderField: "X-API-Key")
        }
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        let mods = try JSONDecoder().decode([ServerModDTO].self, from: data)
        await MainActor.run {
            self.availableServerMods = mods
            self.config.lastSyncDate = Date()
            ModLog("Catálogo de servidor sincronizado: \(mods.count) mods disponibles", category: "NET")
        }
        return mods
    }
    
    /// Descarga el archivo de contenido de un Mod desde el servidor
    public func downloadModData(urlString: String) async throws -> Data {
        let fullURLString: String
        if urlString.hasPrefix("http://") || urlString.hasPrefix("https://") {
            fullURLString = urlString
        } else {
            fullURLString = "\(config.baseEndpoint)/\(urlString.trimmingCharacters(in: CharacterSet(charactersIn: "/")))"
        }
        
        guard let url = URL(string: fullURLString) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        if !config.apiKey.isEmpty {
            request.addValue(config.apiKey, forHTTPHeaderField: "X-API-Key")
        }
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        ModLog("Descarga de Mod completada (\(data.count) bytes)", category: "NET")
        return data
    }
    
    /// Descarga el archivo original limpio desde el servidor para restaurar
    public func downloadOriginalStockFile(bundleID: String, relativePath: String) async throws -> Data {
        let safePath = relativePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? relativePath
        let urlString = "\(config.baseEndpoint)/api/originals/\(bundleID)/\(safePath)"
        
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        if !config.apiKey.isEmpty {
            request.addValue(config.apiKey, forHTTPHeaderField: "X-API-Key")
        }
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            ModLog("Archivo original no disponible en servidor para \(relativePath)", category: "NET")
            throw URLError(.resourceUnavailable)
        }
        
        ModLog("Archivo original descargado del servidor (\(data.count) bytes) para \(relativePath)", category: "NET")
        return data
    }
}
