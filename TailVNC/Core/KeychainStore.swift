import Foundation
import Security

enum KeychainStore {
    private static let vncPasswordService = "com.sancerio.tailvnc.vnc-password"
    private static let macAccountService = "com.sancerio.tailvnc.mac-account"

    static func password(for endpoint: String) -> String? {
        guard let data = data(for: endpoint, service: vncPasswordService) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(password: String, for endpoint: String) throws {
        try save(Data(password.utf8), for: endpoint, service: vncPasswordService)
    }

    static func macCredentials(for endpoint: String) -> MacCredentials? {
        guard let data = data(for: endpoint, service: macAccountService) else { return nil }
        return try? JSONDecoder().decode(MacCredentials.self, from: data)
    }

    static func save(macCredentials: MacCredentials, for endpoint: String) throws {
        try save(JSONEncoder().encode(macCredentials), for: endpoint, service: macAccountService)
    }

    static func deletePassword(for endpoint: String) {
        delete(for: endpoint, service: vncPasswordService)
    }

    static func deleteMacCredentials(for endpoint: String) {
        delete(for: endpoint, service: macAccountService)
    }

    private static func data(for endpoint: String, service: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: endpoint,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private static func save(_ data: Data, for endpoint: String, service: String) throws {
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: endpoint
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(identity as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(updateStatus))
        }

        var newItem = identity
        attributes.forEach { newItem[$0.key] = $0.value }
        let addStatus = SecItemAdd(newItem as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(addStatus))
        }
    }

    private static func delete(for endpoint: String, service: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: endpoint
        ]
        SecItemDelete(query as CFDictionary)
    }
}
