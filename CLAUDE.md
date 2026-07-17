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
- Core proxy, routing, protocol conversion, keychain storage, import/export, and persistence are implemented.
- Onboarding requires a successful connection test and at least one enabled model before a channel can be added.
- Channels can be disabled without deletion; this state is persisted and excluded from routing and model aggregation.
- The app is XcodeGen-first. `project.yml` is authoritative; generated `.xcodeproj` and `.xcworkspace` files are not source files.
- Release builds use static CocoaPods linkage, whole-module optimization, dead-code stripping, and Developer ID signing. CI builds and tests use Debug because unit tests use `@testable import`.
- Usage tracking records requests, input tokens, output tokens, and estimated cost. Prefer exact upstream usage; only estimate tokens for successful responses that omit usage. Do not estimate tokens for failed upstream responses.
- Channels Tab shows runtime circuit-breaker state in each channel row. Keep `ChannelRowView` fed by `CircuitBreaker` snapshots when changing channel list rendering.
- About > Report Issue can open GitHub issue creation and optionally export a redacted diagnostics file. Keep log export redaction conservative around API keys, tokens, and authorization headers.

## Architecture

### Composition Root

`AppServices` is the application composition root and the only application-wide singleton. `AppDelegate` owns `AppServices.shared`, starts the proxy, and creates the menu bar manager. SwiftUI views receive `AppServices` explicitly; their `services ?? .shared` initializers are compatibility defaults for the Settings scene and previews, not a reason to reach for lower-level services.

```text
AppDelegate / SwiftUI scene
          |
          v
    AppServices (composition root)
       |                    |
       v                    v
ChannelServices        RouterServices
       |                    |
       v                    v
ChannelStore         SmartRouter / ProxyServer
KeychainManager      ModelAggregator / ModelSwitcher
CooldownEngine       CircuitBreaker / SwitchLock / UsageTracker
```

### Channel Domain

- `ChannelStore` owns observable channels, the active channel, persistence, and the runtime snapshot used by request handling.
- `ChannelServices` is the channel-domain boundary for CRUD, API-key lookup, enabled-channel filtering, and cooldown queries.
- `KeychainManager` stores every API key in one Keychain item as a JSON dictionary keyed by channel ID. Do not create one Keychain item per key.
- `ChannelsPersistence` is the durable file source of truth; `UserDefaults` is a cache and migration fallback.
- `ChannelManager` handles provider metadata, model fetch/test operations, and connection tests. `ChannelExportService` owns encrypted import/export.

### Routing And Proxy Domain

- `RouterServices` groups only dependencies used during proxy request handling.
- `RouterRuntimeState` exposes a thread-safe channel snapshot to non-main-actor HTTP handlers. Do not read SwiftUI state directly from Swifter callbacks.
- `ProxyServer` maps local endpoints to focused endpoint handlers. `ModelEndpointHandler` serves aggregated `/v1/models`; forwarding handlers preserve the client-facing protocol while converting upstream requests and responses where needed.
- `SmartRouter` makes model-first routing decisions. It considers only enabled, healthy channels and uses `CircuitBreaker`, `CooldownEngine`, and `SwitchLock` for failover coordination.
- `ModelAggregator` caches the deduplicated enabled-model set. `ChannelStore` invalidates that cache after channel/model changes.
- `UsageTracker` is the persisted request/usage store. Request forwarding and streaming forwarding should pass exact usage when available, and fall back to conservative local estimates only after a successful response body or stream has actually been written.

### Singleton Policy

- New production code must receive dependencies through `AppServices`, `ChannelServices`, `RouterServices`, or an initializer. Do not add new `shared` properties.
- `ChannelServices`, `RouterServices`, stores, and all runtime services are constructed explicitly. Tests must use isolated factory helpers and must never replace process-wide service state.
- `AppServices.shared` is acceptable at app/scene boundaries. `NSWorkspace.shared`, `URLSession.shared`, and framework-owned singletons are platform APIs, not app service locators.

