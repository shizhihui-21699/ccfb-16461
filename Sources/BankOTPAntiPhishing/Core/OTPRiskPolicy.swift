import Foundation

/// 验证码进入输入框的来源。
///
/// 系统没有公开 API 直接告知"这段文字来自 QuickType 自动填充"，
/// 依据 Apple《About the Password AutoFill workflow》：自动填充与粘贴/键入一样，
/// 最终都走 `textField(_:shouldChangeCharactersIn:replacementString:)` /
/// `insertText(_:)` 等普通文本变更通道。因此用以下启发式三分类，
/// 分类逻辑收敛在 UI 层的 `OTPTextField` 里，本枚举只承载结论。
public enum OTPEntrySource: String, Equatable, Sendable {
    /// 来自 QuickType 自动填充（系统已按域名绑定做过第一道匹配）。
    case autoFill
    /// 用户从剪贴板粘贴（钓鱼站诱导"复制短信里的验证码再粘贴"是常见路径）。
    case paste
    /// 用户逐字手动键入（AiTM 钓鱼的典型动作：受害者把真实验证码敲进假页面/假 App）。
    case manual
}

/// 一次验证码提交的上下文。
public struct OTPEntryContext: Equatable, Sendable {
    public let source: OTPEntrySource
    /// 本次登录期望绑定的银行域名（即短信模板 `@` 后应出现的域名），如 `bank.example`。
    public let expectedBoundDomain: String
    /// 若 App 侧能拿到本次短信解析结果（如服务端下发的模板元数据），一并传入；拿不到传 `nil`。
    public let parsedMessage: SMSOTPMessage?
    public let capability: OTPCapability
    /// 当前登录会话的服务端风险信号（可选，没有就用默认空集合）。
    public let serverSignals: ServerRiskSignals

    public init(
        source: OTPEntrySource,
        expectedBoundDomain: String,
        parsedMessage: SMSOTPMessage? = nil,
        capability: OTPCapability = OTPCapability(),
        serverSignals: ServerRiskSignals = ServerRiskSignals()
    ) {
        self.source = source
        self.expectedBoundDomain = expectedBoundDomain
        self.parsedMessage = parsedMessage
        self.capability = capability
        self.serverSignals = serverSignals
    }
}

/// 服务端风控信号——App 端只做展示前的实时拦截，真正的 AiTM 识别在服务端。
public struct ServerRiskSignals: Equatable, Sendable {
    /// 同一会话短时间内出现两次 OTP 申请（攻击者在受害者收到短信前后接力登录的典型特征）。
    public var duplicateOTPRequest: Bool = false
    /// 登录 IP 与常用地/设备指纹不一致。
    public var ipOrDeviceMismatch: Bool = false
    /// 不可能旅行（短时间内地理跨度异常）。
    public var impossibleTravel: Bool = false
    /// 该验证码已被消费过一次（重放/接力）。
    public var codeAlreadyConsumed: Bool = false

    public init(
        duplicateOTPRequest: Bool = false,
        ipOrDeviceMismatch: Bool = false,
        impossibleTravel: Bool = false,
        codeAlreadyConsumed: Bool = false
    ) {
        self.duplicateOTPRequest = duplicateOTPRequest
        self.ipOrDeviceMismatch = ipOrDeviceMismatch
        self.impossibleTravel = impossibleTravel
        self.codeAlreadyConsumed = codeAlreadyConsumed
    }

    public var hasAny: Bool {
        duplicateOTPRequest || ipOrDeviceMismatch || impossibleTravel || codeAlreadyConsumed
    }
}

/// 风险等级。
public enum OTPRiskLevel: Int, Comparable, Sendable {
    case low = 0
    case medium = 1
    case high = 2

