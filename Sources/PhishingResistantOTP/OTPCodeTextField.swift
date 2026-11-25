#if canImport(SwiftUI)
import SwiftUI
#if canImport(UIKit)
import UIKit

/// A numeric one-time-code field that enables SMS AutoFill and records
/// whether the current value was typed, pasted, or bulk-inserted.
///
/// Use it in a SwiftUI screen:
///
/// ```swift
/// @State private var code = ""
/// @State private var signals = OTPEntrySignals()
///
/// OTPCodeTextField(code: $code, signals: $signals, codeLength: 6) { code in
///     Task { await viewModel.submit(code: code, signals: signals) }
/// }
/// ```
///
/// The signal is a risk hint only; iOS does not expose a public,
/// unforgeable “this came from domain-bound AutoFill” callback.
public struct OTPCodeTextField: UIViewRepresentable {
    @Binding private var code: String
    @Binding private var signals: OTPEntrySignals
    private let codeLength: Int
    private let onCompleted: ((String) -> Void)?

    public init(
        code: Binding<String>,
        signals: Binding<OTPEntrySignals>,
        codeLength: Int = 6,
        onCompleted: ((String) -> Void)? = nil
    ) {
        self._code = code
        self._signals = signals
        self.codeLength = codeLength
        self.onCompleted = onCompleted
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    public func makeUIView(context: Context) -> ReportingTextField {
        let textField = ReportingTextField(frame: .zero)
        textField.delegate = context.coordinator
        textField.keyboardType = .numberPad
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.spellCheckingType = .no
        textField.smartQuotesType = .no
        textField.smartDashesType = .no
        textField.textContentType = .oneTimeCode
        textField.placeholder = "6位验证码"
        textField.font = .monospacedSystemFont(ofSize: 22, weight: .semibold)
        textField.clearButtonMode = .whileEditing
        textField.onPaste = { [weak textField] in
            context.coordinator.pasteInProgress = true
            textField?.pasteWasInvoked = true
        }
        textField.addTarget(
            context.coordinator,
            action: #selector(Coordinator.editingChanged(_:)),
            for: .editingChanged
        )
        return textField
    }

    public func updateUIView(_ uiView: ReportingTextField, context: Context) {
        if uiView.text != code {
            uiView.text = code
        }
        context.coordinator.parent = self
    }

    public final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: OTPCodeTextField
        var pasteInProgress = false
        private var hasReportedCompletion = false

        init(parent: OTPCodeTextField) {
            self.parent = parent
        }

        public func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            let current = textField.text ?? ""
            guard let textRange = Range(range, in: current) else { return false }
            let candidate = current.replacingCharacters(in: textRange, with: string)
            let digits = candidate.filter { $0.isASCII && $0.isNumber }

            guard digits.count <= parent.codeLength else { return false }

            let replacementDigits = string.filter { $0.isASCII && $0.isNumber }

            if replacementDigits.count > 1 {
                parent.signals.recordBulkInsertWasPaste(pasteInProgress)
            } else if !string.isEmpty {
                parent.signals.recordSingleCharacterEdit()
            } else {
                // Deletion/cut is also a manual editing signal.
                parent.signals.recordSingleCharacterEdit()
            }

            pasteInProgress = false

            // Let UIKit display only normalized digits.
            if candidate != digits {
                textField.text = digits
                parent.code = digits
                return false
            }
            return true
        }

        @objc func editingChanged(_ textField: UITextField) {
            let digits = (textField.text ?? "").filter { $0.isASCII && $0.isNumber }
            if textField.text != digits {
                textField.text = digits
            }
            parent.code = digits

            if digits.count < parent.codeLength {
                hasReportedCompletion = false
            } else if digits.count == parent.codeLength, !hasReportedCompletion {
                hasReportedCompletion = true
                parent.onCompleted?(digits)
            }
        }

        public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }
}

final class ReportingTextField: UITextField {
    var onPaste: (() -> Void)?
    var pasteWasInvoked = false

    override func paste(_ sender: Any?) {
        onPaste?()
        super.paste(sender)
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)) {
            // Keep paste available; the override records it.
            return super.canPerformAction(action, withSender: sender)
        }
        return super.canPerformAction(action, withSender: sender)
    }
}
#endif
#endif
