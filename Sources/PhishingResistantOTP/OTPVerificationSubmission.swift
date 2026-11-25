import Foundation

/// Non-secret client signals sent with the verification request.
///
/// Never put the SMS code in logs. The code is included in the HTTPS request
/// body only and should be treated as a short-lived secret by the server.
public struct OTPVerificationSubmission: Encodable, Sendable {
    public let challengeID: String
    public let code: String
    public let entryMethod: String
    public let manualEditOccurred: Bool
    public let pasteOccurred: Bool
    public let bulkInsertOccurred: Bool
    public let bindingSupport: String
    public let platform: String
    public let osVersion: String
    public let appVersion: String?
    /// Base64-encoded App Attest assertion, when available.
    public let appAttestAssertion: String?
    /// Base64-encoded App Attest key identifier, when available.
    public let appAttestKeyID: String?

    public init(
        challengeID: String,
        code: String,
        signals: OTPEntrySignals,
        bindingSupport: OTPBindingSupport = .current,
        appVersion: String? = nil,
        appAttestAssertion: Data? = nil,
        appAttestKeyID: String? = nil
    ) {
        self.challengeID = challengeID
        self.code = code
        self.entryMethod = signals.method.rawValue
        self.manualEditOccurred = signals.manualEditOccurred
        self.pasteOccurred = signals.pasteOccurred
        self.bulkInsertOccurred = signals.bulkInsertOccurred
        self.bindingSupport = bindingSupport.rawValue
        #if os(iOS)
        self.platform = "ios"
        #elseif os(macOS)
        self.platform = "macos"
        #else
        self.platform = "other"
        #endif
        let v = ProcessInfo.processInfo.operatingSystemVersion
        self.osVersion = "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        self.appVersion = appVersion
        self.appAttestAssertion = appAttestAssertion?.base64EncodedString()
        self.appAttestKeyID = appAttestKeyID
    }
}

public struct OTPVerificationResponse: Decodable, Sendable {
    public let verified: Bool
    public let retryAfterSeconds: Int?
    public let remainingAttempts: Int?
    public let riskAction: RiskAction?

    public enum RiskAction: String, Decodable, Sendable {
        case allow
        case requireStepUp = "require_step_up"
        case reject
    }
}

public protocol OTPVerificationServicing: Sendable {
    func verify(_ submission: OTPVerificationSubmission) async throws -> OTPVerificationResponse
}
