import Foundation
import Security

enum SecureStorageError: Error, Equatable, Sendable {
    case invalidKey
    case readFailed(OSStatus)
    case updateFailed(OSStatus)
    case addFailed(OSStatus)
    case deleteFailed(OSStatus)
}

enum KeychainItemClass: Equatable, Sendable { case genericPassword }
enum KeychainAccessibility: Equatable, Sendable { case whenUnlockedThisDeviceOnly }

struct KeychainItemDescriptor: Equatable, Sendable {
    let itemClass: KeychainItemClass
    let service: String
    let account: String
    let accessibility: KeychainAccessibility
    let synchronizable: Bool
    let accessGroup: String?
}

enum KeychainReadResult: Sendable {
    case data(Data)
    case notFound
    case failure(OSStatus)
}

protocol KeychainSecurityClient: Sendable {
    func read(_ descriptor: KeychainItemDescriptor) async -> KeychainReadResult
    func update(_ descriptor: KeychainItemDescriptor, data: Data) async -> OSStatus
    func add(_ descriptor: KeychainItemDescriptor, data: Data) async -> OSStatus
    func delete(_ descriptor: KeychainItemDescriptor) async -> OSStatus
}

struct SystemKeychainSecurityClient: KeychainSecurityClient {
    func read(_ descriptor: KeychainItemDescriptor) async -> KeychainReadResult {
        var query = query(for: descriptor)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                return .failure(errSecInternalError)
            }
            return .data(data)
        case errSecItemNotFound:
            return .notFound
        default:
            return .failure(status)
        }
    }

    func update(_ descriptor: KeychainItemDescriptor, data: Data) async -> OSStatus {
        SecItemUpdate(
            query(for: descriptor) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
    }

    func add(_ descriptor: KeychainItemDescriptor, data: Data) async -> OSStatus {
        var attributes = query(for: descriptor)
        attributes[kSecValueData as String] = data
        return SecItemAdd(attributes as CFDictionary, nil)
    }

    func delete(_ descriptor: KeychainItemDescriptor) async -> OSStatus {
        SecItemDelete(query(for: descriptor) as CFDictionary)
    }

    private func query(for descriptor: KeychainItemDescriptor) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: descriptor.service,
            kSecAttrAccount as String: descriptor.account,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: false,
        ]
        if let accessGroup = descriptor.accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}

struct KeychainSecureStore: SecureStoring {
    private let service: String
    private let security: any KeychainSecurityClient

    init(
        service: String,
        security: any KeychainSecurityClient = SystemKeychainSecurityClient()
    ) {
        self.service = service
        self.security = security
    }

    func data(forKey key: String) async throws -> Data? {
        switch await security.read(try descriptor(forKey: key)) {
        case .data(let data):
            return data
        case .notFound:
            return nil
        case .failure(let status):
            throw SecureStorageError.readFailed(status)
        }
    }

    func store(_ data: Data, forKey key: String) async throws {
        let descriptor = try descriptor(forKey: key)
        let updateStatus = await security.update(descriptor, data: data)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            let addStatus = await security.add(descriptor, data: data)
            guard addStatus == errSecSuccess else {
                throw SecureStorageError.addFailed(addStatus)
            }
        default:
            throw SecureStorageError.updateFailed(updateStatus)
        }
    }

    func removeData(forKey key: String) async throws {
        let status = await security.delete(try descriptor(forKey: key))
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureStorageError.deleteFailed(status)
        }
    }

    private func descriptor(forKey key: String) throws -> KeychainItemDescriptor {
        guard !key.isEmpty else { throw SecureStorageError.invalidKey }
        return KeychainItemDescriptor(
            itemClass: .genericPassword,
            service: service,
            account: key,
            accessibility: .whenUnlockedThisDeviceOnly,
            synchronizable: false,
            accessGroup: nil
        )
    }
}
