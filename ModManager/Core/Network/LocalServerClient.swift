import Foundation
import Combine

// MARK: - Cloud / Server Specific Restore Errors
public enum CloudRestoreError: LocalizedError {
    case serverOffline(endpoint: String, details: String)
    case itemNotFoundOnServer(bundleID: String, relativePath: String, serverMessage: String?)
    case serverError(statusCode: Int, message: String)
    case badURL(String)
    
    public var errorDescription: String? {
        switch self {
        case .serverOffline(let endpoint, let details):
            return "El servidor en la nube / local no está online o no responde (\(endpoint)).\n\nDetalle: \(details)\n\nComprueba que el servidor esté encendido ('python local_server.py') y que tu dispositivo esté conectado a la misma red Wi-Fi."
            
        case .itemNotFoundOnServer(let bundleID, let relativePath, let serverMessage):
            let extra = serverMessage != nil ? " (\(serverMessage!))" : ""
            return "El servidor está ONLINE, pero NO TIENE el archivo original para este elemento exacto\(extra).\n\n• Aplicación: [\(bundleID)]\n• Archivo requerido: \(relativePath)\n\nPara poder restaurarlo, debes colocar el archivo original en el servidor en la ruta:\noriginals_repo/\(bundleID)/\(relativePath)"
            
        case .serverError(let statusCode, let message):
            return "El servidor respondió con código HTTP \(statusCode): \(message)"
            
        case .badURL(let urlString):
            return "La URL del servidor es inválida: \(urlString)"
        }
    }
    
    public var failureReason: String? {
        switch self {
        case .serverOffline:
            return "Servidor Desconectado"
        case .itemNotFoundOnServer:
            return "Archivo No Encontrado en Servidor"
        case .serverError:
            return "Error de Servidor"
        case .badURL:
            return "URL Inválida"
        }
    }
}

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
    
    private let configStorageKey = "com.modmanager.server.config.v2"
    private let session: URLSession
    
    private init() {
        if let data = UserDefaults.standard.data(forKey: configStorageKey),
           let decoded = try? JSONDecoder().decode(ServerConfig.self, from: data) {
            self.config = decoded
        } else {
            // Predeterminado permanente por defecto
            self.config = ServerConfig.permanentDefault
        }
        
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 8
        sessionConfig.timeoutIntervalForResource = 20
        self.session = URLSession(configuration: sessionConfig)
    }
    
    private func saveConfig() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: configStorageKey)
        }
    }
    
    /// Restablece la configuración del servidor a los valores predeterminados permanentes
    public func resetToPermanentDefault() {
        self.config = ServerConfig.permanentDefault
        ModLog("Configuración de servidor restablecida al valor predeterminado permanente: \(config.baseEndpoint)", category: "NET")
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
                self.connectionStatusMessage = "URL inválida (\(config.baseEndpoint))"
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
                self.connectionStatusMessage = "Servidor Online (\(status))"
                self.config.isConnected = true
                self.config.lastSyncDate = Date()
                ModLog("Conexión exitosa al servidor local: \(self.config.baseEndpoint)", category: "NET")
            }
            return true
        } catch {
            await MainActor.run {
                self.isTestingConnection = false
                self.connectionStatusMessage = "Servidor Desconectado / Offline"
                self.config.isConnected = false
                ModLog("Fallo de conexión con \(self.config.baseEndpoint): \(error.localizedDescription)", category: "NET")
            }
            return false
        }
    }
    
    /// Obtiene el catálogo de Mods disponibles en el servidor
    public func fetchAvailableMods() async throws -> [ServerModDTO] {
        guard let url = URL(string: "\(config.baseEndpoint)/api/mods") else {
            throw CloudRestoreError.badURL("\(config.baseEndpoint)/api/mods")
        }
        
        var request = URLRequest(url: url)
        if !config.apiKey.isEmpty {
            request.addValue(config.apiKey, forHTTPHeaderField: "X-API-Key")
        }
        
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw CloudRestoreError.serverError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500, message: "No se pudo obtener el catálogo")
            }
            
            let mods = try JSONDecoder().decode([ServerModDTO].self, from: data)
            await MainActor.run {
                self.availableServerMods = mods
                self.config.lastSyncDate = Date()
                ModLog("Catálogo de servidor sincronizado: \(mods.count) mods disponibles", category: "NET")
            }
            return mods
        } catch let err as CloudRestoreError {
            throw err
        } catch {
            throw CloudRestoreError.serverOffline(endpoint: config.baseEndpoint, details: error.localizedDescription)
        }
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
            throw CloudRestoreError.badURL(fullURLString)
        }
        
        var request = URLRequest(url: url)
        if !config.apiKey.isEmpty {
            request.addValue(config.apiKey, forHTTPHeaderField: "X-API-Key")
        }
        
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 500
                throw CloudRestoreError.serverError(statusCode: code, message: "Error al descargar el payload del mod")
            }
            
            ModLog("Descarga de Mod completada (\(data.count) bytes)", category: "NET")
            return data
        } catch let err as CloudRestoreError {
            throw err
        } catch {
            throw CloudRestoreError.serverOffline(endpoint: config.baseEndpoint, details: error.localizedDescription)
        }
    }
    
    /// Descarga el archivo original limpio desde el servidor para restaurar.
    /// Distingue claramente entre servidor apagado (offline) y archivo no encontrado (404).
    public func downloadOriginalStockFile(bundleID: String, relativePath: String) async throws -> Data {
        let cleanRelative = relativePath
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        
        let safePath = cleanRelative.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? cleanRelative
        let urlString = "\(config.baseEndpoint)/api/originals/\(bundleID)/\(safePath)"
        
        guard let url = URL(string: urlString) else {
            throw CloudRestoreError.badURL(urlString)
        }
        
        var request = URLRequest(url: url)
        if !config.apiKey.isEmpty {
            request.addValue(config.apiKey, forHTTPHeaderField: "X-API-Key")
        }
        
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            // El servidor no es alcanzable o la conexión falló
            ModLog("Servidor offline o no alcanzable para restaurar: \(error.localizedDescription)", category: "NET")
            throw CloudRestoreError.serverOffline(
                endpoint: config.baseEndpoint,
                details: error.localizedDescription
            )
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudRestoreError.serverOffline(
                endpoint: config.baseEndpoint,
                details: "Respuesta no válida del servidor"
            )
        }
        
        if httpResponse.statusCode == 404 {
            // El servidor ESTÁ ONLINE, pero este elemento exacto no existe en el servidor
            var serverMessage: String?
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let msg = json["error"] as? String {
                serverMessage = msg
            }
            ModLog("Archivo no encontrado en servidor (404) para [\(bundleID)] ruta: \(cleanRelative)", category: "NET")
            throw CloudRestoreError.itemNotFoundOnServer(
                bundleID: bundleID,
                relativePath: cleanRelative,
                serverMessage: serverMessage
            )
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw CloudRestoreError.serverError(
                statusCode: httpResponse.statusCode,
                message: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            )
        }
        
        ModLog("Archivo original descargado del servidor (\(data.count) bytes) para \(cleanRelative)", category: "NET")
        return data
    }
}
