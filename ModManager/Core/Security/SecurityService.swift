import Foundation
import LocalAuthentication
import Combine
import UIKit
import CryptoKit

public final class SecurityService: ObservableObject {
    public static let shared = SecurityService()
    
    // Configuración y llaves
    private let passcodeKey = "com.modmanager.security.passcode_hash"
    private let biometricsEnabledKey = "com.modmanager.security.biometrics_enabled"
    private let defaultPasscode = "4444"
    
    @Published public var isUnlocked: Bool = false
    @Published public var isBiometricsAvailable: Bool = false
    @Published public var isBiometricsEnabled: Bool = false
    @Published public var shouldShake: Bool = false
    @Published public var enteredPin: String = ""
    @Published public var authErrorMessage: String?
    
    private init() {
        checkBiometricsAvailability()
        loadPreferences()
        ensureDefaultPasscodeSet()
    }
    
    private func ensureDefaultPasscodeSet() {
        if UserDefaults.standard.string(forKey: passcodeKey) == nil {
            setPasscode(defaultPasscode)
            ModLog("Código predeterminado establecido: 4444", category: "SEC")
        }
    }
    
    private func loadPreferences() {
        isBiometricsEnabled = UserDefaults.standard.bool(forKey: biometricsEnabledKey)
    }
    
    public func checkBiometricsAvailability() {
        let context = LAContext()
        var error: NSError?
        isBiometricsAvailable = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }
    
    public func authenticateWithBiometrics() {
        guard isBiometricsEnabled && isBiometricsAvailable else { return }
        
        let context = LAContext()
        context.localizedReason = "Desbloquea ModManager con Face ID"
        
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: context.localizedReason) { success, error in
            DispatchQueue.main.async {
                if success {
                    self.unlock()
                } else if let error = error {
                    self.authErrorMessage = error.localizedDescription
                }
            }
        }
    }
    
    public func appendDigit(_ digit: String) {
        guard enteredPin.count < 4 else { return }
        enteredPin.append(digit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        
        if enteredPin.count == 4 {
            validateEnteredPin()
        }
    }
    
    public func deleteDigit() {
        guard !enteredPin.isEmpty else { return }
        enteredPin.removeLast()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    
    public func clearPin() {
        enteredPin = ""
    }
    
    public func validateEnteredPin() {
        let currentHash = hashString(enteredPin)
        let storedHash = UserDefaults.standard.string(forKey: passcodeKey) ?? hashString(defaultPasscode)
        
        if currentHash == storedHash {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            unlock()
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            triggerShake()
            ModLog("Intento de acceso fallido con código incorrecto", category: "SEC")
        }
    }
    
    private func triggerShake() {
        shouldShake = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            self.shouldShake = false
            self.enteredPin = ""
        }
    }
    
    public func unlock() {
        isUnlocked = true
        enteredPin = ""
        authErrorMessage = nil
        ModLog("Acceso concedido a la aplicación", category: "SEC")
    }
    
    public func lock() {
        isUnlocked = false
        enteredPin = ""
    }
    
    public func setPasscode(_ newPin: String) {
        guard newPin.count >= 4 else { return }
        let hash = hashString(newPin)
        UserDefaults.standard.set(hash, forKey: passcodeKey)
    }
    
    public func verifyCurrentPasscode(_ pin: String) -> Bool {
        let currentHash = hashString(pin)
        let storedHash = UserDefaults.standard.string(forKey: passcodeKey) ?? hashString(defaultPasscode)
        return currentHash == storedHash
    }
    
    public func setBiometricsEnabled(_ enabled: Bool) {
        isBiometricsEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: biometricsEnabledKey)
    }
    
    private func hashString(_ str: String) -> String {
        guard let data = str.data(using: .utf8) else { return str }
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}

