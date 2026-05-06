# SmartLLMRouter — Design System

> macOS native menu bar app. Compact, precise, and polished. Follows Apple HIG where it makes sense, adds visual personality where it doesn't.

---

## 1. Color System

### Background Colors

| Token | Light Mode | Dark Mode | Usage |
|-------|-----------|-----------|-------|
| `bgPrimary` | `#FFFFFF` | `#1C1C1E` | Window/menu backgrounds |
| `bgSecondary` | `#F2F2F7` | `#2C2C2E` | Cards, grouped rows |
| `bgTertiary` | `rgba(0,0,0,0.06)` | `rgba(255,255,255,0.08)` | Hover fill, subtle overlays |

### Text Colors

| Token | Light Mode | Dark Mode | Usage |
|-------|-----------|-----------|-------|
| `textPrimary` | `#000000` | `#FFFFFF` | Headings, labels, values |
| `textSecondary` | `#6E6E73` | `#8E8E93` | Subtitles, URLs, metadata |
| `textTertiary` | `#AEAEB2` | `#636366` | Placeholders, empty state |
| `buttonLabel` | `#FFFFFF` | `#FFFFFF` | Primary button text |

### Accent Colors

| Token | Light Mode | Dark Mode | Usage |
|-------|-----------|-----------|-------|
| `accent` | `#007AFF` | `#2684FF` | Primary actions, links, active states |
| `accentHover` | `#0062CC` | `#2684FF` | Button hover background |

### Status Colors (never change with theme)

| Token | Hex | Usage |
|-------|-----|-------|
| `statusOnline` | `#00C853` / Dark: `#00E676` | Proxy running, channel active |
| `statusOffline` | `#FF5252` / Dark: `#FF6E6E` | Proxy stopped, channel down |
| `statusWarning` | `#FFB300` / Dark: `#FFC107` | Cooling down, rate limited |

### Borders & Dividers

| Token | Light Mode | Dark Mode | Usage |
|-------|-----------|-----------|-------|
| `border` | `rgba(0,0,0,0.20)` | `rgba(255,255,255,0.30)` | Dividers, card borders |

### Latency Indicators

| Range | Color | Emoji | Label |
|-------|-------|-------|-------|
| < 300ms | `#00C853` | 🟢 | Fast |
| 300–800ms | `#FFB300` | 🟡 | Normal |
| > 800ms | `#FF5252` | 🔴 | Slow |

---

## 2. Typography

All use `.systemFont` — **never custom fonts**. macOS San Francisco renders perfectly at every weight.

### Hierarchy

| Level | Size | Weight | Line Height | Usage |
|-------|------|--------|-------------|-------|
| `H1` | 20 | `.bold` | 28 | Settings window title, About header |
| `H2` | 15 | `.semibold` | 20 | Section headers, tab titles |
| `H3` | 13 | `.semibold` | 18 | Card titles, channel names |
| `Body` | 13 | `.regular` | 18 | Labels, descriptions |
| `Caption` | 11 | `.regular` | 15 | URLs, metadata, helper text |
| `Micro` | 10 | `.medium` | 13 | Token counts, timestamps, badges |
| `Value` | 24 | `.bold` | 32 | Stat numbers (Usage tab) |
| `Mono` | 12 | `.regular` | 16 | Port numbers, API keys (truncated) |

### Text Rules

- **No hardcoded strings** — always `L10n.xxx`
- **Line limits**: URLs `.lineLimit(1)`, model lists `.lineLimit(1)`, descriptions `.lineLimit(2)`
- **Truncation**: `.truncationMode(.tail)` for URLs and model identifiers
- **Monospace**: Port numbers, keys → `.font(.system(.caption, design: .monospaced))`

---

## 3. Spacing System

**Base unit: 4pt.** All spacing values are multiples of 4.

| Token | Value | Usage |
|-------|-------|-------|
| `xs` | 4 | Tight internal padding (badges, tags) |
| `sm` | 8 | Cell padding, icon-to-text gap |
| `md` | 12 | Section spacing, form field gaps |
| `lg` | 16 | Card padding, group margins |
| `xl` | 24 | Window padding, large section gaps |

### Menu Bar Specific

