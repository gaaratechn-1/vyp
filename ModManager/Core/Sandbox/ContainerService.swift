import Foundation
import UIKit

// MARK: - Sandbox File Item Model
public struct SandboxFileItem: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let relativePath: String
    public let fullPath: String
    public let isDirectory: Bool
    public let fileSizeBytes: Int64
    public let modificationDate: Date?
    public let childCount: Int?
    
    public init(
        name: String,
        relativePath: String,
        fullPath: String,
        isDirectory: Bool,
        fileSizeBytes: Int64 = 0,
        modificationDate: Date? = nil,
        childCount: Int? = nil
    ) {
        self.id = fullPath
        self.name = name
        self.relativePath = relativePath
        self.fullPath = fullPath
        self.isDirectory = isDirectory
        self.fileSizeBytes = fileSizeBytes
        self.modificationDate = modificationDate
        self.childCount = childCount
    }
    
    public var formattedSize: String {
        if isDirectory {
            if let count = childCount {
                return "\(count) elementos"
            }
            return "Carpeta"
        }
        let bytes = Double(fileSizeBytes)
        if bytes < 1024 {
            return "\(fileSizeBytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", bytes / 1024.0)
        } else {
            return String(format: "%.2f MB", bytes / (1024.0 * 1024.0))
        }
    }
}

// MARK: - Path Validation Result Model
public struct PathValidationInfo: Equatable {
    public enum Status: Equatable {
        case fileExists
        case directoryExists
        case parentExists
        case targetNotFound
        case containerInaccessible
    }
    
    public let status: Status
    public let title: String
    public let message: String
    public let fullPath: String?
    public let fileSize: Int64?
    public let modificationDate: Date?
    
    public var isAvailable: Bool {
        status == .fileExists || status == .parentExists || status == .directoryExists
    }
    
    public var formattedSize: String? {
        guard let bytes = fileSize else { return nil }
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024.0)
        } else {
            return String(format: "%.2f MB", Double(bytes) / (1024.0 * 1024.0))
        }
    }
}

// MARK: - Container Service
public final class ContainerService: ObservableObject {
    public static let shared = ContainerService()
    
    @Published public private(set) var installedApps: [InstalledAppInfo] = []
    @Published public private(set) var isScanning: Bool = false
    @Published public private(set) var isMCMBridgeAvailable: Bool = false
    
    private let appDataRoots = [
        "/var/mobile/Containers/Data/Application",
        "/private/var/mobile/Containers/Data/Application"
    ]
    
    private let appBundleRoots = [
        "/var/containers/Bundle/Application",
        "/private/var/containers/Bundle/Application"
    ]
    
    private var containerCache: [String: String] = [:]
    private let cacheLock = NSLock()
    
    private init() {
        checkBridgeStatus()
        refreshApps()
    }
    
    public func checkBridgeStatus() {
        isMCMBridgeAvailable = MCMBridgeAvailable()
        ModLog("Estado de MCM Bridge: \(isMCMBridgeAvailable ? "Disponible" : "No disponible / Simulado")", category: "MCM")
    }
    
    // MARK: - Resolución de Contenedores
    
