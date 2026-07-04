# SmartLLMRouter — SSE 流式协议转换修复方案

## 问题

Claude Code CLI 无法通过 SmartLLMRouter 代理使用。配置 `ANTHROPIC_BASE_URL=http://localhost:1897` 后启动，报错：
```
There's an issue with the selected model
```

## 根因

流式请求（`stream: true`）的响应路径存在两个缺陷：

### 缺陷 1：SSE 响应格式未转换

代理将请求体从 Anthropic → OpenAI 正确转换后转发到上游，但上游返回的 OpenAI SSE chunks（`chat.completion.chunk`）直接透传给客户端，没有转换为 Anthropic SSE 格式。

Claude Code 期望的 Anthropic SSE 事件格式：
```
event: message_start
data: {"type":"message_start","message":{...}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}

event: content_block_stop
data: {"type":"content_block_stop","index":0}

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{...}}

event: message_stop
data: {"type":"message_stop"}
```

实际收到的 OpenAI SSE 格式：
```
data: {"object":"chat.completion.chunk","choices":[{"delta":{"content":"Hello"}}]}
```

### 缺陷 2：无真正流式传输

`HTTPForwardingClient.forwardSync` 使用 `URLSession.shared.data(for:)`，将整个响应缓冲为 Data 后一次性返回。对于长时间运行的生成请求（可能 30-120 秒），客户端必须等待全部完成后才收到数据。

## 修复范围

### 文件变更

| 文件 | 变更类型 | 说明 |
|------|---------|------|
| `Sources/Services/ProtocolConverter.swift` | 修改 | 新增 SSE chunk 转换方法 |
| `Sources/Services/HTTPForwardingClient.swift` | 修改 | 新增流式转发方法 |
| `Sources/Services/StreamingForwarder.swift` | **新增** | 流式 SSE 转发协调器 |
| `Sources/Services/ProxyServer.swift` | 修改 | 流式路径接入 StreamingForwarder |
| `Sources/Services/ProxyEndpointSupport.swift` | 修改 | 新增流式响应构建方法 |

### 不变更

- 非流式请求路径（已正常工作）
- 请求体协议转换（已正常工作）
- 错误处理和重试逻辑（流式路径需要独立处理）

---

## 详细设计

### 1. ProtocolConverter — SSE Chunk 转换

新增两个静态方法：

#### `openAItoAnthropicSSEChunk(openAIEvent: SSEEvent, messageID: String, model: String) -> [String]`

将单个 OpenAI SSE chunk 转换为一个或多个 Anthropic SSE 事件字符串。

**转换映射：**

| OpenAI delta 字段 | Anthropic 事件 | 说明 |
|-------------------|---------------|------|
| `delta.role == "assistant"` (首个 chunk) | `message_start` + `content_block_start` | 生成消息头和文本块开始 |
| `delta.content` 非空 | `content_block_delta` (text_delta) | 文本增量 |
| `delta.tool_calls` | `content_block_start` (tool_use) + `content_block_delta` (input_json_delta) | 工具调用 |
| `delta.reasoning_content` | `content_block_start` (thinking) + `content_block_delta` (thinking_delta) | 推理内容（如 Doubao 的 reasoning_content） |
| `finish_reason == "stop"` | `message_delta` (stop_reason: end_turn) + `message_stop` | 结束 |
| `finish_reason == "length"` | `message_delta` (stop_reason: max_tokens) + `message_stop` | Token 限制 |
| `finish_reason == "tool_calls"` | `message_delta` (stop_reason: tool_use) + `message_stop` | 工具调用结束 |
| `data: [DONE]` | `message_stop`（如果还没发过） | 流结束标记 |

**状态机需要跟踪：**
- `messageStarted: Bool` — 是否已发送 message_start
- `currentContentBlockIndex: Int` — 当前内容块索引
- `currentBlockType: String?` — 当前块类型（text/tool_use/thinking）
- `toolCallStates: [Int: ToolCallState]` — 按 index 跟踪工具调用状态

#### `anthropicToOpenAIRequestSSEChunk(anthropicEvent: SSEEvent) -> [String]`

