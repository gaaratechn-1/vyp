#!/usr/bin/env python3
"""
ModManager - Servidor Local de Referencia (Python 3)
Permite alojar Mods y Archivos Originales en tu red local (IP:Puerto)
para sincronizar directamente con la app ModManager en tu iPhone / iPad.
"""

import http.server
import socketserver
import json
import os
import socket
import sys
from urllib.parse import urlparse, unquote

PORT = 8080
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
MODS_DIR = os.path.join(BASE_DIR, "mods_repo")
ORIGINALS_DIR = os.path.join(BASE_DIR, "originals_repo")

# Crear carpetas del repositorio si no existen
os.makedirs(MODS_DIR, exist_ok=True)
os.makedirs(ORIGINALS_DIR, exist_ok=True)

# Crear archivo de catálogo de ejemplo si no existe
CATALOG_PATH = os.path.join(BASE_DIR, "catalog.json")
if not os.path.exists(CATALOG_PATH):
    sample_catalog = [
        {
            "id": "mod-sample-01",
            "name": "Ejemplo: Configuración Optimizada",
            "bundleID": "com.apple.mobilesafari",
            "relativePath": "Library/Preferences/com.apple.mobilesafari.plist",
            "version": "1.0",
            "description": "Configuración de prueba en el sandbox de Safari",
            "downloadURL": "/api/mods/mod-sample-01/download",
            "originalURL": "/api/originals/com.apple.mobilesafari/Library/Preferences/com.apple.mobilesafari.plist",
            "sha256": None
        }
    ]
    with open(CATALOG_PATH, "w", encoding="utf-8") as f:
        json.dump(sample_catalog, f, indent=2, ensure_ascii=False)
        
    # Crear archivo de payload de ejemplo
    sample_payload_path = os.path.join(MODS_DIR, "mod-sample-01.bin")
    if not os.path.exists(sample_payload_path):
        with open(sample_payload_path, "w", encoding="utf-8") as f:
            f.write("<!-- ModManager Sample Configuration Payload -->\n")

def get_local_ip():
    """Detecta la IP local de la máquina en la red Wi-Fi / LAN."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        # No necesita ser alcanzable, solo determina la interfaz adecuada
        s.connect(('10.255.255.255', 1))
        ip = s.getsockname()[0]
    except Exception:
        ip = '127.0.0.1'
    finally:
        s.close()
    return ip

class ModServerHandler(http.server.BaseHTTPRequestHandler):
    def _send_json(self, status_code, data):
        self.send_response(status_code)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Headers', '*')
        self.end_headers()
        self.wfile.write(json.dumps(data, ensure_ascii=False).encode('utf-8'))

    def _send_binary(self, status_code, data, filename="payload.bin"):
        self.send_response(status_code)
        self.send_header('Content-Type', 'application/octet-stream')
        self.send_header('Content-Disposition', f'attachment; filename="{filename}"')
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(data)

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', '*')
        self.end_headers()

    def do_GET(self):
        parsed = urlparse(self.path)
        path = unquote(parsed.path)

        # 1. Health check
        if path == '/health':
            self._send_json(200, {
                "status": "online",
                "server": "ModManager Local Server",
                "version": "1.0.0"
            })
            return

        # 2. Catálogo de mods
        if path == '/api/mods':
            if os.path.exists(CATALOG_PATH):
                with open(CATALOG_PATH, 'r', encoding='utf-8') as f:
                    mods = json.load(f)
                self._send_json(200, mods)
            else:
                self._send_json(200, [])
            return

        # 3. Descarga de mod
        if path.startswith('/api/mods/') and path.endswith('/download'):
            parts = path.split('/')
            if len(parts) >= 4:
                mod_id = parts[3]
                file_path = os.path.join(MODS_DIR, f"{mod_id}.bin")
                if os.path.exists(file_path):
                    with open(file_path, 'rb') as f:
                        data = f.read()
                    self._send_binary(200, data, f"{mod_id}.bin")
                    return
            self._send_json(404, {"error": "Mod payload no encontrado"})
            return

        # 4. Descarga de archivo original limpio
        if path.startswith('/api/originals/'):
            # Formato: /api/originals/<bundle_id>/<relative_path>
            parts = path.replace('/api/originals/', '', 1).split('/', 1)
            if len(parts) == 2:
                bundle_id, rel_path = parts[0], parts[1]
                safe_rel_path = rel_path.replace('..', '').lstrip('/')
                target_file = os.path.join(ORIGINALS_DIR, bundle_id, safe_rel_path)
                if os.path.exists(target_file) and os.path.isfile(target_file):
                    with open(target_file, 'rb') as f:
                        data = f.read()
                    self._send_binary(200, data, os.path.basename(target_file))
                    return
                else:
                    self._send_json(404, {
                        "error": "Archivo original no encontrado en el servidor",
                        "bundleID": bundle_id,
                        "path": safe_rel_path
                    })
                    return

        self._send_json(404, {"error": "Ruta no encontrada", "path": path})

    def log_message(self, format, *args):
        # Monospaced logging en terminal
        sys.stdout.write(f"[HTTP] {self.address_string()} - {format % args}\n")
        sys.stdout.flush()

def run():
    ip = get_local_ip()
    port = PORT
    if len(sys.argv) > 1:
        try:
            port = int(sys.argv[1])
        except ValueError:
            pass

    print("=" * 60)
    print("       MODMANAGER - SERVIDOR LOCAL DE MODS Y ORIGINALES")
    print("=" * 60)
    print(f"[*] Dirección IP detectada: {ip}")
    print(f"[*] Puerto configurado:    {port}")
    print(f"[*] URL para la App:       http://{ip}:{port}")
    print("-" * 60)
    print(f"[+] Carpeta de Mods:       {MODS_DIR}")
    print(f"[+] Carpeta de Originales: {ORIGINALS_DIR}")
    print("=" * 60)
    print("Coloca tus archivos originales en: originals_repo/<bundle_id>/<ruta>")
    print("Coloca tus archivos mod en:        mods_repo/<id>.bin")
    print("Presiona Ctrl+C para detener el servidor.\n")

    with socketserver.TCPServer(("0.0.0.0", port), ModServerHandler) as httpd:
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nDeteniendo servidor...")

if __name__ == '__main__':
    run()