    public static func < (lhs: OTPRiskLevel, rhs: OTPRiskLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// 风控决策与对应的用户提示文案。
public struct OTPRiskDecision: Equatable, Sendable {
    public let level: OTPRiskLevel
    public let title: String
    public let message: String
    /// 是否需要二次确认（用户仍可继续，但留痕并上报）。
    public let requiresConfirmation: Bool
    /// 是否直接阻断本次验证（如验证码已被消费，继续无意义且危险）。
    public let blocksSubmission: Bool

    public init(
        level: OTPRiskLevel,
        title: String,
        message: String,
        requiresConfirmation: Bool,
        blocksSubmission: Bool = false
    ) {
        self.level = level
        self.title = title
        self.message = message
        self.requiresConfirmation = requiresConfirmation
        self.blocksSubmission = blocksSubmission
    }
}

/// 验证码输入风控策略（纯逻辑、可单测）。
public struct OTPRiskPolicy: Sendable {

    /// 银行受信域名清单（主域名 + 需要区分的子域）。
    public let trustedDomains: Set<String>
    public let parser: SMSOTPParser

    public init(trustedDomains: Set<String>, parser: SMSOTPParser = SMSOTPParser()) {
        self.trustedDomains = trustedDomains
        self.parser = parser
    }

    public func evaluate(_ context: OTPEntryContext) -> OTPRiskDecision {
        // 0. 服务端硬阻断信号优先。
        if context.serverSignals.codeAlreadyConsumed {
            return OTPRiskDecision(
                level: .high,
                title: "验证码已失效",
                message: "该验证码已被使用过，为保护账户安全本次登录已被拦截。如非本人操作，请立即联系客服冻结账户。",
                requiresConfirmation: false,
                blocksSubmission: true
            )
        }

        // 1. 短信域名绑定与银行期望域名不一致——最强的钓鱼信号。
        if let bound = context.parsedMessage?.boundDomain,
           !isTrusted(bound, expected: context.expectedBoundDomain) {
            return OTPRiskDecision(
                level: .high,
                title: "检测到钓鱼风险",
                message: "本条短信中的验证码绑定的是 \(bound)，并非本行域名 \(context.expectedBoundDomain)。请勿在任何其他网站或 App 中输入该验证码。",
                requiresConfirmation: true
            )
        }

        // 2. 系统不支持域名绑定（iOS 14 以下），系统层没有第一道防线，手动/粘贴一律加强提示。
        if !context.capability.domainBindingIsEnforcedByOS
            && context.source != .autoFill {
            return OTPRiskDecision(
                level: .high,
                title: "请确认您正在本行官方渠道操作",
                message: "您的系统版本不支持验证码域名绑定，无法自动核验当前页面真伪。请确认只在本行官方 App 或 \(context.expectedBoundDomain) 网站输入验证码；任何客服、公检法要求转账并索取验证码的都是诈骗。",
                requiresConfirmation: true
            )
        }

        // 3. 支持绑定的系统上，手动键入仍需提示（AiTM 钓鱼的核心动作）。
        if context.source == .manual {
            let base = OTPRiskDecision(
                level: .medium,
                title: "请注意验证码使用场景",
                message: "您正在手动输入短信验证码。本行验证码只会在官方 App 和 \(context.expectedBoundDomain) 网站使用，请勿在其他页面、聊天窗口或电话中提供。",
                requiresConfirmation: true
            )
            return withServerSignals(context.serverSignals, base: base)
        }

        // 4. 粘贴：风险高于自动填充（钓鱼站常诱导复制粘贴）。
        if context.source == .paste {
            let base = OTPRiskDecision(
                level: .medium,
                title: "请确认粘贴来源可信",
                message: "您通过粘贴填写了验证码。请确认短信中的绑定域名是 \(context.expectedBoundDomain)，且当前操作发生在本行官方渠道。",
                requiresConfirmation: true
            )
            return withServerSignals(context.serverSignals, base: base)
        }

        // 5. 自动填充：系统已做域名匹配，默认低风险；服务端有信号再升级。
        let base = OTPRiskDecision(
            level: .low,
            title: "",
            message: "",
            requiresConfirmation: false
        )
        return withServerSignals(context.serverSignals, base: base)
    }

    // MARK: - 内部实现

    func withServerSignals(_ signals: ServerRiskSignals, base: OTPRiskDecision) -> OTPRiskDecision {
        guard signals.hasAny else { return base }
        let reasons = serverReasonText(signals)
        let upgraded = OTPRiskDecision(
            level: .high,
            title: "登录环境存在异常",
            message: "检测到\(reasons)。若非本人操作，请立即停止并联系客服。确认继续将记录本次操作。",
            requiresConfirmation: true
        )
        return upgraded.level >= base.level ? upgraded : base
    }

    func serverReasonText(_ s: ServerRiskSignals) -> String {
        var parts: [String] = []
        if s.duplicateOTPRequest { parts.append("验证码被重复申请") }
        if s.ipOrDeviceMismatch { parts.append("登录设备或网络与常用环境不一致") }
        if s.impossibleTravel { parts.append("登录地点异常") }
        if s.codeAlreadyConsumed { parts.append("验证码已被使用") }
        return parts.joined(separator: "、")
    }

    /// 域名匹配：精确匹配或子域匹配（`auth.bank.example` 属于 `bank.example`）。
    func isTrusted(_ domain: String, expected: String) -> Bool {
        let d = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let e = expected.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if trustedDomains.contains(d) { return true }
        if d == e { return true }
        return d.hasSuffix("." + e)
    }
}
