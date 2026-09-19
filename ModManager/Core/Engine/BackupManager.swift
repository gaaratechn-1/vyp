import Foundation
import CryptoKit

public struct BackupItemMetadata: Codable {
    public let modID: UUID
    public let bundleID: String
    public let relativePath: String
    public let originalSHA256: String
    public let backupDate: Date
    public let fileSize: Int64
}

public final class BackupManager {
    public static let shared = BackupManager()
    
    private let fileManager = FileManager.default
    
    private var backupRootURL: URL {
        let paths = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let root = paths[0].appendingPathComponent("ModBackups", isDirectory: true)
        if !fileManager.fileExists(atPath: root.path) {
            try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        }
        return root
    }
    
    private init() {}
    
    /// Genera la carpeta de almacenamiento de backup para un Mod específico
    private func backupDirectory(for modID: UUID) -> URL {
        let dir = backupRootURL.appendingPathComponent(modID.uuidString, isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    /// Realiza una copia de seguridad del archivo o carpeta original antes de reemplazarlo
    public func backupOriginal(
        sourceURL: URL,
        modID: UUID,
        bundleID: String,
        relativePath: String
    ) throws -> BackupItemMetadata? {
        let modDir = backupDirectory(for: modID)
        let filenameSafe = relativePath.replacingOccurrences(of: "/", with: "___")
        let destinationURL = modDir.appendingPathComponent(filenameSafe)
        let markerURL = modDir.appendingPathComponent(filenameSafe + ".new_marker")
        
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            ModLog("El elemento original no existe en \(sourceURL.path); registrando como nuevo para rollback limpio", category: "BCK")
            try? "".write(to: markerURL, atomically: true, encoding: .utf8)
            return BackupItemMetadata(
                modID: modID,
                bundleID: bundleID,
                relativePath: relativePath,
                originalSHA256: "NEW_CREATED",
                backupDate: Date(),
                fileSize: 0
            )
        }
        
        // Si ya hay un backup previo guardado, conservamos el backup original primario
        if fileManager.fileExists(atPath: destinationURL.path) {
            ModLog("Ya existe backup previo original para: \(relativePath)", category: "BCK")
            let data = try Data(contentsOf: destinationURL)
            let hash = SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
            return BackupItemMetadata(
                modID: modID,
                bundleID: bundleID,
                relativePath: relativePath,
                originalSHA256: hash,
                backupDate: Date(),
                fileSize: Int64(data.count)
            )
        }
        
        let attrs = try fileManager.attributesOfItem(atPath: sourceURL.path)
        let isDir = (attrs[.type] as? FileAttributeType) == .typeDirectory
        
        if isDir {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            ModLog("Copia de seguridad de directorio completada: \(relativePath)", category: "BCK")
            return BackupItemMetadata(
                modID: modID,
                bundleID: bundleID,
                relativePath: relativePath,
                originalSHA256: "DIRECTORY",
                backupDate: Date(),
                fileSize: 0
            )
        } else {
            let data = try Data(contentsOf: sourceURL)
            try data.write(to: destinationURL, options: .atomic)
            let hash = SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
            
            ModLog("Copia de seguridad de archivo original creada: \(relativePath) [SHA: \(hash.prefix(8))]", category: "BCK")
            return BackupItemMetadata(
                modID: modID,
                bundleID: bundleID,
                relativePath: relativePath,
                originalSHA256: hash,
                backupDate: Date(),
                fileSize: Int64(data.count)
            )
        }
    }
    
    /// Restaura el archivo original desde la copia de seguridad local (o elimina si fue creado por el mod)
    public func restoreOriginal(
        modID: UUID,
        targetURL: URL,
        relativePath: String
    ) throws -> Bool {
        let modDir = backupDirectory(for: modID)
        let filenameSafe = relativePath.replacingOccurrences(of: "/", with: "___")
        let backupURL = modDir.appendingPathComponent(filenameSafe)
        let markerURL = modDir.appendingPathComponent(filenameSafe + ".new_marker")
        
        // Si fue un archivo introducido nuevo por el mod, removerlo para dejar limpio el juego
        if fileManager.fileExists(atPath: markerURL.path) {
            if fileManager.fileExists(atPath: targetURL.path) {
                try fileManager.removeItem(at: targetURL)
            }
            ModLog("Archivo creado por mod eliminado limpiamente durante restauración: \(relativePath)", category: "BCK")
            return true
        }
        
        guard fileManager.fileExists(atPath: backupURL.path) else {
            ModLog("No se encontró copia de seguridad local para \(relativePath)", category: "BCK")
            return false
        }
        
        // Crear carpeta contenedora en el sandbox si no existe
        let parentDir = targetURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDir.path) {
            try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }
        
        // Remover el elemento actual modificado
        if fileManager.fileExists(atPath: targetURL.path) {
            try fileManager.removeItem(at: targetURL)
        }
        
        // Copiar el original respaldado
        try fileManager.copyItem(at: backupURL, to: targetURL)
        ModLog("Restauración local completada para: \(relativePath)", category: "BCK")
        return true
    }
    
    /// Verifica si existe un backup local para un elemento
    public func hasLocalBackup(modID: UUID, relativePath: String) -> Bool {
        let modDir = backupDirectory(for: modID)
        let filenameSafe = relativePath.replacingOccurrences(of: "/", with: "___")
        let backupURL = modDir.appendingPathComponent(filenameSafe)
        let markerURL = modDir.appendingPathComponent(filenameSafe + ".new_marker")
        return fileManager.fileExists(atPath: backupURL.path) || fileManager.fileExists(atPath: markerURL.path)
    }
    
    /// Elimina los backups de un Mod específico
    public func deleteBackup(for modID: UUID) {
        let modDir = backupDirectory(for: modID)
        try? fileManager.removeItem(at: modDir)
    }
    
    /// Calcula el espacio total ocupado por todos los backups
    public func totalBackupSize() -> Int64 {
        guard let enumerator = fileManager.enumerator(at: backupRootURL, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
               let size = values.fileSize {
                total += Int64(size)
            }
        }
        return total
    }
    
    /// Limpia todos los backups almacenados
    public func purgeAllBackups() {
        try? fileManager.removeItem(at: backupRootURL)
        try? fileManager.createDirectory(at: backupRootURL, withIntermediateDirectories: true)
        ModLog("Todos los backups locales han sido eliminados", category: "BCK")
    }
}
