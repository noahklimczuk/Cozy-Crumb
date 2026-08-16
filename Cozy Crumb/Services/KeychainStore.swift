//
//  KeychainStore.swift
//  Cozy Crumb
//
//  The one place an API key is stored. Never UserDefaults, never a plist,
//  never logged.
//
//  Items use kSecAttrAccessibleWhenUnlockedThisDeviceOnly: the key does not
//  leave this device and is unreadable while the phone is locked.
//

import Foundation
import Security
import os

struct KeychainStore: Sendable {

    nonisolated static let shared = KeychainStore()

    private let service = "ca.klimczuk.cozycrumb.keys"

    enum Key: String, Sendable {
        case geminiAPIKey = "gemini.api.key"
    }

    nonisolated init() {}

    // MARK: - Read

    nonisolated func string(for key: Key) -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else {
            return nil
        }

        return value
    }

    nonisolated func hasValue(for key: Key) -> Bool {
        string(for: key) != nil
    }

    // MARK: - Write

    @discardableResult
    nonisolated func set(_ value: String?, for key: Key) -> Bool {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let trimmed, !trimmed.isEmpty else {
            return delete(key)
        }

        guard let data = trimmed.data(using: .utf8) else { return false }

        let query = baseQuery(for: key)
        let attributes: [String: Any] = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecSuccess {
            return true
        }

        if updateStatus == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            logIfFailed(addStatus, action: "add")
            return addStatus == errSecSuccess
        }

        logIfFailed(updateStatus, action: "update")
        return false
    }

    @discardableResult
    nonisolated func delete(_ key: Key) -> Bool {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Helpers

    private nonisolated func baseQuery(for key: Key) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
    }

    /// Logs the OSStatus only — never the value, never the key.
    private nonisolated func logIfFailed(_ status: OSStatus, action: String) {
        guard status != errSecSuccess else { return }
        Log.app.error("Keychain \(action, privacy: .public) failed: \(status, privacy: .public)")
    }
}

extension KeychainStore {
    /// Masked form for display in Settings — "…4f2a".
    nonisolated static func masked(_ key: String) -> String {
        guard key.count > 4 else { return "••••" }
        return "••••" + key.suffix(4)
    }
}
