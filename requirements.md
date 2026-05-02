# 📂 产品需求文档 (PRD)：Smart LLM Router

| 项目 | Smart LLM Router (macOS Menu Bar App) |
| :--- | :--- |
| **版本** | v1.1.0 |
| **状态** | 待开发 |
| **目标平台** | macOS 13.0+ (Ventura) |
| **技术栈** | Swift 5.9+, SwiftUI, XcodeGen, SwiftGen, CocoaPods |

## 1. 产品概述
**Smart LLM Router** 是一款原生 macOS 菜单栏应用，作为一个本地 HTTP 网关运行。它的主要目的是为 **Claude Code** (及其他兼容客户端) 提供多厂商 API Key 的统一接入、自动故障转移和负载均衡能力。

**核心价值：**
1.  **零配置客户端**：Claude Code 只需配置 `ANTHROPIC_BASE_URL=http://localhost:8181`。
2.  **透明路由**：用户可在菜单栏一键切换 Key，或开启自动模式，代理层在后台处理重试和切换。
3.  **协议兼容**：自动处理 Anthropic 与 OpenAI 之间的请求/响应格式转换。

---

## 2. 系统架构

### 2.1 架构拓扑
```text
[客户端 Claude Code] 
       │
       │ POST /v1/messages (Anthropic Format)
       ▼
[本地代理 Server (Port 8181)] 
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
*   **监听端口**：默认 `localhost:8181` (可在设置中修改)。
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
    *   严格按照用户在菜单栏选择的 `Provider` 发送。
    *   如果该 Provider 报错，**不自动重试**，直接向客户端报错 (除非用户开启了“备用 Key 列表”)。
2.  **自动模式 (Auto-Failover)**：
    *   维护一个 `Priority List` (按配置顺序)。
    *   依次尝试，直到找到可用的 Provider。

#### B. 故障转移与重试 (Failover & Retry)
*   **触发条件**：
    *   HTTP Status `429` (Rate Limit)
    *   HTTP Status `5xx` (Server Error)
    *   HTTP Status `401` (Invalid Key)
*   **重试策略 (静默重试)**：
    *   **连接级重试**：在**建立连接前**或**收到错误响应头/非流式错误体**时，代理层立即向下一个 Provider 发起**全新请求**。客户端完全无感知。
    *   *注意：如果 SSE 流已经开始传输数据后中断，为了数据一致性，代理层将断开与客户端的连接（此时 Claude Code 会自行处理重试）。*
*   **冷却机制 (Cooldown)**：
    *   报错的 Provider 将被标记为 `isCoolingDown = true`。
    *   冷却时长默认 **30 分钟** (可配置)。
    *   冷却期间，Auto 模式下自动跳过该 Key。

### 3.4 模块四：菜单栏 UI (Menu Bar App)
*   **状态图标**：
    *   🟢 **Running**: 代理运行中，至少有一个可用 Key。
    *   🔴 **Stopped/Error**: 代理未启动或所有 Key 不可用。
*   **菜单内容**：
    *   **Header**: `L10n.App.statusRunning`
    *   **Stats**: `Today Tokens: 12,345` (需实时更新)
    *   **Toggle**: `⚡ Auto Switch [ON/OFF]`
    *   **List**:
        *   ✅ Provider A (Active)
        *   ⏸ Provider B (Cooling)
        *   ⏸ Provider C
    *   **Footer**: `L10n.Settings.title`, `L10n.Common.quit`

### 3.5 模块五：设置窗口 (Settings)
*   **Key 管理 (CRUD)**：
    *   列表显示 Name, Type (Icon), Model。
    *   密码框输入 API Key (存入 Keychain)。
    *   输入 Base URL (默认为官方地址，允许填入代理地址)。
    *   **Test Button**: 发送最小请求验证 Key 有效性。
*   **高级设置**：
    *   `Local Port`: 默认 8181。
    *   `Cooldown Duration (mins)`: 默认 30。
    *   `Retry Count`: 默认 2。
    *   `Auto Switch Trigger`: 多选 [429, 5xx, 401]。

---

## 4. 数据模型定义

### 4.1 Provider 结构体
```swift
struct LLMProvider: Identifiable, Codable {
    let id: UUID
    var name: String
    var type: ProviderType // .anthropic or .openai
    var apiKey: String     // 内存中暂存，读写走 Keychain
    var baseURL: String
    var modelName: String
    var priority: Int      // 自动模式下的排序权重
    
    // 运行时状态 (不持久化)
    var isCoolingDown: Bool
    var cooldownUntil: Date?
}
```

### 4.2 状态管理 (AppState)
使用 `ObservableObject` 或 `Actor` 管理全局状态。

---

## 5. 非功能性需求

1.  **性能**:
    *   冷启动时间 < 2秒。
    *   代理转发延迟 (Latency Overhead) < 10ms。
    *   内存占用 < 50MB。
2.  **安全性**:
    *   **严禁**将 API Key 写入 UserDefaults 或 Log。
    *   所有 Key 必须存储在 macOS Keychain 中 (`KeychainAccess` 库)。
    *   Log 中打印请求/响应时，必须对 Key 进行脱敏处理 (如 `sk-ant...xyz`)。
3.  **稳定性**:
    *   应用关闭时，必须确保后台 Server 停止并释放端口。
    *   处理 SSE 流时必须正确处理 `Task` 取消，防止僵尸进程。
4.  **工程规范**:
    *   **必须**通过修改 `project.yml` 来调整工程配置，禁止直接提交 `.xcodeproj`。
    *   **必须**通过 `Localizable.strings` 维护文案，通过 SwiftGen 生成的 `L10n` 枚举引用，**严禁**在代码中硬编码字符串。

---

## 6. 开发计划 (Roadmap)

建议分 4 个阶段交付，每阶段需编译通过。

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
    *   绑定 UI 到 Router 逻辑。

*   **Phase 4: 高级特性**
    *   实现故障转移 (Failover) 和冷却 (Cooldown) 逻辑。
    *   实现 Token 统计与 UI 实时更新。
    *   添加错误重试机制。
