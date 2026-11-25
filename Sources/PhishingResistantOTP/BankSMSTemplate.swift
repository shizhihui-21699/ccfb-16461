import Foundation

/// The exact SMS content to send.
///
/// Apple requires the binding metadata on the **last line**:
///
/// ```text
/// @login.examplebank.cn #123456
/// ```
///
/// An optional percent-prefixed domain may be appended only when the login
/// UI is served from an iframe on another domain:
///
/// ```text
/// @www.examplebank.cn #123456 %auth.examplebank.cn
/// ```
public struct BoundSMSMessage: Equatable, Sendable {
    public let code: String
    public let domain: OTPDomain
    public let iframeDomain: OTPDomain?
    public let introduction: String

    public init(
        code: String,
        domain: OTPDomain,
        iframeDomain: OTPDomain? = nil,
        introduction: String
    ) {
        self.code = code
        self.domain = domain
        self.iframeDomain = iframeDomain
        self.introduction = introduction
    }

    public var bindingLine: String {
        var line = "@\(domain.rawValue) #\(code)"
        if let iframeDomain {
            line += " %\(iframeDomain.rawValue)"
        }
        return line
    }

    public func render() -> String {
        let body = introduction.trimmingCharacters(in: .whitespacesAndNewlines)
        return body + "\n\n" + bindingLine
    }
}

/// A carrier-approved SMS template.
///
/// Chinese carrier/channel templates generally require review before use.
/// Keep one stable template and vary only approved parameters such as the
/// code and validity period. The domain should normally be fixed in the
/// reviewed template rather than supplied as an arbitrary runtime string.
public struct BankSMSTemplate: Equatable, Sendable {
    public let carrierTemplateID: String
    public let reviewedContent: String
    public let ttlMinutes: Int

    public init(carrierTemplateID: String, reviewedContent: String, ttlMinutes: Int) {
        self.carrierTemplateID = carrierTemplateID
        self.reviewedContent = reviewedContent
        self.ttlMinutes = ttlMinutes
    }

    /// A single backward-compatible template for old and new iOS releases.
    ///
    /// The human-readable first paragraph supports old heuristic parsers and
    /// manual entry. The final line enables domain-bound AutoFill on iOS 14+.
    /// Replace the display name and domains before carrier submission.
    public static let productionLogin = BankSMSTemplate(
        carrierTemplateID: "BANK_LOGIN_OTP_DOMAIN_BOUND_V1",
        reviewedContent: """
        【示例银行】您正在进行登录身份验证，验证码 {code}，{ttl} 分钟内有效。请勿向任何人透露，银行不会索取此验证码。本码仅限官方域名 {domain} 及官方App使用。

        @{domain} #{code}
        """,
        ttlMinutes: 5
    )

    /// Renders the reviewed template.
    ///
    /// - Important: `domain` must be one of the bank's fixed production
    ///   domains. Do not pass a domain from the current web request or
    ///   `Origin` header; that would let a forged request weaken the binding.
    public func makeMessage(
        code: String,
        domain: OTPDomain,
        iframeDomain: OTPDomain? = nil
    ) throws -> BoundSMSMessage {
        guard Self.isValidCode(code) else {
            throw OTPTemplateError.invalidCode
        }

        let rendered = reviewedContent
            .replacingOccurrences(of: "{code}", with: code)
            .replacingOccurrences(of: "{ttl}", with: String(ttlMinutes))
            .replacingOccurrences(of: "{domain}", with: domain.rawValue)

        // The reviewed template already contains the binding line. Rebuilding
        // through BoundSMSMessage guarantees the exact final-line grammar even
        // if an editor accidentally adds trailing whitespace/newlines.
        let introduction: String
        if let range = rendered.range(of: "\n@") {
            introduction = String(rendered[..<range.lowerBound])
        } else {
            introduction = rendered
        }

        return BoundSMSMessage(
            code: code,
            domain: domain,
            iframeDomain: iframeDomain,
            introduction: introduction
        )
    }

    public static func isValidCode(_ code: String) -> Bool {
        (4...8).contains(code.count) && code.allSatisfy { $0.isASCII && $0.isNumber }
    }
}

public enum OTPTemplateError: Error, Equatable {
    case invalidCode
    case unapprovedDomain
}