反向转换（OpenAI 客户端 → Anthropic 上游），暂不需要实现，留作未来扩展。

### 2. HTTPForwardingClient — 流式转发

新增方法：

```swift
func forwardStreaming(
    url: URL,
    method: String,
    headers: [String: String],
    body: Data,
    timeout: TimeInterval,
    onChunk: @escaping (Data) -> Void,
    onComplete: @escaping (Int, [String: String]) -> Void,
    onError: @escaping (Error) -> Void
)
```

**实现方案：** 使用 `URLSession` delegate 模式

```swift
class StreamingSessionDelegate: NSObject, URLSessionDataDelegate {
    var onChunk: (Data) -> Void
    var onComplete: (Int, [String: String]) -> Void
    var onError: (Error) -> Void
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, 
                    didReceive data: Data) {
        onChunk(data)  // 每收到一块数据立即回调
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, 
                    didCompleteWithError error: Error?) {
        if let error { onError(error) }
        else { onComplete(statusCode, headers) }
    }
}
```

**关键点：**
- 使用 `URLSessionConfiguration.default` 创建独立 session
- 设置合理的 `timeoutIntervalForRequest`（如 10 秒，用于连接超时）
- `timeoutIntervalForResource` 设为 120 秒（整个流的超时）
- 在 onError/onComplete 中 invalidate session

### 3. StreamingForwarder — 流式协调器（新文件）

这是核心协调组件，负责：

1. 建立到上游的流式连接
2. 逐块解析 OpenAI SSE
3. 逐块转换为 Anthropic SSE
4. 逐块写入客户端 socket

```swift
final class StreamingForwarder {
    let upstreamURL: URL
    let headers: [String: String]
    let body: Data
    let targetProtocol: RequestForwarder.RequestProtocol
    let incomingProtocol: RequestForwarder.RequestProtocol
    let messageID: String
    let model: String
    
    func start(
        writer: HttpResponseBodyWriter,
        onComplete: @escaping (StreamMetrics) -> Void
    ) throws
}
```

**流程：**

```
Client (Claude Code)
  │  POST /v1/messages {stream: true}
  │  Anthropic SSE format expected
  ▼
ProxyServer.handleStreamingRequest()
  │  1. 路由选择 channel
  │  2. 请求体 Anthropic → OpenAI 转换
  │  3. 创建 StreamingForwarder
  ▼
StreamingForwarder.start(writer:)
  │  1. HTTPForwardingClient.forwardStreaming() → 建立上游连接
  │  2. 收到上游 OpenAI SSE chunks
  │  3. SSEParser.parse(chunk) → [SSEEvent]
  │  4. ProtocolConverter.openAItoAnthropicSSEChunk() → [String]
  │  5. SSEEncoder.encode() → Anthropic SSE 文本
  │  6. writer.write(anthropicSSEData) → 写入客户端 socket
  ▼
Client receives Anthropic SSE stream
```

### 4. ProxyServer — 流式路径接入

在 `handleRequestSync` 中，当 `isStream == true` 且需要协议转换时，调用新的流式处理路径：

```swift
// 现有代码（同步路径）
if isStream && incomingProtocol != upstreamProtocol {
    return handleStreamingRequest(
        request: request,
        channel: channel,
        apiKeys: apiKeys,
        routingDecision: routingDecision,
        bodyData: forwardedBody,
        incomingProtocol: incomingProtocol,
        upstreamProtocol: upstreamProtocol,
        reqId: reqId,
        startTime: startTime
    )
}

// 非流式路径保持不变
```

**流式路径的错误处理：**
- 上游返回非 2xx：缓冲完整错误 body，返回 JSON 错误响应
- 上游连接失败：返回 502
- 上游流中断：发送 `message_stop` 事件，记录不完整响应

### 5. ProxyEndpointSupport — 流式响应构建

```swift
static func streamingResponse(
    writer: @escaping (HttpResponseBodyWriter) throws -> Void
) -> HttpResponse {
    return .raw(200, "OK", ["content-type": "text/event-stream"], writer)
}
```

---

## 需要处理的边界情况

### 1. 上游返回错误（非 2xx）

