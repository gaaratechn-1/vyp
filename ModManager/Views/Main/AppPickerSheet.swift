import SwiftUI

public struct AppPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var containerService = ContainerService.shared
    @Binding var selectedBundleID: String
    @Binding var selectedAppName: String
    
    @State private var searchText: String = ""
    @State private var filterCategory: Int = 0 // 0: Usuario / Juegos, 1: Todas, 2: Sistema
    @State private var showManualPrompt: Bool = false
    @State private var manualBundleID: String = ""
    @State private var manualAppName: String = ""
    
    var filteredApps: [InstalledAppInfo] {
        var base = containerService.installedApps
        
        switch filterCategory {
        case 0: // Usuario / Juegos
            base = base.filter { $0.isUserApp }
        case 2: // Sistema
            base = base.filter { !$0.isUserApp }
        default: // Todas
            break
        }
        
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return base
        }
        return base.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText) ||
            $0.bundleID.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    public var body: some View {
        NavigationView {
            ZStack {
                ModTheme.background
                    .ignoresSafeArea()
                
                VStack(spacing: 12) {
                    // Category Filter Segmented Control
                    Picker("Categoría", selection: $filterCategory) {
                        Text("Usuario / Juegos").tag(0)
                        Text("Todas (\(containerService.installedApps.count))").tag(1)
                        Text("Sistema").tag(2)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    
                    // Search Bar
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(ModTheme.textSecondary)
                        TextField("Buscar aplicación o bundle ID...", text: $searchText)
                            .foregroundColor(ModTheme.textPrimary)
                            .font(.system(size: 14, design: .monospaced))
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(ModTheme.textSecondary)
                            }
                        }
                    }
                    .padding(12)
                    .background(ModTheme.surface)
                    .cornerRadius(ModTheme.cornerRadiusSmall)
                    .overlay(
                        RoundedRectangle(cornerRadius: ModTheme.cornerRadiusSmall)
                            .stroke(ModTheme.border, lineWidth: 1)
                    )
                    .padding(.horizontal, 16)
                    
                    // Manual entry button if search yielded no results or custom app needed
                    if !searchText.isEmpty && !filteredApps.contains(where: { $0.bundleID.lowercased() == searchText.lowercased() }) {
                        Button(action: {
                            selectedBundleID = searchText.trimmingCharacters(in: .whitespaces)
                            selectedAppName = searchText.trimmingCharacters(in: .whitespaces)
                            dismiss()
                        }) {
                            HStack {
                                Image(systemName: "plus.circle")
                                Text("Usar bundle ID: \"\(searchText)\"")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .minimalButton(isPrimary: false)
                        .padding(.horizontal, 16)
                    }
                    
                    // Apps List
                    if containerService.isScanning {
                        Spacer()
                        ProgressView()
                            .tint(ModTheme.textPrimary)
                        Text("Escaneando sandbox de aplicaciones...")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(ModTheme.textSecondary)
                            .padding(.top, 8)
                        Spacer()
                    } else if filteredApps.isEmpty {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: "app.dashed")
                                .font(.system(size: 36))
                                .foregroundColor(ModTheme.textMuted)
                            Text("No se encontraron aplicaciones")
                                .font(.system(size: 14, design: .monospaced))
                                .foregroundColor(ModTheme.textSecondary)
                            
                            Button("Ingresar Bundle ID manualmente") {
                                showManualPrompt = true
                            }
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(ModTheme.textPrimary)
                            .padding(.top, 4)
                        }
                        Spacer()
                    } else {
                        List(filteredApps) { app in
                            Button(action: {
                                selectedBundleID = app.bundleID
                                selectedAppName = app.displayName
                                dismiss()
                            }) {
                                HStack(spacing: 14) {
                                    // Minimalist monochrome badge
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(ModTheme.surfaceSecondary)
                                            .frame(width: 38, height: 38)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .stroke(ModTheme.border, lineWidth: 1)
                                            )
                                        Image(systemName: app.isUserApp ? "gamecontroller.fill" : "gearshape.fill")
                                            .font(.system(size: 16))
                                            .foregroundColor(ModTheme.textPrimary)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 6) {
                                            Text(app.displayName)
                                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                                .foregroundColor(ModTheme.textPrimary)
                                            
                                            if !app.version.isEmpty {
                                                Text("v\(app.version)")
                                                    .font(.system(size: 10, design: .monospaced))
                                                    .foregroundColor(ModTheme.textMuted)
                                            }
                                        }
                                        
                                        Text(app.bundleID)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(ModTheme.textSecondary)
                                        
                                        // Sandbox status indicator
                                        HStack(spacing: 4) {
                                            Circle()
                                                .fill(app.hasValidContainer ? ModTheme.textPrimary : ModTheme.textMuted)
                                                .frame(width: 5, height: 5)
                                            Text(app.hasValidContainer ? "Sandbox resuelto" : "Sandbox por resolver")
                                                .font(.system(size: 9, design: .monospaced))
                                                .foregroundColor(ModTheme.textMuted)
                                        }
                                        .padding(.top, 1)
                                    }
                                    
                                    Spacer()
                                    
                                    if selectedBundleID == app.bundleID {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(ModTheme.textPrimary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .listRowBackground(ModTheme.surface)
                            .listRowSeparatorTint(ModTheme.border)
                        }
                        .listStyle(.plain)
                        .background(ModTheme.background)
                    }
                }
            }
            .navigationTitle("SELECCIONAR APP")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") {
                        dismiss()
                    }
                    .foregroundColor(ModTheme.textPrimary)
                    .font(.system(size: 14, design: .monospaced))
                }
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        Button(action: { showManualPrompt = true }) {
                            Image(systemName: "keyboard")
                                .foregroundColor(ModTheme.textPrimary)
                        }
                        
                        Button(action: { containerService.refreshApps() }) {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(ModTheme.textPrimary)
                        }
                    }
                }
            }
            .sheet(isPresented: $showManualPrompt) {
                manualEntryView
            }
        }
    }
    
    // MARK: - Manual Entry Sheet
    private var manualEntryView: some View {
        NavigationView {
            ZStack {
                ModTheme.background
                    .ignoresSafeArea()
                
                VStack(alignment: .leading, spacing: 18) {
                    Text("INTRODUCIR BUNDLE ID")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(ModTheme.textSecondary)
                    
                    TextField("com.empresa.juego", text: $manualBundleID)
                        .font(.system(size: 14, design: .monospaced))
                        .padding(12)
                        .background(ModTheme.surface)
                        .foregroundColor(ModTheme.textPrimary)
                        .cornerRadius(ModTheme.cornerRadiusSmall)
                        .overlay(RoundedRectangle(cornerRadius: ModTheme.cornerRadiusSmall).stroke(ModTheme.border, lineWidth: 1))
                    
                    Text("Nombre de la App (Opcional)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(ModTheme.textSecondary)
                    
                    TextField("Ej: Mi Juego", text: $manualAppName)
                        .font(.system(size: 14, design: .monospaced))
                        .padding(12)
                        .background(ModTheme.surface)
                        .foregroundColor(ModTheme.textPrimary)
                        .cornerRadius(ModTheme.cornerRadiusSmall)
                        .overlay(RoundedRectangle(cornerRadius: ModTheme.cornerRadiusSmall).stroke(ModTheme.border, lineWidth: 1))
                    
                    Button(action: {
                        let cleanID = manualBundleID.trimmingCharacters(in: .whitespaces)
                        if !cleanID.isEmpty {
                            selectedBundleID = cleanID
                            selectedAppName = manualAppName.isEmpty ? cleanID : manualAppName
                            showManualPrompt = false
                            dismiss()
                        }
                    }) {
                        Text("SELECCIONAR APP")
                            .frame(maxWidth: .infinity)
                    }
                    .minimalButton(isPrimary: true)
                    .padding(.top, 10)
                    
                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("APP PERSONALIZADA")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { showManualPrompt = false }
                        .foregroundColor(ModTheme.textPrimary)
                }
            }
        }
    }
}
