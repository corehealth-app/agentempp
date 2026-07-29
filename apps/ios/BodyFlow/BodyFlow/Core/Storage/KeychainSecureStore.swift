import Foundation
import Security

enum SecureStorageError: Error, Equatable, Sendable {
    case invalidKey
    case unhandledStatus(OSStatus)
}

struct KeychainSecureStore: SecureStoring {
    private let service: String
    private let accessGroup: String?

    init(service: String, accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }

    func data(forKey key: String) async throws -> Data? {
        var query = try baseQuery(forKey: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw SecureStorageError.unhandledStatus(errSecInternalError)
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw SecureStorageError.unhandledStatus(status)
        }
    }

    func store(_ data: Data, forKey key: String) async throws {
        let query = try baseQuery(forKey: key)
        let updateAttributes = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            updateAttributes as CFDictionary
        )

        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addAttributes = query
            addAttributes[kSecValueData as String] = data
            addAttributes[kSecAttrAccessible as String] =
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly

            let addStatus = SecItemAdd(addAttributes as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw SecureStorageError.unhandledStatus(addStatus)
            }
        default:
            throw SecureStorageError.unhandledStatus(updateStatus)
        }
    }

    func removeData(forKey key: String) async throws {
        let query = try baseQuery(forKey: key)
        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureStorageError.unhandledStatus(status)
        }
    }

    private func baseQuery(forKey key: String) throws -> [String: Any] {
        guard !key.isEmpty else {
            throw SecureStorageError.invalidKey
        }

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        return query
    }
}
