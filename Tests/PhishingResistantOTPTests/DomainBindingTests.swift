import XCTest
@testable import PhishingResistantOTP

final class DomainBindingTests: XCTestCase {
    func testNormalizesURLToBareDomain() {
        XCTAssertEqual(OTPDomain("https://login.bankexample.cn/otp?x=1")?.rawValue,
                       "login.bankexample.cn")
    }

    func testAcceptsAtPrefixedDomain() {
        XCTAssertEqual(OTPDomain("@login.bankexample.cn")?.rawValue,
                       "login.bankexample.cn")
    }

    func testRejectsInvalidDomains() {
        XCTAssertNil(OTPDomain(nil))
        XCTAssertNil(OTPDomain(""))
        XCTAssertNil(OTPDomain("not a domain"))
        XCTAssertNil(OTPDomain("*.bankexample.cn"))
        XCTAssertNil(OTPDomain("bankexample"))
        XCTAssertNil(OTPDomain("bankexample.cn:8443"))
    }

    func testURLUserInfoDoesNotMasqueradeAsBankDomain() {
        XCTAssertEqual(
            OTPDomain("https://login.bankexample.cn@evil.test/path")?.rawValue,
            "evil.test"
        )
    }

    func testStrictInitializerRejectsURLAndPort() {
        XCTAssertNil(OTPDomain(strict: "https://login.bankexample.cn"))
        XCTAssertNil(OTPDomain(strict: "login.bankexample.cn/path"))
        XCTAssertNil(OTPDomain(strict: "login.bankexample.cn:443"))
        XCTAssertEqual(OTPDomain(strict: "login.bankexample.cn")?.rawValue,
                       "login.bankexample.cn")
    }

    func testBindingLineMatchesAppleGrammar() throws {
        let domain = try XCTUnwrap(OTPDomain("login.bankexample.cn"))
        let iframe = OTPDomain("auth.bankexample.cn")
        let message = BoundSMSMessage(
            code: "123456",
            domain: domain,
            iframeDomain: iframe,
            introduction: "Your code is 123456."
        )

        XCTAssertEqual(message.bindingLine,
                       "@login.bankexample.cn #123456 %auth.bankexample.cn")
        XCTAssertTrue(message.render().hasSuffix(message.bindingLine))
    }
}
