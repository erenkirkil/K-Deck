import Foundation

public final class GitHubUpdateService: Sendable {
    public static let shared = GitHubUpdateService()

    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    /// GitHub'dan en güncel sürüm bilgisini çeker
    public func fetchLatestRelease(owner: String, repo: String, token: String? = nil) async throws -> GitHubRelease {
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("KDeck-macOS", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

        if let token = token?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        if httpResponse.statusCode == 404 {
            throw NSError(domain: "GitHubUpdateService", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "GitHub üzerinde bu repo için henüz yayınlanmış bir Release bulunamadı."
            ])
        }

        if httpResponse.statusCode == 403 {
            throw NSError(domain: "GitHubUpdateService", code: 403, userInfo: [
                NSLocalizedDescriptionKey: "GitHub API istek limiti doldu. Ayarlar bölümünden GitHub Personal Access Token ekleyebilirsiniz."
            ])
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "GitHubUpdateService", code: httpResponse.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "GitHub API Hatası: HTTP \(httpResponse.statusCode)"
            ])
        }

        let decoder = JSONDecoder()
        return try decoder.decode(GitHubRelease.self, from: data)
    }

    /// Bir uygulamanın release varlıkları arasından macOS için uygun olan asset'i seçer
    public func selectMacAsset(from release: GitHubRelease, for app: ManagedApp) -> GitHubAsset? {
        let assets = release.assets
        if assets.isEmpty { return nil }

        // 1. Önce app.assetPattern ile regex eşleşmesi dene
        if let regex = try? NSRegularExpression(pattern: app.assetPattern, options: .caseInsensitive) {
            for asset in assets {
                let range = NSRange(location: 0, length: asset.name.utf16.count)
                if regex.firstMatch(in: asset.name, options: [], range: range) != nil {
                    // Windows veya exe dosyası olmamalı
                    if !asset.name.lowercased().contains("windows") && !asset.name.hasSuffix(".exe") {
                        return asset
                    }
                }
            }
        }

        // 2. Regex bulunamazsa .dmg uzantılı ve 'windows' içermeyen ilk asset
        if let dmgAsset = assets.first(where: {
            $0.name.lowercased().hasSuffix(".dmg") && !$0.name.lowercased().contains("windows")
        }) {
            return dmgAsset
        }

        // 3. .dmg yoksa .zip uzantılı ve 'windows' içermeyen ilk asset
        if let zipAsset = assets.first(where: {
            $0.name.lowercased().hasSuffix(".zip") &&
            !$0.name.lowercased().contains("windows") &&
            !$0.name.lowercased().contains("win")
        }) {
            return zipAsset
        }

        return nil
    }
}
