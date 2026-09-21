import Foundation

/// İndirilen bir `.app` paketini `/Applications`'a kopyalamadan ÖNCE doğrular.
///
/// Neden gerekli: K-Deck, GitHub Release'ten indirdiği bir ikili dosyayı kullanıcının
/// sistemine kuran tek bileşendir. Daha önce hiçbir doğrulama yapılmadan kopyalanıyor,
/// üstüne `xattr -cr` ile karantina bayrağı siliniyordu — yani Gatekeeper'ın ilk açılış
/// denetimi de bilerek devre dışı bırakılıyordu. GitHub hesabı ele geçirilse ya da bir
/// release varlığı değiştirilse bunu yakalayacak hiçbir kontrol kalmıyordu.
///
/// Üç katman denetlenir:
///  1. `codesign --verify --deep --strict` — imza bütünlüğü (paket kurcalanmamış).
///  2. `spctl -a -t exec` — Gatekeeper değerlendirmesi (Developer ID + notarization).
///  3. Team ID ve bundle kimliği — paketin *beklenen yayıncıya* ait olduğu.
///
/// Üçü de geçmeden kurulum yapılmaz.
public enum SignatureVerifier: Sendable {

    /// Bu projelerin yayıncı Team ID'si. `apps_config.json` içinde `expectedTeamID`
    /// verilmişse o öncelenir.
    public static let defaultTeamID = "992XYS9346"

    public enum VerificationError: LocalizedError, Equatable {
        case codesignFailed(String)
        case gatekeeperRejected(String)
        case teamIDMismatch(expected: String, found: String?)
        case bundleIDMismatch(expected: String, found: String?)
        case metadataUnreadable

        public var errorDescription: String? {
            switch self {
            case .codesignFailed(let detail):
                return "İmza doğrulaması başarısız — paket kurcalanmış olabilir: \(detail)"
            case .gatekeeperRejected(let detail):
                return "Gatekeeper paketi reddetti (notarize edilmemiş veya bozuk): \(detail)"
            case .teamIDMismatch(let expected, let found):
                return "Yayıncı kimliği uyuşmuyor — beklenen \(expected), bulunan \(found ?? "yok"). Kurulum durduruldu."
            case .bundleIDMismatch(let expected, let found):
                return "Paket kimliği uyuşmuyor — beklenen \(expected), bulunan \(found ?? "yok"). Kurulum durduruldu."
            case .metadataUnreadable:
                return "Paketin imza bilgileri okunamadı. Kurulum durduruldu."
            }
        }
    }

    /// Doğrulamayı yürütür. Hata fırlatmadan dönerse paket kurulmaya uygundur.
    public static func verify(
        appAt url: URL,
        expectedTeamID: String,
        expectedBundleID: String?
    ) async throws {
        // 1. İmza bütünlüğü
        let codesignResult = try await ShellCommand.run("/usr/bin/codesign", arguments: [
            "--verify", "--deep", "--strict", url.path
        ])
        guard codesignResult.isSuccess else {
            throw VerificationError.codesignFailed(codesignResult.stderr.isEmpty
                ? "çıkış kodu \(codesignResult.exitCode)" : codesignResult.stderr)
        }

        // 2. Gatekeeper değerlendirmesi (Developer ID imzası + notarization bileti)
        let spctlResult = try await ShellCommand.run("/usr/sbin/spctl", arguments: [
            "-a", "-t", "exec", "-vv", url.path
        ])
        guard spctlResult.isSuccess else {
            throw VerificationError.gatekeeperRejected(spctlResult.stderr.isEmpty
                ? "çıkış kodu \(spctlResult.exitCode)" : spctlResult.stderr)
        }

        // 3. Yayıncı kimliği — imza geçerli olsa bile BAŞKA birinin geçerli imzası olabilir.
        let infoResult = try await ShellCommand.run("/usr/bin/codesign", arguments: [
            "-dv", "--verbose=4", url.path
        ])
        // codesign -dv ayrıntıları stderr'e yazar.
        let metadata = infoResult.stderr.isEmpty ? infoResult.stdout : infoResult.stderr
        guard !metadata.isEmpty else { throw VerificationError.metadataUnreadable }

        let foundTeamID = field("TeamIdentifier", in: metadata)
        // Team ID'yi Apple büyük harf atar; karşılaştırmayı harf duyarsız yapmak güvenliği
        // düşürmez ama yapılandırmadaki yazım farkının kurcalama sanılmasını önler.
        guard let team = foundTeamID,
              team.compare(expectedTeamID, options: .caseInsensitive) == .orderedSame else {
            throw VerificationError.teamIDMismatch(expected: expectedTeamID, found: foundTeamID)
        }

        if let expectedBundleID {
            let foundBundleID = field("Identifier", in: metadata)
            // Bundle kimlikleri macOS'ta harf duyarsızdır (LaunchServices ve CFBundle
            // karşılaştırmaları büyük/küçük harf ayırmaz), dolayısıyla yalnızca harf
            // biçiminde ayrılan iki kimlik AYNI kimliktir. Tam eşleşme aramak güvenliği
            // artırmıyor, yalnızca yapılandırmadaki yazım farkını kurcalama sanıyordu.
            guard let bundle = foundBundleID,
                  bundle.compare(expectedBundleID, options: .caseInsensitive) == .orderedSame else {
                throw VerificationError.bundleIDMismatch(expected: expectedBundleID, found: foundBundleID)
            }
        }
    }

    /// `codesign -dv` çıktısındaki `Anahtar=değer` satırından değeri okur.
    /// Satır başına çapalanır; "TeamIdentifier" ararken "OTeamIdentifier" eşleşmesin.
    static func field(_ key: String, in output: String) -> String? {
        for rawLine in output.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix(key + "=") else { continue }
            let value = String(line.dropFirst(key.count + 1)).trimmingCharacters(in: .whitespaces)
            return value.isEmpty || value == "not set" ? nil : value
        }
        return nil
    }
}
