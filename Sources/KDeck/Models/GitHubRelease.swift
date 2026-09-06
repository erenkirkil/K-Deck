import Foundation

public struct GitHubAsset: Codable, Identifiable, Equatable, Sendable {
    public let id: Int
    public let name: String
    public let size: Int
    public let contentType: String?
    public let browserDownloadUrl: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case size
        case contentType = "content_type"
        case browserDownloadUrl = "browser_download_url"
    }

    public var humanReadableSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }
}

public struct GitHubRelease: Codable, Identifiable, Equatable, Sendable {
    public let id: Int
    public let tagName: String
    public let name: String?
    public let body: String?
    public let htmlUrl: String
    public let publishedAt: String?
    public let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case id
        case tagName = "tag_name"
        case name
        case body
        case htmlUrl = "html_url"
        case publishedAt = "published_at"
        case assets
    }

    public var cleanVersion: String {
        if tagName.lowercased().hasPrefix("v") {
            return String(tagName.dropFirst())
        }
        return tagName
    }

    public var formattedDate: String {
        guard let publishedAt else { return "" }
        let isoFormatter = ISO8601DateFormatter()
        if let date = isoFormatter.date(from: publishedAt) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .medium
            displayFormatter.timeStyle = .none
            displayFormatter.locale = Locale(identifier: "tr_TR")
            return displayFormatter.string(from: date)
        }
        return publishedAt
    }
}
