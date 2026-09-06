#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="K-Deck"
SIGN_ID="Developer ID Application: EREN KIRKIL (992XYS9346)"
PROFILE_NAME="${1:-kdeck-notary}"

BUNDLE_DIR="$PROJECT_DIR/build/$APP_NAME.app"
DMG_DIR="$PROJECT_DIR/dist"
DMG_PATH="$DMG_DIR/$APP_NAME.dmg"
STAGING_DIR="$PROJECT_DIR/build/dmg_staging"

echo "🚀 Başlatılıyor: $APP_NAME Release & Notarization Workflow"
echo "🔑 İmza Kimliği: $SIGN_ID"
echo "🔐 Notary Profili: $PROFILE_NAME"
echo ""

# 1. Swift projesi derleniyor
echo "🔨 [1/6] Swift projesi release modunda derleniyor..."
cd "$PROJECT_DIR"
swift build -c release

BIN_PATH="$PROJECT_DIR/.build/release/KDeck"
MODULE_BUNDLE_PATH="$PROJECT_DIR/.build/release/KDeck_KDeck.bundle"

# 2. .app paketi hazırlanıyor
echo "📦 [2/6] .app paket yapısı hazırlanıyor..."
mkdir -p "$BUNDLE_DIR/Contents/MacOS"
mkdir -p "$BUNDLE_DIR/Contents/Resources"

cp "$PROJECT_DIR/Scripts/Info.plist" "$BUNDLE_DIR/Contents/Info.plist"
cp "$BIN_PATH" "$BUNDLE_DIR/Contents/MacOS/KDeck"
chmod +x "$BUNDLE_DIR/Contents/MacOS/KDeck"

if [ -d "$MODULE_BUNDLE_PATH" ]; then
    cp -R "$MODULE_BUNDLE_PATH" "$BUNDLE_DIR/Contents/Resources/"
fi

if [ -d "$PROJECT_DIR/Sources/KDeck/Resources" ]; then
    cp -R "$PROJECT_DIR/Sources/KDeck/Resources/"* "$BUNDLE_DIR/Contents/Resources/"
fi

if [ -f "$PROJECT_DIR/Scripts/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/Scripts/AppIcon.icns" "$BUNDLE_DIR/Contents/Resources/AppIcon.icns"
fi

# 3. .app İmzalanıyor (Developer ID + Hardened Runtime + Timestamp)
echo "🔏 [3/6] .app paketi Developer ID ile imzalanıyor..."
codesign --force --deep --sign "$SIGN_ID" --options runtime --timestamp "$BUNDLE_DIR"
echo "🔍 İmza doğrulanıyor..."
codesign --verify --deep --strict --verbose=2 "$BUNDLE_DIR"

# 4. DMG Hazırlanıyor
echo "💿 [4/6] DMG imajı oluşturuluyor..."
mkdir -p "$DMG_DIR"
mkdir -p "$STAGING_DIR"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$BUNDLE_DIR" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH"

# 5. DMG İmzalanıyor
echo "🔏 [5/6] DMG imzalanıyor..."
codesign --force --sign "$SIGN_ID" --timestamp "$DMG_PATH"
codesign --verify --verbose=2 "$DMG_PATH"

# 6. Notarization & Staple
echo "☁️ [6/6] Apple Notary servisine gönderiliyor..."
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$PROFILE_NAME" --wait

echo "📎 Noter bileti DMG'ye zımbalanıyor (Staple)..."
xcrun stapler staple "$DMG_PATH"

echo "🔎 Gatekeeper doğrulaması yapılıyor..."
spctl -a -t open --context context:primary-signature -v "$DMG_PATH"

echo ""
echo "🎉 Başarıyla tamamlandı! Apple tarafından onaylanmış DMG hazır:"
echo "👉 $DMG_PATH"
