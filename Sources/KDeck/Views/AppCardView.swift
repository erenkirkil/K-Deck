import SwiftUI

public struct AppCardView: View {
    public let app: ManagedApp
    let manager: AppManager
    @State private var showDetails: Bool = false

    public init(app: ManagedApp, manager: AppManager) {
        self.app = app
        self.manager = manager
    }

    private var status: AppStatus {
        manager.statuses[app.id] ?? .unknown
    }

    private var installedInfo: InstalledAppInfo? {
        manager.installedInfos[app.id]
    }

    private var release: GitHubRelease? {
        manager.releases[app.id]
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Üst Satır: İkon, Başlık, Rozetler
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: app.iconSymbol)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.accentColor)
                    .frame(width: 34, height: 34)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(app.displayName)
                            .font(.system(size: 14, weight: .semibold))

                        if app.isMultiplatform {
                            Text("macOS & Win")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Color.purple.opacity(0.15))
                                .foregroundColor(.purple)
                                .clipShape(Capsule())
                        }
                    }

                    HStack(spacing: 4) {
                        Text(app.category)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        Text("•")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        Text(app.githubOwner + "/" + app.githubRepo)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                StatusBadgeView(status: status)
            }

            // Açıklama
            Text(app.description)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            // İndirme veya Yükleme İlerlemesi
            if case .downloading(let progress, let text) = status {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                    Text(text)
                        .font(.system(size: 10))
                        .foregroundColor(.blue)
                }
                .transition(.opacity)
            } else if case .installing(let step) = status {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.65)
                        .frame(width: 12, height: 12)
                    Text(step)
                        .font(.system(size: 11))
                        .foregroundColor(.purple)
                }
                .transition(.opacity)
            }

            Divider()
                .padding(.vertical, -2)

            // Alt Satır: Sürüm Detayları ve Aksiyon Butonları
            HStack(alignment: .center) {
                // Sürüm Özeti
                HStack(spacing: 8) {
                    if let info = installedInfo {
                        Text("Yüklü: v\(info.version)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    } else {
                        Text("Yüklü değil")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    if let release = release {
                        Text("•  En son: \(release.tagName)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                }

                Spacer()

                // Detay Butonu
                Button {
                    showDetails = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("Sürüm Notları ve Detaylar")

                // Diğer İşlemler Menüsü
                Menu {
                    Button("Yeniden Tara") {
                        Task { await manager.checkStatus(for: app) }
                    }

                    if installedInfo != nil {
                        Button("Finder'da Göster") {
                            manager.revealInFinder(app: app)
                        }
                    }

                    Divider()

                    Link("GitHub Deposunu Aç", destination: app.githubUrl)
                    Link("GitHub Sürümlerini Aç", destination: app.githubReleasesUrl)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .frame(width: 22, height: 22)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Diğer Seçenekler")

                // Ana Aksiyon Butonu
                actionButton
            }
        }
        .padding(11)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.02), radius: 3, x: 0, y: 1)
        .sheet(isPresented: $showDetails) {
            AppDetailSheet(app: app, release: release, installedInfo: installedInfo)
        }
    }

    // MARK: - Duruma Göre Aksiyon Butonu
    @ViewBuilder
    private var actionButton: some View {
        switch status {
        case .unknown, .checking:
            Button("Kontrol...") {}
                .disabled(true)
                .controlSize(.small)

        case .notInstalled(_, let asset):
            Button {
                Task { await manager.installOrUpdate(app: app) }
            } label: {
                Label("Yükle", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(asset == nil)

        case .upToDate:
            Button {
                manager.launchApp(app: app)
            } label: {
                Label("Aç", systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

        case .updateAvailable(_, let latest, _):
            Button {
                Task { await manager.installOrUpdate(app: app) }
            } label: {
                Label("Güncelle (v\(latest))", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .controlSize(.small)

        case .downloading, .installing:
            Button("İşleniyor...") {}
                .disabled(true)
                .controlSize(.small)

        case .error:
            Button {
                Task { await manager.installOrUpdate(app: app) }
            } label: {
                Label("Tekrar Dene", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}
