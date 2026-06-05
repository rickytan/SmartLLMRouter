# 📂 产品需求文档 (PRD)：SmartLLM Router

| 项目 | SmartLLM Router (macOS Menu Bar App) |
| :--- | :--- |
| **版本** | v2.0.0 (需求讨论阶段) |
| **状态** | Phase 1-6 已执行，**本 PRD 用于回溯补充遗漏需求** |
| **最近更新** | 补充配置导入导出、模型匹配、模型能力解析、拖拽排序、完整端点代理与质量门禁需求 |
| **目标平台** | macOS 13.0+ (Ventura) |
| **技术栈** | Swift 5.9+, SwiftUI, XcodeGen, SwiftGen, CocoaPods (Swifter, Alamofire, KeychainAccess, Sparkle, CocoaLumberjack) |

> **⚠️ 重要说明**: 本文档在 Phase 1-6 执行后进行了回溯性补充。原始 PRD 遗漏了大量关键需求，导致执行阶段频繁遇到问题。以下新增模块是基于实际执行中发现的坑点和遗漏整理而成，并以“需求讨论阶段”的口径描述，便于未来从零实现时直接参考。**未来新项目应在需求阶段就考虑这些点。**

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

#### C. 模型驱动路由 (Model-Driven Routing) **[核心升级]**
*   **路由键 (Routing Key)**: 请求的 `model` 字段是第一查找键，而非 Channel 优先级排序。
*   **意图提取**: 代理从请求中识别 `Model ID` 和 `Protocol`。
*   **双层降级链**:
    1.  **Layer 1: 同模型冗余 (Exact Match Redundancy)**
        *   **场景**: 用户请求 `model: "gpt-4o"`，首选 Channel 失败。
        *   **动作**: 查找其他 **同样支持 "gpt-4o"** 且健康的 Channel。
        *   **结果**: 用户获得同一模型的不同供应商响应 (无感切换)。
    2.  **Layer 2: 智能降级 (Smart Model Fallback)**
        *   **场景**: 所有支持 "gpt-4o" 的 Channel 全部不可用。
        *   **动作**: 在 **同协议** 下寻找替代模型。
        *   **约束**: 新模型的 `ContextLength` > 实际请求 Tokens；`EstimatedCost` ≤ `maxFallbackCost`。
        *   **结果**: 用户获得替代模型响应 (例如降级到 GPT-4)。
*   **容错透传 (Pass-Through)**:
    *   **场景**: 请求的模型未在代理配置中列出。
    *   **动作**: 转发至最高优先级的活跃 Channel。
    *   **原因**: 保持对上游新模型的最大兼容性，防止因代理配置滞后导致请求失败。

#### D. 模型聚合与协议隔离 (Model Aggregation & Protocol Isolation)
*   **接口**: 拦截 `GET /v1/models`。
*   **聚合逻辑**: 遍历所有 Channel 的模型列表，合并为一个虚拟模型池。
*   **协议隔离规则**:
    *   **OpenAI 请求**: 仅返回协议为 `OpenAI` 或 `Auto (Dual)` 的模型。
    *   **Anthropic 请求**: 仅返回协议为 `Anthropic` 或 `Auto (Dual)` 的模型。
    *   **禁止**: 绝不向客户端展示不属于当前请求协议的模型。
*   **去重策略**: 同名模型取最大 `ContextLength` 和最低价格。

#### E. 熔断器机制 (Circuit Breaker) **[cc-switch 借鉴]**
*   **状态机**: 引入 `Closed` (正常) → `Open` (熔断) → `Half-Open` (半开) 三态流转。
*   **触发条件**: 基于**错误率** (如 10 次请求错 6 次) 或 **连续失败次数** (如连错 5 次)。
*   **半开恢复 (Half-Open Recovery)**:
    *   熔断达到一定时间（如 60s）后，允许 **1 个试探性请求**通过。
    *   成功 → 立即恢复 `Closed` (正常)；失败 → 立即再次 `Open` 并重新计时。
    *   **优势**: 比固定冷却更动态，能快速响应不稳定的服务器。

#### F. 智能重试与修复 (Smart Retry & Rectification) **[cc-switch 借鉴]**
*   **流式错误缓冲 (Stream Error Buffering)**:
    *   **场景**: 在 SSE 流式响应中，如果上游返回非 200 状态码。
    *   **动作**: 暂停转发，**读取完整的错误 Body**。
    *   **目的**: 只有拿到 Body 才能判断是 Key 过期 (401) 还是模型不对 (400)，从而决定是切换通道还是直接报错，防止客户端仅看到“断连”。
*   **Thinking 自动修复 (Thinking Rectification)**:
    *   **场景**: 上游返回 400 报错，信息包含 `budget_tokens exceeded` 或缺少 Beta Header。
    *   **动作**: 
        1. 拦截响应，提取错误原因。
        2. **自动修改**请求 Body 中的 `thinking.budget_tokens` 为安全值，或注入缺失的 Header。
        3. **本地静默重试**一次。
*   **激进的 400 降级**: 即使上游返回 400，在修复重试失败后，依然尝试切换到下一个 Provider 重试（假设不同厂商对参数的宽容度不同）。

#### G. 并发安全控制 (Concurrency Safety)
*   **并发切换锁 (Switch Lock)**:
    *   **场景**: 当多个请求同时发现当前通道不可用时，避免同时触发切换或重置熔断器的逻辑。
    *   **动作**: 同一时间，只允许一个请求执行“切换/状态变更”操作，其他请求排队或等待结果。
    *   **目的**: 保证本地代理状态机的一致性，防止竞态条件导致 Channel 频繁抖动。

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
*   **Flow**: Start -> Auto-popup Settings -> **批量添加 Channel (至少 1 个测试通过)** -> Shell Auto-Config -> Done.
*   **Skip**: 每页提供 "Skip" 选项，允许用户跳过当前步骤。
*   **第 2 页 (Add Channel) 详细规范**: 见 **模块 3.9 (需求定义)** 和 **模块 3.19 (Claude Code 实现指南)**。
    - 支持一次性添加多个厂商/多个 Key
    - 至少 1 个测试通过的 Channel 才能点击 "Next"（除非点击 "Skip"）
    - 内嵌表单展开/收起，不跳转新页面

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

### 3.9 模块九：Onboarding 第 2 页 - 批量添加多厂商/多 Key **[关键需求]**

#### 核心问题
原始设计只允许用户添加**一个** Channel 就进入下一步。实际场景中用户通常有：
- 多个厂商的 API Key（DeepSeek + DashScope + OpenAI）
- 同一厂商多个 Key（用于负载均衡/故障转移）
- 希望首次设置就把所有 Key 配好，而不是后期再进 Settings 逐个添加

#### 需求定义

##### 交互流程
```
第 2 页：批量添加 Channel
┌─────────────────────────────────────────────┐
│  Added Channels (2)                    [+ Add] │
│  ┌──────────────────────────────────────┐   │
│  │ ✅ DeepSeek (OpenAI)    Connected     │   │
│  │ ✅ DashScope (Anthropic) Connected    │   │
│  │ ❌ OpenAI               Invalid Key   │   │
│  └──────────────────────────────────────┘   │
│                                             │
│  [← Back]     [Skip]     [Next → (disabled)]│
└─────────────────────────────────────────────┘
```

##### 行为规范
1.  **初始状态**: 页面打开时显示空列表 + "Add Channel" 按钮
2.  **添加 Channel**:
    - 点击 "Add Channel" 弹出**内嵌表单**（不是跳转新页面）
    - 表单使用**左右分栏布局**（同 3.9 节描述的 Split-pane 设计）
    - 填写完成后点击 "Test & Add"：
      - 先执行连接测试
      - **测试通过**: 自动添加到上方列表，表单清空，可以继续添加下一个
      - **测试失败**: 显示错误信息，不添加到列表，用户可修改后重试
