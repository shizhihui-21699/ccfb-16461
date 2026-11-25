import Foundation

/// 与短信验证码相关的系统能力分层。
///
/// 事实依据（Apple 官方文档 `Enabling AutoFill for domain-bound SMS codes`）：
/// - iOS 12 / macOS 10.14：引入 Security Code AutoFill，`textContentType = .oneTimeCode`
///   可让系统从短信里识别验证码并推送到 QuickType 栏，但**不做域名绑定**，
///   钓鱼站只要放一个 one-time-code 输入框就能骗到自动填充。
/// - iOS 14 / macOS 11 Big Sur：支持域名绑定短信（短信最后一行 `@域名 #验证码`），
///   系统只在 Safari 当前网站域名、或 App 的关联域（Associated Domains）与短信内
///   `@` 域名匹配时，才把验证码作为自动填充候选；不匹配时**候选直接不出现**。
///   注意：系统并不会在假网站上额外弹"跨域警告"——不提示本身就是保护。
/// - iOS 17：自动填充/粘贴后可由系统自动删除"信息"里的验证码短信（清理向，非安全绑定）。
/// - iOS 18 至今（iOS 26）：未在 Apple 公开文档与 WebKit 发布说明中查到新增的
///   短信 OTP 跨域弹窗警告；域名绑定仍沿用 iOS 14 的"不匹配即不候选"模型。
public struct OTPCapability: Sendable, Equatable {

    public let majorSystemVersion: Int

    public init(majorSystemVersion: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion) {
        self.majorSystemVersion = majorSystemVersion
    }

    /// 系统能否识别短信验证码并提供 QuickType 自动填充（无绑定）。
    public var supportsPlainCodeAutoFill: Bool { majorSystemVersion >= 12 }

    /// 系统是否支持 `@域名 #验证码` 域名绑定自动填充。
    public var supportsDomainBoundAutoFill: Bool { majorSystemVersion >= 14 }

    /// 系统是否支持自动填充后清理验证码短信（iOS 17+）。
    public var supportsAutoCleanup: Bool { majorSystemVersion >= 17 }

    /// 当前设备上，短信域名绑定这道系统防线是否真实生效。
    /// iOS 14 以下机型仍可能在网，必须由 App 侧风险控制兜底。
    public var domainBindingIsEnforcedByOS: Bool { supportsDomainBoundAutoFill }
}
