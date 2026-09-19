import SwiftUI

public struct ServerSettingsView: View {
    @ObservedObject var serverClient = LocalServerClient.shared
    @State private var ipText: String = ""
    @State private var portText: String = ""
    @State private var apiKeyText: String = ""
    @State private var useHttps: Bool = false
    @State private var showAdvancedSettings: Bool = false
    @State private var showSaveNotification: Bool = false
    
    public init() {
        _ipText = State(initialValue: LocalServerClient.shared.config.ipAddress)
        _portText = State(initialValue: String(LocalServerClient.shared.config.port))
        _apiKeyText = State(initialValue: LocalServerClient.shared.config.apiKey)
        _useHttps = State(initialValue: LocalServerClient.shared.config.useHttps)
    }
    
    public var body: some View {
        ZStack {
            ModTheme.background
                .ignoresSafeArea()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Permanent Default Server Info Card
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("SERVIDOR PREDETERMINADO")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(ModTheme.textSecondary)
                            Spacer()
                            if serverClient.config.isPermanentDefault {
                                Text("PREDETERMINADO FIJO")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(ModTheme.background)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(ModTheme.textPrimary)
                                    .cornerRadius(3)
                            }
                        }
                        
                        Text(serverClient.config.baseEndpoint)
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(ModTheme.textPrimary)
                        
                        HStack(spacing: 8) {
                            Circle()
                                .fill(serverClient.config.isConnected ? ModTheme.textPrimary : ModTheme.textMuted)
                                .frame(width: 8, height: 8)
                            Text(serverClient.config.isConnected ? "CONECTADO / ONLINE" : "DESCONECTADO")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(ModTheme.textSecondary)
                        }
                        .padding(.top, 2)
                        
                        Text("Configuración permanente para sincronización y descarga de archivos originales limpios.")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(ModTheme.textMuted)
                            .padding(.top, 2)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .minimalCard()
                    
                    // Action Buttons (Test & Reset)
                    VStack(spacing: 10) {
                        Button(action: testConnection) {
                            HStack {
                                if serverClient.isTestingConnection {
                                    ProgressView().tint(ModTheme.background)
                                        .padding(.trailing, 4)
                                }
                                Text("PROBAR CONEXIÓN AL SERVIDOR")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .minimalButton(isPrimary: true)
                        
                        Button(action: resetToDefault) {
                            HStack {
                                Image(systemName: "arrow.counterclockwise")
                                Text("USAR PREDETERMINADO PERMANENTE")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .minimalButton(isPrimary: false)
                        
                        if let msg = serverClient.connectionStatusMessage {
                            Text(msg)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(ModTheme.textSecondary)
                                .padding(.top, 4)
                        }
                    }
                    
                    Divider()
                        .background(ModTheme.border)
                        .padding(.vertical, 4)
                    
                    // Advanced Custom Server Toggle (Opcional para quien quiera personalizar)
                    DisclosureGroup(
                        isExpanded: $showAdvancedSettings,
                        content: {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Ajusta estos campos solo si ejecutas el servidor en otra IP o puerto diferente al predeterminado.")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(ModTheme.textMuted)
                                    .padding(.top, 4)
                                
                                // IP Address
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("DIRECCIÓN IP")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(ModTheme.textSecondary)
                                    TextField(ServerConfig.defaultIPAddress, text: $ipText)
                                        .font(.system(size: 14, design: .monospaced))
                                        .padding(10)
                                        .background(ModTheme.surface)
                                        .foregroundColor(ModTheme.textPrimary)
                                        .cornerRadius(ModTheme.cornerRadiusSmall)
                                        .overlay(RoundedRectangle(cornerRadius: ModTheme.cornerRadiusSmall).stroke(ModTheme.border, lineWidth: 1))
                                }
                                
                                // Port
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("PUERTO")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(ModTheme.textSecondary)
                                    TextField(String(ServerConfig.defaultPort), text: $portText)
                                        .font(.system(size: 14, design: .monospaced))
                                        .keyboardType(.numberPad)
                                        .padding(10)
                                        .background(ModTheme.surface)
                                        .foregroundColor(ModTheme.textPrimary)
                                        .cornerRadius(ModTheme.cornerRadiusSmall)
                                        .overlay(RoundedRectangle(cornerRadius: ModTheme.cornerRadiusSmall).stroke(ModTheme.border, lineWidth: 1))
                                }
                                
                                // API Key (Optional)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("API KEY (OPCIONAL)")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(ModTheme.textSecondary)
                                    SecureField("Dejar vacío si no requiere", text: $apiKeyText)
                                        .font(.system(size: 14, design: .monospaced))
                                        .padding(10)
                                        .background(ModTheme.surface)
                                        .foregroundColor(ModTheme.textPrimary)
                                        .cornerRadius(ModTheme.cornerRadiusSmall)
                                        .overlay(RoundedRectangle(cornerRadius: ModTheme.cornerRadiusSmall).stroke(ModTheme.border, lineWidth: 1))
                                }
                                
                                // HTTPS Toggle
                                Toggle(isOn: $useHttps) {
                                    Text("USAR HTTPS")
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundColor(ModTheme.textPrimary)
                                }
                                .toggleStyle(SwitchToggleStyle(tint: ModTheme.textPrimary))
                                
                                Button(action: saveCustomConfig) {
                                    Text("GUARDAR PERSONALIZADO")
                                        .frame(maxWidth: .infinity)
                                }
                                .minimalButton(isPrimary: false)
                                .padding(.top, 4)
                            }
                            .padding(.top, 8)
                        },
                        label: {
                            HStack {
                                Image(systemName: "slider.horizontal.3")
                                Text("CONFIGURACIÓN AVANZADA DE RED")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(ModTheme.textSecondary)
                            }
                        }
                    )
                    .padding(14)
                    .minimalCard()
                }
                .padding(16)
            }
        }
        .navigationTitle("SERVIDOR LOCAL")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func resetToDefault() {
        serverClient.resetToPermanentDefault()
        ipText = ServerConfig.defaultIPAddress
        portText = String(ServerConfig.defaultPort)
        useHttps = false
        apiKeyText = ""
        testConnection()
    }
    
    private func saveCustomConfig() {
        let portInt = Int(portText.trimmingCharacters(in: .whitespaces)) ?? ServerConfig.defaultPort
        let cleanIP = ipText.trimmingCharacters(in: .whitespaces)
        serverClient.config = ServerConfig(
            ipAddress: cleanIP.isEmpty ? ServerConfig.defaultIPAddress : cleanIP,
            port: portInt,
            useHttps: useHttps,
            apiKey: apiKeyText.trimmingCharacters(in: .whitespaces),
            isConnected: serverClient.config.isConnected
        )
        showSaveNotification = true
        testConnection()
    }
    
    private func testConnection() {
        Task {
            _ = await serverClient.testConnection()
        }
    }
}