3.  **已添加列表**:
    - 显示每个 Channel 的：厂商图标 + 名称 + 协议 + 测试状态
    - ✅ 绿色 = 测试通过
    - ❌ 红色 = 测试失败（点击可删除）
    - 支持删除已添加的 Channel
4.  **"Next" 按钮状态**:
    - **默认禁用**: 列表中没有任何测试通过的 Channel
    - **启用条件**: 至少有 1 个 Channel 测试状态为 ✅ Connected
    - 显示已添加数量：`Next → (3 channels)`
5.  **"Skip" 按钮**:
    - 始终可用，不受列表状态影响
    - 点击后跳过 Channel 配置，直接进入 Shell Config 步骤
    - 用户可后期在 Settings → Channels 中配置
6.  **数据持久化**:
    - 点击 "Next" 时，将列表中所有测试通过的 Channel 批量写入 `ChannelStore`
    - API Key 存入 Keychain
    - 测试失败的 Channel 不写入（用户需重新测试）

##### 状态机
```
[空列表] → 点击 Add → [表单展开]
                        → Test & Add 成功 → [列表新增 ✅ 项] → 可继续 Add
                        → Test & Add 失败 → [表单保留 + 显示错误] → 可修改重试
                        → 点击 Cancel → [表单收起]

[列表有 1+ 个 ✅] → Next 按钮启用 → 点击 → 批量保存 → 进入下一步
[任意状态] → Skip → 不保存 → 进入下一步
```

---

### 3.10 模块十：Add Channel (Settings) UI 交互需求 **[关键遗漏]**

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

### 3.11 模块十一：自定义厂商支持 **[关键遗漏]**

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

### 3.12 模块十二：协议选择器交互需求

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

### 3.13 模块十三：窗口尺寸需求 **[关键遗漏]**

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

### 3.14 模块十四：macOS 13 兼容性需求 **[关键遗漏]**

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

### 3.15 模块十五：Shell 环境配置需求 **[关键遗漏]**

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

### 3.16 模块十六：工程配置与构建规范 **[关键遗漏]**

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

### 3.17 模块十七：代码级陷阱与命名规范 **[关键遗漏]**

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

### 3.18 模块十八：从 cc switch 类工具/LiteLLM 导入配置 **[新增迁移能力]**

#### 背景
用户可能已经在使用 **ccLoad**, **ccany**, **LiteLLM**, 或 **cc-switch** 等工具。SmartLLM Router 提供**一键导入**功能，实现零成本迁移。

#### 1. 自动探测路径
代理启动 Onboarding 时，后台静默扫描常见路径：
| 工具 | 探测路径 / 文件 | 数据格式 |
|------|---------------|----------|
| **ccLoad** | `~/.cc-load/data.db` | SQLite (Tables: `channels`, `api_keys`) |
| **ccany** | `~/.ccany/data.db` | SQLite (Tables: `channels`, `keys`) |
| **LiteLLM** | `~/.litellm/config.yaml` | YAML (`model_list` definitions) |
| **cc-switch** | `~/.claude/settings.json` | JSON (`apiKey`, `apiHost`) |
| **Env Vars** | 当前 Shell 环境 | `ANTHROPIC_API_KEY` / `OPENAI_API_KEY` |

#### 2. 映射与解析规则
*   **Channel 提取**:
    *   从 SQLite `channels` 表提取 `base_url`, `name`。
    *   从 SQLite `api_keys` 表提取 `key` (解密后)。
    *   根据 URL 特征自动推断协议 (e.g., `/v1` -> OpenAI, `/messages` -> Anthropic)。
*   **去重检测**:
    *   如果 SmartLLM Router 已存在相同 Base URL 的 Channel，跳过导入并提示。
*   **元数据补全**:
    *   导入的 Channel 若缺少模型列表，自动匹配 `providers.json` 补全元数据。

#### 3. Onboarding 交互设计
*   **触发**: Onboarding 首页增加入口 `📦 Import Existing Config`。
*   **预览**:
    *   "Found ccLoad (3 Channels) and LiteLLM (2 Providers)".
    *   列出即将导入的厂商名称（API Key 脱敏）。
*   **执行**:
    *   点击 "Import All"。
    *   Key 存入 Keychain。
    *   Channels 加入本地存储。
    *   自动跳转至"测速"或"完成"步骤。

#### 4. 隐私安全
*   **只读访问**: 仅读取源数据库，**不修改/删除**原工具的配置文件。
*   **本地处理**: 所有解析在本地内存中进行，不上传任何 Key。

#### Channel 初始化器参数顺序
- Swift 初始化器参数有固定顺序，**位置参数必须在标签参数之前**
- `Channel` 定义中 `priority` 在 `protocol` 之前，调用时必须遵循：
  ```swift
  Channel(..., baseURL: "...", priority: 1, protocol: .openai, models: [])
  ```

---

### 3.18 模块十八：凭证安全需求

1.  **API Key 存储**: 必须使用 Keychain，禁止明文存储在 UserDefaults 或文件中
2.  **日志脱敏**: 所有日志中的 API Key/Token 必须显示为 `[REDACTED]`
3.  **测试环境**: UI Test 中需要 Mock Keychain 交互，避免真实 Key 泄露
4.  **导出功能**: 导出配置时自动隐藏 Key（显示为 `sk-...` 或 `[HIDDEN]`）

---

### 3.19 模块十九：Onboarding 第 2 页实现规范 — 给 Claude Code 的执行指南

> 以下是对 Claude Code 的详细实现指令，描述了 Onboarding 第 2 页（Add Channel 步骤）需要如何改造。

#### 改动范围
**文件**: `Sources/Views/Onboarding/OnboardingView.swift`

#### 需要修改的内容

**1. 新增数据结构：临时 Channel 列表**
```swift
// 用于存储待添加的 Channel（尚未持久化）
struct PendingChannel {
    let channel: Channel          // Channel 数据
    let apiKey: String            // API Key（待存入 Keychain）
    let testStatus: TestStatus    // 测试状态
    
    enum TestStatus {
        case testing
        case success
        case failure(String)      // 错误信息
    }
}

@State private var pendingChannels: [PendingChannel] = []
@State private var isAddingChannel: Bool = false  // 控制表单展开/收起
```

**2. 改造 `addChannelStep` 视图结构**

将当前的单 Channel 表单改为：
```
┌──────────────────────────────────────────────────┐
│  Added Channels (2)                        [+ Add]│  ← 点击展开表单
│  ┌────────────────────────────────────────────┐ │
│  │ 🅰️ DeepSeek (OpenAI)       ✅ Connected    │ │  ← 可点击删除
│  │ 🟢 DashScope (Anthropic)   ✅ Connected    │ │
│  │ 🔵 OpenAI                  ❌ Invalid Key   │ │
│  └────────────────────────────────────────────┘ │
│                                                  │
│  [← 表单展开区域 — 复用左右分栏布局]              │
│                                                  │
│  [← Back]     [Skip]     [Next → (2 channels)]  │
└──────────────────────────────────────────────────┘
```

**关键交互逻辑**：

a) **表单展开/收起**：
   - 初始状态：不显示表单，只显示 "Added Channels" 标题 + "[+ Add]" 按钮
   - 点击 "[+ Add]"：在列表下方展开表单（使用 `isAddingChannel` 控制）
   - 表单底部按钮改为 "Test & Add" 和 "Cancel"
   - "Cancel" 收起表单

b) **"Test & Add" 按钮行为**：
   - 点击后执行连接测试
   - **测试通过**: 
     - 将 Channel + API Key 添加到 `pendingChannels` 列表
     - 状态标记为 `.success`
     - 表单清空（重置为初始状态），但**不收起**（方便继续添加下一个）
   - **测试失败**:
     - 不添加到列表
     - 表单保留填写内容
     - 显示错误信息
     - 用户可修改后重试

