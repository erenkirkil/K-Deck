#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="K-Deck"
BUNDLE_DIR="$PROJECT_DIR/build/$APP_NAME.app"

echo "🔨 [1/4] Swift projesi derleniyor (release modu)..."
cd "$PROJECT_DIR"
swift build -c release

BIN_PATH="$PROJECT_DIR/.build/release/KDeck"
MODULE_BUNDLE_PATH="$PROJECT_DIR/.build/release/KDeck_KDeck.bundle"

echo "📦 [2/4] .app paket yapısı hazırlanıyor..."
mkdir -p "$BUNDLE_DIR/Contents/MacOS"
mkdir -p "$BUNDLE_DIR/Contents/Resources"

echo "📋 [3/4] Dosyalar kopyalanıyor..."
cp "$PROJECT_DIR/Scripts/Info.plist" "$BUNDLE_DIR/Contents/Info.plist"
cp "$BIN_PATH" "$BUNDLE_DIR/Contents/MacOS/KDeck"
chmod +x "$BUNDLE_DIR/Contents/MacOS/KDeck"

if [ -d "$MODULE_BUNDLE_PATH" ]; then
    cp -R "$MODULE_BUNDLE_PATH" "$BUNDLE_DIR/Contents/Resources/"
fi

# Resource dosyalarını doğrudan da Contents/Resources içine kopyalayalım (fallback için)
if [ -d "$PROJECT_DIR/Sources/KDeck/Resources" ]; then
    cp -R "$PROJECT_DIR/Sources/KDeck/Resources/"* "$BUNDLE_DIR/Contents/Resources/"
fi

echo "🛡️ [4/4] Ad-hoc imza uygulanıyor..."
codesign --force --deep --sign - "$BUNDLE_DIR"

echo ""
echo "✅ Başarıyla tamamlandı! Uygulama paketi hazır:"
echo "👉 $BUNDLE_DIR"
echo ""
echo "Uygulamayı /Applications altına taşımak için:"
echo "cp -R \"$BUNDLE_DIR\" /Applications/"
