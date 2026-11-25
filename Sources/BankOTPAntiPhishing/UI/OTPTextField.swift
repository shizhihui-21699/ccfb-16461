#if canImport(UIKit)
import UIKit

/// 带输入来源识别的验证码输入框。
///
/// 设计要点：
/// - `textContentType = .oneTimeCode`：让系统接管短信验证码识别与 QuickType 自动填充，
///   域名绑定（iOS 14+）由系统在候选阶段完成，App 无法也不应自己读短信。
/// - 重写 `paste(_:)`：粘贴是可明确识别的独立通道，优先于启发式判断。
/// - 自动填充 vs 手动键入：两者最终都走 `insertText(_:)`，没有公开 API 区分。
///   采用与业界一致的启发式——单次插入完整长度验证码且此前输入框为空 → 自动填充；
///   逐字符插入/删除 → 手动键入。
public final class OTPTextField: UITextField {

    /// 期望的验证码位数。
    public var expectedCodeLength: Int = 6

    /// 最近一次文本变更的来源判断结果。
    public private(set) var lastEntrySource: OTPEntrySource = .manual

    /// 粘贴发生回调（主线程），便于宿主页面埋点与实时提示。
    public var onPaste: ((String) -> Void)?

    /// 自动填充发生回调（主线程）。
    public var onAutoFill: ((String) -> Void)?

    public override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        textContentType = .oneTimeCode          // 系统短信验证码自动填充的总开关
        keyboardType = .numberPad
        autocorrectionType = .no
        autocapitalizationType = .allCharacters
        if #available(iOS 12.0, *) {
            // 让系统知道这是验证码字段；密码样式输入框可避免第三方键盘记录。
            isSecureTextEntry = false
        }
    }

    // MARK: - 粘贴通道（明确可识别）

    public override func paste(_ sender: Any?) {
        let pasted = UIPasteboard.general.string ?? ""
        lastEntrySource = .paste
        onPaste?(pasted)
        super.paste(sender)
    }

    // MARK: - 文本输入通道（自动填充与手动键入共用）

    public override func insertText(_ text: String) {
        let wasEmpty = (self.text ?? "").isEmpty
        let before = self.text

        super.insertText(text)

        let after = self.text ?? ""
        lastEntrySource = classifyInsertion(
            insertedText: text,
            wasEmpty: wasEmpty,
            beforeText: before ?? "",
            afterText: after
        )

        if lastEntrySource == .autoFill {
            onAutoFill?(after)
        }
    }

    public override func deleteBackward() {
        super.deleteBackward()
        // 删除键只能来自人工操作（自动填充不会触发删除）。
        lastEntrySource = .manual
    }

    /// 启发式分类。自动填充的特征是"一次性、整码、落到空框"。
    func classifyInsertion(
        insertedText: String,
        wasEmpty: Bool,
        beforeText: String,
        afterText: String
    ) -> OTPEntrySource {
        let digits = insertedText.filter(\.isNumber)
        // 单次插入即凑齐整码，且插入前为空 → QuickType 自动填充（或扫码/键盘候选整码）。
        if wasEmpty, digits.count == expectedCodeLength, afterText.count >= expectedCodeLength {
            return .autoFill
        }
        // 单次插入多个字符但未凑齐整码，按粘贴类风险对待（保守策略）。
        if insertedText.count > 1 {
            return .paste
        }
        return .manual
    }
}
#endif
