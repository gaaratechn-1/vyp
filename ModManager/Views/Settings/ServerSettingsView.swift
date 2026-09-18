import SwiftUI

public struct ServerSettingsView: View {
    @ObservedObject var serverClient = LocalServerClient.shared
    @State private var ipText: String = ""
    @State private var portText: String = ""
    @State private var apiKeyText: String = ""
    @State private var useHttps: Bool = false
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
                VStack(alignment: .leading, spacing: 20) {
                    // Endpoint Info Card
                    VStack(alignment: .leading, spacing: 6) {
                        Text("ENDPOINT ACTIVO")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(ModTheme.textSecondary)
                        Text(serverClient.config.baseEndpoint)
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                            .foregroundColor(ModTheme.textPrimary)
                        
                        HStack {
                            Circle()
                                .fill(serverClient.config.isConnected ? ModTheme.textPrimary : ModTheme.textMuted)
                                .frame(width: 8, height: 8)
                            Text(serverClient.config.isConnected ? "CONECTADO" : "DESCONECTADO")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(ModTheme.textSecondary)
                        }
                        .padding(.top, 4)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .minimalCard()
                    
                    // Connection Configuration Fields
                    VStack(alignment: .leading, spacing: 14) {
                        Text("CONFIGURACIÓN DE RED")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(ModTheme.textSecondary)
                        
                        // IP Address
                        VStack(alignment: .leading, spacing: 4) {
                            Text("DIRECCIÓN IP")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(ModTheme.textSecondary)
                            TextField("192.168.1.100", text: $ipText)
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
                            TextField("8080", text: $portText)
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
                    }
                    .padding(14)
                    .minimalCard()
                    
                    // Action Buttons
                    VStack(spacing: 10) {
                        Button(action: saveConfig) {
                            Text("GUARDAR CONFIGURACIÓN")
                                .frame(maxWidth: .infinity)
                        }
                        .minimalButton(isPrimary: true)
                        
                        Button(action: testConnection) {
                            HStack {
                                if serverClient.isTestingConnection {
                                    ProgressView().tint(ModTheme.textPrimary)
                                }
                                Text("PROBAR CONEXIÓN")
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
                }
                .padding(16)
            }
        }
        .navigationTitle("SERVIDOR LOCAL")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func saveConfig() {
        let portInt = Int(portText.trimmingCharacters(in: .whitespaces)) ?? 8080
        serverClient.config = ServerConfig(
            ipAddress: ipText.trimmingCharacters(in: .whitespaces),
            port: portInt,
            useHttps: useHttps,
            apiKey: apiKeyText.trimmingCharacters(in: .whitespaces),
            isConnected: serverClient.config.isConnected
        )
        showSaveNotification = true
    }
    
    private func testConnection() {
        saveConfig()
        Task {
            _ = await serverClient.testConnection()
        }
    }
}