## Technical Decisions (ADR)
1. **Shell Config Path**: Use `~/.zshenv` (not `.zshrc`) for non-interactive shell compatibility.
2. **Color Management**: `Assets.xcassets` + SwiftGen generated code (`Asset.xxx.swiftUIColor`). Dark Mode supported via System Reference Colors.
3. **Project Files**: `xcodeproj/` and `xcworkspace/` are `.gitignore`d. XcodeGen is the source of truth.
4. **Static Linking**: `use_frameworks! :linkage => :static` enabled. Sparkle remains dynamic (contains Updater.app).
5. **Protocol Consistency**: The client-facing protocol must remain unchanged. Cross-protocol upstream routing is allowed only when `ProtocolConverter` converts both the request and response back to the client's protocol.
6. **Build Order**: `xcodegen generate` BEFORE `bundle exec pod install`.
7. **Generated Code**: `Sources/Generated/` (L10n.swift, Assets+Generated.swift) committed to repo for fresh-clone builds.

## Pending Tasks
- Expand isolated unit tests around configuration-file writers, usage persistence and estimation, channel/model aggregation, and endpoint-handler fallback paths.
- Keep new services explicit and extend isolated tests at storage, network, and filesystem boundaries.
- Evaluate shell configuration UX only if both interactive and non-interactive shell support is required; `.zshenv` remains the default for non-interactive clients.

## Key Files
- Sources/Views/Onboarding/OnboardingView.swift — First-launch wizard (4 steps)
- Sources/Views/Onboarding/AddChannelView.swift — Channel add/edit form
- Sources/Views/MenuView.swift — Menu bar (rewritten)
- Sources/Views/SettingsView.swift — Settings with 5 tabs (rewritten)
- Sources/Services/AppServices.swift — Composition root and dependency wiring
- Sources/Services/ChannelServices.swift — Channel-domain boundary
- Sources/Services/RouterServices.swift — Routing/proxy dependency boundary
- Sources/Services/ChannelStore.swift — Channel persistence and enabled-channel source
- Sources/Services/ChannelManager.swift — Provider metadata, model fetch, and connection testing
- Sources/Services/ProxyServer.swift — Local HTTP routes and endpoint handlers
- Sources/Services/SmartRouter.swift — Model-first routing and retry decisions
- Sources/Services/ShellConfigManager.swift — `.zshenv` configuration (auto-proxy setup)

## Design System (DESIGN.md)
- Menu: 304pt wide, 12pt padding. Recent requests are grouped by model and should show latest status plus compact input/output token totals.
- Settings: 560×420pt window
- **Colors (Light/Dark)**:
  - Backgrounds: `#FFFFFF` / `#1C1C1E` (bgPrimary), `#F2F2F7` / `#2C2C2E` (bgSecondary)
  - Text: `#000000` / `#FFFFFF` (primary), `#6E6E73` / `#8E8E93` (secondary)
  - Accent: `#007AFF` / `#2684FF` (accent), `#0062CC` / `#2684FF` (hover)
  - Status: `#00C853`/`#00E676` (online), `#FF5252`/`#FF6E6E` (offline), `#FFB300`/`#FFC107` (warning)
  - HoverFill: `rgba(0,0,0,6%)` / `rgba(255,255,255,8%)`
  - Border: `rgba(0,0,0,20%)` / `rgba(255,255,255,30%)`
- All colors via `DesignToken.Colors.xxx` — NEVER hardcode hex in Swift code
- Spacing: 4pt base unit (xs=4, sm=8, md=12, lg=16, xl=24)
- All interactive elements need hover states (0.15s ease-in)
- Status indicators with pulse animation

## Testing
- Unit tests are in `Tests/Unit`; use isolated `UserDefaults`, temporary persistence URLs, and `KeychainManagerTestSupport` for all storage tests. Never exercise the production Keychain from tests.
- `ChannelStoreTestSupport` and `KeychainManagerTestSupport` create isolated dependencies. New tests should construct dependencies explicitly and avoid global state.
- For usage tests, cover both exact provider usage and missing-usage fallback. Failed responses should stay at zero tokens.
- UI tests are in `Tests/UI` and depend on `ACCESSIBILITY_IDS.md`. Add identifiers with every new interactive control.
- Run the Debug test configuration locally and in CI:
  ```bash
  xcodebuild test -workspace SmartLLMRouter.xcworkspace -scheme SmartLLMRouter \
    -configuration Debug -destination 'platform=macOS' \
    -only-testing:SmartLLMRouterTests
  ```
