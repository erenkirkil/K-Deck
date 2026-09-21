import Foundation
import SwiftUI
import Observation

@Observable
@MainActor
public final class AppManager {
    public static let shared = AppManager()

    public var apps: [ManagedApp] = []
    public var statuses: [String: AppStatus] = [:]
    public var releases: [String: GitHubRelease] = [:]
    public var installedInfos: [String: InstalledAppInfo] = [:]
    public var isRefreshingAll: Bool = false

    /// k-deck'in kendisi için bulunan yeni sürüm (varsa). Yalnızca haber verilir.
    public var selfUpdate: SelfUpdateInfo?
    /// Kullanıcı bu oturumda bildirimi kapattıysa tekrar gösterme.
    public var selfUpdateDismissed: Bool = false
    /// Kontrol uygulama ömrü boyunca bir kez yapılır (GitHub anonim limiti saatte 60).
    private var selfUpdateChecked = false

    public struct SelfUpdateInfo: Sendable, Equatable {
        public let currentVersion: String
        public let latestVersion: String
        public let releasesURL: URL
    }
    public var selectedFilter: AppFilter = .all
    public var searchText: String = ""

    // Ayarlar
    private static let tokenAccount = "github_pat"

    /// GitHub PAT. Keychain'de saklanır — eskiden düz metin UserDefaults'taydı.
    public var githubToken: String {
        didSet {
            KeychainStore.set(githubToken, for: Self.tokenAccount)
        }
    }

    public enum AppFilter: String, CaseIterable, Identifiable, Sendable {
        case all = "Tümü"
        case installed = "Yüklü Olanlar"
        case updates = "Güncelleme Var"
        case notInstalled = "Yüklü Olmayanlar"

        public var id: String { rawValue }
    }

    public init() {
        // Keychain'den oku; eski sürümden kalan düz metin token varsa bir kez taşı ve sil.
        if let stored = KeychainStore.get(Self.tokenAccount) {
            self.githubToken = stored
        } else if let legacy = UserDefaults.standard.string(forKey: "kirkil_github_token"),
                  !legacy.isEmpty {
            self.githubToken = legacy
            KeychainStore.set(legacy, for: Self.tokenAccount)
            UserDefaults.standard.removeObject(forKey: "kirkil_github_token")
        } else {
            self.githubToken = ""
        }
        loadConfig()
    }

    /// apps_config.json dosyasının URL'sini bulur (App bundle, Resource bundle veya çalışma dizini)
    private static func findAppsConfigURL() -> URL? {
        // 1. Standart macOS app bundle (Contents/Resources)
        if let url = Bundle.main.url(forResource: "apps_config", withExtension: "json") {
            return url
        }

        // 2. Resource bundle (Contents/Resources/KDeck_KDeck.bundle)
        if let bundleUrl = Bundle.main.url(forResource: "KDeck_KDeck", withExtension: "bundle"),
           let bundle = Bundle(url: bundleUrl),
           let url = bundle.url(forResource: "apps_config", withExtension: "json") {
            return url
        }

        // 3. Bundle kök dizini yanındaki KDeck_KDeck.bundle
        let directBundleUrl = Bundle.main.bundleURL.appendingPathComponent("KDeck_KDeck.bundle")
        if let bundle = Bundle(url: directBundleUrl),
           let url = bundle.url(forResource: "apps_config", withExtension: "json") {
            return url
        }

        // 4. Geliştirme ortamı (çalışma dizini altındaki Sources/KDeck/Resources)
        let devPath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/KDeck/Resources/apps_config.json")
        if FileManager.default.fileExists(atPath: devPath.path) {
            return devPath
        }

        return nil
    }