| Element | Width | Padding |
|---------|-------|---------|
| Menu container | 300pt | 12pt all sides |
| Menu row height | 24pt minimum | 8pt vertical |
| Divider margin | — | 4pt top, 4pt bottom |

### Settings Window

| Element | Width | Height | Padding |
|---------|-------|--------|---------|
| Window | 560pt | 420pt | 0 (tabs handle it) |
| Form section | full | auto | 16pt horizontal, 12pt vertical |
| Card grid | equal columns | 72pt | 12pt gap between cards |

---

## 4. Component Library

All components live under `Sources/Components/`. **Every View file must use these components — never inline native `Button()`, `TextField()`, `Toggle()`, etc.** Components encapsulate DesignToken styling, hover animations, dark mode, and accessibility.

### Directory Structure
```
Sources/Components/
├── Buttons/      (5)  PrimaryButton, SecondaryButton, IconButton, HoverButton, BadgeButton
├── Form/         (7)  LabeledTextField, LabeledSecureField, LabeledNumberField, LabeledPicker, FormRow, FormSection, ToggleRow
├── Status/       (5)  StatusIndicatorView, StatusBadge, LatencyChip, EmptyStateView, LoadingView
├── List/         (6)  SearchBar, ListItem, ChannelRowView, EmptyChannelView, ProviderRow, ProviderListItem
├── Cards/        (3)  ProviderCard, StatCard, InfoCard
└── Protocol/     (1)  ProtocolSelector
```

---

### 4.1 Buttons

#### PrimaryButton
```swift
PrimaryButton("Save", icon: "checkmark", isLoading: false, isDisabled: false) { action }
```
**用途**: 主要操作（保存、确认、下一步）。填充式蓝色按钮，白色文字。
**样式**:
- 背景：`accent` → hover 时 `accentHover`
- 文字：`buttonLabel`（纯白）
- 圆角：6pt，最小高度 28pt
- 加载态：显示 `ProgressView` spinner 替代图标
- 禁用态：`.opacity(0.4)`，无 hover 响应
- 按下反馈：scale 0.98

#### SecondaryButton
```swift
SecondaryButton("Cancel", icon: "xmark", isDisabled: false) { action }
```
**用途**: 次要操作（取消、返回、跳过）。描边按钮，透明背景。
**样式**:
- 边框：`accent` 1pt
- 文字：`accent`
- hover 时背景变为 `accent.opacity(0.1)`，文字不变色
- 按下反馈：scale 0.98

#### IconButton
```swift
IconButton("trash", tooltip: "Delete") { action }
```
**用途**: 纯图标操作（删除、设置、编辑）。28×28pt 方形按钮。
**样式**:
- 默认：透明背景，`textSecondary` 图标
- hover：`hoverFill` 圆角背景，`textPrimary` 图标
- 禁用态：`textTertiary` 图标，无 hover

#### HoverButton
```swift
HoverButton("DeepSeek", subtitle: "api.deepseek.com", icon: "sparkle") { action }
```
**用途**: 列表项中的可点击行（模型切换、厂商选择）。标题 + 副标题 + 图标。
**样式**:
- 默认：透明背景
- hover：`hoverFill` 圆角背景
- 选中态（isSelected）：`accent.opacity(0.1)` + 左侧 `accent` 1pt 边框
- 标题：`body()` font，`textPrimary`
- 副标题：`caption()` font，`textSecondary`

#### BadgeButton
```swift
BadgeButton("+") { action }
```
**用途**: 小型内联操作（添加标签、快速操作）。胶囊形状。
**样式**:
- 圆角：14pt（完全圆角胶囊）
- 背景：`hoverFill` → hover 时 `accent.opacity(0.2)`
- 文字：`textSecondary` → hover 时 `accent`
- 尺寸：自适应内容，padding 8pt 水平

---

### 4.2 Form Components

#### LabeledTextField
```swift
LabeledTextField("Name", placeholder: "My Channel", text: $name)
```
**用途**: 带 label 的文本输入。label 在输入框上方。
**样式**:
- Label：`caption()` font，`textSecondary` 颜色
- 输入框：`.textFieldStyle(.roundedBorder)`，`body()` font
- 间距：label 与输入框之间 `xs` (4pt)

