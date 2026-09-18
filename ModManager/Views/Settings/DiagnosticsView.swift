import SwiftUI

public struct DiagnosticsView: View {
    @ObservedObject var containerService = ContainerService.shared
    @ObservedObject var logService = LogService.shared
    @State private var backupSize: Int64 = BackupManager.shared.totalBackupSize()
    @State private var showPurgeAlert: Bool = false
    
    private var bundleID: String {
        Bundle.main.bundleIdentifier ?? "Desconocido"
    }
    
    private var isCorrectBundle: Bool {
        bundleID == "com.apple.mobile.MobileHouseArrest"
    }
    
    private var formattedBackupSize: String {
        ByteCountFormatter.string(fromByteCount: backupSize, countStyle: .file)
    }
    
    public var body: some View {
        ZStack {
            ModTheme.background
                .ignoresSafeArea()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // System Status Card
                    VStack(alignment: .leading, spacing: 12) {
                        Text("ESTADO DEL SISTEMA")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(ModTheme.textSecondary)
                        
                        // Bundle ID
                        HStack {
                            Text("BUNDLE ID:")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(ModTheme.textSecondary)
                            Spacer()
                            Text(bundleID)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(isCorrectBundle ? ModTheme.textPrimary : ModTheme.destructive)
                        }
                        
                        Divider().background(ModTheme.border)
                        
                        // Sandbox Bridge
                        HStack {
                            Text("MCM BRIDGE (MHA-C2):")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(ModTheme.textSecondary)
                            Spacer()
                            Text(containerService.isMCMBridgeAvailable ? "ACTIVO" : "SIMULADO")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(ModTheme.textPrimary)
                        }
                        
                        Divider().background(ModTheme.border)
                        
                        // Storage
                        HStack {
                            Text("ESPACIO EN BACKUPS:")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(ModTheme.textSecondary)
                            Spacer()
                            Text(formattedBackupSize)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(ModTheme.textPrimary)
                        }
                    }
                    .padding(14)
                    .minimalCard()
                    
                    // Backup Purge Button
                    Button(action: { showPurgeAlert = true }) {
                        HStack {
                            Image(systemName: "trash")
                            Text("PURGAR TODOS LOS BACKUPS")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .minimalButton(isPrimary: false)
                    
                    // Live Terminal Logs
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("REGISTRO DE AUDITORÍA (LOGS)")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(ModTheme.textSecondary)
                            Spacer()
                            Button("Limpiar") {
                                logService.clear()
                            }
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(ModTheme.textSecondary)
                        }
                        
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 6) {
                                ForEach(logService.entries) { entry in
                                    HStack(alignment: .top, spacing: 6) {
                                        Text("[\(entry.formattedTime)]")
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(ModTheme.textMuted)
                                        Text("[\(entry.category)]")
                                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                                            .foregroundColor(ModTheme.textSecondary)
                                        Text(entry.message)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(ModTheme.textPrimary)
                                    }
                                }
                            }
                            .padding(10)
                        }
                        .frame(height: 220)
                        .background(ModTheme.surface)
                        .cornerRadius(ModTheme.cornerRadiusSmall)
                        .overlay(
                            RoundedRectangle(cornerRadius: ModTheme.cornerRadiusSmall)
                                .stroke(ModTheme.border, lineWidth: 1)
                        )
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("DIAGNÓSTICO")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            backupSize = BackupManager.shared.totalBackupSize()
        }
        .alert(isPresented: $showPurgeAlert) {
            Alert(
                title: Text("¿Eliminar todos los backups?"),
                message: Text("Esta acción borrará las copias de seguridad locales de los archivos originales. Esta acción no se puede deshacer."),
                primaryButton: .destructive(Text("Eliminar")) {
                    BackupManager.shared.purgeAllBackups()
                    backupSize = BackupManager.shared.totalBackupSize()
                },
                secondaryButton: .cancel()
            )
        }
    }
}
