// swift-tools-version:6.0
// 手机银行短信验证码防钓鱼组件
import PackageDescription

let package = Package(
    name: "BankOTPAntiPhishing",
    platforms: [
        .iOS(.v13),          // 覆盖仍在网的老机型；域名绑定能力在内部按 iOS 14 分层
        .macOS(.v12)         // 仅为在 macOS 上跑核心逻辑单测，UI 层用 canImport(UIKit) 隔离
    ],
    products: [
        .library(
            name: "BankOTPAntiPhishing",
            targets: ["BankOTPAntiPhishing"]
        )
    ],
    targets: [
        .target(
            name: "BankOTPAntiPhishing",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // 零依赖测试可执行程序：本机仅安装 Command Line Tools、无 XCTest，
        // 在有完整 Xcode 的环境可改回 .testTarget（测试断言本身与框架无关）。
        .executableTarget(
            name: "OTPTestRunner",
            dependencies: ["BankOTPAntiPhishing"],
            path: "Tests/OTPTestRunner",
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