c) **已添加列表项**：
   - 每行显示：厂商图标 + 名称 + 协议标签 + 测试状态
   - ✅ 成功：绿色 checkmark
   - ❌ 失败：红色 xmark + hover 显示删除按钮
   - 点击 ❌ 项可删除

d) **"Next" 按钮**：
   - `disabled` 条件：`pendingChannels.filter { $0.testStatus == .success }.isEmpty`
   - 显示文字：`"Next → (\(successCount) channels)"`
   - 点击时：将所有 `.success` 状态的 Channel 写入 `ChannelStore`，API Key 存入 `KeychainManager`

e) **"Skip" 按钮**：
   - 位置：在 "Back" 和 "Next" 之间
   - 始终可用，不受 `pendingChannels` 影响
   - 点击：不保存任何 pending Channel，直接进入 `.shellConfig` 步骤

**3. 改造 `canProceed` 逻辑**
```swift
private var canProceed: Bool {
    switch currentStep {
    case .welcome:
        true
    case .addChannel:
        // 至少有 1 个测试通过的 Channel
        pendingChannels.contains { $0.testStatus == .success }
    case .shellConfig:
        true
    case .done:
        true
    }
}
```

**4. 改造 `goToNextStep` 中的 addChannel → shellConfig 逻辑**
```swift
case .addChannel:
    // 只保存测试成功的 Channel
    for pending in pendingChannels where pending.testStatus == .success {
        try? KeychainManager.shared.setAPIKey(pending.apiKey, for: pending.channel.id)
        ChannelStore.shared.addChannel(pending.channel)
    }
    currentStep = .shellConfig
```

**5. 表单组件复用**
- 将现有的左右分栏表单提取为独立组件 `ChannelFormView`
- 接受回调：`onTestAndAdd: (Channel, String) async -> Void`
- 接受回调：`onCancel: () -> Void`
- OnboardingView 和 AddChannelView (Settings) 都复用此组件

#### 必须遵守的约束
1. **不能跳转新页面**: 表单必须在当前页面内展开/收起（使用 `if isAddingChannel` 或 `.sheet` 但不要用 NavigationLink 跳转）
2. **窗口尺寸**: 确保 `DesignToken.Layout.onboardingHeight` >= 500px
3. **L10n 同步**: 新增文案必须手动添加到 `Sources/Generated/L10n.swift`
4. **编译通过**: 提交前必须 `xcodebuild` 编译通过

---

### 3.20 模块二十：自动 Fetch Models + 元信息合并 **[新增]**

#### 背景问题
当前 Onboarding 和 Settings 的添加 Channel 流程中，`Channel.models` 始终为空数组。用户添加 Channel 后需要手动：
1. 在 Settings 中进入编辑
2. 点击 "Fetch Models" 获取模型列表
3. 手动编辑每个模型的元信息（Context Length、Price）

这增加了用户首次配置的负担。

#### 技术可行性
| 能力 | 可行性 | 说明 |
|------|--------|------|
| 自动获取模型列表 | ✅ 可行 | 所有 OpenAI 兼容厂商支持 `/v1/models` 端点 |
| 自动获取元信息 | ⚠️ 部分可行 | OpenAI `/v1/models` **不返回** context length 和 price；少数厂商（OpenRouter）有非标准扩展字段 |
| 从 template 匹配填充 | ✅ 可行 | `ProviderTemplate.default_models` 包含已知模型的元信息 |

#### 需求定义

##### 核心流程
```
用户点击 "Test & Add"
        ↓
1. 连接测试通过 ✅
        ↓
2. 自动调用 fetchModels(channel)
        ↓
3. 对每个返回的模型:
   a. 匹配 template.default_models（按 model identifier）
   b. 匹配成功 → 填充 contextLength、inputPricePer1M、outputPricePer1M
   c. 无匹配 → 保留空元信息（用户后期可在 Settings 中编辑）
        ↓
4. 将填充后的 models 列表写入 Channel
        ↓
5. 添加到 pendingChannels 列表
        ↓
6. 表单清空，可继续添加下一个
```

##### 匹配逻辑
```swift
func mergeModelsWithTemplateMetadata(
    fetchedModels: [ModelEntry],
    template: ProviderTemplate?
) -> [ModelEntry] {
    guard let template = template else {
        return fetchedModels // 自定义厂商，无 template 可匹配
    }
    
    return fetchedModels.map { fetched in
        // 按 identifier 匹配 template 中的 default_models
        if let match = template.defaultModels.first(where: { $0.model == fetched.identifier }) {
            var enriched = fetched
            enriched.contextLength = match.contextLength
            enriched.inputPricePer1M = match.inputPrice
            enriched.outputPricePer1M = match.outputPrice
            return enriched
        }
        // 未匹配的模型保留原样（空元信息）
        return fetched
    }
}
```

##### 在 OnboardingView 中的集成
修改 `testAndAdd()` 方法，在连接测试成功后追加：
```swift
if result.success {
    // 连接测试通过后，自动 fetch models
    let fetchedModels = await channelManager.fetchModels(channel: tempChannel)
    let enrichedModels = mergeModelsWithTemplateMetadata(
        fetchedModels: fetchedModels,
        template: selectedProviderId.flatMap { channelManager.getProviderTemplate(id: $0) }
    )
    
    var finalChannel = tempChannel
    finalChannel.models = enrichedModels
    
    let pending = PendingChannel(
        channel: finalChannel,
        apiKey: apiKey,
        testStatus: .success
    )
    pendingChannels.append(pending)
    resetForm()
}
```

##### UI 反馈
- Fetch models 期间不阻塞主流程（后台异步）
- 如果 fetch 失败：
  - **不阻止** Channel 添加（models 为空不影响功能）
  - 日志记录错误
  - 提示用户："Models fetch failed, you can fetch later in Settings"
- 已添加列表中可选显示模型数量：`DeepSeek (OpenAI) · 3 models ✅`

##### 在 Settings AddChannelView 中的集成
Settings 中的添加 Channel 页面已有 "Fetch Models" 按钮。需要增强：
- 连接测试通过后，**自动触发** fetch models（不需要用户手动点击）
- 如果用户之前手动 fetch 过，不再重复 fetch
- 保持手动 "Fetch Models" 按钮（允许用户刷新）

#### 必须遵守的约束
1. **非阻塞**: fetch models 失败不能阻止 Channel 添加成功
2. **幂等性**: 如果 models 列表已存在（用户手动编辑过），不自动覆盖
3. **超时**: fetch models 设置合理超时（如 10 秒），避免无限等待
4. **日志**: fetch 成功/失败都要记录日志，包含模型数量

---

### 3.21 模块二十一：连接测试改用 GET /v1/models **[关键优化]**

#### 背景问题
当前 `ChannelManager.testConnection(channel:)` 的实现使用 **POST 聊天请求**测试连接：
```swift
let testBody: [String: Any] = [
    "model": "gpt-4o-mini",  // 硬编码 model，很多厂商没有这个模型
    "messages": [["role": "user", "content": "Hi"]],
    "max_tokens": 1,
]
```

**问题**：
1. **浪费 Token**：即使 `max_tokens: 1` 仍消耗输入 + 输出 token
2. **硬编码 model 名称**：用 `gpt-4o-mini` 兜底，但 DeepSeek/DashScope 等厂商没有这个模型，可能返回 404 误判为 URL 错误
3. **慢**：需要等模型推理生成响应
4. **Anthropic 端点要求严格**：`max_tokens` 是必填项，某些厂商校验更严

#### 解决方案
**改用 `GET /v1/models` 测试连接**：
- 只需验证 API Key 是否有效
- 不消耗任何 Token
- 不依赖 model 名称
- 响应快（纯元数据查询）

#### 各厂商 `/v1/models` 支持情况

