import XCTest
@testable import KDeck

/// Saf mantık testleri. Kurulum akışının kendisi (indirme, hdiutil, ditto) yan etkili
/// olduğu için test edilmiyor; test edilen şey o akışın *güvenlik kararlarını* veren
/// iki saf fonksiyon: imza alanı ayrıştırma ve sürüm karşılaştırma.
final class SignatureVerifierTests: XCTestCase {

    /// `codesign -dv --verbose=4` çıktısının gerçek biçimi (bu makinede doğrulandı).
    private let realOutput = """
    Executable=/Applications/Claude.app/Contents/MacOS/Claude
    Identifier=com.anthropic.claudefordesktop
    Format=app bundle with Mach-O universal (x86_64 arm64)
    CodeDirectory v=20500 size=1234 flags=0x10000(runtime) hashes=12+7
    TeamIdentifier=Q6L2SF6YDW
    Sealed Resources version=2 rules=13 files=42
    """

    func testReadsTeamIdentifier() {
        XCTAssertEqual(SignatureVerifier.field("TeamIdentifier", in: realOutput), "Q6L2SF6YDW")
    }

    func testReadsBundleIdentifier() {
        XCTAssertEqual(SignatureVerifier.field("Identifier", in: realOutput),
                       "com.anthropic.claudefordesktop")
    }

    /// "Identifier" ararken "TeamIdentifier" satırına düşmemeli — satır başına çapalı.
    func testIdentifierDoesNotMatchTeamIdentifierLine() {
        let output = "TeamIdentifier=AAAA\nIdentifier=com.example.app"
        XCTAssertEqual(SignatureVerifier.field("Identifier", in: output), "com.example.app")
    }

    /// Apple'ın kendi uygulamalarında Team ID "not set" gelir — nil sayılmalı ki
    /// doğrulama sessizce geçmesin.
    func testNotSetIsTreatedAsMissing() {
        XCTAssertNil(SignatureVerifier.field("TeamIdentifier", in: "TeamIdentifier=not set"))
    }

    func testMissingFieldIsNil() {
        XCTAssertNil(SignatureVerifier.field("TeamIdentifier", in: "Identifier=com.example.app"))
    }
}

final class SemVerTests: XCTestCase {

    func testBasicOrdering() {
        XCTAssertTrue(SemVer("1.0.0") < SemVer("1.0.1"))
        XCTAssertTrue(SemVer("1.0.0") < SemVer("1.1.0"))
        XCTAssertTrue(SemVer("1.9.0") < SemVer("2.0.0"))
    }

    func testVPrefixIgnored() {
        XCTAssertEqual(SemVer("v1.2.3"), SemVer("1.2.3"))
    }

    func testPrereleaseIsLessThanRelease() {
        XCTAssertTrue(SemVer("1.0.0-beta") < SemVer("1.0.0"))
    }

    /// Asıl düzeltme: sözlüksel karşılaştırma beta.10'u beta.9'dan küçük sayıyordu.
    func testNumericPrereleasePartsCompareNumerically() {
        XCTAssertTrue(SemVer("1.0.0-beta.9") < SemVer("1.0.0-beta.10"))
        XCTAssertFalse(SemVer("1.0.0-beta.10") < SemVer("1.0.0-beta.9"))
    }

    /// SemVer 2.0: sayısal tanımlayıcı alfanümerikten önce gelir.
    func testNumericSortsBeforeAlphanumeric() {
        XCTAssertTrue(SemVer("1.0.0-1") < SemVer("1.0.0-alpha"))
    }

    /// Ortak parçalar eşitse, daha az parçası olan küçüktür.
    func testShorterPrereleaseIsLess() {
        XCTAssertTrue(SemVer("1.0.0-alpha") < SemVer("1.0.0-alpha.1"))
    }

    func testEqualVersions() {
        XCTAssertEqual(SemVer("2.3.4"), SemVer("2.3.4"))
        XCTAssertFalse(SemVer("2.3.4") < SemVer("2.3.4"))
    }
}

/// İndirme adresi denetimi. Bu fonksiyon, imza doğrulamasından ÖNCE gelen ilk savunma
/// katmanı: URL doğrudan GitHub API yanıtından geldiği için şema ve host burada elenir.
final class DownloadURLTrustTests: XCTestCase {

    private func accepts(_ string: String) -> Bool {
        guard let url = URL(string: string) else { return false }
        return (try? BackgroundInstallerService.assertTrustedDownloadURL(url)) != nil
    }

    func testAcceptsGitHubReleaseAsset() {
        XCTAssertTrue(accepts("https://github.com/erenkirkil/ZenBar/releases/download/v1.2.0/ZenBar.dmg"))
    }

    func testAcceptsRedirectTargetHost() {
        XCTAssertTrue(accepts("https://objects.githubusercontent.com/github-production-release-asset/1/2"))
    }

    func testRejectsPlainHTTP() {
        XCTAssertFalse(accepts("http://github.com/erenkirkil/ZenBar/releases/download/v1.2.0/ZenBar.dmg"))
    }

