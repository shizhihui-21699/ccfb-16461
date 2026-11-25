# 手机银行短信验证码防钓鱼改造（iOS / Swift）

目标：让短信验证码与银行官方域名、官方 App 的 Associated Domains 绑定。iOS 14+ 只在匹配的 Safari 域名或已关联的银行 App 中提供验证码自动填充；手动输入、粘贴、旧系统和电脑网页回退路径给出明确风险提示。

> 重要边界：`@domain #code` 是 **AutoFill 绑定**，不是密码学强认证。它能阻止系统把验证码自动送到仿冒网站，但用户仍可能看着短信手动把码输入钓鱼页。钓鱼页不受银行控制，不会显示 App/网页里的提示。要真正消除实时转发（AiTM）风险，网页高风险登录应逐步升级到通行密钥/Passkey、银行 App 扫码确认或带设备完整性证明的确认。

## 1. 推荐的一次性短信模板

选择一个长期稳定的官方认证域名，例如 `login.bankexample.cn`。模板同时包含：

1. 旧系统和人能读懂的“验证码 123456”；
2. 风险警示；
3. 最后一行严格使用 Apple 域名绑定格式。

```text
【示例银行】您正在进行登录身份验证，验证码 483920，5分钟内有效。请勿向任何人透露，银行不会索取此验证码。本码仅限官方域名 login.bankexample.cn 及官方App使用。

@login.bankexample.cn #483920
```

如果银行主站是 `www.bankexample.cn`，而登录框位于 `auth.bankexample.cn` 的 iframe 中，最后一行改为：

```text
@www.bankexample.cn #483920 %auth.bankexample.cn
```

规则：

- 绑定信息必须在短信**最后一行**；
- 域名前是 `@`，验证码前是 ` #`，两者之间一个空格；
- 不带 `https://`、端口、路径、斜杠或结尾标点；
- 中文/国际化域名必须使用 Punycode（`xn--...`）形式；
- `%` 后只放嵌入式登录 iframe 的域名；
- 域名必须来自服务端固定配置，不能取当前请求的 `Host`/`Origin`；
- 同一条短信兼容 iOS 14+、iOS 12/13 和更老版本，不需要按系统版本切换模板；
- 必须确认运营商/短信平台不会在最后一行之后自动追加“回 T 退订”、链接或签名；否则绑定行不再是最后一行。验证码短信应使用事务类模板，退订/附加文案必须放在绑定行之前或关闭。

运营商模板一旦审核通过，不要为不同系统版本频繁改版。若审核系统不允许同一个 `${code}` 变量出现两次，可定义两个变量，例如 `${code}` 和 `${bindingCode}`，发送时给两者赋同一个验证码值；模板文本仍保持不变。

## 2. 配置 App 与域名的关联

在 Xcode 的 **Signing & Capabilities → Associated Domains** 中添加：

```text
webcredentials:login.bankexample.cn
applinks:login.bankexample.cn
```

本仓库提供了示例：

- `Config/PhoneBank.entitlements`
- `Config/apple-app-site-association`

把 `TEAMID1234.com.example.phonebank` 替换为真实 Team ID 和 Bundle ID，并通过 HTTPS、有效证书、无重定向提供：

```text
https://login.bankexample.cn/.well-known/apple-app-site-association
```

为兼容旧抓取方式，也可在以下地址提供同一份文件：

```text
https://login.bankexample.cn/apple-app-site-association
```

注意 Apple CDN 和设备更新 Associated Domains 缓存可能有延迟；开发期可临时使用：

```text
webcredentials:login.bankexample.cn?mode=developer
```

正式包必须去掉 `?mode=developer`。

## 3. SwiftUI / UIKit 输入框

核心要求只有两行：

```swift
textField.textContentType = .oneTimeCode
textField.keyboardType = .numberPad
```

如果部署目标低于 iOS 12，需要加可用性判断：

```swift
if #available(iOS 12.0, *) {
    textField.textContentType = .oneTimeCode
}
```

本包提供了带输入来源信号的 SwiftUI 控件：

```swift
import SwiftUI
import PhishingResistantOTP

struct LoginOTPView: View {
    @StateObject private var viewModel: OTPVerificationViewModel

    init() {
        let domain = OTPDomain(strict: "login.bankexample.cn")!
        let client = URLSessionOTPVerificationClient(
            endpoint: URL(string: "https://api.bankexample.cn/v1/auth/otp/verify")!
        )
        _viewModel = StateObject(wrappedValue: OTPVerificationViewModel(
            challengeID: "server-created-challenge-id",
            officialDomain: domain,
            service: client
        ))
    }

    var body: some View {
        OTPVerificationScreen(viewModel: viewModel, codeLength: 6)
    }
}
```

`OTPCodeTextField` 会记录：