| 厂商/端点 | 支持 `/v1/models` | 验证结果 |
|-----------|-------------------|----------|
| OpenAI (`api.openai.com`) | ✅ | 标准端点 |
| Anthropic (`api.anthropic.com`) | ✅ | 返回 authentication_error（非 404），端点存在 |
| DeepSeek OpenAI (`api.deepseek.com`) | ✅ | 标准兼容 |
| DeepSeek Anthropic (`api.deepseek.com/anthropic`) | ✅ | 返回 authentication_error，端点存在 |
| DashScope OpenAI | ✅ | 标准兼容 |
| DashScope Anthropic | ⚠️ 需验证 | 空响应，可能不支持，需 fallback 到 POST |
| 其他 OpenAI 兼容厂商 | ✅ | 大部分支持 |

#### 实现方案
```swift
func testConnection(channel: Channel) async -> ConnectionTestResult {
    // 1. 尝试 GET /v1/models（适用于 OpenAI 和 Anthropic 协议）
    let modelsURL = baseURL + "/v1/models"
    var request = URLRequest(url: modelsURL)
    request.httpMethod = "GET"
    request.timeoutInterval = 15  // models 端点响应快，超时更短
    
    // 设置认证头
    if channel.protocol == .anthropic {
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
    } else {
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    }
    
    do {
        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        
        if statusCode == 200 {
            // 解析模型数量（为后续自动填充做准备）
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let models = json["data"] as? [[String: Any]] {
                Log.info("Connection test success, found \(models.count) models")
            }
            return .success()
        } else if statusCode == 401 {
            let errorMsg = extractErrorMessage(data) ?? "Invalid API Key"
            return .failure("❌ Invalid API Key: \(errorMsg)")
        } else if statusCode == 403 {
            // 某些厂商的 /v1/models 端点可能 403 但聊天端点可用
            // Fallback 到 POST 测试
            return await testConnectionByPOST(channel: channel, apiKey: apiKey)
        }
        // ... 其他错误处理
    } catch {
        // Fallback 到 POST 测试
        return await testConnectionByPOST(channel: channel, apiKey: apiKey)
    }
}
```

#### Fallback 策略
```
GET /v1/models
    ↓ 200 → ✅ 成功（同时获取模型列表）
    ↓ 401 → ❌ API Key 无效
    ↓ 403/超时/异常 → Fallback → POST /v1/chat/completions（原有逻辑）
```

#### 对自动 Fetch Models 的影响
- 连接测试成功时已经拿到 `/v1/models` 的响应数据
- 可直接复用该响应，**不需要额外请求**来获取模型列表
- 进一步减少 API 调用次数

#### 必须遵守的约束
1. **不破坏现有行为**: Fallback 确保不支持 `/v1/models` 的厂商仍可正常测试
2. **超时更短**: GET 请求设 15 秒超时（POST 为 30 秒）
3. **日志**: 记录测试方式（GET vs POST fallback）

---

### 3.22 模块二十二：基础 UI 组件库 — 先封装组件再构建页面 **[关键架构调整]**

#### 背景问题
当前项目直接在各页面中写内联视图，没有统一的基础组件层。导致：
1. **样式不一致**：同一种按钮/输入框在不同页面表现不同
2. **重复代码**：hover 效果、圆角、配色逻辑到处复制
3. **维护困难**：改一个全局样式需要改 N 个文件
4. **DesignToken 未充分利用**：有设计系统但页面没有使用组件封装

#### 核心原则
> **先按照视觉规范封装基础组件，再用组件构建页面。不要太着急直接写页面。**

#### 需要封装的基础组件清单

##### 1. 按钮系列 (Buttons)
放在 `Sources/Components/Buttons/` 目录下：

| 组件 | 变体 | 用途 | 样式特征 |
|------|------|------|----------|
| **`PrimaryButton`** | default/disabled/loading | 主要操作（保存、下一步、确认） | 蓝色背景 #007AFF，白色文字，圆角 6pt，hover 加深 |
| **`SecondaryButton`** | default/disabled | 次要操作（取消、返回、稍后设置） | 透明背景，蓝色边框 + 文字，圆角 6pt，hover 浅蓝背景 |
| **`IconButton`** | default/disabled | 纯图标操作（刷新、设置、删除） | 无边框，图标 + hover 背景，28x28pt |
| **`HoverButton`** | default/disabled | 已有，保留但规范化 | 标题 + 图标组合按钮，现有样式保留 |

**统一协议**：
```swift
struct PrimaryButton: View {
    let title: String
    var icon: String? = nil
    var isLoading: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void
}
```

##### 2. 表单组件 (Form)
放在 `Sources/Components/Form/` 目录下：

| 组件 | 用途 | 样式特征 |
|------|------|----------|
| **`FormRow`** | label + content 水平排列 | label 右对齐固定宽度 100pt，content 自适应 |
| **`FormSection`** | 分组标题 + 内容 | 标题 h3 样式，底部细线分隔 |
| **`LabeledTextField`** | 带 label 的文本输入 | label 在上方，input 下方，圆角边框 |
| **`LabeledSecureField`** | 带 label 的密码输入 | 同上，SecureField |
| **`LabeledPicker`** | 带 label 的选择器 | label 在上方，Picker 下方 |

##### 3. 状态组件 (Status)
放在 `Sources/Components/Status/` 目录下：

| 组件 | 用途 | 样式特征 |
|------|------|----------|
| **`StatusIndicatorView`** | 已存在，保留 | 🟢/🔴 圆点 + 脉冲动画 |
| **`StatusBadge`** | 成功/失败/警告标签 | 圆角 4pt，绿/红/黄背景，白色文字，10pt font |
| **`LatencyChip`** | 已存在，保留 | 延迟 ms 展示，颜色按阈值变化 |
| **`EmptyStateView`** | 空数据占位图 | 图标 + 标题 + 描述居中 |
| **`LoadingView`** | 加载中的进度指示 | ProgressView + 可选文字 |

##### 4. 列表组件 (List)
放在 `Sources/Components/List/` 目录下：

| 组件 | 用途 | 样式特征 |
|------|------|----------|
| **`SearchBar`** | 搜索输入框 | 放大镜图标 + 输入框 + 清除按钮，圆角背景 |
| **`ListItem`** | 通用列表行 | hover 背景，左右 padding，分隔线 |
| **`ChannelRowView`** | 已存在，重构到组件目录 | 通道行（图标 + 名称 + 状态 + 延迟） |

##### 5. 卡片组件 (Cards)
放在 `Sources/Components/Cards/` 目录下：

| 组件 | 用途 | 样式特征 |
|------|------|----------|
| **`ProviderCard`** | 厂商选择卡片 | 图标 + 名称，选中高亮，圆角 10pt |
| **`StatCard`** | 统计卡片 | icon + 大数字 + 标签 |
| **`InfoCard`** | 信息提示卡片 | 图标 + 文字，可选关闭按钮 |

##### 6. 协议选择器
放在 `Sources/Components/Protocol/` 目录下：

| 组件 | 用途 | 样式特征 |
|------|------|----------|
| **`ProtocolSelector`** | OpenAI/Anthropic 协议切换 | 芯片按钮组，选中高亮，联动 URL 更新 |

#### 目录结构
```
Sources/
├── Components/
│   ├── Buttons/
│   │   ├── PrimaryButton.swift
│   │   ├── SecondaryButton.swift
│   │   ├── IconButton.swift
│   │   └── HoverButton.swift (从 MenuView 移动)
│   ├── Form/
│   │   ├── FormRow.swift
│   │   ├── FormSection.swift
│   │   ├── LabeledTextField.swift
│   │   ├── LabeledSecureField.swift
│   │   └── LabeledPicker.swift
│   ├── Status/
│   │   ├── StatusIndicatorView.swift (从 MenuView 移动)
│   │   ├── StatusBadge.swift
│   │   ├── LatencyChip.swift (从 MenuView 移动)
│   │   ├── EmptyStateView.swift
│   │   └── LoadingView.swift
│   ├── List/
│   │   ├── SearchBar.swift
│   │   ├── ListItem.swift
│   │   └── ChannelRowView.swift (从 SettingsView 移动)
│   ├── Cards/
│   │   ├── ProviderCard.swift
│   │   ├── StatCard.swift (从 SettingsView 移动)
│   │   └── InfoCard.swift
│   └── Protocol/
│       └── ProtocolSelector.swift
├── Views/          (页面级，使用 Components)
│   ├── MenuView.swift
│   ├── SettingsView.swift
│   └── Onboarding/
├── Models/
├── Services/
└── Utilities/
```

