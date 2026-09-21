import Foundation

/// Semantic Version (SemVer) ayrıştırma ve karşılaştırma yardımcısı
public struct SemVer: Comparable, Equatable, CustomStringConvertible, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: String?
    public let raw: String

    public var description: String {
        return raw
    }

    public init(_ versionString: String) {
        self.raw = versionString
        var cleaned = versionString.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.lowercased().hasPrefix("v") {
            cleaned = String(cleaned.dropFirst())
        }

        let parts = cleaned.components(separatedBy: "-")
        let mainParts = parts[0].components(separatedBy: ".")

        self.major = mainParts.count > 0 ? (Int(mainParts[0]) ?? 0) : 0
        self.minor = mainParts.count > 1 ? (Int(mainParts[1]) ?? 0) : 0
        self.patch = mainParts.count > 2 ? (Int(mainParts[2]) ?? 0) : 0

        if parts.count > 1 {
            self.prerelease = parts.dropFirst().joined(separator: "-")
        } else {
            self.prerelease = nil
        }
    }

    public static func < (lhs: SemVer, rhs: SemVer) -> Bool {
        if lhs.major != rhs.major {
            return lhs.major < rhs.major
        }
        if lhs.minor != rhs.minor {
            return lhs.minor < rhs.minor
        }
        if lhs.patch != rhs.patch {
            return lhs.patch < rhs.patch
        }
        // Eğer ana numaralar eşitse, ön sürüm (prerelease) olan daha küçüktür (1.0.0-beta < 1.0.0)
        if lhs.prerelease != nil && rhs.prerelease == nil {
            return true
        }
        if lhs.prerelease == nil && rhs.prerelease != nil {
            return false
        }
        if let lhsPre = lhs.prerelease, let rhsPre = rhs.prerelease {
            return comparePrerelease(lhsPre, rhsPre)
        }
        return false
    }

    /// SemVer 2.0 kuralı: ön-sürüm etiketi noktadan bölünür, her parça ayrı karşılaştırılır.
    /// Sayısal parçalar sayı olarak karşılaştırılır — düz string karşılaştırması
    /// `beta.10`'u `beta.9`'dan küçük sayıyordu. Sayısal parça alfanümerikten küçüktür.
    static func comparePrerelease(_ lhs: String, _ rhs: String) -> Bool {
        let l = lhs.split(separator: ".", omittingEmptySubsequences: false)
        let r = rhs.split(separator: ".", omittingEmptySubsequences: false)
        for index in 0..<min(l.count, r.count) {
            let lp = String(l[index]), rp = String(r[index])
            if lp == rp { continue }
            switch (Int(lp), Int(rp)) {
            case let (ln?, rn?): return ln < rn      // iki taraf da sayı
            case (_?, nil):      return true         // sayısal < alfanümerik
            case (nil, _?):      return false
            case (nil, nil):     return lp < rp
            }
        }
        // Tüm ortak parçalar eşitse, daha az parçası olan küçüktür.
        return l.count < r.count
    }

    public static func == (lhs: SemVer, rhs: SemVer) -> Bool {
        return lhs.major == rhs.major &&
               lhs.minor == rhs.minor &&
               lhs.patch == rhs.patch &&
               lhs.prerelease == rhs.prerelease
    }
}