#### LabeledSecureField
```swift
LabeledSecureField("API Key", placeholder: "sk-...", text: $apiKey)
```
**用途**: 密码/API Key 输入。与 LabeledTextField 同样式，内部为 `SecureField`。

#### LabeledNumberField
```swift
LabeledNumberField("Port", placeholder: "1897", value: $port)
```
**用途**: 数字输入。内置 `NumberFormatter`（0–65535 范围）。
**样式**: 同 LabeledTextField。

#### LabeledPicker
```swift
LabeledPicker("Protocol", selection: $protocol) {
    Text("OpenAI").tag("openai")
    Text("Anthropic").tag("anthropic")
}
```
**用途**: 带 label 的选择器。label 在上方，Picker 在下方。
**样式**:
- Label：`caption()` font，`textSecondary`
- Picker：`.pickerStyle(.inline)`

#### ToggleRow
```swift
ToggleRow("Auto-Failover", subtitle: "Auto-switch on failure", isOn: $failover)
```
**用途**: 水平排列的开关。左侧标题（可选副标题），右侧 Toggle。
**样式**:
- 标题：`body()` font，`textPrimary`
- 副标题：`caption()` font，`textSecondary`
- hover 时：`hoverFill` 背景，圆角 4pt
- 间距：md (12pt) 水平，xs (4pt) 垂直

#### FormRow
```swift
FormRow("Port") {
    TextField("", value: $port, formatter: NumberFormatter())
}
```
**用途**: 通用 label + content 水平排列容器。label 固定宽度 100pt 右对齐。
**样式**:
- Label：`body()` font，右对齐
- Content：左侧 padding sm (8pt)，自适应宽度

#### FormSection
```swift
FormSection("Service") {
    PrimaryButton("Start", icon: "play.fill") { ... }
    LabeledNumberField("Port", value: $port)
}
```
**用途**: 分组容器。可选标题，内容区带背景。
**样式**:
- 标题：`h3()` font，`textPrimary`，底部 sm (8pt) 间距
- 内容区：lg (16pt) 内边距，`bgSecondary` 背景，圆角 10pt

---

### 4.3 Status Components

#### StatusIndicatorView
**用途**: 🟢/🔴 状态圆点 + 脉冲动画。
**样式**:
- 圆点：8pt，statusOnline/statusOffline
- 脉冲：14pt 半透明覆盖，1.5s 循环动画（仅在线状态）
- 冷却态：慢速脉冲 2s 循环

#### StatusBadge
```swift
StatusBadge(status: .success, text: "Connected")
StatusBadge(status: .failure, text: "Invalid Key")
StatusBadge(status: .warning, text: "Cooldown")
```
**用途**: 连接测试结果标签。圆角胶囊，带图标 + 文字。
**样式**:
- 成功：绿色背景 `statusOnline.opacity(0.12)`，`checkmark.circle.fill`
- 失败：红色背景 `statusOffline.opacity(0.12)`，`xmark.circle.fill`
- 警告：黄色背景 `statusWarning.opacity(0.12)`，`exclamationmark.triangle.fill`
- 文字：`micro()` font (10pt medium)
- 圆角：4pt，padding H:6pt V:2pt

#### LatencyChip
**用途**: 延迟指标。彩色圆点 + ms 数值，单色背景。
**样式**:
- 阈值：<300ms 绿色，300-800ms 黄色，>800ms 红色
- 圆点：6pt，背景 `latencyColor.opacity(0.12)`
- 文字：`micro()` font, `.monospaced` design
- 圆角：4pt

#### EmptyStateView
**用途**: 空数据占位。居中图标 + 标题 + 描述。
**布局**:
```
┌─────────────────────────┐
│                         │
│         📡              │  SF Symbol, 56pt, textSecondary
│                         │
│   No channels configured│  H2, textPrimary
│   Add one to start      │  Caption, textSecondary
│                         │
└─────────────────────────┘
```

#### LoadingView
**用途**: 加载进度指示。ProgressView + 可选文字。
**样式**:
- 居中排列
- 文字：`body()` font，`textSecondary`

---

### 4.4 List Components

