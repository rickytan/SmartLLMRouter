# 📂 产品需求文档 (PRD)：Smart LLM Router

| 项目 | Smart LLM Router (macOS Menu Bar App) |
| :--- | :--- |
| **版本** | v1.4.0 |
| **状态** | 待开发 |
| **目标平台** | macOS 13.0+ (Ventura) |
| **技术栈** | Swift 5.9+, SwiftUI, XcodeGen, SwiftGen, CocoaPods (Swifter, Alamofire, KeychainAccess) |

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

#### A. 运行模式
1.  **手动模式 (Manual)**：
    *   严格按照用户在菜单栏选择的 `Channel` 发送。
    *   如果该 Channel 报错，**不自动重试**，直接向客户端报错。
2.  **自动模式 (Auto-Failover)**：
    *   维护一个 `Priority List` (按 Channel 配置顺序)。
    *   依次尝试，直到找到可用的 Channel。

#### B. 故障转移与重试 (Failover & Retry)
*   **触发条件**：
    *   HTTP Status `429` (Rate Limit)
    *   HTTP Status `5xx` (Server Error)
    *   HTTP Status `401` (Invalid Key)
*   **重试策略 (静默重试)**：
    *   **连接级重试**：在**建立连接前**或**收到错误响应头/非流式错误体**时，代理层立即向下一个 Channel 发起**全新请求**。客户端完全无感知。
    *   *注意：如果 SSE 流已经开始传输数据后中断，为了数据一致性，代理层将断开与客户端的连接（此时 Claude Code 会自行处理重试）。*
*   **冷却机制 (Cooldown)**：
    *   报错的 Channel 将被标记为 `isCoolingDown = true`。
    *   冷却时长默认 **30 分钟** (可配置)。
    *   冷却期间，Auto 模式下自动跳过该 Channel。

### 3.4 模块四：菜单栏 UI (Menu Bar App)
*   **状态图标**：
    *   🟢 **Running**: 代理运行中，至少有一个可用 Channel。
    *   🔴 **Stopped/Error**: 代理未启动或所有 Channel 不可用。
*   **菜单内容**：
    *   **Header**: `L10n.App.statusRunning`
    *   **Stats**: `Today Tokens: 12,345` (需实时更新)
    *   **Toggle**: `⚡ Auto Switch [ON/OFF]`
    *   **List**:
        *   ✅ Channel A (Active)
        *   ⏸ Channel B (Cooling)
        *   ⏸ Channel C
    *   **Footer**: `L10n.Settings.title`, `L10n.Common.quit`

### 3.5 模块五：设置窗口 (Settings)
*   **Channel 管理 (CRUD)**：
    *   列表显示 Name, Type (Icon), Status。
    *   **快速添加**: 提供基于 `providers.json` 的预设列表（如 DeepSeek, 阿里百炼等）。
    *   **表单**: 输入 API Key (存入 Keychain), Base URL (可修改)。
    *   **📡 Fetch Models**: 点击按钮请求 `/v1/models` 获取该 Key 支持的模型列表，供用户勾选（添加到路由）。
    *   **🧪 Test**: 验证 Key 有效性。
*   **高级设置**：
    *   `Local Port`: 默认 1897。
    *   `Cooldown Duration (mins)`: 默认 30。
    *   `Retry Count`: 默认 2。
    *   `Launch at Login`: 开关 (ServiceManagement)。

### 3.6 模块六：首次启动与引导 (Onboarding Flow)
*   **Step 1: 启动检测**
    *   App 启动后（无 Dock 图标），检查 `UserDefaults.hasCompletedOnboarding`。
    *   若未配置，**自动弹出 Settings 窗口**，高亮 Channel 列表。
*   **Step 2: 配置 Channel**
    *   用户选择内置供应商 (如 DeepSeek) -> 填入 Key -> **Fetch Models** -> 测试通过。
*   **Step 3: 客户端引导**
    *   Settings 顶部显示 "Copy Client Config" 卡片。
    *   **内容**：`export ANTHROPIC_BASE_URL=http://localhost:1897`
    *   点击一键复制，标记完成。

