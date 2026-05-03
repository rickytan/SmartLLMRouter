# SmartLLMRouter — Design System

> macOS native menu bar app. Compact, precise, and polished. Follows Apple HIG where it makes sense, adds visual personality where it doesn't.

---

## 1. Color System

### Semantic Colors

| Token | Light Mode | Dark Mode | Usage |
|-------|-----------|-----------|-------|
| `bgPrimary` | `Color(NSColor.windowBackgroundColor)` | same | Window/menu backgrounds |
| `bgSecondary` | `Color(NSColor.controlBackgroundColor)` | same | Cards, grouped rows |
| `bgTertiary` | `Color.gray.opacity(0.08)` | `Color.gray.opacity(0.15)` | Hover states, subtle dividers |
| `textPrimary` | `Color.primary` | same | Headings, labels, values |
| `textSecondary` | `Color.secondary` | same | Subtitles, URLs, metadata |
| `textTertiary` | `Color(NSColor.labelColor).opacity(0.5)` | same | Placeholders, empty state |
| `border` | `Color(NSColor.separatorColor)` | same | Dividers, card borders |

### Status Colors (never change with theme)

| Token | Value | Usage |
|-------|-------|-------|
| `statusOnline` | `Color(#00C853)` | Proxy running, channel active |
| `statusOffline` | `Color(#FF5252)` | Proxy stopped, channel down |
| `statusWarning` | `Color(#FFB300)` | Cooling down, rate limited |
| `statusIdle` | `Color(#9E9E9E)` | No active channel, idle state |

### Latency Indicators

| Range | Color | Emoji | Label |
|-------|-------|-------|-------|
| < 300ms | `#00C853` | 🟢 | Fast |
| 300–800ms | `#FFB300` | 🟡 | Normal |
| > 800ms | `#FF5252` | 🔴 | Slow |
| Timeout/Fail | `#9E9E9E` | ⚫ | Unreachable |

### Accent

| Token | Light | Dark | Usage |
|-------|-------|------|-------|
| `accent` | `Color(#007AFF)` | same | Primary actions, links, active states |
| `accentHover` | `Color(#0062CC)` | `Color(#2684FF)` | Button hover background |

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

## 4. Component Patterns

### 4.1 Status Indicator

```swift
Circle()
    .fill(statusColor)
    .frame(width: 8, height: 8)
    .overlay(
        Circle()
            .fill(statusColor.opacity(0.3))
            .frame(width: 14, height: 14)
            .opacity(isRunning ? 0.6 : 0)
            .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: isRunning)
    )
```

- **Running**: Green, pulse animation
- **Stopped**: Red, no animation
- **Cooldown**: Amber, slow pulse (2s cycle)

### 4.2 Channel Row

```
[●] Channel Name          Latency: 142ms  🟢  [⚡] [⚙️] [×]
     api.openai.com/v1
     gpt-4o, gpt-4o-mini
```

- Left-aligned status dot (8pt)
- Name: H3 semibold, truncated at 120pt
- Latency: Micro, color-coded
- Right-aligned actions (hover reveal)
- URL + models: Caption, secondary, below name
- **Hover**: `.background(bgTertiary)` with 0.15s ease-in animation
- **Selected**: `.background(accent.opacity(0.1))` + 1pt accent border leading

### 4.3 Stat Card (Usage tab)

```
┌─────────────────────┐
│     12.4K           │  ← Value (24pt bold)
│   Today's Tokens    │  ← Label (11pt secondary)
│   ▲ 12% vs avg      │  ← Delta (10pt, green/red)
└─────────────────────┘
```

- Card: `bgSecondary`, corner radius 10, no border
- Padding: 16pt
- Delta: show only if data available, ▲/▼ with color

### 4.4 Action Button

```swift
Button { action() } label: {
    HStack(spacing: 6) {
        Image(systemName: icon)
            .font(.system(size: 12, weight: .medium))
        Text(L10n.xxx)
            .font(.system(size: 12, weight: .medium))
    }
    .frame(maxWidth: .infinity, minHeight: 28)
    .background(hovered ? accentHover : Color.clear)
    .foregroundColor(hovered ? .white : accent)
    .cornerRadius(6)
    .onHover { hovering in withAnimation(.easeInOut(duration: 0.15)) { hovered = hovering } }
}
.buttonStyle(.plain)
```

- **Default**: Blue text, transparent bg
- **Hover**: Blue fill, white text
- **Pressed**: Slight scale down (0.98) + darker blue
- **Disabled**: `.opacity(0.4)`, no hover response

### 4.5 Badge / Tag

```swift
Text(label)
    .font(.system(size: 10, weight: .medium))
    .foregroundColor(.white)
    .padding(.horizontal, 6)
    .padding(.vertical, 2)
    .background(color)
    .cornerRadius(4)
```

- Examples: `Priority 1`, `Cooling`, `429`, `5xx`
- Max 2 badges per row
- Colors map to semantic status colors

