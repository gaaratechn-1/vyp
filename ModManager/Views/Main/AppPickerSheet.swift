import SwiftUI

public struct AppPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var containerService = ContainerService.shared
    @Binding var selectedBundleID: String
    @Binding var selectedAppName: String
    
    @State private var showCustomManual: Bool = false
    @State private var customBundleID: String = ""
    @State private var customAppName: String = ""
    
    // Las 2 versiones objetivo exclusivas
    private let targetGames: [(bundleID: String, name: String, subtitle: String, icon: String)] = [
        ("com.dts.freefiremax", "Free Fire MAX", "Versión MAX con gráficos avanzados", "flame.fill"),
        ("com.dts.freefireth", "Free Fire", "Versión estándar original", "flame")
    ]
    
    public var body: some View {
        NavigationView {
            ZStack {
                ModTheme.background
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("SELECCIONA EL JUEGO OBJETIVO")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(ModTheme.textSecondary)
                            Text("Elige la versión de Free Fire donde deseas instalar y gestionar tus mods.")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(ModTheme.textMuted)
                        }
                        .padding(.horizontal, 4)
                        
                        // Tarjetas de Free Fire
                        ForEach(targetGames, id: \.bundleID) { game in
                            gameCard(bundleID: game.bundleID, name: game.name, subtitle: game.subtitle, icon: game.icon)
                        }
                        
                        Divider()
                            .background(ModTheme.border)
                            .padding(.vertical, 8)
                        
                        // Opción Manual / Avanzada
                        if showCustomManual {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("ENTRADA MANUAL AVANZADA")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(ModTheme.textSecondary)
                                
                                TextField("Nombre (ej: Servidor Avanzado)", text: $customAppName)
                                    .font(.system(size: 12, design: .monospaced))
                                    .padding(10)
                                    .background(ModTheme.surface)
                                    .cornerRadius(ModTheme.cornerRadiusSmall)
                                    .overlay(RoundedRectangle(cornerRadius: ModTheme.cornerRadiusSmall).stroke(ModTheme.border, lineWidth: 1))
                                
                                TextField("Bundle ID (ej: com.dts.freefireth.adv)", text: $customBundleID)
                                    .font(.system(size: 12, design: .monospaced))
                                    .padding(10)
                                    .background(ModTheme.surface)
                                    .cornerRadius(ModTheme.cornerRadiusSmall)
                                    .overlay(RoundedRectangle(cornerRadius: ModTheme.cornerRadiusSmall).stroke(ModTheme.border, lineWidth: 1))
                                
                                Button("Usar Bundle ID Manual") {
                                    guard !customBundleID.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                                    HapticService.shared.lightTap()
                                    selectedBundleID = customBundleID.trimmingCharacters(in: .whitespaces)
                                    selectedAppName = customAppName.trimmingCharacters(in: .whitespaces).isEmpty ? customBundleID : customAppName
                                    dismiss()
                                }
                                .minimalButton(isPrimary: true)
                                .frame(maxWidth: .infinity)
                            }
                            .padding(14)
                            .background(ModTheme.surfaceSecondary)
                            .cornerRadius(ModTheme.cornerRadius)
                            .overlay(RoundedRectangle(cornerRadius: ModTheme.cornerRadius).stroke(ModTheme.border, lineWidth: 1))
                        } else {
                            Button(action: {
                                HapticService.shared.lightTap()
                                showCustomManual = true
                            }) {
                                HStack {
                                    Image(systemName: "plus.circle")
                                    Text("Usar otro Bundle ID de Free Fire...")
                                }
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(ModTheme.textSecondary)
                            }
                            .padding(.horizontal, 4)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("SELECCIONAR JUEGO")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") {
                        HapticService.shared.lightTap()
                        dismiss()
                    }
                    .foregroundColor(ModTheme.textPrimary)
                    .font(.system(size: 14, design: .monospaced))
                }
            }
        }
    }
    
    // MARK: - Tarjeta de Juego
    private func gameCard(bundleID: String, name: String, subtitle: String, icon: String) -> some View {
        let isSelected = (selectedBundleID == bundleID)
        let containerPath = containerService.resolveContainerPath(for: bundleID)
        let isAccessible = containerPath != nil && !containerPath!.isEmpty
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                // Icono
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? ModTheme.textPrimary : ModTheme.surfaceSecondary)
                        .frame(width: 44, height: 44)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(ModTheme.border, lineWidth: 1)
                        )
                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .foregroundColor(isSelected ? ModTheme.background : ModTheme.textPrimary)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(name)
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                            .foregroundColor(ModTheme.textPrimary)
                        
                        if isSelected {
                            Text("ACTIVO")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(ModTheme.background)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(ModTheme.textPrimary)
                                .cornerRadius(4)
                        }
                    }
                    
                    Text(bundleID)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(ModTheme.textSecondary)
                    
                    Text(subtitle)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(ModTheme.textMuted)
                }
                
                Spacer()
            }
            
            // Estado del Sandbox
            HStack(spacing: 6) {
                Circle()
                    .fill(isAccessible ? Color.white : ModTheme.textMuted)
                    .frame(width: 6, height: 6)
                
                if let path = containerPath {
                    Text("Sandbox accesible vía MHA-C2")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(ModTheme.textSecondary)
                } else {
                    Text("Sandbox se activará al seleccionar")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(ModTheme.textMuted)
                }
            }
            .padding(.leading, 4)
            
            // Botón Seleccionar
            Button(action: {
                HapticService.shared.lightTap()
                selectedBundleID = bundleID
                selectedAppName = name
                dismiss()
            }) {
                HStack {
                    Image(systemName: isSelected ? "checkmark" : "arrow.right.circle")
                    Text(isSelected ? "JUEGO ACTUALMENTE SELECCIONADO" : "SELECCIONAR \(name.uppercased())")
                }
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .frame(maxWidth: .infinity)
            }
            .minimalButton(isPrimary: !isSelected)
        }
        .padding(16)
        .background(ModTheme.surface)
        .cornerRadius(ModTheme.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: ModTheme.cornerRadius)
                .stroke(isSelected ? ModTheme.textPrimary : ModTheme.border, lineWidth: isSelected ? 2 : 1)
        )
    }
}
