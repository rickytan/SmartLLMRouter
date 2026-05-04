# 📂 产品需求文档 (PRD)：SmartLLM Router

| 项目 | SmartLLM Router (macOS Menu Bar App) |
| :--- | :--- |
| **版本** | v2.0.0 (需求讨论阶段) |
| **状态** | Phase 1-6 已执行，**本 PRD 用于回溯补充遗漏需求** |
| **最近更新** | 补充 10 个关键遗漏模块 (3.8-3.17) |
| **目标平台** | macOS 13.0+ (Ventura) |
| **技术栈** | Swift 5.9+, SwiftUI, XcodeGen, SwiftGen, CocoaPods (Swifter, Alamofire, KeychainAccess, Sparkle, CocoaLumberjack) |

> **⚠️ 重要说明**: 本文档在 Phase 1-6 执行后进行了回溯性补充。原始 PRD 遗漏了大量关键需求，导致执行阶段频繁遇到问题。以下新增模块 (3.8-3.17) 是基于实际执行中发现的坑点和遗漏整理而成。**未来新项目应在需求阶段就考虑这些点。**

---

## 0. 技术决策记录 (ADR)

### ADR-001: Shell 配置路径选择 `.zshenv`
- **决策**: 使用 `~/.zshenv` 而非 `~/.zshrc` 注入代理环境变量。
- **原因**: `.zshrc` 仅在交互式 Shell 中加载，Claude Code、脚本、CI 等非交互式环境无法读取。`.zshenv` 是所有 zsh 进程启动时**必定**加载的第一个文件，确保代理环境变量全局生效。
- **影响**: `ShellConfigManager` 默认目标文件改为 `~/.zshenv`。

### ADR-002: 颜色管理采用 Asset Catalog + SwiftGen
- **决策**: 所有颜色迁移至 `Assets.xcassets`，使用 SwiftGen 生成类型安全代码 (`Asset.xxx.swiftUIColor`)。
- **原因**: 硬编码 RGB 无法适配暗黑模式；`Color("Name")` 字符串引用缺乏编译期检查。
- **影响**: `DesignTokens.swift` 全部使用 `Asset.xxx.swiftUIColor`，系统 Reference Color 自动适配 Light/Dark。

### ADR-003: 工程文件不纳入版本控制
- **决策**: `SmartLLMRouter.xcodeproj/` 和 `SmartLLMRouter.xcworkspace/` 加入 `.gitignore`。
- **原因**: 项目使用 XcodeGen 管理工程配置，`project.yml` 是唯一可信源。避免多人开发时的工程文件冲突。
- **影响**: 新环境 clone 后需先执行 `xcodegen generate` 生成工程。

### ADR-004: CocoaPods 静态链接
- **决策**: `Podfile` 使用 `use_frameworks! :linkage => :static`。
- **原因**: 减少打包体积（当前 8.6 MB），避免 Framework 签名问题。
- **例外**: Sparkle 因内含 `Updater.app` 必须作为独立 Framework 保留（2.3 MB）。

### ADR-005: 协议一致性约束
- **决策**: 模型切换只能在**同协议簇内**进行，禁止跨协议切换。
- **原因**: 跨协议切换（如 Anthropic → OpenAI）会破坏 Tool Calling 和 SSE 流式响应格式，导致 Claude Code 客户端崩溃。
- **影响**: `ModelSwitcher` 和 `RequestForwarder` 必须验证协议兼容性。

### ADR-006: 构建顺序强制规范
- **决策**: 先 `xcodegen generate`，再 `bundle exec pod install`。
- **原因**: `pod install` 会向 `xcodeproj` 写入 CocoaPods 链接配置，若后执行 `xcodegen` 会覆盖这些配置导致编译失败。
- **影响**: 所有 CI/构建脚本必须遵循此顺序。

---

## 1. 产品概述
**SmartLLM Router** 是一款原生 macOS 菜单栏应用，作为一个本地 HTTP 网关运行。它的主要目的是为 **Claude Code** (及其他兼容客户端) 提供多厂商 API Key 的统一接入、自动故障转移和负载均衡能力。

