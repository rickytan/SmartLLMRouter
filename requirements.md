# 📂 产品需求文档 (PRD)：SmartLLM Router

| 项目 | SmartLLM Router (macOS Menu Bar App) |
| :--- | :--- |
| **版本** | v1.8.3 |
| **状态** | 待开发 |
| **目标平台** | macOS 13.0+ (Ventura) |
| **技术栈** | Swift 5.9+, SwiftUI, XcodeGen, SwiftGen, CocoaPods (Swifter, Alamofire, KeychainAccess, Sparkle) |

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
[Client (Claude Code)] 
       │
       │ POST /v1/messages
       ▼
[Local Proxy Server (Port 1897)] 
       │
       ├── 1. Router Engine (Priority-based / Auto-Failover)
       ├── 2. Protocol Adapter (Anthropic <-> OpenAI)
       └── 3. Upstream Client (Alamofire)
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
*   **Tooling**: XcodeGen, SwiftGen, CocoaPods

---

## 3. 功能需求详情

### 3.1 模块一：本地代理服务 (Proxy Server)
*   **监听端口**：默认 `localhost:1897`。
*   **路由规则**：拦截 `POST /v1/messages` 和 `/v1/chat/completions`。
*   **处理流**：接收 -> 路由决策 -> 协议转换 -> 上游请求 -> 拦截流响应 -> 转发客户端。

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
*   **Content**: ID, Name, BaseURL, Protocols.
*   **Models 扩展结构**:
    ```json
    {
      "model": "gpt-4o",
      "protocol": "openai",
      "metadata": {
        "context_length": 128000,
        "input_price": 5.00,
        "output_price": 15.00
      }
    }
    ```

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
2.  **隐私**: 严禁数据外发, Keychain 存储, 日志脱敏.
3.  **工程**: XcodeGen 管理工程, SwiftGen 管理多语言.

---

## 6. 开发计划 (Roadmap)

*   **Phase 1**: Infrastructure, XcodeGen, CocoaPods, Proxy Server skeleton, Keychain logic.
*   **Phase 2**: Protocol Adapter (SSE/JSON), Swifter + Alamofire bridging.
*   **Phase 3**: Routing Logic, Menu Bar UI, Settings UI (General/Channels), Speed Test feature.
*   **Phase 4**: Auto-Failover/Cooldown, Usage Stats, Auto-Config Shell, Sparkle Updates.
