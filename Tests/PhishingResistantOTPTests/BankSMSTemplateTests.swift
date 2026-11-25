import XCTest
@testable import PhishingResistantOTP

final class BankSMSTemplateTests: XCTestCase {
    func testProductionTemplateHasAppleBindingLineAsLastLine() throws {
        let domain = try XCTUnwrap(OTPDomain(strict: "login.bankexample.cn"))
        let message = try BankSMSTemplate.productionLogin.makeMessage(
            code: "483920",
            domain: domain
        )
        let sms = message.render()

        XCTAssertTrue(sms.contains("验证码 483920"))
        XCTAssertTrue(sms.contains("login.bankexample.cn"))
        XCTAssertTrue(sms.hasSuffix("\n\n@login.bankexample.cn #483920"))
        XCTAssertEqual(sms.components(separatedBy: "\n").last,
                       "@login.bankexample.cn #483920")
    }

    func testSameTemplateRemainsReadableOnOldSystems() throws {
        let domain = try XCTUnwrap(OTPDomain("login.bankexample.cn"))
        let sms = try BankSMSTemplate.productionLogin.makeMessage(
            code: "123456",
            domain: domain
        ).render()

        // Old heuristic parsers and humans need the conventional code in the
        // body, not only after the newer '#' marker.
        XCTAssertTrue(sms.contains("验证码 123456"))
        XCTAssertTrue(sms.contains("银行不会索取此验证码"))
        XCTAssertTrue(sms.hasSuffix("@login.bankexample.cn #123456"))
    }

    func testRejectsMalformedCodes() {
        let domain = OTPDomain("login.bankexample.cn")!
        XCTAssertThrowsError(
            try BankSMSTemplate.productionLogin.makeMessage(code: "12 34", domain: domain)
        )
        XCTAssertThrowsError(
            try BankSMSTemplate.productionLogin.makeMessage(code: "abcdef", domain: domain)
        )
    }
}
