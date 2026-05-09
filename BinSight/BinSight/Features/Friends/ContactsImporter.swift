import Foundation
import Contacts
import CryptoKit

enum ContactsImporter {
    /// Returns hashed E.164 phone numbers from the user's contacts.
    /// Permission must already be granted; raw numbers never leave the device.
    static func collectHashedPhones(defaultRegion: String = "US") async throws -> [String] {
        let store = CNContactStore()
        let granted = try await store.requestAccess(for: .contacts)
        guard granted else { throw NSError(domain: "Contacts", code: 1, userInfo: [NSLocalizedDescriptionKey: "Permission denied"]) }
        let keys = [CNContactPhoneNumbersKey as CNKeyDescriptor]
        let request = CNContactFetchRequest(keysToFetch: keys)
        var hashes: Set<String> = []
        try store.enumerateContacts(with: request) { contact, _ in
            for value in contact.phoneNumbers {
                let raw = value.value.stringValue
                guard let e164 = normalizeToE164(raw, defaultRegion: defaultRegion) else { continue }
                hashes.insert(sha256Hex(e164))
            }
        }
        return Array(hashes)
    }

    static func sha256Hex(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Minimal best-effort E.164 normalization without phonenumberkit. Strips
    /// punctuation, prefixes default region's calling code if no `+`. Good enough
    /// for hashing-based lookup; mismatches degrade gracefully (no false matches).
    static func normalizeToE164(_ raw: String, defaultRegion: String = "US") -> String? {
        var digits = raw.filter { "0123456789+".contains($0) }
        if digits.hasPrefix("+") { return digits }
        digits = digits.filter { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        let cc = callingCode(for: defaultRegion)
        if digits.count == 10 { return "+\(cc)\(digits)" }
        if digits.count == 11 && digits.first == "1" { return "+\(digits)" }
        return "+\(digits)"
    }

    private static func callingCode(for region: String) -> String {
        switch region.uppercased() {
        case "US", "CA": return "1"
        case "GB": return "44"
        case "AU": return "61"
        default: return "1"
        }
    }
}
