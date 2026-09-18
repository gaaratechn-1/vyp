import Foundation
import UIKit

public final class ContainerService: ObservableObject {
    public static let shared = ContainerService()
    
    @Published public private(set) var installedApps: [InstalledAppInfo] = []
    @Published public private(set) var isScanning: Bool = false
    @Published public private(set) var isMCMBridgeAvailable: Bool = false
    
    private let appDataRoot = "/var/mobile/Containers/Data/Application"
    
    private init() {
        checkBridgeStatus()
        refreshApps()
    }
    
    public func checkBridgeStatus() {
        isMCMBridgeAvailable = MCMBridgeAvailable()
        ModLog("Estado de MCM Bridge: \(isMCMBridgeAvailable ? "Disponible" : "No disponible / Simulado")", category: "MCM")
    }
    
    /// Resuelve la ruta física del sandbox para un bundleID dado
    public func resolveContainerPath(for bundleID: String) -> String? {
        var error: NSString?
        // Intentar activar contenedor clase 2 (Application Data)
        if let path = MCMActivateContainerPath(2, bundleID, false, &error), !path.isEmpty {
            ModLog("Contenedor resuelto vía MHA-C2 para [\(bundleID)]: \(path)", category: "MCM")
            return path
        }
        
        if let err = error {
            ModLog("Error al resolver contenedor [\(bundleID)]: \(err)", category: "MCM")
        }
        
        // Fallback: Escaneo directo del sistema de archivos si hay acceso
        if let path = scanContainerByMetadata(bundleID: bundleID) {
            return path
        }
        
        #if targetEnvironment(simulator)
        // Ruta de simulación para pruebas en simulador
        let simPath = (NSTemporaryDirectory() as NSString).appendingPathComponent("SimulatedContainers/\(bundleID)")
        try? FileManager.default.createDirectory(atPath: simPath, withIntermediateDirectories: true)
        return simPath
        #else
        return nil
        #endif
    }
    
    private func scanContainerByMetadata(bundleID: String) -> String? {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: appDataRoot) else { return nil }
        
        for item in items {
            let containerDir = (appDataRoot as NSString).appendingPathComponent(item)
            let metaPath = (containerDir as NSString).appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
            if let data = try? Data(contentsOf: URL(fileURLWithPath: metaPath)),
               let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
               let ident = plist["MCMMetadataIdentifier"] as? String, ident == bundleID {
                return containerDir
            }
        }
        return nil
    }
    
    /// Escanea las aplicaciones del dispositivo
    public func refreshApps() {
        isScanning = true
        DispatchQueue.global(qos: .userInitiated).async {
            var apps: [InstalledAppInfo] = []
            
            // 1. Obtener identificadores vía MCM Bridge si está disponible
            var error: NSString?
            let identifiers = MCMEnumerateIdentifiersForClass(2, 500, &error) as? [String] ?? []
            
            for bundleID in identifiers {
                let name = self.cleanAppDisplayName(from: bundleID)
                let container = self.resolveContainerPath(for: bundleID) ?? ""
                apps.append(InstalledAppInfo(bundleID: bundleID, displayName: name, containerPath: container))
            }
            
            // 2. Si no hay apps detectadas (ej. permisos restringidos o simulador), proveer apps de sistema comunes o simuladas
            if apps.isEmpty {
                let defaultApps = [
                    ("com.apple.mobilesafari", "Safari"),
                    ("com.apple.Preferences", "Ajustes"),
                    ("com.apple.MobileSMS", "Mensajes"),
                    ("com.apple.Photos", "Fotos"),
                    ("com.apple.Music", "Música"),
                    ("com.apple.DocumentsApp", "Archivos")
                ]
                for (bID, name) in defaultApps {
                    let path = self.resolveContainerPath(for: bID) ?? ""
                    apps.append(InstalledAppInfo(bundleID: bID, displayName: name, containerPath: path))
                }
            }
            
            let sorted = apps.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            
            DispatchQueue.main.async {
                self.installedApps = sorted
                self.isScanning = false
                ModLog("Total de aplicaciones detectadas: \(sorted.count)", category: "APP")
            }
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
