import SwiftUI

public struct SettingsView: View {
    @ObservedObject var manager: AppManager
    @Environment(\.dismiss) private var dismiss
    @State private var tokenInput: String = ""
    @State private var isAdvancedExpanded: Bool = false

    public init(manager: AppManager) {
        self.manager = manager
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Başlık
            HStack {
                Text("Ayarlar")
                    .font(.headline)
                Spacer()
                Button("Kapat") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            Form {
                // Genel Bilgilendirme
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.green)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Hesap / Giriş Gerekmez")
                                .font(.system(size: 13, weight: .semibold))
                            Text("K-Deck içerisindeki tüm uygulamalar açık kaynaklıdır. Uygulamaları indirmek ve güncellemek için herhangi bir token girmeniz gerekmez.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Uygulama Listesi Yönetimi
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Uygulama Yapılandırması")
                                .font(.system(size: 13, weight: .semibold))
                            Text("apps_config.json dosyasını yeniden tarar ve depoları yeniler.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Yeniden Yükle") {
                            manager.loadConfig()
                            Task {
                                await manager.refreshAll()
                            }
                        }
                        .controlSize(.small)
                    }
                    .padding(.vertical, 2)
                }

                // Gelişmiş Ayarlar (Token - Sadece Geliştiriciler İçin)
                Section {
                    DisclosureGroup(isExpanded: $isAdvancedExpanded) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("GitHub API anonim isteklerde IP başına saatlik 60 istek sınırı uygular. Normal kullanımda bu limite ulaşılmaz. Yalnızca test amaçlı çok sık istek atıyorsanız veya özel repolar eklediyseniz token girebilirsiniz.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)

                            HStack(spacing: 8) {
                                SecureField("ghp_xxxxxxxxxxxx", text: $tokenInput)
                                    .textFieldStyle(.roundedBorder)
                                    .controlSize(.small)
                                    .frame(maxWidth: 240)

                                Button("Kaydet") {
                                    manager.githubToken = tokenInput
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)

                                if !manager.githubToken.isEmpty {
                                    Button("Sil") {
                                        tokenInput = ""
                                        manager.githubToken = ""
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }

                            if !manager.githubToken.isEmpty {
                                Label("Özel token aktif", systemImage: "checkmark.shield.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.green)
                            }
                        }
                        .padding(.top, 6)
                    } label: {
                        HStack {
                            Text("Gelişmiş Seçenekler")
                                .font(.system(size: 13, weight: .semibold))
                            Text("(Geliştiriciler İçin)")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }

                // Hakkında
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("K-Deck v1.0.0")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Eren Kırkıl macOS uygulamaları merkezi kurulum ve otomatik güncelleme aracı.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 2)
                }
            }
            .formStyle(.grouped)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .frame(minWidth: 460, minHeight: 340)
        .onAppear {
            tokenInput = manager.githubToken
            if !tokenInput.isEmpty {
                isAdvancedExpanded = true
            }
        }
    }
}
