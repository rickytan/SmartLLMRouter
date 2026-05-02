# 📂 产品需求文档 (PRD)：Smart LLM Router

| 项目 | Smart LLM Router (macOS Menu Bar App) |
| :--- | :--- |
| **版本** | v1.8.1 |
| **状态** | 待开发 |
| **目标平台** | macOS 13.0+ (Ventura) |
| **技术栈** | Swift 5.9+, SwiftUI, XcodeGen, SwiftGen, CocoaPods (Swifter, Alamofire, KeychainAccess, Sparkle) |

## 1. 产品概述
**Smart LLM Router** 是一款原生 macOS 菜单栏应用，作为一个本地 HTTP 网关运行。它的主要目的是为 **Claude Code** (及其他兼容客户端) 提供多厂商 API Key 的统一接入、自动故障转移和负载均衡能力。

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
[客户端 Claude Code] 
       │
       │ POST /v1/messages (Model: claude-3-5-sonnet)
       ▼
[本地代理 Server (Port 1897)] 
       │
       ├── [1. Router Engine] ── 决策：选哪个 Provider (Key)?
       │        │
       │        ├── Manual Mode: 用户手动指定
       │        └── Auto Mode: 优先级列表 (跳过冷却中 Key)
       │
       ├── [2. Protocol Adapter] ── 转换请求/响应格式
       │        │
       │        ├── Target is Anthropic: 透传 (Passthrough)
       │        └── Target is OpenAI: 转换 JSON & SSE Stream
       │
       └── [3. Upstream Client] ── 发送请求 (Alamofire)
                │
                ▼
        [Upstream API (Anthropic / OpenAI)]
