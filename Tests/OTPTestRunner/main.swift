import Foundation
import BankOTPAntiPhishing

/// 极简断言框架（无 XCTest 依赖，便于在只有 Command Line Tools 的环境运行）。
/// 测试程序单线程执行，`nonisolated(unsafe)` 在此场景下安全。
nonisolated(unsafe) var failureCount = 0
nonisolated(unsafe) var testCount = 0

func expect(_ condition: Bool, _ message: String, file: StaticString = #fileID, line: UInt = #line) {
    testCount += 1
    if condition { return }
    failureCount += 1
    print("✗ FAIL \(file):\(line) — \(message)")
}

func expectEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String,
                               file: StaticString = #fileID, line: UInt = #line) {
    testCount += 1
    if lhs == rhs { return }
    failureCount += 1
    print("✗ FAIL \(file):\(line) — \(message) (got \(lhs), want \(rhs))")
}

func expectEqual<T: Equatable>(_ lhs: T?, _ rhs: T?, _ message: String,
                               file: StaticString = #fileID, line: UInt = #line) {
    testCount += 1
    if lhs == rhs { return }
    failureCount += 1
    print("✗ FAIL \(file):\(line) — \(message) (got \(String(describing: lhs)), want \(String(describing: rhs)))")
}

// MARK: - 解析器测试

let parser = SMSOTPParser(expectedCodeLength: 6)

do {
    let sms = """
    【示例银行】您正在登录手机银行，验证码 123456，5 分钟内有效，请勿泄露。

    @bank.example #123456
    """
    let r = parser.parse(sms)
    expectEqual(r?.boundDomain, "bank.example", "绑定域名解析")
    expectEqual(r?.code, "123456", "验证码解析")
    expect(r?.isDomainBound == true, "识别为域名绑定短信")
}

do {
    let r = parser.parse("您的验证码 654321\n@bank.example #654321 %iframe-auth.example.org")
    expectEqual(r?.boundDomain, "bank.example", "iframe 场景主域名")
    expectEqual(r?.iframeDomains, ["iframe-auth.example.org"], "iframe 附加域名")
    expectEqual(r?.code, "654321", "iframe 场景验证码")
}

do {
    let r = parser.parse("【示例银行】验证码：246810，请勿向任何人透露。")
    expectEqual(r?.boundDomain, nil, "老模板无绑定域名")
    expectEqual(r?.code, "246810", "老模板回退提取纯数字验证码")
}

do {
    let r = parser.parse("验证码 135790\n＠bank.example　＃135790")
    expectEqual(r?.boundDomain, "bank.example", "全角＠归一化")
    expectEqual(r?.code, "135790", "全角＃归一化")
}

do {
    expectEqual(parser.checkTemplate("登录验证码 123456\n@bank.example #123456"), .ok, "合规模板")
}

do {
    let check = parser.checkTemplate("验证码 123456\n@bank.example #123456\n【示例银行】")
    expect(check.contains(.bindingLineNotLast), "通道尾巴把绑定行顶离最后一行")
    expect(check.contains(.trailingContentAfterBindingLine), "识别末尾额外内容")
}

do {
    let check = parser.checkTemplate("验证码 123456\n@https://bank.example #123456")
    expect(check.contains(.domainNotBareDNS), "拒绝带协议头的域名")
}

do {
    let check = parser.checkTemplate("验证码 1234\n@bank.example #1234")
    expect(check.contains(.codeOutOfPolicy), "拒绝长度不符的验证码")
}

// MARK: - 风控策略测试

let trusted: Set<String> = ["bank.example", "auth.bank.example"]
let policy = OTPRiskPolicy(trustedDomains: trusted)

func makeContext(
    _ source: OTPEntrySource,
    osVersion: Int = 17,
    parsed: SMSOTPMessage? = nil,
    signals: ServerRiskSignals = ServerRiskSignals()
) -> OTPEntryContext {
    OTPEntryContext(
        source: source,
        expectedBoundDomain: "bank.example",
        parsedMessage: parsed,
        capability: OTPCapability(majorSystemVersion: osVersion),
        serverSignals: signals
    )
}

