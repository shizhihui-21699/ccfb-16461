import Foundation

/// How the code appears to have entered the text field.
///
/// iOS does not provide a public API that proves an OTP came from the SMS
/// AutoFill suggestion or that verifies its bound domain inside the app.
/// These values are therefore UI heuristics used for risk communication and
/// server telemetry, not a security boundary.
public enum OTPEntryMethod: String, Hashable, Sendable, Codable {
    case unknown
    /// One character at a time, including a hardware keyboard.
    case typing
    /// Explicit paste action.
    case paste
    /// A multi-character insertion that was not an explicit paste; usually
    /// the system SMS AutoFill suggestion or a password manager fill.
    case assistedBulkInsert
}

/// Signals collected by the OTP input control.
public struct OTPEntrySignals: Equatable, Sendable, Codable {
    public var method: OTPEntryMethod
    public var manualEditOccurred: Bool
    public var pasteOccurred: Bool
    public var bulkInsertOccurred: Bool

    public init(
        method: OTPEntryMethod = .unknown,
        manualEditOccurred: Bool = false,
        pasteOccurred: Bool = false,
        bulkInsertOccurred: Bool = false
    ) {
        self.method = method
        self.manualEditOccurred = manualEditOccurred
        self.pasteOccurred = pasteOccurred
        self.bulkInsertOccurred = bulkInsertOccurred
    }

    public mutating func recordSingleCharacterEdit() {
        method = .typing
        manualEditOccurred = true
    }

    public mutating func recordPaste() {
        method = .paste
        pasteOccurred = true
        manualEditOccurred = true
    }

    public mutating func recordBulkInsertWasPaste(_ wasPaste: Bool) {
        if wasPaste {
            recordPaste()
        } else {
            method = .assistedBulkInsert
            bulkInsertOccurred = true
        }
    }

    public mutating func reset() {
        self = OTPEntrySignals()
    }
}

public struct OTPRiskContext: Equatable, Sendable {
    public var bindingSupport: OTPBindingSupport
    public var entry: OTPEntrySignals
    /// The fixed official domain configured in the app. This is display
    /// material; the server must independently know the expected domain.
    public var officialDomain: OTPDomain
    /// True when the app's Associated Domains configuration and AASA deployment
    /// preflight succeeded. Release builds should fail closed if this is false.
    public var associatedDomainAvailable: Bool
    /// Desktop-web fallback or another channel where iOS AutoFill is absent.
    public var isDesktopWebManualFallback: Bool

    public init(
        bindingSupport: OTPBindingSupport = .current,
        entry: OTPEntrySignals = OTPEntrySignals(),
        officialDomain: OTPDomain,
        associatedDomainAvailable: Bool = true,
        isDesktopWebManualFallback: Bool = false
    ) {
        self.bindingSupport = bindingSupport
        self.entry = entry
        self.officialDomain = officialDomain
        self.associatedDomainAvailable = associatedDomainAvailable
        self.isDesktopWebManualFallback = isDesktopWebManualFallback
    }
}

public struct OTPRiskPrompt: Equatable, Sendable {
    public let title: String
    public let message: String
    public let confirmationButtonTitle: String
    public let cancelButtonTitle: String
    public let severity: Severity

    public enum Severity: String, Equatable, Sendable {
        case notice
        case warning
        case critical
    }
}

public enum OTPRiskDecision: Equatable, Sendable {
    case submitWithoutPrompt
    case requireConfirmation(OTPRiskPrompt)
}

/// Decides whether the user must explicitly acknowledge phishing risk.
///
/// Domain-bound AutoFill is the strong client-side path. Manual entry, paste,
/// old iOS versions, desktop fallback, or broken domain association all get
/// an explicit domain-matching warning.
public enum ManualEntryRiskPolicy {
    public static func evaluate(_ context: OTPRiskContext) -> OTPRiskDecision {
        if context.isDesktopWebManualFallback {
            return .requireConfirmation(desktopPrompt(domain: context.officialDomain))
        }

        if !context.associatedDomainAvailable {
            return .requireConfirmation(configurationPrompt(domain: context.officialDomain))
        }

        switch context.bindingSupport {
        case .manualOnly:
            return .requireConfirmation(oldSystemPrompt(domain: context.officialDomain))

        case .heuristicOnly:
            // iOS 12/13 can autofill, but the SMS has no enforced domain bound.
            // Confirm every submission rather than trusting the fill source.
            return .requireConfirmation(oldSystemPrompt(domain: context.officialDomain))

        case .domainBound:
            if context.entry.manualEditOccurred || context.entry.pasteOccurred {
                return .requireConfirmation(manualPrompt(domain: context.officialDomain))
            }

            // A non-paste bulk insertion on iOS 14+ is normally the system
            // domain-bound AutoFill suggestion. Still send entry metadata to
            // the server for risk analysis.
            return .submitWithoutPrompt
        }
    }

    public static func manualPrompt(domain: OTPDomain) -> OTPRiskPrompt {
        OTPRiskPrompt(
            title: "请确认没有落入钓鱼网站",
            message: """
            验证码只能用于官方银行 App 或域名 \(domain.rawValue)。

            如果验证码是对方通过电话、短信、聊天或“客服页面”要求您输入/转发的，请立即停止。银行不会索取验证码。
            """,
            confirmationButtonTitle: "我在官方 App 或 \(domain.rawValue) 页面，继续",
            cancelButtonTitle: "停止并核实",
            severity: .warning
        )
    }

    static func oldSystemPrompt(domain: OTPDomain) -> OTPRiskPrompt {
        OTPRiskPrompt(
            title: "当前系统不支持域名级防钓鱼填充",
            message: """
            您的 iOS 版本只能启发式识别短信验证码，不能校验短信绑定域名。

            请仅在官方银行 App 或 \(domain.rawValue) 中输入，并确认浏览器地址栏域名完全一致。不要把验证码告诉任何人。
            """,
            confirmationButtonTitle: "我已核对官方域名，继续",
            cancelButtonTitle: "停止",
            severity: .warning
        )
    }

    static func desktopPrompt(domain: OTPDomain) -> OTPRiskPrompt {
        OTPRiskPrompt(
            title: "电脑网页手动输入安全核对",
            message: """
            请核对电脑浏览器地址栏为 https://\(domain.rawValue)，且证书主体属于本银行。

            短信验证码不能发给他人，也不能输入到他人远程控制的页面。更安全的方式是使用手机银行 App 扫码确认或通行密钥。
            """,
            confirmationButtonTitle: "网址和证书无误，继续",
            cancelButtonTitle: "取消登录",
            severity: .critical
        )
    }

    static func configurationPrompt(domain: OTPDomain) -> OTPRiskPrompt {
        OTPRiskPrompt(
            title: "域名绑定配置异常",
            message: """
            本机未能确认 \(domain.rawValue) 与官方 App 的关联关系。为降低钓鱼风险，请取消本次操作并将 App 更新到最新版本。

            如确认当前来自官方渠道，可在核对域名后谨慎继续。
            """,
            confirmationButtonTitle: "我确认来源可靠，继续",
            cancelButtonTitle: "取消",
            severity: .critical
        )
    }
}
