import Foundation
import Combine

public struct LogEntry: Identifiable, Equatable {
    public let id = UUID()
    public let timestamp: Date
    public let message: String
    public let category: String
    
    public var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: timestamp)
    }
}

public final class LogService: ObservableObject {
    public static let shared = LogService()
    
    @Published public private(set) var entries: [LogEntry] = []
    private let queue = DispatchQueue(label: "com.modmanager.logqueue", qos: .utility)
    
    private init() {
        log("LogService inicializado", category: "SYS")
    }
    
    public func log(_ message: String, category: String = "INFO") {
        let entry = LogEntry(timestamp: Date(), message: message, category: category)
        queue.async {
            DispatchQueue.main.async {
                self.entries.insert(entry, at: 0)
                if self.entries.count > 500 {
                    self.entries.removeLast()
                }
            }
        }
        #if DEBUG
        print("[\(category)] \(message)")
        #endif
    }
    
    public func clear() {
        entries.removeAll()
    }
}

public func ModLog(_ message: String, category: String = "MOD") {
    LogService.shared.log(message, category: category)
}