#### 实施步骤
1. **创建 `Sources/Components/` 目录**
2. **逐个组件实现**，每个组件：
   - 使用 `DesignToken` 定义样式
   - 支持 dark mode（通过 Asset Catalog）
   - 支持 hover/press 状态动画
   - 支持 accessibilityIdentifier
3. **迁移现有代码**：将 `HoverButton`、`StatusIndicatorView`、`LatencyChip`、`ChannelRowView`、`StatCard` 移动到对应组件目录
4. **更新所有引用**：页面改为导入组件而非内联实现
5. **编译验证**：确保所有页面使用新组件后编译通过

#### 必须遵守的约束
1. **所有组件必须使用 DesignToken**，禁止硬编码颜色/尺寸
2. **所有交互元素必须有 hover 效果**（0.15s ease-in）
3. **零硬编码字符串**：所有文案使用 L10n.xxx
4. **每个组件必须有 `#Preview`**
5. **组件之间不互相依赖**（除了 DesignToken 和 L10n）

---

### 3.23 模块二十三：UI 组件全面替换审计与执行 **[当前优先级]**

#### 背景
模块 3.22 已创建 21 个基础组件（Buttons 4, Form 5, Status 6, List 3, Cards 3, Protocol 1），但 **4 个 View 文件仍未替换为自定义组件**，存在大量原生 `Button()`、`TextField()`、`SecureField()`、`.buttonStyle(.plain)` 调用。

#### 审计结果

**4 个文件共 50+ 处原生控件待替换**

##### 1. `AddChannelView.swift` — 10+ 处待替换
| 行号 | 原生控件 | 应替换为 | 说明 |
|------|---------|---------|------|
| L130 | `TextField("Search providers...", text: $searchQuery)` | `SearchBar` | 搜索栏 |
| L269 | `TextField("e.g. Local Ollama", text: $customProviderName)` | `LabeledTextField` | 自定义厂商名称 |
| L292 | `TextField("https://api.example.com/v1", text: $baseURL)` | `LabeledTextField` | Base URL |
| L298 | `SecureField("sk-...", text: $apiKey)` | `LabeledSecureField` | API Key |
| L304 | `TextField("", value: $priority, formatter: NumberFormatter())` | `LabeledNumberField` 🆕 | 优先级（需 NumberFormatter 支持） |
| L473 | `TextField("e.g. gpt-4, llama3", text: $newModelName)` | `LabeledTextField` | 模型名 |
| L590 | `Button(L10n.Onboarding.back) { ... }` | `SecondaryButton` | 返回按钮 |
| L722 | `Button("Cancel") { dismiss() }` | `SecondaryButton` | 取消 |
| L725 | `Button("Save") { ... }` | `PrimaryButton` | 保存 |
| L744 | 自定义 TextField 包装函数 | 删除，用 `LabeledTextField` | 冗余包装 |

##### 2. `OnboardingView.swift` — 9+ 处待替换
| 行号 | 原生控件 | 应替换为 | 说明 |
|------|---------|---------|------|
| L339 | `TextField("Search...", text: $searchQuery)` | `SearchBar` | 搜索栏 |
| L411 | `TextField("e.g. Local Ollama", text: $customProviderName)` | `LabeledTextField` | 自定义厂商名称 |
| L433 | `TextField("https://api.example.com/v1", text: $baseURL)` | `LabeledTextField` | Base URL |
| L443 | `SecureField(L10n.Onboarding.apiKeyPlaceholder, text: $apiKey)` | `LabeledSecureField` | API Key |
| L459 | `Button(L10n.Onboarding.cancel) { ... }` | `SecondaryButton` | 取消 |
| L503 | `Button(action: action) { ... }` (内部函数) | `PrimaryButton`/`HoverButton` | ProviderCard 内部按钮 |
| L833/841 | `Button(L10n.Onboarding.skip)` ×2 | `SecondaryButton` | Skip 按钮 |
| L848/855 | `Button(L10n.Onboarding.back)` ×2 | `SecondaryButton` | Back 按钮 |

##### 3. `MenuView.swift` — 3 处待替换
| 行号 | 原生控件 | 应替换为 | 说明 |
|------|---------|---------|------|
| L114 | `Toggle(...)` (代理开关) | `ToggleRow` 🆕 | 菜单内开关 |
| L181 | `Button(action: { ... })` (modelOptionButton) | `HoverButton` | 模型选项按钮 |

##### 4. `SettingsView.swift` — 3 处待替换
| 行号 | 原生控件 | 应替换为 | 说明 |
|------|---------|---------|------|
| L123 | `TextField("", value: $appState.port, formatter: NumberFormatter())` | `LabeledNumberField` 🆕 | 端口号（NumberFormatter） |
| L131 | `Toggle(isOn: $appState.launchAtLogin) { ... }` | `ToggleRow` 🆕 | 开机自启 |
| L256 | `Toggle(L10n.Settings.advancedFailover, isOn: $appState.autoFailover)` | `ToggleRow` 🆕 | 自动故障转移 |

#### 需要新增的组件

##### `ToggleRow` — `Sources/Components/Form/ToggleRow.swift`
```swift
struct ToggleRow: View {
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool
    
    init(_ title: String, subtitle: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
    }
}
```
**样式**: 水平排列，左侧标题(可选副标题)，右侧 Toggle 开关。Hover 时背景变色。使用 DesignToken 颜色/间距。

##### `LabeledNumberField` — `Sources/Components/Form/LabeledNumberField.swift`
```swift
struct LabeledNumberField: View {
    let label: String
    let placeholder: String
    @Binding var value: Int
    
    init(_ label: String, placeholder: String = "", value: Binding<Int>) {
        self.label = label
        self.placeholder = placeholder
        self._value = value
    }
}
```
**样式**: 同 `LabeledTextField`，但内部使用 `TextField` + `NumberFormatter`。支持 `Int` 类型绑定。

#### 实施步骤
1. **先创建 2 个新组件**: `ToggleRow`, `LabeledNumberField`
2. **逐个 View 文件替换**，每个文件完成后编译验证
3. **删除冗余代码**: 如 AddChannelView 中的自定义 TextField 包装函数 (L744)
4. **统一 .buttonStyle(.plain)**: 确保所有自定义按钮内部使用 `.buttonStyle(.plain)`，外部不再需要
5. **全量编译验证**: `xcodegen generate` → `bundle exec pod install` → `xcodebuild` (0 errors)
6. **运行测试**: 确保 45 个单元测试全部通过

#### 必须遵守的约束
1. **零原生控件泄漏**: 替换完成后，4 个 View 文件中不得出现 `Button(`、`TextField(`、`SecureField(`、`Toggle(`、`Picker(`（组件内部实现除外）
2. **所有组件必须使用 DesignToken**: 禁止硬编码颜色/尺寸/间距
3. **零硬编码字符串**: 所有文案使用 `L10n.xxx`
4. **每个新组件必须有 `#Preview`**
5. **编译通过才能提交**: 每次替换后必须编译验证
6. **L10n 同步**: 新增文案必须同步到 `en.lproj/zh-Hans.lproj/Localizable.strings` 和 `Sources/Generated/L10n.swift`
7. **暗黑模式兼容**: 所有新组件通过 Asset Catalog 自动适配 Light/Dark

---

