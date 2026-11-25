import XCTest
@testable import PhishingResistantOTP

final class ManualEntryRiskPolicyTests: XCTestCase {
    let domain = OTPDomain("login.bankexample.cn")!

    func testModernSystemAssistedBulkFillDoesNotWarn() {
        var signals = OTPEntrySignals()
        signals.recordBulkInsertWasPaste(false)

        let context = OTPRiskContext(
            bindingSupport: .domainBound,
            entry: signals,
            officialDomain: domain
        )

        XCTAssertEqual(ManualEntryRiskPolicy.evaluate(context), .submitWithoutPrompt)
    }

    func testTypingOnModernSystemRequiresConfirmation() {
        var signals = OTPEntrySignals()
        signals.recordSingleCharacterEdit()

        let context = OTPRiskContext(
            bindingSupport: .domainBound,
            entry: signals,
            officialDomain: domain
        )

        guard case .requireConfirmation(let prompt) = ManualEntryRiskPolicy.evaluate(context) else {
            return XCTFail("Expected manual-entry confirmation")
        }
        XCTAssertEqual(prompt.severity, .warning)
        XCTAssertTrue(prompt.message.contains("login.bankexample.cn"))
    }

    func testPasteRequiresConfirmation() {
        var signals = OTPEntrySignals()
        signals.recordPaste()

        let context = OTPRiskContext(
            bindingSupport: .domainBound,
            entry: signals,
            officialDomain: domain
        )

        guard case .requireConfirmation = ManualEntryRiskPolicy.evaluate(context) else {
            return XCTFail("Expected paste confirmation")
        }
    }

    func testOldIOSRequiresConfirmationEvenForAssistedFill() {
        var signals = OTPEntrySignals()
        signals.recordBulkInsertWasPaste(false)

        let context = OTPRiskContext(
            bindingSupport: .heuristicOnly,
            entry: signals,
            officialDomain: domain
        )

        guard case .requireConfirmation(let prompt) = ManualEntryRiskPolicy.evaluate(context) else {
            return XCTFail("Expected legacy OS confirmation")
        }
        XCTAssertTrue(prompt.title.contains("不支持域名级"))
    }

    func testDesktopFallbackRequiresCriticalConfirmation() {
        let context = OTPRiskContext(
            bindingSupport: .domainBound,
            officialDomain: domain,
            isDesktopWebManualFallback: true
        )

        guard case .requireConfirmation(let prompt) = ManualEntryRiskPolicy.evaluate(context) else {
            return XCTFail("Expected desktop confirmation")
        }
        XCTAssertEqual(prompt.severity, .critical)
        XCTAssertTrue(prompt.confirmationButtonTitle.contains("https://"))
    }

    func testBrokenAssociatedDomainRequiresCriticalConfirmation() {
        let context = OTPRiskContext(
            bindingSupport: .domainBound,
            officialDomain: domain,
            associatedDomainAvailable: false
        )

        guard case .requireConfirmation(let prompt) = ManualEntryRiskPolicy.evaluate(context) else {
            return XCTFail("Expected configuration confirmation")
        }
        XCTAssertEqual(prompt.severity, .critical)
    }
}
