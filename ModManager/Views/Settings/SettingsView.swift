import SwiftUI

public struct SettingsView: View {
    @ObservedObject var security = SecurityService.shared
    
    public var body: some View {
        NavigationView {
            ZStack {
                ModTheme.background
                    .ignoresSafeArea()
                
                List {
                    Section {
                        NavigationLink(destination: ServerSettingsView()) {
                            HStack(spacing: 12) {
                                Image(systemName: "network")
                                    .foregroundColor(ModTheme.textPrimary)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("SERVIDOR LOCAL")
                                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                        .foregroundColor(ModTheme.textPrimary)
                                    Text("Configuración de IP, Puerto y sincronización")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(ModTheme.textSecondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        
                        NavigationLink(destination: SecuritySettingsView()) {
                            HStack(spacing: 12) {
                                Image(systemName: "lock.shield")
                                    .foregroundColor(ModTheme.textPrimary)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("SEGURIDAD & PIN")
                                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                        .foregroundColor(ModTheme.textPrimary)
                                    Text("Código de acceso (4444) y Face ID")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(ModTheme.textSecondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        
                        NavigationLink(destination: DiagnosticsView()) {
                            HStack(spacing: 12) {
                                Image(systemName: "terminal")
                                    .foregroundColor(ModTheme.textPrimary)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("DIAGNÓSTICO & LOGS")
                                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                        .foregroundColor(ModTheme.textPrimary)
                                    Text("Estado del sandbox, espacio de backups y auditoría")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(ModTheme.textSecondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    } header: {
                        Text("PREFERENCIAS")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(ModTheme.textSecondary)
                    }
                    .listRowBackground(ModTheme.surface)
                    .listRowSeparatorTint(ModTheme.border)
                    
                    Section {
                        Button(action: { security.lock() }) {
                            HStack {
                                Image(systemName: "lock")
                                    .foregroundColor(ModTheme.textPrimary)
                                Text("BLOQUEAR APLICACIÓN")
                                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                    .foregroundColor(ModTheme.textPrimary)
                            }
                        }
                    }
                    .listRowBackground(ModTheme.surface)
                    .listRowSeparatorTint(ModTheme.border)
                    
                    Section {
                        HStack {
                            Text("VERSIÓN")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(ModTheme.textSecondary)
                            Spacer()
                            Text("1.0.0 (MHA-C2)")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(ModTheme.textPrimary)
                        }
                    }
                    .listRowBackground(ModTheme.surface)
                }
                .listStyle(.insetGrouped)
                .background(ModTheme.background)
            }
            .navigationTitle("AJUSTES")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
