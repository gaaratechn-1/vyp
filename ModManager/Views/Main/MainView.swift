import SwiftUI

public struct MainView: View {
    @ObservedObject var engine = ModEngine.shared
    @ObservedObject var containerService = ContainerService.shared
    @ObservedObject var serverClient = LocalServerClient.shared
    
    @State private var selectedFilterBundleID: String = ""
    @State private var selectedFilterAppName: String = "Todas las Versiones"
    @State private var showAppFilterSheet: Bool = false
    @State private var showNewModSheet: Bool = false
    
    var filteredProfiles: [ModProfile] {
        if selectedFilterBundleID.isEmpty {
            return engine.modProfiles
        }
        return engine.modProfiles.filter { $0.targetBundleID == selectedFilterBundleID }
    }
    
    public var body: some View {
        NavigationView {
            ZStack {
                ModTheme.background
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Píldora de Estado del Servidor & Auto-Descubrimiento (Punto 1)
                    HStack {
                        connectionPill
                        
                        Spacer()
                        
                        // Estado de Activación MHA-C2
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 6, height: 6)
                            Text("MHA-C2 ACTIVO")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(ModTheme.textSecondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(ModTheme.surfaceSecondary)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
                    
                    // Filter / App Selection Header
                    VStack(spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("JUEGO SELECCIONADO")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(ModTheme.textSecondary)
                                Text(selectedFilterAppName)
                                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                    .foregroundColor(ModTheme.textPrimary)
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                HapticService.shared.lightTap()
                                showAppFilterSheet = true
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "slider.horizontal.3")
                                    Text("Filtrar")
                                }
                            }
                            .minimalButton(isPrimary: false)
                            
                            if !selectedFilterBundleID.isEmpty {
                                Button(action: {
                                    HapticService.shared.lightTap()
                                    selectedFilterBundleID = ""
                                    selectedFilterAppName = "Todas las Versiones"
                                }) {
                                    Image(systemName: "xmark")
                                        .foregroundColor(ModTheme.textSecondary)
                                }
                                .padding(.leading, 4)
                            }
                        }
                        .padding(14)
                        .minimalCard()
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    
                    // Mods List or Empty State
                    if filteredProfiles.isEmpty {
                        Spacer()
                        VStack(spacing: 16) {
                            Image(systemName: "square.stack.3d.up.slash")
                                .font(.system(size: 40))
                                .foregroundColor(ModTheme.textMuted)
                            
                            Text("NO HAY MODS REGISTRADOS")
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundColor(ModTheme.textPrimary)
                            
                            Text("Crea un mod indicando la carpeta o ruta en Free Fire y carga tus archivos de reemplazo.")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(ModTheme.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                            
                            Button(action: {
                                HapticService.shared.lightTap()
                                showNewModSheet = true
                            }) {
                                HStack {
                                    Image(systemName: "plus")
                                    Text("CREAR PRIMER MOD")
                                }
                            }
                            .minimalButton(isPrimary: true)
                        }
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 14) {
                                ForEach(filteredProfiles) { profile in
                                    ModCardView(profile: profile)
                                }
                            }
                            .padding(16)
                        }
                    }
                }
                
                // Floating processing HUD
                if engine.isProcessing, let msg = engine.activeOperationMessage {
                    VStack {
                        Spacer()
                        HStack(spacing: 12) {
                            ProgressView()
                                .tint(ModTheme.background)
                            Text(msg)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(ModTheme.background)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(ModTheme.textPrimary)
                        .cornerRadius(ModTheme.cornerRadiusSmall)
                        .shadow(radius: 8)
                        .padding(.bottom, 24)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.2), value: engine.isProcessing)
                }
            }
            .navigationTitle("MODS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        HapticService.shared.lightTap()
                        showNewModSheet = true
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(ModTheme.textPrimary)
                    }
                }
            }
            .sheet(isPresented: $showAppFilterSheet) {
                AppPickerSheet(
                    selectedBundleID: $selectedFilterBundleID,
                    selectedAppName: $selectedFilterAppName
                )
            }
            .sheet(isPresented: $showNewModSheet) {
                ModEditorSheet()
            }
        }
    }
    
    // MARK: - Píldora de Conexión del Servidor
    private var connectionPill: some View {
        Button(action: {
            HapticService.shared.lightTap()
            Task {
                _ = await serverClient.testConnection()
            }
        }) {
            if serverClient.isOnline {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 7, height: 7)
                    Text(serverClient.discoveredAddress ?? "\(serverClient.config.host):\(serverClient.config.port)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(ModTheme.textPrimary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(ModTheme.surface)
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.green.opacity(0.4), lineWidth: 1))
            } else {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.gray)
                        .frame(width: 7, height: 7)
                    Text("Modo Local Offline")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(ModTheme.textSecondary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(ModTheme.surface)
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(ModTheme.border, lineWidth: 1))
            }
        }
    }
}
