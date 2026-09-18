import SwiftUI

public struct AppPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var containerService = ContainerService.shared
    @Binding var selectedBundleID: String
    @Binding var selectedAppName: String
    
    @State private var searchText: String = ""
    
    var filteredApps: [InstalledAppInfo] {
        if searchText.isEmpty {
            return containerService.installedApps
        }
        return containerService.installedApps.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText) ||
            $0.bundleID.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    public var body: some View {
        NavigationView {
            ZStack {
                ModTheme.background
                    .ignoresSafeArea()
                
                VStack(spacing: 16) {
                    // Search Bar
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(ModTheme.textSecondary)
                        TextField("Buscar aplicación o bundle ID...", text: $searchText)
                            .foregroundColor(ModTheme.textPrimary)
                            .font(.system(size: 14, design: .monospaced))
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(ModTheme.textSecondary)
                            }
                        }
                    }
                    .padding(12)
                    .background(ModTheme.surface)
                    .cornerRadius(ModTheme.cornerRadiusSmall)
                    .overlay(
                        RoundedRectangle(cornerRadius: ModTheme.cornerRadiusSmall)
                            .stroke(ModTheme.border, lineWidth: 1)
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    
                    // Apps List
                    if containerService.isScanning {
                        Spacer()
                        ProgressView()
                            .tint(ModTheme.textPrimary)
                        Text("Escaneando aplicaciones...")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(ModTheme.textSecondary)
                            .padding(.top, 8)
                        Spacer()
                    } else if filteredApps.isEmpty {
                        Spacer()
                        Text("No se encontraron aplicaciones")
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundColor(ModTheme.textSecondary)
                        Spacer()
                    } else {
                        List(filteredApps) { app in
                            Button(action: {
                                selectedBundleID = app.bundleID
                                selectedAppName = app.displayName
                                dismiss()
                            }) {
                                HStack(spacing: 14) {
                                    // Minimalist monochrome badge instead of colored icon
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(ModTheme.surfaceSecondary)
                                            .frame(width: 36, height: 36)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .stroke(ModTheme.border, lineWidth: 1)
                                            )
                                        Image(systemName: "app.fill")
                                            .font(.system(size: 16))
                                            .foregroundColor(ModTheme.textPrimary)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(app.displayName)
                                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                            .foregroundColor(ModTheme.textPrimary)
                                        Text(app.bundleID)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(ModTheme.textSecondary)
                                    }
                                    
                                    Spacer()
                                    
                                    if selectedBundleID == app.bundleID {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(ModTheme.textPrimary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .listRowBackground(ModTheme.surface)
                            .listRowSeparatorTint(ModTheme.border)
                        }
                        .listStyle(.plain)
                        .background(ModTheme.background)
                    }
                }
            }
            .navigationTitle("SELECCIONAR APP")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") {
                        dismiss()
                    }
                    .foregroundColor(ModTheme.textPrimary)
                    .font(.system(size: 14, design: .monospaced))
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { containerService.refreshApps() }) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(ModTheme.textPrimary)
                    }
                }
            }
        }
    }
}
