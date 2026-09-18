import SwiftUI

public struct PasscodeView: View {
    @ObservedObject var security = SecurityService.shared
    
    let keypadRows = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["", "0", "delete"]
    ]
    
    public var body: some View {
        ZStack {
            ModTheme.background
                .ignoresSafeArea()
            
            VStack(spacing: 40) {
                Spacer()
                
                // Minimalist Title & Subtitle (No logos)
                VStack(spacing: 12) {
                    Text("MOD MANAGER")
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .tracking(3)
                        .foregroundColor(ModTheme.textPrimary)
                    
                    Text("INTRODUCE EL CÓDIGO DE ACCESO")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(ModTheme.textSecondary)
                }
                
                // Passcode Dots Indicator
                HStack(spacing: 20) {
                    ForEach(0..<4) { index in
                        Circle()
                            .fill(index < security.enteredPin.count ? ModTheme.textPrimary : Color.clear)
                            .frame(width: 14, height: 14)
                            .overlay(
                                Circle()
                                    .stroke(ModTheme.borderActive, lineWidth: 1.5)
                            )
                    }
                }
                .modifier(ShakeEffect(animatableData: security.shouldShake ? 1 : 0))
                
                Spacer()
                
                // Numeric Keypad
                VStack(spacing: 18) {
                    ForEach(keypadRows, id: \.self) { row in
                        HStack(spacing: 28) {
                            ForEach(row, id: \.self) { key in
                                if key == "" {
                                    Color.clear
                                        .frame(width: 72, height: 72)
                                } else if key == "delete" {
                                    Button(action: {
                                        security.deleteDigit()
                                    }) {
                                        ZStack {
                                            Circle()
                                                .fill(ModTheme.surface)
                                                .frame(width: 72, height: 72)
                                                .overlay(
                                                    Circle().stroke(ModTheme.border, lineWidth: 1)
                                                )
                                            Image(systemName: "delete.left")
                                                .font(.system(size: 18, weight: .medium))
                                                .foregroundColor(ModTheme.textPrimary)
                                        }
                                    }
                                } else {
                                    Button(action: {
                                        security.appendDigit(key)
                                    }) {
                                        ZStack {
                                            Circle()
                                                .fill(ModTheme.surface)
                                                .frame(width: 72, height: 72)
                                                .overlay(
                                                    Circle().stroke(ModTheme.border, lineWidth: 1)
                                                )
                                            Text(key)
                                                .font(.system(size: 26, weight: .regular, design: .monospaced))
                                                .foregroundColor(ModTheme.textPrimary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                
                // Face ID button if enabled
                if security.isBiometricsEnabled && security.isBiometricsAvailable {
                    Button(action: {
                        security.authenticateWithBiometrics()
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "faceid")
                            Text("Face ID")
                        }
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(ModTheme.textSecondary)
                        .padding(.top, 10)
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .onAppear {
            if security.isBiometricsEnabled {
                security.authenticateWithBiometrics()
            }
        }
    }
}

// MARK: - Shake Animation Effect
struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat
    
    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = 12 * sin(animatableData * .pi * 3)
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}