```

### 2.2 核心依赖
*   **UI Framework**: SwiftUI
*   **HTTP Server**: Swifter (v1.5.0+) - 用于监听本地端口。
*   **HTTP Client**: Alamofire (v5.9.0+) - 用于向上游发起请求，处理 Stream。
*   **Security**: KeychainAccess (v4.2.2) - 用于加密存储 API Key。
*   **Update**: Sparkle (~> 2.6) - 用于安全检查应用更新。
*   **Tooling**: 
    *   **XcodeGen**: 使用 `project.yml` 管理工程，**不使用 .xcodeproj 文件**。
    *   **SwiftGen**: 使用 `swiftgen.yml` 管理多语言和资产，生成类型安全的 Swift 代码。
    *   **CocoaPods**: 管理第三方库。

---

## 3. 功能需求详情

### 3.1 模块一：本地代理服务 (Proxy Server)
*   **监听端口**：默认 `localhost:1897` (可在设置中修改)。
*   **路由规则**：
    *   拦截 `POST /v1/messages` (Anthropic 标准端点)。
    *   拦截 `POST /v1/chat/completions` (OpenAI 标准端点)。
*   **请求处理流**：
    1.  接收请求 Body 并解析 JSON。
    2.  调用 `Router` 获取目标 `Provider`。
    3.  调用 `Adapter` 转换 Request Body (如果目标与来源协议不同)。
    4.  通过 `Alamofire` 向上游发起流式请求。
    5.  拦截上游 SSE 响应，实时转发给客户端。

### 3.2 模块二：协议转换器 (Protocol Adapter) **[核心]**
此模块负责消除 Anthropic 和 OpenAPI 之间的差异。

#### A. 请求转换 (Request Transform)
*   **场景**：客户端发 Anthropic 格式 -> 目标是 OpenAI。
*   **规则**：
    1.  **System Prompt**: 提取 Anthropic 的 `system` (String/Array) -> 转换为 OpenAI 消息列表中的第一条 `{"role": "system", "content": "..."}`。
    2.  **Thinking 参数**: **静默丢弃**。移除 `thinking` 字段，防止 OpenAI 报错。
    3.  **Tools 定义**: 
        *   Anthropic: `{"name": "foo", "input_schema": {...}}`
        *   OpenAI: `{"type": "function", "function": {"name": "foo", "parameters": {...}}}`
    4.  **Max Tokens**: 映射 `max_tokens` -> `max_completion_tokens` (或 `max_tokens` 兼容字段)。

#### B. 响应流转换 (SSE Transform)
*   **场景**：OpenAI 返回 SSE -> 客户端需要 Anthropic SSE。
*   **实时流处理**：
    *   拦截 OpenAI 的 `data: {"choices": [{"delta": {"content": "Hello"}}]}`。
    *   转换为 Anthropic 的 `data: {"type": "content_block_delta", "delta": {"type": "text_delta", "text": "Hello"}, "index": 0}`。
    *   **Usage 统计**：解析 OpenAI 流末尾的 `usage` 块，统计 Token 数，更新 UI。

### 3.3 模块三：智能路由器 (Smart Router)

#### A. 自动切换策略 (Auto-Failover Strategy) **[核心]**
*   **基于优先级的路由**: 用户通过设置窗口拖拽排序。系统始终尝试 Priority 1 -> 2 -> 3...
*   **触发条件 (Triggers)**:
    *   ✅ **Switch**: 429 (Rate Limit), 5xx (Server Error), 401 (Auth), Timeout.
    *   ❌ **Do Not Switch**: 400 (Bad Request/Prompt Error), 403 (Content Policy).
*   **重试行为 (Retry Behavior)**:
    *   **🟢 Pre-Stream (握手阶段)**: 若连接未建立或刚收到错误响应头，**静默重试** (Silent Retry) 下一个可用 Channel，对客户端透明。
    *   **🔴 Mid-Stream (流传输中断)**: 若 SSE 流已开始传输数据后中断，**停止重试**并断开连接，防止数据错乱。由客户端 (Claude Code) 处理后续重试。
*   **智能冷却 (Smart Cooldown)**:
    *   **429**: 15-30 分钟 (默认)。
    *   **502/504**: 5-10 分钟 (默认)。
    *   **401**: 24 小时 (默认，直到用户手动修复)。
*   **范围限制 (Scope Constraint)**: 切换仅在**配置了当前请求模型**的 Channel 间进行。若某 Channel 不支持该模型，直接跳过。

#### B. 运行模式
1.  **手动模式 (Manual)**：
    *   严格按照用户在菜单栏选择的 `Channel` 发送。
    *   如果该 Channel 报错，**不自动重试**，直接向客户端报错。
2.  **自动模式 (Auto-Failover)**：
    *   开启上述自动切换策略。

### 3.4 模块四：菜单栏 UI (Menu Bar App) **[详细交互规范]**

*   **全局状态图标**：
    *   🟢 **Running**: 代理运行中，至少有一个可用 Channel。
    *   🔴 **Stopped/Error**: 代理未启动或所有 Channel 不可用。
*   **下拉菜单结构 (从上至下)**：
    1.  **Header (只读)**：
        *   内容：`🟢 Running | Port: 1897` (根据实际状态变化)。
    2.  **实时统计 (Real-time Stats)**：
        *   内容：`📊 Today: 12,340 Tokens ($0.15)`。
        *   交互：点击可触发 "Reset Stats" 确认弹窗。
        *   **更新机制**：仅在收到上游响应 **回调 (Callback)** 时更新内部数据；**每次菜单展开时**强制刷新显示。
    3.  **分隔线**
    4.  **核心开关 (Routing Mode)**：
        *   内容：`⚡ Auto Failover: [ ON / OFF ]`。
        *   行为：
            *   **ON**：下方 Channel 列表显示为灰色，不可点击 (由系统路由)。
            *   **OFF**：Channel 列表变为可点击 (进入手动模式)。
    5.  **频道列表 (Channel List)**：
        *   样式：显示所有已配置 Channel。
            *   当前活跃：`● Channel Name` (前面有实心圆点)。
            *   非活跃：`Channel Name`。
            *   冷却中：`⏸ Channel Name (Cooling)` (灰色)。
        *   **交互**：手动模式下点击切换。切换仅对**下一个**进入的请求生效，**不中断**正在进行的流。
    6.  **分隔线**
    7.  **子菜单 (Recent Requests)**：
        *   标题：`📋 Recent Requests (Last 5)`。
        *   内容：展示最近 5 条请求。格式：`[Icon] Model Name ... [Status Code] (Latency)`。
            *   成功：绿色图标。失败/限流：红色图标。
        *   交互：**只读展示**，点击无额外动作。
    8.  **分隔线**
    9.  **快捷工具 (Quick Actions)**：
        *   `📋 Copy Env Config`：点击复制 `export ANTHROPIC_BASE_URL=...` 到剪贴板 + Toast 提示。
        *   `🧪 Test Active Key`：点击对当前 Channel 发起 Ping 测试。
    10. **分隔线**
    11. **系统级 (System)**：
        *   `⚙️ Settings`
        *   `❌ Quit`

### 3.5 模块五：设置窗口 (Settings) - 五大板块

Settings 窗口采用标准的左侧导航栏布局，包含 **General**, **Channels**, **Advanced**, **Usage**, **About** 五个 Tab。

#### 3.5.1 General (常规)
*   **Service Control**:
    *   `Proxy Status` (Start/Stop 按钮)。
    *   `Local Port`: 输入框 (Default 1897)，支持修改。
    *   `Launch at Login` (Switch)。
*   **Environment Setup**:
    *   `⚙️ Setup Shell Environment` 按钮 (执行 Onboarding 中提到的 Shell 自动配置逻辑)。
    *   状态提示: `✅ Configured for zsh`。

#### 3.5.2 Channels (渠道管理)
*   **Channel 列表**:
    *   支持 **拖拽排序** (Drag & Drop) 以调整自动切换优先级。
    *   列表项显示：Icon, Name, Models, Status (Active/Cooling/Error)。
*   **添加/编辑 Channel**:
    *   **模板选择**: 基于 `providers.json`。
    *   **表单字段**: Name, Base URL (可自定义), API Key (Keychain)。
    *   **模型管理**:
        *   `📡 Fetch Models` 按钮 (调用 `/v1/models`)。
        *   手动添加输入框。
    *   **验证**: `🧪 Test Connection` 按钮。
    *   **保存**: 保存并更新 Router。

#### 3.5.3 Advanced (高级/路由)
*   **Failover**:
    *   `Enable Auto-Failover` Switch。
    *   **Cooldown Settings**: 输入框 (429, 5xx, 401 的冷却分钟数)。
    *   **Max Retries**: 输入框。
*   **Compatibility**:
    *   `[x] Discard Thinking Parameter` (路由到 OpenAI 时丢弃 thinking 字段)。

#### 3.5.4 Usage (使用量统计)
*   **数据源**: 纯本地存储的 JSON/SQLite (Privacy First)。
*   **顶部视图**: 30 天 Token 消耗柱状图 (支持鼠标悬停查看详情)。
*   **底部列表**:
    *   按 **Channel** 分组统计。
    *   显示：Channel Name, Total Tokens, Est. Cost, Request Count.
*   **功能**:
    *   时间筛选 (7d/30d/Month/All)。
    *   `📋 Export CSV` (导出本地文件)。
    *   `🗑️ Clear History`。

#### 3.5.5 About (关于)
*   **应用信息**:
    *   App Icon, Name, Version (`1.0.0`), Copyright.
*   **更新检查**:
    *   集成 **Sparkle** 框架。
    *   `🔄 Check for Updates` 按钮。
    *   检查源指向 GitHub Releases XML，不上传任何用户数据。
*   **辅助功能**:
    *   `🐙 View on GitHub` 链接。
    *   `🛡️ Privacy Policy` 链接。
    *   `📋 Copy Diagnostics` (复制环境/状态信息到剪贴板)。

### 3.6 模块六：首次启动与引导 (Onboarding Flow)
*   **Step 1: 启动检测**
    *   App 启动后（无 Dock 图标），检查 `UserDefaults.hasCompletedOnboarding`。
    *   若未配置，**自动弹出 Settings 窗口** (Channels Tab)。
    *   提供 **"Set up Later"** 选项。
*   **Step 2: 灵活配置**
    *   支持从模板选择，**必须允许修改 Base URL**。
*   **Step 3: 客户端引导与自动配置**
    *   **卡片展示**: "Copy Client Config" + `⚙️ Help me configure` 按钮。
    *   **自动化配置流程**:
        1.  **Detect**: 识别当前 Shell。
        2.  **Backup**: 自动备份 `.zshrc`。
        3.  **Preview**: 预览写入内容。
        4.  **Execute**: 写入环境变量。
        5.  **Done**: 提示重启终端。

### 3.7 模块七：内置供应商元数据 (Provider Metadata)
*   **资源位置**: `Resources/providers.json`
*   **数据结构**: 
    *   `id`, `name_en/zh`, `base_url`, `supports_protocols`, `default_models`。
    *   **新增 Pricing 字段**: `{"model": "gpt-4o", "input_price": 5.00, "output_price": 15.00}` (用于 Usage 模块计算费用)。
*   **加载策略**: App 启动时从 Bundle 加载。

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
    var priority: Int // 由列表顺序决定
    var isCoolingDown: Bool = false
    var cooldownUntil: Date?
}
```

