import SwiftUI
import UIKit

public struct ModCardView: View {
    let profile: ModProfile
    @ObservedObject var engine = ModEngine.shared
    @ObservedObject var containerService = ContainerService.shared
    @ObservedObject var serverClient = LocalServerClient.shared
    
    @State private var showAlert: Bool = false
    @State private var alertTitle: String = ""
    @State private var alertMessage: String = ""
    @State private var showEditor: Bool = false
    @State private var isPerformingAction: Bool = false
    @State private var copiedPathToast: String?
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header: Name & Status
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(profile.name)
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(ModTheme.textPrimary)
                        
                        if profile.items.count > 1 {
                            Text("\(profile.items.count) ARCHIVOS")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(ModTheme.surfaceSecondary)
                                .foregroundColor(ModTheme.textPrimary)
                                .cornerRadius(4)
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(ModTheme.border, lineWidth: 1))
                        }
                    }
                    
                    Text(profile.targetBundleID == "com.dts.freefireth" ? "Free Fire (\(profile.targetBundleID))" : "Free Fire MAX (\(profile.targetBundleID))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(ModTheme.textSecondary)
                }
                
                Spacer()
                
                // Status Badge (Identifica claramente si está aplicado o cómo fue restaurado)
                statusBadge
            }
            
            Divider()
                .background(ModTheme.border)
            
            // Items List (Exact Paths & Live Path Availability)
            VStack(alignment: .leading, spacing: 8) {
                Text("ELEMENTOS / RUTA EXACTA:")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(ModTheme.textSecondary)
                
                ForEach(profile.items) { item in
                    let validation = containerService.validatePath(bundleID: profile.targetBundleID, relativePath: item.sanitizedRelativePath)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: item.isDirectory ? "folder" : "doc")
                                .font(.system(size: 11))
                                .foregroundColor(ModTheme.textPrimary)
                            
                            Text(item.sanitizedRelativePath)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(ModTheme.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            
                            Spacer()
                            
                            // Botón copiar ruta rápida
                            Button(action: {
                                UIPasteboard.general.string = item.sanitizedRelativePath
                                HapticService.shared.lightTap()
                                copiedPathToast = "Copiado: \(item.sanitizedRelativePath)"
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    copiedPathToast = nil
                                }
                            }) {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 11))
                                    .foregroundColor(ModTheme.textSecondary)
                            }
                        }
                        
                        // Estado de disponibilidad física en el sandbox
                        HStack(spacing: 4) {
                            Circle()
                                .fill(colorForValidation(validation.status))
                                .frame(width: 6, height: 6)
                            
                            Text(textForValidation(validation))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(ModTheme.textSecondary)
                            
                            if let bytes = item.payloadData?.count {
                                Spacer()
                                Text("Mod: \(bytes) B")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(ModTheme.textMuted)
                            }
                        }
                        .padding(.leading, 17)
                    }
                }
                
                if let toast = copiedPathToast {
                    Text(toast)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(ModTheme.textPrimary)
                        .padding(.top, 2)
                }
            }
            .padding(.vertical, 2)
            
            // Action Buttons
            VStack(spacing: 8) {
                // Primary Action: Apply Mod
                Button(action: applyModAction) {
                    HStack {
                        if isPerformingAction {
                            ProgressView()
                                .tint(profile.isApplied ? ModTheme.textPrimary : ModTheme.background)
                                .padding(.trailing, 4)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        Text(profile.isApplied ? "REAPLICAR MOD" : "APLICAR MOD")
                    }
                    .frame(maxWidth: .infinity)
                }
                .minimalButton(isPrimary: true)
                .disabled(isPerformingAction)
                
                // Restore Options
                HStack(spacing: 8) {
                    // Option 1: Restore from Local Backup
                    Button(action: restoreLocalAction) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.uturn.backward")
                            Text("Restaurar Local")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .minimalButton(isPrimary: false)
                    .disabled(isPerformingAction)
                    
                    // Option 2: Restore from Server / Cloud
                    Button(action: restoreServerAction) {
                        HStack(spacing: 4) {
                            Image(systemName: "network")
                            Text("Restaurar Servidor")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .minimalButton(isPrimary: false)
                    .disabled(isPerformingAction)
                }
            }
            
            // Footer: Edit / Delete
            HStack {
                Button(action: { showEditor = true }) {
                    Text("Editar")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(ModTheme.textSecondary)
                }
                Spacer()
                Button(action: { engine.deleteProfile(id: profile.id) }) {
                    Text("Eliminar")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(ModTheme.textMuted)
                }
            }
            .padding(.top, 4)
        }
        .padding(16)
        .minimalCard()
        .sheet(isPresented: $showEditor) {
            ModEditorSheet(existingProfile: profile)
        }
        .alert(isPresented: $showAlert) {
            Alert(
                title: Text(alertTitle),
                message: Text(alertMessage),
                dismissButton: .default(Text("Entendido"))
            )
        }
    }
    
    // MARK: - Subviews
    
    private var statusBadge: some View {
        Group {
            if profile.isApplied {
                Text("MOD APLICADO")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(ModTheme.background)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(ModTheme.textPrimary)
                    .cornerRadius(4)
            } else if profile.lastRestoreSource == .localBackup {
                Text("ORIGINAL (LOCAL)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(ModTheme.textPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(ModTheme.surfaceSecondary)
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(ModTheme.border, lineWidth: 1)
                    )
            } else if profile.lastRestoreSource == .server {
                Text("ORIGINAL (SERVIDOR)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(ModTheme.textPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(ModTheme.surfaceSecondary)
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(ModTheme.border, lineWidth: 1)
                    )
            } else {
                Text("ORIGINAL")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(ModTheme.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(ModTheme.surfaceSecondary)
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(ModTheme.border, lineWidth: 1)
                    )
            }
        }
    }
    
    private func colorForValidation(_ status: PathValidationInfo.Status) -> Color {
        switch status {
        case .fileExists:
            return ModTheme.textPrimary
        case .directoryExists, .parentExists:
            return ModTheme.textSecondary
        case .targetNotFound:
            return ModTheme.textMuted
        case .containerInaccessible:
            return ModTheme.destructive
        }
    }
    
    private func textForValidation(_ validation: PathValidationInfo) -> String {
        switch validation.status {
        case .fileExists:
            if let size = validation.formattedSize {
                return "Existe en sandbox (\(size))"
            }
            return "Existe en sandbox"
        case .directoryExists:
            return "Carpeta encontrada en sandbox"
        case .parentExists:
            return "Carpeta padre existe (se creará archivo)"
        case .targetNotFound:
            return "No existe aún en sandbox"
        case .containerInaccessible:
            return "Sandbox no accesible"
        }
    }
    
    // MARK: - Actions
    
    private func applyModAction() {
        isPerformingAction = true
        HapticService.shared.mediumImpact()
        Task {
            do {
                try await engine.applyMod(profile: profile)
                HapticService.shared.success()
                
                alertTitle = "✓ Mod Aplicado Exitosamente"
                alertMessage = "El mod ha sido aplicado en el sandbox de [\(profile.targetBundleID)].\n\n• Archivos aplicados: \(profile.items.count) elemento(s)\n• Copias de seguridad automáticas guardadas en el dispositivo."
                isPerformingAction = false
                showAlert = true
            } catch {
                HapticService.shared.error()
                alertTitle = "✕ Error al Aplicar Mod"
                alertMessage = error.localizedDescription
                isPerformingAction = false
                showAlert = true
            }
        }
    }
    
    private func restoreLocalAction() {
        isPerformingAction = true
        HapticService.shared.mediumImpact()
        Task {
            do {
                try await engine.restoreFromLocalBackup(profile: profile)
                HapticService.shared.success()
                
                alertTitle = "↺ Originales Restaurados (Local)"
                alertMessage = "Todos los archivos originales (\(profile.items.count)) han sido restaurados con éxito desde el respaldo local.\n\n• Juego: [\(profile.targetBundleID)]"
                isPerformingAction = false
                showAlert = true
            } catch {
                HapticService.shared.error()
                alertTitle = "✕ Error al Restaurar Local"
                alertMessage = error.localizedDescription
                isPerformingAction = false
                showAlert = true
            }
        }
    }
    
    private func restoreServerAction() {
        isPerformingAction = true
        HapticService.shared.mediumImpact()
        Task {
            do {
                try await engine.restoreFromServerOriginal(profile: profile)
                HapticService.shared.success()
                
                alertTitle = "🌐 Originales Restaurados (Servidor)"
                alertMessage = "Archivos originales descargados exitosamente del servidor y restaurados en el sandbox.\n\n• Elementos: \(profile.items.count)\n• Servidor: \(serverClient.config.baseEndpoint)"
                isPerformingAction = false
                showAlert = true
            } catch let error as CloudRestoreError {
                HapticService.shared.error()
                alertTitle = "✕ \(error.failureReason ?? "Error de Restauración")"
                alertMessage = error.localizedDescription
                isPerformingAction = false
                showAlert = true
            } catch {
                HapticService.shared.error()
                alertTitle = "✕ Error al Restaurar"
                alertMessage = error.localizedDescription
                isPerformingAction = false
                showAlert = true
            }
        }
    }
}
