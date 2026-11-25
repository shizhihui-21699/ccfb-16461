#if canImport(SwiftUI)
import SwiftUI
#if canImport(UIKit)

@MainActor
public final class OTPVerificationViewModel: ObservableObject {
    @Published public var code: String = ""
    @Published public var signals = OTPEntrySignals()
    @Published public private(set) var activePrompt: OTPRiskPrompt?
    @Published public var showPrompt: Bool = false
    @Published public private(set) var isSubmitting = false
    @Published public var errorMessage: String?
    @Published public var verified = false

    public let challengeID: String
    public let officialDomain: OTPDomain
    public var associatedDomainAvailable: Bool
    public var isDesktopWebManualFallback: Bool

    private let service: any OTPVerificationServicing
    private let appVersion: String?
    private let assertionProvider: (() async -> (assertion: Data, keyID: String)?)?

    public init(
        challengeID: String,
        officialDomain: OTPDomain,
        service: any OTPVerificationServicing,
        appVersion: String? = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
        associatedDomainAvailable: Bool = true,
        isDesktopWebManualFallback: Bool = false,
        assertionProvider: (() async -> (assertion: Data, keyID: String)?)? = nil
    ) {
        self.challengeID = challengeID
        self.officialDomain = officialDomain
        self.service = service
        self.appVersion = appVersion
        self.associatedDomainAvailable = associatedDomainAvailable
        self.isDesktopWebManualFallback = isDesktopWebManualFallback
        self.assertionProvider = assertionProvider
    }

    public var canSubmit: Bool {
        BankSMSTemplate.isValidCode(code) && !isSubmitting
    }

    public func codeCompleted(_ completedCode: String) {
        code = completedCode
        requestSubmission()
    }

    public func requestSubmission() {
        guard canSubmit else { return }

        let context = OTPRiskContext(
            entry: signals,
            officialDomain: officialDomain,
            associatedDomainAvailable: associatedDomainAvailable,
            isDesktopWebManualFallback: isDesktopWebManualFallback
        )

        switch ManualEntryRiskPolicy.evaluate(context) {
        case .submitWithoutPrompt:
            Task { await submit() }
        case .requireConfirmation(let prompt):
            activePrompt = prompt
            showPrompt = true
        }
    }

    public func confirmRiskAndSubmit() {
        showPrompt = false
        Task { await submit() }
    }

    public func cancelPrompt() {
        showPrompt = false
        activePrompt = nil
        // Clear a manually entered code after the user chooses to stop. This
        // reduces the chance that a confused user immediately retries into
        // the same phishing flow.
        if signals.manualEditOccurred || signals.pasteOccurred {
            code = ""
            signals.reset()
        }
    }

    private func submit() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        var assertion: Data?
        var keyID: String?
        if let pair = await assertionProvider?() {
            assertion = pair.assertion
            keyID = pair.keyID
        }

        let submission = OTPVerificationSubmission(
            challengeID: challengeID,
            code: code,
            signals: signals,
            appVersion: appVersion,
            appAttestAssertion: assertion,
            appAttestKeyID: keyID
        )

        do {
            let response = try await service.verify(submission)
            if response.verified {
                verified = true
            } else if response.riskAction == .requireStepUp {
                errorMessage = "本次登录需要额外安全验证，请使用银行App扫码或通行密钥完成。"
            } else {
                errorMessage = invalidCodeMessage(response: response)
            }
        } catch {
            errorMessage = "网络或安全校验失败，请稍后通过官方App重试。"
        }
    }

    private func invalidCodeMessage(response: OTPVerificationResponse) -> String {
        if let remaining = response.remainingAttempts {
            return "验证码错误或已过期，还可尝试 \(remaining) 次。"
        }
        return "验证码错误或已过期，请重新获取。"
    }
}

public struct OTPVerificationScreen: View {
    @ObservedObject private var viewModel: OTPVerificationViewModel
    private let codeLength: Int

    public init(viewModel: OTPVerificationViewModel, codeLength: Int = 6) {
        self.viewModel = viewModel
        self.codeLength = codeLength
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("短信验证码")
                    .font(.largeTitle.bold())

                Text("为保护账户安全，验证码仅可在官方 App 或 \(viewModel.officialDomain.rawValue) 使用。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                OTPCodeTextField(
                    code: $viewModel.code,
                    signals: $viewModel.signals,
                    codeLength: codeLength,
                    onCompleted: viewModel.codeCompleted
                )
                .frame(height: 56)
                .padding(.horizontal, 12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                )

                if viewModel.signals.manualEditOccurred {
                    Label("正在手动输入；提交前将要求核对官方域名。", systemImage: "exclamationmark.shield")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }

                Button {
                    viewModel.requestSubmission()
                } label: {
                    if viewModel.isSubmitting {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("下一步").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!viewModel.canSubmit)

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Spacer(minLength: 0)
            }
            .padding(24)
        }
        .alert(
            viewModel.activePrompt?.title ?? "安全提示",
            isPresented: $viewModel.showPrompt,
            presenting: viewModel.activePrompt
        ) { prompt in
            Button(prompt.confirmationButtonTitle) {
                viewModel.confirmRiskAndSubmit()
            }
            Button(prompt.cancelButtonTitle, role: .cancel) {
                viewModel.cancelPrompt()
            }
        } message: { prompt in
            Text(prompt.message)
        }
    }
}
#endif
#endif
