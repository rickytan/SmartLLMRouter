# 🚅 SmartLLM Router

A **lightweight, native macOS menu bar proxy** for Claude Code — protocol conversion, silent failover, and token stats across 42+ LLM providers. **100% local, privacy-first.**

> 🇨🇳 [查看中文文档](README_ZH.md)

---

## 🇺🇸 Introduction

**SmartLLM Router** is a lightweight, native macOS menu bar app that runs as a local HTTP proxy. Manage API keys from 42+ LLM providers (DeepSeek, OpenAI, Anthropic, Aliyun, MiniMax, and more) with automatic failover and load balancing — all running locally on your Mac.

### Why SmartLLM Router?

|  | SmartLLM Router | Cloud Proxies |
|---|---|---|
| **Lightweight** | ~8MB native binary, sips resources | Heavy runtimes, Docker required |
| **Native** | Swift + SwiftUI, macOS-native UX | Web UIs, Electron wrappers |
| **Privacy** | 100% local, keys in Keychain | Keys on third-party servers |

### Core Value
1.  **Model-Driven Routing**: Just select a model in your client. The proxy automatically finds the best provider that supports it. No manual switching.
2.  **Invisible Redundancy**: Multiple providers for the same model? If one fails, the proxy silently switches to another. You get the same model, different provider.
3.  **Protocol Isolation**: Strict separation between OpenAI and Anthropic ecosystems. Never see a Claude model in an OpenAI list.
4.  **Zero Client Configuration**: Claude Code only needs `ANTHROPIC_BASE_URL=http://localhost:1897`.
5.  **Privacy First**: 100% Local Execution. No telemetry, no cloud sync. Your API Keys stay in your Mac's Keychain.

### Key Features
*   ✅ **Multi-Provider Support**: Manage keys for Anthropic, OpenAI, DeepSeek, Aliyun DashScope, MiniMax, and more.
*   🔄 **Smart Auto-Failover**: Priority-based routing with intelligent cooldown (handles 429/5xx/401 errors silently).
*   🔀 **Protocol Adapter**: Seamless conversion between Anthropic (Claude) and OpenAI formats.
*   📊 **Real-time Stats**: Track daily token usage and estimated costs (30-day history).
*   📦 **Built-in Provider Metadata**: One-click setup for major providers via `providers.json`.
*   🛡️ **Local & Secure**: API Keys stored in macOS Keychain.

---

## 📥 Install (First-Time Setup)