#### SearchBar
```swift
SearchBar("Search providers...", text: $query)
```
**用途**: 搜索输入框。左侧放大镜图标，右侧清除按钮。
**样式**:
- 背景：`bgSecondary`
- 图标：`textTertiary`，12pt
- 输入：`body()` font，无边框样式
- 圆角：6pt
- hover 时背景变为 `accent.opacity(0.08)`
- 清除按钮：仅当有文字时显示

#### ListItem
**用途**: 通用列表行。hover 背景，左右 padding，底部细线分隔。
**样式**:
- padding：horizontal sm (8pt), vertical xs (4pt)
- hover：`hoverFill` 背景
- 分隔线：`border` 颜色，底部 0.5pt

#### ChannelRowView
**布局**:
```
[●] DeepSeek (OpenAI)           142ms 🟢  [⚡] [⚙️] [×]
    api.deepseek.com
    deepseek-chat, deepseek-v3
```
**用途**: 通道列表行。状态圆点 + 名称 + 延迟 + 操作按钮。
**样式**:
- 名称：`h3()` font，`textPrimary`
- URL/模型：`caption()` font，`textSecondary`
- 延迟：`LatencyChip`
- 操作按钮：hover 时显示（`IconButton`）
- hover 背景：`hoverFill`
- 选中态：`accent.opacity(0.1)` + 左侧 `accent` 1pt 边框

#### EmptyChannelView
**用途**: 通道列表为空时的提示。图标 + 标题 + 操作按钮。
**布局**: 居中显示，引导用户添加 Channel。

#### ProviderRow
```swift
ProviderRow(id: "openai", name: "OpenAI", icon: "sparkle", isSelected: false, isCustom: false) { action }
```
**用途**: AddChannel 表单中的厂商选择行。图标 + 名称 + 选中标记。
**样式**:
- 图标：16pt，选中时 `accent`，否则 `textSecondary`
- 名称：`caption()` font，选中时 `textPrimary`，否则 `textSecondary`
- 选中态：背景 `accent.opacity(0.12)` + 右侧 `checkmark` 标记
- hover 态：`hoverFill` 背景
- 圆角：4pt

#### ProviderListItem
```swift
ProviderListItem(id: "custom", name: "Custom / Local", icon: "globe", isSelected: true) { action }
```
**用途**: Onboarding 引导页中的厂商选择行。与 ProviderRow 视觉一致。
**样式**: 同 ProviderRow。

---

### 4.5 Card Components

#### ProviderCard
**用途**: 厂商选择网格中的卡片。图标 + 名称，选中高亮。
**样式**:
- 圆角：10pt
- 选中态：`accent.opacity(0.1)` 背景 + `accent` 边框
- hover 态：`hoverFill` 背景
- 图标：16pt SF Symbol
- 名称：`caption()` font

#### StatCard
**布局**:
```
┌─────────────────────┐
│     12.4K           │  Value (24pt bold, textPrimary)
│   Today's Tokens    │  Label (11pt secondary)
│   ▲ 12% vs avg      │  Delta (10pt, statusOnline)
└─────────────────────┘
```
**用途**: 统计数据卡片。大数字 + 标签 + 变化趋势。
**样式**:
- 背景：`bgSecondary`
- 圆角：10pt，padding 16pt
- 数值：`value()` font (24pt bold)
- 标签：`caption()` font，`textSecondary`

#### InfoCard
**用途**: 信息提示卡片。图标 + 文字，可选关闭按钮。
**样式**:
- 背景：`bgSecondary`
- 圆角：10pt
- 图标：`featureIconSize` (14pt)
- 文字：`caption()` font

---

### 4.6 Protocol Components

#### ProtocolSelector
```swift
ProtocolSelector(selectedProtocol: $protocol, supportedProtocols: ["openai", "anthropic"]) { newProtocol in
    // protocol changed
}
```
**用途**: OpenAI / Anthropic 协议切换芯片组。
**样式**:
- 芯片按钮：圆角 6pt，选中时 `accent` 填充 + `buttonLabel` 文字
- 未选中：`hoverFill` 背景，`textSecondary` 文字
- hover 时文字变为 `accent`
- 单协议厂商时隐藏选择器

