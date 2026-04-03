#!/bin/bash

# Abilita la terminazione in caso di errori
set -e

APP_NAME="MacBeat"
BUILD_DIR=".build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
DMG_NAME="${APP_NAME}.dmg"

echo "🔨 1. Compilazione in modalità Release..."
swift build -c release

# Rileviamo automaticamente la directory di release (per supportare sia arm64 che x86_64)
ACTUAL_RELEASE_DIR=$(find .build -name "release" -type d | grep "apple-macosx" | head -n 1)

if [ -z "$ACTUAL_RELEASE_DIR" ]; then
    echo "Errore: Directory di release non trovata."
    exit 1
fi

echo "📦 2. Creazione della struttura del pacchetto .app..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

echo "📝 3. Copia dell'eseguibile..."
cp "${ACTUAL_RELEASE_DIR}/${APP_NAME}" "${MACOS_DIR}/"

echo "📂 4. Copia delle risorse..."
# Copia il bundle delle risorse SPM se esiste
if [ -d "${ACTUAL_RELEASE_DIR}/${APP_NAME}_${APP_NAME}.bundle" ]; then
    cp -R "${ACTUAL_RELEASE_DIR}/${APP_NAME}_${APP_NAME}.bundle" "${RESOURCES_DIR}/"
fi

echo "⚙️ 5. Generazione Info.plist..."
cp "Sources/MacBeat/Info.plist" "${CONTENTS_DIR}/Info.plist"

# Assicuriamoci che abbia la stringa PkgInfo necessaria per le App macOS
echo "APPL????" > "${CONTENTS_DIR}/PkgInfo"

echo "🎨 6. Creazione dell'icona (AppIcon.icns)..."
LOGO_PATH="Sources/MacBeat/Resources/images/logo.png"
ICONSET_DIR="${BUILD_DIR}/AppIcon.iconset"

if [ -f "$LOGO_PATH" ]; then
    rm -rf "${ICONSET_DIR}"
    mkdir "${ICONSET_DIR}"
    
    # Genera le varie dimensioni
    sips -z 16 16     "$LOGO_PATH" --out "${ICONSET_DIR}/icon_16x16.png" > /dev/null
    sips -z 32 32     "$LOGO_PATH" --out "${ICONSET_DIR}/icon_16x16@2x.png" > /dev/null
    sips -z 32 32     "$LOGO_PATH" --out "${ICONSET_DIR}/icon_32x32.png" > /dev/null
    sips -z 64 64     "$LOGO_PATH" --out "${ICONSET_DIR}/icon_32x32@2x.png" > /dev/null
    sips -z 128 128   "$LOGO_PATH" --out "${ICONSET_DIR}/icon_128x128.png" > /dev/null
    sips -z 256 256   "$LOGO_PATH" --out "${ICONSET_DIR}/icon_128x128@2x.png" > /dev/null
    sips -z 256 256   "$LOGO_PATH" --out "${ICONSET_DIR}/icon_256x256.png" > /dev/null
    sips -z 512 512   "$LOGO_PATH" --out "${ICONSET_DIR}/icon_256x256@2x.png" > /dev/null
    sips -z 512 512   "$LOGO_PATH" --out "${ICONSET_DIR}/icon_512x512.png" > /dev/null
    sips -z 1024 1024 "$LOGO_PATH" --out "${ICONSET_DIR}/icon_512x512@2x.png" > /dev/null
    
    iconutil -c icns "${ICONSET_DIR}" -o "${RESOURCES_DIR}/AppIcon.icns"
    rm -rf "${ICONSET_DIR}"
    
    # Aggiungi chiave CFBundleIconFile al file Info.plist usando plutil
    plutil -insert CFBundleIconFile -string "AppIcon" "${CONTENTS_DIR}/Info.plist"
else
    echo "Nessun logo trovato in $LOGO_PATH. L'icona dell'app non sarà impostata."
fi

echo "🔐 6.5 Firma dell'app (Ad-Hoc per Apple Silicon)..."
codesign --force --deep --sign - "${APP_BUNDLE}"

echo "💽 7. Creazione del DMG..."
rm -f "${DMG_NAME}"

# Creiamo una cartella temporanea per preparare il contenuto del DMG usando esplicitamente BUILD_DIR
DMG_SRC_DIR="${BUILD_DIR}/dmg_source"
rm -rf "${DMG_SRC_DIR}"
mkdir -p "${DMG_SRC_DIR}"

# Sposta l'app nella cartella 
cp -R "${APP_BUNDLE}" "${DMG_SRC_DIR}/"

# Copia il launcher AppleScript (assicurati che il nome del file coincida)
if [ -d "Avvia MacBeat.app" ]; then
    cp -R "Avvia MacBeat.app" "${DMG_SRC_DIR}/"
else
    echo "⚠️ Attenzione: 'Avvia MacBeat.app' non trovato nella root del progetto!"
fi

# Crea il file Leggimi.txt con le istruzioni per i beta tester
cat << 'EOF' > "${DMG_SRC_DIR}/Leggimi.txt"
🥁 BENVENUTO NELLA BETA DI MACBEAT 🥁

Per testare correttamente il rilevamento dei tocchi ad alta fedeltà, segui questi 3 passaggi:

1. Trascina l'icona "MacBeat" nella cartella "Applications" qui a fianco. (Questo è obbligatorio).
2. Copia l'icona "Avvia MacBeat" dove preferisci (ad esempio sul tuo Desktop o in Applicazioni).
3. Usa SEMPRE e SOLO "Avvia MacBeat" per aprire l'app.

⚠️ Nota sulla Sicurezza:
Al primo avvio tramite il launcher ti verrà richiesta la password del Mac. Questo è un passaggio normale e temporaneo per questa versione Beta. MacBeat necessita di questi privilegi per poter accedere in tempo reale all'accelerometro integrato nel telaio.
EOF

# Aggiungi un symlink verso la cartella Applicazioni
ln -s /Applications "${DMG_SRC_DIR}/Applications"

hdiutil create -volname "${APP_NAME}" -srcfolder "${DMG_SRC_DIR}" -ov -format UDZO "${DMG_NAME}"

echo "✅ Finito! L'app e il launcher sono stati pacchettizzati in ${DMG_NAME}"