**核心价值：**
1.  **零配置客户端**：Claude Code 只需配置 `ANTHROPIC_BASE_URL=http://localhost:1897`。
2.  **透明路由**：用户可在菜单栏一键切换 Key，或开启自动模式，代理层在后台处理重试和切换。
3.  **协议兼容**：自动处理 Anthropic 与 OpenAI 之间的请求/响应格式转换。
4.  **隐私优先 (Privacy First)**：
    *   **100% Local Execution**：所有的路由逻辑、Key 管理、配置信息仅存储在用户本地（Keychain/UserDefaults）。
    *   **Zero Telemetry**：不上传任何使用数据、崩溃报告或遥测信息。
    *   **No Cloud Sync**：不提供也不依赖任何云同步功能，确保数据完全隔离在设备端。

---

## 2. 系统架构

### 2.1 架构拓扑
```text
[Client (Claude Code / OpenAI SDK)] 
       │
       │ POST /v1/messages OR /v1/chat/completions
       ▼
[Local Proxy Server (Port 1897)] 
       │
       ├── 1. Request Auto-Detection (Identify Protocol)
       ├── 2. Router Engine (Priority-based / Auto-Failover)
       ├── 3. Protocol Adapter (Anthropic <-> OpenAI)
       └── 4. Upstream Client (Alamofire)
                │
                ▼
        [Upstream API (DeepSeek / OpenAI / etc.)]
```

### 2.2 核心依赖
*   **UI Framework**: SwiftUI
*   **HTTP Server**: Swifter (v1.5.0+)
*   **HTTP Client**: Alamofire (v5.9.0+)
*   **Security**: KeychainAccess (v4.2.2)
*   **Updates**: Sparkle (v2.6)
*   **Logging**: CocoaLumberjack/Swift (v3.9+) — 异步高性能日志，支持多输出（Console + File），分级日志（DDLogVerbose/Debug/Info/Warn/Error），自动日志轮转
*   **Tooling**: XcodeGen, SwiftGen, CocoaPods, SwiftLint, SwiftFormat

---

## 3. 功能需求详情

### 3.1 模块一：本地代理服务 (Proxy Server)
*   **监听端口**：默认 `localhost:1897`。
*   **请求类型自动识别 (Request Auto-Detection)**:
    *   代理必须能自动识别客户端发来的请求格式，以便后续处理。
    *   **识别策略 (优先级从高到低)**:
        1.  **URL Path 匹配**:
            *   路径包含 `/v1/messages` $\rightarrow$ 识别为 **Anthropic 协议**。
            *   路径包含 `/v1/chat/completions` $\rightarrow$ 识别为 **OpenAI 协议**。
        2.  **JSON Payload 匹配** (兜底方案):
            *   Body 顶层包含 `system` 字段 (String 或 Array) $\rightarrow$ **Anthropic**。
            *   Body 顶层包含 `messages` 但无 `system` $\rightarrow$ **OpenAI**。
*   **处理流**：自动识别 -> 路由决策 -> 协议转换 -> 上游请求 -> 拦截流响应 -> 转发客户端。

### 3.2 模块二：协议转换器 (Protocol Adapter)
*   **请求转换 (Anthropic -> OpenAI)**：System Prompt 注入、Thinking 丢弃、Tools 映射。
*   **响应转换 (SSE OpenAI -> Anthropic)**：拦截 `delta` 实时转码，解析 `usage` 统计。
*   **元数据利用**:
    *   若 `input_tokens` + `output_tokens` > `contextLength`，拦截并报错 `400 Context Window Exceeded`，保护上游不被扣费。
    *   利用 `inputPricePerM` 计算精确费用并更新 Usage 统计。

### 3.3 模块三：智能路由器 (Smart Router)

#### A. 自动切换策略 (Auto-Failover)
*   **优先级驱动**：Priority 1 -> 2 -> 3...
*   **触发条件**：Switch (429, 5xx, 401, Timeout); Do Not Switch (400, 403).
*   **重试行为**：
    *   **Pre-Stream**：静默重试 (Silent Retry)，客户端无感。
    *   **Mid-Stream**：断开连接，防止数据混乱。