### 3.24 模块二十四：Smart Model Fallback — 透明模型映射兜底 **[新增]**

#### 背景问题
当前的 failover 机制只允许**同模型跨 Channel 重试**（如 `gpt-4o` 在 Channel A 失败后，找 Channel B 的 `gpt-4o`）。但如果所有 Channel 都没有这个模型，或者问题是 `context_length_exceeded` 导致的，现有的 failover 无法解决。

#### 核心能力
当请求失败时，代理可以**自动将模型替换为另一个 context 更大的模型**，对客户端透明（客户端仍然看到原 model 名）。

#### 触发条件

| 错误类型 | 兜底行为 |
|---------|---------|
| `context_length_exceeded` | **直接触发** — 找 context 更大的同协议模型 |
| `429 Rate Limit` | 先找同模型的可用 Channel → 找不到再触发 |
| `5xx Server Error` | 先找同模型的可用 Channel → 找不到再触发 |
| `401 / 403` | **不兜底** — 凭证问题，换模型也没用 |

#### 兜底约束（必须全部满足）

1. **同协议**：OpenAI 请求只能兜底到 OpenAI 协议的模型，Anthropic 同理
2. **更大 context**：兜底模型的 `contextLength` 必须大于当前请求实际使用的 token 数
3. **费用控制**：预估总费用（`(input_tokens + 预估output) × price / 1M`）不超过用户设置的上限
4. **不在冷却期**：目标 Channel 不能处于冷却状态
5. **非当前 Channel**：不能兜底到已经失败的 Channel

#### 兜底决策流程

```
请求: {"model": "gpt-4o", ...}
Channel A (DashScope) → 400 context_length_exceeded (实际用了 95K tokens)

↓ 智能兜底扫描:

候选模型筛选:
  ✅ DeepSeek V4-Flash    (1M context, $0.14/1M)   同协议(OpenAI) ✓, context > 95K ✓
  ✅ Qwen-Max             (32K context, $5.60/1M)  ❌ context 不足
  ✅ Claude Sonnet 4      (200K context, $3.00/1M)  ❌ 不同协议
  ✅ OpenAI o1            (200K context, $15.00/1M)  同协议 ✓, context > 95K ✓

按 context 降序排序 → DeepSeek V4-Flash (1M > o1 的 200K)
检查预估费用: (95K + 预估5K) × $0.14/1M = $0.014 ≤ 用户设置的 $2.00 ✓

决策: → DeepSeek V4-Flash
客户端看到: {"model": "gpt-4o", ...}  不变
代理发出:   {"model": "deepseek-v4-flash", ...}  自动替换
```

#### 用户设置（Advanced Tab 新增 Section）

```
┌────────────────────────────────────────────┐
│  ⚠️ Smart Model Fallback                   │
│                                            │
│  [ ] Enable Smart Model Fallback           │  ToggleRow
│                                            │
│  ⚠️ 开启后，当请求失败或上下文超出时，       │
│  代理会自动将请求转发到其他厂商的更大       │
│  上下文模型（如 gpt-4o → deepseek-v4-flash）。│
│  客户端感知的模型名不变，但实际生成模型     │
│  可能改变。工具调用和结构化输出行为         │
│  在不同模型间可能不一致。                    │
│                                            │
│  Max Fallback Cost   [ $2.00 per request ] │  LabeledNumberField
│      跳过预估费用超过此值的兜底模型         │
│                                            │
└────────────────────────────────────────────┘
```

#### 日志记录

每次兜底必须记录以下信息：

```
[INFO] SmartRouter: Fallback triggered for request req-xxx
  Original model: gpt-4o (Channel: DashScope, Error: context_length_exceeded)
  Fallback model: deepseek-v4-flash (Channel: DeepSeek, Context: 1M tokens)
  Protocol: OpenAI (same protocol)
  Estimated cost: $0.014 (limit: $2.00)
  Retry attempt: 1/3
```

#### 费用计算

```swift
func estimatedFallbackCost(inputTokens: Int, outputTokensEstimate: Int, pricePer1M: Double) -> Double {
    return Double(inputTokens + outputTokensEstimate) * pricePer1M / 1_000_000.0
}
```

- `inputTokens`: 从上游错误响应中获取实际使用量（如 Anthropic 的 `usage.input_tokens`）
- `outputTokensEstimate`: 默认预估 5000 tokens（可配置）
- `pricePer1M`: 使用 `ModelEntry.outputPricePer1M`（如果不可用则用 `inputPricePer1M` 作为 fallback）

#### 实现范围

| 文件 | 改动内容 |
|------|---------|
| `SmartRouter.swift` | 新增 `smartFallbackEnabled` / `maxFallbackCost` 设置，新增 `selectFallbackModel()` 方法 |
| `RequestForwarder.swift` | 模型名重写：在转发前替换 body 中的 `model` 字段 |
| `SettingsView.swift` | Advanced Tab 新增 Smart Model Fallback section |
| `L10n.swift` + strings | 新增兜底相关文案 |
| `UserDefaults` | 新增 `smartllm_smart_fallback_enabled` / `smartllm_max_fallback_cost` 键 |

#### 必须遵守的约束

1. **协议一致性**：兜底模型必须与原始请求的协议兼容（OpenAI ↔ OpenAI，Anthropic ↔ Anthropic）
2. **透明性**：客户端看到的 model 名永远不变，只有代理层和日志记录替换
3. **费用保护**：预估费用超过用户设置上限的模型**绝不**作为兜底目标
4. **日志必记**：每次兜底必须记录完整的原始模型 → 兜底模型 → 费用 → Channel 信息
5. **用户明确知情**：设置项必须有明确的警告文案，告知用户兜底可能影响工具调用兼容性

---


### 3.25 模块二十五：Channel 配置导入导出

#### 背景问题
用户通常会配置多个 Provider / Channel，并为每个 Channel 维护 Base URL、协议、模型列表、模型元数据、优先级与 API Key。更换设备、重装应用、备份配置或在多台 Mac 间迁移时，如果只能手动重新录入，会造成较高迁移成本。

#### 需求定义
1. **导出范围**：用户可以从 Settings → Channels 导出所有 Channel 配置。
2. **导出内容**必须包含：
   - Channel 名称、Provider ID、自定义 Provider 名称
   - Base URL、协议类型、优先级、启用状态
   - 模型列表、显示名称、上下文长度、输入/输出价格
   - 模型输入能力（text / image / audio / video）
   - 与路由相关的必要元数据
3. **API Key 处理**：
   - 默认导出时不得明文泄露 API Key。
   - 用户选择加密导出时，允许将 API Key 一并导出，但必须使用用户输入的密码加密。
   - 未加密导出时，API Key 应为空、脱敏或明确排除。
4. **导入行为**：
   - 支持导入 SmartLLM Router 自己导出的配置文件。
   - 导入前展示预览：将导入多少个 Channel、多少个模型、是否包含加密凭证。
   - 支持合并到现有配置，遇到重复 Channel 时应有明确策略（跳过 / 覆盖 / 生成副本）。
5. **加密导入**：
   - 加密文件导入时必须要求用户输入密码。
   - 密码错误、文件损坏、版本不兼容时应给出明确错误提示。
6. **版本兼容**：导出文件应包含 schema version，未来字段变更时可以做兼容迁移。

#### 验收标准
- [ ] 可以导出未加密配置文件，文件中不包含明文 API Key。
- [ ] 可以导出加密配置文件，API Key 经加密保护。
- [ ] 可以导入未加密配置并恢复 Channel、模型、价格、上下文长度、输入能力与优先级。
- [ ] 可以导入加密配置，密码错误时不会写入任何部分配置。
- [ ] 导入重复 Channel 时行为可预期且不会破坏现有配置。
- [ ] 导入非法 JSON、损坏文件、版本不兼容文件时应用不崩溃。

---

