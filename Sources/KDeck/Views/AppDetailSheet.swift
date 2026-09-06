import SwiftUI

public struct AppDetailSheet: View {
    public let app: ManagedApp
    public let release: GitHubRelease?
    public let installedInfo: InstalledAppInfo?
    @Environment(\.dismiss) private var dismiss

    public init(app: ManagedApp, release: GitHubRelease?, installedInfo: InstalledAppInfo?) {
        self.app = app
        self.release = release
        self.installedInfo = installedInfo
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 16) {
                Image(systemName: app.iconSymbol)
                    .font(.system(size: 38))
                    .foregroundColor(.accentColor)
                    .frame(width: 54, height: 54)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(app.displayName)
                            .font(.title2)
                            .fontWeight(.bold)

                        if app.isMultiplatform {
                            Text("macOS & Windows")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.purple.opacity(0.15))
                                .foregroundColor(.purple)
                                .clipShape(Capsule())
                        }
                    }

                    Text(app.githubOwner + "/" + app.githubRepo)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Kapat") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Açıklama
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Hakkında")
                            .font(.headline)
                        Text(app.description)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }

                    // Sistem ve Kurulum Bilgileri
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Sistem Bilgisi")
                            .font(.headline)

                        HStack {
                            Text("Yüklü Sürüm:")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(installedInfo?.version ?? "Yüklü Değil")
                                .fontWeight(.medium)
                        }

                        if let info = installedInfo {
                            HStack {
                                Text("Konum:")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(info.path.path)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }

                            HStack {
                                Text("Durum:")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(info.isRunning ? "Çalışıyor" : "Kapalı")
                                    .foregroundColor(info.isRunning ? .green : .secondary)
                            }
                        }
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    // En Son GitHub Sürüm Bilgileri
                    if let release = release {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("En Son Sürüm (\(release.tagName))")
                                    .font(.headline)
                                Spacer()
                                if !release.formattedDate.isEmpty {
                                    Text(release.formattedDate)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            if let body = release.body, !body.isEmpty {
                                Text("Sürüm Notları:")
                                    .font(.subheadline)
                                    .fontWeight(.medium)

                                Text(body)
                                    .font(.callout)
                                    .foregroundColor(.primary)
                                    .padding()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.secondary.opacity(0.04))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }

                            // Varlıklar
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Yayınlanan Dosyalar:")
                                    .font(.subheadline)
                                    .fontWeight(.medium)

                                ForEach(release.assets) { asset in
                                    HStack {
                                        Image(systemName: asset.name.hasSuffix(".dmg") ? "internaldrive.fill" : "doc.zipper")
                                            .foregroundColor(.blue)
                                        Text(asset.name)
                                            .font(.caption)
                                        Spacer()
                                        Text(asset.humanReadableSize)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    // Bağlantılar
                    HStack(spacing: 12) {
                        Link(destination: app.githubUrl) {
                            Label("GitHub Deposu", systemImage: "arrow.up.right.square")
                        }

                        Link(destination: app.githubReleasesUrl) {
                            Label("Tüm Sürümler", systemImage: "tag")
                        }
                    }
                    .font(.callout)
                }
                .padding()
            }
        }
        .frame(minWidth: 540, minHeight: 460)
    }
}
