# SmartLLMRouter — Claude Code Context

## Project Rules
- **NEVER ask for permission** — just execute commands
- **NEVER ask questions** — make reasonable decisions yourself
- **Always read requirements.md first** before making changes
- **Use CocoaPods** for dependencies (`bundle exec pod install` with Ruby 3.1)
- **macOS 13.0+, Swift 5.9+, SwiftUI**
- **Zero hardcoded strings** — use `L10n.xxx` for all UI text
- **API Keys via KeychainManager only** — never plaintext

## Build Commands
```bash
# Ruby path (system Ruby 2.6 is too old)
export PATH="/opt/homebrew/Cellar/ruby@3.1/3.1.7_1/bin:$PATH"

# Install deps
bundle exec pod install

# Generate project
xcodegen generate

# Build
xcodebuild -workspace SmartLLMRouter.xcworkspace -scheme SmartLLMRouter -destination 'platform=macOS' build
```

## Current State
- 6 CocoaPods installed (no SwiftFormat)
- Logger module implemented (CocoaLumberjack)
- Phase 2 core logic compiles
- Phase 3 partially done (SmartRouter, CooldownEngine, ChannelManager exist)
- Need: Logger migration to all files, Settings UI, Speed Test, Phase 3 completion
