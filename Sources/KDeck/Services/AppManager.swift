import Foundation
import SwiftUI
import Combine

@MainActor
public final class AppManager: ObservableObject {
    public static let shared = AppManager()

    @Published public var apps: [ManagedApp] = []
    @Published public var statuses: [String: AppStatus] = [:]
    @Published public var releases: [String: GitHubRelease] = [:]
    @Published public var installedInfos: [String: InstalledAppInfo] = [:]
    @Published public var isRefreshingAll: Bool = false
    @Published public var selectedFilter: AppFilter = .all
    @Published public var searchText: String = ""

    // Ayarlar
    @Published public var githubToken: String {
        didSet {
            UserDefaults.standard.set(githubToken, forKey: "kirkil_github_token")
        }
    }

    public enum AppFilter: String, CaseIterable, Identifiable {
        case all = "Tümü"
        case installed = "Yüklü Olanlar"
        case updates = "Güncelleme Var"
        case notInstalled = "Yüklü Olmayanlar"

        public var id: String { rawValue }
    }

    public init() {
        self.githubToken = UserDefaults.standard.string(forKey: "kirkil_github_token") ?? ""
        loadConfig()
    }

    /// Konfigürasyon dosyasını (apps_config.json) yükler
    public func loadConfig() {
        var loadedApps: [ManagedApp] = []

        // 1. Bundle modülü içinden oku
        if let url = Bundle.module.url(forResource: "apps_config", withExtension: "json") {
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
        }
    }

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
