import SwiftUI
import UniformTypeIdentifiers

public struct ModEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var engine = ModEngine.shared
    
    @State private var modName: String = ""
    @State private var targetBundleID: String = ""
    @State private var selectedAppName: String = ""
    @State private var relativePath: String = ""
    @State private var isDirectory: Bool = false
    @State private var payloadFilename: String = ""
    @State private var payloadText: String = ""
    @State private var payloadData: Data? = nil
    
    @State private var showAppPicker: Bool = false
    @State private var showFilePicker: Bool = false
    @State private var errorMessage: String?
    
    var existingProfile: ModProfile?
    
    public init(existingProfile: ModProfile? = nil) {
        self.existingProfile = existingProfile
        if let p = existingProfile {
            _modName = State(initialValue: p.name)
            _targetBundleID = State(initialValue: p.targetBundleID)
            if let firstItem = p.items.first {
                _relativePath = State(initialValue: firstItem.relativePath)
                _isDirectory = State(initialValue: firstItem.isDirectory)
                _payloadFilename = State(initialValue: firstItem.payloadFilename)
                _payloadData = State(initialValue: firstItem.payloadData)
                if let d = firstItem.payloadData, let str = String(data: d, encoding: .utf8) {
                    _payloadText = State(initialValue: str)
                }
            }
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
                            TextField("Ej: Monedas Ilimitadas / Texturas HD", text: $modName)
                                .font(.system(size: 14, design: .monospaced))
                                .padding(12)
                                .background(ModTheme.surface)
                                .foregroundColor(ModTheme.textPrimary)
                                .cornerRadius(ModTheme.cornerRadiusSmall)
                                .overlay(RoundedRectangle(cornerRadius: ModTheme.cornerRadiusSmall).stroke(ModTheme.border, lineWidth: 1))
                        }
                        
                        // Section 2: Target App
                        VStack(alignment: .leading, spacing: 8) {
                            Text("APLICACIÓN DESTINO")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(ModTheme.textSecondary)
                            
                            HStack {
                                TextField("Bundle ID (ej: com.company.game)", text: $targetBundleID)
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundColor(ModTheme.textPrimary)
                                
                                Button("Buscar") {
                                    showAppPicker = true
                                }
                                .minimalButton(isPrimary: false)
                            }
                            .padding(8)
                            .background(ModTheme.surface)
                            .cornerRadius(ModTheme.cornerRadiusSmall)
                            .overlay(RoundedRectangle(cornerRadius: ModTheme.cornerRadiusSmall).stroke(ModTheme.border, lineWidth: 1))
                        }
                        
                        // Section 3: Exact Target Path
                        VStack(alignment: .leading, spacing: 8) {
                            Text("RUTA EXACTA EN EL SANDBOX")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(ModTheme.textSecondary)
                            
                            TextField("Ej: Documents/game_save.dat", text: $relativePath)
                                .font(.system(size: 13, design: .monospaced))
                                .padding(12)
                                .background(ModTheme.surface)
                                .foregroundColor(ModTheme.textPrimary)
                                .cornerRadius(ModTheme.cornerRadiusSmall)
                                .overlay(RoundedRectangle(cornerRadius: ModTheme.cornerRadiusSmall).stroke(ModTheme.border, lineWidth: 1))
                            
                            Text("Ruta relativa dentro de Data/Application/<UUID>/")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(ModTheme.textMuted)
                        }
                        
                        // Section 4: Replacement Content
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("CONTENIDO DE REEMPLAZO")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(ModTheme.textSecondary)
                                Spacer()
                                Button("Importar archivo") {
                                    showFilePicker = true
                                }
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(ModTheme.textPrimary)
                            }
                            
                            if !payloadFilename.isEmpty {
                                HStack {
                                    Image(systemName: "doc.fill")
                                        .foregroundColor(ModTheme.textPrimary)
                                    Text(payloadFilename)
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundColor(ModTheme.textPrimary)
                                    Spacer()
                                    if let bytes = payloadData?.count {
                                        Text("\(bytes) bytes")
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(ModTheme.textSecondary)
                                    }
                                }
                                .padding(10)
                                .background(ModTheme.surfaceSecondary)
                                .cornerRadius(ModTheme.cornerRadiusSmall)
                            }
                            
                            // Editor de texto/código integrado para mods ligeros (json, plist, txt)
                            TextEditor(text: $payloadText)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(ModTheme.textPrimary)
                                .frame(height: 120)
                                .padding(8)
                                .background(ModTheme.surface)
                                .cornerRadius(ModTheme.cornerRadiusSmall)
                                .overlay(RoundedRectangle(cornerRadius: ModTheme.cornerRadiusSmall).stroke(ModTheme.border, lineWidth: 1))
                                .onChange(of: payloadText) { val in
                                    payloadData = val.data(using: .utf8)
                                    if payloadFilename.isEmpty {
                                        payloadFilename = "custom_mod.txt"
                                    }
                                }
                        }
                        
                        if let err = errorMessage {
                            Text(err)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(ModTheme.destructive)
                        }
                        
                        // Save Button
                        Button(action: saveMod) {
                            Text("GUARDAR MOD")
                                .frame(maxWidth: .infinity)
                        }
                        .minimalButton(isPrimary: true)
                        .padding(.top, 10)
                    }
                    .padding(20)
                }
            }
            .navigationTitle(existingProfile == nil ? "CREAR MOD" : "EDITAR MOD")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
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
            .sheet(isPresented: $showFilePicker) {
                DocumentPicker { url in
                    if let data = try? Data(contentsOf: url) {
                        self.payloadData = data
                        self.payloadFilename = url.lastPathComponent
                        if let str = String(data: data, encoding: .utf8) {
                            self.payloadText = str
                        } else {
                            self.payloadText = "[Archivo binario: \(data.count) bytes]"
                        }
                    }
                }
            }
        }
    }
    
    private func saveMod() {
        guard !modName.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Introduce un nombre para el Mod."
            return
        }
        guard !targetBundleID.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Introduce el bundle ID de la aplicación."
            return
        }
        guard !relativePath.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Especifica la ruta exacta en el sandbox."
            return
        }
        
        let finalData = payloadData ?? payloadText.data(using: .utf8) ?? Data()
        guard !finalData.isEmpty else {
            errorMessage = "Debes proporcionar contenido o un archivo de reemplazo."
            return
        }
        
        let item = ModItem(
            relativePath: relativePath,
            isDirectory: isDirectory,
            payloadFilename: payloadFilename.isEmpty ? "mod_payload.bin" : payloadFilename,
            payloadData: finalData
        )
        
        let profile = ModProfile(
            id: existingProfile?.id ?? UUID(),
            name: modName,
            targetBundleID: targetBundleID,
            items: [item]
        )
        
        engine.addOrUpdateProfile(profile)
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