### 3.26 模块二十六：聚合 Provider 模型匹配与跨 Channel 模型选择

#### 背景问题
聚合类 Provider（如 OpenRouter、Nvidia、各类转发服务）经常使用带命名空间的模型 ID，例如 `z-ai/glm-5.1`。但客户端或用户可能只填写基础模型名 `glm-5.1`。如果系统只做完全相等匹配，会出现“模型实际存在但路由失败”的问题。

#### 需求定义
1. **统一匹配入口**：路由器、代理转发、模型选择器必须复用同一套模型匹配函数，禁止在多个文件里散落 `==` 判断。
2. **匹配规则**：
   - 完整 ID 相同：匹配成功。
   - 去除 `/` 前缀后的基础模型名相同：匹配成功。
   - 不同版本、不同基础模型名不得误匹配。
3. **双向匹配**：
   - 请求 `glm-5.1` 可匹配已存模型 `z-ai/glm-5.1`。
   - 请求 `z-ai/glm-5.1` 可匹配已存模型 `glm-5.1`。
4. **跨 Channel 模型选择**：模型选择器应展示所有可用 Channel 的模型聚合结果，而不是只展示当前活跃 Channel 的模型。
5. **去重策略**：展示层可按模型标识去重；路由层仍需保留对应 Channel 信息，以便按优先级选择实际上游。
6. **协议隔离**：跨 Channel 聚合不得破坏 OpenAI / Anthropic 协议隔离规则。

#### 验收标准
- [ ] `z-ai/glm-5.1` 与 `glm-5.1` 可以互相匹配。
- [ ] `glm-5.1` 不会匹配 `glm-5.2`。
- [ ] SmartRouter、ProxyServer、ModelSwitcher 的匹配行为一致。
- [ ] 模型选择器可以看到所有 Channel 聚合后的可用模型。
- [ ] 用户选择模型后，路由器能找到支持该模型的最高优先级健康 Channel。
- [ ] Anthropic 请求不会被展示或路由到只支持 OpenAI 且无法转换的模型。

---

### 3.27 模块二十七：`/v1/models` 模型能力元数据解析

#### 背景问题
不同 Provider 的 `/v1/models` 返回结构并不一致。标准 OpenAI 通常只返回基础字段，而 OpenRouter、SenseNova 等 Provider 会返回额外的模型能力、上下文长度与价格信息。系统需要利用这些元数据自动识别模型是否支持图像、音频、视频等输入类型。

#### 需求定义
1. **输入能力字段解析**：模型拉取逻辑必须支持以下两种位置：
   - 顶层字段：`input_modalities`
   - OpenRouter 风格：`architecture.input_modalities`
2. **默认值**：当 API 不返回能力字段时，模型默认支持 `text` 输入。
3. **能力枚举**：系统至少支持 `text`、`image`、`audio`、`video` 四类输入能力。
4. **其他元数据**：如接口返回 `context_length`、`pricing.prompt`、`pricing.completion`、`name` 等字段，应尽量解析并填充到 `ModelEntry`。
5. **模板合并**：当 API 返回信息不完整时，允许从 `providers.json` 的默认模型模板补齐上下文长度、价格与输入能力。
6. **持久化与迁移**：模型输入能力必须随 Channel 存储、导入导出和 Codable 迁移一起保留。旧字段（如布尔型 vision 能力）应能迁移到新的输入能力数组。
7. **UI 展示**：模型列表应以标签形式展示输入能力，但 UI 文案必须通过 L10n 管理，不能硬编码。

#### 验收标准
- [ ] 可正确解析顶层 `input_modalities`。
- [ ] 可正确解析 `architecture.input_modalities`。
- [ ] 未返回能力字段时默认为 `["text"]`。
- [ ] 支持图像输入的模型在 UI 中显示 IMAGE 能力标签。
- [ ] 支持音频输入的模型在 UI 中显示 AUDIO 能力标签。
- [ ] 导入导出后模型能力信息不丢失。
- [ ] 旧配置数据可以兼容迁移到新的输入能力结构。

---

### 3.28 模块二十八：Channel 拖拽排序与路由优先级

#### 背景问题
Channel 顺序代表用户对 Provider 的优先级偏好。用户可能希望将更稳定、更便宜或更快的 Provider 放在前面，让正常路由和 failover 都优先使用这些 Channel。

#### 需求定义
1. **列表交互**：Settings → Channels 列表支持拖拽排序。
2. **优先级同步**：拖拽完成后，系统应自动按列表顺序更新所有 Channel 的 `priority` 字段，从 1 开始递增。
3. **持久化**：排序结果必须持久化，应用重启后保持一致。
4. **路由影响**：SmartRouter 在选择 Channel、同模型冗余、failover 时都必须遵守新的排序结果。
5. **视觉提示**：行内应提供拖拽手柄或等效视觉提示，让用户知道可以调整顺序。
6. **安全性**：拖拽排序不得影响 API Key、模型列表、测速结果、冷却状态等其他 Channel 数据。

#### 验收标准
- [ ] 用户可以通过拖拽调整 Channel 顺序。
- [ ] 拖拽后 UI 立即反映新顺序。
- [ ] 重启应用后顺序保持不变。
- [ ] Channel 的 `priority` 与列表顺序一致。
- [ ] 路由与 failover 按新顺序选择候选 Channel。
- [ ] 拖拽过程中不会丢失 Channel 配置或 Keychain 凭证关联。

---

### 3.29 模块二十九：完整 OpenAI / Anthropic API 端点代理

#### 背景问题
SmartLLM Router 的定位是本地 API Gateway，而不仅是聊天接口转发器。OpenAI SDK、Anthropic SDK、Claude Code 及周边工具可能访问 `/v1/models`、文件、批处理、消息、聊天补全等多个端点。代理层需要尽量兼容官方 API 的常用路径。

#### 需求定义
1. **端点覆盖**：代理应支持 OpenAI 与 Anthropic 官方 API 的常用端点，不应只支持 chat/messages。
2. **透明代理**：无需协议转换的端点应尽量透明转发，包括 method、path、query、headers、body。
3. **协议转换边界**：只有明确需要转换的聊天/消息类请求才进入协议转换逻辑；其他端点不得误套聊天转换。
4. **认证头替换**：转发上游时必须使用 Channel 中存储的 API Key，不能把客户端传入的本地占位 Key 原样传给上游。
5. **响应协议一致性**：OpenAI 客户端应收到 OpenAI 格式响应，Anthropic 客户端应收到 Anthropic 格式响应。
6. **错误处理**：上游错误应保留必要状态码和错误信息，同时避免泄露敏感认证信息。

#### 验收标准
- [ ] `/v1/chat/completions` 可以正常代理或转换。
- [ ] `/v1/messages` 可以正常代理或转换。
- [ ] `/v1/models` 可以正常代理、聚合或按协议返回。
- [ ] 非聊天端点不会被错误地构造成 chat 请求。
- [ ] 上游认证头来自 Keychain 中的 Channel API Key。
- [ ] 客户端协议预期不被破坏。

---

### 3.30 模块三十：自动 Failover 与 401/403 语义

#### 背景问题
部分 Provider 会用 401 表示模型不可用、认证上下文不匹配或聚合服务转发失败，而不一定总是 API Key 无效。如果系统把所有 401 都视为硬失败，会错过可用的备用 Channel。但 403 通常代表权限不足或账号级限制，盲目重试意义较低。

#### 需求定义
1. **可重试错误**：429、5xx、网络超时、连接失败等应触发 failover。
2. **401 策略**：401 默认允许尝试下一个支持同模型/同协议的 Channel，但必须受最大重试次数限制。
3. **403 策略**：403 默认视为硬阻断，不做无意义的跨 Channel 重试，除非未来引入用户显式配置。
4. **重试边界**：所有 failover 都必须遵守 `maxRetries`，防止循环重试。
5. **冷却机制**：触发失败的 Channel 应按错误类型进入对应冷却期，避免短时间内反复命中同一故障 Channel。
6. **日志记录**：每次 failover 决策必须记录请求 ID、原 Channel、错误类型、目标 Channel、重试次数。

