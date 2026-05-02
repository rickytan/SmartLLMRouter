# 🚅 SmartLLM Router

A privacy-first local API gateway for LLMs, specifically optimized for **Claude Code**.
专为 **Claude Code** 设计的隐私优先本地 LLM API 网关。

---

# 🇺🇸 Introduction

**SmartLLM Router** is a native macOS menu bar application that acts as a local HTTP gateway. It allows you to manage multiple API Keys from different providers (DeepSeek, OpenAI, Anthropic, Aliyun, MiniMax, etc.) and provides automatic failover and load balancing.

### Core Value
1.  **Zero Client Configuration**: Claude Code only needs to configure `ANTHROPIC_BASE_URL=http://localhost:1897`.
2.  **Transparent Routing**: Switch providers seamlessly or enable Auto-Failover for high availability.
3.  **Protocol Compatibility**: Automatically converts between Anthropic and OpenAI protocols (JSON & SSE).
4.  **Privacy First**: 100% Local Execution. No telemetry, no cloud sync. Your API Keys stay in your Mac's Keychain.

### Key Features
*   ✅ **Multi-Provider Support**: Manage keys for Anthropic, OpenAI, DeepSeek, Aliyun DashScope, MiniMax, and more.
*   🔄 **Smart Auto-Failover**: Priority-based routing with intelligent cooldown (handles 429/5xx/401 errors silently).
*   🔀 **Protocol Adapter**: Seamless conversion between Anthropic (Claude) and OpenAI formats.
*   📊 **Real-time Stats**: Track daily token usage and estimated costs (30-day history).
*   📦 **Built-in Provider Metadata**: One-click setup for major providers via `providers.json`.
*   🛡️ **Local & Secure**: API Keys stored in macOS Keychain.

---

# 🇨🇳 简介

**SmartLLM Router** 是一款原生 macOS 菜单栏应用，作为一个本地 HTTP 网关运行。它允许你管理来自不同提供商（DeepSeek、OpenAI、Anthropic、阿里百炼、MiniMax 等）的多个 API Key，并提供自动故障转移和负载均衡能力。

### 核心价值
1.  **零配置客户端**：Claude Code 只需配置 `ANTHROPIC_BASE_URL=http://localhost:1897`。
2.  **透明路由**：无缝切换提供商，或开启自动故障转移以实现高可用性。
3.  **协议兼容**：自动处理 Anthropic 与 OpenAI 之间的请求/响应格式转换 (JSON & SSE)。
4.  **隐私优先**：100% 本地运行。无遥测，无云同步。API Key 仅存储在您的 Mac Keychain 中。

### 功能特性
*   ✅ **多厂商支持**：管理 Anthropic, OpenAI, DeepSeek, 阿里百炼, MiniMax 等渠道的 Key。
*   🔄 **智能自动切换**：基于优先级的路由，具备智能冷却机制（自动静默处理 429/5xx/401 错误）。
*   🔀 **协议适配器**：Anthropic (Claude) 与 OpenAI 格式之间的无缝转换。
*   📊 **实时统计**：追踪每日 Token 消耗和预估费用（30 天历史记录）。
*   📦 **内置供应商配置**：通过 `providers.json` 实现主流厂商的一键初始化。
*   🛡️ **本地安全**：API Key 存储在 macOS Keychain，数据绝不外发。

---

# 🏗️ Architecture / 系统架构

```text
[Client (Claude Code)] 
       │
       │ POST /v1/messages (Model: claude-3-5-sonnet)
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

---

# 🚀 Usage / 使用指南

### 1. Quick Start / 快速开始
1.  **Configure Channel**: Open Settings (⚙️) -> Add your API Key (e.g., DeepSeek or OpenAI).
2.  **Setup Shell**: Click **"Help me configure"** (⚙️ Setup Shell Environment) in Settings to automatically update your `.zshrc`.
3.  **Start Coding**: Open your terminal and run Claude Code.

   ```bash
   # If you used the auto-config, this is already done:
   export ANTHROPIC_BASE_URL=http://localhost:1897
   
   claude
   ```

### 2. Manual Setup / 手动设置
You can also manually export the variables in your shell profile:
```bash
export ANTHROPIC_BASE_URL=http://localhost:1897
export ANTHROPIC_API_KEY=placeholder # The proxy will handle the real key
```

---

# 🛠️ Tech Stack / 技术栈

*   **Language**: Swift 5.9+ & SwiftUI
*   **Project**: XcodeGen (No `.xcodeproj` in repo)
*   **Dependency Manager**: CocoaPods
*   **HTTP Server**: Swifter
*   **HTTP Client**: Alamofire
*   **Security**: KeychainAccess
*   **Updates**: Sparkle
*   **Localizations**: SwiftGen

---

# 🛣️ Roadmap / 开发计划

*   [x] **Phase 1**: Infrastructure, XcodeGen, CocoaPods setup, PRD Finalization.
*   [ ] **Phase 2**: Core Proxy Server & Protocol Adapter (SSE/JSON Transform).
*   [ ] **Phase 3**: Routing Engine, Menu Bar UI, Settings UI, `providers.json`.
*   [ ] **Phase 4**: Auto-Failover Logic, Usage Stats, Auto-Config Shell, Sparkle Integration.

---

# 📄 License / 许可证

This project is open-source and available under the MIT License.
本项目是开源的，基于 MIT 许可证。