    /// Resuelve la ruta física del sandbox para un bundleID dado
    public func resolveContainerPath(for bundleID: String) -> String? {
        let cleanID = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanID.isEmpty else { return nil }
        
        cacheLock.lock()
        if let cached = containerCache[cleanID], FileManager.default.fileExists(atPath: cached) {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()
        
        var error: NSString?
        // 1. Intentar activar contenedor clase 2 (Application Data) vía MCM Bridge
        if let path = MCMActivateContainerPath(2, cleanID, false, &error), !path.isEmpty {
            ModLog("Contenedor resuelto vía MHA-C2 para [\(cleanID)]: \(path)", category: "MCM")
            rememberContainerPath(path, for: cleanID)
            return path
        }
        
        // 2. Intentar vía LSApplicationWorkspace
        if let path = resolveContainerViaWorkspace(bundleID: cleanID) {
            ModLog("Contenedor resuelto vía LSApplicationWorkspace para [\(cleanID)]: \(path)", category: "MCM")
            rememberContainerPath(path, for: cleanID)
            return path
        }
        
        // 3. Fallback: Escaneo directo de metadata en el sistema de archivos
        if let path = scanContainerByMetadata(bundleID: cleanID) {
            ModLog("Contenedor resuelto vía metadata FS para [\(cleanID)]: \(path)", category: "MCM")
            rememberContainerPath(path, for: cleanID)
            return path
        }
        
        #if targetEnvironment(simulator)
        // Ruta de simulación para pruebas en simulador
        let simPath = (NSTemporaryDirectory() as NSString).appendingPathComponent("SimulatedContainers/\(cleanID)")
        prepareSimulatedContainer(at: simPath, bundleID: cleanID)
        rememberContainerPath(simPath, for: cleanID)
        return simPath
        #else
        return nil
        #endif
    }
    
    private func rememberContainerPath(_ path: String, for bundleID: String) {
        cacheLock.lock()
        containerCache[bundleID] = path
        cacheLock.unlock()
    }
    
    private func prepareSimulatedContainer(at path: String, bundleID: String) {
        let fm = FileManager.default
        let docs = (path as NSString).appendingPathComponent("Documents")
        let prefs = (path as NSString).appendingPathComponent("Library/Preferences")
        let caches = (path as NSString).appendingPathComponent("Library/Caches")
        
        try? fm.createDirectory(atPath: docs, withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: prefs, withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: caches, withIntermediateDirectories: true)
        
        let sampleSave = (docs as NSString).appendingPathComponent("game_save.dat")
        if !fm.fileExists(atPath: sampleSave) {
            try? "sample_game_save_data_100coins".write(toFile: sampleSave, atomically: true, encoding: .utf8)
        }
        let samplePlist = (prefs as NSString).appendingPathComponent("\(bundleID).plist")
        if !fm.fileExists(atPath: samplePlist) {
            try? "<plist version=\"1.0\"><dict><key>UserModInstalled</key><false/></dict></plist>".write(toFile: samplePlist, atomically: true, encoding: .utf8)
        }
    }
    
    // MARK: - Escaneo de Aplicaciones Multi-Nivel
    
    /// Escanea exhaustivamente todas las aplicaciones instaladas (Usuario y Sistema)
    public func refreshApps() {
        isScanning = true
        DispatchQueue.global(qos: .userInitiated).async {
            var appsMap: [String: InstalledAppInfo] = [:]
            
            // Nivel 1: LSApplicationWorkspace (Enumeración de todas las apps instaladas reales)
            self.scanViaLSApplicationWorkspace(into: &appsMap)
            
            // Nivel 2: Escaneo directo de directorios /var/mobile/Containers/Data/Application
            self.scanViaFileSystemMetadata(into: &appsMap)
            
            // Nivel 3: MCM Bridge Enumeration (si está disponible)
            var error: NSString?
            let identifiers = MCMEnumerateIdentifiersForClass(2, 1000, &error)
            for bundleID in identifiers {
                if appsMap[bundleID] == nil {
                    let name = self.cleanAppDisplayName(from: bundleID)
                    let container = self.resolveContainerPath(for: bundleID) ?? ""
                    let isUser = !bundleID.hasPrefix("com.apple.")
                    appsMap[bundleID] = InstalledAppInfo(
                        bundleID: bundleID,
                        displayName: name,
                        containerPath: container,
                        isUserApp: isUser
                    )
                }
            }
            
            // Nivel 4: Si la lista sigue vacía (ej. Simulador sin permisos de sistema), cargar apps comunes
            if appsMap.isEmpty {
                let defaultApps = [
                    ("com.activision.callofduty.shooter", "Call of Duty: Mobile", true),
                    ("com.tencent.ig", "PUBG MOBILE", true),
                    ("com.dts.freefireth", "Free Fire", true),
                    ("com.roblox.robloxmobile", "Roblox", true),
                    ("com.apple.mobilesafari", "Safari", false),
                    ("com.apple.Preferences", "Ajustes", false),
                    ("com.apple.MobileSMS", "Mensajes", false),
                    ("com.apple.Photos", "Fotos", false),
                    ("com.apple.Music", "Música", false),
                    ("com.apple.DocumentsApp", "Archivos", false)
                ]
                for (bID, name, isUser) in defaultApps {
                    let path = self.resolveContainerPath(for: bID) ?? ""
                    appsMap[bID] = InstalledAppInfo(
                        bundleID: bID,
                        displayName: name,
                        containerPath: path,
                        isUserApp: isUser
                    )
                }
            }
            
            let sorted = Array(appsMap.values).sorted {
                // Apps de usuario primero, luego orden alfabético
                if $0.isUserApp != $1.isUserApp {
                    return $0.isUserApp && !$1.isUserApp
                }
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            
            DispatchQueue.main.async {
                self.installedApps = sorted
                self.isScanning = false
                ModLog("Total de aplicaciones detectadas: \(sorted.count)", category: "APP")
            }
        }
    }
    
    // MARK: - Escaneo Nivel 1: LSApplicationWorkspace
    private func scanViaLSApplicationWorkspace(into map: inout [String: InstalledAppInfo]) {
        guard let workspaceClass = NSClassFromString("LSApplicationWorkspace") as? NSObject.Type else {
            return
        }
        
        let selDefault = NSSelectorFromString("defaultWorkspace")
        guard workspaceClass.responds(to: selDefault),
              let workspace = workspaceClass.perform(selDefault)?.takeUnretainedValue() as? NSObject else {
            return
        }
        
        var proxies: [NSObject] = []
        let selInstalled = NSSelectorFromString("allInstalledApplications")
        let selAll = NSSelectorFromString("allApplications")
        
        if workspace.responds(to: selInstalled),
           let list = workspace.perform(selInstalled)?.takeUnretainedValue() as? [NSObject] {
            proxies = list
        } else if workspace.responds(to: selAll),
                  let list = workspace.perform(selAll)?.takeUnretainedValue() as? [NSObject] {
            proxies = list
        }
        
        for proxy in proxies {
            let selAppID = NSSelectorFromString("applicationIdentifier")
            let selBundleID = NSSelectorFromString("bundleIdentifier")
            var bID: String?
            
            if proxy.responds(to: selAppID),
               let id = proxy.perform(selAppID)?.takeUnretainedValue() as? String {
                bID = id
            } else if proxy.responds(to: selBundleID),
                      let id = proxy.perform(selBundleID)?.takeUnretainedValue() as? String {
                bID = id
            }
            
            guard let bundleID = bID, !bundleID.isEmpty else { continue }
            
            // Nombre mostrado
            var displayName = bundleID
            let selName = NSSelectorFromString("localizedName")
            if proxy.responds(to: selName),
               let name = proxy.perform(selName)?.takeUnretainedValue() as? String, !name.isEmpty {
                displayName = name
            } else {
                displayName = cleanAppDisplayName(from: bundleID)
            }
            
            // Ruta del contenedor de datos
            var containerPath = ""
            let selDataContainer = NSSelectorFromString("dataContainerURL")
            if proxy.responds(to: selDataContainer),
               let url = proxy.perform(selDataContainer)?.takeUnretainedValue() as? NSURL,
               let path = url.path, !path.isEmpty {
                containerPath = path
                rememberContainerPath(path, for: bundleID)
            }
            
            // Tipo de app (Usuario vs Sistema)
            var isUser = true
            let selAppType = NSSelectorFromString("applicationType")
            if proxy.responds(to: selAppType),
               let typeStr = proxy.perform(selAppType)?.takeUnretainedValue() as? String {
                isUser = (typeStr.caseInsensitiveCompare("User") == .orderedSame)
            } else if bundleID.hasPrefix("com.apple.") {
                isUser = false
            }
            
            // Versión
            var version = ""
            let selVersion = NSSelectorFromString("shortVersionString")
            if proxy.responds(to: selVersion),
               let ver = proxy.perform(selVersion)?.takeUnretainedValue() as? String {
                version = ver
            }
            
            map[bundleID] = InstalledAppInfo(
                bundleID: bundleID,
                displayName: displayName,
                containerPath: containerPath,
                version: version,
                isUserApp: isUser
            )
        }
    }
    
    private func resolveContainerViaWorkspace(bundleID: String) -> String? {
        guard let workspaceClass = NSClassFromString("LSApplicationWorkspace") as? NSObject.Type else {
            return nil
        }
        let selDefault = NSSelectorFromString("defaultWorkspace")
        guard workspaceClass.responds(to: selDefault),
              let workspace = workspaceClass.perform(selDefault)?.takeUnretainedValue() as? NSObject else {
            return nil
        }
        
        let selAppForID = NSSelectorFromString("applicationProxyForIdentifier:")
        if workspace.responds(to: selAppForID),
           let proxy = workspace.perform(selAppForID, with: bundleID)?.takeUnretainedValue() as? NSObject {
            let selDataContainer = NSSelectorFromString("dataContainerURL")
            if proxy.responds(to: selDataContainer),
               let url = proxy.perform(selDataContainer)?.takeUnretainedValue() as? NSURL,
               let path = url.path, !path.isEmpty, FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return nil
    }
    
    // MARK: - Escaneo Nivel 2: Sistema de Archivos
    private func scanViaFileSystemMetadata(into map: inout [String: InstalledAppInfo]) {
        let fm = FileManager.default
        for root in appDataRoots {
            guard let items = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for item in items {
                let containerDir = (root as NSString).appendingPathComponent(item)
                let metaPath = (containerDir as NSString).appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
                if let data = try? Data(contentsOf: URL(fileURLWithPath: metaPath)),
                   let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
                   let bundleID = plist["MCMMetadataIdentifier"] as? String, !bundleID.isEmpty {
                    
                    rememberContainerPath(containerDir, for: bundleID)
                    
                    if map[bundleID] == nil {
                        let name = resolveDisplayNameFromBundle(bundleID: bundleID) ?? cleanAppDisplayName(from: bundleID)
                        let isUser = !bundleID.hasPrefix("com.apple.")
                        map[bundleID] = InstalledAppInfo(
                            bundleID: bundleID,
                            displayName: name,
                            containerPath: containerDir,
                            isUserApp: isUser
                        )
                    } else if map[bundleID]?.containerPath.isEmpty == true {
                        // Actualizar ruta si faltaba
                        let existing = map[bundleID]!
                        map[bundleID] = InstalledAppInfo(
                            bundleID: existing.bundleID,
                            displayName: existing.displayName,
                            containerPath: containerDir,
                            version: existing.version,
                            isUserApp: existing.isUserApp
                        )
                    }
                }
            }
        }
    }
    
    private func scanContainerByMetadata(bundleID: String) -> String? {
        let fm = FileManager.default
        for root in appDataRoots {
            guard let items = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for item in items {
                let containerDir = (root as NSString).appendingPathComponent(item)
                let metaPath = (containerDir as NSString).appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
                if let data = try? Data(contentsOf: URL(fileURLWithPath: metaPath)),
                   let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
                   let ident = plist["MCMMetadataIdentifier"] as? String, ident == bundleID {
                    return containerDir
                }
            }
        }
        return nil
    }
    
    private func resolveDisplayNameFromBundle(bundleID: String) -> String? {
        let fm = FileManager.default
        for root in appBundleRoots {
            guard let items = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for item in items {
                let bundleDir = (root as NSString).appendingPathComponent(item)
                guard let subItems = try? fm.contentsOfDirectory(atPath: bundleDir) else { continue }
                for sub in subItems where sub.hasSuffix(".app") {
                    let appDir = (bundleDir as NSString).appendingPathComponent(sub)
                    let infoPlistPath = (appDir as NSString).appendingPathComponent("Info.plist")
                    if let data = try? Data(contentsOf: URL(fileURLWithPath: infoPlistPath)),
                       let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
                       let ident = plist["CFBundleIdentifier"] as? String, ident == bundleID {
                        if let name = plist["CFBundleDisplayName"] as? String, !name.isEmpty {
                            return name
                        }
                        if let name = plist["CFBundleName"] as? String, !name.isEmpty {
                            return name
                        }
                    }
                }
            }
        }
        return nil
    }
    
    // MARK: - Comprobación y Validación de Rutas
    
    /// Valida exhaustivamente si la ruta existe en el sandbox de la aplicación de destino
    public func validatePath(bundleID: String, relativePath: String) -> PathValidationInfo {
        let cleanRelative = relativePath
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        
        guard let containerPath = resolveContainerPath(for: bundleID) else {
            return PathValidationInfo(
                status: .containerInaccessible,
                title: "Sandbox No Accesible",
                message: "No se pudo resolver la ruta del sandbox para [\(bundleID)].",
                fullPath: nil,
                fileSize: nil,
                modificationDate: nil
            )
        }
        
        guard !cleanRelative.isEmpty else {
            return PathValidationInfo(
                status: .directoryExists,
                title: "Raíz del Sandbox",
                message: "Apunta a la raíz del contenedor de la aplicación.",
                fullPath: containerPath,
                fileSize: nil,
                modificationDate: nil
            )
        }
        
        let containerRootURL = URL(fileURLWithPath: containerPath, isDirectory: true)
        let targetURL = containerRootURL.appendingPathComponent(cleanRelative)
        let targetPath = targetURL.path
        let fm = FileManager.default
        
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: targetPath, isDirectory: &isDir) {
            let attrs = try? fm.attributesOfItem(atPath: targetPath)
            let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
            let modDate = attrs?[.modificationDate] as? Date
            
            if isDir.boolValue {
                let itemsCount = (try? fm.contentsOfDirectory(atPath: targetPath))?.count ?? 0
                return PathValidationInfo(
                    status: .directoryExists,
                    title: "Carpeta Existente",
                    message: "La carpeta existe en el sandbox y contiene \(itemsCount) elementos.",
                    fullPath: targetPath,
                    fileSize: nil,
                    modificationDate: modDate
                )
            } else {
                return PathValidationInfo(
                    status: .fileExists,
                    title: "Archivo Disponible",
                    message: "El archivo existe actualmente en el sandbox.",
                    fullPath: targetPath,
                    fileSize: size,
                    modificationDate: modDate
                )
            }
        }
        
        // Comprobar si al menos la carpeta padre existe
        let parentDir = targetURL.deletingLastPathComponent().path
        if fm.fileExists(atPath: parentDir) {
            return PathValidationInfo(
                status: .parentExists,
                title: "Fichero Nuevo (Carpeta Existe)",
                message: "El archivo aún no existe, pero su carpeta contenedora sí está disponible.",
                fullPath: targetPath,
                fileSize: 0,
                modificationDate: nil
            )
        }
        
        return PathValidationInfo(
            status: .targetNotFound,
            title: "Ruta No Creada Aún",
            message: "La ruta completa se creará automáticamente al aplicar el Mod.",
            fullPath: targetPath,
            fileSize: nil,
            modificationDate: nil
        )
    }
    
    // MARK: - Explorador de Archivos del Sandbox
    
    /// Lista el contenido de una carpeta relativa dentro del sandbox de la app
    public func listContents(bundleID: String, subpath: String) -> [SandboxFileItem] {
        guard let containerPath = resolveContainerPath(for: bundleID) else { return [] }
        
        let cleanSubpath = subpath
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        
        let rootURL = URL(fileURLWithPath: containerPath, isDirectory: true)
        let currentFolderURL = cleanSubpath.isEmpty ? rootURL : rootURL.appendingPathComponent(cleanSubpath)
        let currentPath = currentFolderURL.path
        let fm = FileManager.default
        
        guard let contents = try? fm.contentsOfDirectory(atPath: currentPath) else {
            return []
        }
        
        var items: [SandboxFileItem] = []
        for name in contents {
            // Ignorar archivos ocultos irrelevantes si se desea, o mostrarlos con prefijo
            let itemURL = currentFolderURL.appendingPathComponent(name)
            let itemPath = itemURL.path
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: itemPath, isDirectory: &isDir) else { continue }
            
            let itemRelative = cleanSubpath.isEmpty ? name : "\(cleanSubpath)/\(name)"
            let attrs = try? fm.attributesOfItem(atPath: itemPath)
            let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
            let modDate = attrs?[.modificationDate] as? Date
            var childCount: Int? = nil
            if isDir.boolValue {
                childCount = (try? fm.contentsOfDirectory(atPath: itemPath))?.count
            }
            
            items.append(SandboxFileItem(
                name: name,
                relativePath: itemRelative,
                fullPath: itemPath,
                isDirectory: isDir.boolValue,
                fileSizeBytes: size,
                modificationDate: modDate,
                childCount: childCount
            ))
        }
        
        // Carpetas primero, luego orden alfabético
        return items.sorted {
            if $0.isDirectory != $1.isDirectory {
                return $0.isDirectory && !$1.isDirectory
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
    
    private func cleanAppDisplayName(from bundleID: String) -> String {
        let parts = bundleID.split(separator: ".")
        if let last = parts.last {
            return String(last).capitalized
        }
        return bundleID
    }
}
