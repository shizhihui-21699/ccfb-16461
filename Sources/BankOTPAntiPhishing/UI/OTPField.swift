#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import Combine

/// SwiftUI 封装的验证码输入组件，自动接入风控策略。
@available(iOS 13.0, *)
public struct OTPField: UIViewRepresentable {

    @Binding public var code: String
    public let expectedBoundDomain: String
    public let trustedDomains: Set<String>
    public let serverSignals: ServerRiskSignals
    public let parsedMessage: SMSOTPMessage?

    /// 风控决策变化时回调（宿主用来弹风险提示）。
    public var onDecision: ((OTPRiskDecision) -> Void)?

    public init(
        code: Binding<String>,
        expectedBoundDomain: String,
        trustedDomains: Set<String>,
        serverSignals: ServerRiskSignals = ServerRiskSignals(),
        parsedMessage: SMSOTPMessage? = nil,
        onDecision: ((OTPRiskDecision) -> Void)? = nil
    ) {
        self._code = code
        self.expectedBoundDomain = expectedBoundDomain
        self.trustedDomains = trustedDomains
        self.serverSignals = serverSignals
        self.parsedMessage = parsedMessage
        self.onDecision = onDecision
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeUIView(context: Context) -> OTPTextField {
        let field = OTPTextField()
        field.delegate = context.coordinator
        field.onPaste = { [weak field] _ in
            context.coordinator.evaluate(for: .paste, field: field)
        }
        field.onAutoFill = { [weak field] _ in
            context.coordinator.evaluate(for: .autoFill, field: field)
        }
        return field
    }

    public func updateUIView(_ uiView: OTPTextField, context: Context) {
        if uiView.text != code { uiView.text = code }
        context.coordinator.parent = self
    }

    public final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: OTPField
        private var lastEvaluatedSource: OTPEntrySource?

        init(_ parent: OTPField) { self.parent = parent }

        public func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            guard let field = textField as? OTPTextField else { return true }
            let current = field.text ?? ""
            let updated = (current as NSString).replacingCharacters(in: range, with: string)
            parent.code = updated

            // 粘贴与自动填充已在专属回调里评估；这里只处理逐字手动输入。
            if field.lastEntrySource == .manual, string.count <= 1 {
                evaluate(for: .manual, field: field)
            }
            return true
        }

        func evaluate(for source: OTPEntrySource, field: OTPTextField?) {
            // 同一次输入不重复弹窗。
            guard source != lastEvaluatedSource || source == .manual else { return }
            lastEvaluatedSource = source

            let policy = OTPRiskPolicy(trustedDomains: parent.trustedDomains)
            let context = OTPEntryContext(
                source: source,
                expectedBoundDomain: parent.expectedBoundDomain,
                parsedMessage: parent.parsedMessage,
                serverSignals: parent.serverSignals
            )
            let decision = policy.evaluate(context)
            if decision.requiresConfirmation || decision.blocksSubmission {
                DispatchQueue.main.async { [onDecision = parent.onDecision] in
                    onDecision?(decision)
                }
            }
        }
    }
}
#endif
