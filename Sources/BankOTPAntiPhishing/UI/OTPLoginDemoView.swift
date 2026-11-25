#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI

/// 验证码登录演示页：展示"自动填充直过、手动/粘贴弹风险提示、高风险阻断"的完整链路。
@available(iOS 13.0, *)
struct OTPLoginDemoView: View {
    let trustedDomains: Set<String>
    let expectedDomain: String

    @State private var code = ""
    @State private var decision: OTPRiskDecision?
    @State private var showDesktopFallback = false
    @State private var serverSignals = ServerRiskSignals()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("短信验证码登录")
                    .font(.title2).bold()

                Text("系统会在本行官方 App / \(expectedDomain) 页面自动填充验证码；手动输入将进行风险提示。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                OTPField(
                    code: $code,
                    expectedBoundDomain: expectedDomain,
                    trustedDomains: trustedDomains,
                    serverSignals: serverSignals,
                    onDecision: { decision = $0 }
                )
                .frame(height: 52)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)

                Button(action: submit) {
                    Text("登录")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(code.count != 6)

                Button("在电脑网页上登录？（收不到自动填充的降级方案）") {
                    showDesktopFallback = true
                }
                .font(.footnote)

                // 测试用：模拟服务端风控信号
                VStack(alignment: .leading, spacing: 6) {
                    Text("测试开关（模拟服务端信号）").font(.footnote).bold()
                    Toggle("重复申请验证码", isOn: $serverSignals.duplicateOTPRequest)
                    Toggle("设备/网络不一致", isOn: $serverSignals.ipOrDeviceMismatch)
                    Toggle("不可能旅行", isOn: $serverSignals.impossibleTravel)
                }
                .padding()
                .background(Color(.tertiarySystemBackground))
                .cornerRadius(10)
            }
            .padding()
        }
        .alert(item: Binding(
            get: { decision.map(DecisionBox.init) },
            set: { _ in decision = nil }
        )) { box in
            let d = box.decision
            if d.blocksSubmission {
                return Alert(
                    title: Text(d.title),
                    message: Text(d.message),
                    dismissButton: .default(Text("我知道了"))
                )
            }
            return Alert(
                title: Text(d.title),
                message: Text(d.message),
                primaryButton: .destructive(Text("仍要继续")) { /* 留痕上报后放行 */ },
                secondaryButton: .cancel(Text("取消"))
            )
        }
        .sheet(isPresented: $showDesktopFallback) {
            DesktopFallbackView(expectedDomain: expectedDomain)
        }
    }

    private func submit() {
        // 提交瞬间再做一次完整评估（兜底，防止提示被忽略）。
        let policy = OTPRiskPolicy(trustedDomains: trustedDomains)
        let context = OTPEntryContext(
            source: .manual,
            expectedBoundDomain: expectedDomain,
            serverSignals: serverSignals
        )
        let result = policy.evaluate(context)
        if result.blocksSubmission { decision = result }
    }

    private struct DecisionBox: Identifiable {
        let id = UUID()
        let decision: OTPRiskDecision
    }
}

/// 桌面网页端降级方案：短信 OTP 在电脑上天然无法做系统级域名自动填充，
/// 用"App 推送授权 / 扫码登录 / passkey"把用户从"手动敲验证码"里迁走。
@available(iOS 13.0, *)
struct DesktopFallbackView: View {
    let expectedDomain: String

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                Text("电脑端登录的安全替代方式")
                    .font(.headline)
                bullet("优先：在电脑浏览器选择「扫码登录」，用本行 App 扫码并在手机端 Face ID 确认，全程无需手输验证码。")
                bullet("次选：「App 推送授权」——电脑网页发起登录后，手机 App 弹窗展示登录详情，确认即登录。")
                bullet("长期：开通 passkey（通行密钥），钓鱼网站无法获得可用凭证，从根上替代短信验证码。")
                bullet("若只能手动输入短信验证码：请核对浏览器地址栏确为 \(expectedDomain)，银行不会通过电话/聊天索取该验证码。")
                Spacer()
            }
            .padding()
            .navigationTitle("电脑端登录", displayMode: .inline)
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top) {
            Text("•").bold()
            Text(text).font(.subheadline)
        }
    }
}
#endif
