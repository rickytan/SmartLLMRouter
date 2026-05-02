import Foundation
import SwiftUI

class AppState: ObservableObject {
    static let shared = AppState()
    
    @Published var isAutoFailover: Bool = false
    @Published var channels: [Channel] = []
    @Published var stats: UsageStats = UsageStats()
    
    private init() {}
}

struct UsageStats {
    var totalTokens: Int = 0
    var estimatedCost: Double = 0.0
}