    /// Konfigürasyon dosyasını (apps_config.json) yükler
    public func loadConfig() {
        var loadedApps: [ManagedApp] = []

        // 1. Konfigürasyon dosyasından oku
        if let url = Self.findAppsConfigURL() {
            if let data = try? Data(contentsOf: url),
               let decoded = try? JSONDecoder().decode([ManagedApp].self, from: data) {
                loadedApps = decoded
            }
        }

        // 2. Eğer yüklenemezse dahili varsayılanları kullan
        if loadedApps.isEmpty {
            loadedApps = Self.defaultApps
        }

        self.apps = loadedApps
        for app in loadedApps {
            statuses[app.id] = .unknown
        }
    }

    /// Tüm uygulamaların durumunu ve güncellemelerini eşzamanlı denetler
    public func refreshAll() async {
        guard !isRefreshingAll else { return }
        isRefreshingAll = true
        defer { isRefreshingAll = false }

        await withTaskGroup(of: Void.self) { group in
            for app in apps {
                group.addTask {
                    await self.checkStatus(for: app)
                }
            }
            group.addTask { await self.checkSelfUpdate() }
        }
    }

    /// k-deck kendi sürümünü GitHub'daki son sürümle karşılaştırır ve yenisi varsa
    /// kullanıcıyı bilgilendirir.
    ///
    /// **Neden kurmuyor da yalnızca haber veriyor:** k-deck kurulum akışında hedef
    /// uygulamayı önce kapatıyor (`LocalAppScannerService.terminateIfRunning`, gerekirse
    /// `forceTerminate`). Kendini o listeye koysaydı kurulumun ortasında kendini
    /// öldürürdü. Çalışan bir `.app`'i yerinde değiştirmek ayrıca ayrı bir yardımcı süreç
    /// gerektirir. Bu yüzden k-deck `apps_config.json`'da yer almaz; keşif sorununu
    /// çözmek için sürüm karşılaştırması burada yapılır, indirme kullanıcıya bırakılır.
    public func checkSelfUpdate() async {
        guard !selfUpdateChecked else { return }
        selfUpdateChecked = true

        // Paketlenmemiş geliştirme çalıştırmasında (`swift run`) Info.plist yoktur —
        // geliştiriciyi rahatsız etme.
        guard let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              !current.isEmpty else { return }

        let token = githubToken.isEmpty ? nil : githubToken
        guard let release = try? await GitHubUpdateService.shared.fetchLatestRelease(
                owner: Self.selfOwner, repo: Self.selfRepo, token: token) else {
            return   // çevrimdışı ya da limit dolu: sessiz kal, uyarı üretme
        }

        let latest = release.cleanVersion
        guard Self.shouldNotifySelfUpdate(current: current, latest: latest) else { return }
        guard let url = URL(string: "https://github.com/\(Self.selfOwner)/\(Self.selfRepo)/releases/latest") else { return }

        selfUpdate = SelfUpdateInfo(currentVersion: current, latestVersion: latest, releasesURL: url)
    }

    /// Bildirim gösterilmeli mi? Saf karar — ağdan ve `Bundle`'dan bağımsız olduğu için
    /// test edilebilir. Boş/bozuk sürüm dizeleri `SemVer` tarafından 0.0.0'a indirgendiği
    /// için burada ayrıca elenir; aksi halde sürümü okunamayan bir paket her açılışta
    /// "güncelleme var" derdi.
    nonisolated static func shouldNotifySelfUpdate(current: String, latest: String) -> Bool {
        let c = current.trimmingCharacters(in: .whitespacesAndNewlines)
        let l = latest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !c.isEmpty, !l.isEmpty else { return false }
        return SemVer(l) > SemVer(c)
    }

    /// k-deck'in kendi deposu. Uygulamanın kimliği yapılandırmayla değişmemeli.
    private static let selfOwner = "erenkirkil"
    private static let selfRepo = "k-deck"