- 逐字符输入：`.typing`；
- 显式粘贴：`.paste`；
- 非粘贴的整段插入：`.assistedBulkInsert`，通常是系统短信 AutoFill。

iOS 没有公开 API 能让 App 证明“这次填充一定来自域名绑定 AutoFill”。因此这些信号只用于风险提示和服务端风控，不能当作不可伪造的安全边界。

## 4. 手动输入风险策略

`ManualEntryRiskPolicy` 的策略是：

| 场景 | 客户端处理 |
|---|---|
| iOS 14+，非粘贴整段填充 | 通常为域名绑定 AutoFill，不额外打断，上送埋点 |
| iOS 14+，逐字符手动输入 | 提交前弹出官方域名核对 |
| 粘贴验证码 | 提交前弹出风险确认 |
| iOS 12/13 | 系统只有启发式识别，不强制校验域名，任何提交前都提示 |
| iOS 12 以下 | 按纯手动输入处理并提示 |
| 电脑网页手动回退 | 更强提示，要求核对 `https://域名` 和证书 |
| AASA/Entitlement 配置异常 | 严重风险提示，并建议更新/取消 |

提示文案明确告诉用户：

- 验证码只能用于官方 App 和固定域名；
- 银行/客服/公检法不会索取验证码；
- 不要把验证码转发给任何人；
- 可疑时停止并通过官方渠道回拨核实。

## 5. 电脑网页怎么办

桌面浏览器通常无法利用 iPhone 本地 App 的自动填充；即使用户用 iPhone 收到短信，也往往需要手动输入。网页输入框应设置：

```html
<input autocomplete="one-time-code" inputmode="numeric"
       pattern="[0-9]{6}" maxlength="6">
```

示例风险拦截脚本见 `Web/otp-input.example.html`。但必须承认：钓鱼网站不会部署银行的提示脚本，所以网页脚本只能保护“用户确实在官方网页手动输入”的场景。

桌面网页的优先演进方案：

1. **Passkey / WebAuthn**：浏览器把凭据绑定到 RP ID/域名，钓鱼域名无法使用银行凭据，是更强的抗钓鱼方案；
2. **手机银行 App 扫码确认**：二维码绑定服务端登录会话，App 展示登录地点、设备、时间等上下文，并使用生物识别和 App Attest；
3. **推送 + 数字匹配**：作为过渡，但仍需防止攻击者实时转发页面内容；
4. 对不支持上述方式的用户，保留短信手动输入，但进行域名、证书和防诈骗提示，并在服务端提高风控等级。

## 6. 服务端必须配合的事项

客户端提示不能替代服务端安全控制。

### 6.1 Challenge 绑定

- 每次登录先生成一次性 `challenge_id` / `auth_session_id`；
- 验证码只对该 challenge、手机号、用途（登录/转账/改设备）有效；
- 服务端只存验证码哈希，例如 HMAC-SHA256 或 Argon2id；
- 设置短有效期、最大错误次数、验证成功后立即消费；
- 验证接口使用 HTTPS、防重放、限流和异常设备/IP 风控。

这不能阻止攻击者把受害者输入的码实时转发给真网站，但能防止验证码被跨会话、跨用途重用。

### 6.2 上送客户端信号

`OTPVerificationSubmission` 已包含：

```json
{
  "challengeID": "chk_...",
  "code": "123456",
  "entryMethod": "typing",
  "manualEditOccurred": true,
  "pasteOccurred": false,
  "bulkInsertOccurred": false,
  "bindingSupport": "domainBound",
  "platform": "ios",
  "osVersion": "26.0.0",
  "appVersion": "8.4.0"
}
```

这些字段可被篡改，只作为风控特征。高风险操作应要求不可伪造的 App Attest 断言。

### 6.3 App Attest 示例骨架

```swift
import DeviceCheck
import CryptoKit

actor AppAttestSigner {
    private let service = DCAppAttestService.shared
    private var keyID: String?

    func assertion(forServerChallenge challenge: Data) async throws -> (Data, String) {
        let id: String
        if let keyID {
            id = keyID
        } else {
            id = try await service.generateKey()
            keyID = id

            // 首次安装：
            // 1. 从服务端取一次性 attestation challenge；
            // 2. let hash = Data(SHA256.hash(data: challenge))
            // 3. let attestation = try await service.attestKey(id, clientDataHash: hash)
            // 4. 把 attestation 发给服务端，由服务端校验 Apple 证书链。
        }

        let clientDataHash = Data(SHA256.hash(data: challenge))
        let assertion = try await service.generateAssertion(
            keyID: id,
            clientDataHash: clientDataHash
        )
        return (assertion, id)
    }
}
```

服务端验证 App Attest 后，可以对“官方 App 内确认”和“无完整性证明的网页/脚本提交”采用不同风险策略。

## 7. iOS 27+ 的可选增强

