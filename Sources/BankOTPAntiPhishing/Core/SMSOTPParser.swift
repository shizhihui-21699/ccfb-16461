import Foundation

/// 短信验证码解析结果。
public struct SMSOTPMessage: Equatable, Sendable {
    /// 短信中绑定的主域名（`@` 后的值），未绑定为 `nil`。
    public let boundDomain: String?
    /// iframe 嵌入登录场景的附加域名（`%` 后的值），普通场景为 `nil`。
    public let iframeDomains: [String]
    /// 短信中声明的验证码（`#` 后的值）。
    public let code: String
    /// 短信原文（脱敏后再落日志，勿直接打印）。
    public let rawText: String

    public init(boundDomain: String?, iframeDomains: [String], code: String, rawText: String) {
        self.boundDomain = boundDomain
        self.iframeDomains = iframeDomains
        self.code = code
        self.rawText = rawText
    }

    public var isDomainBound: Bool { boundDomain != nil }
}

/// 银行下发短信的模板校验结果——用于上线前/运营商送审前自检，
/// 避免通道在末尾追加签名把"最后一行"约定破坏掉。
public struct SMSTemplateCheck: OptionSet, Equatable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let ok                              = SMSTemplateCheck(rawValue: 1 << 0)
    /// 绑定行不在短信最后一行（Apple 要求最后一行必须是 `@域名 #验证码`）。
    public static let bindingLineNotLast              = SMSTemplateCheck(rawValue: 1 << 1)
    /// 缺少 `@域名`。
    public static let missingDomain                   = SMSTemplateCheck(rawValue: 1 << 2)
    /// 缺少 `#验证码`。
    public static let missingCode                     = SMSTemplateCheck(rawValue: 1 << 3)
    /// 域名带了协议头（`https://`）或路径，Apple 只接受裸 DNS 域名。
    public static let domainNotBareDNS                = SMSTemplateCheck(rawValue: 1 << 4)
    /// 验证码长度/字符集不符合银行策略。
    public static let codeOutOfPolicy                 = SMSTemplateCheck(rawValue: 1 << 5)
    /// 末尾存在通道签名等额外行，可能把绑定行顶离最后一行。
    public static let trailingContentAfterBindingLine = SMSTemplateCheck(rawValue: 1 << 6)
}

/// 解析银行短信验证码，兼容 iOS 域名绑定格式与历史纯验证码格式。
///
/// Apple 规则（见 `Enabling AutoFill for domain-bound SMS codes`）：
/// 短信前半部分内容任意；**最后一行**必须是
/// `@<DNS域名> #<验证码>`，两个字段以空格分隔；iframe 场景可再追加 `%<域名>`。
public struct SMSOTPParser: Sendable {

    /// 银行期望的验证码长度（国内银行短信验证码普遍为 6 位数字）。
    public let expectedCodeLength: Int

    public init(expectedCodeLength: Int = 6) {
        self.expectedCodeLength = expectedCodeLength
    }

    /// 解析一条短信。
    /// - 优先按域名绑定格式解析最后一行；
    /// - 绑定格式缺失时，回退提取纯数字验证码（兼容 iOS 14 以下老模板/存量用户）。
    public func parse(_ message: String) -> SMSOTPMessage? {
        let normalized = Self.normalizeSymbols(message)
        let lines = normalized
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard let lastLine = lines.last else { return nil }

        if let bound = parseBindingLine(lastLine) {
            return SMSOTPMessage(
                boundDomain: bound.domain,
                iframeDomains: bound.iframeDomains,
                code: bound.code,
                rawText: message
            )
        }

        // 回退：历史模板，无域名绑定，仅提取验证码。
        guard let code = extractPlainCode(from: normalized) else { return nil }
        return SMSOTPMessage(boundDomain: nil, iframeDomains: [], code: code, rawText: message)
    }

    /// 上线前对"模板样例"做合规校验（变量用占位符或真实样例均可）。
    public func checkTemplate(_ template: String) -> SMSTemplateCheck {
        let normalized = Self.normalizeSymbols(template)
        let lines = normalized
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var issues = SMSTemplateCheck()

        guard let lastLine = lines.last else {
            return [.missingDomain, .missingCode]
        }

        // 绑定行必须且只能出现在最后一行；先在全文范围内定位它。
        let bindingIndex = lines.firstIndex { parseBindingLine($0) != nil }

        guard let index = bindingIndex, let bound = parseBindingLine(lines[index]) else {
            if !lastLine.contains("@") { issues.insert(.missingDomain) }
            if !lastLine.contains("#") { issues.insert(.missingCode) }
            return issues
        }

        if index != lines.count - 1 {
            issues.insert(.bindingLineNotLast)
            issues.insert(.trailingContentAfterBindingLine)
        }

        if bound.domain.lowercased().hasPrefix("http://")
            || bound.domain.lowercased().hasPrefix("https://")
            || bound.domain.contains("/") {
            issues.insert(.domainNotBareDNS)
        }

        if bound.code.count != expectedCodeLength
            || bound.code.rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) != nil {
            issues.insert(.codeOutOfPolicy)
        }

        return issues.isEmpty ? .ok : issues
    }

    // MARK: - 内部实现

    struct BindingLine {
        let domain: String
        let code: String
        let iframeDomains: [String]
    }

    func parseBindingLine(_ line: String) -> BindingLine? {
        // 形如：@bank.example #123456 或 @bank.example #123456 %iframe.example
        // 字段以空白分隔；#、% 作为字段前缀。
        let tokens = line.split(whereSeparator: { $0.isWhitespace })
        guard let atToken = tokens.first(where: { $0.hasPrefix("@") }),
              let hashToken = tokens.first(where: { $0.hasPrefix("#") }) else {
            return nil
        }

        let domain = String(atToken.dropFirst())
        let code = String(hashToken.dropFirst())
        guard !domain.isEmpty, !code.isEmpty else { return nil }

        let iframeDomains = tokens
            .filter { $0.hasPrefix("%") }
            .map { String($0.dropFirst()) }
            .filter { !$0.isEmpty }

        return BindingLine(domain: domain, code: code, iframeDomains: iframeDomains)
    }

    func extractPlainCode(from text: String) -> String? {
        // 取第一段满足长度的连续数字；优先匹配预期长度，避免把订单号当验证码。
        let pattern = "(?<!\\d)\\d{\(expectedCodeLength)}(?!\\d)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: text,
                range: NSRange(text.startIndex..., in: text)
              ),
              let range = Range(match.range, in: text) else {
            return nil
        }
        return String(text[range])
    }

    /// 运营商通道可能把半角符号转成全角，统一回半角，保证 `@ # %` 能被识别。
    static func normalizeSymbols(_ text: String) -> String {
        var s = text
        let mapping: [Character: Character] = [
            "＠": "@", "＃": "#", "％": "%",
            "　": " ", "\r\n": "\n", "\r": "\n"
        ]
        for (full, half) in mapping where full != "\r\n" && full != "\r" {
            s = s.replacingOccurrences(of: String(full), with: String(half))
        }
        s = s.replacingOccurrences(of: "\r\n", with: "\n")
             .replacingOccurrences(of: "\r", with: "\n")
        return s
    }
}
