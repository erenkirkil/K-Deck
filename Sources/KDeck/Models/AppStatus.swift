import Foundation

public enum AppStatus: Equatable, Sendable {
    case unknown
    case checking
    case notInstalled(latestVersion: String?, asset: GitHubAsset?)
    case upToDate(installedVersion: String)
    case updateAvailable(installedVersion: String, latestVersion: String, asset: GitHubAsset)
    case downloading(progress: Double, text: String)
    case installing(step: String)
    case error(message: String)

    public var isBusy: Bool {
        switch self {
        case .checking, .downloading, .installing:
            return true
        default:
            return false
        }
    }

    public var canInstall: Bool {
        switch self {
        case .notInstalled(_, let asset):
            return asset != nil
        default:
            return false
        }
    }

    public var canUpdate: Bool {
        switch self {
        case .updateAvailable:
            return true
        default:
            return false
        }
    }

    public var canLaunch: Bool {
        switch self {
        case .upToDate, .updateAvailable:
            return true
        default:
            return false
        }
    }
}
