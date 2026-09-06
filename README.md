# K-Deck

Eren Kırkıl macOS uygulamaları için merkezi yönetim, indirme ve otomatik güncelleme aracı.

## Desteklenen Uygulamalar

1. **CloseToQuit** (`erenkirkil/CloseToQuit`) - Pencere kapatıldığında uygulamadan tam çıkış yapma aracı.
2. **sclip** (`erenkirkil/sclip`) - Hızlı ve modern pano yöneticisi (Çoklu platform: macOS & Windows).
3. **DockToggle** (`erenkirkil/DockToggle`) - macOS Dock görünürlüğünü hızlıca değiştirme aracı.
4. **Tiler** (`erenkirkil/Tiler`) - Pencere döşeme ve ekran yönetimi.
5. **ZenBar** (`erenkirkil/zenbar`) - macOS menü çubuğu düzenleyici.

## Özellikler

- 🚀 **Tek Tıkla Kurulum ve Güncelleme**: GitHub Releases üzerinden en güncel `.dmg` dosyalarını otomatik indirir ve `/Applications` dizinine kurar.
- 🔍 **Akıllı Sürüm Takibi**: Sistemde kurulu uygulamaların versiyonu (`Info.plist`) ile GitHub'daki en güncel sürümü (`tag_name`) karşılaştırır.
- 🛡️ **Gatekeeper Karantina Temizliği**: Yeni kurulan veya güncellenen uygulamalar için karantina özniteliğini (`xattr -cr`) otomatik temizler.
- 💻 **Modern Native SwiftUI Arayüzü**: macOS Sequoia & Sonoma tasarım diliyle tam uyumlu şık ve duyarlı kompakt arayüz.
- ⚙️ **Yapılandırılabilir Altyapı**: Yeni uygulamalar `apps_config.json` üzerinden kod değiştirmeden eklenebilir.

## Derleme ve Çalıştırma

```bash
# Geliştirici modunda çalıştırma
swift run

# Bağımsız .app paketi oluşturma
./Scripts/build_app.sh
```
