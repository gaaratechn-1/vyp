import SwiftUI

public struct ModCardView: View {
    let profile: ModProfile
    @ObservedObject var engine = ModEngine.shared
    @ObservedObject var serverClient = LocalServerClient.shared
    
    @State private var showAlert: Bool = false
    @State private var alertTitle: String = ""
    @State private var alertMessage: String = ""
    @State private var showEditor: Bool = false
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header: Name & Status
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.name)
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(ModTheme.textPrimary)
                    
                    Text(profile.targetBundleID)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(ModTheme.textSecondary)
                }
                
                Spacer()
                
                // Status Badge (Minimalist)
                Text(profile.isApplied ? "APLICADO" : "ORIGINAL")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(profile.isApplied ? ModTheme.background : ModTheme.textPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(profile.isApplied ? ModTheme.textPrimary : ModTheme.surfaceSecondary)
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(ModTheme.border, lineWidth: 1)
                    )
            }
            
            Divider()
                .background(ModTheme.border)
            
            // Items List (Exact Paths)
            VStack(alignment: .leading, spacing: 6) {
                Text("ELEMENTOS / RUTA:")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(ModTheme.textSecondary)
                
                ForEach(profile.items) { item in
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
                        
                        if let bytes = item.payloadData?.count {
                            Text("\(bytes) B")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(ModTheme.textMuted)
                        }
                    }
                }
            }
            .padding(.vertical, 2)
            
            // Action Buttons
            VStack(spacing: 8) {
                // Primary Action: Apply Mod
                Button(action: applyModAction) {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text(profile.isApplied ? "REAPLICAR MOD" : "APLICAR MOD")
                    }
                    .frame(maxWidth: .infinity)
                }
                .minimalButton(isPrimary: true)
                
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
                    
                    // Option 2: Restore from Server / Cloud
                    Button(action: restoreServerAction) {
                        HStack(spacing: 4) {
                            Image(systemName: "network")
                            Text("Restaurar Servidor")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .minimalButton(isPrimary: false)
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
                dismissButton: .default(Text("OK"))
            )
        }
    }
    
    private func applyModAction() {
        Task {
            do {
                try await engine.applyMod(profile: profile)
                alertTitle = "Mod Aplicado"
                alertMessage = "El elemento ha sido reemplazado correctamente y se creó el backup del original."
                showAlert = true
            } catch {
                alertTitle = "Error"
                alertMessage = error.localizedDescription
                showAlert = true
            }
        }
    }
    
    private func restoreLocalAction() {
        Task {
            do {
                try await engine.restoreFromLocalBackup(profile: profile)
                alertTitle = "Restauración Local"
                alertMessage = "El archivo original guardado en el backup local ha sido restablecido."
                showAlert = true
            } catch {
                alertTitle = "Error al Restaurar"
                alertMessage = error.localizedDescription
                showAlert = true
            }
        }
    }
    
    private func restoreServerAction() {
        Task {
            do {
                try await engine.restoreFromServerOriginal(profile: profile)
                alertTitle = "Restauración desde Servidor"
                alertMessage = "El archivo original limpio ha sido descargado desde el servidor IP:Puerto y restablecido."
                showAlert = true
            } catch {
                alertTitle = "Error de Servidor"
                alertMessage = error.localizedDescription
                showAlert = true
            }
        }
    }
}
