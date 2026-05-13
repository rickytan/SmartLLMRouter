# 🚀 SmartLLMRouter CI/CD & Sparkle 自动更新指南

本文档说明如何配置完整的自动化发布流水线，包括**代码签名**、**公证 (Notarization)**、**Sparkle 自动更新** 和 **GitHub Pages 分发**。

---

## 📋 概览

```
git tag v1.0.0 && git push origin v1.0.0
         │
         ▼
┌─────────────────────────────────────────┐
│  GitHub Actions (macos-14 Runner)       │
│                                         │
│  1. xcodegen → pod install → swiftgen   │
│  2. xcodebuild Release 构建              │
│  3. 代码签名 (Developer ID)              │
│  4. 打包 ZIP 提交公证 (Notarization)     │
│  5. Staple 公证票据                      │
│  6. generate_appcast 生成 Appcast.xml    │
│  7. 推送 GitHub Release                  │
│  8. 部署 appcast.xml → GitHub Pages      │
└─────────────────────────────────────────┘
         │
         ▼
   用户端 Sparkle 自动检测更新
```

---

## 🔑 第一步：准备 Apple 开发者凭证

### 1.1 导出 Developer ID 证书

```bash
# 在本地 Mac 的钥匙串中找到 Developer ID Application 证书
# 右键 → 导出 → 保存为 DeveloperID.p12（设置密码）
```

将 `.p12` 文件转为 Base64：

```bash
base64 -i DeveloperID.p12 -o DeveloperID.p12.b64
```

### 1.2 创建 App 专用密码

1. 访问 [appleid.apple.com](https://appleid.apple.com)
2. 登录你的 Apple ID → **App 专用密码** → 生成一个新密码
3. 记录该密码（仅在创建时显示一次）

### 1.3 获取 Team ID

在 [Apple Developer 后台](https://developer.apple.com/account) 的 Membership 页面找到 **Team ID**（10 位字符）。

### 1.4 生成 Sparkle EdDSA 密钥对

下载 Sparkle 后运行：

```bash
# 下载 Sparkle（替换版本号）
curl -L https://github.com/sparkle-project/Sparkle/releases/download/2.6.4/Sparkle-2.6.4.tar.xz | tar xJ

# 生成密钥对
./Sparkle-2.6.4/bin/generate_keys

# 输出示例：
# Private key (base64): Edw...（保密，用于 CI）
# Public key (base64): aBC...（填入 Info.plist 的 SUPublicEDKey）
```

---

## ⚙️ 第二步：配置 GitHub Secrets 和 Variables

### Secrets（设置 → Secrets and variables → Actions → Secrets）

| Secret 名称 | 值 | 说明 |
|---|---|---|
| `BUILD_CERTIFICATE_BASE64` | 上述 `.p12.b64` 文件内容 | 签名证书 |
| `P12_PASSWORD` | `.p12` 导出时设的密码 | 证书密码 |
| `KEYCHAIN_PASSWORD` | 自定义强密码 | 临时钥匙串密码 |
| `APPLE_ID` | 你的 Apple ID 邮箱 | 公证用 |
| `APPLE_APP_SPECIFIC_PASSWORD` | 1.2 生成的专用密码 | 公证用 |
| `SPARKLE_ED_PRIVATE_KEY` | 1.4 生成的 Private key | 签名 Appcast |

### Variables（设置 → Secrets and variables → Actions → Variables）

| Variable 名称 | 值 | 说明 |
|---|---|---|
| `CODE_SIGN_IDENTITY_NAME` | `Developer ID Application: Your Name (XXXXXXXXXX)` | 钥匙串中证书的完整名称 |
| `APPLE_TEAM_ID` | 1.3 获取的 Team ID | 公证用 |

---

## 📄 第三步：更新 Info.plist

在 `project.yml` 中更新 Sparkle 的公钥：

```yaml
settings:
  base:
    # 将下方值替换为你 1.4 生成的 Public key
    SUPublicEDKey: "aBC...你的公钥..."
    SUFeedURL: "https://smartllmrouter.github.io/appcast.xml"
```

> **重要**：`SUPublicEDKey` 必须与 `SPARKLE_ED_PRIVATE_KEY` 配对。如果不匹配，客户端会拒绝更新。

---

## 🚀 第四步：发布新版本

一切就绪后，发布新版本只需一个 Git Tag：

```bash
# 确认版本号已更新（project.yml 中的 MARKETING_VERSION / CURRENT_PROJECT_VERSION）
git tag v1.0.0
git push origin main --tags
```

GitHub Actions 会自动触发 Release 工作流。完成后：

1. **GitHub Release** 页面会出现带 `.zip` 和 `.dSYM` 的新 Release
2. **GitHub Pages** 会收到最新的 `appcast.xml`
3. 用户端 Sparkle 自动检测到更新

---

## 🔍 第五步：验证发布

### 检查 Appcast

```bash
curl -s https://smartllmrouter.github.io/appcast.xml | head -50
```

应看到包含 `<enclosure>` 标签指向 GitHub Releases 下载链接的 XML。

### 客户端测试

在另一台 Mac 上安装 App 后，打开控制台查看 Sparkle 日志：

```bash
log stream --predicate 'subsystem == "org.sparkle-project.Sparkle"' --info
```

---

## 🐛 常见问题

### Q: 公证失败，提示 "The executable does not have the hardened runtime enabled"

A: 确保 `codesign` 时使用了 `--options runtime` 参数，且 entitlements 文件存在。

### Q: generate_appcast 报错 "No items found"

A: 确保 release 文件夹中包含 `.zip` 文件，且 ZIP 内的 App 结构正确（`SmartLLMRouter.app/Contents/...`）。

### Q: 客户端不弹出更新提示

A: 检查以下几点：
1. `SUFeedURL` 是否指向正确的 `appcast.xml` 地址
2. `SUPublicEDKey` 是否与生成 Appcast 的私钥配对
3. `appcast.xml` 中的 `sparkle:version` 是否大于客户端当前版本

### Q: GitHub Pages 没有更新

A: 检查 workflow 日志中 "Deploy Appcast to GitHub Pages" 步骤是否成功。如果仓库未启用 GitHub Pages，需要在 Settings → Pages 中启用，Source 选 `GitHub Actions`。

### Q: 需要发布 Beta 版本怎么办？

A: 使用包含 `beta` 或 `alpha` 的 tag（如 `v1.1.0-beta.1`），工作流会跳过 GitHub Pages 部署，仅创建 GitHub Release。你可以手动将生成的 `appcast.xml` 上传到另一个 Feed URL 用于测试通道。

---

## 📁 相关文件

| 文件 | 说明 |
|---|---|
| `.github/workflows/release.yml` | CI/CD 主工作流 |
| `.github/scripts/setup-keychain.sh` | CI 钥匙串配置脚本 |
| `Resources/SmartLLMRouter.entitlements` | Hardened Runtime 权限声明 |
| `project.yml` | XcodeGen 项目配置（含 Sparkle 设置） |