### 3.7 模块七：内置供应商元数据 (Provider Metadata)
*   **资源位置**: `Resources/providers.json`
*   **数据结构**: 
    *   `id`: 唯一标识
    *   `name_en/zh`: 多语言名称
    *   `base_url`: 默认 API 端点
    *   `supports_protocols`: 支持的协议列表 (`openai`, `anthropic`)
    *   `default_models`: 预置的模型及其协议映射
*   **加载策略**:
    *   App 启动时从 Bundle 加载该 JSON。
    *   在 Settings -> Add Channel 界面中，作为 "Select Provider Template" 的列表源。
    *   支持未来版本通过远程更新此 JSON (预留接口，暂不实现)。

---

## 4. 数据模型定义

### 4.1 Channel 结构体
```swift
struct Channel: Identifiable, Codable {
    let id: UUID
    var name: String // e.g., "DeepSeek Main", "My Proxy"
    var providerId: String? // 关联 providers.json 中的 id (用于显示 Logo/名称)
    var apiKey: String // 内存中暂存，读写走 Keychain
    var baseURL: String
    var priority: Int
    
    var isCoolingDown: Bool // 运行时状态
    var cooldownUntil: Date?
}
```

### 4.2 Model 结构体
```swift
struct ModelEntry: Identifiable, Codable {
    let id: UUID
    var channelId: UUID // 归属哪个 Channel
    var modelName: String // e.g., "claude-3-5-sonnet", "deepseek-chat"
    var protocolType: ProviderType // .openai or .anthropic
}
```

### 4.3 Provider Metadata 结构体
```swift
struct ProviderTemplate: Identifiable, Codable {
    let id: String
    var name: String
    var baseURL: String
    var protocols: [String] // ["openai", "anthropic"]
    var models: [(name: String, protocol: String)]
}
```

### 4.4 状态管理 (AppState)
使用 `ObservableObject` 或 `Actor` 管理全局状态。

---

## 5. 非功能性需求

1.  **性能**:
    *   冷启动时间 < 2秒。
    *   代理转发延迟 (Latency Overhead) < 10ms。
    *   内存占用 < 50MB。
2.  **隐私与数据隔离 (Privacy & Security)**:
    *   **严禁数据外发**：除了将用户的 LLM 请求转发给其配置的上游 API 端点外，**严禁**向任何第三方服务器发送数据。
    *   **本地存储**：所有配置（Channels, Models, Settings）仅存储在 macOS Keychain 和 UserDefaults 中。
    *   **日志脱敏**：本地调试日志 (Console Log) 中打印的请求头/Body 时，必须自动掩盖 API Key，防止开发者工具调试时泄露。
3.  **工程规范**:
    *   **必须**通过修改 `project.yml` 来调整工程配置，禁止直接提交 `.xcodeproj`。
    *   **必须**通过 `Localizable.strings` 维护文案，通过 SwiftGen 生成的 `L10n` 枚举引用，**严禁**在代码中硬编码字符串。

---

## 6. 开发计划 (Roadmap)

*   **Phase 1: 基础设施**
    *   XcodeGen 项目搭建，CocoaPods 集成。
    *   实现 `ProxyServer` 基础类，能够启动并响应 HTTP 请求。
    *   实现 Keychain 存取逻辑。
    *   配置 SwiftGen 基础环境。

*   **Phase 2: 核心代理与转换**
    *   实现 Anthropic -> Anthropic 透传。
    *   实现 Anthropic -> OpenAI 请求/响应转换 (含 SSE 实时转换)。
    *   *验收标准：Claude Code 能通过代理成功调用 OpenAI 模型。*

*   **Phase 3: 路由与 UI**
    *   实现 `SmartRouter` (手动/自动切换)。
    *   实现 SwiftUI MenuBar UI 和 Settings Window。
    *   解析 `providers.json` 并渲染供应商列表。
    *   绑定 UI 到 Router 逻辑。

*   **Phase 4: 高级特性**
    *   实现故障转移 (Failover) 和冷却 (Cooldown) 逻辑。
    *   实现 Token 统计与 UI 实时更新。
    *   实现 Fetch Models 功能。
