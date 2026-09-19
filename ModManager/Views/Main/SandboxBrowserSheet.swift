import SwiftUI
import UIKit

public struct SandboxBrowserSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var containerService = ContainerService.shared
    
    let bundleID: String
    let appName: String
    @Binding var selectedRelativePath: String
    
    @State private var currentSubpath: String = ""
    @State private var searchText: String = ""
    @State private var toastMessage: String?
    @State private var showToast: Bool = false
    
    public init(
        bundleID: String,
        appName: String,
        selectedRelativePath: Binding<String>
    ) {
        self.bundleID = bundleID
        self.appName = appName
        self._selectedRelativePath = selectedRelativePath
    }
    
    private var containerPath: String? {
        containerService.resolveContainerPath(for: bundleID)
    }
    
    private var items: [SandboxFileItem] {
        let all = containerService.listContents(bundleID: bundleID, subpath: currentSubpath)
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return all
        }
        return all.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    public var body: some View {
        NavigationView {
            ZStack {
                ModTheme.background
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header: App info & resolved container
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(appName.isEmpty ? bundleID : appName)
                                .font(.system(size: 15, weight: .bold, design: .monospaced))
                                .foregroundColor(ModTheme.textPrimary)
                            Spacer()
                            Text(bundleID)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(ModTheme.textSecondary)
                        }
                        
                        if let path = containerPath {
                            Text("SANDBOX: \(path)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(ModTheme.textMuted)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } else {
                            Text("Contenedor no resuelto. Verifica permisos de acceso.")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(ModTheme.destructive)
                        }
                    }
                    .padding(14)
                    .background(ModTheme.surface)
                    .overlay(
                        Rectangle()
                            .frame(height: 1)
                            .foregroundColor(ModTheme.border),
                        alignment: .bottom
                    )
                    
                    // Quick Folder Shortcuts
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            shortcutButton(title: "Raíz", path: "")
                            shortcutButton(title: "Documents", path: "Documents")
                            shortcutButton(title: "Library", path: "Library")
                            shortcutButton(title: "Preferences", path: "Library/Preferences")
                            shortcutButton(title: "App Support", path: "Library/Application Support")
                            shortcutButton(title: "Caches", path: "Library/Caches")
                            shortcutButton(title: "tmp", path: "tmp")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .background(ModTheme.surfaceSecondary)
                    
                    // Current Path & Navigation Breadcrumb
                    HStack(spacing: 8) {
                        if !currentSubpath.isEmpty {
                            Button(action: goUpOneLevel) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.up")
                                    Text("Subir")
                                }
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(ModTheme.textPrimary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(ModTheme.surface)
                                .cornerRadius(4)
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(ModTheme.border, lineWidth: 1))
                            }
                        }
                        
                        Image(systemName: "folder")
                            .font(.system(size: 12))
                            .foregroundColor(ModTheme.textSecondary)
                        
                        Text(currentSubpath.isEmpty ? "/" : "/\(currentSubpath)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(ModTheme.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.head)
                        
                        Spacer()
                        
                        // Botón de 1 toque: Establecer esta carpeta como destino
                        Button(action: {
                            HapticService.shared.lightTap()
                            selectedRelativePath = currentSubpath
                            toast("Carpeta seleccionada como destino")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                dismiss()
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Usar esta carpeta")
                            }
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(ModTheme.background)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(ModTheme.textPrimary)
                            .cornerRadius(4)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(ModTheme.surface)
                    .overlay(
                        Rectangle()
                            .frame(height: 1)
                            .foregroundColor(ModTheme.border),
                        alignment: .bottom
                    )
                    
                    // Search Bar
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(ModTheme.textSecondary)
                        TextField("Filtrar archivos en esta carpeta...", text: $searchText)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(ModTheme.textPrimary)
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(ModTheme.textSecondary)
                            }
                        }
                    }
                    .padding(10)
                    .background(ModTheme.surfaceSecondary)
                    .cornerRadius(ModTheme.cornerRadiusSmall)
                    .overlay(RoundedRectangle(cornerRadius: ModTheme.cornerRadiusSmall).stroke(ModTheme.border, lineWidth: 1))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    
                    // Items List
                    if items.isEmpty {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: "folder.badge.minus")
                                .font(.system(size: 36))
                                .foregroundColor(ModTheme.textMuted)
                            Text("Esta carpeta está vacía o no es accesible")
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(ModTheme.textSecondary)
                        }
                        Spacer()
                    } else {
                        List {
                            ForEach(items) { item in
                                itemRow(item)
                                    .listRowBackground(ModTheme.surface)
                                    .listRowSeparatorTint(ModTheme.border)
                            }
                        }
                        .listStyle(.plain)
                        .background(ModTheme.background)
                    }
                }
                
                // Toast notification for copying paths
                if showToast, let msg = toastMessage {
                    VStack {
                        Spacer()
                        HStack(spacing: 8) {
                            Image(systemName: "doc.on.doc.fill")
                                .font(.system(size: 12))
                            Text(msg)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .lineLimit(2)
                        }
                        .foregroundColor(ModTheme.background)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(ModTheme.textPrimary)
                        .cornerRadius(8)
                        .shadow(radius: 6)
                        .padding(.bottom, 24)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.25), value: showToast)
                }
            }
            .navigationTitle("EXPLORADOR DE SANDBOX")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") {
                        dismiss()
                    }
                    .foregroundColor(ModTheme.textPrimary)
                    .font(.system(size: 14, design: .monospaced))
                }
            }
        }
    }
    
    // MARK: - Subviews
    
    private func shortcutButton(title: String, path: String) -> some View {
        let isSelected = (currentSubpath == path)
        return Button(action: {
            currentSubpath = path
            searchText = ""
        }) {
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .bold : .regular, design: .monospaced))
                .foregroundColor(isSelected ? ModTheme.background : ModTheme.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? ModTheme.textPrimary : ModTheme.surface)
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(ModTheme.border, lineWidth: 1)
                )
        }
    }
    
    private func itemRow(_ item: SandboxFileItem) -> some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: item.isDirectory ? "folder.fill" : iconForFile(item.name))
                .font(.system(size: 18))
                .foregroundColor(item.isDirectory ? ModTheme.textPrimary : ModTheme.textSecondary)
                .frame(width: 24)
            
            // Name & metadata
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.system(size: 13, weight: item.isDirectory ? .bold : .medium, design: .monospaced))
                    .foregroundColor(ModTheme.textPrimary)
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    Text(item.formattedSize)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(ModTheme.textMuted)
                    
                    if let date = item.modificationDate {
                        Text("•")
                            .foregroundColor(ModTheme.textMuted)
                        Text(date, style: .date)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(ModTheme.textMuted)
                    }
                }
            }
            
            Spacer()
            
            // Action Menu / Buttons
            HStack(spacing: 6) {
                // Menu for copy options
                Menu {
                    Button(action: { copyToClipboard(text: item.relativePath, label: "Ruta relativa") }) {
                        Label("Copiar Ruta Relativa", systemImage: "doc.on.doc")
                    }
                    Button(action: { copyToClipboard(text: item.fullPath, label: "Ruta absoluta") }) {
                        Label("Copiar Ruta Absoluta", systemImage: "link")
                    }
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 13))
                        .foregroundColor(ModTheme.textSecondary)
                        .padding(8)
                        .background(ModTheme.surfaceSecondary)
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(ModTheme.border, lineWidth: 1))
                }
                
                if item.isDirectory {
                    Menu {
                        Button(action: {
                            HapticService.shared.lightTap()
                            selectedRelativePath = item.relativePath
                            toast("Carpeta seleccionada como destino")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                dismiss()
                            }
                        }) {
                            Label("Usar como Carpeta Destino", systemImage: "folder.badge.checkmark")
                        }
                        Button(action: {
                            HapticService.shared.lightTap()
                            currentSubpath = item.relativePath
                            searchText = ""
                        }) {
                            Label("Abrir Carpeta", systemImage: "folder")
                        }
                        Button(action: { copyToClipboard(text: item.relativePath, label: "Ruta relativa") }) {
                            Label("Copiar Ruta Relativa", systemImage: "doc.on.doc")
                        }
                        Button(action: { copyToClipboard(text: item.fullPath, label: "Ruta absoluta") }) {
                            Label("Copiar Ruta Absoluta", systemImage: "link")
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Text("Elegir")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8))
                        }
                        .foregroundColor(ModTheme.textPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(ModTheme.surfaceSecondary)
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(ModTheme.border, lineWidth: 1))
                    }
                    
                    // Navigate inside directory
                    Button(action: {
                        HapticService.shared.lightTap()
                        currentSubpath = item.relativePath
                        searchText = ""
                    }) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(ModTheme.textPrimary)
                            .padding(8)
                            .background(ModTheme.surfaceSecondary)
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(ModTheme.border, lineWidth: 1))
                    }
                } else {
                    // Select file directly
                    Button(action: {
                        HapticService.shared.lightTap()
                        selectedRelativePath = item.relativePath
                        copyToClipboard(text: item.relativePath, label: "Ruta seleccionada y copiada")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            dismiss()
                        }
                    }) {
                        Text("Elegir")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(ModTheme.background)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(ModTheme.textPrimary)
                            .cornerRadius(6)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Actions
    
    private func goUpOneLevel() {
        HapticService.shared.lightTap()
        let parts = currentSubpath.split(separator: "/")
        if parts.count <= 1 {
            currentSubpath = ""
        } else {
            let parent = parts.dropLast().joined(separator: "/")
            currentSubpath = parent
        }
        searchText = ""
    }
    
    private func toast(_ message: String) {
        toastMessage = message
        showToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation {
                showToast = false
            }
        }
    }
    
    private func copyToClipboard(text: String, label: String) {
        UIPasteboard.general.string = text
        HapticService.shared.lightTap()
        toast("\(label): \(text)")
    }
    
    private func iconForFile(_ name: String) -> String {
        let lower = name.lowercased()
        if lower.hasSuffix(".plist") { return "list.bullet.rectangle" }
        if lower.hasSuffix(".json") { return "curlybraces" }
        if lower.hasSuffix(".txt") || lower.hasSuffix(".log") { return "doc.plaintext" }
        if lower.hasSuffix(".png") || lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") { return "photo" }
        if lower.hasSuffix(".dat") || lower.hasSuffix(".bin") || lower.hasSuffix(".db") || lower.hasSuffix(".sqlite") { return "cylinder.split.1x2" }
        return "doc"
    }
}
