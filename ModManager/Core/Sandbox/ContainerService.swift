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

// MARK: - 3105 LaunchServices CSStore Candidate Extractor
fileprivate enum LaunchServicesCandidateExtractor {
    private static func isIdentifierByte(_ byte: UInt8) -> Bool {
        switch byte {
        case 45, 46, 48...57, 65...90, 95, 97...122: // '-', '.', '0'-'9', 'A'-'Z', '_', 'a'-'z'
            return true
        default:
            return false
        }
    }

    static func identifiers(from data: Data, limit: Int = 32_768) -> [String] {
        guard limit > 0, !data.isEmpty else { return [] }

        return data.withUnsafeBytes { rawBuffer in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            var result: [String] = []
            var seen = Set<String>()
            var index = 0

            while index < bytes.count, result.count < limit {
                guard isIdentifierByte(bytes[index]) else {
                    index += 1
                    continue
                }

                let start = index
                while index < bytes.count, isIdentifierByte(bytes[index]) {
                    index += 1
                }
                let length = index - start
                guard (3...255).contains(length),
                      let identifier = String(bytes: bytes[start..<index], encoding: .utf8),
                      isValidBundleIdentifier(identifier),
                      !identifier.hasPrefix("group."),
                      !identifier.hasPrefix("systemgroup."),
                      seen.insert(identifier).inserted else {
                    continue
                }
                result.append(identifier)
            }

            return result
        }
    }

    static func isValidBundleIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty,
              value.utf8.count <= 255,
              value.contains("."),
              !value.contains(".."),
              value.first != ".",
              value.last != "." else {
            return false
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}

// MARK: - Container Service (Implementación 3105 MHA-C2)
public final class ContainerService: ObservableObject {
    public static let shared = ContainerService()
    
    @Published public private(set) var installedApps: [InstalledAppInfo] = []
    @Published public private(set) var isScanning: Bool = false
    @Published public private(set) var isMCMBridgeAvailable: Bool = false
    
    public static let appDataRoot = "/var/mobile/Containers/Data/Application"
    
    private var containerCache: [String: String] = [:]
    private let cacheLock = NSLock()
    
    // Aplicaciones Objetivo Exclusivas: Free Fire MAX y Free Fire
    public static let targetFreeFireBundleIDs: [String] = [
        "com.dts.freefiremax",
        "com.dts.freefireth"
    ]
    
    private init() {
        checkBridgeStatus()
        refreshApps()
    }
    
    public func checkBridgeStatus() {
        isMCMBridgeAvailable = MCMBridgeAvailable()
        ModLog("Estado de MCM Bridge: \(isMCMBridgeAvailable ? "Disponible" : "No disponible / Simulado")", category: "MCM")
    }
    
    // MARK: - Canonicidad de Rutas (3105)
    
    public static func canonicalPath(_ path: String) -> String {
        guard !path.isEmpty else { return "" }
        if path.hasPrefix("/private/var/") {
            return "/var" + path.dropFirst("/private/var".count)
        }
        return path
    }
    
    public static func isApplicationContainerPath(_ path: String) -> Bool {
        let canonicalRoot = canonicalPath(appDataRoot)
        let canon = canonicalPath(path)
        guard canon.hasPrefix(canonicalRoot + "/") else { return false }
        let uuidStr = (canon as NSString).lastPathComponent
        return UUID(uuidString: uuidStr) != nil
    }
    
    // MARK: - Resolución de Contenedores
    
    /// Resuelve y activa la ruta física del sandbox para un bundleID dado
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
        // 1. Activar contenedor clase 2 (Application Data) vía MHA-C2
        if let path = MCMActivateContainerPath(2, cleanID, false, &error), Self.isApplicationContainerPath(path) {
            rememberContainerPath(path, for: cleanID)
            return path
        }
        
        // 2. Consulta vía LSApplicationProxy
        let info = MCMAppInfoForBundleID(cleanID)
        if let container = info["container"] as? String,
           !container.isEmpty,
           Self.isApplicationContainerPath(container) {
            rememberContainerPath(container, for: cleanID)
            return container
        }
        
        #if targetEnvironment(simulator)
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
    }
    
    // MARK: - Catálogo de Bundles en Disco (/Applications, /System/Applications, /var/containers/Bundle/Application)
    private struct AppBundleMetadata {
        let bundleID: String
        let displayName: String
        let version: String
    }
    
    private func scanApplicationBundleCatalog() -> [String: AppBundleMetadata] {
        var catalog: [String: AppBundleMetadata] = [:]
        let fm = FileManager.default
        let roots: [(path: String, nested: Bool)] = [
            ("/var/containers/Bundle/Application", true),
            ("/Applications", false),
            ("/System/Applications", false)
        ]
        
        for root in roots {
            guard let entries = try? fm.contentsOfDirectory(atPath: root.path) else { continue }
            var appPaths: [String] = []
            
            if root.nested {
                for dir in entries.prefix(2048) {
                    guard UUID(uuidString: dir) != nil else { continue }
                    let containerDir = (root.path as NSString).appendingPathComponent(dir)
                    guard let children = try? fm.contentsOfDirectory(atPath: containerDir) else { continue }
                    for child in children.prefix(16) {
                        if child.hasSuffix(".app") {
                            appPaths.append((containerDir as NSString).appendingPathComponent(child))
                        }
                    }
                }
            } else {
                for entry in entries.prefix(2048) {
                    if entry.hasSuffix(".app") {
                        appPaths.append((root.path as NSString).appendingPathComponent(entry))
                    }
                }
            }
            
            for appPath in appPaths {
                let infoPath = (appPath as NSString).appendingPathComponent("Info.plist")
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: infoPath)),
                      let plist = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any],
                      let bundleID = (plist["CFBundleIdentifier"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !bundleID.isEmpty else {
                    continue
                }
                
                let name = (plist["CFBundleDisplayName"] as? String) ?? (plist["CFBundleName"] as? String) ?? self.cleanAppDisplayName(from: bundleID)
                let version = (plist["CFBundleShortVersionString"] as? String) ?? ""
                catalog[bundleID] = AppBundleMetadata(bundleID: bundleID, displayName: name, version: version)
            }
        }
        
        return catalog
    }
    
    // MARK: - Contenedores del Sandbox vía Inodos fsgetpath (Método 3105 bad_query_list)
    private func scanFilesystemContainers() -> [String: (bundleID: String, name: String)] {
        var result: [String: (bundleID: String, name: String)] = [:]
        let containerDirs = MCMEnumerateDirectoriesViaFSGetPath(Self.appDataRoot, 2_000_000)
        
        for dir in containerDirs {
            let metadataPath = (dir as NSString).appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: metadataPath)),
                  let plist = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any],
                  let bundleID = (plist["MCMMetadataIdentifier"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !bundleID.isEmpty,
                  !bundleID.hasPrefix("systemgroup.") else {
                continue
            }
            
            var name = ""
            if let info = plist["MCMMetadataInfo"] as? [String: Any] {
                name = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? ""
            }
            result[bundleID] = (bundleID: bundleID, name: name.isEmpty ? self.cleanAppDisplayName(from: bundleID) : name)
            rememberContainerPath(dir, for: bundleID)
        }
        
        return result
    }
    
    // MARK: - Escaneo Exclusivo de Free Fire (Free Fire MAX & Free Fire)
    
    public func refreshApps() {
        isScanning = true
        DispatchQueue.global(qos: .userInitiated).async {
            var appsMap: [String: InstalledAppInfo] = [:]
            
            let targetGames = [
                ("com.dts.freefiremax", "Free Fire MAX"),
                ("com.dts.freefireth", "Free Fire")
            ]
            
            for (bundleID, defaultName) in targetGames {
                var containerPath = self.resolveContainerPath(for: bundleID) ?? ""
                
                // Si aún no tenemos ruta, intentar activar con MHA-C2
                if containerPath.isEmpty {
                    var lookupErr: NSString?
                    if let path = MCMActivateContainerPath(2, bundleID, false, &lookupErr),
                       Self.isApplicationContainerPath(path) {
                        containerPath = path
                        self.rememberContainerPath(path, for: bundleID)
                    }
                }
                
                #if targetEnvironment(simulator)
                if containerPath.isEmpty {
                    let simPath = (NSTemporaryDirectory() as NSString).appendingPathComponent("SimulatedContainers/\(bundleID)")
                    self.prepareSimulatedContainer(at: simPath, bundleID: bundleID)
                    containerPath = simPath
                    self.rememberContainerPath(simPath, for: bundleID)
                }
                #endif
                
                var displayName = defaultName
                let info = MCMAppInfoForBundleID(bundleID)
                if let name = info["name"] as? String, !name.isEmpty && name != bundleID {
                    displayName = name
                }
                
                appsMap[bundleID] = InstalledAppInfo(
                    bundleID: bundleID,
                    displayName: displayName,
                    containerPath: containerPath,
                    version: "iOS",
                    isUserApp: true
                )
            }
            
            let resultList = Array(appsMap.values)
            self.publishApps(resultList)
            
            DispatchQueue.main.async {
                self.isScanning = false
                ModLog("Objetivos de Free Fire listos: \(self.installedApps.count)", category: "APP")
            }
        }
    }
    
    private func publishApps(_ list: [InstalledAppInfo]) {
        let sorted = list.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        DispatchQueue.main.async {
            self.installedApps = sorted
        }
    }
    
    /// Filtro estricto: Solo permite com.dts.freefiremax y com.dts.freefireth
    public static func shouldDisplayApp(bundleID: String) -> Bool {
        let clean = bundleID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return clean == "com.dts.freefiremax" || clean == "com.dts.freefireth"
    }
    
    // MARK: - Extracción de com.apple.LaunchServices-*.csstore (3105)
    
    private func extractLaunchServicesStoreIdentifiers() -> [String] {
        var cachePaths: [String] = []
        var seenCachePaths = Set<String>()
        
        func addPath(_ p: String) {
            let canon = Self.canonicalPath(p)
            if !canon.isEmpty && seenCachePaths.insert(canon).inserted {
                cachePaths.append(canon)
            }
        }
        
        // 1. Activar contenedor de com.apple.lsd (Clase 10 = System Container)
        var serviceLookupErr: NSString?
        if let lsdPath = MCMActivateContainerPath(10, "com.apple.lsd", false, &serviceLookupErr) {
            let cachePath = (lsdPath as NSString).appendingPathComponent("Library/Caches")
            addPath(cachePath)
            ModLog("3105: Contenedor com.apple.lsd activado: \(lsdPath)", category: "MCM")
        }
        
        // 2. Rutas del sistema estándar
        addPath("/var/mobile/Library/Caches")
        addPath("/var/db/lsd")
        
        var identifiers: [String] = []
        var seenIdentifiers = Set<String>()
        let fm = FileManager.default
        
        for cacheDir in cachePaths {
            guard let files = try? fm.contentsOfDirectory(atPath: cacheDir) else { continue }
            for filename in files {
                guard filename.hasPrefix("com.apple.LaunchServices-") && filename.hasSuffix(".csstore") else {
                    continue
                }
                let fullPath = (cacheDir as NSString).appendingPathComponent(filename)
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: fullPath), options: .mappedIfSafe) else {
                    continue
                }
                
                let extracted = LaunchServicesCandidateExtractor.identifiers(from: data, limit: 16_384)
                for id in extracted where seenIdentifiers.insert(id).inserted {
                    identifiers.append(id)
                }
                ModLog("3105: Extraídos \(extracted.count) identificadores de \(filename)", category: "MCM")
            }
        }
        
        return identifiers
    }
    
    // MARK: - Comprobación y Validación de Rutas
    
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
