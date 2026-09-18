import SwiftUI

@main
struct ModManagerApp: App {
    @StateObject private var security = SecurityService.shared
    @StateObject private var engine = ModEngine.shared
    @StateObject private var containerService = ContainerService.shared
    @StateObject private var serverClient = LocalServerClient.shared
    
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
        ModLog("Iniciando ModManager...", category: "APP")
    }
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(security)
                .environmentObject(engine)
                .environmentObject(containerService)
                .environmentObject(serverClient)
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase) { phase in
                    if phase == .background {
                        // Bloquear al enviar la app a segundo plano para seguridad
                        security.lock()
                    }
                }
        }
    }
}
