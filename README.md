# 手机银行短信验证码防钓鱼改造方案（iOS / Swift）

## 1. 威胁模型：攻击者是怎么得手的

这是典型的 **AiTM（Adversary-in-the-Middle，攻击者中继）钓鱼**，不是普通的假网站骗密码：

```
受害者手机                仿冒网站(攻击者)              真实银行
    │                           │                         │
    │ 1. 输入账号/密码 ─────────▶│                         │
    │                           │ 2. 同步用真凭据登录 ────▶│
    │                           │ ◀──── 下发短信验证码 ───│
    │ ◀── 3. 银行短信（确实是银行发的）│                    │
    │ 4. 在仿冒页填入验证码 ────▶│                         │
    │                           │ 5. 把验证码中继给真站 ──▶│
    │                           │ ◀──────── 登录成功 ─────│
```

要害在于：**短信是真的、验证码是真的、甚至发件号码也是真的**，唯一假的是输入场所。
所以防御的着力点不是"识别假短信"，而是**让验证码与银行的域名/App 强绑定，并且对"手动输入"这个唯一还能被利用的通道加风险控制**。

## 2. 先纠正一个常见误解：iOS 到底提供了什么

调研了 Apple 官方文档、WebKit 博客和 iOS 18～26 的发布材料后，需要明确：
**iOS 没有"在钓鱼网站上弹系统级跨域警告"的公开功能。** 它的机制是静默的——不匹配就不给候选。

| 系统版本 | 能力 | 对本方案的意义 |
|---|---|---|
| iOS 11 及以下 | 无短信验证码自动填充 | 只能手动输入，系统层零防护，全部靠 App/服务端风控 |
| iOS 12/13 | Security Code AutoFill：`oneTimeCode` 字段识别短信验证码并推 QuickType 栏 | **不做域名绑定**，钓鱼站放个同类型输入框就能骗到自动填充 |
| **iOS 14+**（含 macOS 11 Big Sur+） | **域名绑定短信**：最后一行 `@域名 #验证码`；系统只在 Safari 当前域名或 App 关联域匹配时才给自动填充候选 | 核心防线。钓鱼域/恶意 App 里**候选根本不出现**，而不是弹警告 |
| iOS 17+ | 自动填充后可自动删除验证码短信 | 减少残留，属清理向能力 |
| iOS 18～26 | 公开文档未记载新增短信 OTP 跨域弹窗；绑定模型沿用 iOS 14 | 不要把安全承诺建立在不存在的系统弹窗上 |

> 结论：**"系统只在真页面/真 App 自动填充"靠 iOS 14 的域名绑定实现；"手动输入时提示风险"必须由 App 自己实现。** 本方案代码严格按这个真实边界设计。

## 3. 整体架构：四层纵深防御

```
┌─────────────────────────────────────────────────────────────┐
│ 第 1 层 短信模板绑定  最后一行 @bank.example #123456          │
│         （服务端/运营商侧，一次送审，系统自动识别）             │
├─────────────────────────────────────────────────────────────┤
│ 第 2 层 系统域名校验  iOS 14+ 域名不匹配 → QuickType 无候选    │
│         + App 关联域 webcredentials + AASA 文件双向确认        │
├─────────────────────────────────────────────────────────────┤
│ 第 3 层 App 输入风控  区分 自动填充/粘贴/手动，分级提示与阻断   │
│         （OTPTextField + OTPRiskPolicy，本仓库代码）           │
├─────────────────────────────────────────────────────────────┤
│ 第 4 层 服务端反中继  重复申请、异地、设备指纹、一次性消费校验   │
│         + 桌面端用扫码/推送/passkey 替代手动输入               │
└─────────────────────────────────────────────────────────────┘
```

任何单层都有盲区，四层叠加才能覆盖"旧机型、电脑网页、手动输入、系统 API 不透明"这些缺口。

## 4. 代码结构

```
Sources/BankOTPAntiPhishing/
├── Core/                         # 纯逻辑，不依赖 UIKit，可在 macOS/Linux 单测
│   ├── OTPCapability.swift       # 系统版本能力矩阵（iOS 12/14/17 分层）
│   ├── SMSOTPParser.swift        # 短信解析 + 送审模板合规自检（兼容全角符号/老模板）
│   └── OTPRiskPolicy.swift       # 三分类输入来源 + 分级风控决策
└── UI/                           # #if canImport(UIKit) 隔离，仅 iOS 编译
    ├── OTPTextField.swift        # UIKit：拦截 paste、启发式区分自动填充与手动
    ├── OTPField.swift            # SwiftUI 封装，自动接风控策略
    └── OTPLoginDemoView.swift    # 完整演示页（风险弹窗 + 桌面端降级引导）
Config/
├── BankApp.entitlements          # webcredentials/applinks 关联域配置
├── apple-app-site-association.json  # 部署到 https://bank.example/.well-known/
├── web-login-sample.html         # 网页端 autocomplete="one-time-code"
└── sms-templates.txt             # 运营商送审模板与反面案例
Tests/OTPTestRunner/main.swift    # 37 条断言（零依赖，swift run 即可跑）
```

## 5. 三个难点的具体应对