    /// Tek bir uygulamanın durumunu denetler
    public func checkStatus(for app: ManagedApp) async {
        statuses[app.id] = .checking

        // 1. Yerel kurulumu kontrol et
        let installedInfo = LocalAppScannerService.shared.scan(app: app)
        self.installedInfos[app.id] = installedInfo

        // 2. GitHub Release bilgisini al
        let token = githubToken.isEmpty ? nil : githubToken
        var latestRelease: GitHubRelease? = nil
        do {
            latestRelease = try await GitHubUpdateService.shared.fetchLatestRelease(
                owner: app.githubOwner,
                repo: app.githubRepo,
                token: token
            )
            self.releases[app.id] = latestRelease
        } catch {
            // GitHub hatası alındıysa ve yerelde kuruluysa en azından yüklü göster
            if let info = installedInfo {
                statuses[app.id] = .upToDate(installedVersion: info.version)
            } else {
                statuses[app.id] = .error(message: error.localizedDescription)
            }
            return
        }

        guard let release = latestRelease else {
            if let info = installedInfo {
                statuses[app.id] = .upToDate(installedVersion: info.version)
            } else {
                statuses[app.id] = .notInstalled(latestVersion: nil, asset: nil)
            }
            return
        }

        let macAsset = GitHubUpdateService.shared.selectMacAsset(from: release, for: app)

        if let info = installedInfo {
            let localSemVer = SemVer(info.version)
            let remoteSemVer = SemVer(release.cleanVersion)

            if remoteSemVer > localSemVer, let asset = macAsset {
                statuses[app.id] = .updateAvailable(
                    installedVersion: info.version,
                    latestVersion: release.cleanVersion,
                    asset: asset
                )
            } else {
                statuses[app.id] = .upToDate(installedVersion: info.version)
            }
        } else {
            statuses[app.id] = .notInstalled(
                latestVersion: release.cleanVersion,
                asset: macAsset
            )
        }
    }

    /// Uygulamayı indirir ve kurar / günceller
    public func installOrUpdate(app: ManagedApp) async {
        guard let status = statuses[app.id] else { return }

        var targetAsset: GitHubAsset? = nil
        switch status {
        case .notInstalled(_, let asset):
            targetAsset = asset
        case .updateAvailable(_, _, let asset):
            targetAsset = asset
        case .error:
            if let release = releases[app.id] {
                targetAsset = GitHubUpdateService.shared.selectMacAsset(from: release, for: app)
            }
        default:
            break
        }

        guard let asset = targetAsset else {
            statuses[app.id] = .error(message: "Kurulacak uygun macOS paketi bulunamadı.")
            return
        }

        statuses[app.id] = .downloading(progress: 0.0, text: "İndirme başlıyor...")

        do {
            try await BackgroundInstallerService.shared.installOrUpdate(
                app: app,
                asset: asset,
                onProgress: { [weak self] progress, text in
                    Task { @MainActor in
                        self?.statuses[app.id] = .downloading(progress: progress, text: text)
                    }
                },
                onStep: { [weak self] step in
                    Task { @MainActor in
                        self?.statuses[app.id] = .installing(step: step)
                    }
                }
            )

            // Kurulum sonrası durumu yeniden tara
            await checkStatus(for: app)
        } catch {
            statuses[app.id] = .error(message: error.localizedDescription)
        }
    }

    /// Uygulamayı başlatır
    public func launchApp(app: ManagedApp) {
        if let info = installedInfos[app.id] {
            LocalAppScannerService.shared.launchApp(at: info.path)
        } else {
            let defaultUrl = URL(fileURLWithPath: "/Applications").appendingPathComponent(app.appFileName)
            LocalAppScannerService.shared.launchApp(at: defaultUrl)
        }
    }

    /// Uygulamayı Finder'da gösterir
    public func revealInFinder(app: ManagedApp) {
        if let info = installedInfos[app.id] {
            LocalAppScannerService.shared.revealInFinder(at: info.path)
        }
    }

