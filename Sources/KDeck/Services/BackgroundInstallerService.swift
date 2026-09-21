import Foundation

public actor BackgroundInstallerService {
    public static let shared = BackgroundInstallerService()

    public enum InstallError: LocalizedError {
        case downloadFailed(String)
        case dmgMountFailed(String)
        case appNotFoundInPackage
        case copyFailed(String)
        case detachFailed(String)
        case verificationFailed(String)
        case ambiguousPackage(String)

        public var errorDescription: String? {
            switch self {
            case .downloadFailed(let msg): return "İndirme başarısız: \(msg)"
            case .dmgMountFailed(let msg): return "DMG imajı açılamadı: \(msg)"
            case .appNotFoundInPackage: return "Paket içeriğinde .app uygulaması bulunamadı."
            case .copyFailed(let msg): return "Uygulama /Applications dizinine kopyalanamadı: \(msg)"
            case .detachFailed(let msg): return "Sanal disk bağlantısı kesilemedi: \(msg)"
            case .verificationFailed(let msg): return "Güvenlik doğrulaması başarısız: \(msg)"
            case .ambiguousPackage(let msg): return "Paket içeriği beklenenle uyuşmuyor: \(msg)"
            }
        }
    }

    /// Arşiv/imaj içinden kurulacak `.app`'i seçer.
    ///
    /// Eskiden beklenen isim yoksa "bulunan ilk .app" alınıp hedefe *beklenen adla*
    /// kopyalanıyordu — yani içeriği bambaşka bir paket doğru isimle kurulabiliyordu.
    /// Artık yalnızca tam ad eşleşmesi kabul edilir; ad tutmuyorsa ve pakette tek bir
    /// .app varsa o aday olarak alınır ama imza doğrulaması bundle kimliğini zaten
    /// karşılaştıracağı için yanlış paket orada elenir.
    private func locateApp(in directory: URL, expecting app: ManagedApp) throws -> URL {
        let exact = directory.appendingPathComponent(app.appFileName)
        if FileManager.default.fileExists(atPath: exact.path) {
            return exact
        }
        let candidates = ((try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension.lowercased() == "app" }

        guard let only = candidates.first, candidates.count == 1 else {
            if candidates.isEmpty { throw InstallError.appNotFoundInPackage }
            throw InstallError.ambiguousPackage(
                "\(app.appFileName) bulunamadı; pakette \(candidates.count) farklı .app var.")
        }
        return only
    }

    /// Kopyalamadan önce imzayı, Gatekeeper değerlendirmesini ve yayıncı kimliğini denetler.
    private func verify(_ appURL: URL, against app: ManagedApp) async throws {
        do {
            try await SignatureVerifier.verify(
                appAt: appURL,
                expectedTeamID: app.expectedTeamID ?? SignatureVerifier.defaultTeamID,
                expectedBundleID: app.bundleIdentifier)
        } catch {
            throw InstallError.verificationFailed(error.localizedDescription)
        }
    }

    /// İndirme ve yükleme işlemini sırasıyla icra eder
    public func installOrUpdate(
        app: ManagedApp,
        asset: GitHubAsset,
        destinationDir: URL = URL(fileURLWithPath: "/Applications"),
        onProgress: @Sendable @escaping (Double, String) -> Void,
        onStep: @Sendable @escaping (String) -> Void
    ) async throws {
        onStep("İndirme hazırlanıyor...")

        // 1. Geçici indirme konumu
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("kirkil_install_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let targetDownloadUrl = tempDir.appendingPathComponent(asset.name)

        // 2. İndirme (URLSession ile ilerleme takibi)
        try await downloadFile(from: asset.browserDownloadUrl, to: targetDownloadUrl, onProgress: onProgress)

        // 3. Çalışıyorsa uygulamayı nazikçe kapat
        onStep("Eski oturum kontrol ediliyor...")
        _ = await LocalAppScannerService.shared.terminateIfRunning(app: app)

        let lowerName = asset.name.lowercased()
        if lowerName.hasSuffix(".dmg") {
            try await installFromDMG(
                dmgPath: targetDownloadUrl,
                app: app,
                destinationDir: destinationDir,
                onStep: onStep
            )
        } else if lowerName.hasSuffix(".zip") {
            try await installFromZip(
                zipPath: targetDownloadUrl,
                app: app,
                destinationDir: destinationDir,
                onStep: onStep
            )
        } else {
            throw InstallError.downloadFailed("Desteklenmeyen paket türü: \(asset.name)")
        }

        // 4. Karantina bayrağını temizle.
        //
        // Bu satır daha önce HİÇBİR doğrulama yapılmadan çalışıyordu ve Gatekeeper'ın
        // ilk açılış denetimini kaldırdığı için kurcalanmış bir sürümü yakalayacak tek
        // kontrolü yok ediyordu. Artık yalnızca imza + Gatekeeper + Team ID denetiminin
        // üçü de geçtikten sonra buraya ulaşılır: denetimi kendimiz yaptığımız için
        // bayrağı kaldırmak güvenlidir ve kullanıcı gereksiz bir diyalog görmez.
        onStep("Karantina bayrağı kaldırılıyor...")
        let finalAppUrl = destinationDir.appendingPathComponent(app.appFileName)
        _ = try? await ShellCommand.run("/usr/bin/xattr", arguments: ["-cr", finalAppUrl.path])

        // 5. Geçici indirme klasörünü temizle
        try? FileManager.default.removeItem(at: tempDir)

        onStep("Kurulum tamamlandı!")
    }

    // MARK: - İndirme Yardımcısı
    private func downloadFile(
        from urlString: String,
        to destination: URL,
        onProgress: @Sendable @escaping (Double, String) -> Void
    ) async throws {
        guard let url = URL(string: urlString) else {
            throw InstallError.downloadFailed("Geçersiz URL: \(urlString)")
        }

        let delegate = DownloadProgressDelegate(destination: destination, onProgress: onProgress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let downloadTask = session.downloadTask(with: url)
        downloadTask.resume()

        try await delegate.waitForCompletion()
    }

    // MARK: - DMG Kurulumu
    private func installFromDMG(
        dmgPath: URL,
        app: ManagedApp,
        destinationDir: URL,
        onStep: @Sendable @escaping (String) -> Void
    ) async throws {
        let mountPoint = FileManager.default.temporaryDirectory.appendingPathComponent("kirkil_mount_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)

        onStep("DMG imajı bağlanıyor...")
        let attachResult = try await ShellCommand.run("/usr/bin/hdiutil", arguments: [
            "attach",
            dmgPath.path,
            "-nobrowse",
            "-quiet",
            "-mountpoint",
            mountPoint.path
        ])

        guard attachResult.isSuccess else {
            try? FileManager.default.removeItem(at: mountPoint)
            throw InstallError.dmgMountFailed(attachResult.stderr)
        }

        defer {
            // Unmount işlemi her durumda çağrılır
            Task {
                _ = try? await ShellCommand.run("/usr/bin/hdiutil", arguments: ["detach", mountPoint.path, "-force", "-quiet"])
                try? FileManager.default.removeItem(at: mountPoint)
            }
        }

        onStep("Uygulama paketi taranıyor...")
        let foundApp = try locateApp(in: mountPoint, expecting: app)

        // Kopyalamadan ÖNCE doğrula — bağlı imajdaki paket üzerinde.
        onStep("İmza ve yayıncı kimliği doğrulanıyor...")
        try await verify(foundApp, against: app)

        onStep("Uygulama /Applications klasörüne yerleştiriliyor...")
        let destinationAppUrl = destinationDir.appendingPathComponent(app.appFileName)

        // ditto komutu macOS'ta .app bundle'larını atomic ve izinleri koruyarak kopyalamanın en güvenli yoludur
        let copyResult = try await ShellCommand.run("/usr/bin/ditto", arguments: [
            foundApp.path,
            destinationAppUrl.path
        ])

        guard copyResult.isSuccess else {
            throw InstallError.copyFailed(copyResult.stderr)
        }
    }

    // MARK: - ZIP Kurulumu
    private func installFromZip(
        zipPath: URL,
        app: ManagedApp,
        destinationDir: URL,
        onStep: @Sendable @escaping (String) -> Void
    ) async throws {
        let extractDir = FileManager.default.temporaryDirectory.appendingPathComponent("kirkil_zip_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: extractDir)
        }

        onStep("Arşiv çıkartılıyor...")
        let unzipResult = try await ShellCommand.run("/usr/bin/ditto", arguments: [
            "-xk",
            zipPath.path,
            extractDir.path
        ])

        guard unzipResult.isSuccess else {
            throw InstallError.copyFailed("Zip açılamadı: \(unzipResult.stderr)")
        }

        onStep("Uygulama bulunuyor...")
        let foundApp = try locateApp(in: extractDir, expecting: app)

        onStep("İmza ve yayıncı kimliği doğrulanıyor...")
        try await verify(foundApp, against: app)

        onStep("Uygulama /Applications klasörüne yerleştiriliyor...")
        let destinationAppUrl = destinationDir.appendingPathComponent(app.appFileName)

        let copyResult = try await ShellCommand.run("/usr/bin/ditto", arguments: [
            foundApp.path,
            destinationAppUrl.path
        ])

        guard copyResult.isSuccess else {
            throw InstallError.copyFailed(copyResult.stderr)
        }
    }
}

// MARK: - URLSession Download Delegate
private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let onProgress: @Sendable (Double, String) -> Void
    private var continuation: CheckedContinuation<Void, Error>?

    init(destination: URL, onProgress: @Sendable @escaping (Double, String) -> Void) {
        self.destination = destination
        self.onProgress = onProgress
    }

    func waitForCompletion() async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 {
            let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            let currentMB = Double(totalBytesWritten) / (1024 * 1024)
            let totalMB = Double(totalBytesExpectedToWrite) / (1024 * 1024)
            let text = String(format: "İndiriliyor: %%%.0f (%.1f / %.1f MB)", progress * 100, currentMB, totalMB)
            onProgress(progress, text)
        } else {
            let currentMB = Double(totalBytesWritten) / (1024 * 1024)
            let text = String(format: "İndiriliyor: %.1f MB", currentMB)
            onProgress(0.5, text)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            continuation?.resume()
            continuation = nil
        } catch {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}