### 难点 A：不同系统版本对绑定格式支持不一致

- **能力收敛在 `OTPCapability` 一处**，所有策略判断只依赖它，不散落 `#available`。
- iOS 14+：吃域名绑定红利，钓鱼侧拿不到自动填充候选。
- iOS 12/13：有自动填充但无绑定，`OTPRiskPolicy` 对手动/粘贴输入直接升到**高风险强提示**，并在文案里告诉用户当前系统无法自动核验页面真伪。
- iOS 11 及以下：无自动填充，引导走 App 内推送确认，不鼓励在网页手动输码。
- 短信解析对**全角 `＠＃`、CRLF、通道变体做归一化**，避免老机型/通道转码导致绑定失效。

### 难点 B：电脑网页端只能手动输入

系统级域名绑定只在 Apple 生态的 Safari/关联 App 内生效，PC 浏览器（尤其 Windows）没有等价物。方案不是硬堵，而是**给替代通道把人迁走**（见 `OTPLoginDemoView.DesktopFallbackView`）：

1. 扫码登录：PC 展示二维码，手机 App 扫码 + Face ID 确认，PC 全程不碰验证码；
2. App 推送授权：PC 发起登录，手机弹窗展示登录详情，一键批准；
3. passkey（通行密钥）：FIDO2 协议天然抗钓鱼，钓鱼站拿不到可用凭证，是短信 OTP 的长期替代品；
4. 确实只能手动输码时：网页提示核对地址栏域名，服务端风控（第 4 层）从严。

### 难点 C：短信模板要运营商审核、不能频繁改

- **模板里只有 `${code}` 是变量，绑定行格式恒定**，按一次送审长期使用，不存在频繁变更。
- 送审前用 `SMSOTPParser.checkTemplate(_:)` 自检，能机器拦下三类最常见的上线事故：
  通道签名追加到绑定行之后（绑定行离开最后一行）、域名带了 `https://`、验证码长度不符。
- 与短信通道合同里明确：**签名/营销内容只能前置，禁止尾部追加**；上线后用真实下发短信回归测试。
- 域名用稳定主域（`bank.example`），子域用 `auth.bank.example` 并在关联域里逐一声明，避免以后换域要重新送审。

## 6. 关键实现说明与局限（务必知悉）

1. **App 无法读取短信内容**（iOS 无公开 API），域名匹配由系统在 QuickType 候选阶段完成。`SMSOTPParser` 的用途是：服务端模板校验、测试、以及服务端把本次短信元数据透传给 App 时的解析。
2. **系统没有公开 API 告知"这次文本变更是自动填充还是手动"**。两者都走 `insertText(_:)`。`OTPTextField` 采用业界通用启发式：空框单次插入整码 → 自动填充；逐字符 → 手动；重写 `paste(_:)` 精确捕获粘贴。启发式有误判空间，所以它只用于**风险提示分级**，阻断性决策由服务端信号兜底。
3. **自动填充不等于绝对安全**：若用户设备本身被恶意描述文件/越狱环境劫持，绑定可能被绕过。高风险操作（转账、改密）仍需服务端二次核验。
4. 短信 OTP 本质是可钓鱼因子，本方案是**降低被钓成功率的缓解措施**；战略上应按 [WWDC24 Session 10125](https://developer.apple.com/videos/play/wwdc2024/10125) 的路线推进 passkey 迁移。

## 7. 验证方式

```bash
swift test            # 有完整 Xcode 的环境（改回 .testTarget）
swift run OTPTestRunner   # 本机（仅 Command Line Tools）已验证：37/37 断言通过
```

真机验证要点：把模板短信发给自己，长按验证码若出现"拷贝验证码"且 QuickType 仅在银行 App/官网出现候选，即绑定生效；在任意非关联 App 的输入框里候选应消失。

## 参考来源（均为官方/一手材料）

- [Enabling AutoFill for domain-bound SMS codes — Apple Developer](https://developer.apple.com/documentation/security/enabling-autofill-for-domain-bound-sms-codes)（绑定格式、iOS 14/macOS 11 版本要求、iframe `%` 语法）
- [About the Password AutoFill workflow — Apple Developer](https://developer.apple.com/documentation/security/about-the-password-autofill-workflow)（自动填充走普通文本变更通道、3 分钟候选窗口）
- [Configuring an associated domain — Apple Developer](https://developer.apple.com/documentation/xcode/configuring-an-associated-domain)（webcredentials/applinks 前缀、AASA、CDN 机制）
- [Supporting associated domains — Apple Developer](https://developer.apple.com/documentation/xcode/supporting-associated-domains)（AASA 文件格式与部署路径）
- [Streamline sign-in with passkey upgrades and credential managers — WWDC24 10125](https://developer.apple.com/videos/play/wwdc2024/10125)（短信等可钓鱼因子向 passkey 迁移路线）
- [WebKit Features in Safari 18.0](https://www.webkit.org/blog/15865/webkit-features-in-safari-18-0/) / [Safari 26.0](https://webkit.org/blog/17333/webkit-features-in-safari-26-0/)（核实后续版本未新增短信 OTP 系统弹窗）