    /// `file://` ile yerel bir dosya "indirilemez".
    func testRejectsFileScheme() {
        XCTAssertFalse(accepts("file:///etc/passwd"))
    }

    func testRejectsForeignHost() {
        XCTAssertFalse(accepts("https://evil.example.com/ZenBar.dmg"))
    }

    /// Host adı sonuna github.com eklenerek kandırılamamalı.
    func testRejectsLookalikeHost() {
        XCTAssertFalse(accepts("https://github.com.evil.example.com/ZenBar.dmg"))
        XCTAssertFalse(accepts("https://notgithub.com/ZenBar.dmg"))
    }

    func testHostMatchIsCaseInsensitive() {
        XCTAssertTrue(accepts("https://GitHub.com/erenkirkil/Tiler/releases/download/v1.0.0/Tiler.dmg"))
    }
}

/// k-deck'in kendi güncelleme bildirimi. Bildirim yalnızca gerçekten yeni bir sürüm
/// varken çıkmalı; yanlış pozitif, kullanıcıyı boşuna indirme sayfasına yollar.
final class SelfUpdateDecisionTests: XCTestCase {

    private func notifies(current: String, latest: String) -> Bool {
        AppManager.shouldNotifySelfUpdate(current: current, latest: latest)
    }

    func testNotifiesWhenNewerExists() {
        XCTAssertTrue(notifies(current: "1.2.0", latest: "1.3.0"))
        XCTAssertTrue(notifies(current: "1.2.0", latest: "2.0.0"))
    }

    func testSilentWhenUpToDate() {
        XCTAssertFalse(notifies(current: "1.2.0", latest: "1.2.0"))
    }

    /// Yerelde daha yeni bir derleme varken (geliştirici makinesi) uyarı çıkmamalı.
    func testSilentWhenLocalIsNewer() {
        XCTAssertFalse(notifies(current: "1.3.0", latest: "1.2.0"))
    }

    func testHandlesVPrefixedTag() {
        XCTAssertTrue(notifies(current: "1.2.0", latest: "v1.3.0"))
        XCTAssertFalse(notifies(current: "1.2.0", latest: "v1.2.0"))
    }

    /// Sürüm okunamadıysa sessiz kal — yoksa her açılışta yanlış uyarı verir.
    func testSilentOnUnreadableVersions() {
        XCTAssertFalse(notifies(current: "", latest: "1.3.0"))
        XCTAssertFalse(notifies(current: "1.2.0", latest: ""))
        XCTAssertFalse(notifies(current: "   ", latest: "1.3.0"))
    }

    /// Ön sürüm, yayınlanmış sürümden yeni sayılmamalı.
    func testPrereleaseIsNotNewerThanRelease() {
        XCTAssertFalse(notifies(current: "1.2.0", latest: "1.2.0-beta.1"))
    }
}

/// Yapılandırmadaki kimliklerin gerçek paketlerle tutarlılığı.
///
/// Gerçek bir hatadan doğdu: apps_config.json'daki `bundleIdentifier` değerlerinin
/// dördü yanlış harf biçimindeydi (`com.erenkirkil.Tiler` ↔ `com.erenkirkil.tiler`).
/// İmza doğrulaması bu alanı tam eşleşmeyle karşılaştırdığı için temiz bir sistemde
/// beş kurulumun dördü "paket kimliği uyuşmuyor" diyerek durdu.
final class AppsConfigIntegrityTests: XCTestCase {

    /// Depolardan doğrulanmış gerçek bundle kimlikleri.
    private let realBundleIDs = [
        "closetoquit": "com.erenkirkil.closetoquit",
        "docktoggle":  "com.erenkirkil.docktoggle",
        "tiler":       "com.erenkirkil.tiler",
        "zenbar":      "com.erenkirkil.ZenBar",
        "sclip":       "com.erenkirkil.sclip",
    ]

    private func loadConfig() throws -> [ManagedApp] {
        // Test paketinden değil, kaynak ağacındaki dosyadan oku: yayınlanan veri bu.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // KDeckTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // paket kökü
            .appendingPathComponent("Sources/KDeck/Resources/apps_config.json")
        return try JSONDecoder().decode([ManagedApp].self, from: Data(contentsOf: url))
    }

    func testConfigBundleIDsMatchRealApps() throws {
        for app in try loadConfig() {
            guard let expected = realBundleIDs[app.id] else {
                XCTFail("Testte karşılığı olmayan uygulama: \(app.id)")
                continue
            }
            XCTAssertEqual(app.bundleIdentifier, expected,
                           "\(app.id) için yapılandırmadaki bundle kimliği gerçek paketle uyuşmuyor")
        }
    }

    func testEveryAppDeclaresABundleID() throws {
        for app in try loadConfig() {
            XCTAssertNotNil(app.bundleIdentifier, "\(app.id) bundle kimliği tanımlamıyor")
            XCTAssertFalse(app.appFileName.isEmpty, "\(app.id) appFileName tanımlamıyor")
        }
    }
}
