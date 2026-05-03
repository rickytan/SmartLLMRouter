# Accessibility Identifier 规范

> 所有 UI 测试依赖 `accessibilityIdentifier` 定位元素。
> Claude Code 在编写/重构 View 时，**必须**为以下元素添加标识符。

---

## 规则

1. **所有可交互元素**（按钮、开关、输入框、列表项）必须有 `accessibilityIdentifier`
2. **状态指示器**（运行/停止/冷却）必须有标识符
3. **动态列表项**使用 `prefix.index` 格式（如 `channel.row.0`）
4. **互斥元素**（如 running/stopped）两个都要定义，测试会判断哪个存在

---

## MenuView

| 元素 | Identifier | 类型 |
|------|-----------|------|
| 服务状态（运行） | `menu.status.running` | 状态文本/指示器 |
| 服务状态（停止） | `menu.status.stopped` | 状态文本/指示器 |
| 端口号 | `menu.port.label` | 文本 |
| 故障转移开关 | `menu.failover.toggle` | Toggle |
| 活跃频道 | `menu.active.channel` | 文本 |
| 复制环境变量 | `menu.copy环境变量` | 按钮 |
| 测试密钥 | `menu测试密钥` | 按钮 |
| 设置按钮 | `menu.settings` | 按钮 |
| 退出按钮 | `menu.quit` | 按钮 |
| 最近请求 | `menu.recent.requests` | 区域/文本 |

### 示例
```swift
Circle()
    .fill(proxy.isRunning ? Color.green : Color.red)
    .frame(width: 8, height: 8)
    .accessibilityIdentifier(proxy.isRunning ? "menu.status.running" : "menu.status.stopped")

Text(":\(proxy.port)")
    .accessibilityIdentifier("menu.port.label")
```

---

## SettingsView

### Tab 标识
| Tab | Identifier |
|-----|-----------|
| General | `settings.tab.general` |
| Channels | `settings.tab.channels` |
| Advanced | `settings.tab.advanced` |
| Usage | `settings.tab.usage` |
| About | `settings.tab.about` |

### General Tab
| 元素 | Identifier |
|------|-----------|
| 端口输入框 | `settings.general.port` |
| 启动服务按钮 | `settings.general.start` |
| 停止服务按钮 | `settings.general.stop` |
| 开机自启开关 | `settings.general.launchAtLogin` |

### Channels Tab
| 元素 | Identifier |
|------|-----------|
| 添加频道按钮 | `settings.channels.add` |
| 批量测速按钮 | `settings.channels.testAll` |
| 频道列表 | `settings.channels.list` |

### Channel Row（动态）
| 元素 | Identifier 格式 | 示例 |
|------|----------------|------|
| 频道行 | `channel.row.{index}` | `channel.row.0` |
| 频道名称 | `channel.name.{index}` | `channel.name.0` |
| 测速按钮 | `channel.speedtest.{index}` | `channel.speedtest.0` |
| 编辑按钮 | `channel.edit.{index}` | `channel.edit.0` |
| 删除按钮 | `channel.delete.{index}` | `channel.delete.0` |
| 状态指示器 | `channel.status.{index}` | `channel.status.0` |

### Advanced Tab
| 元素 | Identifier |
|------|-----------|
| 故障转移开关 | `settings.advanced.failover` |
| 429 冷却时间 | `settings.advanced.cooldown.429` |
| 5xx 冷却时间 | `settings.advanced.cooldown.5xx` |
| 401 冷却时间 | `settings.advanced.cooldown.401` |

### Usage Tab
| 元素 | Identifier |
|------|-----------|
| 总请求数 | `usage.totalRequests` |
| 总 Token 数 | `usage.totalTokens` |
| 总费用 | `usage.totalCost` |

### About Tab
| 元素 | Identifier |
|------|-----------|
| 版本信息 | `about.version` |
| GitHub 按钮 | `about.github` |

---

## 动态列表实现示例

```swift
// ChannelRow.swift
struct ChannelRow: View {
    let channel: Channel
    let index: Int  // 传入索引
    
    var body: some View {
        HStack {
            StatusIndicator()
                .accessibilityIdentifier("channel.status.\(index)")
            
            Text(channel.name)
                .accessibilityIdentifier("channel.name.\(index)")
            
            Spacer()
            
            Button { testLatency() } label: {
                Image(systemName: "bolt")
            }
            .accessibilityIdentifier("channel.speedtest.\(index)")
            
            Button { editChannel() } label: {
                Image(systemName: "pencil")
            }
            .accessibilityIdentifier("channel.edit.\(index)")
            
            Button { deleteChannel() } label: {
                Image(systemName: "trash")
            }
            .accessibilityIdentifier("channel.delete.\(index)")
        }
        .accessibilityIdentifier("channel.row.\(index)")
    }
}

// ChannelsTab.swift
List {
    ForEach(Array(channelStore.channels.enumerated()), id: \.element.id) { index, channel in
        ChannelRow(channel: channel, index: index)
    }
}
.accessibilityIdentifier("settings.channels.list")
```

---

## 验证

编写 View 后，运行 UI 测试验证覆盖率：
```bash
xcodebuild test -workspace SmartLLMRouter.xcworkspace \
  -scheme SmartLLMRouter \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:SmartLLMRouterUITests/AccessibilityCoverageTests
```

目标：70% 以上标识符覆盖率。
