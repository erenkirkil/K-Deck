import SwiftUI

public struct StatusBadgeView: View {
    public let status: AppStatus

    public init(status: AppStatus) {
        self.status = status
    }

    public var body: some View {
        HStack(spacing: 3) {
            switch status {
            case .unknown:
                Label("Bilinmiyor", systemImage: "questionmark.circle")
                    .foregroundColor(.secondary)
            case .checking:
                Label("Kontrol...", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundColor(.blue)
            case .notInstalled:
                Label("Yüklü Değil", systemImage: "arrow.down.circle")
                    .foregroundColor(.secondary)
            case .upToDate(let version):
                Label("Güncel (v\(version))", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
            case .updateAvailable(_, let latest, _):
                Label("Güncelleme (v\(latest))", systemImage: "arrow.up.circle.fill")
                    .foregroundColor(.orange)
            case .downloading(_, let text):
                Label(text, systemImage: "arrow.down.circle.fill")
                    .foregroundColor(.blue)
            case .installing(let step):
                Label(step, systemImage: "gearshape.arrow.triangle.2.circlepath")
                    .foregroundColor(.purple)
            case .error(let message):
                Label("Hata: \(message)", systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
            }
        }
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(badgeBackground)
        .clipShape(Capsule())
    }

    @ViewBuilder
    private var badgeBackground: some View {
        switch status {
        case .unknown:
            Color.secondary.opacity(0.12)
        case .checking:
            Color.blue.opacity(0.12)
        case .notInstalled:
            Color.secondary.opacity(0.12)
        case .upToDate:
            Color.green.opacity(0.14)
        case .updateAvailable:
            Color.orange.opacity(0.15)
        case .downloading:
            Color.blue.opacity(0.14)
        case .installing:
            Color.purple.opacity(0.14)
        case .error:
            Color.red.opacity(0.14)
        }
    }
}
