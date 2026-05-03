import Foundation

// MARK: - ProviderIconMapper

/// Maps provider IDs to meaningful SF Symbols for UI display
enum ProviderIconMapper {

    /// Returns an SF Symbol name for a given provider ID
    static func symbol(for id: String) -> String {
        switch id {
        case "anthropic":
            return "a.circle.fill"
        case "openai":
            return "o.circle.fill"
        case "google_gemini":
            return "g.circle.fill"
        case "deepseek":
            return "d.circle.fill"
        case "dashscope":
            return "q.circle.fill"  // Qwen
        case "minimax":
            return "m.circle.fill"
        case "moonshot":
            return "moonphase.waxing.gibbous"
        case "zhipu":
            return "z.circle.fill"
        case "mistral":
            return "wind"
        case "groq":
            return "bolt.circle.fill"
        case "together_ai":
            return "arrow.2.circlepath.circle.fill"
        case "cohere":
            return "c.circle.fill"
        case "fireworks":
            return "sparkle"
        case "openrouter":
            return "link.circle.fill"
        case "siliconflow":
            return "cpu.fill"
        case "xiaomi_mimo":
            return "x.circle.fill"
        default:
            return "globe"
        }
    }
}
