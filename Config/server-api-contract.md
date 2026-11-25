# 服务端配套：反 AiTM 中继的接口与风控约定

App 端能做的是"输入场景风险提示"，识别攻击者中继登录的主战场在服务端。本文档约定两端接口。

## 1. 下发验证码时返回模板元数据（可选但推荐）

`POST /auth/otp/issue` 响应体增加：

```json
{
  "otp_context_id": "ctx_8f3a2c",
  "expected_bound_domain": "bank.example",
  "sms_template_last_line": "@bank.example #******",
  "expires_in": 300
}
```

App 把 `expected_bound_domain` 传给 `OTPField` / `OTPRiskPolicy`，用于本地提示文案与域名比对。

## 2. 校验验证码时上报输入来源

`POST /auth/otp/verify` 请求体增加：

```json
{
  "otp_context_id": "ctx_8f3a2c",
  "code": "123456",
  "entry_source": "manual",
  "os_major_version": 17,
  "device_fingerprint": "fp_....",
  "user_acknowledged_risk": false
}
```

`entry_source` 取值：`autofill` / `paste` / `manual`（对应 App 端 `OTPEntrySource`）。

## 3. 服务端风控信号（映射到 `ServerRiskSignals`）

| 信号 | 检测逻辑 | 处置 |
|---|---|---|
| `duplicateOTPRequest` | 同一账号/会话在短窗口内重复申请 OTP（攻击者与受害者各触发一次） | 升级核验或拒绝 |
| `ipOrDeviceMismatch` | IP 归属地、UA、设备指纹与历史画像不一致 | 叠加人脸/推送确认 |
| `impossibleTravel` | 两次成功登录地理跨度超出物理可达 | 冻结并人工审核 |
| `codeAlreadyConsumed` | 验证码已成功消费一次又被提交（中继成功后受害者再提交，或反之） | **直接阻断**，触发账户保护 |

服务端通过 `GET /auth/otp/risk-signals?context_id=...` 或在 verify 响应中回传，App 用 `ServerRiskSignals` 承接后交给 `OTPRiskPolicy`。

## 4. 验证码一次性与绑定硬规则

1. 验证码验证成功立即作废，任何重放返回 `codeAlreadyConsumed`；
2. 错误次数达阈值（建议 5 次/有效期内）作废并重新下发；
3. 短信网关侧锁定模板，绑定行 `@bank.example #...` 不允许被通道改写或追加后缀；
4. 高风险交易（转账限额以上、改绑手机、重置密码）禁止仅凭短信 OTP 通过，强制 passkey/人脸/硬件因子。

## 5. 桌面网页端替代通道（消除手动输码）

- `GET /auth/qr/login`：签发一次性登录二维码，App 扫码确认后 PC 换 token；
- `POST /auth/push/approve`：App 推送授权，展示 PC 端 IP/UA/地理位置供用户核对；
- passkey：网页用 `navigator.credentials.get({ publicKey: ... })`，RP ID 绑定银行域名，钓鱼站无法触发有效断言。