*   **智能冷却 (Cooldown)**：
    *   429: ~30min; 5xx: ~10min; 401: ~24h.
*   **范围限制**：仅在支持相同模型的 Channel 间切换。

#### B. 运行模式
1.  **Manual**：用户指定，失败即报错。
2.  **Auto**：开启自动切换策略。

### 3.4 模块四：菜单栏 UI (Menu Bar App)
*   **Header**: 状态 (🟢/🔴) + 端口。
*   **Stats**: 实时 Token 统计 (Callback 更新)。
*   **Routing Mode**: Auto Failover 开关。
*   **Channel List**: 显示当前活跃/非活跃/冷却状态。手动模式可点击切换。
*   **Recent Requests**: 最近 5 条请求日志 (只读)。
*   **Quick Actions**: Copy Env Config, Test Active Key.

### 3.5 模块五：设置窗口 (Settings) - 五大板块

#### 3.5.1 General (常规)
*   **Service Control**: Start/Stop, Local Port (1897), Launch at Login.
*   **Environment**: `⚙️ Setup Shell Environment` (Auto-config `.zshrc` flow).

#### 3.5.2 Channels (渠道管理) **[包含测速与模型元信息]**
*   **List View**:
    *   **拖拽排序**: 调整优先级。
    *   **延迟展示**: 每个 Channel 旁边显示 `Latency: XX ms` (通过测速功能获取)。
    *   **状态**: Active, Cooling, Error.
*   **Speed Test (测速)**:
    *   **单个测速**: 列表项提供 `⚡` 按钮，发送微型请求 (1 token) 测量 Time to First Token (TTFT)。
    *   **批量测速**: 顶部提供 **"⚡ Test All"** 按钮，依次测试所有配置的 Channel。
    *   **视觉反馈**: 🟢 <500ms, 🟡 500-1000ms, 🔴 >1000ms。
*   **Add/Edit Channel**:
    *   **Template**: From `providers.json`.
    *   **Fields**: Name, Base URL, API Key (Keychain).
    *   **Models**: 
        *   Fetch Models / Manual Add.
        *   **Model Metadata (元信息配置)**:
            *   点击模型旁的 `⚙️` 图标可编辑元信息。
            *   支持配置：Context Length, Input/Output Price ($/1M tokens)。
            *   用途：用于 Usage 统计精确计费，以及防止上下文超限请求。

#### 3.5.3 Advanced (高级)
*   **Failover**: Enable Switch, Cooldown durations (429/5xx/401), Max Retries.
*   **Compatibility**: Discard Thinking Parameter.

#### 3.5.4 Usage (使用量统计)
*   **Data**: Local storage only.
*   **Visuals**: 30-day bar chart.
*   **List**: Group by Channel (Total Tokens, Est. Cost [利用模型元信息计算], Requests).
*   **Actions**: Filter time range, Export CSV.

#### 3.5.5 About (关于)
*   **Info**: Version, Copyright.
*   **Updates**: Check for Updates (Sparkle), View on GitHub.
*   **Tools**: Copy Diagnostics, Privacy Policy.

### 3.6 模块六：首次启动与引导 (Onboarding Flow)
*   **Flow**: Start -> Auto-popup Settings -> Select Template/Config Key -> Shell Auto-Config -> Done.
*   **Skip**: "Set up Later" option.

### 3.7 模块七：内置供应商元数据 (Provider Metadata)
*   **File**: `Resources/providers.json`.
*   **Content**: ID, Name, BaseURL, Protocols, Models.
*   **Models 扩展结构**:
    ```json
    {
      "model": "gpt-4o",
      "protocol": "openai",
      "context_length": 128000,
      "input_price": 5.00,
      "output_price": 15.00
    }
    ```

---

### 3.8 模块八：多协议 Base URL 映射需求 **[关键遗漏]**

