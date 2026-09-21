import Foundation

public struct ManagedApp: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let displayName: String
    public let description: String
    public let githubOwner: String
    public let githubRepo: String
    public let appFileName: String
    public let bundleIdentifier: String?
    public let assetPattern: String
    public let isMultiplatform: Bool
    public let category: String
    public let iconSymbol: String
    /// Beklenen yayıncı Team ID'si. JSON'da yoksa `SignatureVerifier.defaultTeamID`
    /// kullanılır (Optional olduğu için mevcut apps_config.json'lar bozulmaz).
    public let expectedTeamID: String?

    public var githubUrl: URL {
        URL(string: "https://github.com/\(githubOwner)/\(githubRepo)")!
    }

    public var githubReleasesUrl: URL {
        URL(string: "https://github.com/\(githubOwner)/\(githubRepo)/releases")!
    }

    public init(
        id: String,
        name: String,
        displayName: String,
        description: String,
        githubOwner: String,
        githubRepo: String,
        appFileName: String,
        bundleIdentifier: String? = nil,
        assetPattern: String = ".*\\.dmg$",
        isMultiplatform: Bool = false,
        category: String = "Genel",
        iconSymbol: String = "app.badge",
        expectedTeamID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.description = description
        self.githubOwner = githubOwner
        self.githubRepo = githubRepo
        self.appFileName = appFileName
        self.bundleIdentifier = bundleIdentifier
        self.assetPattern = assetPattern
        self.isMultiplatform = isMultiplatform
        self.category = category
        self.iconSymbol = iconSymbol
        self.expectedTeamID = expectedTeamID
    }
}