流式请求的上游可能返回非 2xx 状态码（如 401、429、500）。此时上游返回的是普通 JSON 错误，不是 SSE 流。

**处理：** 在建立流式连接后，先检查 HTTP 状态码。如果不是 2xx，缓冲完整 body 并返回标准错误响应（复用现有的错误处理和重试逻辑）。

### 2. 上游流中断

网络问题可能导致上游 SSE 流中途断开。

**处理：** 收到 `URLSession` 的 `didCompleteWithError` 时，如果还没发送 `message_stop`，补发一个。

### 3. OpenAI SSE 格式变体

不同 OpenAI 兼容 API 的 SSE 格式可能有细微差异：
- 某些 API 在最后一个 chunk 的 `usage` 字段中返回 token 计数
- `reasoning_content` 字段（DeepSeek、Doubao 等）
- `tool_calls` 的 `arguments` 是分块发送的

**处理：** SSEParser 已经能处理标准 SSE 格式。转换逻辑需要处理所有 delta 字段变体。

### 4. 大量工具调用

Claude Code 可能一次调用多个工具。OpenAI 格式的 `tool_calls` 按 `index` 分块发送，需要按 index 聚合后转换为 Anthropic 格式的 `tool_use` content_block。

**处理：** 维护 `toolCallStates` 字典，按 index 跟踪每个工具调用的 name、id、arguments 累积。在 `finish_reason == "tool_calls"` 时发送所有 tool_use block 的 content_block_stop。

### 5. 思考/推理内容

OpenAI 兼容 API（Doubao、DeepSeek）在 `delta.reasoning_content` 中返回推理过程。

**处理：** 将 `reasoning_content` 转换为 Anthropic 的 `thinking` content_block。注意 Anthropic 原生 API 的 thinking 格式可能不同，但 Claude Code 应该能接受 `thinking` 类型的 content_block。

---

## 测试方案

### 单元测试

1. **ProtocolConverter.openAItoAnthropicSSEChunk** 测试：
   - 纯文本流（role chunk → content chunks → finish chunk → [DONE]）
   - 工具调用流（role → tool_calls → finish → [DONE]）
   - 推理+文本流（reasoning_content → content → finish → [DONE]）
   - 混合内容（text + tool_calls）
   - 空 delta chunk
   - [DONE] 无 message_start（边界）

2. **StreamingForwarder** 集成测试：
   - Mock 上游返回标准 OpenAI SSE → 验证输出为 Anthropic SSE
   - Mock 上游返回非 2xx → 验证错误响应
   - Mock 上游流中断 → 验证 message_stop 补发

### 手动测试

1. 配置 Claude Code 指向代理：
   ```bash
   export ANTHROPIC_BASE_URL=http://localhost:1897
   export ANTHROPIC_AUTH_TOKEN=<任意值>
   export ANTHROPIC_MODEL=glm-5.2
   claude
   ```

2. 验证 Claude Code 启动无报错
3. 验证对话流式输出正常
4. 验证工具调用（文件读写、终端命令）正常
5. 验证长文本生成不超时

---

## 实现优先级

1. **P0 — 核心流式转换**：ProtocolConverter SSE 转换 + StreamingForwarder + ProxyServer 接入
2. **P1 — 错误处理**：上游非 2xx 错误缓冲和重试
3. **P2 — 工具调用支持**：tool_calls chunk 聚合和转换
4. **P3 — 思考内容支持**：reasoning_content → thinking 转换

---

## 风险评估

| 风险 | 影响 | 缓解 |
|------|------|------|
| Swifter socket 写入阻塞 | 流式写入可能被 Swifter 的连接管理中断 | 使用独立的 write 循环，确保 socket 不被提前关闭 |
| URLSession delegate 线程安全 | 回调可能在不同线程 | 使用 actor 或 dispatch queue 同步 |
| 上游 API 格式不一致 | 不同 provider 的 OpenAI SSE 格式可能有差异 | 做好容错，未知字段忽略 |
| Claude Code 版本兼容性 | 未来 Claude Code 可能改变 SSE 解析逻辑 | 严格遵循 Anthropic 官方 SSE 规范 |
