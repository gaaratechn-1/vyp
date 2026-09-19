import SwiftUI
import UniformTypeIdentifiers

// MARK: - Modelo de Edición para Elementos de un Mod (Lotes)
public struct EditableModItem: Identifiable {
    public let id: UUID
    public var relativePath: String
    public var isDirectory: Bool
    public var payloadFilename: String
    public var payloadData: Data?
    public var payloadText: String
    
    public init(from item: ModItem) {
        self.id = item.id
        self.relativePath = item.relativePath
        self.isDirectory = item.isDirectory
        self.payloadFilename = item.payloadFilename
        self.payloadData = item.payloadData
        if let d = item.payloadData, let s = String(data: d, encoding: .utf8) {
            self.payloadText = s
        } else if let d = item.payloadData {
            self.payloadText = "[Binario: \(d.count) bytes]"
        } else {
            self.payloadText = ""
        }
    }
    
    public init() {
        self.id = UUID()
        self.relativePath = ""
        self.isDirectory = false
        self.payloadFilename = ""
        self.payloadData = nil
        self.payloadText = ""
    }
}

public struct ModEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var engine = ModEngine.shared
    @ObservedObject var containerService = ContainerService.shared
    
    @State private var modName: String = ""
    @State private var targetBundleID: String = "com.dts.freefiremax"
    @State private var selectedAppName: String = "Free Fire MAX"
    
    // Lista de archivos del lote (Punto 5)
    @State private var modItems: [EditableModItem] = [EditableModItem()]
    
    @State private var showAppPicker: Bool = false
    @State private var showSandboxBrowser: Bool = false
    @State private var showFilePicker: Bool = false
    @State private var activeItemIndex: Int = 0
    @State private var errorMessage: String?
    
    var existingProfile: ModProfile?
    
    public init(existingProfile: ModProfile? = nil) {
        self.existingProfile = existingProfile
        if let p = existingProfile {
            _modName = State(initialValue: p.name)
            _targetBundleID = State(initialValue: p.targetBundleID)
            _selectedAppName = State(initialValue: p.targetBundleID == "com.dts.freefireth" ? "Free Fire" : "Free Fire MAX")
            let mapped = p.items.isEmpty ? [EditableModItem()] : p.items.map { EditableModItem(from: $0) }
            _modItems = State(initialValue: mapped)
        }
    }
    
    public var body: some View {
        NavigationView {
            ZStack {
                ModTheme.background
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        // Section 1: Mod Name
                        VStack(alignment: .leading, spacing: 8) {
                            Text("NOMBRE DEL MOD")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(ModTheme.textSecondary)
                            TextField("Ej: Texturas Armas / Gráficos Ultra", text: $modName)
                                .font(.system(size: 14, design: .monospaced))
                                .padding(12)
                                .background(ModTheme.surface)
                                .foregroundColor(ModTheme.textPrimary)
                                .cornerRadius(ModTheme.cornerRadiusSmall)
                                .overlay(RoundedRectangle(cornerRadius: ModTheme.cornerRadiusSmall).stroke(ModTheme.border, lineWidth: 1))
                        }
                        
                        // Section 2: Target App (Free Fire Exclusivo)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("JUEGO DESTINO")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(ModTheme.textSecondary)
                            
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(selectedAppName)
                                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                                        .foregroundColor(ModTheme.textPrimary)
                                    Text(targetBundleID)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(ModTheme.textSecondary)
                                }
                                
                                Spacer()
                                
                                Button("Cambiar Juego") {
                                    HapticService.shared.lightTap()
                                    showAppPicker = true
                                }
                                .minimalButton(isPrimary: false)
                            }
                            .padding(12)
                            .background(ModTheme.surface)
                            .cornerRadius(ModTheme.cornerRadiusSmall)
                            .overlay(RoundedRectangle(cornerRadius: ModTheme.cornerRadiusSmall).stroke(ModTheme.border, lineWidth: 1))
                        }
                        
                        // Section 3: Mod Items (Lotes / Múltiples Elementos)
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text("ARCHIVOS DEL MOD (\(modItems.count))")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(ModTheme.textSecondary)
                                
                                Spacer()
                                
                                Button(action: {
                                    HapticService.shared.lightTap()
                                    modItems.append(EditableModItem())
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "plus.circle")
                                        Text("Añadir Archivo")
                                    }
                                }
                                .minimalButton(isPrimary: false)
                            }
                            
                            ForEach(Array(modItems.indices), id: \.self) { idx in
                                itemEditorCard(index: idx)
                            }
                        }
                        
                        if let err = errorMessage {
                            Text(err)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(ModTheme.destructive)
                                .padding(.horizontal, 4)
                        }
                        
                        // Save Button
                        Button(action: saveMod) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                Text("GUARDAR MOD (\(modItems.count) ELEMENTOS)")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .minimalButton(isPrimary: true)
                        .padding(.top, 10)
                        .padding(.bottom, 30)
                    }
                    .padding(20)
                }
            }
            .navigationTitle(existingProfile == nil ? "CREAR MOD" : "EDITAR MOD")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        HapticService.shared.lightTap()
                        dismiss()
                    }
                    .foregroundColor(ModTheme.textPrimary)
                    .font(.system(size: 14, design: .monospaced))
                }
            }
            .sheet(isPresented: $showAppPicker) {
                AppPickerSheet(
                    selectedBundleID: $targetBundleID,
                    selectedAppName: $selectedAppName
                )
            }
            .sheet(isPresented: $showSandboxBrowser) {
                if activeItemIndex < modItems.count {
                    SandboxBrowserSheet(
                        bundleID: targetBundleID,
                        appName: selectedAppName,
                        selectedRelativePath: $modItems[activeItemIndex].relativePath
                    )
                }
            }
            .sheet(isPresented: $showFilePicker) {
                DocumentPicker { url in
                    if let data = try? Data(contentsOf: url), activeItemIndex < modItems.count {
                        HapticService.shared.lightTap()
                        modItems[activeItemIndex].payloadData = data
                        modItems[activeItemIndex].payloadFilename = url.lastPathComponent
                        if let str = String(data: data, encoding: .utf8) {
                            modItems[activeItemIndex].payloadText = str
                        } else {
                            modItems[activeItemIndex].payloadText = "[Archivo binario: \(data.count) bytes]"
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Tarjeta de Edición de Cada Archivo del Lote
    @ViewBuilder
    private func itemEditorCard(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ELEMENTO #\(index + 1)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(ModTheme.textPrimary)
                
                Spacer()
                
                if modItems.count > 1 {
                    Button(action: {
                        HapticService.shared.lightTap()
                        modItems.remove(at: index)
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundColor(ModTheme.destructive)
                    }
                }
            }
            
            // Ruta exacta o Carpeta
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("RUTA O CARPETA EN SANDBOX")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(ModTheme.textSecondary)
                    
                    Spacer()
                    
                    Button(action: {
                        HapticService.shared.lightTap()
                        activeItemIndex = index
                        showSandboxBrowser = true
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "folder.badge.gearshape")
                            Text("Explorar")
                        }
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(ModTheme.textPrimary)
                    }
                }
                
                TextField("Ej: Documents/content/ o Documents/skin.bytes", text: $modItems[index].relativePath)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(10)
                    .background(ModTheme.surfaceSecondary)
                    .foregroundColor(ModTheme.textPrimary)
                    .cornerRadius(ModTheme.cornerRadiusSmall)
                    .overlay(RoundedRectangle(cornerRadius: ModTheme.cornerRadiusSmall).stroke(ModTheme.border, lineWidth: 1))
            }
            
            // Validación de Ruta
            let validation = containerService.validatePath(bundleID: targetBundleID, relativePath: modItems[index].relativePath)
            pathValidationBadge(info: validation)
            
            // Archivo de Reemplazo
            VStack(alignment: .leading, spacing: 6) {
                Text("CONTENIDO / ARCHIVO DE REEMPLAZO")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(ModTheme.textSecondary)
                
                HStack {
                    if !modItems[index].payloadFilename.isEmpty {
                        Image(systemName: "doc.fill")
                            .foregroundColor(ModTheme.textPrimary)
                        Text(modItems[index].payloadFilename)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(ModTheme.textPrimary)
                            .lineLimit(1)
                    } else {
                        Text("Ningún archivo cargado")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(ModTheme.textMuted)
                    }
                    
                    Spacer()
                    
                    Button("Cargar Archivo") {
                        HapticService.shared.lightTap()
                        activeItemIndex = index
                        showFilePicker = true
                    }
                    .minimalButton(isPrimary: false)
                }
                .padding(10)
                .background(ModTheme.surfaceSecondary)
                .cornerRadius(ModTheme.cornerRadiusSmall)
                .overlay(RoundedRectangle(cornerRadius: ModTheme.cornerRadiusSmall).stroke(ModTheme.border, lineWidth: 1))
                
                // Editor de texto alternativo si es texto plano
                if modItems[index].payloadData == nil || modItems[index].payloadText.starts(with: "[Archivo binario:") == false {
                    TextField("O pega contenido de texto plano aquí...", text: $modItems[index].payloadText)
                        .font(.system(size: 11, design: .monospaced))
                        .padding(8)
                        .background(ModTheme.surfaceSecondary)
                        .foregroundColor(ModTheme.textPrimary)
                        .cornerRadius(4)
                        .onChange(of: modItems[index].payloadText) { val in
                            modItems[index].payloadData = val.data(using: .utf8)
                            if modItems[index].payloadFilename.isEmpty {
                                modItems[index].payloadFilename = "config_override.txt"
                            }
                        }
                }
            }
        }
        .padding(14)
        .background(ModTheme.surface)
        .cornerRadius(ModTheme.cornerRadius)
        .overlay(RoundedRectangle(cornerRadius: ModTheme.cornerRadius).stroke(ModTheme.border, lineWidth: 1))
    }
    
    // MARK: - Badge de Validación
    private func pathValidationBadge(info: PathValidationInfo) -> some View {
        HStack(spacing: 8) {
            Image(systemName: iconForValidation(info.status))
                .font(.system(size: 11, weight: .bold))
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(info.title.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                    if let size = info.formattedSize {
                        Text("(\(size))")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(ModTheme.textMuted)
                    }
                }
                Text(info.message)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(ModTheme.textSecondary)
            }
            
            Spacer()
        }
        .padding(8)
        .background(ModTheme.surfaceSecondary)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(ModTheme.border, lineWidth: 1)
        )
    }
    
    private func iconForValidation(_ status: PathValidationInfo.Status) -> String {
        switch status {
        case .fileExists: return "checkmark.circle.fill"
        case .directoryExists: return "folder.badge.checkmark"
        case .parentExists: return "plus.circle.fill"
        case .targetNotFound: return "questionmark.circle"
        case .containerInaccessible: return "xmark.octagon.fill"
        }
    }
    
    // MARK: - Guardar Mod con Lotes
    private func saveMod() {
        guard !modName.trimmingCharacters(in: .whitespaces).isEmpty else {
            HapticService.shared.warning()
            errorMessage = "Introduce un nombre para el Mod."
            return
        }
        
        var validatedItems: [ModItem] = []
        for (i, item) in modItems.enumerated() {
            let rel = item.relativePath.trimmingCharacters(in: .whitespaces)
            guard !rel.isEmpty else {
                HapticService.shared.warning()
                errorMessage = "El elemento #\(i + 1) debe tener una ruta o carpeta destino."
                return
            }
            let data = item.payloadData ?? item.payloadText.data(using: .utf8) ?? Data()
            guard !data.isEmpty else {
                HapticService.shared.warning()
                errorMessage = "El elemento #\(i + 1) no tiene archivo ni contenido cargado."
                return
            }
            
            let isDir = item.isDirectory || rel.hasSuffix("/")
            let filename = item.payloadFilename.isEmpty ? "mod_payload_\(i + 1).bin" : item.payloadFilename
            
            validatedItems.append(ModItem(
                id: item.id,
                relativePath: rel,
                isDirectory: isDir,
                payloadFilename: filename,
                payloadData: data
            ))
        }
        
        let profile = ModProfile(
            id: existingProfile?.id ?? UUID(),
            name: modName,
            targetBundleID: targetBundleID,
            items: validatedItems
        )
        
        engine.addOrUpdateProfile(profile)
        HapticService.shared.success()
        dismiss()
    }
}

// MARK: - Minimal Document Picker
struct DocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data, .item, .content], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker
        init(_ parent: DocumentPicker) { self.parent = parent }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first {
                parent.onPick(url)
            }
        }
    }
}
