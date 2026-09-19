import Foundation
import Combine
import CryptoKit

public enum ModEngineError: LocalizedError {
    case containerNotFound(String)
    case targetPathInvalid(String)
    case payloadMissing
    case replacementFailed(String)
    case backupFailed(String)
    case serverDownloadFailed(String)
    case restoreFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .containerNotFound(let bID):
            return "No se pudo acceder al sandbox de [\(bID)]. Verifica permisos o si la app está instalada."
        case .targetPathInvalid(let path):
            return "La ruta especificada es inválida: \(path)"
        case .payloadMissing:
            return "El archivo de reemplazo (payload) está vacío o no se ha proporcionado."
        case .replacementFailed(let reason):
            return "Error al reemplazar archivo: \(reason)"
        case .backupFailed(let reason):
            return "Fallo al crear la copia de seguridad: \(reason)"
        case .serverDownloadFailed(let reason):
            return "Error al descargar desde el servidor: \(reason)"
        case .restoreFailed(let reason):
            return "No se pudo restaurar el archivo original: \(reason)"
        }
    }
}

public final class ModEngine: ObservableObject {
    public static let shared = ModEngine()
    
    @Published public var modProfiles: [ModProfile] = []
    @Published public var isProcessing: Bool = false
    @Published public var activeOperationMessage: String?
    
    private let storageKey = "com.modmanager.profiles.v1"
    private let fileManager = FileManager.default
    
    private init() {
        loadProfiles()
    }
    