#### 验收标准
- [ ] Channel A 返回 429 时自动尝试 Channel B。
- [ ] Channel A 返回 5xx 或网络超时时自动尝试 Channel B。
- [ ] Channel A 返回 401 时，在重试次数允许范围内尝试下一个候选 Channel。
- [ ] 所有候选 Channel 都返回 401 时能正确终止并返回清晰错误。
- [ ] 403 默认不触发 failover。
- [ ] 日志能还原完整路由和 failover 决策链路。

---

### 3.31 模块三十一：Channel 行实时数据绑定与并发安全

#### 背景问题
测速、冷却状态、用量统计和代理请求计数都可能由异步任务或 Swifter 后台线程更新。如果 UI 行持有旧的 Channel 值拷贝，或 ObservableObject 在后台线程直接发布更新，会导致 UI 不刷新、数据竞争或 SwiftUI 运行时警告。

#### 需求定义
1. **实时绑定**：列表行展示动态数据时，应通过 Channel ID 从 Store 读取最新数据，而不是长期持有值拷贝。
2. **Store 观察**：SwiftUI View 应通过 `@ObservedObject` 或等效机制观察 Store，确保测速结果、冷却状态实时更新。
3. **请求计数原子性**：代理请求 ID / request count 必须线程安全递增。
4. **用量统计线程安全**：UsageTracker 等后台可调用服务应使用串行队列或等效机制保护内部状态。
5. **主线程发布**：所有 `@Published` 更新必须切回主线程发布。
6. **Swifter 线程模型**：所有从请求处理线程调用的服务都必须考虑后台线程访问场景。

#### 验收标准
- [ ] 测速完成后 Channel 行延迟数值立即刷新。
- [ ] Channel 冷却/恢复状态能实时反映在 UI。
- [ ] 高并发请求下 request ID 不重复、不跳乱。
- [ ] Thread Sanitizer 不报告相关数据竞争。
- [ ] 不出现 “Publishing changes from background threads” 警告。

---

### 3.32 模块三十二：窗口激活、嵌套 Sheet 与 macOS UI 兼容

#### 背景问题
菜单栏应用通常以 accessory 模式运行，没有 Dock 图标。macOS 下 `window.makeKeyAndOrderFront` 不一定能把窗口带到前台；SwiftUI `.sheet` 在已由 sheet 呈现的视图中继续嵌套也可能失效。需求阶段必须明确这些平台约束，避免实现阶段出现窗口不可见或弹窗无响应。

#### 需求定义
1. **窗口前置**：从菜单栏、Onboarding 或 Settings 打开窗口前，应显式激活应用。
2. **Accessory App 行为**：应用作为菜单栏工具运行时，不应因为关闭窗口而退出。
3. **嵌套弹窗策略**：需要在 sheet 内再展示编辑器时，应使用 AppKit `NSPanel.beginSheet` 或等效原生方案，不能依赖 SwiftUI 嵌套 `.sheet`。
4. **弹窗生命周期**：AppKit 弹窗必须有明确的关闭回调、代理释放和内存清理策略。
5. **Dismiss 机制**：由 AppKit 管理的弹窗内，SwiftUI View 不应依赖 `@Environment(\.dismiss)`，应通过 `onCancel` / `onSave` 回调关闭。

#### 验收标准
- [ ] Onboarding 和 Settings 从菜单栏打开时出现在前台。
- [ ] 关闭最后一个窗口后菜单栏应用仍继续运行。
- [ ] Add Channel 内的模型元数据编辑器可以稳定打开。
- [ ] ESC、关闭按钮、Cancel、Save 都能正确关闭弹窗。
- [ ] 反复打开关闭弹窗无明显内存泄漏。

---

### 3.33 模块三十三：UI 自动化测试与质量门禁

#### 背景问题
项目存在多步 Onboarding、Settings Tab、Add/Edit Channel、模型元数据编辑、导入导出、拖拽排序等复杂交互。没有 UI 测试时，SwiftUI 重构、组件替换、窗口行为修复很容易引入回归。

#### 需求定义
1. **UI Test 基类**：提供统一的 App 启动参数、通用等待、窗口打开、断言工具和 Accessibility ID 常量。
2. **覆盖范围**：至少覆盖 MenuView、SettingsView、Settings Tab、Onboarding、Add Channel、Channel CRUD、模型元数据编辑器、导入导出入口。
3. **Accessibility ID**：所有可交互元素必须有稳定的 `accessibilityIdentifier`。
4. **ModalPresenter 测试**：AppKit sheet / NSPanel 弹窗应能被 UI Test 定位和关闭。
5. **编译门禁**：UI Test 代码必须保持可编译，避免使用不存在的 API 或错误的 sleep 类型。
6. **执行策略**：UI 测试作为 Hermes 质量门禁的一部分；业务实现由 Claude Code 完成后，Hermes 负责补充/运行测试和审查。

#### 验收标准
- [ ] 所有 UI Test 文件可以编译通过。
- [ ] Add Channel 关键路径可自动化验证。
- [ ] 模型元数据编辑弹窗可自动化验证打开、保存、取消和关闭。
- [ ] Settings Tab 切换可自动化验证。
- [ ] Onboarding 关键流程可自动化验证。
- [ ] Accessibility ID 覆盖关键交互元素。

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
- [ ] Onboarding 是否支持批量添加多个 Channel（不能只添加一个就跳转）
- [ ] Onboarding "Next" 按钮是否有合理的启用条件（至少 1 个测试通过，或提供 Skip 选项）
- [ ] 添加 Channel 后是否自动 fetch models 并填充元信息
- [ ] `/v1/models` 是否解析 input_modalities / architecture.input_modalities 并默认回退为 text
- [ ] 模型能力标签（text/image/audio/video）是否随存储、导入导出和迁移保留
- [ ] 连接测试是否使用 GET /v1/models（而非 POST 聊天请求，避免浪费 token 和硬编码 model）
- [ ] 是否支持 Channel 配置导入导出，并明确未加密/加密导出的 API Key 处理策略
- [ ] 是否支持 Channel 拖拽排序，并确认排序会影响路由和 failover 优先级
- [ ] 是否先封装基础 UI 组件库再构建页面（按钮、表单、状态、列表、卡片、协议选择器）
- [ ] 所有 View 页面是否已完全使用自定义组件替换原生控件（零 Button/TextField/SecureField/Toggle/Picker 泄漏）

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

### 7.7 路由与代理能力
- [ ] 聚合 Provider 模型名是否支持完整 ID 与基础模型名双向匹配
- [ ] 所有模型匹配路径是否复用统一函数，避免散落 `==` 判断
- [ ] 模型选择器是否聚合所有 Channel 的可用模型，而不是只看当前活跃 Channel
- [ ] OpenAI / Anthropic 协议隔离是否在模型展示、路由和 fallback 中保持一致
- [ ] 非聊天端点是否走透明代理，避免误套 chat/messages 转换逻辑
- [ ] 401 / 403 / 429 / 5xx / timeout 的 failover 语义是否分别定义
- [ ] failover 是否受 `maxRetries` 限制并记录完整决策链路
- [ ] 转发上游时是否替换为 Channel Keychain API Key，避免透传客户端占位 Key

### 7.8 质量门禁
- [ ] UI Test 是否覆盖 Onboarding、Settings Tab、Add/Edit Channel、模型编辑、导入导出入口
- [ ] 所有可交互元素是否有稳定 accessibilityIdentifier
- [ ] UI Test 是否避免 `sleep(0.5)`、`.isDisabled` 等已知编译陷阱
- [ ] Hermes 是否只负责 Review、测试、编译与质量门禁，业务/UI 实现交给 Claude Code