iOS/iPadOS 27 与 macOS 27 新增了 `ASDeliveredVerificationCodesManager`，其 `ASVerificationCode` 暴露系统解析出的 `code`、`domain` 和 `embeddedDomains`。但 Apple 文档注明 `oneTimeCodes(...)` **仅限已启用的凭据提供方调用**，并可能需要用户授权。因此普通手机银行 App 仍应使用下面的 iOS 14 域名绑定模板和 `.oneTimeCode`；只有在银行同时提供并启用 Credential Provider 扩展、且使用 Xcode 27 SDK 构建时，才把该 API 作为增强：

- `domain == "login.bankexample.cn"` 且 `embeddedDomains` 全部属于银行白名单：才自动填入/提交；
- `domain == nil`：按旧系统/启发式验证码处理，要求手动风险确认；
- 域名不在白名单：不要自动提交，提示用户当前短信码可能正被用于钓鱼站点。

该 API 不能替代本方案：短信最后一行的 `@domain #code`、Associated Domains 和 `.oneTimeCode` 仍需保留，以覆盖 iOS 14–26 以及桌面网页用户。

## 8. 测试矩阵

至少覆盖：

| 用例 | 预期 |
|---|---|
| iOS 14+ 真域名 Safari | QuickType 出现域名绑定验证码并可填充 |
| iOS 14+ 仿冒/近似域名 Safari | 不出现该域名绑定码的自动填充 |
| iOS 14+ 官方 App | AASA 生效后可自动填充 |
| iOS 14+ App 中手动输入完整码 | 提交前弹风险确认 |
| 粘贴验证码 | 弹风险确认 |
| 自动填充后手动改一位 | 视为手动干预并提示 |
| iOS 12/13 | `oneTimeCode` 可启发式填充，但提交前提示旧系统无域名强绑定 |
| 电脑浏览器 | `autocomplete=one-time-code` 正常；手动输入有网页提示 |
| iframe 登录域 | `%auth...` 后缀按 Apple 文档验证 |
| AASA 未部署/缓存未更新 | 配置异常提示且监控可见 |
| 运营商短信 | 最后一行未被签名、退订文案或标点破坏 |
| 运营商自动追加“回T退订” | 不得出现在 `@domain #code` 之后，否则绑定失效 |

真机测试前确认：

```text
https://login.bankexample.cn/.well-known/apple-app-site-association
```

返回 `200`、`Content-Type: application/json`、合法证书且无重定向。

## 9. 发布顺序

1. 确定长期稳定的认证域名和 iframe 域名；
2. 部署 AASA，配置 Associated Domains；
3. 向运营商/短信平台提交并冻结通用模板；
4. 发布带 `.oneTimeCode`、输入来源识别和风险弹窗的 App；
5. 服务端发布 challenge 绑定、限流、哈希存储和风险埋点；
6. 小范围验证真域名、仿冒域名、旧系统和桌面回退；
7. 逐步为网页高风险登录增加 Passkey/App 扫码确认。

## 10. 本仓库代码

- `Sources/PhishingResistantOTP/OTPDomain.swift`：域名校验与系统版本支持级别；
- `Sources/PhishingResistantOTP/BankSMSTemplate.swift`：稳定短信模板和严格最后一行；
- `Sources/PhishingResistantOTP/OTPCodeTextField.swift`：UIKit/SwiftUI 验证码输入与输入来源识别；
- `Sources/PhishingResistantOTP/ManualEntryRiskPolicy.swift`：手动/粘贴/旧系统/桌面风险策略；
- `Sources/PhishingResistantOTP/OTPVerificationScreen.swift`：可直接接入的 SwiftUI 页面和 ViewModel；
- `Sources/PhishingResistantOTP/OTPVerificationSubmission.swift`：上送服务端的遥测模型；
- `Web/otp-input.example.html`：桌面网页回退示例；
- `Config/`：Entitlements 和 AASA 示例。

当前机器只有 Command Line Tools、没有完整 Xcode/XCTest，因此已用 `swift build` 和独立编译断言验证核心逻辑；单元测试文件保留在 `Tests/`，可在安装 Xcode 的环境中执行 `swift test` 或在 Xcode 内运行。

## 参考资料

- Apple: [Enabling AutoFill for domain-bound SMS codes](https://developer.apple.com/documentation/security/enabling-autofill-for-domain-bound-sms-codes)
- Apple: [One-time codes](https://developer.apple.com/documentation/security/one-time-codes)
- Apple: [Supporting associated domains](https://developer.apple.com/documentation/xcode/supporting-associated-domains)
- Apple: [Configuring an associated domain](https://developer.apple.com/documentation/Xcode/configuring-an-associated-domain)
- Apple: [`ASVerificationCode`](https://developer.apple.com/documentation/authenticationservices/asverificationcode)
- Apple: [`ASDeliveredVerificationCodesManager`](https://developer.apple.com/documentation/authenticationservices/asdeliveredverificationcodesmanager)