#### 背景问题
多个厂商**同时支持 OpenAI 和 Anthropic 两种协议**，但两个协议的 Base URL **不同**：
| 厂商 | OpenAI 协议 URL | Anthropic 协议 URL |
|------|----------------|-------------------|
| DeepSeek | `https://api.deepseek.com` | `https://api.deepseek.com/anthropic` |
| 阿里 DashScope | `https://dashscope.aliyuncs.com/compatible-mode/v1` | `https://dashscope.aliyuncs.com/compatible-mode/anthropic` |
| 小米 Mimo | `https://api.xiaomimimo.com/v1` | `https://api.xiaomimimo.com/anthropic` |

**⚠️ 注意：厂商 URL 会变更！**
- DeepSeek 的 OpenAI 端点**不需要 `/v1` 后缀**（官方文档明确说明）
- DashScope 从 `coding.dashscope.aliyuncs.com` 迁移到 `dashscope.aliyuncs.com`
- **必须建立定期验证机制**，不能假设配置永久有效

#### 需求定义
1.  **Per-Protocol Base URL**: `ProviderTemplate` 必须支持按协议存储不同的 Base URL
    ```json
    "base_urls": {
      "openai": "https://api.deepseek.com",
      "anthropic": "https://api.deepseek.com/anthropic"
    }
    ```
2.  **向后兼容**: 保留单 `base_url` 字段作为 fallback（仅支持单协议的厂商）
3.  **URL 获取方法**: 提供 `func baseURL(for protocol: String) -> String?` 统一入口
4.  **Channel 创建时协议绑定**: `ChannelManager.createChannelFromTemplate` 必须接受 `protocol` 参数，根据协议选择对应 URL
5.  **厂商 URL 验证流程**:
    - 每次发布前必须核对官方文档
    - 建立变更监控机制（GitHub Issue 或定期手动检查）
    - 厂商文档变更时，必须同步更新 `providers.json`

---

### 3.9 模块九：Add Channel / Onboarding UI 交互需求 **[关键遗漏]**

#### 历史问题
之前的设计将厂商选择网格 + 表单字段垂直堆叠，导致：
1.  用户需要**滚到底部**才能看到 API Key 输入框
2.  用户**不知道下面还有内容**，以为表单已结束
3.  厂商网格占用大量空间，实际只需要选一个

#### 新布局需求：左右分栏
```
┌─────────────────┬──────────────────────────┐
│  🔍 Search...   │  Provider Name           │
│  ─────────────  │  ⚡ OpenAI  🔵 Anthropic │
│  🌐 Custom/Local│  ─────────────────────── │
│  🅰️ Anthropic   │  Base URL [input]        │
│  🔵 OpenAI      │  API Key  [input]        │
│  🟢 MiniMax     │  [Test Connection] ✅    │
│  🔴 OpenRouter  │  ─────────────────────── │
│  🟡 Xiaomi      │  Models [Fetch] [+]      │
└─────────────────┴──────────────────────────┘
```

**左侧 (200px 固定宽度)**：
- 搜索框（支持按名称/ID 过滤）
- "Custom / Local" 选项（始终在顶部）
- 内置厂商列表（可滚动）
- 选中状态高亮 + ✓ 标记

**右侧 (自适应宽度)**：
- 厂商名称/自定义名称输入
- 协议选择器（OpenAI / Anthropic 芯片按钮）
- Base URL 输入框（**始终可见**）
- API Key 输入框（**始终可见**）
- 优先级输入
- 连接测试按钮 + 结果展示
- 模型列表管理

#### 连接测试需求
- **必须显示具体错误原因**，不能只显示"成功/失败"
- 错误类型分类：
  - `401 Invalid API Key`: 显示 API 返回的具体错误信息
  - `403 Access Denied`: 权限不足
  - `429 Rate Limited`: 请求限流
  - `5xx Server Error`: 服务端问题
  - `Network Error`: 网络问题（DNS 解析失败、超时、SSL 错误等）
- 解析 API 返回的 JSON 错误信息（`error.message`, `error.type`）
- 测试期间按钮禁用 + loading 状态

---

### 3.10 模块十：自定义厂商支持 **[关键遗漏]**

#### 背景
用户需要连接**本地运行的模型服务**（如 Ollama、LMStudio、LocalAI、vLLM），这些不在内置厂商列表中。

