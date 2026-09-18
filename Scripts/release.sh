#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="K-Deck"
SIGN_ID="Developer ID Application: EREN KIRKIL (992XYS9346)"
PROFILE_NAME="${1:-kdeck-notary}"

# Hedef tag tespiti (parametre veya Info.plist)
PLIST_VERSION="$(plutil -extract CFBundleShortVersionString raw -expect string "$PROJECT_DIR/Scripts/Info.plist" 2>/dev/null || echo "1.0.0")"
TAG="${2:-v$PLIST_VERSION}"
if [ "$TAG" = "--no-upload" ]; then
    TAG="v$PLIST_VERSION"
    SKIP_UPLOAD=true
else
    SKIP_UPLOAD=false
    if [ "${3:-}" = "--no-upload" ]; then
        SKIP_UPLOAD=true
    fi
fi

if [[ "$TAG" != v* ]]; then
    TAG="v$TAG"
fi

BUNDLE_DIR="$PROJECT_DIR/build/$APP_NAME.app"
DMG_DIR="$PROJECT_DIR/dist"
DMG_PATH="$DMG_DIR/$APP_NAME.dmg"
STAGING_DIR="$PROJECT_DIR/build/dmg_staging"

echo "🚀 Başlatılıyor: $APP_NAME Release, Notarization & GitHub Workflow"
echo "🔑 İmza Kimliği: $SIGN_ID"
echo "🔐 Notary Profili: $PROFILE_NAME"
echo "🏷️ Hedef Sürüm/Tag: $TAG"
echo ""

# 1. Swift projesi derleniyor
echo "🔨 [1/7] Swift projesi release modunda derleniyor..."
cd "$PROJECT_DIR"
swift build -c release

BIN_PATH="$PROJECT_DIR/.build/release/KDeck"
MODULE_BUNDLE_PATH="$PROJECT_DIR/.build/release/KDeck_KDeck.bundle"

# 2. .app paketi hazırlanıyor
echo "📦 [2/7] .app paket yapısı hazırlanıyor..."
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
echo "🔏 [3/7] .app paketi Developer ID ile imzalanıyor..."
codesign --force --deep --sign "$SIGN_ID" --options runtime --timestamp "$BUNDLE_DIR"
echo "🔍 İmza doğrulanıyor..."
codesign --verify --deep --strict --verbose=2 "$BUNDLE_DIR"

# 4. DMG Hazırlanıyor
echo "💿 [4/7] DMG imajı oluşturuluyor..."
mkdir -p "$DMG_DIR"
mkdir -p "$STAGING_DIR"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$BUNDLE_DIR" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH"

# 5. DMG İmzalanıyor
echo "🔏 [5/7] DMG imzalanıyor..."
codesign --force --sign "$SIGN_ID" --timestamp "$DMG_PATH"
codesign --verify --verbose=2 "$DMG_PATH"

# 6. Notarization & Staple
echo "☁️ [6/7] Apple Notary servisine gönderiliyor..."
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$PROFILE_NAME" --wait

echo "📎 Noter bileti DMG'ye zımbalanıyor (Staple)..."
xcrun stapler staple "$DMG_PATH"

echo "🔎 Gatekeeper doğrulaması yapılıyor..."
spctl -a -t open --context context:primary-signature -v "$DMG_PATH"

# 7. GitHub Release Güncelleme / Yükleme
if [ "$SKIP_UPLOAD" = true ]; then
    echo "⏭️ [7/7] GitHub Release yükleme adımı atlandı (--no-upload)."
else
    echo "🐙 [7/7] GitHub Release güncelleniyor ($TAG)..."
    if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
        if gh release view "$TAG" >/dev/null 2>&1; then
            echo "📤 Mevcut $TAG sürümüne yeni DMG yükleniyor (clobber)..."
            gh release upload "$TAG" "$DMG_PATH" --clobber
            echo "✅ GitHub Release ($TAG) başarıyla güncellendi!"
        else
            echo "🎉 Yeni GitHub Release oluşturuluyor ($TAG)..."
            gh release create "$TAG" "$DMG_PATH" --title "$TAG" --generate-notes
            echo "✅ Yeni GitHub Release ($TAG) başarıyla oluşturuldu ve DMG yüklendi!"
        fi
        echo "🔗 https://github.com/erenkirkil/K-Deck/releases/tag/$TAG"
    else
        echo "⚠️ GitHub CLI (gh) bulunamadı veya oturum açılmamış. DMG yerelde hazır ancak GitHub'a otomatik yüklenemedi."
    fi
fi

echo ""
echo "🎉 Tüm adımlar başarıyla tamamlandı! Dağıtıma hazır Apple onaylı DMG:"
echo "👉 $DMG_PATH"