expectEqual(policy.evaluate(makeContext(.autoFill)).level, .low, "自动填充低风险")
expect(policy.evaluate(makeContext(.autoFill)).requiresConfirmation == false, "自动填充不弹窗")
expectEqual(policy.evaluate(makeContext(.manual, osVersion: 17)).level, .medium, "新系统手动输入中风险")
expect(policy.evaluate(makeContext(.manual, osVersion: 17)).requiresConfirmation, "手动输入需二次确认")
expectEqual(policy.evaluate(makeContext(.paste, osVersion: 17)).level, .medium, "粘贴中风险")
expectEqual(policy.evaluate(makeContext(.manual, osVersion: 13)).level, .high, "iOS 13 无系统绑定防线，手动输入高风险")

do {
    let phishing = SMSOTPMessage(
        boundDomain: "bank-example.evil.cn",
        iframeDomains: [],
        code: "123456",
        rawText: "@bank-example.evil.cn #123456"
    )
    let d = policy.evaluate(makeContext(.autoFill, parsed: phishing))
    expectEqual(d.level, .high, "绑定域名与银行不一致 → 高风险")
    expect(d.message.contains("bank-example.evil.cn"), "风险文案点出钓鱼域名")
}

do {
    let sms = SMSOTPMessage(
        boundDomain: "auth.bank.example",
        iframeDomains: [],
        code: "123456",
        rawText: "@auth.bank.example #123456"
    )
    expectEqual(policy.evaluate(makeContext(.autoFill, parsed: sms)).level, .low, "受信子域放行")
}

do {
    var signals = ServerRiskSignals()
    signals.codeAlreadyConsumed = true
    let d = policy.evaluate(makeContext(.autoFill, signals: signals))
    expect(d.blocksSubmission, "验证码已消费 → 直接阻断")
    expectEqual(d.level, .high, "阻断为高风险")
}

do {
    var signals = ServerRiskSignals()
    signals.duplicateOTPRequest = true
    signals.impossibleTravel = true
    let d = policy.evaluate(makeContext(.manual, signals: signals))
    expectEqual(d.level, .high, "服务端信号升级为高风险")
    expect(d.message.contains("重复申请"), "文案包含重复申请")
    expect(d.message.contains("登录地点异常"), "文案包含地点异常")
}

// MARK: - 系统能力矩阵测试

expect(OTPCapability(majorSystemVersion: 11).supportsPlainCodeAutoFill == false, "iOS 11 无自动填充")
expect(OTPCapability(majorSystemVersion: 12).supportsPlainCodeAutoFill, "iOS 12 起支持普通验证码自动填充")
expect(OTPCapability(majorSystemVersion: 13).supportsDomainBoundAutoFill == false, "iOS 13 不支持域名绑定")
expect(OTPCapability(majorSystemVersion: 14).supportsDomainBoundAutoFill, "iOS 14 起支持域名绑定")
expect(OTPCapability(majorSystemVersion: 14).domainBindingIsEnforcedByOS, "iOS 14 系统层强制绑定匹配")
expect(OTPCapability(majorSystemVersion: 13).domainBindingIsEnforcedByOS == false, "iOS 13 系统层无绑定防线")
expect(OTPCapability(majorSystemVersion: 17).supportsAutoCleanup, "iOS 17 起支持验证码短信自动清理")
expect(OTPCapability(majorSystemVersion: 16).supportsAutoCleanup == false, "iOS 16 无自动清理")

// MARK: - 结果汇总

print("──")
if failureCount == 0 {
    print("✅ 全部 \(testCount) 条断言通过")
} else {
    print("❌ \(failureCount)/\(testCount) 条断言失败")
    exit(EXIT_FAILURE)
}
