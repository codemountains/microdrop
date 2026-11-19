import Foundation
import Security

nonisolated struct MicroCMSCredentials: Sendable {
    let serviceID: String
    let apiKey: String

    init(serviceID: String, apiKey: String) throws {
        let service = serviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard service.range(of: #"\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z"#, options: .regularExpression) != nil else {
            throw CredentialStoreError.invalidService
        }
        guard !key.isEmpty, key.utf8.allSatisfy({ (33...126).contains($0) }) else {
            throw CredentialStoreError.invalidKey
        }
        self.serviceID = service
        self.apiKey = key
    }
}

nonisolated struct CredentialRegistration: Equatable, Sendable {
    let serviceID: String
    fileprivate let generation: Data
}

nonisolated enum CredentialStore {
    // Both targets sign with the same first keychain access group.
    private static var item: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "microDrop.microCMS.credentials",
            kSecAttrAccount as String: "upload",
            kSecAttrSynchronizable as String: false,
            kSecUseDataProtectionKeychain as String: true
        ]
    }

    static func register(serviceID: String, apiKey: String) throws {
        let credentials = try MicroCMSCredentials(serviceID: serviceID, apiKey: apiKey)
        var attributes = item
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        attributes[kSecAttrLabel as String] = credentials.serviceID
        attributes[kSecAttrGeneric as String] = Data(UUID().uuidString.utf8)
        attributes[kSecValueData as String] = Data(credentials.apiKey.utf8)
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem { throw CredentialStoreError.alreadyRegistered }
        try check(status)
    }

    static func registration() throws -> CredentialRegistration? {
        guard let attributes = try read(includingKey: false) else { return nil }
        guard let generation = attributes[kSecAttrGeneric as String] as? Data else {
            throw CredentialStoreError.invalidRecord
        }
        return try CredentialRegistration(serviceID: serviceID(in: attributes), generation: generation)
    }

    static func credentials(for registration: CredentialRegistration) throws -> MicroCMSCredentials {
        guard let attributes = try read(includingKey: true, registration: registration) else {
            throw CredentialStoreError.shareAgain
        }
        guard let keyData = attributes[kSecValueData as String] as? Data,
              let key = String(data: keyData, encoding: .utf8) else { throw CredentialStoreError.invalidRecord }
        return try MicroCMSCredentials(serviceID: serviceID(in: attributes), apiKey: key)
    }

    static func delete(_ registration: CredentialRegistration) throws {
        let query = query(for: registration)
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecItemNotFound { throw CredentialStoreError.registrationChanged }
        try check(status)
    }

    private static func query(for registration: CredentialRegistration?) -> [String: Any] {
        var query = item
        if let registration {
            query[kSecAttrLabel as String] = registration.serviceID
            query[kSecAttrGeneric as String] = registration.generation
        }
        return query
    }

    private static func read(includingKey: Bool, registration: CredentialRegistration? = nil) throws -> [String: Any]? {
        var query = query(for: registration)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnAttributes as String] = true
        if includingKey { query[kSecReturnData as String] = true }
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let attributes = result as? [String: Any] else { throw CredentialStoreError.invalidRecord }
        return attributes
    }

    private static func serviceID(in attributes: [String: Any]) throws -> String {
        guard let service = attributes[kSecAttrLabel as String] as? String, !service.isEmpty else {
            throw CredentialStoreError.invalidRecord
        }
        return service
    }

    private static func check(_ status: OSStatus) throws {
        switch status {
        case errSecSuccess: return
        case errSecInteractionNotAllowed: throw CredentialStoreError.locked
        default: throw CredentialStoreError.keychain(status)
        }
    }
}

private nonisolated enum CredentialStoreError: LocalizedError {
    case invalidService, invalidKey, alreadyRegistered, registrationChanged, shareAgain, invalidRecord, locked
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidService: "サービスIDを半角の英小文字・数字・ハイフンで入力してください。"
        case .invalidKey: "APIキーを空白を含まない半角文字で入力してください。"
        case .alreadyRegistered: "すでに登録されています。変更するには登録を削除してください。"
        case .registrationChanged: "登録内容が変わりました。現在の登録を確認してください。"
        case .shareAgain: "登録内容が変わりました。写真をもう一度共有してください。"
        case .invalidRecord: "キーチェーンの登録情報を読み取れませんでした。"
        case .locked: "デバイスのロックを解除して、もう一度お試しください。"
        case .keychain(let status): "キーチェーンにアクセスできませんでした（\(status)）。"
        }
    }
}
