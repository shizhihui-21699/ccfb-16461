import Foundation

/// A DNS domain that an SMS one-time code is bound to.
///
/// The SMS machine-readable suffix uses the bare domain, without a scheme,
/// path, query, fragment, port, or trailing slash:
///
/// ```text
/// @login.examplebank.cn #123456
/// ```
public struct OTPDomain: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public var description: String { rawValue }

    /// Creates a domain from configuration or user input.
    ///
    /// This initializer tolerates a copied URL such as
    /// `https://login.examplebank.cn/path` and normalizes it to
    /// `login.examplebank.cn`.
    public init?(_ input: String?) {
        guard let normalized = OTPDomain.normalize(input) else { return nil }
        self.rawValue = normalized
    }

    /// Creates a domain only when `input` is already a bare DNS name.
    ///
    /// Use this from startup configuration checks where a URL or path is
    /// likely a deployment mistake that should fail fast.
    public init?(strict input: String?) {
        guard let input else { return nil }
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.contains("://"), !value.contains("/"), !value.contains("?", ),
              !value.contains("#"), !value.contains(":") else {
            return nil
        }
        self.init(value)
    }

    static func normalize(_ input: String?) -> String? {
        guard var value = input?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !value.isEmpty else {
            return nil
        }

        if value.contains("://"),
           let url = URL(string: value),
           let host = url.host {
            value = host.lowercased()
        } else if let slash = value.firstIndex(of: "/") {
            value = String(value[..<slash])
        }

        if value.hasPrefix("@") {
            value.removeFirst()
        }
        if let at = value.lastIndex(of: "@") {
            value = String(value[value.index(after: at)...])
        }

        // A bare host:port is not accepted. Configuration should specify the
        // DNS name only; release validation uses OTPDomain(strict:).
        if !value.contains("://"), value.contains(":") {
            return nil
        }
        if let colon = value.firstIndex(of: ":") {
            value = String(value[..<colon])
        }
        while value.hasSuffix(".") {
            value.removeLast()
        }

        guard value.count <= 253, !value.isEmpty, !value.contains("*") else {
            return nil
        }

        let labels = value.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return nil }

        let labelPattern = #"^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$"#
        guard let regex = try? NSRegularExpression(pattern: labelPattern) else {
            return nil
        }

        for label in labels {
            let range = NSRange(label.startIndex..<label.endIndex, in: label)
            guard label.count >= 1,
                  label.count <= 63,
                  regex.firstMatch(in: String(label), range: range) != nil else {
                return nil
            }
        }

        if let tld = labels.last, tld.allSatisfy({ $0.isNumber }) {
            return nil
        }

        return value
    }
}

/// The SMS AutoFill binding level supported by the running system.
public enum OTPBindingSupport: String, Hashable, Sendable {
    /// iOS 14+, macOS Big Sur+, or a newer system that understands
    /// `@domain #code`.
    case domainBound

    /// iOS 12–13: `textContentType = .oneTimeCode` and heuristic SMS code
    /// detection, but no cryptographic/DNS binding check by AutoFill.
    case heuristicOnly

    /// Systems older than iOS 12: users generally read and type the code.
    case manualOnly

    public static var current: OTPBindingSupport {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        #if os(iOS) || os(tvOS) || os(visionOS)
        switch version.majorVersion {
        case 14...:
            return .domainBound
        case 12..<14:
            return .heuristicOnly
        default:
            return .manualOnly
        }
        #else
        // macOS Big Sur is major version 11. Catalina 10.15 had Security
        // Code AutoFill support, but not enforced domain binding.
        if version.majorVersion >= 11 {
            return .domainBound
        } else if version.majorVersion == 10, version.minorVersion >= 15 {
            return .heuristicOnly
        } else {
            return .manualOnly
        }
        #endif
    }
}
