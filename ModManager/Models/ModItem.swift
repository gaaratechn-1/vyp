import Foundation
import CryptoKit

// MARK: - Mod Element / Item Model
public struct ModItem: Codable, Identifiable, Hashable {
    public var id: UUID
    /// Ruta relativa exacta dentro del sandbox de la app (ej: "Documents/game_save.json" o "Library/Preferences/")
    public var relativePath: String
    /// Indica si el elemento es una carpeta completa o un archivo
    public var isDirectory: Bool
    /// Nombre del archivo de reemplazo o identificador del payload
    public var payloadFilename: String
    /// Contenido binario del mod (si se almacena embebido)
    public var payloadData: Data?
    /// Hash SHA-256 del contenido modificado para verificación
    public var sha256Hex: String?
    
    public init(
        id: UUID = UUID(),
        relativePath: String,
        isDirectory: Bool = false,
        payloadFilename: String = "",
        payloadData: Data? = nil,
        sha256Hex: String? = nil
    ) {
        self.id = id
        self.relativePath = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.isDirectory = isDirectory
        self.payloadFilename = payloadFilename
        self.payloadData = payloadData
        
        if let data = payloadData, sha256Hex == nil {
            let digest = SHA256.hash(data: data)
            self.sha256Hex = digest.compactMap { String(format: "%02x", $0) }.joined()
        } else {
            self.sha256Hex = sha256Hex
        }
    }
    
    /// Normaliza la ruta relativa para prevenir Directory Traversal (../)
    public var sanitizedRelativePath: String {
        let clean = relativePath.replacingOccurrences(of: "\\", with: "/")
        let components = clean.split(separator: "/").filter { $0 != "." && $0 != ".." }
        return components.joined(separator: "/")
    }
}
