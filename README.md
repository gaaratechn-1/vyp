# ModManager (iOS)

> Aplicación personal para gestión, reemplazo atómico y restauración dual de modificaciones ("Mods") en el sandbox de aplicaciones de iOS, basada en la técnica MHA-C2 de 3105.

---

## Características

* **UI Minimalista en Blanco y Negro:** Diseño monocromático estricto, sin logos, con tipografía monospaced y alto contraste.
* **Compuerta de Seguridad:** Acceso protegido por código PIN (predeterminado: **`4444`**), con animación de rechazo (shake), hápticos y soporte opcional para Face ID / Touch ID.
* **Acceso a Sandboxes (MHA-C2):** Utiliza el bundle identifier `com.apple.mobile.MobileHouseArrest` y la biblioteca del sistema `libsystem_containermanager.dylib` para obtener tokens de sandbox sin requerir jailbreak permanente ni daemons de fondo.
* **Apartado Main (Mod Center):**
  * Selector de aplicación destino mediante escaneo de contenedores de iOS.
  * Reemplazo atómico de elementos (archivos individuales o directorios completos) especificando la ruta relativa exacta dentro de `Data/Application/<UUID>/`.
  * Verificación de integridad mediante hashes SHA-256.
* **Restauración Dual:**
  * **Restablecer Original (Local):** Restaura la copia de seguridad original generada automáticamente de forma previa al reemplazo.
  * **Restablecer Original (Servidor Local):** Descarga el archivo original limpio oficial desde tu servidor local configurado por IP y Puerto.
* **Apartado Settings:**
  * Configuración de Servidor Local (`http://IP:PUERTO`), botón de prueba de conexión y sincronización de catálogo.
  * Panel de seguridad para cambiar el PIN `4444` y alternar biometría.
  * Panel de diagnósticos con verificación de Bundle ID, espacio ocupado en disco por backups y consola de logs en tiempo real.

---

## Estructura del Proyecto

```text
ModManager/
├── ModManager/
│   ├── App/
│   │   ├── ModManagerApp.swift           # Entrada de la app y bloqueo en background
│   │   └── RootView.swift                # Router entre PIN y Main / Settings
│   ├── Core/
│   │   ├── Bridging/
│   │   │   ├── ModManager-Bridging-Header.h
│   │   │   ├── mcm_bridge.h
│   │   │   └── mcm_bridge.m              # Acceso al sandbox con MHA-C2
│   │   ├── Security/
│   │   │   └── SecurityService.swift     # PIN 4444, Face ID y Keychain
│   │   ├── Sandbox/
│   │   │   └── ContainerService.swift    # Resolución de contenedores
│   │   ├── Engine/
│   │   │   ├── ModEngine.swift           # Reemplazo atómico y restauración dual
│   │   │   └── BackupManager.swift       # Gestión de copias de seguridad de originales
│   │   └── Network/
│   │       └── LocalServerClient.swift   # Cliente HTTP para IP:Puerto
│   ├── Models/
│   │   ├── ModItem.swift
│   │   ├── ModProfile.swift
│   │   ├── InstalledAppInfo.swift
│   │   └── ServerConfig.swift
│   ├── Views/
│   │   ├── Security/
│   │   │   └── PasscodeView.swift        # Teclado numérico B&W
│   │   ├── Main/
│   │   │   ├── MainView.swift            # Centro de Mods
│   │   │   ├── ModCardView.swift         # Tarjeta de Mod y acciones
│   │   │   ├── ModEditorSheet.swift      # Creador/Editor de mods
│   │   │   └── AppPickerSheet.swift      # Selector de apps instaladas
│   │   ├── Settings/
│   │   │   ├── SettingsView.swift
│   │   │   ├── ServerSettingsView.swift  # Configuración IP:Puerto
│   │   │   ├── SecuritySettingsView.swift# Cambio de PIN
│   │   │   └── DiagnosticsView.swift     # Logs y auditoría
│   │   └── Theme/
│   │       └── ModTheme.swift            # Sistema de diseño monocromático
│   └── Resources/
│       ├── Info.plist                    # Bundle ID: com.apple.mobile.MobileHouseArrest
│       └── Assets.xcassets/
├── ModManager.xcodeproj/                 # Proyecto Xcode listo para compilar
├── server/
│   └── local_server.py                   # Servidor local Python de referencia
└── .github/
    └── workflows/
        └── build-ipa.yml                 # Compilación automática de IPA en GitHub
```

---

## Servidor Local (IP y Puerto)

Para sincronizar Mods o permitir la restauración de archivos originales desde tu red local:

1. Abre una terminal en la carpeta `server`:
   ```bash
   cd server
   python local_server.py
   ```
2. El servidor detectará automáticamente tu dirección IP local y mostrará:
   ```text
   [*] Dirección IP detectada: 192.168.1.xxx
   [*] Puerto configurado:    8080
   [*] URL para la App:       http://192.168.1.xxx:8080
   ```
3. En la app ModManager, ve a **SETTINGS** -> **SERVIDOR LOCAL**, introduce la IP y el Puerto, y presiona **PROBAR CONEXIÓN**.
4. **Estructura de archivos en el servidor:**
   * Archivos originales limpios: `server/originals_repo/<bundle_id>/<ruta_relativa>`
   * Archivos de mod: `server/mods_repo/<id>.bin`
   * Catálogo de mods: `server/catalog.json`

---

## Compilación y Generación de la IPA

### Opción 1: GitHub Actions (Automático)
1. Sube este repositorio a tu GitHub:
   ```bash
   git init
   git add .
   git commit -m "Initial commit of ModManager"
   git remote add origin https://github.com/tu-usuario/tu-repo.git
   git push -u origin main
   ```
2. La acción `.github/workflows/build-ipa.yml` se ejecutará automáticamente en un runner de macOS, compilará el proyecto y generará el archivo `ModManager.ipa` en los artefactos de la compilación o en GitHub Releases (al crear un tag `v1.0.0`).

### Opción 2: Compilación Local en Mac (Xcode / Terminal)
```bash
xcodebuild archive \
  -project ModManager.xcodeproj \
  -scheme ModManager \
  -configuration Release \
  -archivePath build/ModManager.xcarchive \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO

mkdir -p build/Payload
cp -r build/ModManager.xcarchive/Products/Applications/ModManager.app build/Payload/
cd build && zip -r ModManager.ipa Payload
```

---

## Firma e Instalación en Dispositivo

> **IMPORTANTE:** Para que `libsystem_containermanager.dylib` otorgue los permisos de acceso a los sandboxes de otras aplicaciones, el archivo `Info.plist` DEBE mantener `CFBundleIdentifier` como `com.apple.mobile.MobileHouseArrest`. Debe firmarse utilizando un certificado Enterprise o herramientas de firma compatibles.
