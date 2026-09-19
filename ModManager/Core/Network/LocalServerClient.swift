import Foundation
import Combine
import Network

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
    
    // Píldora de estado en tiempo real (Punto 1)
    @Published public var isOnline: Bool = false
    @Published public var discoveredAddress: String? = nil
    
    private let configStorageKey = "com.modmanager.server.config.v2"
    private let session: URLSession
    private var browser: NWBrowser?
    private var udpListener: NWListener?
    private var pingTimer: Timer?
    
    private init() {
        if let data = UserDefaults.standard.data(forKey: configStorageKey),
           let decoded = try? JSONDecoder().decode(ServerConfig.self, from: data) {
            self.config = decoded
        } else {
            // Predeterminado permanente por defecto
            self.config = ServerConfig.permanentDefault
        }
        
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 4
        sessionConfig.timeoutIntervalForResource = 15
        self.session = URLSession(configuration: sessionConfig)
        
        // Iniciar auto-descubrimiento en segundo plano
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.startAutoDiscovery()
        }
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
    
    // MARK: - Auto-Descubrimiento Bonjour / mDNS & Beacon UDP (Punto 1)
    
    public func startAutoDiscovery() {
        startBonjourBrowser()
        startUDPBeaconListener()
        startPeriodicPing()
    }
    
    private func startBonjourBrowser() {
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_modmanager._tcp", domain: nil)
        let params = NWParameters()
        let b = NWBrowser(for: descriptor, using: params)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            for result in results {
                if case let .service(name, _, _, _) = result.endpoint {
                    ModLog("Bonjour: Servidor local encontrado: \(name)", category: "NET")
                    self?.resolveBonjourService(result.endpoint)
                }
            }
        }
        b.start(queue: .main)
        self.browser = b
    }
    
    private func resolveBonjourService(_ endpoint: NWEndpoint) {
        let connection = NWConnection(to: endpoint, using: .tcp)
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            if case .ready = state {
                if let remote = connection.currentPath?.remoteEndpoint,
                   case let .hostPort(host, port) = remote {
                    let hostString: String
                    switch host {
                    case .ipv4(let ip4): hostString = "\(ip4)"
                    case .ipv6(let ip6): hostString = "\(ip6)"
                    default: hostString = "\(host)"
                    }
                    self.applyDiscoveredServer(host: hostString, port: Int(port.rawValue))
                }
                connection.cancel()
            }
        }
        connection.start(queue: .main)
    }
    
    private func startUDPBeaconListener() {
        do {
            let params = NWParameters.udp
            params.allowLocalEndpointReuse = true
            let listener = try NWListener(using: params, on: 8081)
            listener.newConnectionHandler = { [weak self] conn in
                conn.start(queue: .main)
                conn.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, _, _ in
                    if let data = data, let str = String(data: data, encoding: .utf8), str.hasPrefix("MODMANAGER_BEACON:") {
                        let urlStr = String(str.dropFirst("MODMANAGER_BEACON:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                        if let u = URL(string: urlStr), let h = u.host, let p = u.port {
                            self?.applyDiscoveredServer(host: h, port: p)
                        }
                    }
                    conn.cancel()
                }
            }
            listener.start(queue: .main)
            self.udpListener = listener
        } catch {
            ModLog("Listener UDP no iniciado: \(error.localizedDescription)", category: "NET")
        }
    }
    
    private func applyDiscoveredServer(host: String, port: Int) {
        DispatchQueue.main.async {
            if self.config.host != host || self.config.port != port {
                ModLog("Servidor local descubierto automáticamente: \(host):\(port)", category: "NET")
                self.config.host = host
                self.config.port = port
                self.discoveredAddress = "\(host):\(port)"
            }
            Task {
                _ = await self.testConnection()
            }
        }
    }
    
    private func startPeriodicPing() {
        Task { _ = await self.testConnection() }
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: true) { [weak self] _ in
            guard let client = self else { return }
            Task {
                _ = await client.testConnection()
            }
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
                self.connectionStatusMessage = "URL inválida (\(config.baseEndpoint))"
                self.config.isConnected = false
                self.isOnline = false
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
                    self.isOnline = false
                }
                return false
            }
            
            let status = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["status"] as? String ?? "OK"
            
            await MainActor.run {
                self.isTestingConnection = false
                self.connectionStatusMessage = "Servidor Online (\(status))"
                self.config.isConnected = true
                self.config.lastSyncDate = Date()
                self.isOnline = true
                self.discoveredAddress = "\(self.config.host):\(self.config.port)"
                ModLog("Conexión exitosa al servidor local: \(self.config.baseEndpoint)", category: "NET")
            }
            return true
        } catch {
            await MainActor.run {
                self.isTestingConnection = false
                self.connectionStatusMessage = "Sin conexión: \(error.localizedDescription)"
                self.config.isConnected = false
                self.isOnline = false
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
