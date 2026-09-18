import SwiftUI

public struct RootView: View {
    @ObservedObject var security = SecurityService.shared
    @State private var selectedTab: Int = 0
    
    public init() {
        // Estilo de TabBar minimalista en negro puro
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(named: "Background") ?? .black
        appearance.stackedLayoutAppearance.selected.iconColor = .white
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor.white]
        appearance.stackedLayoutAppearance.normal.iconColor = .darkGray
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.darkGray]
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
    
    public var body: some View {
        ZStack {
            ModTheme.background
                .ignoresSafeArea()
            
            if !security.isUnlocked {
                PasscodeView()
                    .transition(.opacity)
            } else {
                TabView(selection: $selectedTab) {
                    MainView()
                        .tabItem {
                            Image(systemName: "square.stack.3d.up")
                            Text("MAIN")
                                .font(.system(size: 10, design: .monospaced))
                        }
                        .tag(0)
                    
                    SettingsView()
                        .tabItem {
                            Image(systemName: "gearshape")
                            Text("SETTINGS")
                                .font(.system(size: 10, design: .monospaced))
                        }
                        .tag(1)
                }
                .accentColor(ModTheme.textPrimary)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: security.isUnlocked)
    }
}