### 4.2 Model 结构体
```swift
struct ModelEntry: Identifiable, Codable {
    let id: UUID
    var channelId: UUID
    var modelName: String
    var protocolType: ProviderType
}
```

---

## 5. 非功能性需求

1.  **性能**:
    *   冷启动时间 < 2秒。
    *   代理转发延迟 (Latency Overhead) < 10ms。
    *   内存占用 < 50MB。
2.  **隐私与数据隔离 (Privacy & Security)**:
    *   **严禁数据外发**：除了转发给上游 API，**严禁**向任何第三方发送数据。
    *   **本地存储**：配置仅存储于 Keychain 和 UserDefaults。
    *   **日志脱敏**：本地日志必须掩盖 API Key。
3.  **工程规范**:
    *   **必须**通过修改 `project.yml` 来调整工程配置。
    *   **必须**通过 `Localizable.strings` 和 SwiftGen 维护文案。

---

## 6. 开发计划 (Roadmap)

*   **Phase 1: 基础设施** (XcodeGen, SwiftGen, Sparkle, Proxy Server, Keychain)
*   **Phase 2: 核心代理与转换** (Anthropic/OpenAI SSE & JSON Transform)
*   **Phase 3: 路由与 UI** (Router, Menu Bar, Settings General/Channels, providers.json)
*   **Phase 4: 高级特性** (Auto-Failover, Cooldown, Usage Stats, About, Auto-Config Shell)
