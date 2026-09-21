import Foundation
import Security

/// GitHub Personal Access Token'ı Keychain'de saklar.
///
/// Daha önce token düz metin olarak `UserDefaults`'a yazılıyordu: arayüzde `SecureField`
/// ile alınmasına rağmen plist dosyasında açıkta duruyordu, kullanıcı olarak çalışan her
/// süreç okuyabiliyordu ve yedeklere (Time Machine, iCloud) olduğu gibi giriyordu.
public enum KeychainStore: Sendable {

    private static let service = "com.erenkirkil.KDeck"

    public static func set(_ value: String, for account: String) {
        // Boş değer "sil" anlamına gelir.
        guard !value.isEmpty else { remove(account); return }
        guard let data = value.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            // Cihazdan çıkmasın, yalnızca kilit açıkken erişilebilsin.
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert.merge(attributes) { current, _ in current }
            SecItemAdd(insert as CFDictionary, nil)
        }
    }

    public static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }
        return value
    }

    public static func remove(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