---

## 5. Interaction Patterns

### Hover Effects

**Everything clickable MUST have a hover state.** No exceptions.

```swift
.onHover { hovering in
    withAnimation(.easeInOut(duration: DesignToken.Animation.hoverDuration)) {
        self.isHovered = hovering
    }
}
.background(isHovered ? DesignToken.Colors.hoverFill : Color.clear)
```

- **Duration**: 0.15s (snappy, not sluggish)
- **Easing**: `.easeInOut`
- **Hover fill**: `DesignToken.Colors.hoverFill` — auto-adapts: `rgba(0,0,0,0.06)` light / `rgba(255,255,255,0.08)` dark
- **Button hover**: Solid accent color fill + white text (full transition)

### Click Feedback

```swift
.scaleEffect(pressed ? 0.98 : 1.0)
.animation(.easeInOut(duration: 0.1), value: pressed)
.onTapGesture { withAnimation { pressed = true } }
```

- All buttons: scale to 0.98 on press
- Duration: 0.1s (instant feel)
- Return to 1.0 immediately on release

### Loading States

- **Channel list**: No skeleton, just show what's available
- **Speed test**: Inline spinner per channel, disable other actions
- **Fetch models**: Spinner in model picker, disable confirm button
- **Test connection**: Spinner replaces ⚡ icon, reverts to result

### Transitions

| Action | Transition | Duration |
|--------|-----------|----------|
| Settings window open | `.move(edge: .bottom)` + fade | 0.3s |
| Channel add/remove | `.opacity` + `.scale` | 0.2s |
| Tab switch | Crossfade | 0.15s |
| Menu open | Native (no override) | — |
| Onboarding sheet | `.scale` from center + fade | 0.3s |

---

## 6. Layout Patterns

### 6.1 Menu Bar Menu (300pt wide)

```
┌──────────────────────────────┐
│ ● Running        :1897       │  H3, status + port right-aligned
│                              │
│ ─────────────────────────── │  Divider
│                              │
│  12 requests · 8.4K tokens   │  Caption, secondary, centered
│                              │
│ ─────────────────────────── │
│                              │
│  ◉ Auto Failover      [ON]  │  Full-width toggle row
│                              │
│ ─────────────────────────── │
│                              │
│  Active: DeepSeek GPT-4      │  H3 + URL below
│  api.deepseek.com            │
│                              │
│ ─────────────────────────── │
│                              │
│  Recent Requests             │  H3 section header
│  gpt-4o  ·  2m ago  ·  ✓    │  Micro, truncated, last 5
│  claude  ·  5m ago  ·  ✗    │
│                              │
│ ─────────────────────────── │
│                              │
│  📋 Copy Env Config          │  Full-width button, hover effect
│  🔌 Test Active Key          │
│                              │
│ ─────────────────────────── │
│                              │
│  ⚙️ Settings         Quit    │  HStack, space-between
│                              │
└──────────────────────────────┘
```

**Rules:**
- Every section separated by `Divider()`
- No more than 7 sections (avoids scrolling)
- Buttons are full-width with icon prefix
- Status dot always first element

### 6.2 Settings Window (560 × 420pt)

#### General Tab
```
┌────────────────────────────────────────────┐
│                                            │
│  Service                                   │  H2
│                                            │
│  [▶️ Start Service] / [⏹️ Stop Service]    │  PrimaryButton, full-width
│  ● Running on port 1897                    │  Status line below button
│                                            │
│  Port          [1897          ]            │  LabeledNumberField
│  [ ] Launch at Login                       │  ToggleRow
│                                            │
│  ────────────────────────────────────────  │
│                                            │
│  Shell Environment                         │  H2
│                                            │
│  [⚙️ Auto-Configure Shell]                 │  SecondaryButton
│  Variables already added to ~/.zshenv  ✓   │  StatusBadge(.success)
│                                            │
└────────────────────────────────────────────┘
```

