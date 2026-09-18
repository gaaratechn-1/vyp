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
                    
                    // Mods List or Empty State
                    if engine.isProcessing {
                        Spacer()
                        VStack(spacing: 12) {
                            ProgressView()
                                .tint(ModTheme.textPrimary)
                            Text(engine.activeOperationMessage ?? "Procesando...")
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(ModTheme.textSecondary)
                        }
                        Spacer()
                    } else if filteredProfiles.isEmpty {
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