### 4.6 Latency Chip

```swift
HStack(spacing: 4) {
    Circle().fill(latencyColor).frame(width: 6, height: 6)
    Text("\(ms, specifier: "%.0f")ms")
        .font(.system(size: 10, weight: .medium, design: .monospaced))
}
.padding(.horizontal, 6)
.padding(.vertical, 2)
.background(latencyColor.opacity(0.12))
.cornerRadius(4)
```

### 4.7 Empty State

```
┌─────────────────────────┐
│                         │
│       📡                │  ← SF Symbol, 48pt, secondary
│                         │
│   No channels configured│  ← Body, primary
│   Add one to get started│  ← Caption, secondary
│                         │
│    [+ Add Channel]      │  ← Primary button, centered
│                         │
└─────────────────────────┘
```

### 4.8 Speed Test Progress

```swift
ProgressView(value: completed, total: total)
    .progressViewStyle(.linear)
    .tint(accent)
    .frame(height: 2)
```

- Inline progress above channel list during bulk test
- Per-channel: spinner overlay on ⚡ button during test

---

## 5. Interaction Patterns

### Hover Effects

**Everything clickable MUST have a hover state.** No exceptions.

```swift
.onHover { hovering in
    withAnimation(.easeInOut(duration: 0.15)) {
        self.hovered = hovering
    }
}
.background(hovered ? Color.gray.opacity(0.08) : Color.clear)
```

- **Duration**: 0.15s (snappy, not sluggish)
- **Easing**: `.easeInOut`
- **Hover fill**: `Color.gray.opacity(0.08)` light / `0.15` dark
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
│  [▶️ Start Service] / [⏹️ Stop Service]    │  Primary button, full-width
│  ● Running on port 1897                    │  Status line below button
│                                            │
│  Port          [1897          ]            │  Form row
│  [ ] Launch at Login                       │  Toggle row
│                                            │
│  ────────────────────────────────────────  │
│                                            │
│  Shell Environment                         │  H2
│                                            │
│  [⚙️ Auto-Configure Shell]                 │  Secondary button
│  Variables already added to ~/.zshrc  ✓    │  Success state (green)
│                                            │
└────────────────────────────────────────────┘
```

#### Channels Tab
```
┌────────────────────────────────────────────┐
│  [⚡ Test All]                    [+ Add]  │  Toolbar
│                                            │
│  ┌──────────────────────────────────────┐ │
│  │● DeepSeek                  142ms 🟢│ │  ← hover bg
│  │  api.deepseek.com                    │ │
│  │  deepseek-chat, deepseek-coder       │ │
│  └──────────────────────────────────────┘ │
│  ┌──────────────────────────────────────┐ │
│  │● OpenAI                    389ms 🟡│ │
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

All colors use semantic tokens — **never hardcode `.white` or `.black`**.

| Rule | Do | Don't |
|------|---|-------|
| Text | `Color.primary` / `.secondary` | `.black` / `.gray` |
| Background | `Color(NSColor.windowBackgroundColor)` | `.white` |
| Card bg | `Color(NSColor.controlBackgroundColor)` | `Color(.white)` |
| Borders | `Color(NSColor.separatorColor)` | `Color.gray` |
| Status colors | Keep original hex | Adjust for theme |
| Accent | Keep `#007AFF` | Use different blue |

### Testing Dark Mode

```swift
.preferredColorScheme(.dark)  // Add to #Preview for testing
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
Sources/Views/
├── MenuView.swift              # Main menu bar content
├── SettingsView.swift          # TabView container
├── Tabs/
│   ├── GeneralSettingsTab.swift
│   ├── ChannelsTab.swift
│   ├── AdvancedTab.swift
│   ├── UsageTab.swift
│   └── AboutTab.swift
├── Rows/
│   ├── ChannelRow.swift
│   ├── RequestLogRow.swift
│   └── ModelRow.swift
├── Components/
│   ├── StatusIndicator.swift
│   ├── StatCard.swift
│   ├── LatencyChip.swift
│   ├── ActionButton.swift
│   └── EmptyStateView.swift
└── Onboarding/
    └── OnboardingView.swift
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
.foregroundColor(.blue)          // ✅ Use semantic: .accent

// ❌ Magic numbers
.padding(7)                       // ✅ Use spacing tokens: .padding(.md)
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
- [ ] All colors are semantic (no hardcoded `.white`/`.black`)
- [ ] All interactive elements have hover states
- [ ] All buttons have press feedback (`.scaleEffect`)
- [ ] Spacing uses 4pt multiples
- [ ] Dark mode tested (`.preferredColorScheme(.dark)`)
- [ ] `#Preview` block exists and renders correctly
- [ ] No `print()` statements — use `Log.xxx`
- [ ] No empty `// TODO` button handlers
- [ ] No `.constant(true)` bindings
- [ ] View file < 250 lines (extract if longer)
