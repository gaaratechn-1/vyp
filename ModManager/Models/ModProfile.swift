import Foundation

// MARK: - Mod Status
public enum ModStatus: String, Codable {
    case ready          // Mod creado pero no aplicado (estado original en app)
    case applied        // Mod actualmente activo en el sandbox
    case modifiedOutdated // Mod aplicado pero el archivo fue cambiado exteriormente
    case error          // Error al validar o aplicar
}

// MARK: - Mod Profile (Grupo de elementos modificados)
public struct ModProfile: Codable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var notes: String
    public var targetBundleID: String
    public var items: [ModItem]
    public var status: ModStatus
    public var isApplied: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var lastBackupDate: Date?
    
    public init(
        id: UUID = UUID(),
        name: String,
        notes: String = "",
        targetBundleID: String,
        items: [ModItem] = [],
        status: ModStatus = .ready,
        isApplied: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastBackupDate: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.targetBundleID = targetBundleID
        self.items = items
        self.status = status
        self.isApplied = isApplied
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastBackupDate = lastBackupDate
    }
}
