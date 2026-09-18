import SwiftUI

public struct MainDashboardView: View {
    @State private var manager = AppManager.shared
    @State private var showSettings: Bool = false

    private let columns = [
        GridItem(.adaptive(minimum: 340, maximum: 500), spacing: 10)
    ]

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - Üst Araç Çubuğu / Başlık
            headerView

            Divider()

            // MARK: - Filtre ve Arama Çubuğu
            filterBarView
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // MARK: - Ana Uygulama Izgarası
            ScrollView {
                if manager.filteredApps.isEmpty {
                    emptyStateView
                        .padding(.top, 40)
                } else {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(manager.filteredApps) { app in
                            AppCardView(app: app, manager: manager)
                        }
                    }
                    .padding(14)
                }
            }

            Divider()

            // MARK: - Alt Bilgi Çubuğu
            footerView
        }
        .frame(minWidth: 700, minHeight: 460)
        .sheet(isPresented: $showSettings) {
            SettingsView(manager: manager)
        }
        .task {
            await manager.refreshAll()
        }
    }

    // MARK: - Header
    private var headerView: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 22))
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 1) {
                Text("K-Deck")
                    .font(.system(size: 16, weight: .bold))

                Text("Merkezi macOS Uygulama ve Güncelleme Yöneticisi")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Tümünü Güncelle / Denetle Butonu
            Button {
                Task {
                    await manager.refreshAll()
                }
            } label: {
                HStack(spacing: 5) {
                    if manager.isRefreshingAll {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 12))
                    }
                    Text("Tümünü Denetle")
                        .font(.system(size: 12))
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(manager.isRefreshingAll)

            // Ayarlar Butonu
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Ayarlar")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Filtre & Arama
    private var filterBarView: some View {
        HStack(spacing: 12) {
            // Arama Kutusu
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                TextField("Uygulama veya kategori ara...", text: $manager.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))

                if !manager.searchText.isEmpty {
                    Button {
                        manager.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            )
            .frame(maxWidth: 280)

            Spacer()

            // Segment Filtresi
            HStack(spacing: 8) {
                Text("Filtrele:")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .fixedSize()

                Picker("", selection: $manager.selectedFilter) {
                    Text("Tümü (\(manager.apps.count))").tag(AppManager.AppFilter.all)
                    Text("Yüklü (\(manager.installedCount))").tag(AppManager.AppFilter.installed)
                    Text("Güncelleme Var (\(manager.updateAvailableCount))").tag(AppManager.AppFilter.updates)
                    Text("Yüklü Olmayanlar").tag(AppManager.AppFilter.notInstalled)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    // MARK: - Boş Durum
    private var emptyStateView: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundColor(.secondary)

            Text("Sonuç Bulunamadı")
                .font(.system(size: 14, weight: .semibold))

            Text("Arama kriterinize veya seçili filtreye uygun uygulama yok.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            if !manager.searchText.isEmpty {
                Button("Aramayı Temizle") {
                    manager.searchText = ""
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    // MARK: - Footer
    private var footerView: some View {
        HStack {
            Text("\(manager.apps.count) Uygulama Takip Ediliyor")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Spacer()

            if manager.updateAvailableCount > 0 {
                Label("\(manager.updateAvailableCount) yeni güncelleme mevcut", systemImage: "sparkles")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.orange)
            } else {
                Label("Tüm sistem güncel", systemImage: "checkmark.circle")
                    .font(.system(size: 11))
                    .foregroundColor(.green)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
