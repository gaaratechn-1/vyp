import SwiftUI

public struct MainView: View {
    @ObservedObject var engine = ModEngine.shared
    @ObservedObject var containerService = ContainerService.shared
    @ObservedObject var serverClient = LocalServerClient.shared
    
    @State private var selectedFilterBundleID: String = ""
    @State private var selectedFilterAppName: String = "Todas las Aplicaciones"
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
                    // Filter / App Selection Header
                    VStack(spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("APP DESTINO")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(ModTheme.textSecondary)
                                Text(selectedFilterAppName)
                                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                    .foregroundColor(ModTheme.textPrimary)
                            }
                            
                            Spacer()
                            
                            Button(action: { showAppFilterSheet = true }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "slider.horizontal.3")
                                    Text("Filtrar")
                                }
                            }
                            .minimalButton(isPrimary: false)
                            
                            if !selectedFilterBundleID.isEmpty {
                                Button(action: {
                                    selectedFilterBundleID = ""
                                    selectedFilterAppName = "Todas las Aplicaciones"
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
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                    
                    // Mods List or Empty State (No se destruye durante operaciones)
                    if filteredProfiles.isEmpty {
                        Spacer()
                        VStack(spacing: 16) {
                            Image(systemName: "square.stack.3d.up.slash")
                                .font(.system(size: 40))
                                .foregroundColor(ModTheme.textMuted)
                            
                            Text("NO HAY MODS REGISTRADOS")
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundColor(ModTheme.textPrimary)
                            
                            Text("Crea un nuevo mod indicando la ruta exacta en el sandbox o sincroniza con el servidor.")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(ModTheme.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                            
                            Button(action: { showNewModSheet = true }) {
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
                
                // Non-destructive floating processing HUD
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
                    Button(action: { showNewModSheet = true }) {
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
}