Download the latest DMG from the [Releases page](https://github.com/rickytan/SmartLLMRouter/releases) and drag **SmartLLMRouter.app** into **Applications**.

> ⚠️ **First-launch Gatekeeper warning is expected.** SmartLLMRouter is currently **ad-hoc signed** — there is no paid Apple Developer certificate behind the build, so macOS will say:
>
> > *"SmartLLMRouter cannot be opened because it is from an unidentified developer."*
>
> The app is open source and built directly from this repo by GitHub Actions. You can verify the build at [Actions](https://github.com/rickytan/SmartLLMRouter/actions) before bypassing.

### Option A — Right-click → Open (recommended)

1. In Finder, **right-click `SmartLLMRouter.app`** in `/Applications` → **Open**
2. Click **Open** again in the warning dialog
3. Done — subsequent launches work normally (double-click)

### Option B — Clear quarantine attribute (one-shot)

```bash
xattr -cr /Applications/SmartLLMRouter.app
open /Applications/SmartLLMRouter.app
```

This removes the `com.apple.quarantine` extended attribute that Gatekeeper checks. Standard practice for ad-hoc signed apps and not specific to SmartLLMRouter.

> 💡 **Why ad-hoc?** Apple Developer Program costs $99/year. While SmartLLMRouter is in alpha, we ship ad-hoc DMGs to keep distribution free and the build pipeline reproducible. Sparkle auto-update is intentionally disabled in this release — check the Releases page manually for new versions.

---

## 🎯 Typical Use Cases

### Use Case 1: Claude Code with Multiple API Providers

The most common scenario — a developer uses Claude Code for daily work, with API keys from multiple providers for redundancy.

```mermaid
flowchart LR
    CC[Claude Code] -->|"POST /v1/messages\nmodel: deepseek-v4-flash"| Proxy[SmartLLM Proxy\n:1897]
    
    Proxy --> DS[DeepSeek\nPriority 1]
    Proxy --> NS[Nvidia\nPriority 2]
    Proxy --> SN[Sensenova\nPriority 3]
    
    DS -->|200 OK| Proxy
    Proxy -->|SSE Stream| CC
    
    style Proxy fill:#007AFF,color:#fff
    style DS fill:#00C853,color:#fff
    style NS fill:#76B900,color:#fff
    style SN fill:#FF9800,color:#fff
```

**Flow:**
1. Claude Code sends `model: "deepseek-v4-flash"` to `localhost:1897`
2. Proxy checks: DeepSeek supports `deepseek-v4-flash`? → Yes → Forward to DeepSeek
3. DeepSeek responds → Stream back to Claude Code
4. If DeepSeek is down → Auto-fallback to Nvidia (if it also supports the model)

**Setup:**
```bash
export ANTHROPIC_BASE_URL=http://localhost:1897
claude
```

---

### Use Case 2: Rate Limit Failover (429 Handling)

When a provider hits rate limits, SmartLLM Router automatically retries with another provider — no interruption to your workflow.

```mermaid
flowchart TD
    Start([Claude Code Request]) --> Proxy[SmartLLM Proxy]
    
    Proxy --> P1{Priority 1\nDeepSeek}
    P1 -->|429 Rate Limited| CB[Circuit Breaker\nRecords Failure]
    P1 -->|200 OK| Success([Response Streamed])
    
    CB --> Cooldown[Cooldown 30min]
    Cooldown --> P2{Priority 2\nNvidia}
    P2 -->|200 OK| Success
    
    P2 -->|Error| P3{Priority 3\nSensenova}
    P3 -->|200 OK| Success
    P3 -->|Error| Fail([Return Error])
    
    style P1 fill:#FF5252,color:#fff
    style P2 fill:#76B900,color:#fff
    style P3 fill:#FF9800,color:#fff
    style Success fill:#00C853,color:#fff
```

**What happens:**
1. DeepSeek returns `429 Too Many Requests`
2. Circuit Breaker records failure, marks DeepSeek as "cooling down" (30 min)
3. Proxy automatically retries with Nvidia (Priority 2)
4. Nvidia returns 200 → Response streamed to Claude Code
5. Developer sees no interruption — the same model name works regardless of provider

---

### Use Case 3: Context Length Exceeded → Smart Model Fallback

When a request exceeds a model's context window, the proxy intelligently routes to a compatible model with larger capacity.

```mermaid
flowchart TD
    Request([Request: model=gpt-4o\nmessages: 200K tokens]) --> Router[Smart Router]
    
    Router --> Check{Model Supports\n200K Context?}
    Check -->|gpt-4o: 128K\nExceeded| Fallback[Smart Fallback\nFind Compatible Model]
    
    Fallback --> Search{Find Same Protocol\nwith Larger Context}
    Search -->|gpt-4o-mini: 128K\nStill insufficient| Search2{Try GPT-4.1\n1M context}
    Search2 -->|Available &\nWithin Cost Limit| Forward[Forward to\ngpt-4.1]
    Search2 -->|Not Available| Default[Pass-Through to\nDefault Channel]
    
    Forward --> Response([Response Returned])
    Default --> Response
    
    style Request fill:#007AFF,color:#fff
    style Fallback fill:#FF9800,color:#fff
    style Forward fill:#00C853,color:#fff
```

**Decision logic:**
1. Request asks for `gpt-4o` with 200K tokens → exceeds 128K context
2. Layer 1: Try other channels with `gpt-4o` → Same limit
3. Layer 2: Find compatible model (same protocol, larger context) → `gpt-4.1` (1M context)
4. Verify cost constraint → Within budget → Forward to `gpt-4.1`
5. Claude Code receives response as if nothing happened

---

### Use Case 4: Protocol Conversion (Anthropic ↔ OpenAI)

Claude Code speaks Anthropic protocol, but your best provider only supports OpenAI format. SmartLLM Router handles the conversion transparently.

```mermaid
flowchart LR
    CC[Claude Code] -->|Anthropic Protocol\n/v1/messages| Proxy[SmartLLM Proxy]
    
    subgraph Conversion [Protocol Adapter]
        direction TB
        Detect[Detect: Anthropic Request]
        Convert[Convert: Anthropic → OpenAI]
        Detect --> Convert
    end
    
    Proxy --> Conversion
    Conversion -->|OpenAI Protocol\n/v1/chat/completions| Provider[Provider API]
    
    Provider -->|OpenAI SSE Stream| Proxy
    
    subgraph Reverse [Reverse Conversion]
        direction TB
        Detect2[Detect: OpenAI Response]
        Convert2[Convert: OpenAI → Anthropic SSE]
        Detect2 --> Convert2
    end
    
    Proxy --> Reverse
    Reverse -->|Anthropic SSE Stream| CC
    
    style Proxy fill:#007AFF,color:#fff
    style Conversion fill:#FF9800,color:#fff
    style Reverse fill:#FF9800,color:#fff
```

**What's converted:**
- **Request**: System prompt injection, thinking parameter handling, tool definitions
- **Response**: OpenAI delta chunks → Anthropic SSE events, usage statistics mapping
- **Headers**: `Authorization: Bearer` ↔ `x-api-key` (protocol-specific auth)

---

### Use Case 5: Local Model + Cloud Hybrid

Developers running local models (Ollama, vLLM) alongside cloud APIs — SmartLLM Router unifies them behind a single endpoint.

```mermaid
flowchart TD
    CC[Claude Code / OpenAI SDK] --> Proxy[SmartLLM Proxy\n:1897]
    
    Proxy --> Route{Route by Model}
    Route -->|llama-3.3-70b| Ollama[Ollama\nlocalhost:11434]
    Route -->|deepseek-v4-flash| Cloud1[DeepSeek Cloud]
    Route -->|gpt-4o| Cloud2[OpenAI API]
    Route -->|custom-model| VLLM[vLLM Server\n:8080]
    
    Ollama --> Proxy
    Cloud1 --> Proxy
    Cloud2 --> Proxy
    VLLM --> Proxy
    
    Proxy --> CC
    
    style Proxy fill:#007AFF,color:#fff
    style Ollama fill:#FF6B6B,color:#fff
    style VLLM fill:#9C27B0,color:#fff
```

**Setup in SmartLLM Router:**
- Add Ollama as a "Custom / Local" provider with `http://localhost:11434/v1`
- Add cloud providers with their respective API keys
- Configure model lists for each channel

**Result:** One `localhost:1897` endpoint serves all models — local and cloud.

---

### Use Case 6: Configuration Migration

Migrating from other tools (cc-switch, LiteLLM, ccLoad) to SmartLLM Router with zero data loss.

```mermaid
flowchart LR
    Old1[cc-switch\n~/.claude/settings.json] -->|Import| Import[Config Importer]
    Old2[LiteLLM\n~/.litellm/config.yaml] -->|Import| Import
    Old3[Env Variables\nANTHROPIC_API_KEY] -->|Detect| Import
    
    Import --> Preview[Preview\nFound 3 Channels]
    Preview -->|Import All| Store[SmartLLM Router\nChannelStore + Keychain]
    
    Store --> Ready([Ready to Use])
    
    style Import fill:#FF9800,color:#fff
    style Store fill:#00C853,color:#fff
```

**Migration flow:**
1. Onboarding detects existing config files
2. Shows preview: "Found cc-switch (2 keys) and LiteLLM (3 providers)"
3. User clicks "Import All"
4. Channels and keys are imported (keys stored in Keychain)
5. Ready to use immediately

---

## 🏗️ Architecture

```mermaid
flowchart TD
    Client((Claude Code)) -- request --> ProxyNode[SmartLLM Proxy]
    
    subgraph ProxyCore [Proxy Core]
        direction TB
        Detect[1. Protocol Detection]
        Extract[2. Intent Extraction]
        Match[3. Channel Matching]
        Check{4. Healthy?}
        L1[Layer 1: Same Model]
        L2[Layer 2: Compatible Model]
        L3[Layer 3: Pass-Through]
        Convert[5. Protocol Conversion]
        
        Detect --> Extract --> Match --> Check
        Check -- No --> L1 --> L2 --> L3 --> Convert
        Check -- Yes --> Convert
    end

    ProxyNode --> ProxyCore
    Convert -- forward --> UpstreamAPI((Upstream API))
    UpstreamAPI -- response --> ProxyNode
    
    subgraph Metrics [Metrics & Privacy async]
        Usage[7. Usage Tracking]
        Log[8. Local Logging]
    end
    
    ProxyNode -. track .-> Metrics
    ProxyNode -- stream --> Client
```

### Core Workflow
1.  **Detection & Extraction**: Claude Code sends requests to the local proxy, automatically identifying the protocol and extracting the requested model.
2.  **Model-Driven Routing**: Matches the best provider for the model, with a three-layer fallback guarantee.
3.  **Protocol Conversion**: Transparently handles the conversion between OpenAI and Anthropic protocols.
4.  **Privacy Stats**: Locally records Token consumption and estimated costs.
5.  **Response Streaming**: Converted response streams are returned to Claude Code.

---

## 📉 Fallback Strategy

SmartLLM Router implements a **Layered Fallback** strategy with **Circuit Breaker** protection.

```mermaid
flowchart TD
    Start((Request Received)) --> Error{Error Occurred?}
    
    Error -- No --> Success[Return Success Response]
    Error -- Yes --> TypeCheck{Check Error Type}
    
    TypeCheck -- "401 / 403 Auth" --> Block[Block: Credential Invalid]
    TypeCheck -- "400 Context Exceeded" --> L2[L2: Compatible Model]
    TypeCheck -- "429 / 5xx" --> RetryCheck{Retries < Max?}
    
    RetryCheck -- No --> MaxRetries[Return Error: Max Retries]
    
    RetryCheck -- Yes --> CircuitBreaker{Channel Healthy?}
    
    CircuitBreaker -- "No (Tripped)" --> Remove[Remove from Pool]
    CircuitBreaker -- "Yes" --> Pool[Select from Available]
    
    Remove --> Pool
    
    Pool --> L1[L1: Same Model Redundancy]
    L1 --> L2
    L2 --> L3[L3: Default Pass-Through]
    L3 --> Retry[Retry Request]
    
    Retry --> Start
```

### Fallback Layers
*   **Layer 1 (Same Model)**: Tries other channels with the **exact same model**. Best for rate limits.
*   **Layer 2 (Compatible Model)**: Tries a **same-protocol** model with larger context. Used for `context_length_exceeded`.
*   **Layer 3 (Pass-Through)**: Falls back to the default channel as a last resort.

### Circuit Breaker
*   **Closed**: Normal operation.
*   **Open**: Channel failed too many times. Temporarily excluded.
*   **Half-Open**: After cool-down, a probe request tests recovery.

---

## 🛠️ Development Guide

### Prerequisites
- macOS 13.0+
- Xcode 15.0+
- Homebrew (for Ruby 3.1)

### Build Steps (Strict Order)

```bash
# Step 1: Generate Xcode Project
xcodegen generate

# Step 2: Install Dependencies
bundle exec pod install

# Step 3: Generate Localization Code
swiftgen config run

# Step 4: Build
xcodebuild -workspace SmartLLMRouter.xcworkspace -scheme SmartLLMRouter -destination 'platform=macOS' build
```

### Run Tests
```bash
xcodebuild test -workspace SmartLLMRouter.xcworkspace -scheme SmartLLMRouter -destination 'platform=macOS' -only-testing:SmartLLMRouterTests
```

---

## 🚀 Usage

### Quick Start
1.  **Install & Launch**: Run the app. First launch opens the Onboarding Wizard.
2.  **Configure Channel**: Follow the wizard to add your API Key.
3.  **Auto-Config Shell**: Click **"Help me configure"** in Settings to update `.zshenv`.
4.  **Start Coding**:

```bash
export ANTHROPIC_BASE_URL=http://localhost:1897
claude
```

### Manual Setup
```bash
export ANTHROPIC_BASE_URL=http://localhost:1897
export ANTHROPIC_API_KEY=placeholder # The proxy handles the real key
```

---

## 🛣️ Roadmap

*   [x] **Phase 1**: Infrastructure, XcodeGen, CocoaPods setup.
*   [x] **Phase 2**: Core Proxy Server & Protocol Adapter.
*   [x] **Phase 3**: Routing Engine, Menu Bar UI, Settings UI, Dark Mode.
*   [x] **Phase 4**: Auto-Failover, Cooldown Engine, Usage Stats, Auto-Config Shell, Sparkle.
*   [x] **Phase 5**: Smart Model Fallback, 27-Component UI Library, Connection Test.
*   [ ] **Phase 6**: Advanced Metrics Dashboard, Zero-Cost Health Checks.

---

## 📄 License

This project is open-source and available under the MIT License.
