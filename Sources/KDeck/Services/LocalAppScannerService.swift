import Foundation
import AppKit

public struct InstalledAppInfo: Sendable {
    public let path: URL
    public let version: String
    public let isRunning: Bool
}

@MainActor
public final class LocalAppScannerService: Sendable {
    public static let shared = LocalAppScannerService()

    private let standardAppDirs: [URL] = [
        URL(fileURLWithPath: "/Applications"),
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
    ]

    /// Belirtilen uygulamanın sistemde kurulu olup olmadığını ve sürümünü tespit eder
    public func scan(app: ManagedApp) -> InstalledAppInfo? {
        for dir in standardAppDirs {
            let candidateUrl = dir.appendingPathComponent(app.appFileName)
            var isDir: ObjCBool = false

            if FileManager.default.fileExists(atPath: candidateUrl.path, isDirectory: &isDir), isDir.boolValue {
                // Info.plist oku
                let infoPlistUrl = candidateUrl.appendingPathComponent("Contents/Info.plist")
                guard let plistData = try? Data(contentsOf: infoPlistUrl),
                      let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else {
                    // Info.plist okunamasa da dosya var
                    return InstalledAppInfo(path: candidateUrl, version: "0.0.0", isRunning: checkIfRunning(app: app, path: candidateUrl))
                }

                let shortVersion = plist["CFBundleShortVersionString"] as? String
                let bundleVersion = plist["CFBundleVersion"] as? String
                let version = shortVersion ?? bundleVersion ?? "1.0.0"

                let running = checkIfRunning(app: app, path: candidateUrl)
                return InstalledAppInfo(path: candidateUrl, version: version, isRunning: running)
            }
        }
        return nil
    }

    /// Uygulamanın o anda açık olup olmadığını kontrol eder
    public func checkIfRunning(app: ManagedApp, path: URL? = nil) -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications
        for running in runningApps {
            if let bundleId = app.bundleIdentifier, running.bundleIdentifier == bundleId {
                return true
            }
            if let exeUrl = running.bundleURL, exeUrl.lastPathComponent.lowercased() == app.appFileName.lowercased() {
                return true
            }
        }
        return false
    }

    /// Uygulamayı başlatır
    public func launchApp(at url: URL) {
        NSWorkspace.shared.open(url)
    }

    /// Finder'da gösterir
    public func revealInFinder(at url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Güncelleme öncesi çalışan uygulamayı sonlandırma isteği
    public func terminateIfRunning(app: ManagedApp) async -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications
        for running in runningApps {
            if (app.bundleIdentifier != nil && running.bundleIdentifier == app.bundleIdentifier) ||
               (running.bundleURL?.lastPathComponent.lowercased() == app.appFileName.lowercased()) {
                let success = running.terminate()
                if !success {
                    // Zorla kapat
                    running.forceTerminate()
                }
                // Kısa bir bekleme
                try? await Task.sleep(nanoseconds: 500_000_000)
                return true
            }
        }
        return false
    }
}