#### Channels Tab
```
┌────────────────────────────────────────────┐
│  [⚡ Test All]                    [+ Add]  │  Toolbar: HoverButton + IconButton
│                                            │
│  ┌──────────────────────────────────────┐ │
│  │● DeepSeek                  142ms 🟢│ │  ChannelRowView, hover bg
│  │  api.deepseek.com                    │ │
│  │  deepseek-chat, deepseek-coder       │ │
│  └──────────────────────────────────────┘ │
│  ┌──────────────────────────────────────┐ │
│  │● OpenAI                    389ms 🟡│ │  ChannelRowView
│  │  api.openai.com/v1                   │ │
│  │  gpt-4o, gpt-4o-mini                │ │
│  └──────────────────────────────────────┘ │
│                                            │
│  Reorder: drag using ⠿ handle on left     │  Caption, hint
└────────────────────────────────────────────┘
```

---

## 7. Iconography

All icons via **SF Symbols**. Version 4.5+ required (macOS 13 ships with it).

### Primary Icons

| Icon | Size | Weight | Usage |
|------|------|--------|-------|
| `network` | 14 | `.medium` | Menu bar item, app icon |
| `network.slash` | 14 | `.medium` | Stopped state |
| `gearshape` | 14 | `.medium` | Settings button |
| `server.rack` | 14 | `.medium` | Channels tab |
| `slider.horizontal.3` | 14 | `.medium` | Advanced tab |
| `chart.bar.fill` | 14 | `.medium` | Usage tab |
| `info.circle` | 14 | `.medium` | About tab |
| `bolt` | 12 | `.medium` | Speed test button |
| `square.and.arrow.up` | 12 | `.medium` | Copy/Export |
| `checkmark.circle.fill` | 12 | — | Success, verified |
| `xmark.circle.fill` | 12 | — | Error, failed |
| `arrow.clockwise` | 12 | `.medium` | Retry, refresh |
| `ellipsis.circle.fill` | 12 | — | Testing/loading |
| `pencil` | 12 | `.medium` | Edit |
| `trash` | 12 | `.medium` | Delete |
| `line.3.horizontal` | 12 | `.medium` | Drag handle |

### Icon Rules
- **Consistent sizing**: Use `.font(.system(size: N, weight: .medium))` not `.imageScale()`
- **Always pair icon + text** in buttons (except icon-only action buttons in channel rows)
- **No custom icon assets** unless absolutely necessary (SF Symbols covers 99%)

---

## 8. Dark Mode

All colors are defined in `Assets.xcassets` with **Any + Dark Appearance** configurations. Access via `Asset.xxx.swiftUIColor` or `DesignToken.Colors.xxx` — **never hardcode hex values in code**.

### Color Mapping

| Light Mode | Dark Mode | How It Works |
|------------|-----------|-------------|
| `#FFFFFF` → `#1C1C1E` | Backgrounds invert | `bgPrimary` / `bgSecondary` |
| `#000000` → `#FFFFFF` | Text inverts | `textPrimary` |
| `#6E6E73` → `#8E8E93` | Subtle text lightens | `textSecondary` |
| `#007AFF` → `#2684FF` | Accent brightens slightly | `accent` |
| `#00C853` → `#00E676` | Status colors brighten for visibility | `statusOnline` |

### Rules

| Rule | Do | Don't |
|------|---|-------|
| All colors | Use `DesignToken.Colors.xxx` or `Asset.xxx.swiftUIColor` | Hardcode `#FFFFFF` or `Color.white` |
| Hover fill | `DesignToken.Colors.hoverFill` (auto alpha adapts) | `Color.gray.opacity(0.08)` |
| Status colors | Use token (auto dark variant) | Adjust hex manually for theme |
| Borders | `DesignToken.Colors.border` (auto alpha adapts) | `Color(NSColor.separatorColor)` |

### Testing Dark Mode

```swift
// In #Preview:
#Preview("Dark Mode") {
    SomeView()
        .preferredColorScheme(.dark)
}

// Or toggle in Simulator/running app:
// System Settings → Appearance → Dark
```

---

## 9. Accessibility

| Rule | Value |
|------|-------|
| Minimum button size | 22 × 22pt |
| Minimum touch target | 28 × 28pt |
| Minimum text size | 10pt (micro) |
| Contrast ratio | ≥ 4.5:1 for text (WCAG AA) |
| Focus rings | Never suppress `.focusRingStyle()` |
| VoiceOver | `.accessibilityLabel()` on icon-only buttons |

