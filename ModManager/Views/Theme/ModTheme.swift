import SwiftUI

// MARK: - Minimalist Black & White Design System
public enum ModTheme {
    // Pure Monochrome Palette
    public static let background = Color(hex: "000000")       // Pitch black
    public static let surface = Color(hex: "0D0D0D")          // Deep black surface
    public static let surfaceSecondary = Color(hex: "181818") // Elevated card surface
    public static let border = Color(hex: "282828")           // Subtle gray divider
    public static let borderActive = Color(hex: "555555")     // Highlighted border
    
    // Text Hierarchy
    public static let textPrimary = Color(hex: "FFFFFF")      // Pure crisp white
    public static let textSecondary = Color(hex: "8E8E93")    // Subdued gray
    public static let textMuted = Color(hex: "48484A")        // Faint gray
    
    // Status (Monochrome Style)
    public static let activeIndicator = Color(hex: "FFFFFF")  // Active state: bright white
    public static let inactiveIndicator = Color(hex: "3A3A3C")// Inactive state: dark gray
    public static let destructive = Color(hex: "E0E0E0")      // Clean high-contrast accent
    
    // Spacing & Corner Radii
    public static let cornerRadiusSmall: CGFloat = 8
    public static let cornerRadiusMedium: CGFloat = 14
    public static let cornerRadiusLarge: CGFloat = 20
    public static let cornerRadius: CGFloat = 14
}

// MARK: - Color Hex Initializer
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Minimalist Card & Button View Modifiers
public struct MinimalCardModifier: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .background(ModTheme.surface)
            .cornerRadius(ModTheme.cornerRadiusMedium)
            .overlay(
                RoundedRectangle(cornerRadius: ModTheme.cornerRadiusMedium)
                    .stroke(ModTheme.border, lineWidth: 1)
            )
    }
}

public struct MinimalButtonModifier: ViewModifier {
    let isPrimary: Bool
    
    public func body(content: Content) -> some View {
        content
            .font(.system(size: 14, weight: .semibold, design: .monospaced))
            .foregroundColor(isPrimary ? ModTheme.background : ModTheme.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(isPrimary ? ModTheme.textPrimary : ModTheme.surfaceSecondary)
            .cornerRadius(ModTheme.cornerRadiusSmall)
            .overlay(
                RoundedRectangle(cornerRadius: ModTheme.cornerRadiusSmall)
                    .stroke(isPrimary ? Color.clear : ModTheme.border, lineWidth: 1)
            )
    }
}

public extension View {
    func minimalCard() -> some View {
        modifier(MinimalCardModifier())
    }
    
    func minimalButton(isPrimary: Bool = true) -> some View {
        modifier(MinimalButtonModifier(isPrimary: isPrimary))
    }
}