    // MARK: - Persistencia de Mods
    private func loadProfiles() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([ModProfile].self, from: data) {
            self.modProfiles = decoded
        } else {
            // Ejemplo predeterminado si está vacío
            self.modProfiles = []
        }
    }
    
    public func saveProfiles() {
        if let data = try? JSONEncoder().encode(modProfiles) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
    
    public func addOrUpdateProfile(_ profile: ModProfile) {
        if let index = modProfiles.firstIndex(where: { $0.id == profile.id }) {
            modProfiles[index] = profile
        } else {
            modProfiles.append(profile)
        }
        saveProfiles()
    }
    
    public func deleteProfile(id: UUID) {
        BackupManager.shared.deleteBackup(for: id)
        modProfiles.removeAll(where: { $0.id == id })
        saveProfiles()
    }
    
    // MARK: - Operaciones de Aplicación de Mods
    
    /// Aplica un Mod completo en el sandbox de la aplicación de destino
    public func applyMod(profile: ModProfile) async throws {
        await MainActor.run {
            self.isProcessing = true
            self.activeOperationMessage = "Aplicando mod: \(profile.name)..."
        }
        
        defer {
            Task { @MainActor in
                self.isProcessing = false
                self.activeOperationMessage = nil
            }
        }
        
        guard let containerPath = ContainerService.shared.resolveContainerPath(for: profile.targetBundleID) else {
            throw ModEngineError.containerNotFound(profile.targetBundleID)
        }
        
        let containerRootURL = URL(fileURLWithPath: containerPath, isDirectory: true)
        
        for item in profile.items {
            let targetURL = containerRootURL.appendingPathComponent(item.sanitizedRelativePath)
            
            // 1. Crear copia de seguridad automática del archivo original antes de tocar nada
            _ = try BackupManager.shared.backupOriginal(
                sourceURL: targetURL,
                modID: profile.id,
                bundleID: profile.targetBundleID,
                relativePath: item.sanitizedRelativePath
            )
            
            // 2. Obtener los datos de reemplazo (Mod)
            guard let payloadData = item.payloadData, !payloadData.isEmpty else {
                throw ModEngineError.payloadMissing
            }
            
            // 3. Realizar reemplazo atómico
            try performAtomicReplacement(data: payloadData, targetURL: targetURL)
        }
        
        await MainActor.run {
            if let idx = self.modProfiles.firstIndex(where: { $0.id == profile.id }) {
                self.modProfiles[idx].isApplied = true
                self.modProfiles[idx].status = .applied
                self.modProfiles[idx].lastRestoreSource = nil
                self.modProfiles[idx].lastBackupDate = Date()
                self.modProfiles[idx].updatedAt = Date()
                self.saveProfiles()
            }
            ModLog("Mod [\(profile.name)] aplicado exitosamente en \(profile.targetBundleID)", category: "ENG")
        }
    }
    
    /// Restaura el original desde el Backup Local
    public func restoreFromLocalBackup(profile: ModProfile) async throws {
        await MainActor.run {
            self.isProcessing = true
            self.activeOperationMessage = "Restaurando originales desde backup local..."
        }
        
        defer {
            Task { @MainActor in
                self.isProcessing = false
                self.activeOperationMessage = nil
            }
        }
        
        guard let containerPath = ContainerService.shared.resolveContainerPath(for: profile.targetBundleID) else {
            throw ModEngineError.containerNotFound(profile.targetBundleID)
        }
        
        let containerRootURL = URL(fileURLWithPath: containerPath, isDirectory: true)
        
        for item in profile.items {
            let targetURL = containerRootURL.appendingPathComponent(item.sanitizedRelativePath)
            
            let restored = try BackupManager.shared.restoreOriginal(
                modID: profile.id,
                targetURL: targetURL,
                relativePath: item.sanitizedRelativePath
            )
            
            if !restored {
                throw ModEngineError.restoreFailed("No se encontró backup local para \(item.sanitizedRelativePath)")
            }
        }
        
        await MainActor.run {
            if let idx = self.modProfiles.firstIndex(where: { $0.id == profile.id }) {
                self.modProfiles[idx].isApplied = false
                self.modProfiles[idx].status = .ready
                self.modProfiles[idx].lastRestoreSource = .localBackup
                self.modProfiles[idx].updatedAt = Date()
                self.saveProfiles()
            }
            ModLog("Restauración local completada para [\(profile.name)]", category: "ENG")
        }
    }
    
    /// Restaura el original descargándolo desde el Servidor Local IP:Puerto
    public func restoreFromServerOriginal(profile: ModProfile) async throws {
        await MainActor.run {
            self.isProcessing = true
            self.activeOperationMessage = "Descargando originales desde el servidor..."
        }
        
        defer {
            Task { @MainActor in
                self.isProcessing = false
                self.activeOperationMessage = nil
            }
        }
        
        guard let containerPath = ContainerService.shared.resolveContainerPath(for: profile.targetBundleID) else {
            throw ModEngineError.containerNotFound(profile.targetBundleID)
        }
        
        let containerRootURL = URL(fileURLWithPath: containerPath, isDirectory: true)
        
        for item in profile.items {
            let targetURL = containerRootURL.appendingPathComponent(item.sanitizedRelativePath)
            
            // Descargar stock original del servidor (lanza CloudRestoreError con detalle exacto)
            let originalData = try await LocalServerClient.shared.downloadOriginalStockFile(
                bundleID: profile.targetBundleID,
                relativePath: item.sanitizedRelativePath
            )
            
            // Reemplazo atómico con el archivo original del servidor
            try performAtomicReplacement(data: originalData, targetURL: targetURL)
        }
        
        await MainActor.run {
            if let idx = self.modProfiles.firstIndex(where: { $0.id == profile.id }) {
                self.modProfiles[idx].isApplied = false
                self.modProfiles[idx].status = .ready
                self.modProfiles[idx].lastRestoreSource = .server
                self.modProfiles[idx].updatedAt = Date()
                self.saveProfiles()
            }
            ModLog("Restauración desde servidor completada para [\(profile.name)]", category: "ENG")
        }
    }
    
    // MARK: - Reemplazo Atómico
    private func performAtomicReplacement(data: Data, targetURL: URL) throws {
        let parentDir = targetURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDir.path) {
            try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }
        
        let tempURL = parentDir.appendingPathComponent(".mod-staging-\(UUID().uuidString)")
        
        do {
            try data.write(to: tempURL, options: .atomic)
            
            if fileManager.fileExists(atPath: targetURL.path) {
                try fileManager.removeItem(at: targetURL)
            }
            
            try fileManager.moveItem(at: tempURL, to: targetURL)
            ModLog("Archivo reemplazado atómicamente: \(targetURL.lastPathComponent)", category: "ENG")
        } catch {
            try? fileManager.removeItem(at: tempURL)
            throw ModEngineError.replacementFailed(error.localizedDescription)
        }
    }
}
