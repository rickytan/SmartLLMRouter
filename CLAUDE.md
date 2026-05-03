# SmartLLMRouter — Claude Code Context

## Project Rules
- **NEVER ask for permission** — just execute commands
- **NEVER ask questions** — make reasonable decisions yourself
- **Always read requirements.md first** before making changes
- **Read DESIGN.md** for visual design system (colors, spacing, typography, components)
- **Read ACCESSIBILITY_IDS.md** for all accessibilityIdentifier values
- **Use CocoaPods** for dependencies (`bundle exec pod install` with Ruby 3.1)
- **macOS 13.0+, Swift 5.9+, SwiftUI**
- **Zero hardcoded strings** — use `L10n.xxx` for all UI text
- **API Keys via KeychainManager only** — never plaintext
- **SwiftFormat warning**: Current version may aggressively delete `self` in closures and `Log.` prefixes. Check build after formatting.
- **Protocol Consistency (CRITICAL)**:
  - When routing or switching models, **NEVER** break the client's protocol expectation.
  - If client sends **Anthropic** protocol, proxy MUST return **Anthropic** protocol response.
  - Routing to *any* backend supporting Anthropic protocol (or convertible to it) is **ALLOWED**.
  - Routing an Anthropic request to a native OpenAI endpoint *without* converting the response back is **FORBIDDEN** (breaks Tool Calling/SSE).

## Build Commands
```bash
# Ruby path (system Ruby 2.6 is too old)
export PATH="/opt/homebrew/Cellar/ruby@3.1/3.1.7_1/bin:$PATH"

# ⚠️ ORDER MATTERS: xcodegen first, then pod install (pod install writes CocoaPods links into the xcodeproj)
xcodegen generate
bundle exec pod install

# Build
xcodebuild -workspace SmartLLMRouter.xcworkspace -scheme SmartLLMRouter -destination 'platform=macOS' build

# Run tests
xcodebuild test -workspace SmartLLMRouter.xcworkspace -scheme SmartLLMRouter -destination 'platform=macOS' -only-testing:SmartLLMRouterTests
```

## Current State
- **Phase 1-2**: ✅ Complete — All core services
- **Phase 3 UI**: ✅ MenuView & SettingsView fully rewritten with DesignTokens
- **Onboarding**: ✅ Integrated, 4-step flow complete
- **Phase 4**: ✅ **COMPLETE** — UsageTab stacked bar chart (grouped by channel), Sparkle auto-update integrated, zero hardcoded visual values across all Views
- **Static Linking**: ✅ `use_frameworks! :linkage => :static` enabled, app size 8.6 MB

## Pending Tasks
- **Phase 5: Unified Model Switcher** (IN PROGRESS)
  - Implement `ModelSwitcher` service to manage active model.
  - Update `MenuView` to allow selecting models from the active channel.
  - Update `RequestForwarder` to replace `model` field in requests.
  - **Strict Protocol Consistency**: Only allow switching models that support the active channel's protocol.
- **UI Test expansion**: Add UITest cases for Onboarding flow, AddChannel CRUD, Settings tabs
- **UsageTracker integration in Proxy**: Ensure `UsageTracker.recordUsage` is called from `RequestForwarder` on every proxied request

## Key Files
- Sources/Views/Onboarding/OnboardingView.swift — First-launch wizard (4 steps)
- Sources/Views/Onboarding/AddChannelView.swift — Channel add/edit form
- Sources/Views/MenuView.swift — Menu bar (rewritten)
- Sources/Views/SettingsView.swift — Settings with 5 tabs (rewritten)
- Sources/Models/AppState.swift — Has onboardingCompleted property
- Sources/Services/ChannelManager.swift — Channel CRUD, speed test, provider templates
- Sources/Services/ShellConfigManager.swift — .zshrc configuration

## Design System (DESIGN.md)
- Menu: 300pt wide, 12pt padding
- Settings: 560×420pt window
- Colors: `#00C853` (online), `#FF5252` (offline), `#FFB300` (warning), `#007AFF` (accent)
- Spacing: 4pt base unit (xs=4, sm=8, md=12, lg=16, xl=24)
- All interactive elements need hover states (0.15s ease-in)
- Status indicators with pulse animation

## Testing
- 8 unit tests passing in SmartLLMRouterTests
- UI Test infrastructure ready in SmartLLMRouterUITests (24 test cases)
- Hermes handles testing — you focus on implementation