#### 需求定义
1.  **Custom Provider 入口**: 厂商列表顶部提供 "Custom / Local" 选项
2.  **默认值**:
    - Base URL: `http://localhost:11434/v1` (Ollama 默认地址)
    - 协议: OpenAI（大多数本地服务兼容 OpenAI 格式）
3.  **自定义字段**:
    - Provider Name（用户自定义）
    - Base URL（完全可编辑）
    - API Key（可选，本地服务通常不需要）
    - 协议选择（OpenAI / Anthropic）
4.  **Channel 存储**:
    - `providerId` 设为 `"custom"` 或 `nil`
    - 不影响内置厂商的模板匹配逻辑

---

### 3.11 模块十一：协议选择器交互需求

#### 需求定义
1.  **UI 形式**: 芯片按钮 (Chip) 或 Segmented Control
    - OpenAI 芯片 / Anthropic 芯片
    - 选中状态：高亮 + ✓ 标记
    - 未选中状态：普通背景
2.  **联动行为**:
    - 切换协议时，**自动更新 Base URL**（如果当前选择的是内置厂商且该厂商支持多协议）
    - 切换协议后，**重置连接测试结果**
    - 切换协议后，**过滤模型列表**（只显示支持该协议的模型）
3.  **单协议厂商**: 自动推断，不显示选择器（或显示但禁用）
4.  **多协议厂商**: 显示选择器，默认选中第一个支持的协议

---

### 3.12 模块十二：窗口尺寸需求 **[关键遗漏]**

#### 问题
窗口太小导致内容需要滚动，用户体验差。

#### 最小尺寸要求
| 窗口 | 最小宽度 | 最小高度 | 说明 |
|------|---------|---------|------|
| Onboarding | 520px | 500px | 需要容纳左右分栏 + 足够垂直空间 |
| Add Channel (Settings) | 520px | 500px | 同上 |
| Settings (主窗口) | 560px | 420px | 现有尺寸可接受 |

**设计原则**: 确保用户在**不滚动**的情况下能看到：
- 厂商选择列表（至少 8 个选项）
- Base URL 输入框
- API Key 输入框
- 连接测试按钮

---

### 3.13 模块十三：macOS 13 兼容性需求 **[关键遗漏]**

#### 已知陷阱
1.  **MenuBarExtra.onAppear 在 macOS 13 不触发**:
    - **问题**: 代理启动逻辑放在 `MenuBarExtra.onAppear` 中，macOS 13 下永远不会执行
    - **解决**: 必须使用 AppKit `AppDelegate.applicationDidFinishLaunching` 启动代理
2.  **窗口关闭导致 App 退出**:
    - **问题**: macOS 默认行为是最后一个窗口关闭时终止应用
    - **解决**: `AppDelegate` 必须实现 `applicationShouldTerminateAfterLastWindowClosed` 返回 `false`
3.  **Dock 图标问题**:
    - **问题**: 菜单栏应用不应出现在 Dock 中
    - **解决**: `NSApp.setActivationPolicy(.accessory)` 确保应用只在菜单栏显示
4.  **NSStatusItem 强引用**:
    - **问题**: SwiftUI `MenuBarExtra` 在 macOS 13 渲染异常
    - **解决**: 使用原生 `NSStatusItem` 并保存为强引用属性

#### 生命周期铁律
```
✅ 正确: 代理启动 → AppDelegate.applicationDidFinishLaunching
❌ 错误: 代理启动 → MenuBarExtra.onAppear (macOS 13 不触发)

✅ 正确: applicationShouldTerminateAfterLastWindowClosed → false
❌ 错误: 依赖默认行为 (窗口关闭 = App 退出)
```

---

### 3.14 模块十四：Shell 环境配置需求 **[关键遗漏]**

#### 问题
`.zshrc` 仅在**交互式 Shell** 中加载，Claude Code、脚本、CI 等**非交互式进程**无法读取。

#### 需求定义
1.  **目标文件**: `~/.zshenv`（所有 zsh 进程启动时**必定**加载）
2.  **注入内容**:
    ```bash
    export ANTHROPIC_BASE_URL=http://localhost:1897
    export OPENAI_BASE_URL=http://localhost:1897
    ```
