import UIKit

/// Servicio centralizado para generación de respuestas hápticas (Taptic Engine) en iOS.
public final class HapticService {
    public static let shared = HapticService()
    
    private init() {}
    
    /// Toque sutil y ligero para interacción con interruptores, pestañas y copiado de rutas.
    public func lightTap() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
    }
    
    /// Impacto medio para pulsación de botones principales de acción (Aplicar Mod, Restaurar).
    public func mediumImpact() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
    }
    
    /// Notificación de éxito: doble vibración corta al completar exitosamente una operación en el sandbox.
    public func success() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
    }
    
    /// Notificación de advertencia: vibración para avisos de rutas inexistentes o confirmaciones.
    public func warning() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.warning)
    }
    
    /// Notificación de error: vibración fuerte si falla la inyección o el servidor está offline.
    public func error() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.error)
    }
}