---

## 10. SwiftUI View Architecture

### File Structure

```
Sources/
├── Components/                    # 27 reusable design-token components
│   ├── Buttons/                   (5) PrimaryButton, SecondaryButton, IconButton, HoverButton, BadgeButton
│   ├── Form/                      (7) LabeledTextField, LabeledSecureField, LabeledNumberField,
│   │                               LabeledPicker, FormRow, FormSection, ToggleRow
│   ├── Status/                    (5) StatusIndicatorView, StatusBadge, LatencyChip,
│   │                               EmptyStateView, LoadingView
│   ├── List/                      (6) SearchBar, ListItem, ChannelRowView,
│   │                               EmptyChannelView, ProviderRow, ProviderListItem
│   ├── Cards/                     (3) ProviderCard, StatCard, InfoCard
│   └── Protocol/                  (1) ProtocolSelector
├── Views/                         # Page-level views (use Components only)
│   ├── MenuView.swift             # Menu bar content (300pt)
│   ├── SettingsView.swift         # Settings TabView (560×420pt)
│   └── Onboarding/
│       ├── OnboardingView.swift   # First-launch wizard (4 steps)
│       └── AddChannelView.swift   # Channel add/edit (split-pane)
├── Models/
├── Services/
└── Utilities/
```

### View Rules

1. **Extract subviews** when a `body` exceeds 30 lines
2. **No business logic in Views** — all state in ObservableObjects
3. **Use `@Observable`** (Swift 5.9+ Observation framework) instead of `@ObservableObject`
4. **Single responsibility**: Each view does one thing well
5. **`#Preview` on every View** — enables live preview
6. **Extract Components** when reused in 2+ places (StatusIndicator, ActionButton, etc.)

---

## 11. Anti-Patterns (DON'T do these)

```swift
// ❌ Hardcoded colors
.foregroundColor(.blue)          // ✅ Use semantic: DesignToken.Colors.accent

// ❌ Native controls in Views — use custom components
Button("Save") { ... }           // ✅ PrimaryButton("Save") { ... }
TextField("", text: $name)       // ✅ LabeledTextField("Name", text: $name)
Toggle(isOn: $val) { ... }       // ✅ ToggleRow("Label", isOn: $val)

// ❌ Magic numbers
.padding(7)                       // ✅ Use spacing tokens: .padding(.sm)
.frame(width: 287)               // ✅ Round to system: .frame(width: 280)

// ❌ Empty button handlers
Button { /* TODO */ } { ... }    // ✅ Implement or don't show

// ❌ .constant() bindings
Toggle(isOn: .constant(true))    // ✅ Bind to real state

// ❌ Inline complex logic in body
Text(usage.requests > 0 ? "\(usage.requests) requests" : "No requests")
// ✅ Extract to computed property or ViewModifier

// ❌ Nested conditionals in body
if x { if y { ... } }           // ✅ Use @ViewBuilder or extract subview

// ❌ Ignoring safe area without reason
.ignoresSafeArea()               // ✅ Only for full-bleed backgrounds

// ❌ Fixed heights on text
.frame(height: 20)               // ✅ Let text size itself naturally
```

---

## 12. Checklist Before Committing UI Changes

- [ ] All text uses `L10n.xxx` (no hardcoded strings)
- [ ] All colors use `DesignToken.Colors.xxx` (no `.white`/`.black`/hex literals)
- [ ] No native `Button()`, `TextField()`, `SecureField()`, `Toggle()`, `Picker()` in View files — use Components
- [ ] All interactive elements have hover states (0.15s ease-in)
- [ ] All buttons have press feedback (`.scaleEffect(0.98)`)
- [ ] Spacing uses 4pt multiples (`DesignToken.Spacing.xs/sm/md/lg/xl`)
- [ ] Dark mode renders correctly (check `#Preview("Dark Mode")`)
- [ ] `#Preview` block exists and renders correctly
- [ ] No `print()` statements — use `Log.xxx`
- [ ] No empty `// TODO` button handlers
- [ ] No `.constant(true)` bindings
- [ ] View file < 250 lines (extract subviews if longer)
