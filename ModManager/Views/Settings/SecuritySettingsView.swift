import SwiftUI

public struct SecuritySettingsView: View {
    @ObservedObject var security = SecurityService.shared
    
    @State private var currentPin: String = ""
    @State private var newPin: String = ""
    @State private var confirmPin: String = ""
    @State private var statusMessage: String?
    @State private var isSuccess: Bool = false
    
    public var body: some View {
        ZStack {
            ModTheme.background
                .ignoresSafeArea()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Biometrics Section
                    if security.isBiometricsAvailable {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("BIOMETRÍA")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(ModTheme.textSecondary)
                            
                            Toggle(isOn: Binding(
                                get: { security.isBiometricsEnabled },
                                set: { security.setBiometricsEnabled($0) }
                            )) {
                                Text("HABILITAR FACE ID / TOUCH ID")
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundColor(ModTheme.textPrimary)
                            }
                            .toggleStyle(SwitchToggleStyle(tint: ModTheme.textPrimary))
                        }
                        .padding(14)
                        .minimalCard()
                    }
                    
                    // Change Passcode Section
                    VStack(alignment: .leading, spacing: 14) {
                        Text("CAMBIAR CÓDIGO PIN")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(ModTheme.textSecondary)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("CÓDIGO ACTUAL")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(ModTheme.textSecondary)
                            SecureField("PIN actual (por defecto 4444)", text: $currentPin)
                                .font(.system(size: 14, design: .monospaced))
                                .keyboardType(.numberPad)
                                .padding(10)
                                .background(ModTheme.surface)
                                .foregroundColor(ModTheme.textPrimary)
                                .cornerRadius(ModTheme.cornerRadiusSmall)
                                .overlay(RoundedRectangle(cornerRadius: ModTheme.cornerRadiusSmall).stroke(ModTheme.border, lineWidth: 1))
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("NUEVO CÓDIGO (4 DÍGITOS)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(ModTheme.textSecondary)
                            SecureField("Nuevo PIN", text: $newPin)
                                .font(.system(size: 14, design: .monospaced))
                                .keyboardType(.numberPad)
                                .padding(10)
                                .background(ModTheme.surface)
                                .foregroundColor(ModTheme.textPrimary)
                                .cornerRadius(ModTheme.cornerRadiusSmall)
                                .overlay(RoundedRectangle(cornerRadius: ModTheme.cornerRadiusSmall).stroke(ModTheme.border, lineWidth: 1))
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("CONFIRMAR NUEVO CÓDIGO")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(ModTheme.textSecondary)
                            SecureField("Repetir nuevo PIN", text: $confirmPin)
                                .font(.system(size: 14, design: .monospaced))
                                .keyboardType(.numberPad)
                                .padding(10)
                                .background(ModTheme.surface)
                                .foregroundColor(ModTheme.textPrimary)
                                .cornerRadius(ModTheme.cornerRadiusSmall)
                                .overlay(RoundedRectangle(cornerRadius: ModTheme.cornerRadiusSmall).stroke(ModTheme.border, lineWidth: 1))
                        }
                        
                        if let msg = statusMessage {
                            Text(msg)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(isSuccess ? ModTheme.textPrimary : ModTheme.destructive)
                        }
                        
                        Button(action: updatePinAction) {
                            Text("ACTUALIZAR PIN")
                                .frame(maxWidth: .infinity)
                        }
                        .minimalButton(isPrimary: true)
                    }
                    .padding(14)
                    .minimalCard()
                    
                    // Lock Immediately Button
                    Button(action: {
                        security.lock()
                    }) {
                        HStack {
                            Image(systemName: "lock.fill")
                            Text("BLOQUEAR AHORA")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .minimalButton(isPrimary: false)
                }
                .padding(16)
            }
        }
        .navigationTitle("SEGURIDAD")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func updatePinAction() {
        guard security.verifyCurrentPasscode(currentPin) else {
            statusMessage = "El código actual es incorrecto."
            isSuccess = false
            return
        }
        guard newPin.count == 4 else {
            statusMessage = "El nuevo PIN debe tener exactamente 4 dígitos."
            isSuccess = false
            return
        }
        guard newPin == confirmPin else {
            statusMessage = "Los códigos nuevos no coinciden."
            isSuccess = false
            return
        }
        
        security.setPasscode(newPin)
        statusMessage = "Código de acceso actualizado exitosamente."
        isSuccess = true
        currentPin = ""
        newPin = ""
        confirmPin = ""
    }
}