3.  **Onboarding 展示**: 显示目标文件路径和将要注入的内容预览
4.  **幂等性**: 重复执行不应重复注入（检查是否已存在）
5.  **配置状态检测**: 能检测是否已配置，避免重复操作

---

### 3.15 模块十五：工程配置与构建规范 **[关键遗漏]**

#### SwiftGen 配置
1.  **strings + xcassets 共存**: `SwiftGen.yml` 必须同时配置两个输入源
2.  **v6 语法注意**: 输入路径不可直接写多个 `.lproj`，否则报 `Duplicate file` 错误
3.  **L10n.swift 双轨制**:
    - SwiftGen `structured-swift5` 生成的嵌套命名与现有 `L10n.X.Y` 约定不兼容
    - 决定：`strings` 仅保留在 `SwiftGen.yml` 作占位，实际代码维护**手写** `L10n.swift`
    - **新增 UI 文案必须手动同步至 `L10n.swift`**，否则编译报 `use of unresolved identifier`

#### 构建顺序铁律
```
1. xcodegen generate     (生成 .xcodeproj)
2. bundle exec pod install (写入 CocoaPods 链接配置)
3. swiftgen config run   (生成类型安全代码)
4. xcodebuild            (编译)
```
**⚠️ 如果顺序错误**: `pod install` 后执行 `xcodegen` 会覆盖 CocoaPods 配置，导致编译失败。

#### 工程文件版本控制
- `.xcodeproj/` 和 `.xcworkspace/` **不纳入 Git**
- `project.yml` 是唯一可信源
- 新环境 clone 后必须先执行 `xcodegen generate`

---

### 3.16 模块十六：代码级陷阱与命名规范 **[关键遗漏]**

#### Swift 关键字冲突
- `protocol` 是 Swift 保留字，**不能作为参数名**
- 必须使用反引号转义：``func createChannel(protocol: APIProtocol)``
- 或使用替代命名：`func createChannel(apiProtocol: APIProtocol)`

#### 类型转换需求
- `ProviderModel` (来自 JSON) → `ModelEntry` (内部模型) 需要显式转换
- 转换函数应处理所有字段映射：
  ```swift
  func providerModelToModelEntry(_ pm: ProviderModel) -> ModelEntry {
      ModelEntry(
          id: UUID().uuidString,
          identifier: pm.model,
          displayName: pm.model,
          contextLength: pm.contextLength,
          inputPricePer1M: pm.inputPrice,
          outputPricePer1M: pm.outputPrice,
          isEnabled: true
      )
  }
  ```

#### Channel 初始化器参数顺序
- Swift 初始化器参数有固定顺序，**位置参数必须在标签参数之前**
- `Channel` 定义中 `priority` 在 `protocol` 之前，调用时必须遵循：
  ```swift
  Channel(..., baseURL: "...", priority: 1, protocol: .openai, models: [])
  ```

---

### 3.17 模块十七：凭证安全需求

1.  **API Key 存储**: 必须使用 Keychain，禁止明文存储在 UserDefaults 或文件中
2.  **日志脱敏**: 所有日志中的 API Key/Token 必须显示为 `[REDACTED]`
3.  **测试环境**: UI Test 中需要 Mock Keychain 交互，避免真实 Key 泄露
4.  **导出功能**: 导出配置时自动隐藏 Key（显示为 `sk-...` 或 `[HIDDEN]`）

---

## 4. 数据模型定义

### 4.1 Channel 结构体
```swift
struct Channel: Identifiable, Codable {
    let id: UUID
    var name: String
    var providerId: String?
    var apiKey: String
    var baseURL: String
    var priority: Int
    var isCoolingDown: Bool = false
    var cooldownUntil: Date?
    var lastLatencyMs: Double = 0.0 
}
```

### 4.2 Model 结构体 (含元信息)
```swift
struct ModelEntry: Identifiable, Codable {
    let id: UUID
    var channelId: UUID
    var modelName: String
    var protocolType: ProviderType
    
    // 模型元信息
    var contextLength: Int = 128000          // 上下文限制
    var inputPricePerM: Double = 0.0         // 输入价格 ($/1M tokens)
    var outputPricePerM: Double = 0.0        // 输出价格 ($/1M tokens)
}
```