    // MARK: - Filtreleme ve İstatistikler
    public var filteredApps: [ManagedApp] {
        apps.filter { app in
            // Arama filtresi
            if !searchText.isEmpty {
                let match = app.name.localizedCaseInsensitiveContains(searchText) ||
                            app.displayName.localizedCaseInsensitiveContains(searchText) ||
                            app.description.localizedCaseInsensitiveContains(searchText) ||
                            app.category.localizedCaseInsensitiveContains(searchText)
                if !match { return false }
            }

            // Durum filtresi
            let status = statuses[app.id] ?? .unknown
            switch selectedFilter {
            case .all:
                return true
            case .installed:
                if case .upToDate = status { return true }
                if case .updateAvailable = status { return true }
                return false
            case .updates:
                if case .updateAvailable = status { return true }
                return false
            case .notInstalled:
                if case .notInstalled = status { return true }
                return false
            }
        }
    }

    public var installedCount: Int {
        apps.filter {
            if let status = statuses[$0.id] {
                if case .upToDate = status { return true }
                if case .updateAvailable = status { return true }
            }
            return false
        }.count
    }

    public var updateAvailableCount: Int {
        apps.filter {
            if let status = statuses[$0.id], case .updateAvailable = status { return true }
            return false
        }.count
    }

    // MARK: - Sabit Varsayılanlar (JSON bulunamazsa güvenlik önlemi)
    public static let defaultApps: [ManagedApp] = [
        ManagedApp(
            id: "closetoquit",
            name: "CloseToQuit",
            displayName: "CloseToQuit",
            description: "Kapatılan pencerelerin arka planda kalmasını önler ve otomatik çıkış (Quit) yapar.",
            githubOwner: "erenkirkil",
            githubRepo: "CloseToQuit",
            appFileName: "CloseToQuit.app",
            bundleIdentifier: "com.erenkirkil.CloseToQuit",
            assetPattern: ".*\\.dmg$",
            isMultiplatform: false,
            category: "Sistem & Verimlilik",
            iconSymbol: "xmark.circle.fill"
        ),
        ManagedApp(
            id: "sclip",
            name: "sclip",
            displayName: "sclip Clipboard",
            description: "Hızlı, hafif ve modern pano (clipboard) yöneticisi (macOS & Windows).",
            githubOwner: "erenkirkil",
            githubRepo: "sclip",
            appFileName: "sclip.app",
            bundleIdentifier: "com.erenkirkil.sclip",
            assetPattern: ".*\\.dmg$",
            isMultiplatform: true,
            category: "Verimlilik",
            iconSymbol: "doc.on.clipboard.fill"
        ),
        ManagedApp(
            id: "docktoggle",
            name: "DockToggle",
            displayName: "DockToggle",
            description: "macOS Dock'unun görünürlüğünü tek tıkla gizleyip göstermeye yarayan araç.",
            githubOwner: "erenkirkil",
            githubRepo: "DockToggle",
            appFileName: "DockToggle.app",
            bundleIdentifier: "com.erenkirkil.DockToggle",
            assetPattern: ".*\\.dmg$",
            isMultiplatform: false,
            category: "Sistem & Arayüz",
            iconSymbol: "dock.rectangle"
        ),
        ManagedApp(
            id: "tiler",
            name: "Tiler",
            displayName: "Tiler Window Manager",
            description: "Pencereleri ekranınıza kolayca döşeyip düzenlemenizi sağlayan pencere yöneticisi.",
            githubOwner: "erenkirkil",
            githubRepo: "Tiler",
            appFileName: "Tiler.app",
            bundleIdentifier: "com.erenkirkil.Tiler",
            assetPattern: ".*\\.dmg$",
            isMultiplatform: false,
            category: "Pencere Yönetimi",
            iconSymbol: "rectangle.split.2x2.fill"
        ),
        ManagedApp(
            id: "zenbar",
            name: "ZenBar",
            displayName: "ZenBar",
            description: "Menü çubuğu ikonlarını gizleyip düzenleyen minimalist menü aracı.",
            githubOwner: "erenkirkil",
            githubRepo: "zenbar",
            appFileName: "ZenBar.app",
            bundleIdentifier: "com.erenkirkil.zenbar",
            assetPattern: ".*\\.dmg$",
            isMultiplatform: false,
            category: "Menü Çubuğu",
            iconSymbol: "menubar.rectangle"
        )
    ]
}
