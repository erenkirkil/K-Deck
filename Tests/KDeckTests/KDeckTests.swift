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