---

## 5. 非功能性需求

1.  **性能**: 冷启动 < 2s, 转发延迟 < 10ms, 内存 < 50MB.
2.  **隐私**: 严禁数据外发, Keychain 存储, **日志脱敏**（API Key / Secret 必须脱敏为 `[REDACTED]`，禁止明文出现在日志中）.
3.  **日志系统**: 采用 CocoaLumberjack/Swift，全模块统一通过 `DDLog` 输出：
    *   支持 Console + File 双输出，日志文件自动轮转（单文件最大 1MB，保留最近 7 天）
    *   分级：Debug（开发调试）、Info（常规操作）、Warn（可恢复异常）、Error（不可恢复错误）
    *   Proxy 层记录请求路由决策、协议转换、上游响应状态码；Router 层记录故障切换、冷却期触发
    *   Release 构建默认 `DDLogLevelInfo`，Debug 构建默认 `DDLogLevelDebug`
4.  **工程**: XcodeGen 管理工程, SwiftGen 管理多语言, SwiftLint + SwiftFormat 自动格式化.

---

## 6. 开发计划 (Roadmap)

*   **Phase 1**: Infrastructure, XcodeGen, CocoaPods, Proxy Server skeleton, Keychain logic.
*   **Phase 2**: Protocol Adapter (SSE/JSON), Swifter + Alamofire bridging.
*   **Phase 3**: Routing Logic, Menu Bar UI, Settings UI (General/Channels), Speed Test feature.
*   **Phase 4**: Auto-Failover/Cooldown, Usage Stats, Auto-Config Shell, Sparkle Updates.
*   **Phase 5**: Unified Model Switcher (Protocol-aware).
*   **Phase 6**: Multi-protocol Base URL mapping, UI redesign (split-pane), Custom provider support, URL verification, Error detail display.

---

## 7. 需求阶段检查清单 **[新增]**

> 以下检查清单基于 Phase 1-6 执行经验整理，**未来项目启动前必须逐项确认**：

### 7.1 外部依赖验证
- [ ] 所有厂商 Base URL 已核对官方文档（不能假设配置永久有效）
- [ ] 识别哪些厂商支持多协议，确认每个协议的独立 URL
- [ ] 建立 URL 变更监控/定期验证机制
- [ ] 第三方依赖版本兼容性确认（CocoaPods、Swift 版本等）

### 7.2 UI/UX 需求
- [ ] 窗口尺寸是否足够容纳核心操作（无需滚动）
- [ ] 关键输入框（API Key、URL）是否在首屏可见
- [ ] 是否支持自定义/本地服务（不仅限于内置厂商）
- [ ] 错误提示是否具体（不能只显示"失败"）
- [ ] 多协议场景下的协议选择交互设计
- [ ] 加载/测试状态的用户反馈

### 7.3 平台兼容性
- [ ] 最低支持版本的生命周期陷阱（如 macOS 13 的 MenuBarExtra.onAppear 不触发）
- [ ] 窗口关闭行为（菜单栏应用不应退出）
- [ ] Dock 图标显示策略
- [ ] 原生 AppKit 与 SwiftUI 混用注意事项

### 7.4 工程配置
- [ ] 构建顺序明确定义（xcodegen → pod install → swiftgen → build）
- [ ] SwiftGen 配置完整性（strings + xcassets 共存）
- [ ] 工程文件版本控制策略（哪些进 Git，哪些不进）
- [ ] L10n 维护策略（自动生成 vs 手写）

### 7.5 安全与隐私
- [ ] API Key 存储方案（Keychain）
- [ ] 日志脱敏策略
- [ ] 测试环境凭证处理
- [ ] 配置导出时的敏感信息隐藏

### 7.6 代码级陷阱
- [ ] Swift 保留字冲突检查（如 `protocol`）
- [ ] 类型转换需求识别（外部 JSON → 内部模型）
- [ ] 初始化器参数顺序确认
- [ ] 向后兼容性设计（旧数据格式迁移）

